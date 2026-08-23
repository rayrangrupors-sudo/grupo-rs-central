extends SceneTree

const MainScene := preload("res://scenes/estoque_profissional.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard: Node = MainScene.instantiate()
	root.add_child(dashboard)
	await process_frame

	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_name", "IMPERATRIZ")
	dashboard.call("_clear_screen")
	await process_frame

	var sidebar: Control = dashboard.call("_build_sidebar")
	root.add_child(sidebar)
	await process_frame

	var group := sidebar.find_child("SidebarEquipmentGroup", true, false)
	var toggle := sidebar.find_child("SidebarEquipmentToggle", true, false) as Button
	if toggle == null:
		var buttons: Dictionary = dashboard.get("sidebar_buttons")
		toggle = buttons.get("equipment_group") as Button
	_check(group != null, "Grupo Equipamentos nao foi criado.")
	_check(toggle != null, "Botao Equipamentos nao foi criado.")
	if toggle == null:
		_finish()
		return

	var children := sidebar.find_child("SidebarEquipmentChildren", true, false) as VBoxContainer
	_check(children != null, "Container dos filhos de Equipamentos nao foi criado.")
	_check(bool(toggle.get_meta("expanded", false)), "Equipamentos nao iniciou expandido.")
	_check(_button_with_label(sidebar, "Estoque") != null, "Filho Estoque nao foi encontrado.")
	_check(_button_with_label(sidebar, "Localização") != null, "Filho Localização nao foi encontrado.")
	_check(_button_with_label(sidebar, "Cadastro em massa") != null, "Filho Cadastro em massa nao foi encontrado.")

	toggle.pressed.emit()
	await process_frame
	_check(not bool(toggle.get_meta("expanded", true)), "Equipamentos nao recolheu.")
	_check(children != null and not children.visible, "Filhos continuaram visiveis recolhido.")
	var chevron := toggle.find_child("SidebarChevron", true, false) as Label
	_check(chevron != null and chevron.text == "⌄", "Chevron recolhido nao foi atualizado.")

	toggle.pressed.emit()
	await process_frame
	_check(bool(toggle.get_meta("expanded", false)), "Equipamentos nao expandiu novamente.")
	_check(children != null and children.visible, "Filhos nao reapareceram ao expandir.")

	dashboard.call("_set_page_context", "bulk", "Cadastro em massa", "Teste do grupo")
	await process_frame
	var parent_label := _label_with_text(toggle, "Equipamentos")
	var bulk_button := _button_with_label(sidebar, "Cadastro em massa")
	var bulk_label := _label_with_text(bulk_button, "Cadastro em massa") if bulk_button != null else null
	_check(parent_label != null and parent_label.get_theme_color("font_color").is_equal_approx(Color.WHITE), "Grupo nao ficou ativo com filho selecionado.")
	_check(bulk_label != null and bulk_label.get_theme_color("font_color").is_equal_approx(Color.WHITE), "Filho selecionado nao ficou ativo.")

	_finish()


func _button_with_label(node: Node, wanted: String) -> Button:
	if node is Button:
		var label := _label_with_text(node, wanted)
		if label != null:
			return node as Button
	for child in node.get_children():
		var result := _button_with_label(child, wanted)
		if result != null:
			return result
	return null


func _label_with_text(node: Node, wanted: String) -> Label:
	if node is Label and (node as Label).text == wanted:
		return node as Label
	for child in node.get_children():
		var result := _label_with_text(child, wanted)
		if result != null:
			return result
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("SIDEBAR_EQUIPMENT_GROUP_CHECK_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
