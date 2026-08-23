extends SceneTree


const BULK_DELETE_PLATES := """TYT - 3423
TTT - 1T11
BRA - 0001
GRS - T38
HFG - 4521
HGT - 4562
HJG - J785
RJF - 2525
ROE - 0F37
ROK - 0000
SDR - 6532
SHS - 1212
SLS - 139
SNF - 7C50
SOO - 8569
AAA - T248
AAA - T253
AAA - T254"""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/estoque_profissional.tscn")
	if scene == null:
		push_error("Cena principal nao carregou.")
		quit(1)
		return

	var dashboard: Node = scene.instantiate()
	root.add_child(dashboard)
	await process_frame

	if not InputMap.has_action("minimizar"):
		push_error("Acao minimizar nao existe.")
		quit(1)
		return

	var has_f11 := false
	for event in InputMap.action_get_events("minimizar"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F11:
			has_f11 = true
			break

	if not has_f11:
		push_error("Acao minimizar nao esta mapeada para F11.")
		quit(1)
		return

	var imperatriz_button := _find_button_by_text(dashboard, "IMPERATRIZ")
	if imperatriz_button == null:
		push_error("Botao Imperatriz nao encontrado.")
		quit(1)
		return

	imperatriz_button.pressed.emit()
	await process_frame
	# Este fluxo de interface usa uma filial descartavel para nao misturar a
	# fila operacional real com os registros criados pelo teste.
	dashboard.set("selected_branch_preview_store", null)
	dashboard.set("selected_branch_preview_branch_id", "")
	dashboard.set("selected_branch_db_path", "user://__codex_test_inventory.json")
	dashboard.set("selected_branch_backup_name", "__codex_test_inventory.json")
	dashboard.set("selected_branch_backup_dir", "user://__codex_test_backups")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://__codex_test_inventory.json.pending.json"))
	var imperatriz_enter := _find_button_by_text(dashboard, "Entrar")
	if imperatriz_enter == null:
		push_error("Botao Entrar de Imperatriz nao encontrado.")
		quit(1)
		return
	imperatriz_enter.pressed.emit()
	await create_timer(1.8).timeout
	await process_frame

	var login_input := _find_line_edit_by_placeholder(dashboard, "Login")
	var senha_input := _find_line_edit_by_placeholder(dashboard, "Senha")
	if login_input == null or senha_input == null:
		push_error("Campos de login nao encontrados.")
		quit(1)
		return

	login_input.text = "Lucas"
	senha_input.text = _test_password()
	dashboard.set("selected_branch_db_path", "user://__codex_test_inventory.json")
	dashboard.set("selected_branch_backup_name", "__codex_test_inventory.json")
	dashboard.set("selected_branch_backup_dir", "user://__codex_test_backups")
	dashboard.call("_attempt_login")
	var online_deadline := Time.get_ticks_msec() + 35000
	while Time.get_ticks_msec() < online_deadline and not bool(dashboard.get("online_data_available")):
		await create_timer(0.1).timeout
	dashboard.call("_show_list")
	await process_frame

	if _has_label_or_line_edit_text(dashboard, "RS300"):
		push_error("Botao RS300 ainda esta visivel na sidebar.")
		quit(1)
		return
	if not _has_label_or_line_edit_text(dashboard, "Sair"):
		push_error("Botao Sair nao esta visivel na sidebar.")
		quit(1)
		return
	if not _has_label_or_line_edit_text(dashboard, "Configurações"):
		push_error("Botao Configuracoes nao esta visivel na sidebar.")
		quit(1)
		return
	var test_vault_password := OS.get_environment("GRUPO_RS_VAULT_SETUP_PASSWORD")
	if test_vault_password.strip_edges() != "":
		var vault := root.get_node_or_null("SecretVault")
		if vault == null or not bool((vault.call("unlock_view", test_vault_password) as Dictionary).get("ok", false)):
			push_error("Cofre nao desbloqueou para a validacao de configuracoes.")
			quit(1)
			return

	dashboard.call("_show_arya_config")
	await process_frame
	if not _has_label_or_line_edit_text(dashboard, "Configuracoes") \
			or (not _has_label_or_line_edit_text(dashboard, "Grupo RS") and not _has_label_or_line_edit_text(dashboard, "Arya") and not _has_label_or_line_edit_text(dashboard, "Cofre de credenciais")):
		push_error("Aba Config. nao abriu em uma secao valida.")
		quit(1)
		return
	var grupo_config_button := _find_button_by_text(dashboard, "Grupo RS")
	if grupo_config_button == null:
		push_error("Botao interno Grupo RS nao foi encontrado na aba Config.")
		quit(1)
		return
	grupo_config_button.pressed.emit()
	await process_frame
	if not _has_label_or_line_edit_text(dashboard, "Grupo RS / Imperatriz"):
		push_error("Secao Grupo RS / Imperatriz nao apareceu na aba Config.")
		quit(1)
		return
	if _find_line_edit_by_placeholder(dashboard, "https://seu-servidor/api_rest_app") == null:
		push_error("Campo da API oficial nao foi encontrado.")
		quit(1)
		return
	var araguaina_config_button := _find_button_by_text(dashboard, "Araguaina")
	var acailandia_config_button := _find_button_by_text(dashboard, "Acailandia")
	var maraba_config_button := _find_button_by_text(dashboard, "Maraba")
	if araguaina_config_button == null or acailandia_config_button == null or maraba_config_button == null:
		push_error("Botoes das tres bases regionais nao foram encontrados.")
		quit(1)
		return
	araguaina_config_button.pressed.emit()
	await process_frame
	if not _has_label_or_line_edit_text(dashboard, "Base regional / Araguaina"):
		push_error("Pagina independente de Araguaina nao abriu.")
		quit(1)
		return
	if _find_line_edit_by_placeholder(dashboard, "https://servidor/Base/") == null:
		push_error("Campo da URL de Araguaina nao foi encontrado.")
		quit(1)
		return
	var link_config_button := _find_button_by_text(dashboard, "Link Solutions")
	if link_config_button == null:
		push_error("Botao interno Link Solutions nao foi encontrado na aba Config.")
		quit(1)
		return
	link_config_button.pressed.emit()
	await process_frame
	if _find_line_edit_by_placeholder(dashboard, "E-mail/login Link Solutions") == null:
		push_error("Secao Link Solutions nao apareceu na aba Config.")
		quit(1)
		return
	if _find_button_by_text(dashboard, "Codex") != null:
		push_error("A aba Codex foi aposentada, mas ainda apareceu na configuracao.")
		quit(1)
		return
	var updates_config_button := _find_button_by_text(dashboard, "Atualizacoes")
	if updates_config_button == null:
		push_error("Botao interno Atualizacoes nao foi encontrado na aba Config.")
		quit(1)
		return
	updates_config_button.pressed.emit()
	await process_frame
	if _find_line_edit_by_placeholder(dashboard, "Caminho local ou URL HTTPS do manifest.json") == null:
		push_error("Origem das atualizacoes nao apareceu na aba Config.")
		quit(1)
		return
	var update_version_label: Label = dashboard.get("update_version_label")
	if _find_button_by_text(dashboard, "Verificar agora") == null \
			or _find_button_by_text(dashboard, "Reiniciar e aplicar") == null \
			or update_version_label == null \
			or not update_version_label.text.begins_with("v"):
		push_error("Controles ou versao do atualizador nao apareceram.")
		quit(1)
		return

	dashboard.call("_show_bulk_registration")
	await process_frame
	if _find_button_by_text(dashboard, "Excluir em massa") != null:
		push_error("Botao de exclusao em massa ainda apareceu no cadastro em massa.")
		quit(1)
		return

	dashboard.call("_show_maintenance_register")
	await process_frame
	var maintenance_input := _find_text_edit_with_placeholder(dashboard, "Cole aqui as manutencoes")
	if maintenance_input == null:
		push_error("Campo de cadastro de manutencoes nao encontrado.")
		quit(1)
		return

	maintenance_input.text = "CLIENTE TESTE\tABC - 1234\t024288263\tlinksolutions\t(83) 99999-9999\t30/06/2026 09:00:00"
	dashboard.call("_register_maintenances", false)
	await process_frame

	dashboard.call("_show_maintenance_schedule")
	await process_frame
	if not _has_label_or_line_edit_text(dashboard, "CLIENTE TESTE"):
		push_error("Manutencao cadastrada nao apareceu em agendamentos.")
		quit(1)
		return

	var schedule_button := _find_button_by_tooltip(dashboard, "Agendar retorno")
	if schedule_button == null:
		push_error("Acao de agendamento nao encontrada na manutencao.")
		quit(1)
		return
	schedule_button.pressed.emit()
	await process_frame

	var note_input := _find_text_edit_with_placeholder(dashboard, "Observacao")
	if note_input == null:
		push_error("Campo de observacao nao encontrado no agendamento.")
		quit(1)
		return
	note_input.text = "cliente pediu retorno"

	var date_input := _find_line_edit_by_placeholder(dashboard, "dd/mm/aaaa")
	var time_input := _find_line_edit_by_placeholder(dashboard, "00:00")
	var save_schedule_button := _find_button_by_text(dashboard, "Salvar")
	if date_input == null or time_input == null or save_schedule_button == null:
		push_error("Campos de data/hora ou botao Salvar nao encontrados.")
		quit(1)
		return

	date_input.text = "30/06/2026"
	time_input.text = "10:30"
	save_schedule_button.pressed.emit()
	await process_frame

	dashboard.call("_show_maintenance_done_schedule")
	await process_frame
	var search_input := _find_line_edit_by_placeholder(dashboard, "Buscar por nome, serie, placa ou data")
	if search_input == null:
		push_error("Busca de agendamentos OK nao encontrada.")
		quit(1)
		return

	search_input.text = "024288263"
	search_input.text_changed.emit(search_input.text)
	await process_frame
	if not _has_label_or_line_edit_text(dashboard, "CLIENTE TESTE"):
		push_error("Agendamento OK nao apareceu na busca por serie.")
		quit(1)
		return

	var complete_button := _find_button_by_text(dashboard, "Concluido")
	if complete_button == null:
		push_error("Botao Concluido nao encontrado.")
		quit(1)
		return
	var test_store = dashboard.get("store")
	var scheduled_rows: Array = test_store.get_scheduled_maintenances("024288263")
	if scheduled_rows.is_empty():
		push_error("Agendamento OK nao foi salvo no banco.")
		quit(1)
		return
	if str(scheduled_rows[0].get("note", "")) != "cliente pediu retorno":
		push_error("Observacao nao foi salva automaticamente.")
		quit(1)
		return
	dashboard.call("_complete_maintenance", str(scheduled_rows[0].get("id", "")))
	await process_frame

	var pagination_rows: Array[Dictionary] = []
	for index in range(23):
		pagination_rows.append({
			"client": "CLIENTE PAGINA %02d" % index,
			"plate": "PGN - %04d" % index,
			"serial": "0248%05d" % index,
			"note": "Teste de paginacao %02d" % index,
		})
	test_store.add_maintenances(pagination_rows)
	dashboard.call("_show_maintenance_schedule")
	await process_frame

	var maintenance_body = dashboard.get("maintenance_schedule_body")
	if maintenance_body == null or maintenance_body.get_child_count() != 10:
		push_error("Lista de manutencoes deveria renderizar exatamente 10 registros por pagina.")
		quit(1)
		return
	var maintenance_page_info = dashboard.get("maintenance_page_info_label")
	if maintenance_page_info == null or not str(maintenance_page_info.text).contains("Mostrando 1-10 de 23"):
		push_error("Resumo da paginacao de manutencoes incorreto.")
		quit(1)
		return
	var next_maintenance_page := _find_button_by_text(dashboard, "Proximo")
	if next_maintenance_page == null or next_maintenance_page.disabled:
		push_error("Botao Proximo da manutencao nao foi criado.")
		quit(1)
		return
	next_maintenance_page.pressed.emit()
	await process_frame
	if int(dashboard.get("maintenance_current_page")) != 1 or maintenance_body.get_child_count() != 10:
		push_error("Segunda pagina da manutencao nao preservou o limite de 10 registros.")
		quit(1)
		return

	var maintenance_search := _find_line_edit_by_placeholder(dashboard, "Buscar cliente, placa, serie ou observacao")
	if maintenance_search == null:
		push_error("Busca da lista de manutencoes nao foi criada.")
		quit(1)
		return
	maintenance_search.text = "024800022"
	maintenance_search.text_changed.emit(maintenance_search.text)
	await process_frame
	if maintenance_body.get_child_count() != 1 or not _has_label_or_line_edit_text(dashboard, "CLIENTE PAGINA 22"):
		push_error("Busca da manutencao nao filtrou a serie esperada.")
		quit(1)
		return

	var second_dashboard: Node = scene.instantiate()
	root.add_child(second_dashboard)
	await process_frame
	var acailandia_button := _find_button_by_text(second_dashboard, "ACAILANDIA")
	if acailandia_button == null:
		push_error("Botao Acailandia nao encontrado.")
		quit(1)
		return

	acailandia_button.pressed.emit()
	await process_frame
	var acailandia_enter := _find_button_by_text(second_dashboard, "Entrar")
	if acailandia_enter == null:
		push_error("Botao Entrar de Acailandia nao encontrado.")
		quit(1)
		return
	acailandia_enter.pressed.emit()
	await create_timer(1.8).timeout
	second_dashboard.call("_attempt_login")
	var second_login := _find_line_edit_by_placeholder(second_dashboard, "Login")
	var second_senha := _find_line_edit_by_placeholder(second_dashboard, "Senha")
	if second_login == null or second_senha == null:
		push_error("Login de Acailandia nao abriu.")
		quit(1)
		return
	second_login.text = "Lucas"
	second_senha.text = _test_password()
	second_dashboard.call("_attempt_login")
	await process_frame
	if str(second_dashboard.get("selected_branch_db_path")) != "user://inventory_db_acailandia.json":
		push_error("Banco de Acailandia nao esta separado.")
		quit(1)
		return

	if not dashboard.has_method("_minimize_window"):
		push_error("Funcao _minimize_window nao existe.")
		quit(1)
		return

	dashboard.call("_minimize_window")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://__codex_test_inventory.json"))
	print("UI_CHECK_OK")
	quit(0)


func _find_new_button(node: Node) -> Button:
	if node is Button:
		var button := node as Button
		if button.text == "" and _has_new_label(button) and _has_icon(button):
			return button

	for child in node.get_children():
		var found := _find_new_button(child)
		if found != null:
			return found

	return null


func _find_button_by_text(node: Node, text_value: String) -> Button:
	if node is Button and (node as Button).text == text_value:
		return node as Button

	for child in node.get_children():
		var found := _find_button_by_text(child, text_value)
		if found != null:
			return found

	return null


func _find_button_by_tooltip(node: Node, tooltip: String) -> Button:
	if node is Button and (node as Button).tooltip_text == tooltip:
		return node as Button

	for child in node.get_children():
		var found := _find_button_by_tooltip(child, tooltip)
		if found != null:
			return found

	return null


func _find_line_edit_by_placeholder(node: Node, placeholder: String) -> LineEdit:
	if node is LineEdit and (node as LineEdit).placeholder_text == placeholder:
		return node as LineEdit

	for child in node.get_children():
		var found := _find_line_edit_by_placeholder(child, placeholder)
		if found != null:
			return found

	return null


func _find_text_edit_with_placeholder(node: Node, placeholder_start: String) -> TextEdit:
	if node is TextEdit and (node as TextEdit).placeholder_text.begins_with(placeholder_start):
		return node as TextEdit

	for child in node.get_children():
		var found := _find_text_edit_with_placeholder(child, placeholder_start)
		if found != null:
			return found

	return null


func _has_label_or_line_edit_text(node: Node, text_value: String) -> bool:
	if node is Label and (node as Label).text == text_value:
		return true
	if node is LineEdit and (node as LineEdit).text == text_value:
		return true

	for child in node.get_children():
		if _has_label_or_line_edit_text(child, text_value):
			return true

	return false


func _has_label_text_containing(node: Node, text_value: String) -> bool:
	if node is Label and (node as Label).text.contains(text_value):
		return true

	for child in node.get_children():
		if _has_label_text_containing(child, text_value):
			return true

	return false


func _has_new_label(node: Node) -> bool:
	if node is Label and (node as Label).text == "Novo":
		return true

	for child in node.get_children():
		if _has_new_label(child):
			return true

	return false


func _has_icon(node: Node) -> bool:
	if node is TextureRect and (node as TextureRect).texture != null:
		return true

	for child in node.get_children():
		if _has_icon(child):
			return true

	return false


func _test_password() -> String:
	return String.chr(50) + String.chr(49) + String.chr(48) + String.chr(51)
