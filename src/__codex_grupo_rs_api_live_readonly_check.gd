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
		print("GRUPO_RS_API_LIVE_AUTH=FAIL code=%s message=%s" % [str(login.get("response_code", "")), str(login.get("message", ""))])
		dashboard.queue_free()
		quit(0)
		return
	print("GRUPO_RS_API_LIVE_AUTH=OK")

	var me: Dictionary = await dashboard.call("_grupo_rs_api_get", "/endpoints/v1/auth/me.php")
	print("GRUPO_RS_API_LIVE_ME=%s" % ("OK" if bool(me.get("ok", false)) else "FAIL"))
	var vehicles: Dictionary = await dashboard.call("_grupo_rs_api_fetch_vehicles")
	print("GRUPO_RS_API_LIVE_VEHICLES=%s rows=%d" % ["OK" if bool(vehicles.get("ok", false)) else "FAIL", (vehicles.get("rows", []) as Array).size()])
	var locations: Dictionary = await dashboard.call("_grupo_rs_api_fetch_locations")
	print("GRUPO_RS_API_LIVE_LOCATIONS=%s rows=%d" % ["OK" if bool(locations.get("ok", false)) else "FAIL", (locations.get("rows", []) as Array).size()])

	if bool(vehicles.get("ok", false)) and not (vehicles.get("rows", []) as Array).is_empty():
		var first_vehicle: Dictionary = (vehicles.get("rows", []) as Array)[0] as Dictionary
		var vehicle_id := str(first_vehicle.get("vehicle_id", "")).strip_edges()
		if vehicle_id != "":
			var now := Time.get_date_string_from_system()
			var records: Dictionary = await dashboard.call("_grupo_rs_api_latest_event", vehicle_id, now + " 23:59:59")
			print("GRUPO_RS_API_LIVE_RECORDS=%s" % ("OK" if bool(records.get("ok", false)) else "NO_DATA"))

	dashboard.queue_free()
	print("GRUPO_RS_API_LIVE_READONLY_CHECK_DONE")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
