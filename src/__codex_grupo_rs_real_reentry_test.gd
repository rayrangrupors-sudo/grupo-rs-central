extends SceneTree

class DashboardStub:
	extends "res://src/inventory_dashboard.gd"
	var test_serial := ""
	var test_plate := ""
	var created_equipment_id := 0
	var cleanup_messages: Array[String] = []

	func _cleanup_synthetic_record(serial: String, plate: String) -> Dictionary:
		var vehicle_cleanup: Dictionary = await _delete_modern_grupo_rs_vehicle_for_serial(serial)
		cleanup_messages.append(str(vehicle_cleanup.get("message", "")))
		var vehicle_rows_response: Dictionary = await _fetch_modern_grupo_rs_vehicle_rows_all_statuses(serial, true)
		if bool(vehicle_rows_response.get("ok", false)):
			var active_serial_rows: Array[Dictionary] = []
			for vehicle_row in vehicle_rows_response.get("rows", []) as Array[Dictionary]:
				if _search_key(str(vehicle_row.get("serial", ""))) != _search_key(serial):
					continue
				var vehicle_status := _search_key(str(vehicle_row.get("status", "")))
				if vehicle_status not in ["i", "inativo", "inactive"]:
					active_serial_rows.append(vehicle_row)
			if not active_serial_rows.is_empty():
				return {"ok": false, "message": "O vinculo veicular sintetico ainda esta ativo no portal."}
		var found: Dictionary = await _grupo_rs_api_find_equipment(serial, true)
		if not bool(found.get("ok", false)):
			return {"ok": true, "message": "O registro sintetico ja nao aparece na consulta."}
		var row := found.get("row", {}) as Dictionary
		var id := int(_grupo_rs_api_equipment_id_from_row(row, true))
		if id <= 0:
			return {"ok": false, "message": "O equipamento sintetico permaneceu sem ID para inativacao."}
		# A API oficial nao permite exclusao fisica de equipamentos (retorna 405);
		# o saneamento seguro e inativar o registro e retirar o vinculo veicular.
		var inactivated: Dictionary = await _grupo_rs_api_json_request(
			"/endpoints/equipamentos.php?id=%d" % id,
			HTTPClient.METHOD_PATCH,
			{"ativo": "I"},
			true
		)
		cleanup_messages.append("INATIVAR=%s" % str(inactivated.get("response_code", 0)))
		if not bool(inactivated.get("ok", false)):
			return {"ok": false, "message": "A API nao permitiu inativar o equipamento sintetico."}
		var after: Dictionary = await _grupo_rs_api_find_equipment(serial, true)
		if not bool(after.get("ok", false)):
			return {"ok": false, "message": "A leitura final nao encontrou o equipamento sintetico apos a inativacao."}
		var after_row := after.get("row", {}) as Dictionary
		var after_status := str(after_row.get("ativo", after_row.get("status", ""))).strip_edges().to_upper()
		if after_status not in ["I", "INATIVO", "INACTIVE"]:
			return {"ok": false, "message": "O equipamento sintetico permaneceu ativo apos a limpeza."}
		return {"ok": true, "message": "Vinculo removido e equipamento sintetico inativado (a API bloqueia exclusao fisica)."}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var dashboard := DashboardStub.new()
	root.add_child(dashboard)
	await process_frame
	var token := str(Time.get_unix_time_from_system())
	var suffix := int(Time.get_ticks_msec() % 900) + 100
	dashboard.test_serial = "99%07d" % (int(token) % 10000000)
	dashboard.test_plate = "ZZT - 9%02d" % (suffix % 100)
	var test_chip := "895554830000" + "%08d" % suffix
	var test_phone := "9899%07d" % suffix
	var changed_chip := "895554830001" + "%08d" % suffix
	var changed_phone := "9898%07d" % suffix

	# Nunca reutilize um identificador de teste existente.
	var existing: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", dashboard.test_serial, true)
	if bool(existing.get("ok", false)):
		_fail(dashboard, "O serial sintetico ja existe; teste abortado para nao tocar em registro anterior.")
		return
	var plate_collision: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", dashboard.test_plate, "", true)
	if bool(plate_collision.get("ok", false)):
		_fail(dashboard, "A placa sintetica ja existe; teste abortado para nao tocar em registro anterior.")
		return

	var registration_request := {
		"serial": dashboard.test_serial,
		"local_sku": dashboard.test_serial,
		"chip_number": test_chip,
		"phone": test_phone,
		"apn": "hinova.br",
		"model": "RS 300",
		"operator": "Tim",
		"plate": dashboard.test_plate,
		"client": "RS300",
		"vehicle_type": "Carro",
		"vehicle_model": "Veiculo QA",
		"vehicle_brand": "Marca QA",
		"vehicle_year": "2026",
		"vehicle_color": "Azul",
		"vehicle_chassis": "9BWQA%010d" % suffix,
		"vehicle_observation": "TESTE_AUTOMATIZADO_GRUPO_RS",
		"tracker_status": "Estoque",
		"equipment_only": false,
		"clear_vehicle_fields": false,
	}
	# Para o teste remoto completo, iniciamos pelo portal web. Assim o aparelho
	# fica imediatamente visivel para a etapa seguinte mesmo quando a API nova
	# ainda estiver propagando uma gravacao entre os servicos.
	var registration: Dictionary = await dashboard.call("_register_modern_equipment_via_web", registration_request)
	if not bool(registration.get("ok", false)):
		await dashboard.call("_cleanup_synthetic_record", dashboard.test_serial, dashboard.test_plate)
		_fail(dashboard, "Cadastro remoto sintetico falhou: %s" % str(registration.get("message", "")))
		return
	await create_timer(2.0).timeout
	print("REAL_REENTRY_REGISTRATION_OK transport=web")
	var portal_rows: Array[Dictionary] = await dashboard.call("_fetch_modern_grupo_rs_equipment_rows", dashboard.test_serial, true)
	print("REAL_REENTRY_PORTAL rows=%d plate=%s" % [portal_rows.size(), str(portal_rows[0].get("plate", "")) if not portal_rows.is_empty() else ""])
	var found: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", dashboard.test_serial, true)
	if not bool(found.get("ok", false)):
		await dashboard.call("_cleanup_synthetic_record", dashboard.test_serial, dashboard.test_plate)
		_fail(dashboard, "Cadastro aceito, mas a leitura final nao encontrou o equipamento sintetico.")
		return
	dashboard.created_equipment_id = int(dashboard.call("_grupo_rs_api_equipment_id_from_row", found.get("row", {}) as Dictionary, true))
	var initial_vehicle: Dictionary = await dashboard.call("_perform_modern_vehicle_modification", {
		"remote_serial": dashboard.test_serial,
		"serial": dashboard.test_serial,
		"old_plate": "",
		"new_plate": dashboard.test_plate,
		"vehicle_model": "Veiculo QA",
		"vehicle_brand": "Marca QA",
		"vehicle_year": "2026",
		"vehicle_color": "Azul",
		"vehicle_chassis": "9BWQA%010d" % suffix,
		"vehicle_observation": "TESTE_AUTOMATIZADO_GRUPO_RS",
		"client": "RS300",
		"vehicle_type": "Carro",
		"clear_vehicle_fields": false,
	})
	if not bool(initial_vehicle.get("ok", false)):
		await dashboard.call("_cleanup_synthetic_record", dashboard.test_serial, dashboard.test_plate)
		_fail(dashboard, "Cadastro web da placa sintetica falhou: %s" % str(initial_vehicle.get("message", "")))
		return
	var initial_rows: Dictionary = await dashboard.call("_fetch_modern_grupo_rs_vehicle_rows_all_statuses", dashboard.test_plate, true)
	var rows_debug: Array = initial_rows.get("rows", []) as Array
	print("REAL_REENTRY_VEHICLE rows=%d plate=%s serial=%s" % [rows_debug.size(), str(rows_debug[0].get("plate", "")) if not rows_debug.is_empty() else "", str(rows_debug[0].get("serial", "")) if not rows_debug.is_empty() else ""])

	# Modificacao real dos campos do equipamento: chip, telefone e APN preservados.
	var equipment_modify := {
		"serial": dashboard.test_serial,
		"remote_serial": dashboard.test_serial,
		"old_plate": dashboard.test_plate,
		"new_plate": dashboard.test_plate,
		"vehicle_target_plate": dashboard.test_plate,
		"apply_vehicle_policy": false,
		"equipment_fields_changed": true,
		"chip_number": changed_chip,
		"phone": changed_phone,
		"apn": "hinova.br",
		"model": "RS 300",
		"operator": "Tim",
		"clear_vehicle_fields": false,
	}
	var equipment_change: Dictionary = await dashboard.call("_perform_equipment_modification", equipment_modify, null)
	if not bool(equipment_change.get("ok", false)):
		await dashboard.call("_cleanup_synthetic_record", dashboard.test_serial, dashboard.test_plate)
		_fail(dashboard, "Modificacao real de chip/telefone falhou: %s" % str(equipment_change.get("message", "")))
		return

	# Reentrada com placa e dados de veiculo novos, sem apagar o cadastro anterior.
	# A placa de teste e escolhida por consulta remota, evitando colisao com
	# qualquer dado sintetico deixado por uma execucao interrompida.
	var new_plate := ""
	for candidate_offset in range(20):
		var candidate := "ZZX - %04d" % ((int(token) + suffix + candidate_offset) % 10000)
		var candidate_collision: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", candidate, "", true)
		if not bool(candidate_collision.get("ok", false)):
			new_plate = candidate
			break
	if new_plate == "":
		await dashboard.call("_cleanup_synthetic_record", dashboard.test_serial, dashboard.test_plate)
		_fail(dashboard, "Nao foi possivel reservar uma placa sintetica livre para a reentrada.")
		return
	var vehicle_change := {
		"serial": dashboard.test_serial,
		"remote_serial": dashboard.test_serial,
		"old_plate": dashboard.test_plate,
		"new_plate": new_plate,
		"vehicle_target_plate": new_plate,
		"apply_vehicle_policy": true,
		"equipment_fields_changed": false,
		"vehicle_association_requested": true,
		"clear_vehicle_fields": false,
		"vehicle_model": "Veiculo QA 2",
		"vehicle_brand": "Marca QA 2",
		"vehicle_year": "2025",
		"vehicle_color": "Prata",
		"vehicle_chassis": "9BWQA2%07d" % suffix,
		"vehicle_observation": "TESTE_REENTRADA_AUTOMATIZADO",
		"client": "RS300",
		"vehicle_type": "Carro",
	}
	var vehicle_change_result: Dictionary = await dashboard.call("_perform_equipment_modification", vehicle_change, null)
	if not bool(vehicle_change_result.get("ok", false)):
		print("REAL_REENTRY_CHANGE_RESULT %s" % str(vehicle_change_result))
		await dashboard.call("_cleanup_synthetic_record", dashboard.test_serial, dashboard.test_plate)
		_fail(dashboard, "Reentrada real com nova placa/chassi falhou: %s" % str(vehicle_change_result.get("message", "")))
		return

	# Simula cancelamento: limpeza explicita do vinculo e retorno ao estoque.
	var return_to_stock := {
		"serial": dashboard.test_serial,
		"remote_serial": dashboard.test_serial,
		"old_plate": new_plate,
		"new_plate": "",
		"vehicle_target_plate": "",
		"apply_vehicle_policy": false,
		"clear_vehicle_association": true,
		"clear_vehicle_fields": true,
		"equipment_fields_changed": false,
		"tracker_status": "Estoque",
	}
	var stock_result: Dictionary = await dashboard.call("_perform_equipment_modification", return_to_stock, null)
	if not bool(stock_result.get("ok", false)):
		await dashboard.call("_cleanup_synthetic_record", dashboard.test_serial, new_plate)
		_fail(dashboard, "Retorno sintetico ao estoque falhou: %s" % str(stock_result.get("message", "")))
		return
	var cleanup: Dictionary = await dashboard.call("_cleanup_synthetic_record", dashboard.test_serial, new_plate)
	if not bool(cleanup.get("ok", false)):
		_fail(dashboard, "O fluxo funcionou, mas a limpeza do equipamento sintetico nao foi confirmada: %s" % str(cleanup.get("message", "")))
		return
	print("REAL_REENTRY_CLEANUP %s" % str(cleanup.get("message", "")))
	print("REAL_REENTRY_TEST_OK serial=%s plate_initial=%s plate_reassigned=%s cleanup=true" % [dashboard.test_serial, dashboard.test_plate, new_plate])
	dashboard.queue_free()
	quit(0)

func _fail(dashboard: Node, message: String) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		var cleanup_steps: Array = dashboard.get("cleanup_messages") as Array
		print("REAL_REENTRY_FAIL serial=%s cleanup_steps=%s" % [str(dashboard.get("test_serial")), "; ".join(cleanup_steps)])
	push_error(message)
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	quit(1)
