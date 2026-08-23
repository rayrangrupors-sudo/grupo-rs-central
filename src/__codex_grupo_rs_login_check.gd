extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard: Node = DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set("selected_branch_id", "__codex_grupo_rs_login")
	dashboard.set("selected_branch_name", "Teste")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")

	var result: Dictionary = await dashboard.call("_modern_grupo_rs_login")
	if not bool(result.get("ok", false)):
		push_error("Login do Grupo RS novo falhou: %s" % str(result.get("message", "")))
		dashboard.queue_free()
		quit(1)
		return

	print("GRUPO_RS_MODERN_LOGIN_CHECK_OK")
	dashboard.set("selected_branch_grupo_rs_mode", "legacy")
	dashboard.set(
		"selected_branch_grupo_rs_base_url",
		str(dashboard.call("_legacy_grupo_rs_delete_base_url"))
	)
	dashboard.set(
		"selected_branch_grupo_rs_platform_url",
		str(dashboard.call("_legacy_grupo_rs_delete_platform_url"))
	)
	var legacy_result: Dictionary = await dashboard.call("_legacy_grupo_rs_login")
	if not bool(legacy_result.get("ok", false)):
		push_error("Login do Grupo RS antigo falhou: %s" % str(legacy_result.get("message", "")))
		dashboard.queue_free()
		quit(1)
		return
	print("GRUPO_RS_LEGACY_LOGIN_CHECK_OK")
	dashboard.queue_free()
	await process_frame
	quit(0)
