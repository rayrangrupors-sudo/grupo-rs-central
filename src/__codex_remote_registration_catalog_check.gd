extends SceneTree


class DashboardStub:
	extends "res://src/inventory_dashboard.gd"
	var writes: Array[Dictionary] = []

	func _modern_grupo_rs_get(_path: String, _retry_login: bool = true) -> Dictionary:
		return {
			"ok": true,
			"body": """
			<select name='CodModelo'>
				<option value='2122'>RS 300</option>
				<option value='77'>V7.3.5</option>
			</select>
			<select name='CodOperadora'>
				<option value='2'>Vivo</option>
				<option value='6'>MULTI OPERADORA</option>
			</select>
			""",
		}

	func _grupo_rs_api_find_equipment(serial: String, _force_read: bool = true) -> Dictionary:
		return {"ok": false, "response_code": 404, "not_found": true, "message": "nao encontrado: %s" % serial}

	func _grupo_rs_api_json_request(_path: String, method: int, payload: Dictionary, _retry_login: bool = true) -> Dictionary:
		writes.append({"method": method, "payload": payload.duplicate(true)})
		return {"ok": true, "response_code": 201, "body": JSON.stringify({"id": 9010, "numeroSerie": str(payload.get("numeroSerie", ""))})}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := DashboardStub.new()
	root.add_child(dashboard)
	await process_frame

	var request := {
		"serial": "024399999",
		"apn": "linksolutions.br",
		"chip_number": "89555483000099999999",
		"phone": "83999999999",
		"model": "RS300",
		"operator": "VIVO",
	}
	var result: Dictionary = await dashboard.call("_grupo_rs_api_register_equipment", request)
	if not bool(result.get("ok", false)):
		_fail(dashboard, "Cadastro RS300/VIVO foi rejeitado: %s" % str(result))
		return
	if dashboard.writes.size() != 1:
		_fail(dashboard, "Cadastro fora do mapa fixo gerou quantidade incorreta de escritas: %d" % dashboard.writes.size())
		return
	var payload: Dictionary = dashboard.writes[0].get("payload", {}) as Dictionary
	if int(payload.get("codModelo", 0)) != 2122 or int(payload.get("codOperadora", 0)) != 2:
		_fail(dashboard, "Modelo RS 300 ou operadora VIVO nao foi aplicado ao payload: %s" % str(payload))
		return

	var second_request := request.duplicate(true)
	second_request["serial"] = "024399998"
	second_request["model"] = "V7.3.5"
	var second_result: Dictionary = await dashboard.call("_grupo_rs_api_register_equipment", second_request)
	if not bool(second_result.get("ok", false)):
		_fail(dashboard, "Fallback do catalogo para tipo local foi rejeitado: %s" % str(second_result))
		return
	var second_payload: Dictionary = dashboard.writes[1].get("payload", {}) as Dictionary
	if int(second_payload.get("codModelo", 0)) != 2122 or int(second_payload.get("codOperadora", 0)) != 2:
		_fail(dashboard, "Tipo local nao foi convertido para RS 300: %s" % str(second_payload))
		return

	var writes_before_missing_operator := dashboard.writes.size()
	var missing_operator_request := request.duplicate(true)
	missing_operator_request["serial"] = "024399997"
	missing_operator_request["operator"] = ""
	var missing_operator_result: Dictionary = await dashboard.call("_grupo_rs_api_register_equipment", missing_operator_request)
	if bool(missing_operator_result.get("ok", false)) or dashboard.writes.size() != writes_before_missing_operator:
		_fail(dashboard, "Cadastro sem operadora nao foi bloqueado antes da escrita: %s" % str(missing_operator_result))
		return
	if not str(missing_operator_result.get("message", "")).to_lower().contains("operadora obrigatoria"):
		_fail(dashboard, "Mensagem de operadora obrigatoria nao foi exibida: %s" % str(missing_operator_result))
		return

	dashboard.queue_free()
	print("REMOTE_REGISTRATION_CATALOG_CHECK_OK")
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)
