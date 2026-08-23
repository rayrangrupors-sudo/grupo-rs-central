extends SceneTree

const BRANCH_ID := "imperatriz"
const DB_PATH := "user://inventory_db.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var firebase := root.get_node_or_null("FirebaseSync")
	var store_script := load("res://src/inventory_store.gd")
	if firebase == null or store_script == null:
		_fail("Dependencias da integracao nao carregaram.")
		return

	var store: InventoryStore = store_script.new()
	store.configure(DB_PATH, "inventory_db.json", "user://backups", true)
	store.load_db()
	var before: Dictionary = store.get_pending_sync_status()
	print("PENDING_RECOVERY_BEFORE count=%d" % int(before.get("count", 0)))

	firebase.call("bind_store", store, BRANCH_ID)
	var deadline := Time.get_ticks_msec() + 120000
	var final_status: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.25).timeout
		final_status = firebase.call("get_status")
		var state := str(final_status.get("state", ""))
		if state in ["conflict", "auth_error", "error", "offline"]:
			_fail("Sincronizacao terminou em %s: %s" % [state, str(final_status.get("message", ""))])
			return
		if state == "synced" and not bool(final_status.get("pending", false)):
			break

	var after: Dictionary = store.get_pending_sync_status()
	var snapshot: Dictionary = store.get_sync_snapshot()
	print(
		"PENDING_RECOVERY_AFTER count=%d state=%s products=%d movements=%d logs=%d maintenances=%d" % [
			int(after.get("count", 0)),
			str(final_status.get("state", "")),
			(snapshot.get("products", []) as Array).size(),
			(snapshot.get("movements", []) as Array).size(),
			(snapshot.get("system_logs", []) as Array).size(),
			(snapshot.get("maintenances", []) as Array).size(),
		]
	)
	if str(final_status.get("state", "")) != "synced" or bool(final_status.get("pending", false)):
		_fail("A fila nao foi confirmada como sincronizada.")
		return
	if int(after.get("count", 0)) != 0:
		_fail("A fila local ainda possui registros pendentes.")
		return

	print("LIVE_PENDING_RECOVERY_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
