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
var _gemini_enabled: CheckBox
var _online_analysis: CheckBox
var _history_enabled: CheckBox
var _inventory_context: CheckBox
var _maintenance_context: CheckBox
var _monitor_enabled: CheckBox
var _api_key: LineEdit
var _model: LineEdit
var _daily_limit: SpinBox
var _status: Label
var _test_button: Button
var _key_configured := false
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
	description.text = "Configure o modo local, a conexao oficial do Gemini e os contextos autorizados."
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

	var credentials := _card()
	root.add_child(credentials)
	var credentials_stack := _card_stack(credentials)
	credentials_stack.add_child(_section_title("Gemini API"))
	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 8)
	credentials_stack.add_child(key_row)
	_api_key = _line_edit("Chave local do Gemini")
	_api_key.secret = true
	key_row.add_child(_api_key)
	var clear_key := _button("Limpar chave", Color("#e8eef4"), COLOR_NAVY, Vector2(120, 42))
	clear_key.pressed.connect(_clear_key)
	key_row.add_child(clear_key)
	var model_row := HBoxContainer.new()
	model_row.add_theme_constant_override("separation", 8)
	credentials_stack.add_child(model_row)
	_model = _line_edit("Modelo oficial")
	model_row.add_child(_model)
	_daily_limit = SpinBox.new()
	_daily_limit.min_value = 1
	_daily_limit.max_value = 100
	_daily_limit.step = 1
	_daily_limit.custom_minimum_size = Vector2(150, 42)
	_daily_limit.tooltip_text = "Limite local diario de chamadas online"
	var daily_limit_line := _daily_limit.get_line_edit()
	daily_limit_line.add_theme_stylebox_override("normal", _style(Color.WHITE, COLOR_BORDER, 1, 6))
	daily_limit_line.add_theme_stylebox_override("focus", _style(Color.WHITE, COLOR_BLUE, 2, 6))
	daily_limit_line.add_theme_color_override("font_color", COLOR_TEXT)
	daily_limit_line.add_theme_color_override("font_selected_color", Color.WHITE)
	model_row.add_child(_daily_limit)

	var note := Label.new()
	note.text = "A chave fica no cofre criptografado deste computador e nunca e gravada no arquivo comum de configuracoes."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", COLOR_MUTED)
	credentials_stack.add_child(note)
	var activation_note := Label.new()
	activation_note.text = "Ao salvar uma chave nova, o Gemini e a analise online serao ativados automaticamente."
	activation_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	activation_note.add_theme_font_size_override("font_size", 12)
	activation_note.add_theme_color_override("font_color", COLOR_BLUE)
	credentials_stack.add_child(activation_note)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	var save := _button("Salvar alteracoes", COLOR_BLUE, Color.WHITE, Vector2(165, 44))
	save.pressed.connect(_save)
	actions.add_child(save)
	_test_button = _button("Testar conexao", Color("#e8f4fc"), COLOR_NAVY, Vector2(150, 44))
	_test_button.pressed.connect(_test_connection)
	actions.add_child(_test_button)
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
	_gemini_enabled = _check("Ativar Gemini")
	_online_analysis = _check("Permitir analise online")
	_history_enabled = _check("Salvar historico local")
	_monitor_enabled = _check("Ativar monitor local")
	for control in [_local_enabled, _gemini_enabled, _online_analysis, _history_enabled, _monitor_enabled]:
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
	note.text = "Identificadores, credenciais e dados pessoais sao removidos antes de qualquer chamada online."
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
	_gemini_enabled.button_pressed = bool(values.get("gemini_enabled", false))
	_online_analysis.button_pressed = bool(values.get("allow_online_analysis", false))
	_history_enabled.button_pressed = bool(values.get("save_history_local", false))
	_inventory_context.button_pressed = bool(values.get("context_inventory", true))
	_maintenance_context.button_pressed = bool(values.get("context_maintenance", true))
	_monitor_enabled.button_pressed = bool(values.get("monitor_enabled", true))
	_model.text = str(values.get("model", "gemini-2.5-flash-lite"))
	_daily_limit.value = float(values.get("daily_request_limit", 20))
	_key_configured = bool(values.get("api_key_configured", false))
	_api_key.placeholder_text = "Chave ja configurada" if _key_configured else "Cole a chave do Google AI Studio"
	if reveal_credentials and _vault_unlocked():
		var vault := _secret_vault()
		if vault != null:
			_api_key.text = str(vault.call("get_secret", "luna", "gemini_api_key", ""))
			_api_key.secret = false
	if _key_configured:
		_set_status(
			"Chave configurada no cofre criptografado."
			if reveal_credentials else
			"Chave configurada no cofre criptografado. O valor permanece oculto.",
			COLOR_GREEN
		)
	else:
		_set_status("O modo local funciona sem chave. Configure o Gemini apenas se desejar analise online.", COLOR_MUTED)


func _save() -> bool:
	if not _vault_unlocked():
		_set_status("O cofre foi bloqueado. Desbloqueie novamente em Configuracoes.", COLOR_RED)
		return false
	if _manager == null or not is_instance_valid(_manager):
		return false
	var typed_key := _api_key.text.strip_edges()
	if typed_key != "" and typed_key.length() < AISettings.MIN_API_KEY_LENGTH:
		_set_status("A chave informada parece incompleta. Cole a chave inteira gerada no Google AI Studio.", COLOR_RED)
		return false
	if typed_key != "":
		_gemini_enabled.button_pressed = true
		_online_analysis.button_pressed = true
	if typed_key == "" and not _key_configured \
			and (_gemini_enabled.button_pressed or _online_analysis.button_pressed):
		_set_status("Cole primeiro uma chave valida do Google AI Studio.", COLOR_RED)
		return false
	var changes := {
		"local_ai_enabled": _local_enabled.button_pressed,
		"gemini_enabled": _gemini_enabled.button_pressed,
		"allow_online_analysis": _online_analysis.button_pressed,
		"save_history_local": _history_enabled.button_pressed,
		"context_inventory": _inventory_context.button_pressed,
		"context_maintenance": _maintenance_context.button_pressed,
		"monitor_enabled": _monitor_enabled.button_pressed,
		"model": _model.text.strip_edges(),
		"daily_request_limit": int(_daily_limit.value),
	}
	if typed_key != "":
		changes["gemini_api_key"] = typed_key
	var saved := bool(_manager.call("save_settings", changes))
	if saved:
		_key_configured = _key_configured or typed_key != ""
		_api_key.clear()
		_api_key.placeholder_text = "Chave ja configurada" if _key_configured else "Cole a chave do Google AI Studio"
		_set_status(
			"Configuracoes salvas. Gemini online ativado; use Testar conexao para validar a chave."
			if _key_configured and _gemini_enabled.button_pressed and _online_analysis.button_pressed
			else "Configuracoes da Luna salvas neste computador.",
			COLOR_GREEN
		)
	else:
		_set_status("Nao foi possivel salvar as configuracoes da Luna.", COLOR_RED)
	return saved


func _test_connection() -> void:
	if not _save():
		return
	_test_button.disabled = true
	_set_status("Testando a conexao oficial do Gemini...", COLOR_BLUE)
	var result: Variant = await _manager.call("test_connection")
	_test_button.disabled = false
	if typeof(result) != TYPE_DICTIONARY:
		_set_status("Resposta de teste invalida.", COLOR_RED)
		return
	var response := result as Dictionary
	if bool(response.get("ok", false)):
		_set_status("Conexao realizada com sucesso. A Luna online esta pronta.", COLOR_GREEN)
	else:
		_set_status(str(response.get("message", "Nao foi possivel conectar ao Gemini.")), COLOR_RED)


func _clear_key() -> void:
	if not _vault_unlocked():
		_set_status("O cofre foi bloqueado. Desbloqueie novamente em Configuracoes.", COLOR_RED)
		return
	if _manager != null and is_instance_valid(_manager) and bool(_manager.call("clear_api_key")):
		_manager.call("save_settings", {
			"gemini_enabled": false,
			"allow_online_analysis": false,
		})
		_key_configured = false
		_gemini_enabled.button_pressed = false
		_online_analysis.button_pressed = false
		_api_key.clear()
		_api_key.placeholder_text = "Cole a chave do Google AI Studio"
		_set_status("Chave local removida.", COLOR_GREEN)


func _clear_cache() -> void:
	if _manager != null and is_instance_valid(_manager):
		_manager.call("clear_cache")
		_set_status("Cache temporario da Luna limpo.", COLOR_GREEN)


func _set_status(message: String, color: Color) -> void:
	if _status != null:
		_status.text = message
		_status.add_theme_color_override("font_color", color)


func _vault_unlocked() -> bool:
	var vault := _secret_vault()
	return vault != null and bool(vault.call("is_view_unlocked"))


func _secret_vault() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var vault := tree.root.get_node_or_null("SecretVault")
	if vault != null:
		return vault
	vault = SecretVaultScript.new()
	vault.name = "SecretVault"
	tree.root.add_child(vault)
	return vault


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
