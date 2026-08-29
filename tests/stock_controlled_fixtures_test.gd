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


class FakeBancoLocalSQLSync:
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


class DischargeDashboard:
	extends DashboardScript

	var local_database_mode := "success"
	var local_database_calls := 0
	var success_count := 0
	var error_count := 0
	var refresh_count := 0
	var logged_actions: Array[String] = []

	func _ensure_local_database_modification_saved(_serial: String = "", _expected_product: Dictionary = {}) -> Dictionary:
		local_database_calls += 1
		if local_database_mode == "error":
			return {"ok": false, "state": "error", "message": "fixture_local_database_refused"}
		if local_database_mode == "pending":
			return {"ok": false, "state": "pending", "pending": true, "message": "fixture_local_database_pending"}
		return {"ok": true, "state": "synced"}

	func _show_success(_title: String, _message: String) -> void:
		success_count += 1

	func _show_error(_title: String, _message: String) -> void:
		error_count += 1

	func _log_system_action(action: String, _details: String = "", _serial: String = "") -> void:
		logged_actions.append(action)

	func _refresh_table() -> void:
		refresh_count += 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_first_plate_link_fixture()
	await _check_api_alias_and_cache_status_fixtures()
	await _check_discharge_local_database_barrier_fixtures()
	await _check_temporal_out_of_order_and_tie()
	await _check_local_database_only_branches_fixture()
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


func _check_api_alias_and_cache_status_fixtures() -> void:
	var dashboard := DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	var row: Dictionary = dashboard._grupo_rs_api_inventory_equipment_row({
		"NumeroSerie": "910000099",
		"Placa": "ALS-001",
		"Cliente": "CLIENTE TESTE",
		"NumeroChip": "89550000000000000001",
		"NumeroTelefone": "99999999999",
		"APN": "hinova.br",
		"Status": "Ativo",
	})
	_check(str(row.get("serial", "")) == "910000099", "Alias case-insensitive não capturou série.")
	_check(str(row.get("plate", "")) == "ALS-001", "Alias case-insensitive não capturou placa.")
	_check(str(row.get("chip", "")) == "89550000000000000001", "Alias case-insensitive não capturou chip.")
	_check(str(row.get("phone", "")) == "99999999999", "Alias case-insensitive não capturou telefone.")
	_check(str(row.get("apn", "")) == "hinova.br", "Alias case-insensitive não capturou APN.")
	_check(str(row.get("status", "")) == "Ativo", "Alias case-insensitive não capturou status cadastral.")
	var empty_status: Dictionary = dashboard._cached_location_status_for_serial("910000099")
	_check(str(empty_status.get("label", "")) == "Não consultado", "Cache limpo não diferencia status não consultado.")
	dashboard.location_status_busy["910000099"] = true
	var busy_status: Dictionary = dashboard._cached_location_status_for_serial("910000099")
	_check(str(busy_status.get("label", "")) == "Consultando", "Cache ocupado não diferencia status consultando.")
	dashboard.location_status_busy.clear()
	dashboard.location_status_cache["910000099"] = {"label": "Indisponivel", "color": Color("#d97706"), "checked_at": Time.get_unix_time_from_system()}
	var unavailable_status: Dictionary = dashboard._cached_location_status_for_serial("910000099")
	_check(str(unavailable_status.get("label", "")) == "Indisponivel", "Cache não preservou status indisponível explícito.")
	dashboard.queue_free()
	await process_frame


func _check_discharge_local_database_barrier_fixtures() -> void:
	await _check_discharge_confirmed()
	await _check_discharge_local_database_refused_or_pending("error")
	await _check_discharge_local_database_refused_or_pending("pending")
	await _check_discharge_repeat_without_duplicate_movement()
	await _check_discharge_reopen_sync()


func _new_discharge_dashboard(db_name: String, local_database_mode: String = "success") -> DischargeDashboard:
	var dashboard := DischargeDashboard.new()
	root.add_child(dashboard)
	var store := StoreScript.new()
	store.configure("user://%s.json" % db_name, "%s.json" % db_name, "", false)
	store.replace_from_remote({
		"products": [{
			"sku": "DISCHARGE-FIXTURE",
			"imei": "930000001",
			"plate": "",
			"model": "V7.3.5",
			"operator": "Fixture",
			"tracker_status": "Estoque",
			"status": "Estoque",
			"stock": 1,
		}],
		"movements": [],
		"maintenance": [],
		"logs": [],
		"sms_logs": [],
	})
	dashboard.store = store
	dashboard.local_database_mode = local_database_mode
	return dashboard


func _check_discharge_confirmed() -> void:
	var dashboard := _new_discharge_dashboard("stock_discharge_confirmed")
	await process_frame
	var result: Dictionary = await dashboard._install_equipment_confirmed("DISCHARGE-FIXTURE", "DBA-001")
	var product: Dictionary = dashboard.store.get_product("DISCHARGE-FIXTURE")
	_check(bool(result.get("ok", false)), "Dar baixa confirmada não retornou sucesso após Banco local SQL.")
	_check(int(dashboard.local_database_calls) == 1, "Dar baixa confirmada não chamou Banco local SQL uma vez.")
	_check(int(dashboard.success_count) == 1, "Dar baixa confirmada não exibiu sucesso.")
	_check(int(dashboard.refresh_count) == 1, "Dar baixa confirmada não atualizou tabela após Banco local SQL.")
	_check(str(product.get("tracker_status", "")) == "Instalado", "Dar baixa confirmada não instalou fixture.")
	_check(_movement_count(dashboard.store) == 1, "Dar baixa confirmada não registrou movimento único.")
	dashboard.queue_free()
	await process_frame


func _check_discharge_local_database_refused_or_pending(mode: String) -> void:
	var dashboard := _new_discharge_dashboard("stock_discharge_%s" % mode, mode)
	await process_frame
	var result: Dictionary = await dashboard._install_equipment_confirmed("DISCHARGE-FIXTURE", "DBA-002")
	var product: Dictionary = dashboard.store.get_product("DISCHARGE-FIXTURE")
	_check(not bool(result.get("ok", false)), "Dar baixa com Banco local SQL %s virou sucesso falso." % mode)
	_check(bool(result.get("local_database_pending", false)), "Dar baixa com Banco local SQL %s não ficou pendente." % mode)
	_check(int(dashboard.success_count) == 0, "Dar baixa com Banco local SQL %s exibiu sucesso falso." % mode)
	_check(int(dashboard.error_count) == 1, "Dar baixa com Banco local SQL %s não informou pendência/erro." % mode)
	_check(int(dashboard.refresh_count) == 0, "Dar baixa com Banco local SQL %s atualizou tabela antes da confirmação." % mode)
	_check(str(product.get("tracker_status", "")) == "Instalado", "Dar baixa com Banco local SQL %s não preservou Store local." % mode)
	_check(str(product.get("remote_registration_status", "")) == "local_database_pending", "Dar baixa com Banco local SQL %s não marcou pendência local." % mode)
	_check(_movement_count(dashboard.store) == 1, "Dar baixa com Banco local SQL %s duplicou movimento inicial." % mode)
	dashboard.queue_free()
	await process_frame


func _check_discharge_repeat_without_duplicate_movement() -> void:
	var dashboard := _new_discharge_dashboard("stock_discharge_repeat")
	await process_frame
	var first: Dictionary = await dashboard._install_equipment_confirmed("DISCHARGE-FIXTURE", "DBA-003")
	var second: Dictionary = await dashboard._install_equipment_confirmed("DISCHARGE-FIXTURE", "DBA-003")
	_check(bool(first.get("ok", false)) and bool(second.get("ok", false)), "Repetição de Dar baixa idempotente não confirmou.")
	_check(_movement_count(dashboard.store) == 1, "Repetição de Dar baixa duplicou movimento.")
	_check(int(dashboard.local_database_calls) == 2, "Repetição de Dar baixa não reconfirmou Banco local SQL sem duplicar Store.")
	dashboard.queue_free()
	await process_frame


func _check_discharge_reopen_sync() -> void:
	var dashboard := _new_discharge_dashboard("stock_discharge_reopen")
	await process_frame
	var result: Dictionary = await dashboard._install_equipment_confirmed("DISCHARGE-FIXTURE", "DBA-004")
	var snapshot: Dictionary = dashboard.store.get_sync_snapshot()
	var reopened := StoreScript.new()
	reopened.configure("user://stock_discharge_reopen_after.json", "stock_discharge_reopen_after.json", "", false)
	reopened.replace_from_remote(snapshot)
	var products: Array[Dictionary] = reopened.get_products()
	_check(bool(result.get("ok", false)), "Dar baixa antes da reabertura não confirmou.")
	_check(products.size() == 1, "Reabertura da baixa não preservou produto único.")
	_check(str(products[0].get("tracker_status", "")) == "Instalado", "Reabertura da baixa perdeu status instalado.")
	_check(str(products[0].get("plate", "")) == "DBA-004", "Reabertura da baixa perdeu placa sintética.")
	dashboard.queue_free()
	await process_frame


func _movement_count(store: Variant) -> int:
	var snapshot: Dictionary = store.get_sync_snapshot()
	return (snapshot.get("movements", []) as Array).size()


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


func _check_local_database_only_branches_fixture() -> void:
	var dashboard := BranchDashboardScript.new()
	var sync := FakeBancoLocalSQLSync.new()
	var store := StoreScript.new()
	root.add_child(sync)
	root.add_child(dashboard)
	await process_frame
	dashboard.offline_local_database_sync = sync
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
	_check(products.size() == 1, "Filial Banco local SQL-only não carregou fixture do Banco local SQL simulado.")
	_check(str(products[0].get("plate", "")) == "FBO-001", "Filial Banco local SQL-only perdeu placa sintética.")
	_check(not dashboard._branch_supports_operational_apis(), "Filial Banco local SQL-only habilitou APIs operacionais.")
	_check(not dashboard._grupo_rs_api_reads_enabled(), "Filial Banco local SQL-only habilitou leitura Grupo RS.")
	_check(dashboard.offline_table_refreshes == 1, "Filial Banco local SQL-only não atualizou tabela após Banco local SQL simulado.")
	dashboard.queue_free()
	sync.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
