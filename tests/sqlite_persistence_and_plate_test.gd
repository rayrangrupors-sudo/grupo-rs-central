extends SceneTree

const StoreScript := preload("res://src/inventory_store.gd")
const TEST_DB := "C:/GRUPO RS CENTRAL/test_artifacts/sqlite_persistence_and_plate_test.sqlite"


func _init() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	push_error("FAIL: %s" % message)
	quit(1)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DB.get_base_dir())
	for suffix in ["", "-wal", "-shm", ".pending.json"]:
		if FileAccess.file_exists(TEST_DB + suffix):
			DirAccess.remove_absolute(TEST_DB + suffix)

	var store: InventoryStore = StoreScript.new()
	store.configure_isolated_sqlite_for_testing(TEST_DB, "teste_placas")
	store.load_db()
	var created := store.upsert_product({
		"sku": "TESTE-PLACA-001",
		"imei": "024999001",
		"chip_number": "8955000000000000001",
		"plate": "AAA - 103",
		"model": "ST310",
		"operator": "CLARO",
		"tracker_status": "Estoque",
		"stock": 1,
	})
	_require(not created.is_empty(), "cadastro retorna somente depois do save SQLite")
	var verified_create := store.verify_product_persisted("TESTE-PLACA-001", created)
	_require(bool(verified_create.get("ok", false)), "cadastro relido fisicamente do SQLite")
	_require(str(created.get("identification_plate", "")) == "AAA - 103", "placa inicial vira identificacao do aparelho")

	var edited := created.duplicate(true)
	edited["operator"] = "VIVO"
	edited["chip_phone"] = "99999999999"
	edited = store.upsert_product(edited)
	_require(not edited.is_empty(), "alteracao gravada")
	_require(bool(store.verify_product_persisted("TESTE-PLACA-001", edited).get("ok", false)), "alteracao relida e comparada no disco")
	var wrong_expected := edited.duplicate(true)
	wrong_expected["operator"] = "TIM"
	_require(not bool(store.verify_product_persisted("TESTE-PLACA-001", wrong_expected).get("ok", false)), "verificacao recusa conteudo diferente do SQLite")

	_require(store.install_tracker("TESTE-PLACA-001", "QRE - 4A02"), "baixa realizada")
	var installed := store.get_product("TESTE-PLACA-001")
	_require(str(installed.get("identification_plate", "")) == "AAA - 103", "baixa preserva identificacao AAA - 103")
	_require(str(installed.get("vehicle_plate", "")) == "QRE - 4A02", "baixa guarda veiculo QRE - 4A02 separadamente")
	_require(bool(store.verify_product_persisted("TESTE-PLACA-001", installed).get("ok", false)), "relacao identificacao/veiculo confirmada no disco")

	var reopened: InventoryStore = StoreScript.new()
	reopened.configure_isolated_sqlite_for_testing(TEST_DB, "teste_placas")
	reopened.load_db()
	var after_restart := reopened.get_product("TESTE-PLACA-001")
	_require(str(after_restart.get("identification_plate", "")) == "AAA - 103", "identificacao sobrevive ao reinicio")
	_require(str(after_restart.get("vehicle_plate", "")) == "QRE - 4A02", "placa do veiculo sobrevive ao reinicio")

	_require(reopened.set_tracker_status("TESTE-PLACA-001", "Estoque"), "retorno ao estoque gravado")
	var returned := reopened.get_product("TESTE-PLACA-001")
	_require(str(returned.get("plate", "")) == "AAA - 103", "retorno ao estoque restaura identificacao visivel")
	_require(str(returned.get("vehicle_plate", "")) == "", "retorno ao estoque encerra vinculo atual com veiculo")
	_require(bool(reopened.verify_product_persisted("TESTE-PLACA-001", returned).get("ok", false)), "retorno ao estoque confirmado fisicamente")

	print("TEST_DB=%s" % TEST_DB)
	print("ALL_TESTS_PASSED")
	quit(0)
