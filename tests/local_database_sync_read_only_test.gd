extends SceneTree

const LocalDatabaseService := preload("res://src/local_data_service.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sync := LocalDatabaseService.new()
	root.add_child(sync)
	await process_frame
	var summary: Dictionary = sync.call("get_configuration_summary")
	_check(str(summary.get("provider", "")) == "SQLite local", "O provedor operacional não é SQLite local.")
	_check(str(summary.get("database", "")).ends_with("grupo_rs_central.sqlite"), "O caminho do SQLite não foi informado.")
	_check(not bool(sync.call("is_local_database_auth_required")), "O SQLite local não deve exigir autenticação externa.")
	var status: Dictionary = sync.call("get_status")
	_check(bool(status.get("local", false)), "O serviço não se identificou como local.")
	_check(bool(status.get("data_available", false)), "O serviço local não informou disponibilidade.")

	sync.queue_free()
	await process_frame
	if failures.is_empty():
		print("BANCO_LOCAL_SQL_SYNC_READ_ONLY_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
