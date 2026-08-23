extends SceneTree


var failures: Array[String] = []


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
	var store_script := load("res://src/inventory_store.gd")
	var store: RefCounted = store_script.new()
	store.call("configure", "user://__codex_inventory_filter.json", "__codex_inventory_filter.json", "user://__codex_inventory_filter_backups", true)
	store.call("load_db")
	dashboard.set("store", store)

	dashboard.set("selected_status_filter_key", "manutencao")
	dashboard.set("table_current_page", 2)
	var list_view: Control = dashboard.call("_build_list_view")
	root.add_child(list_view)
	await process_frame

	if str(dashboard.get("selected_status_filter_key")) != "manutencao":
		_fail("O filtro Manutencao foi perdido ao reconstruir a lista.")
		return
	if int(dashboard.get("table_current_page")) != 2:
		_fail("A pagina atual foi perdida ao reconstruir a lista.")
		return

	list_view.queue_free()
	dashboard.queue_free()
	await process_frame
	print("INVENTORY_FILTER_PERSISTENCE_CHECK_OK")
	quit(0)


func _fail(message: String) -> void:
	if failures.is_empty():
		failures.append(message)
	push_error(message)
	quit(1)
