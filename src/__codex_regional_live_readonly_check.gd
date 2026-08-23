extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		push_error("Nao foi possivel compilar o dashboard atual.")
		quit(1)
		return

	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame

	var failures: Array[String] = []
	var configs: Array = dashboard.call("_branch_configs")
	for raw_config in configs:
		var config := raw_config as Dictionary
		if str(config.get("grupo_rs_mode", "")) != "legacy":
			continue
		var branch_id := str(config.get("id", "")).strip_edges().to_lower()
		dashboard.set("selected_branch_id", branch_id)
		dashboard.set("selected_branch_name", str(config.get("name", "")))
		dashboard.set("selected_branch_grupo_rs_mode", "legacy")
		dashboard.set("selected_branch_grupo_rs_base_url", str(config.get("grupo_rs_base_url", "")))
		dashboard.set("selected_branch_grupo_rs_platform_url", str(config.get("grupo_rs_platform_url", "")))

		var login: Dictionary = await dashboard.call("_legacy_grupo_rs_login")
		if not bool(login.get("ok", false)):
			failures.append("%s login" % branch_id)
			print("REGIONAL_LIVE %s login=FAIL" % branch_id)
			continue

		var equipment_page: Dictionary = await dashboard.call("_legacy_grupo_rs_get", "/Cadastros/EquipamentosListar")
		var location_page: Dictionary = await dashboard.call("_legacy_grupo_rs_get", "/Geral/LocalizacaoView")
		var equipment_ok := bool(equipment_page.get("ok", false))
		var location_ok := bool(location_page.get("ok", false))
		if not equipment_ok:
			failures.append("%s equipamentos" % branch_id)
		if not location_ok:
			failures.append("%s localizacao" % branch_id)
		print("REGIONAL_LIVE %s login=OK equipamentos_http=%s(%d bytes) localizacao_http=%s(%d bytes)" % [
			branch_id,
			"OK" if equipment_ok else "FAIL",
			str(equipment_page.get("body", "")).length(),
			"OK" if location_ok else "FAIL",
			str(location_page.get("body", "")).length(),
		])

	dashboard.queue_free()
	await process_frame
	if failures.is_empty():
		print("REGIONAL_LIVE_READONLY_CHECK_OK")
		quit(0)
	else:
		push_error("Falhas na leitura real: %s" % ", ".join(failures))
		quit(1)
