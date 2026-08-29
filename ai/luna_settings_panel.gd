class_name LunaSettingsPanel
extends Control

const SecretVaultScript := preload("res://src/security/secret_vault.gd")

const COLOR_NAVY := Color("#0c294a")
const COLOR_BLUE := Color("#0879bd")
const COLOR_BORDER := Color("#d7e4ee")
const COLOR_TEXT := Color("#162231")
const COLOR_MUTED := Color("#64748b")
const COLOR_GREEN := Color("#0aa66f")
const COLOR_RED := Color("#dc4545")

var _manager: Node
var _local_enabled: CheckBox
var _history_enabled: CheckBox
var _inventory_context: CheckBox
var _maintenance_context: CheckBox
var _monitor_enabled: CheckBox
var _status: Label
var reveal_credentials := false


func _ready() -> void:
	_manager = get_node_or_null("/root/AIManager")
	_build_interface()
	_load_values()


func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(760, 500)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var heading := Label.new()
	heading.text = "Assistente Luna"
	heading.add_theme_font_size_override("font_size", 23)
	heading.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(heading)
	var description := Label.new()
	description.text = "Configure o modo local e os contextos autorizados."
	description.add_theme_font_size_override("font_size", 13)
	description.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(description)

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	columns.add_theme_constant_override("separation", 12)
	root.add_child(columns)
	columns.add_child(_build_modes_card())
	columns.add_child(_build_privacy_card())

	root.add_child(_card_with_message(
		"Modo legado removido",
		"A interface de configuracao agora opera somente com a Luna local. Nao ha mais chave, teste de conexao ou ativacao online nesta versao."
	))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	var save := _button("Salvar alteracoes", COLOR_BLUE, Color.WHITE, Vector2(165, 44))
	save.pressed.connect(_save)
	actions.add_child(save)
	var clear_cache := _button("Limpar cache", Color("#e8eef4"), COLOR_NAVY, Vector2(125, 44))
	clear_cache.pressed.connect(_clear_cache)
	actions.add_child(clear_cache)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(_status)


func _build_modes_card() -> Control:
	var card := _card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 180)
	var stack := _card_stack(card)
	stack.add_child(_section_title("Modos da Luna"))
	_local_enabled = _check("Ativar IA local")
	_history_enabled = _check("Salvar historico local")
	_monitor_enabled = _check("Ativar monitor local")
	for control in [_local_enabled, _history_enabled, _monitor_enabled]:
		stack.add_child(control)
	return card


func _build_privacy_card() -> Control:
	var card := _card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 180)
	var stack := _card_stack(card)
	stack.add_child(_section_title("Contexto autorizado"))
	_inventory_context = _check("Permitir resumo do estoque")
	_maintenance_context = _check("Permitir resumo de manutencao")
	stack.add_child(_inventory_context)
	stack.add_child(_maintenance_context)
	var note := Label.new()
	note.text = "Identificadores, credenciais e dados pessoais sao removidos antes de qualquer processamento externo."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", COLOR_MUTED)
	stack.add_child(note)
	return card


func _load_values() -> void:
	if _manager == null or not is_instance_valid(_manager):
		_set_status("AIManager indisponivel nesta execucao.", COLOR_RED)
		return
	var raw: Variant = _manager.call("settings_snapshot")
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var values := raw as Dictionary
	_local_enabled.button_pressed = bool(values.get("local_ai_enabled", true))
	_history_enabled.button_pressed = bool(values.get("save_history_local", false))
	_inventory_context.button_pressed = bool(values.get("context_inventory", true))
	_maintenance_context.button_pressed = bool(values.get("context_maintenance", true))
	_monitor_enabled.button_pressed = bool(values.get("monitor_enabled", true))
	_set_status("A Luna agora opera somente em modo local.", COLOR_GREEN)


func _save() -> bool:
	if _manager == null or not is_instance_valid(_manager):
		return false
	var changes := {
		"local_ai_enabled": _local_enabled.button_pressed,
		"save_history_local": _history_enabled.button_pressed,
		"context_inventory": _inventory_context.button_pressed,
		"context_maintenance": _maintenance_context.button_pressed,
		"monitor_enabled": _monitor_enabled.button_pressed,
	}
	var saved := bool(_manager.call("save_settings", changes))
	if saved:
		_set_status("Configuracoes da Luna salvas neste computador.", COLOR_GREEN)
	else:
		_set_status("Nao foi possivel salvar as configuracoes da Luna.", COLOR_RED)
	return saved


func _clear_cache() -> void:
	if _manager != null and is_instance_valid(_manager):
		_manager.call("clear_cache")
		_set_status("Cache temporario da Luna limpo.", COLOR_GREEN)


func _set_status(message: String, color: Color) -> void:
	if _status != null:
		_status.text = message
		_status.add_theme_color_override("font_color", color)


func _card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("#f8fbfd"), COLOR_BORDER, 1, 7))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	return panel


func _card_with_message(title: String, text: String) -> Control:
	var card := _card()
	var stack := _card_stack(card)
	if stack == null:
		return card
	stack.add_child(_section_title(title))
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", COLOR_MUTED)
	stack.add_child(label)
	return card


func _card_stack(card: PanelContainer) -> VBoxContainer:
	var margin := card.get_child(0) as MarginContainer
	if margin == null or margin.get_child_count() == 0:
		return null
	return margin.get_child(0) as VBoxContainer


func _section_title(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	return label


func _check(value: String) -> CheckBox:
	var control := CheckBox.new()
	control.text = value
	control.add_theme_font_size_override("font_size", 14)
	control.add_theme_color_override("font_color", COLOR_TEXT)
	control.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	control.add_theme_color_override("font_hover_color", COLOR_TEXT)
	control.add_theme_color_override("font_hover_pressed_color", COLOR_TEXT)
	control.add_theme_color_override("font_focus_color", COLOR_TEXT)
	control.add_theme_color_override("font_disabled_color", COLOR_MUTED)
	return control


func _line_edit(placeholder: String) -> LineEdit:
	var control := LineEdit.new()
	control.placeholder_text = placeholder
	control.custom_minimum_size = Vector2(0, 42)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.add_theme_stylebox_override("normal", _style(Color.WHITE, COLOR_BORDER, 1, 6))
	control.add_theme_stylebox_override("focus", _style(Color.WHITE, COLOR_BLUE, 2, 6))
	control.add_theme_color_override("font_color", COLOR_TEXT)
	return control


func _button(text_value: String, background: Color, foreground: Color, minimum: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = minimum
	button.add_theme_stylebox_override("normal", _style(background, background, 1, 7))
	button.add_theme_stylebox_override("hover", _style(background.lightened(0.05), background, 1, 7))
	button.add_theme_stylebox_override("pressed", _style(background.darkened(0.05), background, 1, 7))
	button.add_theme_color_override("font_color", foreground)
	button.add_theme_color_override("font_hover_color", foreground)
	button.add_theme_font_size_override("font_size", 14)
	return button


func _style(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style
