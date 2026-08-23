extends SceneTree

const SERIAL := "997326976"

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
		_fail("Login recusado: %s" % str(login.get("message", "")))
		return
	var equipment: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", SERIAL, true)
	if not bool(equipment.get("ok", false)):
		_fail("Equipamento nao encontrado: %s" % str(equipment.get("message", "")))
		return
	var vehicle: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", "", SERIAL, true, true)
	print("LIVE_READ_OK serial=%s equipment=%s vehicle=%s" % [SERIAL, str(equipment.get("row", {})), str(vehicle.get("row", {}))])
	dashboard.queue_free()
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
