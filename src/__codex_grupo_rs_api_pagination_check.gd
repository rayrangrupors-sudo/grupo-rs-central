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

	if str(dashboard.call("_grupo_rs_api_page_path", "/endpoints/localizacao.php", 50, 50)) != "/endpoints/localizacao.php?skip=50&take=50":
		_fail("URL paginada sem skip/take esperados.")
		return
	if str(dashboard.call("_grupo_rs_api_page_path", "/endpoints/v1/registros/listar.php?codVeiculo=1", 100, 50)) != "/endpoints/v1/registros/listar.php?codVeiculo=1&skip=100&take=50":
		_fail("URL paginada com parametros existentes foi montada incorretamente.")
		return

	var more_state: Dictionary = dashboard.call("_grupo_rs_api_pagination_state", {
		"paginacao": {"temMais": true, "proximoSkip": 50}
	}, 0, 50)
	if not bool(more_state.get("has_more", false)) or int(more_state.get("next_skip", -1)) != 50:
		_fail("Estado de pagina seguinte nao foi reconhecido.")
		return
	var last_state: Dictionary = dashboard.call("_grupo_rs_api_pagination_state", {
		"paginacao": {"temMais": false, "proximoSkip": 100}
	}, 50, 50)
	if bool(last_state.get("has_more", true)):
		_fail("Estado da ultima pagina foi interpretado como ainda pendente.")
		return

	dashboard.queue_free()
	print("GRUPO_RS_API_PAGINATION_CHECK_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
