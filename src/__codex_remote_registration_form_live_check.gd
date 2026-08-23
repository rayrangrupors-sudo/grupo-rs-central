extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard: Node = DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	var page: Dictionary = await dashboard.call("_modern_grupo_rs_get", "equipamentos_editar.php?acao=novo")
	print("REMOTE_FORM_HTTP_OK=%s CODE=%s BODY_SIZE=%d" % [bool(page.get("ok", false)), int(page.get("response_code", 0)), str(page.get("body", "")).length()])
	if not bool(page.get("ok", false)):
		push_error("Nao foi possivel ler a tela real de cadastro remoto.")
		quit(1)
		return
	var html := str(page.get("body", ""))
	var regex := RegEx.new()
	if regex.compile("(?is)<form\\b[^>]*>") == OK:
		var actions: Array[String] = []
		for match_result in regex.search_all(html):
			var tag: String = match_result.get_string(0)
			var action: String = str(dashboard.call("_regex_first_group", tag, "(?is)action=[\\\"']([^\\\"']*)[\\\"']"))
			actions.append(str(action))
		print("REMOTE_FORM_ACTIONS=%s" % [str(actions)])
	var equipment_form: String = dashboard.call("_extract_html_form_by_action", html, "equipamentos_actions.php")
	if equipment_form == "":
		equipment_form = dashboard.call("_extract_html_form_by_action", html, "equipamentos_action.php")
	var build: Dictionary = dashboard.call("_build_modern_equipment_registration_fields", equipment_form, {
		"serial": "024399999",
		"apn": "hinova.br",
		"chip_number": "89555483000024956727",
		"phone": "37991183429",
		"operator": "Tim",
	})
	print("REMOTE_EQUIPMENT_FORM_FOUND=%s BUILD_FIELDS_OK=%s" % [equipment_form != "", bool(build.get("ok", false))])
	if equipment_form == "" or not bool(build.get("ok", false)):
		push_error("O parser nao reconheceu a tela real de novo equipamento.")
		quit(1)
		return
	dashboard.queue_free()
	await process_frame
	quit(0)
