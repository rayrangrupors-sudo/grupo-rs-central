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

	# Completa o registro criado pelo teste API-only, caso ele tenha ficado sem placa.
	var serial := "024003510"
	var plate := "TST - 3510"
	var request := {
		"serial": serial,
		"apn": "linksolutions.br",
		"chip_number": "895554830000003510",
		"phone": "3199903510",
		"model": "RS 300",
		"operator": "Tim",
		"plate": plate,
		"vehicle_model": "Carro",
		"vehicle_type": "Carro",
		"tracker_status": "Estoque",
		"api_vehicle_status": "A",
		"equipment_only": false,
	}

	var login: Dictionary = await dashboard.call("_grupo_rs_api_login")
	if not bool(login.get("ok", false)):
		_fail("Login API recusado: %s" % str(login.get("message", "")))
		return
	var equipment: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
	if not bool(equipment.get("ok", false)):
		_fail("O equipamento de teste nao foi encontrado: %s" % str(equipment.get("message", "")))
		return

	var registration: Dictionary = await dashboard.call("_perform_equipment_registration", request)
	print("RECOVERY_REGISTRATION=%s" % JSON.stringify(registration))
	if not bool(registration.get("ok", false)):
		_fail("A conclusao hibrida falhou: %s" % str(registration.get("message", registration)))
		return

	var vehicle: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", plate, serial, true)
	if not bool(vehicle.get("ok", false)):
		_fail("A associacao nao apareceu apos a conclusao: %s" % str(vehicle.get("message", "")))
		return
	var second_plate := "TST - 3511"
	var update_request := {"remote_serial": serial, "api_vehicle_status": "A"}
	var updated: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, vehicle.get("row", {}) as Dictionary, second_plate)
	if not bool(updated.get("ok", false)):
		_fail("A alteracao da placa falhou: %s" % str(updated.get("message", updated)))
		return
	var changed: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", second_plate, serial, true)
	if not bool(changed.get("ok", false)):
		_fail("A nova placa nao foi confirmada: %s" % str(changed.get("message", "")))
		return
	var restored: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, changed.get("row", {}) as Dictionary, plate)
	if not bool(restored.get("ok", false)):
		_fail("A restauracao da placa falhou: %s" % str(restored.get("message", restored)))
		return
	var final_check: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", plate, serial, true)
	if not bool(final_check.get("ok", false)):
		_fail("A placa original nao foi confirmada na consulta final.")
		return
	print("RECOVERY_LIVE_CHECK_OK cadastro=OK associacao=OK alteracao=OK restauracao=OK")
	dashboard.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
