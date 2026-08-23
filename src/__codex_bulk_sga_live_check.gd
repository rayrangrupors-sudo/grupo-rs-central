extends SceneTree


const TEST_CUSTOMER := "JOAO DA SILVA SOARES"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := load("res://src/inventory_dashboard.gd")
	if dashboard_script == null:
		_fail("Tela principal nao carregou.")
		return
	var dashboard: Control = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_name", "imperatriz")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")

	var result: Dictionary = await dashboard.call("_lookup_sga_status_by_customer", TEST_CUSTOMER)
	var rastreio: Dictionary = result.get("rastreio", {})
	var protecao: Dictionary = result.get("protecao", {})
	var forbidden_states := ["unconfigured", "invalid_config", "login", "rs_error"]
	var rastreio_state := str(rastreio.get("state", ""))
	var protecao_state := str(protecao.get("state", ""))
	print(
		"BULK_SGA_LIVE_RESULT rastreio=%s protecao=%s"
		% [rastreio_state, protecao_state]
	)
	if rastreio_state in forbidden_states or protecao_state in forbidden_states:
		_fail("Um dos acessos reais recusou a consulta.")
		return
	if rastreio_state == "" or protecao_state == "":
		_fail("Um dos SGA nao retornou estado.")
		return

	dashboard.queue_free()
	print("BULK_SGA_LIVE_CHECK_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
