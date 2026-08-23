extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store_script := load("res://src/inventory_store.gd")
	var dashboard_script := load("res://src/__codex_auto_sms_dashboard_stub.gd")
	if store_script == null or dashboard_script == null:
		_fail("Dependencias da auditoria nao carregaram.")
		return

	var store: InventoryStore = store_script.new()
	store.configure("user://__codex_maintenance_audit.json", "__codex_maintenance_audit.json", "user://__codex_maintenance_audit_backups", false)
	store.load_db()
	store.add_maintenances([
		_auto_row("024711111", "STL - 0001", "monitor_grupo_rs_manutencao"),
		_auto_row("024722222", "REC - 0002", "monitor_grupo_rs_manutencao"),
		_auto_row("024733333", "DEL - 0003", "monitor_automatico"),
		_auto_row("024744444", "ERR - 0004", "monitor_grupo_rs_manutencao"),
		{
			"client": "CLIENTE MANUAL",
			"plate": "MAN - 0005",
			"serial": "024755555",
			"provider": "manual",
			"note": "Manutencao cadastrada pelo usuario.",
		},
	])

	var dashboard: Node = dashboard_script.new()
	dashboard.set("store", store)
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	var stale_rows: Array[Dictionary] = [{
		"serial": "024711111",
		"monitor_interval": "24 - 72 Horas",
		"apn": "hinova",
	}]
	dashboard.set("test_grupo_rs_maintenance_rows", stale_rows)
	dashboard.set("test_equipment_presence_by_serial", {
		"024722222": {"ok": true, "found": true},
		"024733333": {"ok": true, "found": false},
		"024744444": {"ok": false, "found": false, "message": "Falha simulada."},
	})
	root.add_child(dashboard)
	await process_frame

	var result: Dictionary = await dashboard.call("_audit_auto_reset_maintenances", true)
	if not bool(result.get("ok", false)) or int(result.get("removed", 0)) != 2 or int(result.get("kept", 0)) != 1 or int(result.get("protected_errors", 0)) != 1:
		_fail("Resultado inesperado da auditoria: %s" % str(result), dashboard)
		return
	if not _has_serial(store, "024711111") or not _has_serial(store, "024744444") or not _has_serial(store, "024755555"):
		_fail("Registro desatualizado, protegido por erro ou manual foi removido.", dashboard)
		return
	if _has_serial(store, "024722222") or _has_serial(store, "024733333"):
		_fail("Registro recuperado ou excluido permaneceu na manutencao.", dashboard)
		return

	store.add_maintenances([_auto_row("024766666", "PAR - 0006", "monitor_grupo_rs_manutencao")])
	dashboard.set("test_grupo_rs_maintenance_fetch_complete", false)
	var partial: Dictionary = await dashboard.call("_audit_auto_reset_maintenances", true)
	if bool(partial.get("ok", false)) or not _has_serial(store, "024766666"):
		_fail("Consulta parcial removeu uma manutencao indevidamente: %s" % str(partial), dashboard)
		return

	dashboard.queue_free()
	await process_frame
	_cleanup()
	print("AUTO_MAINTENANCE_AUDIT_CHECK_OK")
	quit(0)


func _auto_row(serial: String, plate: String, provider: String) -> Dictionary:
	return {
		"client": "CLIENTE %s" % serial,
		"plate": plate,
		"serial": serial,
		"provider": provider,
		"note": "Entrada automatica pelo monitor: sem retorno apos 24 horas do SMS.",
	}


func _has_serial(store: InventoryStore, serial: String) -> bool:
	for item in store.get_maintenances(false):
		if str(item.get("serial", "")) == serial:
			return true
	return false


func _cleanup() -> void:
	for path in [
		"user://__codex_maintenance_audit.json",
		"user://__codex_maintenance_audit.json.tmp",
		"user://__codex_maintenance_audit.json.bak",
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail(message: String, dashboard: Node = null) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	_cleanup()
	quit(1)
