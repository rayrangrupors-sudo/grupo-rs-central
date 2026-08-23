extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		push_error("LINKSOLUTIONS_LIVE_CHECK_FAILED: script principal nao compilou")
		quit(1)
		return

	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame
	var login: Dictionary = await dashboard.call("_request_linksolutions_login")
	if not bool(login.get("ok", false)):
		push_error("LINKSOLUTIONS_LIVE_LOGIN_FAILED: %s" % str(login.get("message", "falha sem detalhe")))
		dashboard.free()
		quit(1)
		return

	var result: Dictionary = await dashboard.call("_lookup_linksolutions_chip_status", "89555483000025854947")
	print("LINKSOLUTIONS_LIVE_LOGIN_OK")
	print("LINKSOLUTIONS_LIVE_QUERY=%s STATUS=%s" % [str(result.get("message", "")), str(result.get("status", ""))])
	if dashboard.has_method("_cancel_tracked_inventory_query_requests"):
		dashboard.call("_cancel_tracked_inventory_query_requests")
	dashboard.queue_free()
	await process_frame
	quit(0 if not str(result.get("status", "")).is_empty() else 1)
