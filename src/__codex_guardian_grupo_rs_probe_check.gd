extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := load("res://src/inventory_dashboard.gd")
	if dashboard_script == null:
		push_error("Dashboard nao carregou.")
		quit(1)
		return

	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame

	dashboard.set("selected_branch_id", "__codex_guardian_probe")
	dashboard.set("selected_branch_name", "Teste")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")

	var credentials: Dictionary = dashboard.call("_modern_grupo_rs_credentials")
	if str(credentials.get("password", "")) != "":
		print("GUARDIAN_GRUPO_RS_CREDENTIALS_PRESENT")
	else:
		print("GUARDIAN_GRUPO_RS_CREDENTIALS_EMPTY_OK")

	var probe: Dictionary = await dashboard.call("_guardian_probe_grupo_rs")
	if str(probe.get("status", "")) != "ok":
		push_error("Sonda Grupo RS deveria funcionar em modo leitura: %s" % str(probe))
		dashboard.queue_free()
		await process_frame
		quit(1)
		return

	dashboard.queue_free()
	await process_frame
	print("GUARDIAN_GRUPO_RS_PROBE_CHECK_OK")
	quit(0)
