extends SceneTree

const FirebaseSyncScript := preload("res://src/firebase_sync.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sync: Node = FirebaseSyncScript.new()
	sync.name = "FirebaseSync"
	root.add_child(sync)
	await process_frame
	if sync == null:
		_finish("FIREBASE_READONLY_ERROR sync_unavailable")
		return

	var summary: Dictionary = sync.call("get_configuration_summary")
	var configured := bool(summary.get("configured", false))
	print(
		"FIREBASE_READONLY_CONFIG configured=%s has_refresh_token=%s"
		% [str(configured), str(bool(summary.get("has_refresh_token", false)))]
	)
	if not configured:
		_finish("FIREBASE_READONLY_ERROR config_not_loaded")
		return

	# This is deliberately a read-only probe. Do not call the historical
	# _verify_connection_read_write() diagnostic here because it writes/deletes a
	# heartbeat record in the remote database.
	var live_result: Dictionary = await sync.call(
		"_database_request",
		HTTPClient.METHOD_GET,
		"health/ping"
	)
	print(
		"FIREBASE_READONLY_LIVE ok=%s status=%s"
		% [str(bool(live_result.get("ok", false))), str(live_result.get("status", 0))]
	)
	if not bool(live_result.get("ok", false)):
		_finish("FIREBASE_READONLY_ERROR live_connection_failed")
		return
	_finish("FIREBASE_READONLY_CHECK_OK")


func _finish(message: String) -> void:
	print(message)
	quit(0 if message.ends_with("_OK") else 1)
