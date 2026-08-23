extends SceneTree


class DashboardStub:
	extends "res://src/inventory_dashboard.gd"
	var mode := "existing"
	var writes: Array[Dictionary] = []

	func _grupo_rs_api_find_equipment(serial: String, _force_read: bool = true) -> Dictionary:
		if mode == "transport_failure":
			return {"ok": false, "response_code": 0, "message": "timeout"}
		if mode == "existing":
			return {"ok": true, "row": {"id": 5001, "numeroSerie": serial, "codModelo": 2122, "codOperadora": 4}}
		return {"ok": false, "response_code": 404, "not_found": true, "message": "nao encontrado"}

	func _grupo_rs_api_json_request(path: String, method: int, payload: Dictionary, _retry_login: bool = true) -> Dictionary:
		writes.append({"path": path, "method": method, "payload": payload.duplicate(true)})
		if method == HTTPClient.METHOD_POST:
			return {"ok": true, "response_code": 201, "body": "{\"id\":6002,\"numeroSerie\":\"024288082\"}"}
		return {"ok": true, "response_code": 200, "body": "{\"ok\":true}"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := DashboardStub.new()
	root.add_child(dashboard)
	await process_frame
	var request := {
		"serial": "024288082",
		"apn": "hinova.br",
		"chip_number": "8955483000024288082",
		"phone": "32988146312",
		"model": "RS 300",
		"operator": "Tim",
	}

	var updated: Dictionary = await dashboard.call("_grupo_rs_api_register_equipment", request)
	if not bool(updated.get("ok", false)) or not bool(updated.get("existing", false)):
		_fail(dashboard, "Equipamento existente nao foi tratado como atualizacao: %s" % str(updated))
		return
	if dashboard.writes.size() != 1 or int(dashboard.writes[0].get("method", -1)) != HTTPClient.METHOD_PATCH:
		_fail(dashboard, "Equipamento existente gerou POST ou numero incorreto de escritas: %s" % str(dashboard.writes))
		return

	dashboard.mode = "missing"
	dashboard.writes.clear()
	var created: Dictionary = await dashboard.call("_grupo_rs_api_register_equipment", request)
	if not bool(created.get("ok", false)) or bool(created.get("existing", false)):
		_fail(dashboard, "Equipamento ausente nao foi criado: %s" % str(created))
		return
	if dashboard.writes.size() != 1 or int(dashboard.writes[0].get("method", -1)) != HTTPClient.METHOD_POST:
		_fail(dashboard, "Equipamento ausente nao gerou um unico POST: %s" % str(dashboard.writes))
		return

	dashboard.mode = "transport_failure"
	dashboard.writes.clear()
	var blocked: Dictionary = await dashboard.call("_grupo_rs_api_register_equipment", request)
	if bool(blocked.get("ok", false)) or not dashboard.writes.is_empty():
		_fail(dashboard, "Falha de consulta liberou uma escrita e poderia duplicar o equipamento: %s" % str(blocked))
		return

	dashboard.queue_free()
	print("GRUPO_RS_API_IDEMPOTENCY_CHECK_OK existing=PATCH missing=POST transport_failure=BLOCKED")
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)
