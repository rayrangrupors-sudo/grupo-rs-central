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
	var login: Dictionary = await dashboard.call("_grupo_rs_api_login_with_credentials", "lucasabm", "425")
	if not bool(login.get("ok", false)):
		_fail("Login recusado: %s" % str(login.get("message", "")))
		return
	var found: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", "024003557", true)
	if not bool(found.get("ok", false)):
		_fail("Registro de teste nao encontrado.")
		return
	var request := {
		"serial": "024003557",
		"apn": "linksolutions.br",
		"chip_number": "89555483000000003557",
		"phone": "3199903557",
		"model": "RS 300",
		"operator": "Tim",
	}
	var patched: Dictionary = await dashboard.call("_grupo_rs_api_patch_equipment", request, found.get("row", {}) as Dictionary)
	if not bool(patched.get("ok", false)):
		_fail("Nao foi possivel corrigir o dado artificial: %s" % str(patched.get("message", patched)))
		return
	var final_row: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", "024003557", true)
	if not bool(final_row.get("ok", false)):
		_fail("Consulta final do reparo falhou.")
		return
	print("USER425_TEST_DATA_REPAIRED=OK serial=024003557")
	dashboard.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
