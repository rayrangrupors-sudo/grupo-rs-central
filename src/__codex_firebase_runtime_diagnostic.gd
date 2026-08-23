extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard: Control = DashboardScript.new()
	root.add_child(dashboard)
	await process_frame

	var sync: Node = dashboard.call("_firebase_sync")
	if sync == null or sync.name != "FirebaseSync":
		_finish("FIREBASE_RUNTIME_ERROR fallback_unavailable")
		return
	var status: Dictionary = sync.call("get_status")
	print(
		"FIREBASE_RUNTIME_STATUS node=%s configured=%s state=%s branch=%s message=%s"
		% [
			str(sync.get_path()),
			str(status.get("configured", false)),
			str(status.get("state", "")),
			str(status.get("branch", "")),
			str(status.get("message", "")),
		]
	)
	if not bool(status.get("configured", false)):
		_finish("FIREBASE_RUNTIME_ERROR config_not_loaded")
		return

	var live_result: Dictionary = await sync.call(
		"_database_request",
		HTTPClient.METHOD_GET,
		"health/ping"
	)
	print(
		"FIREBASE_RUNTIME_LIVE ok=%s status=%s"
		% [str(live_result.get("ok", false)), str(live_result.get("status", 0))]
	)
	if not bool(live_result.get("ok", false)):
		_finish("FIREBASE_RUNTIME_ERROR live_connection_failed")
		return

	var verification: Dictionary = await sync.call("_verify_connection_read_write")
	print(
		"FIREBASE_RUNTIME_VERIFY ok=%s read=%s write=%s message=%s"
		% [
			str(verification.get("ok", false)),
			str((sync.call("get_status") as Dictionary).get("read_ok", false)),
			str((sync.call("get_status") as Dictionary).get("write_ok", false)),
			str(verification.get("message", "")),
		]
	)
	if not bool(verification.get("ok", false)):
		_finish("FIREBASE_RUNTIME_ERROR read_write_verification_failed")
		return
	_finish("FIREBASE_RUNTIME_DIAGNOSTIC_OK")


func _finish(message: String) -> void:
	print(message)
	quit()
