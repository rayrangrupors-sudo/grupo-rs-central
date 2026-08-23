extends SceneTree

const SERIALS := ["997326645", "997326976"]

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
	var started := Time.get_ticks_msec()
	var login: Dictionary = await dashboard.call("_grupo_rs_api_login")
	print("TIMING_LOGIN_MS=%d ok=%s" % [Time.get_ticks_msec() - started, str(login.get("ok", false))])
	if not bool(login.get("ok", false)):
		_fail(str(login.get("message", "login falhou")))
		return
	for serial in SERIALS:
		var query_started := Time.get_ticks_msec()
		var rows: Array = await dashboard.call("_fetch_grupo_rs_equipment_rows", serial)
		var elapsed := Time.get_ticks_msec() - query_started
		var plate := ""
		if not rows.is_empty():
			plate = str((rows[0] as Dictionary).get("plate", ""))
		print("TIMING_QUERY serial=%s ms=%d rows=%d plate=%s" % [serial, elapsed, rows.size(), plate])
	dashboard.queue_free()
	await process_frame
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
