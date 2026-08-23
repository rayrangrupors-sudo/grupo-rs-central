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

	await dashboard.call("_maintain_grupo_rs_api_session")
	var state := str(dashboard.get("grupo_rs_api_health_state"))
	var last_health := int(dashboard.get("grupo_rs_api_last_health_at"))
	if state != "online" or last_health <= 0:
		_fail("Monitor real da API nao confirmou estado online: %s" % state)
		return

	await dashboard.call("_maintain_grupo_rs_api_session")
	if str(dashboard.get("grupo_rs_api_health_state")) != "online":
		_fail("A segunda validacao da API perdeu o estado online.")
		return

	dashboard.queue_free()
	print("API_MAINTENANCE_LIVE_CHECK_OK state=%s" % state)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
