extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		push_error("Dashboard nao compilou.")
		quit(1)
		return

	var dashboard: Node = dashboard_script.new()
	var response := '{"status":true,"data":[{"iccid":"89550534390025555820","msisdn":"5531983946211","provider":"CLARO","apn":"hinova.br","conn_status":0}]}'
	var parsed: Dictionary = dashboard.call("_parse_rs300_arya_response", response, "25555820")
	if str(parsed.get("iccid", "")) != "89550534390025555820":
		_fail(dashboard, "A busca por sufixo nao recuperou o ICCID completo.")
		return
	if str(parsed.get("phone", "")) != "5531983946211":
		_fail(dashboard, "O telefone da Arya nao foi recuperado.")
		return
	if str(parsed.get("operator", "")) != "CLARO":
		_fail(dashboard, "A operadora provider da Arya nao foi preservada.")
		return
	if str(dashboard.call("_arya_chip_search_suffix", "89550534390025555820")) != "25555820":
		_fail(dashboard, "O sufixo do ICCID nao foi normalizado.")
		return

	dashboard.free()
	print("ARYA_INVENTORY_PARSER_CHECK_OK")
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	push_error(message)
	dashboard.free()
	quit(1)
