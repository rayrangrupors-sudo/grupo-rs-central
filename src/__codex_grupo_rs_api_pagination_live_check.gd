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
		_fail("Login real da API falhou: %s" % str(login.get("message", "sem mensagem")))
		return

	var locations: Dictionary = await dashboard.call("_grupo_rs_api_fetch_locations")
	if not bool(locations.get("ok", false)):
		_fail("Consulta real de localizacao falhou: %s" % str(locations.get("message", "sem mensagem")))
		return
	var location_rows := locations.get("rows", []) as Array
	print("GRUPO_RS_API_LIVE_LOCATION_BATCH rows=%d pages=%d" % [location_rows.size(), int(locations.get("pages", 0))])
	if location_rows.is_empty():
		_fail("Consulta real de localizacao nao trouxe registros.")
		return
	var checked := 0
	for row in location_rows:
		if checked >= 10:
			break
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var current := row as Dictionary
		var serial := str(current.get("serial", ""))
		var plate := str(current.get("plate", ""))
		var found: Dictionary = await dashboard.call("_grupo_rs_api_find_location", serial, plate)
		if not bool(found.get("ok", false)):
			_fail("API nao localizou a linha visivel %d (%s / %s)." % [checked + 1, serial, plate])
			return
		checked += 1
		print("GRUPO_RS_API_VISIBLE_ROW_OK index=%d serial=%s plate=%s" % [checked, serial, plate])
	if checked == 0:
		_fail("Nenhuma linha valida foi encontrada para a consulta visivel.")
		return

	dashboard.queue_free()
	print("GRUPO_RS_API_PAGINATION_LIVE_CHECK_OK checked=%d location_only=true battery_queries=0" % checked)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
