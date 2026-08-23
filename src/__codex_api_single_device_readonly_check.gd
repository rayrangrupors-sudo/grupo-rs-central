extends SceneTree


const TEST_SERIAL := "024379377"


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

	print("API_TEST_SERIAL=%s" % TEST_SERIAL)
	var login: Dictionary = await dashboard.call("_grupo_rs_api_login")
	if not bool(login.get("ok", false)):
		_fail("Login API recusado: %s" % str(login.get("message", "")))
		return
	print("API_LOGIN=OK")

	var equipment_result: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", TEST_SERIAL, true)
	if not bool(equipment_result.get("ok", false)):
		_fail("Equipamento nao encontrado: %s" % str(equipment_result.get("message", "")))
		return
	var equipment := equipment_result.get("row", {}) as Dictionary
	print("API_EQUIPMENT=OK %s" % JSON.stringify(equipment))

	var vehicle_result: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", "", TEST_SERIAL, true)
	if not bool(vehicle_result.get("ok", false)):
		print("API_VEHICLE=NO_DATA message=%s" % str(vehicle_result.get("message", "")))
	else:
		var vehicle := vehicle_result.get("row", {}) as Dictionary
		var plate := str(vehicle.get("plate", ""))
		var vehicle_id := str(vehicle.get("vehicle_id", ""))
		print("API_VEHICLE=OK %s" % JSON.stringify(vehicle))

		var location_result: Dictionary = await dashboard.call("_grupo_rs_api_find_location", TEST_SERIAL, plate)
		if bool(location_result.get("ok", false)):
			print("API_LOCATION=OK %s" % JSON.stringify(location_result.get("location", {})))
		else:
			print("API_LOCATION=NO_DATA message=%s" % str(location_result.get("message", "")))

		if vehicle_id != "":
			var now := Time.get_date_string_from_system()
			var records: Dictionary = await dashboard.call("_grupo_rs_api_latest_event", vehicle_id, now + " 23:59:59")
			if bool(records.get("ok", false)):
				print("API_RECORD=OK %s" % JSON.stringify(records.get("event", records)))
			else:
				print("API_RECORD=NO_DATA message=%s" % str(records.get("message", "")))

	dashboard.queue_free()
	print("API_SINGLE_DEVICE_READONLY_CHECK_DONE")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
