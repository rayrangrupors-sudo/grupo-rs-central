extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	var reload_result := dashboard_script.reload()
	if reload_result != OK:
		_fail("Dashboard nao compilou a partir do codigo atual.")
		return
	if dashboard_script == null:
		_fail("Dashboard nao carregou.")
		return
	var dashboard: Node = dashboard_script.new()

	var configs: Array = dashboard.call("_branch_configs")
	var legacy_ids: Array[String] = []
	for config in configs:
		if str((config as Dictionary).get("grupo_rs_mode", "")) == "legacy":
			legacy_ids.append(str((config as Dictionary).get("id", "")))
	if legacy_ids != ["araguaina", "acailandia", "maraba"]:
		_fail("As tres bases regionais nao foram mapeadas: %s" % str(legacy_ids))
		return

	var regional_credentials: Dictionary = dashboard.call(
		"_legacy_grupo_rs_credentials_for_branch",
		"araguaina",
		{
			"grupo_rs_legacy_araguaina_user": "regional-user",
			"grupo_rs_legacy_araguaina_password": "regional-password",
			"grupo_rs_legacy_user": "shared-user",
			"grupo_rs_legacy_password": "shared-password",
		}
	)
	if str(regional_credentials.get("username", "")) != "regional-user" or str(regional_credentials.get("password", "")) != "regional-password":
		_fail("A credencial especifica da base nao teve prioridade sobre a antiga compartilhada.")
		return

	dashboard.set("selected_branch_id", "araguaina")
	if not bool(dashboard.call("_is_regional_branch")):
		_fail("A base regional deixou de ser reconhecida.")
		return
	if str(dashboard.call("_regional_status_label", {"tracker_status": "Reserva"})) != "Estoque":
		_fail("Reserva nao foi convertida para Estoque no fluxo regional.")
		return
	if str(dashboard.call("_regional_status_label", {"tracker_status": "Inativo"})) != "Parado":
		_fail("Inativo nao foi convertido para Parado no fluxo regional.")
		return
	var regional_queue: Array = dashboard.get("internal_battery_queue")
	if not regional_queue.is_empty():
		_fail("A bateria interna ainda possui fila regional ativa.")
		return

	dashboard.free()
	print("REGIONAL_INTEGRATION_CHECK_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
