extends SceneTree


class DashboardStub:
	extends "res://src/inventory_dashboard.gd"
	var find_calls := 0
	var post_calls: Array[Dictionary] = []

	func _grupo_rs_api_find_equipment(serial: String, _force_read: bool = true) -> Dictionary:
		find_calls += 1
		if find_calls < 2:
			return {"ok": false, "response_code": 404, "not_found": true, "message": "eventual consistency"}
		return {
			"ok": true,
			"row": {"id": 9021, "numeroSerie": serial, "apn": "hinova.br"},
		}

	func _grupo_rs_api_json_request(path: String, method: int, payload: Dictionary, _retry_login: bool = true) -> Dictionary:
		post_calls.append({"path": path, "method": method, "payload": payload.duplicate(true)})
		return {"ok": true, "response_code": 201, "body": "{\"ok\":true}"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := DashboardStub.new()
	root.add_child(dashboard)
	await process_frame
	var request := {
		"serial": "024288081",
		"apn": "hinova.br",
		"chip_number": "8955483000024288081",
		"phone": "32988146311",
		"model": "RS 300",
		"operator": "Tim",
	}
	var result: Dictionary = await dashboard.call("_grupo_rs_api_register_equipment", request)
	if not bool(result.get("ok", false)):
		_fail(dashboard, "Cadastro API de equipamento nao confirmou no stub: %s" % str(result))
		return
	if dashboard.find_calls != 2:
		_fail(dashboard, "A confirmacao do equipamento repetiu a leitura ou nao encerrou de forma objetiva: %d leituras." % dashboard.find_calls)
		return
	if dashboard.post_calls.size() != 1:
		_fail(dashboard, "Cadastro API de equipamento repetiu o POST ou nao enviou o cadastro.")
		return
	var post_payload: Dictionary = dashboard.post_calls[0].get("payload", {}) as Dictionary
	if str(post_payload.get("numeroSerie", "")) != "024288081" \
			or int(post_payload.get("codModelo", 0)) != 2122 \
			or int(post_payload.get("codOperadora", 0)) != 4:
		_fail(dashboard, "Payload de cadastro do equipamento incorreto: %s" % str(post_payload))
		return
	var equipment_row := result.get("row", {}) as Dictionary
	if int(dashboard.call("_grupo_rs_api_equipment_id_from_row", equipment_row, true)) != 9021:
		_fail(dashboard, "O identificador generico do equipamento nao foi recuperado para a associacao.")
		return

	dashboard.queue_free()
	print("GRUPO_RS_API_EQUIPMENT_WRITE_CHECK_OK")
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)
