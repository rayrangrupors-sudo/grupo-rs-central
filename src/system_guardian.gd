class_name SystemGuardian
extends Node

signal snapshot_changed(snapshot: Dictionary)
signal event_recorded(event: Dictionary)

const DEFAULT_STATE_PATH := "user://system_guardian_state.json"
const DEFAULT_INTERVAL_SECONDS := 900
const MAX_EVENTS_PER_BRANCH := 80
const REPAIR_COOLDOWN_SECONDS := 900
const SAFE_ACTIONS := [
	"restart_timers",
	"renew_grupo_rs_session",
	"renew_linksolutions_session",
	"release_transient_locks",
	"clear_transient_caches",
]

var _branch_id := "default"
var _probe_callback := Callable()
var _repair_callback := Callable()
var _audit_callback := Callable()
var _state_reader := Callable()
var _state_writer := Callable()
var _state_path := DEFAULT_STATE_PATH
var _interval_seconds := DEFAULT_INTERVAL_SECONDS
var _timer: Timer
var _running := false
var _enabled := true
var _next_run_at := 0
var _cycle_count := 0
var _anomaly_streaks: Dictionary = {}
var _last_fixes: Dictionary = {}
var _events: Array[Dictionary] = []
var _all_states: Dictionary = {}
var _exiting_tree := false
var _snapshot := {
	"status": "idle",
	"summary": "Assistente aguardando",
	"components": [],
	"last_run_at": 0,
	"next_run_at": 0,
	"cycle_count": 0,
	"repairs": 0,
	"enabled": true,
}


func configure(
	branch_id: String,
	probe_callback: Callable,
	repair_callback: Callable,
	audit_callback: Callable = Callable(),
	state_path: String = DEFAULT_STATE_PATH,
	interval_seconds: int = DEFAULT_INTERVAL_SECONDS,
	state_reader: Callable = Callable(),
	state_writer: Callable = Callable()
) -> void:
	_branch_id = branch_id.strip_edges() if branch_id.strip_edges() != "" else "default"
	_probe_callback = probe_callback
	_repair_callback = repair_callback
	_audit_callback = audit_callback
	_state_path = state_path
	_state_reader = state_reader
	_state_writer = state_writer
	_interval_seconds = maxi(interval_seconds, 10)
	_load_state()


func start(initial_delay_seconds: float = 4.0) -> void:
	if _exiting_tree or not is_inside_tree():
		return
	if _running:
		return
	if _timer == null:
		_timer = Timer.new()
		_timer.one_shot = true
		_timer.timeout.connect(_on_timer_timeout)
		add_child(_timer)
	if not _timer.is_inside_tree():
		return
	if not _timer.is_stopped():
		return
	if not _enabled:
		_update_snapshot_state("paused", "Assistente pausado")
		return
	_schedule_next(maxf(initial_delay_seconds, 0.1))


func shutdown() -> void:
	var was_scheduled := _timer != null and not _timer.is_stopped()
	if _timer != null:
		_timer.stop()
	_next_run_at = 0
	if was_scheduled:
		_persist_state()


func set_enabled(value: bool) -> void:
	_enabled = value
	if not _enabled:
		if _timer != null:
			_timer.stop()
		_next_run_at = 0
		_update_snapshot_state("paused", "Assistente pausado")
	else:
		_update_snapshot_state("idle", "Assistente retomado")
		_schedule_next(1.0)
	_persist_state()


func is_enabled() -> bool:
	return _enabled


func is_running() -> bool:
	return _running


func seconds_until_next() -> int:
	if not _enabled or _next_run_at <= 0:
		return 0
	return maxi(_next_run_at - int(Time.get_unix_time_from_system()), 0)


func get_snapshot() -> Dictionary:
	var result := _snapshot.duplicate(true)
	result["events"] = _events.duplicate(true)
	result["running"] = _running
	result["enabled"] = _enabled
	result["next_run_at"] = _next_run_at
	return result


func run_now(reason: String = "manual") -> Dictionary:
	if _running:
		return get_snapshot()
	if not _enabled and reason != "test":
		return get_snapshot()
	if not _probe_callback.is_valid():
		_update_snapshot_state("error", "Sonda de diagnostico indisponivel")
		return get_snapshot()

	_running = true
	if _timer != null:
		_timer.stop()
	_next_run_at = 0
	_update_snapshot_state("checking", "Analisando sistema")

	var raw_probe: Variant = await _probe_callback.call()
	var probe: Dictionary = raw_probe if typeof(raw_probe) == TYPE_DICTIONARY else {}
	var components := _normalize_components(probe.get("components", []))
	if components.is_empty():
		components.append({
			"id": "guardian_probe",
			"label": "Diagnostico interno",
			"status": "error",
			"message": "A verificacao nao retornou componentes validos.",
		})
	var repaired_count := 0
	var previous_status := str(_snapshot.get("status", "idle"))

	for index in range(components.size()):
		var component := components[index]
		var component_id := str(component.get("id", "component-%d" % index))
		var status := str(component.get("status", "warning"))
		var anomalous := status == "warning" or status == "error"
		if anomalous:
			_anomaly_streaks[component_id] = int(_anomaly_streaks.get(component_id, 0)) + 1
		else:
			_anomaly_streaks[component_id] = 0

		var action := str(component.get("fix_action", "")).strip_edges()
		if action == "" or not anomalous:
			components[index] = component
			continue

		if not SAFE_ACTIONS.has(action):
			component["automation"] = "blocked"
			component["automation_message"] = "Acao fora da lista segura."
			if int(_anomaly_streaks.get(component_id, 0)) == 1:
				_record_event("blocked", component_id, "Acao bloqueada", "%s: %s" % [component_id, action])
			components[index] = component
			continue

		var repair_after := maxi(int(component.get("repair_after", 1)), 1)
		if int(_anomaly_streaks.get(component_id, 0)) < repair_after:
			component["automation"] = "observing"
			component["automation_message"] = "Confirmando anomalia antes de agir."
			components[index] = component
			continue
		if not _repair_is_available(action):
			component["automation"] = "cooldown"
			component["automation_message"] = "Correcao em periodo de seguranca."
			components[index] = component
			continue
		if not _repair_callback.is_valid():
			component["automation"] = "unavailable"
			components[index] = component
			continue

		var raw_repair: Variant = await _repair_callback.call(action, component.duplicate(true))
		var repair: Dictionary = raw_repair if typeof(raw_repair) == TYPE_DICTIONARY else {}
		_last_fixes[action] = int(Time.get_unix_time_from_system())
		if bool(repair.get("ok", false)):
			repaired_count += 1
			_anomaly_streaks[component_id] = 0
			component["status"] = "recovered"
			component["automation"] = "repaired"
			component["message"] = str(repair.get("message", "Correcao segura aplicada."))
			_record_event("repair", component_id, "Correcao automatica", str(component.get("message", "")))
		else:
			component["automation"] = "failed"
			component["automation_message"] = str(repair.get("message", "A correcao segura falhou."))
			_record_event("error", component_id, "Falha na autocorrecao", str(component.get("automation_message", "")))
		components[index] = component

	_cycle_count += 1
	_running = false
	var status_data := _summarize_components(components)
	_snapshot = {
		"status": str(status_data.get("status", "ok")),
		"summary": str(status_data.get("summary", "Sistema verificado")),
		"components": components,
		"last_run_at": int(Time.get_unix_time_from_system()),
		"next_run_at": 0,
		"cycle_count": _cycle_count,
		"repairs": repaired_count,
		"reason": reason,
		"enabled": _enabled,
	}
	if str(_snapshot.get("status", "")) == "error":
		_record_event("error", "system", "Atencao necessaria", str(_snapshot.get("summary", "")))
	elif str(_snapshot.get("status", "")) == "ok" and (previous_status == "error" or previous_status == "warning"):
		_record_event("info", "system", "Sistema normalizado", str(_snapshot.get("summary", "")))
	elif repaired_count > 0:
		_record_event("info", "system", "Ciclo concluido", "%d correcao(oes) segura(s)." % repaired_count)
	_persist_state()
	if _enabled:
		_schedule_next(float(_interval_seconds))
	_emit_snapshot()
	return get_snapshot()


func _on_timer_timeout() -> void:
	run_now("automatico")


func _schedule_next(delay_seconds: float) -> void:
	if not _enabled:
		return
	if _timer == null:
		return
	var delay := maxf(delay_seconds, 0.1)
	_timer.start(delay)
	_next_run_at = int(Time.get_unix_time_from_system()) + int(ceil(delay))
	_snapshot["next_run_at"] = _next_run_at
	_emit_snapshot()


func _normalize_components(raw_components: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(raw_components) != TYPE_ARRAY:
		return result
	for index in range((raw_components as Array).size()):
		var raw: Variant = (raw_components as Array)[index]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var component := (raw as Dictionary).duplicate(true)
		component["id"] = str(component.get("id", "component-%d" % index))
		component["label"] = str(component.get("label", component.get("id", "Componente")))
		var status := str(component.get("status", "warning")).to_lower()
		if not ["ok", "info", "warning", "error", "recovered"].has(status):
			status = "warning"
		component["status"] = status
		component["message"] = str(component.get("message", "Sem detalhes."))
		result.append(component)
	return result


func _summarize_components(components: Array[Dictionary]) -> Dictionary:
	var errors := 0
	var warnings := 0
	var recovered := 0
	for component in components:
		match str(component.get("status", "warning")):
			"error":
				errors += 1
			"warning":
				warnings += 1
			"recovered":
				recovered += 1
	if errors > 0:
		return {"status": "error", "summary": "%d falha(s) e %d alerta(s)" % [errors, warnings]}
	if warnings > 0:
		return {"status": "warning", "summary": "%d alerta(s) em observacao" % warnings}
	if recovered > 0:
		return {"status": "recovered", "summary": "%d correcao(oes) aplicada(s)" % recovered}
	return {"status": "ok", "summary": "Todos os componentes estao normais"}


func _repair_is_available(action: String) -> bool:
	var last_fix := int(_last_fixes.get(action, 0))
	return last_fix <= 0 or int(Time.get_unix_time_from_system()) - last_fix >= REPAIR_COOLDOWN_SECONDS


func _record_event(kind: String, component_id: String, title: String, details: String) -> void:
	var event := {
		"timestamp": Time.get_datetime_string_from_system(false, true),
		"kind": kind,
		"component": component_id,
		"title": title,
		"details": details,
	}
	_events.push_front(event)
	if _events.size() > MAX_EVENTS_PER_BRANCH:
		_events.resize(MAX_EVENTS_PER_BRANCH)
	event_recorded.emit(event.duplicate(true))
	if _audit_callback.is_valid():
		_audit_callback.call(event.duplicate(true))


func _update_snapshot_state(status: String, summary: String) -> void:
	_snapshot["status"] = status
	_snapshot["summary"] = summary
	_snapshot["enabled"] = _enabled
	_snapshot["next_run_at"] = _next_run_at
	_emit_snapshot()


func _emit_snapshot() -> void:
	snapshot_changed.emit(get_snapshot())


func _load_state() -> void:
	if _state_reader.is_valid():
		var online_state: Variant = _state_reader.call()
		_all_states = (online_state as Dictionary).duplicate(true) \
			if typeof(online_state) == TYPE_DICTIONARY else {}
	elif _state_path.strip_edges() != "":
		_all_states = _read_json_dictionary(_state_path)
	else:
		_all_states = {}
	var raw_state: Variant = _all_states.get(_branch_id, {})
	if typeof(raw_state) != TYPE_DICTIONARY:
		return
	var state := raw_state as Dictionary
	_enabled = bool(state.get("enabled", true))
	_cycle_count = int(state.get("cycle_count", 0))
	if typeof(state.get("anomaly_streaks", {})) == TYPE_DICTIONARY:
		_anomaly_streaks = (state.get("anomaly_streaks", {}) as Dictionary).duplicate(true)
	if typeof(state.get("last_fixes", {})) == TYPE_DICTIONARY:
		_last_fixes = (state.get("last_fixes", {}) as Dictionary).duplicate(true)
	if typeof(state.get("events", [])) == TYPE_ARRAY:
		_events.clear()
		for raw_event in state.get("events", []):
			if typeof(raw_event) == TYPE_DICTIONARY:
				_events.append((raw_event as Dictionary).duplicate(true))
	if typeof(state.get("snapshot", {})) == TYPE_DICTIONARY:
		_snapshot = (state.get("snapshot", {}) as Dictionary).duplicate(true)
	_snapshot["enabled"] = _enabled
	_snapshot["cycle_count"] = _cycle_count


func _persist_state() -> void:
	_all_states[_branch_id] = {
		"enabled": _enabled,
		"cycle_count": _cycle_count,
		"anomaly_streaks": _anomaly_streaks,
		"last_fixes": _last_fixes,
		"events": _events,
		"snapshot": _snapshot,
		"saved_at": Time.get_datetime_string_from_system(false, true),
	}
	if _state_writer.is_valid():
		_state_writer.call(_all_states.duplicate(true))
	elif _state_path.strip_edges() != "":
		_write_json_dictionary(_state_path, _all_states)


func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _write_json_dictionary(path: String, value: Dictionary) -> bool:
	var temp_path := "%s.tmp" % path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file = null
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var absolute_target := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(absolute_target)
		if remove_error != OK:
			DirAccess.remove_absolute(absolute_temp)
			return false
	return DirAccess.rename_absolute(absolute_temp, absolute_target) == OK


func _exit_tree() -> void:
	_exiting_tree = true
	shutdown()
