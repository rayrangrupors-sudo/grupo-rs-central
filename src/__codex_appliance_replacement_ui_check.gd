extends SceneTree


var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Load the source directly so this focused check is not affected by an older
	# compiled script cache left by a published build.
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		_fail("Dashboard nao carregou.")
		return
	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame
	var store_script := load("res://src/inventory_store.gd")
	var store: RefCounted = store_script.new()
	store.call("configure", "user://__codex_replacement_ui.json", "__codex_replacement_ui.json", "user://__codex_replacement_backups", true)
	store.call("load_db")
	dashboard.set("store", store)

	var list_view: Control = dashboard.call("_build_list_view")
	root.add_child(list_view)
	await process_frame

	var replacement_button := _find_button(list_view, "Trocar aparelho")
	_expect(replacement_button != null, "Botao Trocar aparelho nao apareceu abaixo dos controles.")
	if replacement_button != null:
		replacement_button.pressed.emit()
		await process_frame

	var client_input := _find_line_edit(dashboard, "Ex.: AAA - C40")
	var swap_input := _find_line_edit(dashboard, "Ex.: PTP - 0H26")
	_expect(client_input != null, "Campo Placa cliente nao apareceu no modal.")
	_expect(swap_input != null, "Campo Placa troca nao apareceu no modal.")

	if client_input != null and swap_input != null:
		client_input.text = "AAA - C40"
		swap_input.text = "PTP - 0H26"
		var confirm_button := _find_button(dashboard, "Confirmar troca")
		_expect(confirm_button != null, "Botao Confirmar troca nao apareceu no modal.")
		_expect(confirm_button != null and not confirm_button.disabled, "Botao Confirmar troca iniciou desabilitado.")

	dashboard.call("_close_appliance_replacement_modal")
	dashboard.call("_show_appliance_replacement_success", {
		"prepared": {
			"client_plate": "AAA - C43",
			"swap_plate": "PTP - 0H26",
			"target_serial": "024312725",
			"source_serial": "024288081",
			"maintenance_plate": "MANUT - 001",
		},
		"local": {"message": ""},
	})
	await process_frame
	_expect(_find_label_containing(dashboard, "Troca concluida") != null, "Layout de sucesso nao apareceu.")
	_expect(_find_label_containing(dashboard, "Historico e registros preservados") != null, "Aviso de preservacao nao apareceu no sucesso.")
	_expect(_find_button(dashboard, "Entendi") != null, "Botao Entendi nao apareceu no sucesso.")
	var success_button := _find_button(dashboard, "Entendi")
	if success_button != null:
		success_button.pressed.emit()
	await process_frame
	list_view.queue_free()
	dashboard.queue_free()
	await process_frame

	if failures.is_empty():
		print("APPLIANCE_REPLACEMENT_UI_CHECK_OK")
		quit(0)
	else:
		print("APPLIANCE_REPLACEMENT_UI_CHECK_FAILED: %d" % failures.size())
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _find_button(node: Node, text_value: String) -> Button:
	if node is Button and str((node as Button).text) == text_value:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, text_value)
		if found != null:
			return found
	return null


func _find_line_edit(node: Node, placeholder: String) -> LineEdit:
	if node is LineEdit and str((node as LineEdit).placeholder_text) == placeholder:
		return node as LineEdit
	for child in node.get_children():
		var found := _find_line_edit(child, placeholder)
		if found != null:
			return found
	return null


func _find_label_containing(node: Node, fragment: String) -> Label:
	if node is Label and str((node as Label).text).contains(fragment):
		return node as Label
	for child in node.get_children():
		var found := _find_label_containing(child, fragment)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
