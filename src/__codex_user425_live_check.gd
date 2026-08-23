extends SceneTree


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

	var login: Dictionary = await dashboard.call("_grupo_rs_api_login_with_credentials", "lucasabm", "425")
	print("USER425_API_LOGIN=%s code=%s" % ["OK" if bool(login.get("ok", false)) else "FAIL", str(login.get("response_code", ""))])
	if not bool(login.get("ok", false)):
		_fail("Login API recusado para lucasabm/425: %s" % str(login.get("message", "")))
		return

	var nonce := str(int(Time.get_ticks_msec()) % 100000).pad_zeros(5)
	var serial := "024%s" % nonce.pad_zeros(6)
	var plate := "USR - %s" % nonce.substr(nonce.length() - 4, 4)
	var second_plate := "USR - %s" % str((nonce.to_int() + 1) % 10000).pad_zeros(4)
	var chip := "895554830000%s" % nonce.substr(nonce.length() - 6, 6)
	var phone := "31999%s" % nonce
	var request := {
		"serial": serial,
		"apn": "linksolutions.br",
		"chip_number": chip,
		"phone": phone,
		"model": "RS 300",
		"operator": "Tim",
		"plate": plate,
		"vehicle_model": "Carro",
		"vehicle_type": "Carro",
		"tracker_status": "Estoque",
		"api_vehicle_status": "A",
		"equipment_only": false,
	}
	print("USER425_TEST_SERIAL=%s plate=%s" % [serial, plate])
	var before: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
	if bool(before.get("ok", false)):
		_fail("A serie temporaria ja existe; teste cancelado.")
		return

	var registration: Dictionary = await dashboard.call("_perform_equipment_registration", request)
	print("USER425_REGISTRATION=%s" % JSON.stringify(registration))
	if not bool(registration.get("ok", false)):
		_fail("Cadastro/associacao nao confirmado: %s" % str(registration.get("message", registration)))
		return
	var equipment: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
	var vehicle: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", plate, serial, true)
	if not bool(equipment.get("ok", false)) or not bool(vehicle.get("ok", false)):
		_fail("Consulta final nao confirmou equipamento e associacao.")
		return

	var update_request := {"remote_serial": serial, "api_vehicle_status": "A"}
	var updated: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, vehicle.get("row", {}) as Dictionary, second_plate)
	print("USER425_PLATE_UPDATE=%s" % JSON.stringify(updated))
	if not bool(updated.get("ok", false)):
		_fail("Alteracao da placa nao confirmada: %s" % str(updated.get("message", updated)))
		return
	var changed: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", second_plate, serial, true)
	if not bool(changed.get("ok", false)):
		_fail("Nova placa nao encontrada na consulta API.")
		return

	var restored: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, changed.get("row", {}) as Dictionary, plate)
	print("USER425_PLATE_RESTORE=%s" % JSON.stringify(restored))
	if not bool(restored.get("ok", false)):
		_fail("Restauracao da placa nao confirmada: %s" % str(restored.get("message", restored)))
		return
	var final_check: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", plate, serial, true)
	if not bool(final_check.get("ok", false)):
		_fail("Associacao original nao encontrada na consulta final.")
		return
	print("USER425_LIVE_CHECK_OK cadastro=OK associacao=OK alteracao=OK restauracao=OK")
	dashboard.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
