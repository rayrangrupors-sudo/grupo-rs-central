extends SceneTree


const TEST_SERIAL := "024393169"
const ORIGINAL_PLATE := "TST - 3169"
const PROBE_PLATE := "TST - 3171"


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
		_fail("Login API recusado: %s" % str(login.get("message", "")))
		return
	print("FULL_API_LOGIN=OK")

	var equipment_lookup: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", TEST_SERIAL, true)
	if not bool(equipment_lookup.get("ok", false)):
		_fail("Equipamento de teste nao foi encontrado pela API: %s" % str(equipment_lookup.get("message", "")))
		return
	var equipment_row := equipment_lookup.get("row", {}) as Dictionary
	var equipment_request := {
		"serial": TEST_SERIAL,
		"apn": "linksolutions.br",
		"chip_number": "8955548300003169",
		"phone": "3199993169",
		"model": "RS 300",
		"operator": "Tim",
	}
	var equipment_write: Dictionary = await dashboard.call("_grupo_rs_api_patch_equipment", equipment_request, equipment_row)
	print("FULL_API_EQUIPMENT_UPDATE=%s code=%s message=%s" % ["OK" if bool(equipment_write.get("ok", false)) else "FAIL", str(equipment_write.get("response_code", "")), str(equipment_write.get("message", ""))])
	if not bool(equipment_write.get("ok", false)):
		_fail("A API nao confirmou a alteracao do equipamento.")
		return

	var original_lookup: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", ORIGINAL_PLATE, TEST_SERIAL, true)
	if not bool(original_lookup.get("ok", false)):
		_fail("A associacao original nao foi encontrada pela API: %s" % str(original_lookup.get("message", "")))
		return
	var original_row := original_lookup.get("row", {}) as Dictionary

	var vehicle_request := {
		"plate": PROBE_PLATE,
		"serial": TEST_SERIAL,
		"vehicle_model": "Carro",
		"vehicle_type": "Carro",
		"api_vehicle_status": "Ativo",
	}
	var create_result: Dictionary = await dashboard.call("_grupo_rs_api_register_vehicle", vehicle_request, equipment_write.get("row", equipment_row))
	print("FULL_API_VEHICLE_CREATE=%s api=%s fallback=%s code=%s message=%s" % ["OK" if bool(create_result.get("ok", false)) else "FAIL", str(create_result.get("api", false)), str(create_result.get("fallback_web", false)), str(create_result.get("response_code", "")), str(create_result.get("message", ""))])
	if not bool(create_result.get("ok", false)):
		_fail("A API nao confirmou a criacao da placa/associacao; nenhum fallback web foi executado.")
		return

	var created_row := create_result.get("row", {}) as Dictionary
	var update_request := {"remote_serial": TEST_SERIAL, "api_vehicle_status": "Ativo"}
	var restore_result: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, created_row, ORIGINAL_PLATE)
	print("FULL_API_VEHICLE_RESTORE=%s code=%s message=%s" % ["OK" if bool(restore_result.get("ok", false)) else "FAIL", str(restore_result.get("response_code", "")), str(restore_result.get("message", ""))])
	if not bool(restore_result.get("ok", false)):
		_fail("A placa de teste foi criada, mas a restauracao pela API falhou.")
		return

	var final_lookup: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", ORIGINAL_PLATE, TEST_SERIAL, true)
	if not bool(final_lookup.get("ok", false)):
		_fail("A associacao original nao foi confirmada apos a restauracao.")
		return
	print("FULL_API_ASSOCIATION=OK original=%s probe=%s restored=%s" % [ORIGINAL_PLATE, PROBE_PLATE, str(_row_value(final_lookup.get("row", {}), ["serial", "numeroSerie", "numero_serie"]))])
	print("FULL_API_LIVE_CHECK_OK cadastro_aparelho=OK alteracao_placa=OK associacao=OK")
	dashboard.queue_free()
	quit(0)


func _row_value(raw: Variant, keys: Array[String]) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return ""
	var row := raw as Dictionary
	for key in keys:
		if row.has(key):
			return str(row.get(key, ""))
	return ""


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
