extends SceneTree

var test_failed := false


class DashboardHarness:
	extends "res://src/inventory_dashboard.gd"


class FakeRemote:
	var equipment: Dictionary = {}
	var vehicles: Dictionary = {}
	var existing_registration_hits := 0
	var reassignment_hits := 0
	var modification_hits := 0

	func register_equipment(request: Dictionary) -> Dictionary:
		var serial := str(request.get("serial", ""))
		var row := {
			"serial": serial,
			"chip_number": str(request.get("chip_number", "")),
			"phone": str(request.get("phone", "")),
			"apn": str(request.get("apn", "")),
			"operator": str(request.get("operator", "")),
			"model": "RS 300",
		}
		if equipment.has(serial):
			row = equipment[serial].duplicate(true)
			existing_registration_hits += 1
		row.merge({
			"chip_number": str(request.get("chip_number", row.get("chip_number", ""))),
			"phone": str(request.get("phone", row.get("phone", ""))),
			"apn": str(request.get("apn", row.get("apn", ""))),
			"operator": str(request.get("operator", row.get("operator", ""))),
		}, true)
		equipment[serial] = row
		return {"ok": true, "response_code": 200, "row": row, "existing": existing_registration_hits > 0}

	func register_vehicle(request: Dictionary) -> Dictionary:
		var serial := str(request.get("serial", ""))
		var plate := str(request.get("plate", ""))
		for current_plate in vehicles.keys():
			if str(vehicles[current_plate].get("serial", "")) == serial:
				vehicles.erase(current_plate)
				reassignment_hits += 1
				break
		if vehicles.has(plate):
			return {"ok": false, "response_code": 409, "message": "Placa ja associada a outro veiculo"}
		vehicles[plate] = _vehicle_row(serial, plate)
		return {"ok": true, "response_code": 200, "row": vehicles[plate]}

	func modify_equipment(request: Dictionary) -> Dictionary:
		var serial := str(request.get("serial", ""))
		if not equipment.has(serial):
			return {"ok": false, "response_code": 404, "message": "Equipamento ficticio nao encontrado"}
		var row: Dictionary = equipment[serial].duplicate(true)
		row["chip_number"] = str(request.get("chip_number", row.get("chip_number", "")))
		row["phone"] = str(request.get("phone", row.get("phone", "")))
		row["apn"] = str(request.get("apn", row.get("apn", "")))
		row["operator"] = str(request.get("operator", row.get("operator", "")))
		equipment[serial] = row
		modification_hits += 1
		return {"ok": true, "response_code": 200, "row": row}

	func modify_vehicle(serial: String, plate: String) -> Dictionary:
		for current_plate in vehicles.keys():
			if str(vehicles[current_plate].get("serial", "")) == serial and str(current_plate) != plate:
				vehicles.erase(current_plate)
				reassignment_hits += 1
				break
		vehicles[plate] = _vehicle_row(serial, plate)
		return {"ok": true, "response_code": 200, "row": vehicles[plate]}

	func swap_vehicles(serial_a: String, serial_b: String, plate_a: String, plate_b: String) -> Dictionary:
		if not vehicles.has(plate_a) or not vehicles.has(plate_b):
			return {"ok": false, "response_code": 404, "message": "As duas placas ficticias precisam existir para a troca"}
		if str(vehicles[plate_a].get("serial", "")) != serial_a or str(vehicles[plate_b].get("serial", "")) != serial_b:
			return {"ok": false, "response_code": 409, "message": "A troca nao coincide com as associacoes esperadas"}
		var row_a: Dictionary = vehicles[plate_a].duplicate(true)
		var row_b: Dictionary = vehicles[plate_b].duplicate(true)
		row_a["serial"] = serial_b
		row_b["serial"] = serial_a
		vehicles[plate_a] = row_a
		vehicles[plate_b] = row_b
		reassignment_hits += 2
		return {"ok": true, "response_code": 200, "row_a": vehicles[plate_a], "row_b": vehicles[plate_b]}

	func _vehicle_row(serial: String, plate: String) -> Dictionary:
		return {
			"serial": serial,
			"plate": plate,
			"client": "RS300",
			"vehicle_type": "Carro",
			"model": "",
			"brand": "",
			"year": "",
			"color": "",
			"chassis": "",
		}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var store_script := load("res://src/inventory_store.gd")
	var store = store_script.new()
	store.configure("user://__codex_two_device_flow.json", "__codex_two_device_flow.json", "user://__codex_two_device_flow_backups", false)
	store.load_db()
	store.mark_remote_available()
	var dashboard := DashboardHarness.new()
	dashboard.store = store
	var remote := FakeRemote.new()

	var device_a := {
		"serial": "024999901",
		"chip_number": "89559999000000000101",
		"phone": "62999111001",
		"apn": "hinova.br",
		"operator": "Vivo",
		"plate": "TST - 901",
		"tracker_status": "Estoque",
	}
	var device_b := {
		"serial": "024999902",
		"chip_number": "89559999000000000102",
		"phone": "62999111002",
		"apn": "linksolutions.br",
		"operator": "Tim",
		"plate": "TST - 902",
		"tracker_status": "Reserva",
	}
	for device in [device_a, device_b]:
		var serial := str(device["serial"])
		var local := {"sku": serial, "imei": serial, "equipment_number": serial, "tracker_status": "Estoque", "status": "Estoque", "location": "Estoque", "plate": "", "client": "RS300", "model": "RS 300", "category": "RS 300", "operator": str(device["operator"])}
		store.upsert_product_replacing_sku(serial, local)
		var request := dashboard._smart_registration_prepare_request(device)
		var equipment_result := remote.register_equipment(request)
		_expect(bool(equipment_result.get("ok", false)), "Cadastro inicial ficticio recusado para %s." % serial)
		var vehicle_result := remote.register_vehicle(request)
		_expect(bool(vehicle_result.get("ok", false)), "Vinculacao inicial ficticia recusada para %s." % serial)
		var finalized := dashboard._finalize_local_equipment_registration(local, request)
		_expect(bool(finalized.get("ok", false)), "Persistencia local do cadastro falhou para %s." % serial)
		_log(store, "Cadastro remoto concluido", "API confirmou equipamento %s" % serial, serial, "cadastro", 200, 31)
		_log(store, "Vinculacao remota concluida", "API confirmou placa %s" % str(device["plate"]), serial, "vinculacao", 200, 44)

	_expect(remote.equipment.size() == 2, "O cadastro inicial criou quantidade diferente de dois equipamentos.")
	_expect(remote.vehicles.size() == 2, "O cadastro inicial criou quantidade diferente de duas associacoes.")

	# Recadastro do aparelho A: mesma serie, novo chip/APN/telefone e nova placa.
	var recadastro_a := device_a.duplicate(true)
	recadastro_a["chip_number"] = "89559999000000000901"
	recadastro_a["phone"] = "62999111901"
	recadastro_a["apn"] = "linksolutions.br"
	recadastro_a["operator"] = "Vivo"
	recadastro_a["plate"] = "TST - 991"
	var recadastro_request := dashboard._smart_registration_prepare_request(recadastro_a)
	var recadastro_equipment := remote.register_equipment(recadastro_request)
	_expect(bool(recadastro_equipment.get("ok", false)), "Recadastro do aparelho existente falhou.")
	var recadastro_vehicle := remote.register_vehicle(recadastro_request)
	_expect(bool(recadastro_vehicle.get("ok", false)), "Troca de placa no recadastro falhou.")
	var recadastro_product: Dictionary = store.get_product(device_a["serial"])
	var recadastro_final := dashboard._finalize_local_equipment_registration(recadastro_product, recadastro_request)
	_expect(bool(recadastro_final.get("ok", false)), "Persistencia do recadastro falhou.")
	_log(store, "Recadastro remoto concluido", "Mesma serie com novo chip e nova placa", device_a["serial"], "cadastro", 200, 58)
	_log(store, "Vinculacao remota concluida", "Aparelho existente movido para TST - 991", device_a["serial"], "vinculacao", 200, 47)
	_expect(remote.equipment.size() == 2, "O recadastro duplicou o equipamento existente.")
	_expect(remote.existing_registration_hits == 1, "O caminho de aparelho existente nao foi exercitado exatamente uma vez.")
	_expect(not remote.vehicles.has("TST - 901") and remote.vehicles.has("TST - 991"), "A placa antiga nao foi liberada no recadastro.")
	_expect(str(remote.equipment[device_a["serial"]]["chip_number"]) == "89559999000000000901", "O novo chip do recadastro nao foi aplicado.")

	# Modificacao do aparelho B, seguida de troca atomica das duas associacoes.
	var modification_request := dashboard._smart_registration_prepare_request({
		"serial": device_b["serial"],
		"chip_number": "89559999000000000902",
		"phone": "62999111902",
		"apn": "hinova.br",
		"operator": "Claro",
		"plate": device_b["plate"],
		"tracker_status": "Manutencao",
	})
	var modification_result := remote.modify_equipment(modification_request)
	_expect(bool(modification_result.get("ok", false)), "Modificacao do segundo aparelho falhou.")
	var modification_vehicle := remote.modify_vehicle(device_b["serial"], device_b["plate"])
	_expect(bool(modification_vehicle.get("ok", false)), "Reconciliacao veicular da modificacao falhou.")
	var modified_local := dashboard._finalize_local_equipment_modification({
		"serial": device_b["serial"],
		"local_sku": device_b["serial"],
		"vehicle_target_plate": device_b["plate"],
		"chip_number": modification_request["chip_number"],
		"phone": modification_request["phone"],
		"apn": modification_request["apn"],
		"operator": modification_request["operator"],
		"tracker_status": "Manutencao",
	})
	_expect(bool(modified_local.get("ok", false)), "Persistencia da modificacao falhou.")
	_log(store, "Modificacao remota concluida", "Chip, APN, telefone e status atualizados", device_b["serial"], "modificacao", 200, 63)

	var swap_result := remote.swap_vehicles(device_a["serial"], device_b["serial"], "TST - 991", "TST - 902")
	_expect(bool(swap_result.get("ok", false)), "Troca atomica entre os dois aparelhos falhou.")
	var swap_a := dashboard._finalize_local_equipment_modification({"serial": device_a["serial"], "local_sku": device_a["serial"], "vehicle_target_plate": "TST - 902"})
	var swap_b := dashboard._finalize_local_equipment_modification({"serial": device_b["serial"], "local_sku": device_b["serial"], "vehicle_target_plate": "TST - 991"})
	_expect(bool(swap_a.get("ok", false)) and bool(swap_b.get("ok", false)), "Persistencia local da troca falhou.")
	_log(store, "Troca de associacao concluida", "Troca atomica entre TST - 991 e TST - 902", device_a["serial"], "modificacao", 200, 71)
	_log(store, "Troca de associacao concluida", "Troca atomica entre TST - 902 e TST - 991", device_b["serial"], "modificacao", 200, 69)

	_expect(str(remote.vehicles["TST - 902"]["serial"]) == device_a["serial"], "A troca nao colocou o aparelho A na placa do aparelho B.")
	_expect(str(remote.vehicles["TST - 991"]["serial"]) == device_b["serial"], "A troca nao colocou o aparelho B na placa do aparelho A.")
	_expect(str(remote.vehicles["TST - 902"]["client"]) == "RS300" and str(remote.vehicles["TST - 991"]["client"]) == "RS300", "A troca perdeu o titular RS300.")
	_expect(str(remote.vehicles["TST - 902"]["vehicle_type"]) == "Carro" and str(remote.vehicles["TST - 991"]["vehicle_type"]) == "Carro", "A troca perdeu o tipo Carro.")
	_expect(str(store.get_product(device_a["serial"]).get("plate", "")) == "TST - 902", "O espelho local do aparelho A nao acompanhou a troca.")
	_expect(str(store.get_product(device_b["serial"]).get("plate", "")) == "TST - 991", "O espelho local do aparelho B nao acompanhou a troca.")

	var metrics: Dictionary = store.get_remote_operation_metrics()
	_expect(int(metrics.get("failed", 0)) == 0, "O fluxo ficticio gerou falha remota inesperada.")
	_expect(int(metrics.get("fallback", 0)) == 0, "O fluxo ficticio acionou fallback sem necessidade.")
	_expect(int(metrics.get("association_conflicts", 0)) == 0, "O fluxo ficticio gerou conflito de associacao.")
	_expect(int(metrics.get("risk_high", 0)) == 0, "O fluxo ficticio classificou operacao saudavel como alto risco.")
	_expect(float(metrics.get("success_rate", 0.0)) == 1.0, "A taxa de sucesso calculada pelo log nao chegou a 100%%.")
	_expect(float(metrics.get("observability_rate", 0.0)) == 1.0, "A observabilidade HTTP das operacoes ficticias nao chegou a 100%%.")
	if test_failed:
		dashboard.free()
		_cleanup()
		quit(1)
		return
	print("TWO_DEVICE_FLOW_CHECK_OK")
	print("TWO_DEVICE_FLOW_METRICS=" + JSON.stringify(metrics))
	print("TWO_DEVICE_FLOW_REMOTE_EQUIPMENT=" + str(remote.equipment.size()) + " VEHICLES=" + str(remote.vehicles.size()) + " EXISTING_RECADASTRO=" + str(remote.existing_registration_hits) + " SWAP_REASSIGNMENTS=" + str(remote.reassignment_hits))
	dashboard.free()
	_cleanup()
	quit(0)


func _log(store, action: String, details: String, serial: String, phase: String, http_code: int, latency_ms: int) -> void:
	store.add_system_log_event(action, details, serial, {
		"status": "completed",
		"phase": phase,
		"operation": phase,
		"transport": "api",
		"origin": "API Grupo RS",
		"http_code": http_code,
		"attempt": 1,
		"max_attempts": 1,
		"latency_ms": latency_ms,
		"correlation_id": "test-%s-%s" % [serial, Time.get_ticks_msec()],
		"retryable": false,
	})


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		test_failed = true


func _cleanup() -> void:
	for path in [
		"user://__codex_two_device_flow.json",
		"user://__codex_two_device_flow.json.tmp",
		"user://__codex_two_device_flow.json.bak",
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
