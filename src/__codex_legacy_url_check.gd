extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := load("res://src/inventory_dashboard.gd")
	if dashboard_script == null:
		_fail("Dashboard nao carregou.")
		return
	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame

	dashboard.set("selected_branch_grupo_rs_base_url", "https://sis.sosrastrear.com.br/Cadastros/EquipamentosListar")
	if str(dashboard.call("_legacy_grupo_rs_root_url")) != "https://sis.sosrastrear.com.br":
		_fail("A URL de equipamentos nao foi reduzida para a raiz correta.")
		return
	if str(dashboard.call("_legacy_grupo_rs_url", "/Login/Login")) != "https://sis.sosrastrear.com.br/Login/Login":
		_fail("O login foi montado em um caminho invalido.")
		return
	if str(dashboard.call("_legacy_grupo_rs_url", "/Cadastros/EquipamentosListar")) != "https://sis.sosrastrear.com.br/Cadastros/EquipamentosListar":
		_fail("A rota de equipamentos nao foi preservada.")
		return
	if str(dashboard.call("_legacy_grupo_rs_delete_base_url")) != "https://sis.sosrastrear.com.br/Cadastros/EquipamentosListar":
		_fail("A URL antiga salva nao foi migrada para o novo acesso.")
		return

	dashboard.set("selected_branch_grupo_rs_base_url", "https://sis.sosrastrear.com.br/Base/FrmPrincipal")
	if str(dashboard.call("_legacy_grupo_rs_root_url")) != "https://sis.sosrastrear.com.br":
		_fail("A rota antiga anterior deixou de ser aceita.")
		return

	dashboard.queue_free()
	await process_frame
	print("LEGACY_URL_CHECK_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
