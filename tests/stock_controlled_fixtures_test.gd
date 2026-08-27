extends SceneTree

const DashboardScript := preload("res://tests/fixtures/offline_inventory_dashboard.gd")
const BranchDashboardScript := preload("res://tests/fixtures/offline_branch_inventory_dashboard.gd")
const StoreScript := preload("res://src/inventory_store.gd")

var failures: Array[String] = []


class FirstLinkDashboard:
	extends DashboardScript

	var find_vehicle_calls := 0
	var find_equipment_calls := 0
	var register_vehicle_calls := 0
	var requested_plate := ""
	var requested_serial := ""
	var registered_vehicle := false

	func _grupo_rs_api_find_vehicle(plate: String = "", serial: String = "", _exact: bool = false, _include_full: bool = false) -> Dictionary:
		find_vehicle_calls += 1
		requested_plate = str(plate)
		requested_serial = str(serial)
		if registered_vehicle:
			return {"ok": true, "row": {"serial": serial, "plate": plate, "client": "RS300", "tipoVeiculo": "Carro"}}
		return {"ok": false, "not_found": true, "response_code": 404, "message": "fixture_not_found"}

	func _grupo_rs_api_find_equipment(serial: String, _exact: bool = true) -> Dictionary:
		find_equipment_calls += 1
		return {"ok": true, "row": {"serial": serial, "api_id": "fixture-equipment"}}

	func _grupo_rs_api_register_vehicle(request: Dictionary, _equipment_row: Dictionary) -> Dictionary:
		register_vehicle_calls += 1
		registered_vehicle = true
		return {
			"ok": true,
			"row": {
				"serial": str(request.get("serial", "")),
				"plate": str(request.get("new_plate", request.get("plate", ""))),
				"client": "RS300",
				"tipoVeiculo": "Carro",
			},
		}


class FakeFirebaseSync:
	extends Node

	var bound_store: Variant
	var bound_branch := ""
	var snapshots: Dictionary = {}
	var refresh_calls: Array[String] = []

	func bind_store(next_store: Variant, branch_id: String) -> void:
		bound_store = next_store
		bound_branch = branch_id

	func refresh_remote(_health_only: bool = false) -> Dictionary:
		refresh_calls.append(bound_branch)
		var snapshot: Dictionary = snapshots.get(bound_branch, {})
		if bound_store != null:
			bound_store.replace_from_remote(snapshot)
		return {
			"ok": true,
			"state": "synced",
			"branch": bound_branch,
			"data_available": true,
			"record_count": (snapshot.get("products", []) as Array).size(),
		}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_first_plate_link_fixture()
	await _check_temporal_out_of_order_and_tie()
	await _check_firebase_only_branches_fixture()
	if failures.is_empty():
		print("STOCK_CONTROLLED_FIXTURES_TEST_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _check_first_plate_link_fixture() -> void:
	var dashboard := FirstLinkDashboard.new()
	root.add_child(dashboard)
	await process_frame
	var result: Dictionary = await dashboard._perform_api_vehicle_modification({
		"serial": "900000001",
		"remote_serial": "900000001",
		"old_plate": "",
		"new_plate": "TST-001",
		"plate": "TST-001",
		"vehicle_type": "Carro",
		"force_rs300_titular": true,
		"clear_vehicle_fields": true,
	})
	_check(bool(result.get("handled", false)), "Primeiro vínculo não foi tratado pelo caminho API.")
	_check(bool(result.get("ok", false)), "Primeiro vínculo de placa sintético não concluiu confirmado.")
	_check(int(dashboard.find_vehicle_calls) >= 1, "Primeiro vínculo não consultou ausência da placa antes de criar.")
	_check(int(dashboard.find_equipment_calls) == 1, "Primeiro vínculo não confirmou equipamento antes de criar placa.")
	_check(int(dashboard.register_vehicle_calls) == 1, "Primeiro vínculo não chamou a criação de placa uma única vez.")
	dashboard.queue_free()
	await process_frame


func _check_temporal_out_of_order_and_tie() -> void:
	var dashboard := DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set_process(false)
	var product := {"sku": "SKU-TEMPORAL", "imei": "910000001", "plate": "TMP-001"}
	dashboard.set("inventory_device_cycle_products", [product])
	var newer_variant: Variant = dashboard._grupo_rs_api_normalize_location({
		"numeroSerie": "910000001",
		"placa": "TMP-001",
		"data_servidor": "2026-08-27 10:00:00",
		"data_gps": "2026-08-27 10:00:00",
	})
	var older_variant: Variant = dashboard._grupo_rs_api_normalize_location({
		"numeroSerie": "910000001",
		"placa": "TMP-001",
		"data_servidor": "2026-08-27 09:00:00",
		"data_gps": "2026-08-27 09:00:00",
	})
	if typeof(newer_variant) == TYPE_DICTIONARY and typeof(older_variant) == TYPE_DICTIONARY:
		dashboard._process_inventory_communication_page([newer_variant as Dictionary])
		var key := str(dashboard._inventory_communication_cache_key_for_product(product))
		var first_status: Dictionary = dashboard.inventory_communication_status_cache.get(key, {}) as Dictionary
		dashboard._process_inventory_communication_page([older_variant as Dictionary])
		var final_status: Dictionary = dashboard.inventory_communication_status_cache.get(key, {}) as Dictionary
		_check(str(first_status.get("server_at", "")) == str(final_status.get("server_at", "")), "Dado fora de ordem substituiu leitura mais recente.")
	else:
		_check(false, "Fixtures temporais não normalizaram.")
	var equal_current := {"server_unix": 100, "gps_unix": 100, "label": "confirmado", "coordinate_state": "valid"}
	var equal_incoming := {"server_unix": 100, "gps_unix": 100, "label": "pendente", "extra_flag": "preservar"}
	var merged: Dictionary = dashboard._merge_equal_inventory_communication_status(equal_current, equal_incoming)
	_check(str(merged.get("label", "")) == "confirmado", "Empate temporal sobrescreveu estado confirmado.")
	_check(str(merged.get("extra_flag", "")) == "preservar", "Empate temporal não completou campo ausente.")
	dashboard.queue_free()
	await process_frame


func _check_firebase_only_branches_fixture() -> void:
	var dashboard := BranchDashboardScript.new()
	var sync := FakeFirebaseSync.new()
	var store := StoreScript.new()
	root.add_child(sync)
	root.add_child(dashboard)
	await process_frame
	dashboard.offline_firebase_sync = sync
	sync.snapshots = {
		"araguaina": {
			"products": [{"sku": "BRANCH-FIXTURE", "imei": "920000001", "plate": "FBO-001", "status": "estoque"}],
			"movements": [],
			"maintenance": [],
			"logs": [],
			"sms_logs": [],
		}
	}
	dashboard.store = store
	dashboard.selected_branch_id = "araguaina"
	dashboard.current_section = "inventory"
	sync.bind_store(store, "araguaina")
	await dashboard._refresh_open_branch_from_remote(sync, "araguaina", store)
	var products: Array[Dictionary] = store.get_products()
	_check(products.size() == 1, "Filial Firebase-only não carregou fixture do Firebase simulado.")
	_check(str(products[0].get("plate", "")) == "FBO-001", "Filial Firebase-only perdeu placa sintética.")
	_check(not dashboard._branch_supports_operational_apis(), "Filial Firebase-only habilitou APIs operacionais.")
	_check(not dashboard._grupo_rs_api_reads_enabled(), "Filial Firebase-only habilitou leitura Grupo RS.")
	_check(dashboard.offline_table_refreshes == 1, "Filial Firebase-only não atualizou tabela após Firebase simulado.")
	dashboard.queue_free()
	sync.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
