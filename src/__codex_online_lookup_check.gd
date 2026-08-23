extends SceneTree


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

	var imperatriz_button := _find_button_by_text(dashboard, "IMPERATRIZ")
	if imperatriz_button == null:
		push_error("Botao Imperatriz nao encontrado.")
		quit(1)
		return

	imperatriz_button.pressed.emit()
	await create_timer(1.8).timeout
	await process_frame

	var login_input := _find_line_edit_by_placeholder(dashboard, "Login")
	var senha_input := _find_line_edit_by_placeholder(dashboard, "Senha")
	if login_input == null or senha_input == null:
		push_error("Campos de login nao encontrados.")
		quit(1)
		return

	login_input.text = "Lucas"
	senha_input.text = String.chr(50) + String.chr(49) + String.chr(48) + String.chr(51)
	dashboard.set("selected_branch_db_path", "user://__codex_test_online_inventory.json")
	dashboard.set("selected_branch_backup_name", "__codex_test_online_inventory.json")
	dashboard.set("selected_branch_backup_dir", "user://__codex_test_online_backups")
	dashboard.call("_attempt_login")
	await process_frame
	await process_frame

	dashboard.call("_show_list")
	await process_frame
	var search_input := _find_line_edit_by_placeholder(dashboard, "Buscar por IMEI, placa, tipo ou operadora")
	if search_input == null:
		push_error("Campo de busca nao encontrado.")
		quit(1)
		return

	search_input.text = "024373321"
	dashboard.call("_submit_search")
	await create_timer(5.0).timeout
	await process_frame

	if not _has_label_or_line_edit_text(dashboard, "LUCIANA DA SILVA RODRIGUES"):
		push_error("Resultado online nao apareceu na tela.")
		quit(1)
		return
	if not _has_label_or_line_edit_text(dashboard, "Status atual") or not _has_label_or_line_edit_text(dashboard, "Bat. Int"):
		push_error("As colunas de registros nao apareceram no Grupo RS online.")
		quit(1)
		return

	var record_finished := false
	for _attempt in range(30):
		var location_cache: Dictionary = dashboard.get("location_status_cache")
		var battery_cache: Dictionary = dashboard.get("internal_battery_cache")
		var location: Dictionary = location_cache.get("024373321", {})
		var battery: Dictionary = battery_cache.get("024373321", {})
		if not location.is_empty() and str(location.get("label", "")) != "Consultando" and not battery.is_empty():
			record_finished = true
			break
		await create_timer(0.5).timeout
	if not record_finished:
		push_error("Status e Bat. Int do resultado online nao terminaram a consulta automatica.")
		quit(1)
		return

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://__codex_test_online_inventory.json"))
	print("ONLINE_LOOKUP_CHECK_OK")
	quit(0)


func _find_button_by_text(node: Node, text_value: String) -> Button:
	if node is Button and (node as Button).text == text_value:
		return node as Button

	for child in node.get_children():
		var found := _find_button_by_text(child, text_value)
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


func _has_label_or_line_edit_text(node: Node, text_value: String) -> bool:
	if node is Label and (node as Label).text == text_value:
		return true
	if node is LineEdit and (node as LineEdit).text == text_value:
		return true

	for child in node.get_children():
		if _has_label_or_line_edit_text(child, text_value):
			return true

	return false
