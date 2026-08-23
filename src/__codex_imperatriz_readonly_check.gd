extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		_fail("Dashboard atual nao compilou.")
		return
	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_name", "IMPERATRIZ")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")

	var modern_credentials: Dictionary = dashboard.call("_modern_grupo_rs_credentials")
	var link_credentials: Dictionary = dashboard.call("_linksolutions_credentials")
	var modern_user := str(modern_credentials.get("username", "")).strip_edges()
	var modern_password := str(modern_credentials.get("password", ""))
	var link_user := str(link_credentials.get("username", "")).strip_edges()
	var link_password := str(link_credentials.get("password", ""))
	print("CREDENTIAL_SOURCE GrupoRS_user=%s GrupoRS_password=%s Link_user=%s Link_password=%s" % [
		"OK" if modern_user != "" else "MISSING",
		"OK" if modern_password != "" else "MISSING",
		"OK" if link_user != "" else "MISSING",
		"OK" if link_password != "" else "MISSING",
	])

	var group_login: Dictionary = await dashboard.call("_modern_grupo_rs_login")
	print("IMPERATRIZ_GRUPO_RS login=%s" % ("OK" if bool(group_login.get("ok", false)) else "FAIL"))

	var arya_login: Dictionary = await dashboard.call("_ensure_arya_token", true)
	print("IMPERATRIZ_ARYA login=%s" % ("OK" if bool(arya_login.get("ok", false)) else "FAIL"))
	var link_login: Dictionary = await dashboard.call("_request_linksolutions_login")
	print("IMPERATRIZ_LINKSOLUTIONS login=%s" % ("OK" if bool(link_login.get("ok", false)) else "FAIL"))

	if not bool(group_login.get("ok", false)):
		_fail("Grupo RS novo recusou a sessao; leituras publicas permanecem disponiveis, mas alteracoes protegidas exigem credencial valida.")
		return
	if not bool(arya_login.get("ok", false)):
		_fail("Arya recusou a sessao; consulta de chip fica bloqueada.")
		return
	if not bool(link_login.get("ok", false)):
		_fail("Link Solutions recusou a sessao; chips dessa APN ficam bloqueados.")
		return

	print("IMPERATRIZ_READONLY_CHECK_OK")
	dashboard.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
