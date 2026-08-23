extends SceneTree


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
		_fail("Login API recusado: %s" % str(login.get("message", "")))
		return
	var result: Dictionary = await dashboard.call("_smart_4g_hybrid_vehicle_by_plate", "SMW - 6E12")
	print("SMART_4G_HYBRID_LIVE_RESULT=%s" % JSON.stringify(result))
	if not bool(result.get("ok", false)):
		_fail("Busca hibrida nao localizou SMW - 6E12: %s" % str(result))
		return
	var row := result.get("row", {}) as Dictionary
	var lat := str(row.get("lat", "")).replace(",", ".").to_float()
	var lng := str(row.get("lng", "")).replace(",", ".").to_float()
	if not is_finite(lat) or not is_finite(lng) or lat == 0.0 or lng == 0.0:
		_fail("Busca hibrida encontrou a placa sem coordenadas validas: %s" % str(row))
		return
	print("SMART_4G_HYBRID_LIVE_CHECK_OK source=%s serial=%s lat=%s lng=%s" % [str(result.get("source", "")), str(row.get("serial", "")), str(lat), str(lng)])
	dashboard.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
