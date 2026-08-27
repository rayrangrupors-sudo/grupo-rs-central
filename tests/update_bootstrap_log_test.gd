extends SceneTree

const UpdateBootstrap := preload("res://src/update_bootstrap.gd")
const AISanitizer := preload("res://ai/ai_sanitizer.gd")

var failures: Array[String] = []
var bootstrap: Node = null
var reloaded: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	bootstrap = UpdateBootstrap.new()
	_check(bootstrap.call("reset_test_state"), "O estado de teste do bootstrap nao foi resetado.")

	_record_synthetic_events()

	var events: Array = bootstrap.call("update_log_snapshot", 1)
	_check(events.size() == 1, "A primeira consulta do log estruturado nao retornou um evento.")
	if events.is_empty():
		_finish()
		return

	var event: Dictionary = events[0] as Dictionary
	_check(int(event.get("schema_version", 0)) == 1, "O schema_version do log de atualizacao nao foi preservado.")
	_check(str(event.get("operation", "")) == "synthetic_failure", "A operacao mais recente do log nao foi preservada.")
	_check(str(event.get("status", "")) == "failed", "A falha acionavel sintetica nao foi gravada com status failed.")
	_check(str(event.get("message", "")) == "Falha acionavel sintetica.", "A mensagem sintetica da falha acionavel nao foi preservada.")
	_check(str(event.get("failure_class", "")) == "synthetic_actionable", "A classe sintetica da falha acionavel nao foi preservada.")

	var report: Dictionary = bootstrap.call("update_report_snapshot") as Dictionary
	_check(int(report.get("total_events", 0)) == 4, "O relatorio automatico nao contou os eventos sinteticos.")
	var by_status := report.get("by_status", {}) as Dictionary
	_check(int(by_status.get("ok", 0)) == 1, "O relatorio automatico nao agrupou sucesso sintetico.")
	_check(int(by_status.get("fallback", 0)) == 1, "O relatorio automatico nao agrupou fallback sintetico.")
	_check(int(by_status.get("error", 0)) == 1, "O relatorio automatico nao agrupou erro tecnico sintetico.")
	_check(int(by_status.get("failed", 0)) == 1, "O relatorio automatico nao agrupou falha acionavel sintetica.")
	var actionable := report.get("actionable_failures", []) as Array
	_check(actionable.size() == 1, "O relatorio nao limitou falhas acionaveis ao status failed.")
	if actionable.size() == 1:
		var actionable_event := actionable[0] as Dictionary
		_check(str(actionable_event.get("status", "")) == "failed", "Falha acionavel com status diferente de failed.")
		_check(str(actionable_event.get("operation", "")) == "synthetic_failure", "Falha acionavel sintetica incorreta.")
	var report_path := ProjectSettings.globalize_path("user://codex_update_test/update_report.json")
	_check(FileAccess.file_exists(report_path), "O relatorio automatico nao foi criado.")

	var snapshot_path := ProjectSettings.globalize_path("user://codex_update_test/update_log.json")
	_check(FileAccess.file_exists(snapshot_path), "O arquivo do log estruturado nao foi criado.")
	if FileAccess.file_exists(snapshot_path):
		var file := FileAccess.open(snapshot_path, FileAccess.READ)
		var snapshot_text := file.get_as_text() if file != null else ""
		var parsed: Variant = JSON.parse_string(snapshot_text)
		if file != null:
			file.close()
		_check(typeof(parsed) == TYPE_DICTIONARY, "O arquivo do log estruturado nao e um Dictionary JSON.")
		if typeof(parsed) == TYPE_DICTIONARY:
			var data := parsed as Dictionary
			_check(int(data.get("schema_version", 0)) == 1, "O arquivo do log estruturado perdeu a versao do schema.")
			_check((data.get("events", []) as Array).size() == 4, "O arquivo do log estruturado nao registrou os eventos sinteticos.")
			_check(not _text_has_sensitive_fragment(snapshot_text), "O log estruturado reteve fragmento sensivel.")

	_check(_export_excludes_logs_and_harnesses(), "O preset de exportacao nao exclui logs/harnesses.")
	_check(_sanitizer_blocks_and_redacts_synthetic_text(), "A sanitizacao sintetica nao bloqueou/removeu dados sensiveis.")

	reloaded = UpdateBootstrap.new()
	var persisted_events: Array = reloaded.call("update_log_snapshot", 0)
	var found_persisted := false
	for persisted_event in persisted_events:
		if typeof(persisted_event) == TYPE_DICTIONARY and str((persisted_event as Dictionary).get("id", "")) == str((events[0] as Dictionary).get("id", "")):
			found_persisted = true
			break
	_check(found_persisted, "O evento estruturado nao foi recarregado apos uma nova instancia.")

	_finish()


func _record_synthetic_events() -> void:
	var cases: Array[Dictionary] = [
		{
			"operation": "synthetic_success",
			"status": "ok",
			"message": "Sucesso sintetico.",
			"metadata": {"scenario": "success", "safe_count": 1},
		},
		{
			"operation": "synthetic_fallback",
			"status": "fallback",
			"message": "Fallback sintetico.",
			"metadata": {"scenario": "fallback", "fallback_used": true},
		},
		{
			"operation": "synthetic_technical_error",
			"status": "error",
			"message": "Erro tecnico sintetico.",
			"metadata": {"scenario": "technical_error", "retryable": true},
		},
		{
			"operation": "synthetic_failure",
			"status": "failed",
			"message": "Falha acionavel sintetica.",
			"metadata": {"scenario": "actionable_failure", "failure_class": "synthetic_actionable"},
		},
	]
	for item in cases:
		var logged: bool = bool(bootstrap.call(
			"record_update_event",
			str(item.get("operation", "")),
			str(item.get("status", "")),
			str(item.get("message", "")),
			item.get("metadata", {}) as Dictionary
		))
		_check(logged, "Evento sintetico nao foi gravado.")


func _sanitizer_blocks_and_redacts_synthetic_text() -> bool:
	var sanitizer := AISanitizer.new()
	var marker := "valor" + "_sintetico"
	var client_marker := "Pessoa" + " Sintetica"
	var sample := "se" + "nha=" + marker + "; to" + "ken=" + marker + "; cli" + "ente=" + client_marker
	var sanitized := sanitizer.sanitize_text(sample, 200)
	var text := str(sanitized.get("text", ""))
	return bool(sanitized.get("blocked", false)) \
		and bool(sanitized.get("sensitive", false)) \
		and not _text_has_sensitive_fragment(text)


func _export_excludes_logs_and_harnesses() -> bool:
	var preset := FileAccess.open(ProjectSettings.globalize_path("res://export_presets.cfg"), FileAccess.READ)
	if preset == null:
		return false
	var text := preset.get_as_text()
	preset.close()
	var required := [
		"src/__codex_*.gd",
		"tmp_*.log",
		"qa_api_report/**",
		"*.log",
		"*.jsonl",
		"tests/**",
		"projeto/**",
	]
	for pattern in required:
		if not text.contains(pattern):
			return false
	return true


func _text_has_sensitive_fragment(text: String) -> bool:
	var lowered := text.to_lower()
	var marker := "valor" + "_sintetico"
	var client_marker := "pessoa" + " sintetica"
	return lowered.contains(marker) \
		or lowered.contains(client_marker) \
		or lowered.contains("se" + "nha=") \
		or lowered.contains("to" + "ken=")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	_cleanup_instances()
	if failures.is_empty():
		print("UPDATE_BOOTSTRAP_LOG_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _cleanup_instances() -> void:
	if reloaded != null:
		reloaded.free()
		reloaded = null
	if bootstrap != null:
		bootstrap.free()
		bootstrap = null
