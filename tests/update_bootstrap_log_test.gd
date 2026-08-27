extends SceneTree

const UpdateBootstrap := preload("res://src/update_bootstrap.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var bootstrap := UpdateBootstrap.new()
	_check(bootstrap.call("reset_test_state"), "O estado de teste do bootstrap nao foi resetado.")

	var logged: bool = bool(bootstrap.call("record_update_event", "install", "staged", "Atualizacao instalada e aguardando reinicio.", {
		"candidate_version": "9.9.9",
		"sha256": "abc123",
		"size": 1234,
	}))
	_check(logged, "O evento estruturado de atualizacao nao foi gravado.")

	var events: Array = bootstrap.call("update_log_snapshot", 1)
	_check(events.size() == 1, "A primeira consulta do log estruturado nao retornou um evento.")
	if events.is_empty():
		_finish()
		return

	var event: Dictionary = events[0] as Dictionary
	_check(int(event.get("schema_version", 0)) == 1, "O schema_version do log de atualizacao nao foi preservado.")
	_check(str(event.get("operation", "")) == "install", "A operacao do log de atualizacao nao foi gravada.")
	_check(str(event.get("status", "")) == "staged", "O status do log de atualizacao nao foi gravado.")
	_check(str(event.get("message", "")) == "Atualizacao instalada e aguardando reinicio.", "A mensagem do log de atualizacao nao foi gravada.")
	_check(str(event.get("candidate_version", "")) == "9.9.9", "Os metadados do log de atualizacao nao foram preservados.")
	_check(int(event.get("size", 0)) == 1234, "O tamanho do log de atualizacao nao foi preservado.")

	var report: Dictionary = bootstrap.call("update_report_snapshot") as Dictionary
	_check(int(report.get("total_events", 0)) == 1, "O relatorio automatico nao contou os eventos.")
	_check(int((report.get("by_status", {}) as Dictionary).get("staged", 0)) == 1, "O relatorio automatico nao agrupou o status.")
	_check((report.get("actionable_failures", []) as Array).is_empty(), "O relatorio classificou um evento bem-sucedido como falha acionavel.")
	var report_path := ProjectSettings.globalize_path("user://codex_update_test/update_report.json")
	_check(FileAccess.file_exists(report_path), "O relatorio automatico nao foi criado.")

	var snapshot_path := ProjectSettings.globalize_path("user://codex_update_test/update_log.json")
	_check(FileAccess.file_exists(snapshot_path), "O arquivo do log estruturado nao foi criado.")
	if FileAccess.file_exists(snapshot_path):
		var file := FileAccess.open(snapshot_path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else {}
		if file != null:
			file.close()
		_check(typeof(parsed) == TYPE_DICTIONARY, "O arquivo do log estruturado nao e um Dictionary JSON.")
		if typeof(parsed) == TYPE_DICTIONARY:
			var data := parsed as Dictionary
			_check(int(data.get("schema_version", 0)) == 1, "O arquivo do log estruturado perdeu a versao do schema.")
			_check((data.get("events", []) as Array).size() == 1, "O arquivo do log estruturado nao registrou o evento.")

	var reloaded: Node = UpdateBootstrap.new()
	var persisted_events: Array = reloaded.call("update_log_snapshot", 0)
	var found_persisted := false
	for persisted_event in persisted_events:
		if typeof(persisted_event) == TYPE_DICTIONARY and str((persisted_event as Dictionary).get("id", "")) == str((events[0] as Dictionary).get("id", "")):
			found_persisted = true
			break
	_check(found_persisted, "O evento estruturado nao foi recarregado apos uma nova instancia.")

	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("UPDATE_BOOTSTRAP_LOG_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
