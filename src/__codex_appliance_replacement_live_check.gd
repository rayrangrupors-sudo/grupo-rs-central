extends SceneTree


const TEST_SERIALS := ["024003657", "024004048"]


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
		_fail("Login API falhou: %s" % str(login.get("message", "")))
		return
	var serials: Array = TEST_SERIALS
	var requested_serial := OS.get_environment("CODEX_SWAP_LIVE_SERIAL").strip_edges()
	if requested_serial != "":
		serials = [requested_serial]
	for serial in serials:
		var equipment: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
		var vehicle: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", "", serial, true, true)
		print("LIVE_SWAP_READ serial=%s equipment=%s vehicle=%s plate=%s client=%s" % [
			serial,
			"OK" if bool(equipment.get("ok", false)) else "NO",
			"OK" if bool(vehicle.get("ok", false)) else "NO",
			str((vehicle.get("row", {}) as Dictionary).get("plate", "")),
			str((vehicle.get("row", {}) as Dictionary).get("client", "")),
		])
	dashboard.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
