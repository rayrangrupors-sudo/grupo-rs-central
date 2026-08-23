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
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	var api_status_product: Dictionary = {"tracker_status": "Estoque"}
	var maintenance_product: Dictionary = {"tracker_status": "Manutencao"}
	var platform_status_product: Dictionary = {"tracker_status": "Instalado"}
	if str(dashboard.call("_grupo_rs_location_source_mode_for_product", api_status_product)) != "api" \
		or str(dashboard.call("_grupo_rs_location_source_mode_for_product", maintenance_product)) != "api" \
		or str(dashboard.call("_grupo_rs_location_source_mode_for_product", platform_status_product)) != "api":
		_fail("Roteamento por status esta incorreto.")
		return

	if str(dashboard.call("_grupo_rs_api_url", "/endpoints/localizacao.php")) != "https://novogrupors.ddns.net/api_rest_app/endpoints/localizacao.php":
		_fail("URL da API oficial foi montada incorretamente.")
		return
	var api_location: Dictionary = dashboard.call("_grupo_rs_api_location_result", "024291507", "AAA - 0A00", "RS300", {
		"plate": "AAA - 0A00",
		"lat": "-5.5264",
		"lng": "-47.4919",
	})
	if not bool(api_location.get("ok", false)) or str(api_location.get("source", "")) != "grupo_rs_api":
		_fail("Localizacao da API nova nao foi normalizada.")
		return
	var battery_fields: Dictionary = dashboard.call("_grupo_rs_api_normalize_location", {
		"Bateria": 12,
		"bateriaInterna": null,
	})
	if str(battery_fields.get("battery_voltage", "")) != "12" or str(battery_fields.get("battery_internal", "")) != "":
		_fail("Tensao e bateria interna foram misturadas na normalizacao da API.")
		return
	var token: String = dashboard.call("_grupo_rs_api_find_token", {"data": {"access_token": "jwt-contract-test"}})
	if token != "jwt-contract-test":
		_fail("Token JWT aninhado nao foi localizado.")
		return

	var payload := {"data": {"veiculos": [{
		"codVeiculo": 13205,
		"placa": "AAA - 0A00",
		"numeroSerie": "024291507",
		"latitude": -5.5264,
		"longitude": -47.4919,
		"ignicao": 0,
		"velocidade": 0,
		"ultima_comunicacao": "04/08/2026 12:00:00",
	}]}}
	var rows: Array[Dictionary] = dashboard.call("_grupo_rs_api_extract_rows", payload)
	if rows.size() != 1:
		_fail("Lista de veiculos embrulhada em data nao foi extraida.")
		return
	var normalized: Dictionary = dashboard.call("_grupo_rs_api_normalize_location", rows[0])
	if str(normalized.get("serial", "")) != "024291507" \
			or str(normalized.get("vehicle_id", "")) != "13205" \
			or str(normalized.get("ignition", "")) != "0":
		_fail("Campos de serie, veiculo ou ignicao nao foram normalizados.")
		return
	if str(dashboard.call("_format_grupo_rs_vehicle_plate_for_display", "AAA016")) != "AAA - 016" \
			or str(dashboard.call("_format_grupo_rs_vehicle_plate_for_display", "AAA-016")) != "AAA - 016" \
			or str(dashboard.call("_format_grupo_rs_vehicle_plate_for_display", "AAA - 016")) != "AAA - 016":
		_fail("A placa nao foi padronizada para o formato AAA - 016.")
		return
	var current_api_fields: Dictionary = dashboard.call("_grupo_rs_api_normalize_location", {
		"StatusIgnicao": 1,
		"SinalGPS": 1,
		"Hodometro": 3846,
		"Direcao": 76,
		"TipoEvento": 72,
	})
	if str(current_api_fields.get("ignition", "")) != "1" \
			or str(current_api_fields.get("gps_signal", "")) != "1" \
			or str(current_api_fields.get("odometer", "")) != "3846" \
			or str(current_api_fields.get("heading", "")) != "76" \
			or str(current_api_fields.get("event_type", "")) != "72":
		_fail("Campos reais da API nova nao foram normalizados.")
		return

	var association_row: Dictionary = dashboard.call("_grupo_rs_api_normalize_location", {
		"codVeiculo": 77,
		"codEquipamento": 9021,
		"placa": "AAA - C31",
		"numeroSerie": "024288081",
		"modelo": "HB20",
		"ano": 2018,
	})
	if str(association_row.get("vehicle_id", "")) != "77" \
		or str(association_row.get("equipment_id", "")) != "9021" \
		or int(dashboard.call("_grupo_rs_api_equipment_id_from_row", {"codEquipamento": 9021})) != 9021 \
		or int(dashboard.call("_grupo_rs_api_equipment_id_from_row", {"id": 9021}, true)) != 9021 \
		or int(dashboard.call("_grupo_rs_api_equipment_id_from_row", {"id": 77})) != 0:
		_fail("Os identificadores de veiculo e equipamento nao foram preservados para a associacao.")
		return
	var nested_association: Dictionary = dashboard.call("_grupo_rs_api_normalize_location", {
		"CodVeiculo": 78.0,
		"Placa": "AAA - C32",
		"equipamento": {"codEquipamento": 9022.0, "numeroSerie": "024288082"},
	})
	if str(nested_association.get("serial", "")) != "024288082" \
			or str(nested_association.get("vehicle_id", "")) != "78" \
			or str(nested_association.get("equipment_id", "")) != "9022":
		_fail("O objeto equipamento da resposta nova nao foi lido corretamente.")
		return
	var create_payload: Dictionary = dashboard.call("_grupo_rs_api_vehicle_payload", {
		"plate": "AAA - C31",
		"vehicle_model": "HB20",
		"vehicle_year": "2018",
		"api_vehicle_status": "Manutencao",
	}, {}, "AAA - C31", 9021)
	if str(create_payload.get("placa", "")) != "AAAC31" \
			or str(create_payload.get("modelo", "")) != "HB20" \
			or str(create_payload.get("ano", "")) != "2018" \
			or str(create_payload.get("status", "")) != "A" \
			or int(create_payload.get("codEquipamento", 0)) != 9021:
		_fail("O payload de cadastro/associacao da placa foi montado incorretamente.")
		return
	var rs300_create_payload: Dictionary = dashboard.call("_grupo_rs_api_vehicle_payload", {
		"plate": "AAA - C33",
		"vehicle_type": "Carro",
		"force_rs300_titular": true,
		"api_client_id": "12824",
	}, {}, "AAA - C33", 9023)
	if int(rs300_create_payload.get("codCliente", 0)) != 12824 \
			or int(rs300_create_payload.get("codEquipamento", 0)) != 9023:
		_fail("O cadastro automatico nao envia explicitamente o titular RS300 e o equipamento.")
		return
	var preserve_client_payload: Dictionary = dashboard.call("_grupo_rs_api_vehicle_payload", {
		"plate": "AAA - C34",
		"vehicle_type": "Carro",
	}, {"client": "LUCAS BARROS PEREIRA SOUSA", "client_id": "77", "vehicle_id": "501"}, "AAA - C34", 9024)
	if preserve_client_payload.has("codCliente"):
		_fail("A edicao normal nao pode mover automaticamente o titular existente.")
		return
	var inactive_payload: Dictionary = dashboard.call("_grupo_rs_api_vehicle_payload", {
		"plate": "MANUT - 001",
		"api_vehicle_status": "Inativo",
	}, {}, "MANUT - 001", 0)
	if str(inactive_payload.get("status", "")) != "I" or int(inactive_payload.get("codEquipamento", -1)) != 0:
		_fail("O payload nao respeitou o status ou a desassociacao do equipamento.")
		return

	var now := Time.get_datetime_dict_from_system()
	var current_update := "%02d/%02d/%04d %02d:%02d:00" % [
		int(now.get("day", 1)),
		int(now.get("month", 1)),
		int(now.get("year", 1970)),
		int(now.get("hour", 0)),
		int(now.get("minute", 0)),
	]
	var status: Dictionary = dashboard.call("_location_monitoring_status", {
		"updated_at": current_update,
		"ignition": normalized.get("ignition", ""),
		"speed": normalized.get("speed", "0"),
	})
	if str(status.get("label", "")) != "Desligado":
		_fail("Ignicao 0 da API nao foi convertida para Desligado.")
		return

	dashboard.queue_free()
	print("GRUPO_RS_API_CONTRACT_CHECK_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
