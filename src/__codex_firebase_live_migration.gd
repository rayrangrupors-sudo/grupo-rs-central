extends SceneTree

const BRANCH_TIMEOUT_SECONDS := 120.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var firebase := root.get_node_or_null("FirebaseSync")
	var store_script := load("res://src/inventory_store.gd")
	if firebase == null or store_script == null:
		_fail("Sincronizador Firebase nao carregou.")
		return

	var branches := [
		{
			"id": "imperatriz",
			"path": "user://inventory_db.json",
			"backup": "inventory_db.json",
			"backup_dir": "user://backups",
			"migrate": true,
		},
		{
			"id": "araguaina",
			"path": "user://inventory_db_araguaina.json",
			"backup": "inventory_db_araguaina.json",
			"backup_dir": "user://backups_araguaina",
			"migrate": false,
		},
		{
			"id": "acailandia",
			"path": "user://inventory_db_acailandia.json",
			"backup": "inventory_db_acailandia.json",
			"backup_dir": "user://backups_acailandia",
			"migrate": false,
		},
		{
			"id": "maraba",
			"path": "user://inventory_db_maraba.json",
			"backup": "inventory_db_maraba.json",
			"backup_dir": "user://backups_maraba",
			"migrate": false,
		},
	]

	for branch in branches:
		var store: InventoryStore = store_script.new()
		store.configure(
			str(branch.get("path", "")),
			str(branch.get("backup", "")),
			str(branch.get("backup_dir", "")),
			bool(branch.get("migrate", false))
		)
		var snapshot := store.load_db()
		firebase.call("bind_store", store, str(branch.get("id", "")))
		var deadline := Time.get_ticks_msec() + int(BRANCH_TIMEOUT_SECONDS * 1000.0)
		var final_status: Dictionary = {}
		while Time.get_ticks_msec() < deadline:
			await create_timer(0.25).timeout
			final_status = firebase.call("get_status")
			var state := str(final_status.get("state", ""))
			if state in ["synced", "conflict", "auth_error", "error", "offline"]:
				break

		if str(final_status.get("state", "")) != "synced":
			_fail("Base %s nao sincronizou: %s" % [str(branch.get("id", "")), str(final_status)])
			return
		print(
			"FIREBASE_BRANCH_OK %s products=%d movements=%d logs=%d maintenances=%d" % [
				str(branch.get("id", "")),
				(snapshot.get("products", []) as Array).size(),
				(snapshot.get("movements", []) as Array).size(),
				(snapshot.get("system_logs", []) as Array).size(),
				(snapshot.get("maintenances", []) as Array).size(),
			]
		)

	print("FIREBASE_LIVE_MIGRATION_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
