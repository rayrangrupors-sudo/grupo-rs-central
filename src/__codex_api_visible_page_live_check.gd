extends SceneTree


const TARGET_COUNT := 10


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
	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")

	var login: Dictionary = await dashboard.call("_grupo_rs_api_login")
	if not bool(login.get("ok", false)):
		_fail("Login real da API falhou: %s" % str(login.get("message", "sem mensagem")))
		return
	print("VISIBLE_PAGE_API_LOGIN=OK")

	var locations: Dictionary = await dashboard.call("_grupo_rs_api_fetch_locations")
	if not bool(locations.get("ok", false)):
		_fail("Consulta real de localizacao falhou: %s" % str(locations.get("message", "sem mensagem")))
		return
	var location_rows := locations.get("rows", []) as Array
	if location_rows.is_empty():
		_fail("A API retornou a pagina de localizacao vazia.")
		return
	print("VISIBLE_PAGE_LOCATION_BATCH=OK rows=%d pages=%d" % [location_rows.size(), int(locations.get("pages", 0))])

	var checked := 0
	var location_ok := 0
	for raw in location_rows:
		if checked >= TARGET_COUNT:
			break
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var location := raw as Dictionary
		var serial := str(location.get("serial", "")).strip_edges()
		var plate := str(location.get("plate", "")).strip_edges()
		if serial == "" and plate == "":
			continue
		checked += 1
		var current_location: Dictionary = await dashboard.call("_grupo_rs_api_find_location", serial, plate)
		if bool(current_location.get("ok", false)):
			location_ok += 1
		var current_data := current_location.get("location", {}) as Dictionary
		print("VISIBLE_ROW_%02d_OK serial=%s plate=%s equipment=%s vehicle=%s location=%s records=%s" % [
			checked,
			serial,
			plate,
			"SKIPPED_BULK",
			"SKIPPED_BULK",
			"OK" if bool(current_location.get("ok", false)) else "NO_DATA",
			"SKIPPED_BULK",
		])

	if checked < TARGET_COUNT:
		_fail("A API retornou menos de %d linhas utilizaveis para o teste da pagina atual." % TARGET_COUNT)
		return
	print("VISIBLE_PAGE_API_CHECK_OK checked=%d location_ok=%d battery_queries=0" % [checked, location_ok])
	dashboard.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
