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
	var login: Dictionary = await dashboard.call("_grupo_rs_api_login")
	if not bool(login.get("ok", false)):
		_fail("Login API recusado: %s" % str(login.get("message", "")))
		return

	var nonce := str(int(Time.get_ticks_msec()) % 900000 + 100000)
	var serial := "024%s" % nonce.substr(nonce.length() - 6, 6)
	var plate := "QAX - %s" % nonce.substr(nonce.length() - 4, 4)
	var second_plate := "QAY - %s" % nonce.substr(nonce.length() - 4, 4)
	var request := {
		"serial": serial,
		"apn": "linksolutions.br",
		"chip_number": "895554830000%s" % nonce,
		"phone": "31999%s" % nonce.substr(nonce.length() - 6, 6),
		"model": "RS 300",
		"operator": "Tim",
	}
	print("API_ONLY_TEST_SERIAL=%s PLATE=%s SECOND_PLATE=%s" % [serial, plate, second_plate])

	var before: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
	if bool(before.get("ok", false)):
		_fail("Identificador gerado ja existe; teste cancelado para proteger registro antigo.")
		return
	var equipment_result: Dictionary = await dashboard.call("_grupo_rs_api_register_equipment", request)
	print("API_ONLY_EQUIPMENT_CREATE ok=%s http=%s" % [str(equipment_result.get("ok", false)), str(equipment_result.get("response_code", 0))])
	if not bool(equipment_result.get("ok", false)):
		_fail("Cadastro real do equipamento pela API falhou: %s" % str(equipment_result.get("message", "")))
		return
	var equipment_row := equipment_result.get("row", {}) as Dictionary

	var edited := request.duplicate(true)
	edited["phone"] = "31988%s" % nonce.substr(nonce.length() - 6, 6)
	var equipment_edit: Dictionary = await dashboard.call("_grupo_rs_api_patch_equipment", edited, equipment_row)
	print("API_ONLY_EQUIPMENT_EDIT ok=%s http=%s" % [str(equipment_edit.get("ok", false)), str(equipment_edit.get("response_code", 0))])
	if not bool(equipment_edit.get("ok", false)):
		_fail("Alteracao do equipamento novo falhou: %s" % str(equipment_edit.get("message", "")))
		return
	equipment_row = equipment_edit.get("row", equipment_row) as Dictionary
	var equipment_restore: Dictionary = await dashboard.call("_grupo_rs_api_patch_equipment", request, equipment_row)
	print("API_ONLY_EQUIPMENT_RESTORE ok=%s http=%s" % [str(equipment_restore.get("ok", false)), str(equipment_restore.get("response_code", 0))])
	if not bool(equipment_restore.get("ok", false)):
		_fail("Restauracao do equipamento novo falhou: %s" % str(equipment_restore.get("message", "")))
		return
	equipment_row = equipment_restore.get("row", equipment_row) as Dictionary

	# Sem fallback: este request precisa ser aprovado pela rota veiculos.php.
	var vehicle_request := {
		"plate": plate,
		"serial": serial,
		"vehicle_type": "Carro",
		"api_vehicle_status": "Ativo",
	}
	var vehicle_result: Dictionary = await dashboard.call("_grupo_rs_api_register_vehicle", vehicle_request, equipment_row)
	var vehicle_http := int(vehicle_result.get("response_code", 0))
	print("API_ONLY_VEHICLE_CREATE ok=%s api=%s http=%d fallback=%s detail=%s" % [str(vehicle_result.get("ok", false)), str(vehicle_result.get("api", false)), vehicle_http, str(vehicle_result.get("fallback_web", false)), str(vehicle_result)])
	if not bool(vehicle_result.get("ok", false)):
		_fail("POST real de veiculos.php falhou: %s" % str(vehicle_result.get("message", "")))
		return
	var api_create_http_ok := vehicle_http >= 200 and vehicle_http < 300
	var created_row := vehicle_result.get("row", {}) as Dictionary
	if created_row.is_empty():
		_fail("API aceitou cadastro sem retornar linha para o teste.")
		return

	var update_request := {"remote_serial": serial, "api_vehicle_status": "Ativo"}
	var changed: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, created_row, second_plate)
	print("API_ONLY_VEHICLE_EDIT ok=%s http=%s" % [str(changed.get("ok", false)), str(changed.get("response_code", 0))])
	if not bool(changed.get("ok", false)):
		_fail("Alteracao real da placa de teste falhou: %s" % str(changed.get("message", "")))
		return
	var restored: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, changed.get("row", created_row) as Dictionary, plate)
	print("API_ONLY_VEHICLE_RESTORE ok=%s http=%s" % [str(restored.get("ok", false)), str(restored.get("response_code", 0))])
	if not bool(restored.get("ok", false)):
		_fail("Restauracao real da placa de teste falhou: %s" % str(restored.get("message", "")))
		return

	var final_equipment: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
	var final_vehicle: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", plate, serial, true, false)
	var final_ok := bool(final_equipment.get("ok", false)) and bool(final_vehicle.get("ok", false))
	print("API_ONLY_FINAL equipment=%s vehicle=%s final=%s" % [str(final_equipment.get("ok", false)), str(final_vehicle.get("ok", false)), str(final_ok)])
	dashboard.queue_free()
	if not final_ok:
		_fail("Consulta final nao confirmou aparelho e associacao restaurados.")
		return
	if not api_create_http_ok:
		_fail("A associacao funcionou, mas o POST da API ainda retornou HTTP %d; a correcao do 500 nao foi confirmada." % vehicle_http)
		return
	print("GRUPO_RS_API_VEHICLE_CREATE_REAL_CHECK_OK http=%d cadastro=OK associacao=OK alteracao=OK restauracao=OK" % vehicle_http)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
