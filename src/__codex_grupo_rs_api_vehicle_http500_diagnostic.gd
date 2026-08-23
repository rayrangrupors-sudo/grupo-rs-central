extends SceneTree


const SERIAL := "024103567"
const FIRST_PLATE := "QAX - 3567"
const TEST_PLATE := "QAZ - 3567"
const RESTORE_PLATE := "QAX - 3567"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		_fail("Dashboard nao compilou.")
		return
	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")
	var login: Dictionary = await dashboard.call("_grupo_rs_api_login")
	if not bool(login.get("ok", false)):
		_fail("Login recusado: %s" % str(login.get("message", "")))
		return
	var equipment: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", SERIAL, true)
	if not bool(equipment.get("ok", false)):
		_fail("Equipamento de teste nao localizado: %s" % str(equipment.get("message", "")))
		return
	var equipment_row := equipment.get("row", {}) as Dictionary
	var equipment_id := int(dashboard.call("_grupo_rs_api_equipment_id_from_row", equipment_row, true))
	if equipment_id <= 0:
		_fail("Equipamento de teste sem id.")
		return
	var old_lookup: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", FIRST_PLATE, SERIAL, true, false)
	var before_lookup: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", TEST_PLATE, SERIAL, true, false)
	print("DIAG_BEFORE first=%s test=%s equipment=%d" % [str(old_lookup.get("ok", false)), str(before_lookup.get("ok", false)), equipment_id])
	if bool(before_lookup.get("ok", false)):
		_fail("Placa diagnostica ja existe; teste interrompido.")
		return
	var payload := {"placa": dashboard.call("_normalize_location_plate", TEST_PLATE), "status": "A", "codTipoVeiculo": 1, "codEquipamento": equipment_id}
	var response: Dictionary = await dashboard.call("_grupo_rs_api_json_request", "/endpoints/veiculos.php", HTTPClient.METHOD_POST, payload)
	print("DIAG_POST http=%s ok=%s body=%s" % [str(response.get("response_code", 0)), str(response.get("ok", false)), str(response.get("body", "")).substr(0, 1000)])
	var after_lookup: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", TEST_PLATE, SERIAL, true, false)
	print("DIAG_AFTER test=%s row=%s" % [str(after_lookup.get("ok", false)), str(after_lookup.get("row", {}))])
	var api_http_ok := int(response.get("response_code", 0)) >= 200 and int(response.get("response_code", 0)) < 300
	if bool(after_lookup.get("ok", false)):
		var row := after_lookup.get("row", {}) as Dictionary
		var restore: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", {"remote_serial": SERIAL, "api_vehicle_status": "Ativo"}, row, RESTORE_PLATE)
		print("DIAG_RESTORE ok=%s http=%s" % [str(restore.get("ok", false)), str(restore.get("response_code", 0))])
	if api_http_ok:
		print("GRUPO_RS_API_VEHICLE_HTTP500_DIAGNOSTIC_OK http=%s" % str(response.get("response_code", 0)))
		dashboard.queue_free()
		quit(0)
		return
	_fail("POST ainda nao esta corrigido: HTTP %s; associacao_pos_post=%s" % [str(response.get("response_code", 0)), str(after_lookup.get("ok", false))])


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
