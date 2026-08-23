extends Node

signal mode_changed(mode: String, message: String)
signal request_started(mode: String)
signal request_finished(result: Dictionary)
signal alert_created(alert: Dictionary)
signal settings_changed(settings: Dictionary)

const SettingsScript := preload("res://ai/ai_settings.gd")
const SanitizerScript := preload("res://ai/ai_sanitizer.gd")
const CacheScript := preload("res://ai/ai_cache.gd")
const ContextScript := preload("res://ai/ai_context_provider.gd")
const LocalAssistantScript := preload("res://ai/local_assistant.gd")
const GeminiClientScript := preload("res://ai/gemini_client.gd")
const MonitorScript := preload("res://ai/ai_system_monitor.gd")

const USAGE_PATH := "user://luna_ai_usage.json"
const HISTORY_PATH := "user://luna_chat_history.json"
const LOG_PATH := "user://luna_ai_logs.jsonl"
const MAX_LOG_BYTES := 524288
const ALLOWED_ACTIONS := [
	"open_inventory",
	"open_maintenance",
	"open_logs",
	"open_settings",
	"open_monitor_4g",
]

var settings: AISettings
var sanitizer: AISanitizer
var cache: AICache
var context_provider: AIContextProvider
var local_assistant: LocalAssistant
var gemini_client: GeminiClient
var system_monitor: AISystemMonitor

var _history: Array[Dictionary] = []
var _usage: Dictionary = {}
var _request_busy := false
var _current_mode := "local"
var _bound_branch := ""


func _ready() -> void:
	settings = SettingsScript.new()
	settings.load_settings()
	sanitizer = SanitizerScript.new()
	cache = CacheScript.new()
	cache.configure(int(settings.get_value("cache_ttl_seconds", 1800)))
	context_provider = ContextScript.new()
	context_provider.setup(settings)
	local_assistant = LocalAssistantScript.new()
	local_assistant.setup(context_provider)
	gemini_client = GeminiClientScript.new()
	add_child(gemini_client)
	system_monitor = MonitorScript.new()
	add_child(system_monitor)
	system_monitor.setup(context_provider, settings)
	system_monitor.alert_created.connect(_on_monitor_alert_created)
	_load_usage()
	_load_history()
	_emit_mode()


func uses_encrypted_secret_vault() -> bool:
	return true


func bind_store(store: Object, branch_id: String, sync_provider: Object = null) -> void:
	_bound_branch = branch_id
	context_provider.bind_store(store, branch_id, sync_provider)
	call_deferred("_run_initial_monitor")


func unbind_store() -> void:
	_bound_branch = ""
	context_provider.unbind_store()


func update_page_context(context: Dictionary) -> void:
	context_provider.update_page_context(context)


func update_runtime_context(context: Dictionary) -> void:
	context_provider.update_runtime_context(context)


func ask(question: String, options: Dictionary = {}) -> Dictionary:
	var started_at := Time.get_ticks_msec()
	if _request_busy:
		return _complete_result({
			"ok": false,
			"mode": _current_mode,
			"error": "busy",
			"text": "A Luna ainda esta processando a mensagem anterior.",
		}, started_at, 0, false)
	_request_busy = true

	var local_result := {
		"handled": false,
		"text": "A IA local esta desativada.",
		"actions": [],
	}
	if bool(settings.get_value("local_ai_enabled", true)):
		local_result = local_assistant.answer(question)

	var force_online := bool(options.get("force_online", false))
	var online_needed := force_online or local_assistant.should_use_online(question, local_result)
	if bool(local_result.get("handled", false)) and not online_needed:
		var local_response := _build_local_response(local_result)
		_record_exchange(question, str(local_response.get("text", "")))
		return _complete_result(local_response, started_at, question.length(), false)

	if not _online_allowed():
		var offline_response := _offline_fallback(local_result)
		_record_exchange(question, str(offline_response.get("text", "")))
		return _complete_result(offline_response, started_at, question.length(), false)

	var sanitized_question := sanitizer.sanitize_text(question, int(settings.get_value("max_prompt_chars", 6000)))
	if bool(sanitized_question.get("blocked", false)):
		var privacy_response := {
			"ok": true,
			"mode": "local",
			"intent": "privacy_protection",
			"text": "Por seguranca, nao enviei esta mensagem para a IA online porque ela parece conter uma credencial. Remova senhas, tokens ou chaves e tente novamente.",
			"actions": [],
			"privacy_blocked": true,
		}
		if bool(local_result.get("handled", false)):
			privacy_response["text"] += "\n\nResposta local: %s" % str(local_result.get("text", ""))
		_record_exchange(question, str(privacy_response.get("text", "")))
		return _complete_result(privacy_response, started_at, int(sanitized_question.get("sanitized_chars", 0)), false)

	var raw_context := context_provider.get_controlled_context(question)
	var safe_context := sanitizer.sanitize_dictionary(raw_context, int(settings.get_value("max_prompt_chars", 6000)))
	var safe_history := sanitizer.sanitize_history(
		_history,
		int(settings.get_value("max_history_messages", 20)),
		int(settings.get_value("max_prompt_chars", 6000))
	)
	var model := str(settings.get_value("model", AISettings.DEFAULT_MODEL))
	var cache_key := cache.make_key(str(sanitized_question.get("text", "")), safe_context, model)
	var cached := cache.get_value(cache_key)
	if bool(cached.get("hit", false)):
		var cached_result: Dictionary = (cached.get("value", {}) as Dictionary).duplicate(true)
		cached_result["cached"] = true
		_record_exchange(question, str(cached_result.get("text", "")))
		return _complete_result(cached_result, started_at, int(sanitized_question.get("sanitized_chars", 0)), true)

	var limit_status := _check_usage_limit()
	if not bool(limit_status.get("ok", false)):
		var limit_response := _offline_fallback(local_result)
		limit_response["error"] = str(limit_status.get("error", "rate_limit"))
		limit_response["text"] = "O limite temporario da IA online foi atingido. A Luna continuara operando no modo local."
		if bool(local_result.get("handled", false)):
			limit_response["text"] += "\n\n%s" % str(local_result.get("text", ""))
		_record_exchange(question, str(limit_response.get("text", "")))
		return _complete_result(limit_response, started_at, int(sanitized_question.get("sanitized_chars", 0)), false)

	_current_mode = "online"
	_emit_mode()
	request_started.emit("online")
	var online_result := await gemini_client.send_message(
		str(sanitized_question.get("text", "")),
		safe_context,
		safe_history,
		str(settings.get_value("gemini_api_key", "")),
		model
	)
	if bool(online_result.get("ok", false)):
		_increment_usage()
		var safe_answer := sanitizer.sanitize_text(str(online_result.get("text", "")), 12000)
		var response := {
			"ok": true,
			"mode": "online",
			"intent": "gemini",
			"text": str(safe_answer.get("text", "")),
			"actions": [],
			"cached": false,
			"model_used": str(online_result.get("model_used", model)),
		}
		cache.put(cache_key, response.duplicate(true))
		_record_exchange(question, str(response.get("text", "")))
		_current_mode = "local"
		_emit_mode()
		return _complete_result(response, started_at, int(sanitized_question.get("sanitized_chars", 0)), false)

	var fallback := _offline_fallback(local_result)
	fallback["error"] = str(online_result.get("error", "online_error"))
	if str(online_result.get("error", "")) == "rate_limit":
		fallback["text"] = "O limite temporario da IA online foi atingido. A Luna continuara operando no modo local."
	else:
		fallback["text"] = "O modo online esta indisponivel no momento. Continuarei ajudando usando os recursos locais do sistema."
	if bool(local_result.get("handled", false)):
		fallback["text"] += "\n\n%s" % str(local_result.get("text", ""))
	_current_mode = "local"
	_emit_mode()
	_record_exchange(question, str(fallback.get("text", "")))
	return _complete_result(fallback, started_at, int(sanitized_question.get("sanitized_chars", 0)), false)


func test_connection() -> Dictionary:
	if _request_busy:
		return {"ok": false, "error": "busy", "message": "A Luna esta ocupada."}
	_request_busy = true
	_current_mode = "online"
	_emit_mode()
	var started_at := Time.get_ticks_msec()
	var result := await gemini_client.test_connection(
		str(settings.get_value("gemini_api_key", "")),
		str(settings.get_value("model", AISettings.DEFAULT_MODEL))
	)
	_request_busy = false
	_current_mode = "local"
	_emit_mode()
	_write_technical_log(
		"connection_test",
		bool(result.get("ok", false)),
		Time.get_ticks_msec() - started_at,
		str(result.get("error", "")),
		0,
		false
	)
	return result


func cancel_online_request() -> void:
	gemini_client.cancel_request()
	_request_busy = false
	_current_mode = "local"
	_emit_mode()


func settings_snapshot() -> Dictionary:
	return settings.get_all(false)


func save_settings(changes: Dictionary) -> bool:
	var saved := settings.save_settings(changes)
	if saved:
		cache.configure(int(settings.get_value("cache_ttl_seconds", 1800)))
		system_monitor.apply_settings()
		if not bool(settings.get_value("save_history_local", false)):
			_remove_history_file()
		settings_changed.emit(settings_snapshot())
		_emit_mode()
	return saved


func clear_api_key() -> bool:
	var result := settings.clear_api_key()
	settings_changed.emit(settings_snapshot())
	_emit_mode()
	return result


func clear_cache() -> void:
	cache.clear()


func clear_history() -> void:
	_history.clear()
	_remove_history_file()


func get_history() -> Array[Dictionary]:
	return _history.duplicate(true)


func get_mode_status() -> Dictionary:
	var key_configured := str(settings.get_value("gemini_api_key", "")).strip_edges() != ""
	var online_enabled := bool(settings.get_value("gemini_enabled", false)) and bool(settings.get_value("allow_online_analysis", false))
	var mode := "local"
	var message := "Luna Local"
	if _current_mode == "online" and _request_busy:
		mode = "online"
		message = "Luna Online - Gemini"
	elif online_enabled and not key_configured:
		mode = "configuration_required"
		message = "Configuracao necessaria"
	elif not bool(settings.get_value("local_ai_enabled", true)):
		mode = "disabled"
		message = "Luna desativada"
	elif online_enabled and key_configured:
		mode = "hybrid"
		message = "Luna Hibrida - Automatico"
	return {
		"mode": mode,
		"message": message,
		"busy": _request_busy,
		"online_enabled": online_enabled,
		"key_configured": key_configured,
		"api_key_source": settings.api_key_source(),
		"cache_entries": cache.size(),
	}


func get_alerts() -> Array[Dictionary]:
	return system_monitor.get_alerts()


func run_monitor_now() -> Array[Dictionary]:
	return system_monitor.run_now()


func dismiss_alert(alert_id: String) -> void:
	system_monitor.dismiss_alert(alert_id)


func safe_actions(actions: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(actions) != TYPE_ARRAY:
		return result
	for item in actions as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var action := item as Dictionary
		if ALLOWED_ACTIONS.has(str(action.get("id", ""))):
			result.append(action.duplicate(true))
	return result


func set_test_transport(transport: Callable) -> void:
	gemini_client.set_test_transport(transport)


func clear_test_transport() -> void:
	gemini_client.clear_test_transport()


func _online_allowed() -> bool:
	return (
		bool(settings.get_value("gemini_enabled", false))
		and bool(settings.get_value("allow_online_analysis", false))
		and str(settings.get_value("gemini_api_key", "")).strip_edges() != ""
	)


func _build_local_response(local_result: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"mode": "local",
		"intent": str(local_result.get("intent", "")),
		"text": str(local_result.get("text", "")),
		"actions": safe_actions(local_result.get("actions", [])),
	}


func _offline_fallback(local_result: Dictionary) -> Dictionary:
	if bool(local_result.get("handled", false)):
		return _build_local_response(local_result)
	return {
		"ok": true,
		"mode": "local",
		"intent": "offline_fallback",
		"text": "O modo online esta indisponivel no momento. Continuarei ajudando usando os recursos locais do sistema.\n\nNao encontrei dados suficientes no sistema para responder com seguranca.",
		"actions": [],
	}


func _complete_result(result: Dictionary, started_at: int, sent_chars: int, cache_hit: bool) -> Dictionary:
	_request_busy = false
	if _current_mode != "local":
		_current_mode = "local"
		_emit_mode()
	var duration := Time.get_ticks_msec() - started_at
	_write_technical_log(
		str(result.get("mode", "local")),
		bool(result.get("ok", false)),
		duration,
		str(result.get("error", "")),
		sent_chars,
		cache_hit
	)
	request_finished.emit(result.duplicate(true))
	return result


func _record_exchange(question: String, answer: String) -> void:
	var max_messages := int(settings.get_value("max_history_messages", 20))
	_history.append({"role": "user", "text": question, "created_at": Time.get_datetime_string_from_system(false, true)})
	_history.append({"role": "assistant", "text": answer, "created_at": Time.get_datetime_string_from_system(false, true)})
	while _history.size() > max_messages:
		_history.pop_front()
	if bool(settings.get_value("save_history_local", false)):
		var safe_history := sanitizer.sanitize_history(_history, max_messages, 24000)
		var file := FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(safe_history, "\t"))


func _load_history() -> void:
	if not bool(settings.get_value("save_history_local", false)) or not FileAccess.file_exists(HISTORY_PATH):
		return
	var file := FileAccess.open(HISTORY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		return
	var max_messages := int(settings.get_value("max_history_messages", 20))
	for item in parsed as Array:
		if typeof(item) == TYPE_DICTIONARY:
			_history.append((item as Dictionary).duplicate(true))
	while _history.size() > max_messages:
		_history.pop_front()


func _remove_history_file() -> void:
	if FileAccess.file_exists(HISTORY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HISTORY_PATH))


func _check_usage_limit() -> Dictionary:
	_roll_usage_day()
	var daily_limit := int(settings.get_value("daily_request_limit", 20))
	if int(_usage.get("count", 0)) >= daily_limit:
		return {"ok": false, "error": "daily_limit"}
	var last_request_at := int(_usage.get("last_request_at", 0))
	var interval := int(settings.get_value("minimum_interval_seconds", 10))
	if last_request_at > 0 and int(Time.get_unix_time_from_system()) - last_request_at < interval:
		return {"ok": false, "error": "minimum_interval"}
	return {"ok": true}


func _increment_usage() -> void:
	_roll_usage_day()
	_usage["count"] = int(_usage.get("count", 0)) + 1
	_usage["last_request_at"] = int(Time.get_unix_time_from_system())
	_save_usage()


func _roll_usage_day() -> void:
	var today := Time.get_date_string_from_system()
	if str(_usage.get("date", "")) != today:
		_usage = {"date": today, "count": 0, "last_request_at": 0}


func _load_usage() -> void:
	_usage = {"date": Time.get_date_string_from_system(), "count": 0, "last_request_at": 0}
	if not FileAccess.file_exists(USAGE_PATH):
		return
	var file := FileAccess.open(USAGE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_usage = (parsed as Dictionary).duplicate(true)
	_roll_usage_day()


func _save_usage() -> void:
	var file := FileAccess.open(USAGE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_usage, "\t"))


func _write_technical_log(
	mode: String,
	success: bool,
	duration_ms: int,
	error_code: String,
	sent_chars: int,
	cache_hit: bool
) -> void:
	_rotate_log_if_needed()
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(JSON.stringify({
		"timestamp": Time.get_datetime_string_from_system(false, true),
		"mode": mode,
		"success": success,
		"duration_ms": duration_ms,
		"error_code": error_code,
		"sent_chars": sent_chars,
		"cache_hit": cache_hit,
		"branch": _bound_branch,
	}))


func _rotate_log_if_needed() -> void:
	if not FileAccess.file_exists(LOG_PATH):
		return
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null or file.get_length() <= MAX_LOG_BYTES:
		return
	var lines: Array[String] = []
	while not file.eof_reached():
		var line := file.get_line()
		if line != "":
			lines.append(line)
	var keep_from := maxi(lines.size() - 250, 0)
	var output := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if output != null:
		for index in range(keep_from, lines.size()):
			output.store_line(lines[index])


func _on_monitor_alert_created(alert: Dictionary) -> void:
	alert_created.emit(alert.duplicate(true))


func _run_initial_monitor() -> void:
	if context_provider.is_ready() and bool(settings.get_value("monitor_enabled", true)):
		system_monitor.run_now()


func _emit_mode() -> void:
	var status := get_mode_status()
	mode_changed.emit(str(status.get("mode", "local")), str(status.get("message", "Luna Local")))
