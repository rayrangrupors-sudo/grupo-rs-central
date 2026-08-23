extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var firebase := root.get_node_or_null("FirebaseSync")
	var store_script := load("res://src/inventory_store.gd")
	if firebase == null or store_script == null:
		_fail("Dependencias da integracao nao carregaram.")
		return

	var store: InventoryStore = store_script.new()
	store.configure("user://inventory_db.json", "inventory_db.json", "user://backups", true)
	store.load_db()
	firebase.call("bind_store", store, "imperatriz")
	if not await _wait_for_state(firebase, "synced", 90.0):
		_fail("Firebase nao ficou sincronizado antes do registro.")
		return

	var already_logged := false
	for entry in store.get_system_logs(0):
		if str(entry.get("action", "")) == "Firebase ativado" \
				and str(entry.get("details", "")).contains("3.8.4"):
			already_logged = true
			break
	if not already_logged:
		store.add_system_log(
			"Firebase ativado",
			"Versao 3.8.4: sincronizador inicializado pelo executavel fixo; autenticacao, leitura e gravacao remota validadas."
		)

	firebase.call("force_sync")
	if not await _wait_for_state(firebase, "synced", 90.0, true):
		_fail("Registro local nao chegou ao Firebase.")
		return

	print("FIREBASE_INCREMENTAL_LOG_OK")
	quit(0)


func _wait_for_state(firebase: Node, wanted: String, timeout_seconds: float, require_cycle: bool = false) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	var saw_activity := not require_cycle
	while Time.get_ticks_msec() < deadline:
		var status: Dictionary = firebase.call("get_status")
		var state := str(status.get("state", ""))
		if state in ["connecting", "syncing", "pending"]:
			saw_activity = true
		if state == wanted and saw_activity and not bool(status.get("pending", false)):
			return true
		if state in ["conflict", "auth_error", "error", "offline"]:
			return false
		await create_timer(0.2).timeout
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
