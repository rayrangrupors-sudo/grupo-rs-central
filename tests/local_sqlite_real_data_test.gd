extends SceneTree

const StoreScript := preload("res://src/inventory_store.gd")
var failures: Array[String] = []

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var store: InventoryStore = StoreScript.new()
	store.configure("", "", "imperatriz", false)
	store.load_db()
	var fixtures: Array[Dictionary] = [
		{"sku":"TESTE-SQLITE-001","imei":"869990000000001","chip_number":"8955000000000000001","plate":"TST-0001","name":"Rastreador teste 1","category":"Rastreador","status":"Estoque","tracker_status":"Estoque","stock":1,"quantity":1,"operator":"lucasabm"},
		{"sku":"TESTE-SQLITE-002","imei":"869990000000002","chip_number":"8955000000000000002","plate":"TST-0002","name":"Rastreador teste 2","category":"Rastreador","status":"Estoque","tracker_status":"Estoque","stock":1,"quantity":1,"operator":"lucasabm"},
		{"sku":"TESTE-SQLITE-003","imei":"869990000000003","chip_number":"8955000000000000003","plate":"TST-0003","name":"Rastreador teste 3","category":"Rastreador","status":"Estoque","tracker_status":"Estoque","stock":1,"quantity":1,"operator":"lucasabm"},
	]
	for fixture in fixtures:
		_check(not store.upsert_product(fixture).is_empty(), "Falha ao cadastrar %s" % fixture.sku)
		store.add_system_log_event("CREATE", "Aparelho sintetico cadastrado no teste SQLite.", fixture.sku, {"operator":"lucasabm","entity_type":"device","entity_id":fixture.sku})
	_check(store.install_tracker("TESTE-SQLITE-001", "TST-BAIXA") , "Falha ao dar baixa no aparelho 001")
	store.add_system_log_event("DISCHARGE", "Baixa real de teste para placa TST-BAIXA.", "TESTE-SQLITE-001", {"operator":"lucasabm","entity_type":"device","entity_id":"TESTE-SQLITE-001"})
	_check(store.delete_product("TESTE-SQLITE-002"), "Falha ao excluir o aparelho 002")
	store.add_system_log_event("DELETE", "Exclusao real solicitada no teste SQLite.", "TESTE-SQLITE-002", {"operator":"lucasabm","entity_type":"device","entity_id":"TESTE-SQLITE-002"})
	var remaining := store.get_products("TESTE-SQLITE")
	_check(remaining.size() == 2, "Quantidade final incorreta: %d" % remaining.size())
	_check(store.get_product("TESTE-SQLITE-002").is_empty(), "Aparelho 002 ainda existe")
	var installed := store.get_product("TESTE-SQLITE-001")
	_check(str(installed.get("tracker_status","")).to_lower().contains("instal"), "A baixa do aparelho 001 nao persistiu")
	var backup_path := store.export_manual_backup()
	_check(backup_path != "" and FileAccess.file_exists(backup_path), "Backup SQLite nao foi criado")
	var inspection := store.inspect_backup(backup_path)
	_check(bool(inspection.get("valid",false)), "Backup criado nao passou na integridade")
	print(JSON.stringify({"remaining":remaining.size(),"installed":installed,"movements":store.get_recent_movements(20).size(),"audit":store.get_system_logs(50).size(),"backup":backup_path,"inspection":inspection}))
	if failures.is_empty():
		print("LOCAL_SQLITE_REAL_DATA_TEST_OK"); quit(0); return
	for failure in failures: push_error(failure)
	quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
