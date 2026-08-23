extends SceneTree

const StoreScript := preload("res://src/inventory_store.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var configs := [
		{"label": "imperatriz", "path": "user://inventory_db.json"},
		{"label": "araguaina", "path": "user://inventory_db_araguaina.json"},
		{"label": "acailandia", "path": "user://inventory_db_acailandia.json"},
		{"label": "maraba", "path": "user://inventory_db_maraba.json"},
	]
	for config in configs:
		var store = StoreScript.new()
		store.configure(str(config.get("path", "")), "", "", false)
		store.load_db()
		var diagnostics := store.get_diagnostics()
		print("DIAG|%s|products=%d|diagnostics=%d" % [
			str(config.get("label", "")),
			int(store.get_system_health().get("products", 0)),
			diagnostics.size(),
		])
		for i in range(mini(diagnostics.size(), 12)):
			var item: Dictionary = diagnostics[i]
			print("DIAG_ITEM|%s|%s|%s|%s" % [
				str(config.get("label", "")),
				str(item.get("type", "")),
				str(item.get("sku", "")),
				str(item.get("details", "")),
			])
	print("GUARDIAN_DIAGNOSTICS_DUMP_OK")
	quit(0)
