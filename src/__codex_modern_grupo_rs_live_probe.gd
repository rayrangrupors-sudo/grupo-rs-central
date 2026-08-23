extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard: Node = DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set("selected_branch_id", "__codex_modern_live_probe")
	dashboard.set("selected_branch_name", "Imperatriz")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")

	var login: Dictionary = await dashboard.call("_modern_grupo_rs_login")
	if not bool(login.get("ok", false)):
		push_error("PROBE_LOGIN_FAILED: %s" % str(login.get("message", "")))
		dashboard.queue_free()
		quit(1)
		return

	var vehicle_page: Dictionary = await dashboard.call("_modern_grupo_rs_get", "veiculos_editar.php?acao=novo")
	if not bool(vehicle_page.get("ok", false)):
		push_error("PROBE_VEHICLE_FORM_FAILED: %s" % str(vehicle_page.get("message", "")))
		dashboard.queue_free()
		quit(1)
		return
	var form_html: String = str(dashboard.call(
		"_extract_html_form_by_action",
		str(vehicle_page.get("body", "")),
		"veiculos_actions.php"
	))
	var options: Array[Dictionary] = dashboard.call("_legacy_select_options", form_html, "TrocarEquip")
	var available_serial := ""
	for option in options:
		var label := str(option.get("label", "")).strip_edges()
		if label != "" and label.to_lower() != "nao trocar":
			available_serial = label
			break
	if form_html == "" or available_serial == "":
		push_error("PROBE_VEHICLE_EQUIPMENT_OPTION_FAILED: nenhum aparelho livre apareceu em TrocarEquip")
		dashboard.queue_free()
		quit(1)
		return

	var equipment_response: Dictionary = await dashboard.call(
		"_modern_grupo_rs_get",
		"equipamentos_listar.php?busca=%s&status=todos" % available_serial.uri_encode()
	)
	if not bool(equipment_response.get("ok", false)):
		push_error("PROBE_EQUIPMENT_LIST_FAILED: %s" % str(equipment_response.get("message", "")))
		dashboard.queue_free()
		quit(1)
		return
	var equipment_rows: Array[Dictionary] = dashboard.call(
		"_parse_grupo_rs_equipment_rows",
		str(equipment_response.get("body", ""))
	)
	var equipment_found := false
	for row in equipment_rows:
		if str(row.get("serial", "")).strip_edges() == available_serial:
			equipment_found = true
			break
	if not equipment_found:
		push_error("PROBE_EQUIPMENT_PARSE_FAILED: equipamento livre nao foi lido da lista")
		dashboard.queue_free()
		quit(1)
		return

	print("MODERN_GRUPO_RS_LIVE_READONLY_OK equipment_rows=%d vehicle_equipment_option=true serial=%s" % [equipment_rows.size(), available_serial])
	dashboard.queue_free()
	await process_frame
	quit(0)
