extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store_script := load("res://src/inventory_store.gd")
	if store_script == null:
		_fail("Store nao carregou.")
		return

	var store: InventoryStore = store_script.new()
	store.configure("user://__codex_maintenance_date_inventory.json", "__codex_maintenance_date_inventory.json", "user://__codex_maintenance_date_backups", false)
	store.load_db()
	store.mark_remote_available()
	var product := {
		"sku": "024399999",
		"imei": "024399999",
		"equipment_number": "024399999",
		"model": "RS300",
		"category": "RS300",
		"operator": "Tim",
		"plate": "AAA - T999",
		"tracker_status": "Estoque",
		"status": "Estoque",
		"stock": 1,
	}
	if store.upsert_product(product).is_empty():
		_fail("Produto de teste nao foi criado.")
		return
	if not store.install_tracker("024399999", "AAA - T999"):
		_fail("Instalacao de teste nao foi registrada.")
		return
	var installed := store.get_product("024399999")
	if str(installed.get("installed_at", "")) == "":
		_fail("Instalacao de teste nao recebeu data.")
		return
	if not store.set_tracker_status("024399999", "Manutencao"):
		_fail("Transicao para manutencao falhou.")
		return
	var maintenance := store.get_product("024399999")
	if str(maintenance.get("installed_at", "")) != "" or str(maintenance.get("discharged_at", "")) != "":
		_fail("Data antiga permaneceu ao entrar em manutencao.")
		return

	if not store.install_tracker("024399999", "BBB - T111"):
		_fail("Reinstalacao de teste nao foi registrada.")
		return
	var form_edit := store.get_product("024399999")
	form_edit["tracker_status"] = "Manutencao"
	form_edit["status"] = "Manutencao"
	form_edit["stock"] = 0
	form_edit.erase("installed_at")
	form_edit.erase("discharged_at")
	if store.upsert_product_replacing_sku("024399999", form_edit).is_empty():
		_fail("Edicao de formulario nao foi salva.")
		return
	var saved_edit := store.get_product("024399999")
	if str(saved_edit.get("installed_at", "")) != "" or str(saved_edit.get("discharged_at", "")) != "":
		_fail("Edicao de formulario restaurou data de instalacao.")
		return

	var history := store.get_product_history("024399999", 20)
	var has_install_movement := false
	for event in history:
		if str(event.get("action", "")).to_lower() == "baixa":
			has_install_movement = true
			break
	if not has_install_movement:
		_fail("Historico da baixa anterior nao foi preservado.")
		return

	_cleanup()
	print("MAINTENANCE_DATE_CHECK_OK")
	quit(0)


func _cleanup() -> void:
	for path in [
		"user://__codex_maintenance_date_inventory.json",
		"user://__codex_maintenance_date_inventory.json.tmp",
		"user://__codex_maintenance_date_inventory.json.bak",
		"user://__codex_maintenance_date_inventory.json.pending.json",
		"user://__codex_maintenance_date_inventory.json.pending.json.tmp",
		"user://__codex_maintenance_date_inventory.json.pending.json.bak",
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail(message: String) -> void:
	_cleanup()
	push_error(message)
	quit(1)
