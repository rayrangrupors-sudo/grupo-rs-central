extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	var reload_error := dashboard_script.reload()
	if reload_error != OK:
		_fail("Dashboard nao compilou no teste: %s" % reload_error)
		return
	if dashboard_script == null:
		_fail("Script do dashboard nao carregou.")
		return
	var dashboard: Node = dashboard_script.new()

	dashboard.set("selected_branch_id", "imperatriz")
	_expect(bool(dashboard.call("_branch_supports_sms")), "Imperatriz perdeu SMS.")
	_expect(not bool(dashboard.call("_branch_supports_auto_monitor")), "Monitor automatico aposentado voltou a ficar ativo.")
	_expect(bool(dashboard.call("_branch_supports_monitor_4g")), "Imperatriz perdeu Monitor 4G.")

	for branch_id in ["araguaina", "acailandia", "maraba"]:
		dashboard.set("selected_branch_id", branch_id)
		dashboard.set("selected_branch_grupo_rs_mode", "legacy")
		_expect(not bool(dashboard.call("_branch_supports_sms")), "%s ainda libera SMS." % branch_id)
		_expect(not bool(dashboard.call("_branch_supports_auto_monitor")), "%s ainda libera monitor automatico." % branch_id)
		_expect(not bool(dashboard.call("_branch_supports_monitor_4g")), "%s ainda libera Monitor 4G." % branch_id)
		_expect(bool(dashboard.call("_branch_supports_stock_sync")), "%s perdeu sincronizacao de estoque." % branch_id)
		_expect(bool(dashboard.call("_is_regional_branch")), "%s nao foi reconhecida como base regional." % branch_id)
		_expect(str(dashboard.call("_regional_status_label", {"tracker_status": "Reserva"})) == "Estoque", "%s nao normalizou Reserva para Estoque." % branch_id)
		_expect(str(dashboard.call("_regional_status_label", {"tracker_status": "Manutencao"})) == "Parado", "%s nao normalizou Manutencao para Parado." % branch_id)
		_expect(str(dashboard.call("_regional_status_label", {"tracker_status": "Instalado"})) == "Instalado", "%s alterou Instalado indevidamente." % branch_id)

		var table_header: Control = dashboard.call("_build_table_header")
		_expect(not _has_text(table_header, "Chip"), "%s exibiu coluna Chip." % branch_id)
		_expect(_has_text(table_header, "Acoes"), "%s nao exibiu coluna de acoes." % branch_id)
		table_header.free()

		var row: Control = dashboard.call("_make_table_row", {
			"sku": "024300001",
			"imei": "024300001",
			"plate": "GRS - T91",
			"model": "Novo",
			"operator": "Tim",
			"tracker_status": "Reserva",
		})
		_expect(_has_text(row, "Estoque"), "%s nao exibiu Reserva como Estoque." % branch_id)
		_expect(not _has_text(row, "Editar"), "%s exibiu edicao operacional." % branch_id)
		_expect(_has_text(row, "Dar baixa"), "%s nao exibiu o botao Dar baixa." % branch_id)
		_expect(_has_type(row, "LineEdit"), "%s nao exibiu campo de placa editavel." % branch_id)
		_expect(_find_tooltip(row, "Excluir registro local"), "%s nao exibiu exclusao local." % branch_id)
		row.free()

		var bulk: Control = dashboard.call("_build_bulk_command_toolbar")
		_expect(not _has_text(bulk, "Reset SMS massa"), "%s exibiu reset SMS em massa." % branch_id)
		_expect(not _has_text(bulk, "Consultar clientes"), "%s exibiu consulta de clientes." % branch_id)
		_expect(not _has_text(bulk, "Consultar SGA"), "%s exibiu consulta SGA." % branch_id)
		bulk.free()

	dashboard.free()
	print("REGIONAL_BASE_POLICY_CHECK_OK")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _find_tooltip(root: Node, expected: String) -> bool:
	if root is Control and str((root as Control).tooltip_text) == expected:
		return true
	for child in root.get_children():
		if _find_tooltip(child, expected):
			return true
	return false


func _has_text(root: Node, expected: String) -> bool:
	if root is Button and str((root as Button).text).contains(expected):
		return true
	if root is Label and str((root as Label).text).contains(expected):
		return true
	for child in root.get_children():
		if _has_text(child, expected):
			return true
	return false


func _has_type(root: Node, expected: String) -> bool:
	if root.get_class() == expected:
		return true
	for child in root.get_children():
		if _has_type(child, expected):
			return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
