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

	var nonce := str(int(Time.get_ticks_msec()) % 100000).pad_zeros(5)
	var serial := "024%s" % nonce.pad_zeros(6)
	var plate := "TST - %s" % nonce.substr(nonce.length() - 4, 4)
	var second_plate := "TST - %s" % str((nonce.to_int() + 1) % 10000).pad_zeros(4)
	var chip := "895554830000%s" % nonce.substr(nonce.length() - 8, 8)
	var phone := "31999%s" % nonce
	var request := {
		"serial": serial,
		"apn": "linksolutions.br",
		"chip_number": chip,
		"phone": phone,
		"model": "RS 300",
		"operator": "Tim",
	}
	print("API_REGISTRATION_TEST_SERIAL=%s" % serial)
	print("API_REGISTRATION_TEST_PLATE=%s" % plate)

	var before: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
	if bool(before.get("ok", false)):
		_fail("A serie gerada ja existe; teste interrompido para nao alterar um equipamento existente.")
		return

	var equipment_result: Dictionary = await dashboard.call("_grupo_rs_api_register_equipment", request)
	print("API_REGISTRATION_EQUIPMENT_CREATE=%s code=%s message=%s" % ["OK" if bool(equipment_result.get("ok", false)) else "FAIL", str(equipment_result.get("response_code", "")), str(equipment_result.get("message", ""))])
	if not bool(equipment_result.get("ok", false)):
		_fail("A API nao confirmou o cadastro do equipamento novo.")
		return

	var equipment_row := equipment_result.get("row", {}) as Dictionary
	# Edita e restaura somente o equipamento criado por este teste. Nenhum
	# equipamento preexistente entra neste ciclo.
	var edited_request := request.duplicate(true)
	edited_request["phone"] = "31998%s" % nonce
	var equipment_edit: Dictionary = await dashboard.call("_grupo_rs_api_patch_equipment", edited_request, equipment_row)
	print("API_REGISTRATION_EQUIPMENT_UPDATE=%s code=%s message=%s" % ["OK" if bool(equipment_edit.get("ok", false)) else "FAIL", str(equipment_edit.get("response_code", "")), str(equipment_edit.get("message", ""))])
	if not bool(equipment_edit.get("ok", false)):
		_fail("O equipamento novo foi criado, mas a alteracao do telefone nao foi confirmada.")
		return
	equipment_row = equipment_edit.get("row", equipment_row) as Dictionary
	var equipment_restore: Dictionary = await dashboard.call("_grupo_rs_api_patch_equipment", request, equipment_row)
	print("API_REGISTRATION_EQUIPMENT_RESTORE=%s code=%s message=%s" % ["OK" if bool(equipment_restore.get("ok", false)) else "FAIL", str(equipment_restore.get("response_code", "")), str(equipment_restore.get("message", ""))])
	if not bool(equipment_restore.get("ok", false)):
		_fail("A alteracao do equipamento passou, mas os dados originais do teste nao foram restaurados.")
		return
	equipment_row = equipment_restore.get("row", equipment_row) as Dictionary
	var vehicle_request := {
		"plate": plate,
		"serial": serial,
		"vehicle_model": "Carro",
		"vehicle_type": "Carro",
		"api_vehicle_status": "Ativo",
	}
	var vehicle_result: Dictionary = await dashboard.call("_grupo_rs_api_register_vehicle", vehicle_request, equipment_row)
	print("API_REGISTRATION_VEHICLE_CREATE=%s api=%s fallback=%s code=%s message=%s detail=%s" % ["OK" if bool(vehicle_result.get("ok", false)) else "FAIL", str(vehicle_result.get("api", false)), str(vehicle_result.get("fallback_web", false)), str(vehicle_result.get("response_code", "")), str(vehicle_result.get("message", "")), str(vehicle_result)])
	if not bool(vehicle_result.get("ok", false)):
		if not bool(vehicle_result.get("fallback_web", false)):
			_fail("O equipamento foi criado pela API, mas a placa/associacao nao foi confirmada e nao houve fallback seguro.")
			return
		# O POST da API falhou de forma recuperavel: repete o mesmo cadastro pelo
		# fluxo publico, que deve usar o portal apenas neste caso.
		var fallback_request := request.duplicate(true)
		fallback_request["plate"] = plate
		fallback_request["vehicle_model"] = "Carro"
		fallback_request["vehicle_type"] = "Carro"
		fallback_request["api_vehicle_status"] = "Ativo"
		var fallback_result: Dictionary = await dashboard.call("_perform_equipment_registration", fallback_request)
		print("API_REGISTRATION_WEB_FALLBACK=%s api_vehicle=%s message=%s" % ["OK" if bool(fallback_result.get("ok", false)) else "FAIL", str(fallback_result.get("api_vehicle", false)), str(fallback_result.get("message", ""))])
		if not bool(fallback_result.get("ok", false)):
			_fail("A API falhou e o fallback web nao confirmou a placa/associacao nova.")
			return
		vehicle_result = await dashboard.call("_grupo_rs_api_find_vehicle", plate, serial, true)
		if not bool(vehicle_result.get("ok", false)):
			_fail("O fallback web concluiu, mas a API nao encontrou a associacao para continuar o teste de alteracao.")
			return

	var created_row := vehicle_result.get("row", {}) as Dictionary
	var update_request := {"remote_serial": serial, "api_vehicle_status": "Ativo"}
	var update_result: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, created_row, second_plate)
	print("API_REGISTRATION_VEHICLE_UPDATE=%s code=%s message=%s" % ["OK" if bool(update_result.get("ok", false)) else "FAIL", str(update_result.get("response_code", "")), str(update_result.get("message", ""))])
	if not bool(update_result.get("ok", false)):
		_fail("A placa foi criada pela API, mas a alteracao nao foi confirmada.")
		return

	var updated_row := update_result.get("row", {}) as Dictionary
	var restore_result: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, updated_row, plate)
	print("API_REGISTRATION_VEHICLE_RESTORE=%s code=%s message=%s" % ["OK" if bool(restore_result.get("ok", false)) else "FAIL", str(restore_result.get("response_code", "")), str(restore_result.get("message", ""))])
	if not bool(restore_result.get("ok", false)):
		_fail("A alteracao passou, mas a placa de teste nao foi restaurada.")
		return

	var final_equipment: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
	var final_vehicle: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", plate, serial, true)
	if not bool(final_equipment.get("ok", false)) or not bool(final_vehicle.get("ok", false)):
		_fail("A consulta final nao confirmou equipamento e associacao API.")
		return
	print("API_REGISTRATION_FINAL=OK equipment=%s vehicle=%s serial=%s plate=%s" % [str(_id(final_equipment.get("row", {}))), str(_id(final_vehicle.get("row", {}))), serial, plate])
	print("API_REGISTRATION_LIVE_CHECK_OK cadastro=OK alteracao=OK associacao=OK")
	dashboard.queue_free()
	quit(0)


func _id(raw: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return ""
	var row := raw as Dictionary
	for key in ["codEquipamento", "equipment_id", "id", "vehicle_id"]:
		if row.has(key):
			return str(row.get(key, ""))
	return ""


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
