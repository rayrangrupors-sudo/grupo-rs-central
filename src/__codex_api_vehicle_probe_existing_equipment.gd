extends SceneTree


const SERIAL := "024005144"


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

	var login: Dictionary = await dashboard.call("_grupo_rs_api_login_with_retry", "lucasabm", "425")
	if not bool(login.get("ok", false)):
		_fail("Login API recusado code=%s message=%s" % [str(login.get("response_code", "")), str(login.get("message", ""))])
		return
	print("API_VEHICLE_PROBE_LOGIN=OK")

	var equipment: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", SERIAL, true)
	if not bool(equipment.get("ok", false)):
		_fail("Equipamento de teste nao localizado.")
		return
	var equipment_row := equipment.get("row", {}) as Dictionary
	var equipment_id := int(dashboard.call("_grupo_rs_api_equipment_id_from_row", equipment_row, true))
	if equipment_id <= 0:
		_fail("Equipamento de teste sem codigo para associacao.")
		return
	print("API_VEHICLE_PROBE_EQUIPMENT=OK id=%d serial=%s" % [equipment_id, SERIAL])

	var suffix := str(int(Time.get_ticks_msec()) % 9000 + 1000)
	var first_plate := "ZRT - %s" % suffix
	var second_plate := "ZRV - %s" % suffix
	print("API_VEHICLE_PROBE_BEFORE_LOOKUP=%s" % Time.get_time_string_from_system())
	var existing: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", first_plate, SERIAL, true, false)
	print("API_VEHICLE_PROBE_AFTER_LOOKUP=%s ok=%s code=%s" % [Time.get_time_string_from_system(), str(existing.get("ok", false)), str(existing.get("response_code", ""))])
	var vehicle: Dictionary
	if bool(existing.get("ok", false)):
		vehicle = existing
		print("API_VEHICLE_PROBE_ASSOCIATION=EXISTING")
	else:
		var request := {"plate": first_plate, "serial": SERIAL, "vehicle_model": "Carro", "vehicle_type": "Carro", "api_vehicle_status": "A"}
		print("API_VEHICLE_PROBE_BEFORE_REGISTER=%s plate=%s" % [Time.get_time_string_from_system(), first_plate])
		vehicle = await dashboard.call("_grupo_rs_api_register_vehicle", request, equipment_row)
		print("API_VEHICLE_PROBE_AFTER_REGISTER=%s" % Time.get_time_string_from_system())
		if not bool(vehicle.get("ok", false)):
			print("API_VEHICLE_PROBE_REGISTER_RESULT=%s" % JSON.stringify(vehicle))
			_fail("Cadastro da placa pela API falhou: %s" % str(vehicle.get("message", "")))
			return
		print("API_VEHICLE_PROBE_CREATE=OK api=%s" % str(vehicle.get("api", false)))

	var vehicle_row: Dictionary = vehicle.get("row", {}) as Dictionary
	var update_request := {"remote_serial": SERIAL, "api_vehicle_status": "A"}
	var updated: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, vehicle_row, second_plate)
	if not bool(updated.get("ok", false)):
		_fail("Alteracao da placa pela API falhou: %s" % str(updated.get("message", "")))
		return
	print("API_VEHICLE_PROBE_UPDATE=OK")

	var changed_row: Dictionary = updated.get("row", {}) as Dictionary
	var restored: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, changed_row, first_plate)
	if not bool(restored.get("ok", false)):
		_fail("Restauracao da placa de teste falhou: %s" % str(restored.get("message", "")))
		return
	var final_check: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", first_plate, SERIAL, true)
	if not bool(final_check.get("ok", false)):
		_fail("Associacao final nao foi confirmada.")
		return
	print("API_VEHICLE_PROBE_RESTORE=OK")
	print("API_VEHICLE_PROBE_LIVE_CHECK_OK cadastro=OK associacao=OK alteracao=OK restauracao=OK")
	dashboard.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
