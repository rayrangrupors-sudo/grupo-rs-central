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
	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")
	var login: Dictionary = await dashboard.call("_grupo_rs_api_login")
	if not bool(login.get("ok", false)):
		_fail("Login recusado: %s" % str(login.get("message", "")))
		return
	var vehicle: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", "ROR - 9H20", "", true, false)
	if not bool(vehicle.get("ok", false)):
		_fail("Veiculo de leitura nao localizado: %s" % str(vehicle.get("message", "")))
		return
	var row := vehicle.get("row", {}) as Dictionary
	var vehicle_id := str(row.get("vehicle_id", "")).strip_edges()
	var date := Time.get_date_string_from_system()
	var path := "/endpoints/v1/veiculos/trajeto-dia.php?veiculo=%s&data=%s&skip=0&take=10" % [vehicle_id.uri_encode(), date.uri_encode()]
	var response: Dictionary = await dashboard.call("_grupo_rs_api_get", path, true, true)
	print("GRUPO_RS_API_TRAJETO_VERIFY vehicle=%s http=%s ok=%s body=%s" % [vehicle_id, str(response.get("response_code", 0)), str(response.get("ok", false)), str(response.get("body", "")).substr(0, 220)])
	if int(response.get("response_code", 0)) != 200 or not bool(response.get("ok", false)):
		_fail("A correcao do trajeto ainda nao respondeu HTTP 200.")
		return
	dashboard.queue_free()
	print("GRUPO_RS_API_TRAJETO_VERIFY_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
