extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		push_error("LINKSOLUTIONS_CONTRACT_FAILED: script principal nao compilou")
		quit(1)
		return

	var dashboard: Node = dashboard_script.new()
	var direct: Dictionary = dashboard.call("_parse_linksolutions_sim_response", {
		"ok": true,
		"body": '{"id":17,"iccid":"89555483000025854947","msisdn":"5532988146311","status__name":"Connected","last_conn":"06/08/2026 15:20:00","last_rat_type":"4G"}'
	})
	if not bool(direct.get("ok", false)):
		_fail(dashboard, "resposta unitaria nao foi interpretada")
		return
	if str((direct.get("parsed", {}) as Dictionary).get("iccid", "")) != "89555483000025854947":
		_fail(dashboard, "ICCID da resposta unitaria nao foi preservado")
		return

	var envelope: Dictionary = dashboard.call("_parse_linksolutions_sim_response", {
		"ok": true,
		"body": '{"data":{"content":[{"iccid":"89555483000025854954","msisdn":"5532988146311","status_name":"Offline"}]}}'
	})
	if not bool(envelope.get("ok", false)):
		_fail(dashboard, "envelope data/content nao foi interpretado")
		return
	var envelope_item: Dictionary = envelope.get("parsed", {})
	if str(envelope_item.get("iccid", "")) != "89555483000025854954":
		_fail(dashboard, "ICCID do envelope nao foi preservado")
		return

	if str(dashboard.call("_normalize_linksolutions_status", "Connected")) != "online":
		_fail(dashboard, "status Connected nao virou online")
		return
	if str(dashboard.call("_normalize_linksolutions_status", "Offline")) != "offline":
		_fail(dashboard, "status Offline nao virou offline")
		return
	if str(dashboard.call("_chip_phone_from_data", {"msisdn": "5532988146311"})) != "5532988146311":
		_fail(dashboard, "MSISDN nao foi extraido")
		return
	if str(dashboard.call("_chip_phone_from_data", {"line__msisdn": "5532988146311"})) != "5532988146311":
		_fail(dashboard, "line__msisdn nao foi extraido")
		return
	if str(dashboard.call("_chip_phone_from_data", {"line": {"msisdn": "5532988146311"}})) != "5532988146311":
		_fail(dashboard, "MSISDN aninhado nao foi extraido")
		return
	if str(dashboard.call("_chip_phone_from_data", {"id": 5532988146311, "number": 17})) != "":
		_fail(dashboard, "identificador generico foi confundido com telefone")
		return
	var empty_skeleton: Dictionary = dashboard.call("_parse_linksolutions_sim_response", {
		"ok": true,
		"body": '{"id":0,"iccid":null,"msisdn":null,"status__name":null,"last_conn":null}'
	})
	if bool(empty_skeleton.get("ok", false)):
		_fail(dashboard, "resposta vazia da LSIM foi confundida com chip localizado")
		return
	if not bool(dashboard.call("_linksolutions_sim_matches_query", {"iccid": "89555483000020962584"}, "20962584")):
		_fail(dashboard, "sufixo valido do ICCID nao foi reconhecido")
		return
	if bool(dashboard.call("_linksolutions_sim_matches_query", {"iccid": "89555483000020962584"}, "99999999")):
		_fail(dashboard, "ICCID diferente foi aceito como correspondencia")
		return
	if not bool(dashboard.call("_apn_is_linksolutions", "linksolutions.br")):
		_fail(dashboard, "APN Linksolutions nao foi reconhecida")
		return

	print("LINKSOLUTIONS_CONTRACT_OK")
	dashboard.free()
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	push_error("LINKSOLUTIONS_CONTRACT_FAILED: %s" % message)
	dashboard.free()
	quit(1)
