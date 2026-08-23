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

	var nonce := str(int(Time.get_unix_time_from_system()) % 10000).pad_zeros(4)
	var serial := "02439%s" % nonce
	var plate := "TST - %s" % nonce
	var chip := "895554830000%s" % nonce
	var phone := "319999%s" % nonce
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

	print("REMOTE_REGISTRATION_TEST_SERIAL=%s" % serial)
	print("REMOTE_REGISTRATION_TEST_PLATE=%s" % plate)
	print("REMOTE_REGISTRATION_TEST_CHIP_SUFFIX=%s" % nonce)
	var login: Dictionary = await dashboard.call("_grupo_rs_api_login")
	if not bool(login.get("ok", false)):
		_fail("Login API recusado: %s" % str(login.get("message", "")))
		return
	print("REMOTE_REGISTRATION_API_LOGIN=OK")

	var before: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
	if bool(before.get("ok", false)):
		_fail("A serie de teste ja existe; o teste foi interrompido para nao alterar um equipamento existente.")
		return

	print("REMOTE_REGISTRATION_BEFORE_WORKFLOW")
	var raw_result: Variant = await dashboard.call("_perform_equipment_registration", request)
	print("REMOTE_REGISTRATION_AFTER_WORKFLOW type=%s" % typeof(raw_result))
	var result: Dictionary = raw_result as Dictionary
	print("REMOTE_REGISTRATION_RESULT=%s" % JSON.stringify(result))
	if not bool(result.get("ok", false)):
		_fail("Cadastro remoto nao confirmou equipamento e veiculo: %s" % str(result.get("message", result)))
		return

	var equipment_check: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
	if not bool(equipment_check.get("ok", false)):
		_fail("O equipamento foi aceito, mas nao foi encontrado na consulta final.")
		return
	var vehicle_check: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", plate, serial, true)
	if not bool(vehicle_check.get("ok", false)):
		_fail("A placa foi aceita, mas a associacao nao foi encontrada na consulta final: %s" % str(vehicle_check.get("message", "")))
		return

	var created_vehicle := vehicle_check.get("row", {}) as Dictionary
	var second_plate := "TST - %s" % str((nonce.to_int() + 1) % 10000).pad_zeros(4)
	if second_plate == plate:
		second_plate = "TST - %s" % str((nonce.to_int() + 2) % 10000).pad_zeros(4)
	print("REMOTE_REGISTRATION_UPDATE_PLATE=%s" % second_plate)
	var update_request := {
		"remote_serial": serial,
		"api_vehicle_status": "Ativo",
	}
	var updated_vehicle: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, created_vehicle, second_plate)
	if not bool(updated_vehicle.get("ok", false)):
		_fail("O cadastro foi criado, mas a alteracao da placa/associacao falhou: %s" % str(updated_vehicle.get("message", updated_vehicle)))
		return
	var updated_row := updated_vehicle.get("row", {}) as Dictionary
	var updated_serial := _row_value(updated_row, ["serial", "numeroSerie", "numero_serie"])
	if _digits_only(updated_serial) != _digits_only(serial):
		_fail("A nova placa foi confirmada, mas retornou outro equipamento: %s" % updated_serial)
		return
	var updated_check: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", second_plate, serial, true)
	if not bool(updated_check.get("ok", false)):
		_fail("A alteracao foi aceita, mas a nova associacao nao apareceu na consulta final.")
		return
	print("REMOTE_REGISTRATION_UPDATE=OK plate=%s serial=%s" % [second_plate, serial])

	var restored_vehicle: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, updated_check.get("row", {}) as Dictionary, plate)
	if not bool(restored_vehicle.get("ok", false)):
		_fail("A alteracao foi confirmada, mas nao foi possivel restaurar a placa de teste: %s" % str(restored_vehicle.get("message", restored_vehicle)))
		return
	var restored_check: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", plate, serial, true)
	if not bool(restored_check.get("ok", false)):
		_fail("A placa original nao foi restaurada apos o teste: %s" % str(restored_check.get("message", "")))
		return
	print("REMOTE_REGISTRATION_RESTORE=OK plate=%s serial=%s" % [plate, serial])

	var vehicle := vehicle_check.get("row", {}) as Dictionary
	print("REMOTE_REGISTRATION_EQUIPMENT=OK id=%s serial=%s" % [str(_row_value(equipment_check.get("row", {}), ["codEquipamento", "id"])), serial])
	print("REMOTE_REGISTRATION_VEHICLE=OK id=%s plate=%s equipment=%s" % [str(vehicle.get("vehicle_id", "")), str(vehicle.get("plate", "")), str(vehicle.get("equipment_id", ""))])
	print("REMOTE_REGISTRATION_LIVE_CHECK_OK cadastro=OK alteracao=OK associacao=OK")
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


func _digits_only(value: String) -> String:
	var result := ""
	for character in value:
		if character >= "0" and character <= "9":
			result += character
	return result


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
