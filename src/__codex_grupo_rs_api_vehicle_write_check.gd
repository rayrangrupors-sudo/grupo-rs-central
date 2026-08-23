extends SceneTree


class ApiStub:
	var base_script := load("res://src/inventory_dashboard.gd")
	var post_calls: Array[Dictionary] = []
	var patch_calls: Array[Dictionary] = []
	var created := false
	var updated := false
	var restored := false
	var vehicle_reads_before_visible := 0

	func _new_dashboard() -> Node:
		var dashboard: Node = base_script.new()
		return dashboard

	func find_vehicle(plate: String) -> Dictionary:
		if plate == "AAA - C31" and not created:
			# O endpoint real responde 200 com lista vazia para uma placa nova.
			return {"ok": false, "response_code": 200, "not_found": true, "message": "A API retornou 0 veiculo(s)"}
		if plate == "AAA - C31" and created and vehicle_reads_before_visible > 0:
			vehicle_reads_before_visible -= 1
			return {"ok": false, "response_code": 404, "not_found": true, "message": "eventual consistency"}
		if plate == "AAA - C31" and restored:
			return {"ok": true, "row": {"vehicle_id": "77", "equipment_id": "9021", "plate": "AAA - C31", "serial": "024288081"}}
		if plate == "AAA - C31" and created:
			return {"ok": true, "row": {"vehicle_id": "77", "equipment_id": "9021", "plate": "AAA - C31", "serial": "024288081"}}
		if plate == "AAA - C32" and not updated:
			return {"ok": true, "row": {"vehicle_id": "77", "equipment_id": "9021", "plate": "AAA - C32", "serial": "024288081"}}
		if plate == "AAA - C32" and updated:
			return {"ok": true, "row": {"vehicle_id": "77", "equipment_id": "9021", "plate": "AAA - C32", "serial": "024288081"}}
		return {"ok": false, "response_code": 404, "not_found": true, "message": "not found"}

	func json_request(path: String, method: int, payload: Dictionary, _retry_login: bool = true) -> Dictionary:
		if method == HTTPClient.METHOD_POST:
			post_calls.append({"path": path, "payload": payload.duplicate(true)})
			created = true
			return {"ok": true, "response_code": 201, "body": "{\"ok\":true}"}
		if method == HTTPClient.METHOD_PATCH:
			patch_calls.append({"path": path, "payload": payload.duplicate(true)})
			if str(payload.get("placa", "")) == "AAA - C31":
				restored = true
			else:
				updated = true
			return {"ok": true, "response_code": 200, "body": "{\"ok\":true}"}
		return {"ok": false, "response_code": 405, "message": "unsupported"}

	func register_vehicle(request: Dictionary, equipment_row: Dictionary) -> Dictionary:
		var dashboard := _new_dashboard()
		dashboard.set_script(base_script)
		# The real implementation is exercised on a dashboard subclass in _run.
		return {}


class DashboardStub:
	extends "res://src/inventory_dashboard.gd"
	var api := ApiStub.new()

	func _grupo_rs_api_find_vehicle(plate: String = "", _serial: String = "", _force_read: bool = true, _allow_full_scan: bool = true) -> Dictionary:
		return api.find_vehicle(plate)

	func _grupo_rs_api_json_request(path: String, method: int, payload: Dictionary, retry_login: bool = true) -> Dictionary:
		return api.json_request(path, method, payload, retry_login)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := DashboardStub.new()
	root.add_child(dashboard)
	await process_frame
	var request := {
		"plate": "AAA - C31",
		"serial": "024288081",
		"vehicle_model": "HB20",
		"vehicle_year": "2018",
		"api_vehicle_status": "Estoque",
	}
	var created: Dictionary = await dashboard.call("_grupo_rs_api_register_vehicle", request, {"codEquipamento": 9021})
	if not bool(created.get("ok", false)):
		_fail(dashboard, "Cadastro API de veiculo nao confirmou no stub: %s" % str(created))
		return
	if bool(created.get("confirmation_pending", false)):
		if not bool(created.get("accepted", false)) or str(created.get("warning", "")).strip_edges() == "":
			_fail(dashboard, "Cadastro aceito sem aviso de publicacao posterior.")
			return
	if dashboard.api.post_calls.size() != 1:
		_fail(dashboard, "Cadastro API nao enviou exatamente um POST.")
		return
	var post_payload: Dictionary = dashboard.api.post_calls[0].get("payload", {}) as Dictionary
	if str(post_payload.get("placa", "")) != "AAA - C31" \
			or str(post_payload.get("status", "")) != "A" \
			or int(post_payload.get("codEquipamento", 0)) != 9021 \
			or int(post_payload.get("codCliente", 0)) != 12824 \
			or int(post_payload.get("codTipoVeiculo", 0)) != 1:
		_fail(dashboard, "Payload POST de placa/associacao incorreto: %s" % str(post_payload))
		return
	for cleared_field in ["modelo", "marca", "ano", "cor", "chassi", "dataCompra", "observacao"]:
		if str(post_payload.get(cleared_field, "__missing__")) != "":
			_fail(dashboard, "Cadastro automatico nao limpou %s: %s" % [cleared_field, str(post_payload)])
			return

	var update_request := {"remote_serial": "024288081", "api_vehicle_status": "Ativo"}
	var existing := {"vehicle_id": "77", "equipment_id": "9021", "plate": "AAA - C31", "serial": "024288081"}
	var updated: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", update_request, existing, "AAA - C32")
	if not bool(updated.get("ok", false)):
		_fail(dashboard, "Alteracao API de placa nao confirmou no stub: %s" % str(updated))
		return
	if dashboard.api.patch_calls.size() != 1:
		_fail(dashboard, "Alteracao API nao enviou exatamente um PATCH.")
		return
	var patch_payload: Dictionary = dashboard.api.patch_calls[0].get("payload", {}) as Dictionary
	if str(patch_payload.get("placa", "")) != "AAAC32" or str(patch_payload.get("status", "")) != "A":
		_fail(dashboard, "Payload PATCH de placa incorreto: %s" % str(patch_payload))
		return

	var rollback: Dictionary = await dashboard.call("_rollback_api_vehicle_reassignment", {
		"after": updated.get("row", {}),
	}, {
		"old_plate": "AAA - C31",
		"remote_serial": "024288081",
	})
	if not bool(rollback.get("ok", false)) or dashboard.api.patch_calls.size() != 2:
		_fail(dashboard, "Restauracao API nao confirmou o segundo PATCH: %s" % str(rollback))
		return
	var restore_payload: Dictionary = dashboard.api.patch_calls[1].get("payload", {}) as Dictionary
	if str(restore_payload.get("placa", "")) != "AAAC31":
		_fail(dashboard, "Payload de restauracao incorreto: %s" % str(restore_payload))
		return

	dashboard.queue_free()
	print("GRUPO_RS_API_VEHICLE_WRITE_CHECK_OK")
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)
