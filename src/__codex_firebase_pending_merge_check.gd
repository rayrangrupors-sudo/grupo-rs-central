extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sync_script := load("res://src/firebase_sync.gd")
	if sync_script == null:
		_fail("FirebaseSync nao carregou.")
		return
	var sync: Node = sync_script.new()
	root.add_child(sync)
	await process_frame

	var remote_snapshot := {
		"schema": 3,
		"products": [{"sku": "024300010", "operator": "Tim"}],
		"movements": [{"id": "remote-movement", "sku": "024300010"}],
		"system_logs": [{"id": "remote-log", "action": "Remoto"}],
		"maintenances": [],
		"runtime": {"remote_state": {"ok": true}},
	}
	var incomplete_pending := {
		"schema": 3,
		"products": [],
		"movements": [],
		"system_logs": [{"id": "pending-log", "action": "Pendente"}],
		"maintenances": [],
		"runtime": {"pending_state": {"queued": true}},
	}
	var merged: Dictionary = sync.call("_merge_pending_snapshot_with_remote", remote_snapshot, incomplete_pending)
	if (merged.get("products", []) as Array).size() != 1 \
			or (merged.get("movements", []) as Array).size() != 1 \
			or (merged.get("system_logs", []) as Array).size() != 2 \
			or not (merged.get("runtime", {}) as Dictionary).has("remote_state") \
			or not (merged.get("runtime", {}) as Dictionary).has("pending_state"):
		_fail("Merge descartou dados oficiais: %s" % str(merged))
		return

	print("FIREBASE_PENDING_MERGE_CHECK_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
