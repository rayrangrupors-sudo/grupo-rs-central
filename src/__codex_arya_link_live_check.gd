extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	var arya: Dictionary = await dashboard.call("_ensure_arya_token", true)
	if not bool(arya.get("ok", false)):
		push_error("ARYA_LIVE_CHECK_FAILED: %s" % str(arya.get("message", "")))
		quit(1)
		return
	print("ARYA_LIVE_CHECK_OK")
	var link: Dictionary = await dashboard.call("_request_linksolutions_login")
	if not bool(link.get("ok", false)):
		push_error("LINKSOLUTIONS_LIVE_CHECK_FAILED: %s" % str(link.get("message", "")))
		quit(1)
		return
	print("LINKSOLUTIONS_LIVE_CHECK_OK")
	dashboard.queue_free()
	await process_frame
	quit(0)
