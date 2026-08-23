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
		_fail("Login API recusado: %s" % str(login.get("message", "")))
		return
	var queries := ["ROR - 9H20", "024381076", "RODRIGO MARTINS"]
	var found := 0
	for query in queries:
		var rows: Array = await dashboard.call("_fetch_grupo_rs_equipment_rows", query)
		var api_rows := 0
		for row in rows:
			if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("source", "")) == "grupo_rs_api":
				api_rows += 1
		print("GRUPO_RS_API_INVENTORY_QUERY query=%s rows=%d api_rows=%d" % [query, rows.size(), api_rows])
		if api_rows > 0:
			found += 1
	if found < 2:
		_fail("A busca operacional nao confirmou duas consultas reais pela API.")
		return
	dashboard.queue_free()
	print("GRUPO_RS_API_INVENTORY_SEARCH_LIVE_CHECK_OK queries=%d" % found)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
