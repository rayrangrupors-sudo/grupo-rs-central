extends SceneTree


var failures: Array[String] = []


class FakeSwapApi:
	var rows: Dictionary = {}
	var update_calls: Array[String] = []
	var fail_serial := ""
	var fail_after_apply := false
	var delayed_serial := ""
	var delayed_plate := ""
	var delayed_reads := 0

	func add_row(serial: String, plate: String, vehicle_id: String, client: String, client_id: String, model: String) -> void:
		rows[serial] = {
			"serial": serial,
			"plate": plate,
			"client": client,
			"client_id": client_id,
			"vehicle_id": vehicle_id,
			"equipment_id": vehicle_id,
			"vehicle_type": "Carro",
			"status": "A",
			"model": model,
			"brand": "MARCA TESTE",
			"year": "2024",
			"color": "BRANCO",
			"chassis": "CHASSI-%s" % serial,
			"raw": {"CodTipoVeiculo": "1"},
		}

	func find_vehicle(plate: String, serial: String) -> Dictionary:
		for raw in rows.values():
			var row: Dictionary = raw as Dictionary
			var serial_match := serial == "" or str(row.get("serial", "")) == serial
			var plate_match := plate == "" or str(row.get("plate", "")) == plate
			if serial_match and plate_match:
				if serial == delayed_serial and plate == delayed_plate and delayed_reads > 0:
					delayed_reads -= 1
					return {"ok": false, "not_found": true, "response_code": 200, "message": "propagacao atrasada"}
				return {"ok": true, "row": row.duplicate(true), "rows": [row.duplicate(true)]}
		return {"ok": false, "not_found": true, "response_code": 200, "message": "nao encontrado"}

	func update_vehicle(request: Dictionary, existing: Dictionary, new_plate: String) -> Dictionary:
		var serial := str(request.get("remote_serial", request.get("serial", "")))
		update_calls.append("%s->%s" % [serial, new_plate])
		if serial == fail_serial and not fail_after_apply:
			return {"ok": false, "response_code": 503, "message": "falha controlada"}
		var row: Dictionary = rows.get(serial, existing).duplicate(true)
		row["plate"] = new_plate
		if bool(request.get("force_rs300_titular", false)):
			row["client_id"] = str(request.get("api_client_id", row.get("client_id", "")))
			row["client"] = "MANUTENÇÕES" if row["client_id"] == "77" else "CLIENTE TESTE"
		if bool(request.get("clear_vehicle_fields", false)):
			for field_name in ["model", "brand", "year", "color", "chassis", "purchase_date", "observation"]:
				row[field_name] = ""
		else:
			var copied: Dictionary = request.get("copy_vehicle_fields", {}) as Dictionary
			if copied.has("modelo"):
				row["model"] = str(copied.get("modelo", ""))
			if copied.has("marca"):
				row["brand"] = str(copied.get("marca", ""))
		rows[serial] = row
		if serial == fail_serial and fail_after_apply:
			return {"ok": false, "response_code": 500, "message": "timeout apos persistencia"}
		return {"ok": true, "response_code": 200, "row": row.duplicate(true)}


class DashboardHarness:
	extends "res://src/inventory_dashboard.gd"
	var fake := FakeSwapApi.new()

	func _grupo_rs_api_reads_enabled() -> bool:
		return true

	func _grupo_rs_supports_modern_api() -> bool:
		return true

	func _grupo_rs_api_find_vehicle(plate: String = "", serial: String = "", force_read: bool = true, allow_full_scan: bool = true) -> Dictionary:
		return fake.find_vehicle(plate, serial)

	func _grupo_rs_api_update_vehicle(request: Dictionary, existing: Dictionary, new_plate: String) -> Dictionary:
		return fake.update_vehicle(request, existing, new_plate)

	func _fetch_grupo_rs_client_id(label: String) -> String:
		return "77" if label == "MANUTENÇÕES" else "9"

	func _next_modern_maintenance_plate() -> Dictionary:
		return {"ok": true, "plate": "MANUT - 991", "remote_plate": "MANUT991"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var store_script := load("res://src/inventory_store.gd")
	var store = store_script.new()
	store.configure("user://__codex_appliance_replacement_flow.json", "__codex_appliance_replacement_flow.json", "user://__codex_appliance_replacement_flow_backups", false)
	store.load_db()
	store.mark_remote_available()
	var dashboard := DashboardHarness.new()
	root.add_child(dashboard)
	dashboard.store = store
	_expect(bool(dashboard.call("_replacement_vehicle_status_is_active", "A")), "O status API A deveria ser aceito como ativo.")
	_expect(bool(dashboard.call("_replacement_vehicle_status_is_active", "1")), "O status API 1 deveria ser aceito como ativo.")
	_expect(bool(dashboard.call("_replacement_vehicle_status_is_active", "Ativo")), "O status do portal Ativo deveria ser aceito.")
	_expect(not bool(dashboard.call("_replacement_vehicle_status_is_active", "I")), "O status API I deveria permanecer bloqueado.")
	dashboard.fake.add_row("024999901", "TST - 901", "101", "CLIENTE TESTE", "9", "VEICULO ORIGEM")
	dashboard.fake.add_row("024999902", "TST - 902", "102", "OUTRO CLIENTE", "10", "VEICULO DESTINO")
	store.upsert_product({"sku": "024999901", "imei": "024999901", "equipment_number": "024999901", "model": "RS 300", "operator": "Vivo", "plate": "TST - 901", "client": "CLIENTE TESTE", "tracker_status": "Instalado", "status": "Instalado", "location": "Instalado", "stock": 0})
	store.upsert_product({"sku": "024999902", "imei": "024999902", "equipment_number": "024999902", "model": "RS 300", "operator": "Tim", "plate": "TST - 902", "client": "OUTRO CLIENTE", "tracker_status": "Reserva", "status": "Reserva", "location": "Reserva", "stock": 0})

	var success: Dictionary = await dashboard.call("_perform_appliance_replacement", {"client_plate": "TST - 901", "swap_plate": "TST - 902", "operation_id": "test-swap-success"})
	_expect(bool(success.get("ok", false)), "Troca API de sucesso nao foi concluida: %s" % str(success))
	_expect(dashboard.fake.update_calls == ["024999901->MANUT991", "024999902->TST - 901"], "A ordem API segura nao foi respeitada: %s" % str(dashboard.fake.update_calls))
	_expect(str(dashboard.fake.rows["024999902"].get("plate", "")) == "TST - 901", "O aparelho substituto nao recebeu a placa cliente.")
	_expect(str(dashboard.fake.rows["024999901"].get("plate", "")) == "MANUT991", "O aparelho antigo nao foi enviado para manutencao.")
	_expect(str(store.get_product("024999902").get("plate", "")) == "TST - 901", "O Firebase nao confirmou a placa do aparelho substituto.")
	_expect(str(store.get_product("024999901").get("plate", "")) == "MANUT - 991", "O Firebase nao confirmou a manutencao do aparelho antigo.")
	_expect(store.get_maintenances().size() == 1, "A manutencao nao foi gravada na mesma transacao local.")

	# Timeout depois da persistencia: a leitura confirma a alteracao e nenhum
	# segundo POST e feito.
	dashboard.fake.rows["024999901"]["plate"] = "TST - 901"
	dashboard.fake.rows["024999902"]["plate"] = "TST - 902"
	dashboard.fake.update_calls.clear()
	dashboard.fake.fail_serial = "024999901"
	dashboard.fake.fail_after_apply = true
	dashboard.fake.delayed_serial = "024999901"
	dashboard.fake.delayed_plate = "MANUT991"
	dashboard.fake.delayed_reads = 2
	var timeout_success: Dictionary = await dashboard.call("_perform_appliance_replacement", {"client_plate": "TST - 901", "swap_plate": "TST - 902", "operation_id": "test-swap-timeout"})
	_expect(bool(timeout_success.get("ok", false)), "Timeout confirmado por leitura deveria concluir a troca.")
	_expect(dashboard.fake.update_calls.count("024999901->MANUT991") == 1, "Timeout gerou reenvio duplicado para o aparelho antigo.")
	dashboard.fake.fail_serial = ""
	dashboard.fake.fail_after_apply = false
	dashboard.fake.delayed_serial = ""
	dashboard.fake.delayed_plate = ""
	dashboard.fake.delayed_reads = 0

	# Falha antes da aplicacao da segunda etapa: a primeira etapa deve ser
	# restaurada e o estoque local nao pode ser alterado.
	dashboard.fake.rows["024999901"]["plate"] = "TST - 901"
	dashboard.fake.rows["024999902"]["plate"] = "TST - 902"
	dashboard.fake.update_calls.clear()
	dashboard.fake.fail_serial = "024999902"
	var failed: Dictionary = await dashboard.call("_perform_appliance_replacement", {"client_plate": "TST - 901", "swap_plate": "TST - 902", "operation_id": "test-swap-rollback"})
	_expect(not bool(failed.get("ok", false)), "Falha controlada da segunda etapa foi apresentada como sucesso.")
	_expect(str(dashboard.fake.rows["024999902"].get("plate", "")) == "TST - 902", "Rollback nao restaurou o aparelho substituto.")
	_expect(str(store.get_product("024999902").get("plate", "")) == "TST - 901" or str(store.get_product("024999902").get("plate", "")) == "TST - 902", "Estado local ficou corrompido apos rollback.")

	if failures.is_empty():
		print("APPLIANCE_REPLACEMENT_FLOW_CHECK_OK")
	else:
		print("APPLIANCE_REPLACEMENT_FLOW_CHECK_FAILED count=%d" % failures.size())
		quit(1)
	dashboard.queue_free()
	_cleanup()
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _cleanup() -> void:
	for path in [
		"user://__codex_appliance_replacement_flow.json",
		"user://__codex_appliance_replacement_flow.json.tmp",
		"user://__codex_appliance_replacement_flow.json.bak",
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
