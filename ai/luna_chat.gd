class_name LunaChat
extends Control

signal action_requested(action_id: String, payload: Dictionary)

const MAX_VISIBLE_MESSAGES := 40
const COLOR_NAVY := Color("#0c294a")
const COLOR_BLUE := Color("#0879bd")
const COLOR_BLUE_LIGHT := Color("#e8f4fc")
const COLOR_BORDER := Color("#d7e4ee")
const COLOR_TEXT := Color("#162231")
const COLOR_MUTED := Color("#64748b")
const COLOR_GREEN := Color("#0aa66f")
const COLOR_RED := Color("#dc4545")

var _manager: Node
var _message_list: VBoxContainer
var _scroll: ScrollContainer
var _input: LineEdit
var _send_button: Button
var _stop_button: Button
var _clear_button: Button
var _auto_mode_button: Button
var _gemini_mode_button: Button
var _route_button_group := ButtonGroup.new()
var _mode_label: Label
var _processing_row: HBoxContainer
var _processing_label: Label
var _processing_timer: Timer
var _processing_step := 0
var _busy := false
var _current_page := ""
var _route_mode := "auto"


func _ready() -> void:
	_manager = get_node_or_null("/root/AIManager")
	_build_interface()
	_connect_manager()
	_seed_conversation()
	_refresh_mode()


func set_page_context(page_name: String) -> void:
	_current_page = page_name


func ask_initial(question: String) -> void:
	if not is_node_ready():
		await ready
	_input.text = question
	_submit_message()


func _exit_tree() -> void:
	if _busy and _manager != null and is_instance_valid(_manager):
		_manager.call("cancel_online_request")


func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(760, 420)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _style(Color.WHITE, COLOR_BORDER, 1, 8))
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	root.add_child(_build_header())
	root.add_child(_build_suggestions())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 230)
	root.add_child(_scroll)

	_message_list = VBoxContainer.new()
	_message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_list.add_theme_constant_override("separation", 9)
	_scroll.add_child(_message_list)

	_processing_row = HBoxContainer.new()
	_processing_row.visible = false
	_processing_row.add_theme_constant_override("separation", 8)
	root.add_child(_processing_row)
	var pulse := Label.new()
	pulse.text = "●"
	pulse.add_theme_color_override("font_color", COLOR_BLUE)
	_processing_row.add_child(pulse)
	_processing_label = Label.new()
	_processing_label.text = "Luna analisando"
	_processing_label.add_theme_color_override("font_color", COLOR_MUTED)
	_processing_label.add_theme_font_size_override("font_size", 13)
	_processing_row.add_child(_processing_label)

	var composer := HBoxContainer.new()
	composer.add_theme_constant_override("separation", 8)
	root.add_child(composer)
	_input = LineEdit.new()
	_input.placeholder_text = "Pergunte sobre o sistema, estoque ou esta tela"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(0, 46)
	_input.add_theme_stylebox_override("normal", _style(Color("#f8fbfd"), COLOR_BORDER, 1, 7))
	_input.add_theme_stylebox_override("focus", _style(Color.WHITE, COLOR_BLUE, 2, 7))
	_input.add_theme_color_override("font_color", COLOR_TEXT)
	_input.add_theme_font_size_override("font_size", 15)
	_input.text_submitted.connect(func(_value: String) -> void: _submit_message())
	composer.add_child(_input)

	_send_button = _button("Enviar", COLOR_BLUE, Color.WHITE, Vector2(112, 46))
	_send_button.pressed.connect(_submit_message)
	composer.add_child(_send_button)
	_stop_button = _button("Interromper", COLOR_RED, Color.WHITE, Vector2(118, 46))
	_stop_button.visible = false
	_stop_button.pressed.connect(_cancel_request)
	composer.add_child(_stop_button)

	_processing_timer = Timer.new()
	_processing_timer.wait_time = 0.4
	_processing_timer.timeout.connect(_animate_processing)
	add_child(_processing_timer)


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var emblem := Label.new()
	emblem.text = "L"
	emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emblem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emblem.custom_minimum_size = Vector2(42, 42)
	emblem.add_theme_font_size_override("font_size", 22)
	emblem.add_theme_color_override("font_color", Color.WHITE)
	emblem.add_theme_stylebox_override("normal", _style(COLOR_NAVY, COLOR_NAVY, 1, 8))
	row.add_child(emblem)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 1)
	row.add_child(stack)
	var title := Label.new()
	title.text = "Assistente Luna"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	stack.add_child(title)
	_mode_label = Label.new()
	_mode_label.text = "Luna Local"
	_mode_label.add_theme_font_size_override("font_size", 12)
	_mode_label.add_theme_color_override("font_color", COLOR_GREEN)
	stack.add_child(_mode_label)

	row.add_child(_build_route_selector())

	_clear_button = _button("Limpar", Color("#e7eff6"), COLOR_NAVY, Vector2(86, 40))
	_clear_button.tooltip_text = "Limpar a conversa desta tela"
	_clear_button.pressed.connect(_clear_conversation)
	row.add_child(_clear_button)
	return row


func _build_route_selector() -> Control:
	var selector := HBoxContainer.new()
	selector.add_theme_constant_override("separation", 2)

	_auto_mode_button = _button("Automatico", COLOR_BLUE_LIGHT, COLOR_NAVY, Vector2(104, 40))
	_auto_mode_button.toggle_mode = true
	_auto_mode_button.button_group = _route_button_group
	_auto_mode_button.button_pressed = true
	_auto_mode_button.tooltip_text = "Prioriza respostas locais e usa o Gemini quando a pergunta exige analise."
	_auto_mode_button.add_theme_stylebox_override("pressed", _style(COLOR_NAVY, COLOR_NAVY, 1, 7))
	_auto_mode_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	_auto_mode_button.pressed.connect(_select_route_mode.bind("auto"))
	selector.add_child(_auto_mode_button)

	_gemini_mode_button = _button("Gemini", COLOR_BLUE_LIGHT, COLOR_NAVY, Vector2(82, 40))
	_gemini_mode_button.toggle_mode = true
	_gemini_mode_button.button_group = _route_button_group
	_gemini_mode_button.tooltip_text = "Envia a proxima pergunta ao Gemini quando a conexao e a chave estiverem disponiveis."
	_gemini_mode_button.add_theme_stylebox_override("pressed", _style(COLOR_BLUE, COLOR_BLUE, 1, 7))
	_gemini_mode_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	_gemini_mode_button.pressed.connect(_select_route_mode.bind("gemini"))
	selector.add_child(_gemini_mode_button)
	return selector


func _build_suggestions() -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 7)
	flow.add_theme_constant_override("v_separation", 7)
	for suggestion in [
		"Resumo do estoque",
		"Verificar inconsistencias",
		"Equipamentos em manutencao",
		"Status da sincronizacao",
		"Como usar esta tela?",
	]:
		var button := _button(suggestion, COLOR_BLUE_LIGHT, COLOR_NAVY, Vector2(0, 34))
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_use_suggestion.bind(suggestion))
		flow.add_child(button)
	return flow


func _seed_conversation() -> void:
	if _manager == null:
		_add_message("luna", "A Luna nao esta disponivel nesta execucao.")
		return
	var history: Variant = _manager.call("get_history")
	if typeof(history) == TYPE_ARRAY and not (history as Array).is_empty():
		for item in history as Array:
			if typeof(item) == TYPE_DICTIONARY:
				var message := item as Dictionary
				_add_message(str(message.get("role", "assistant")), str(message.get("text", "")), [], false)
	else:
		_add_message(
			"luna",
			"Ola. Posso consultar o GRUPO RS CENTRAL localmente e usar o Gemini apenas quando voce autorizar e a pergunta exigir uma analise avancada."
		)


func _submit_message() -> void:
	if _busy:
		return
	var question := _input.text.strip_edges()
	if question == "":
		_show_inline_error("Digite uma pergunta antes de enviar.")
		return
	_input.clear()
	_add_message("user", question)
	_set_busy(true)
	if _manager == null or not is_instance_valid(_manager):
		_add_message("luna", "A Luna nao esta disponivel nesta execucao.")
		_set_busy(false)
		return
	var options := {"current_page": _current_page}
	if _route_mode == "gemini":
		options["force_online"] = true
	var result: Variant = await _manager.call("ask", question, options)
	if not is_inside_tree():
		return
	if typeof(result) != TYPE_DICTIONARY:
		_add_message("luna", "Nao foi possivel interpretar a resposta da assistente.")
	else:
		var response := result as Dictionary
		_add_message(
			"luna",
			str(response.get("text", response.get("message", "Resposta indisponivel."))),
			response.get("actions", []),
			true,
			str(response.get("mode", "local"))
		)
	_set_busy(false)
	_refresh_mode()


func _add_message(
	role: String,
	text: String,
	actions: Variant = [],
	scroll_to_end: bool = true,
	source_mode: String = ""
) -> void:
	if _message_list == null:
		return
	var is_user := role in ["user", "usuario"]
	var alignment := HBoxContainer.new()
	alignment.alignment = BoxContainer.ALIGNMENT_END if is_user else BoxContainer.ALIGNMENT_BEGIN
	_message_list.add_child(alignment)

	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_END if is_user else Control.SIZE_SHRINK_BEGIN
	bubble.custom_minimum_size = Vector2(240, 0)
	bubble.add_theme_stylebox_override(
		"panel",
		_style(COLOR_NAVY if is_user else Color("#f3f8fc"), COLOR_NAVY if is_user else COLOR_BORDER, 1, 8)
	)
	alignment.add_child(bubble)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 13)
	margin.add_theme_constant_override("margin_right", 13)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	bubble.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

	if not is_user and source_mode != "":
		var source := Label.new()
		source.text = "GEMINI" if source_mode == "online" else "LOCAL"
		source.add_theme_font_size_override("font_size", 10)
		source.add_theme_color_override("font_color", COLOR_BLUE if source_mode == "online" else COLOR_GREEN)
		content.add_child(source)

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(330, 0)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE if is_user else COLOR_TEXT)
	content.add_child(label)
	var safe_actions := _safe_actions(actions)
	if not safe_actions.is_empty():
		var action_row := HFlowContainer.new()
		action_row.add_theme_constant_override("h_separation", 7)
		content.add_child(action_row)
		for action in safe_actions:
			var action_button := _button(str(action.get("label", "Abrir")), COLOR_BLUE, Color.WHITE, Vector2(0, 34))
			action_button.add_theme_font_size_override("font_size", 12)
			action_button.pressed.connect(_emit_action.bind(str(action.get("id", "")), action))
			action_row.add_child(action_button)

	while _message_list.get_child_count() > MAX_VISIBLE_MESSAGES:
		_message_list.get_child(0).queue_free()
	if scroll_to_end:
		call_deferred("_scroll_to_end")


func _safe_actions(actions: Variant) -> Array[Dictionary]:
	if _manager == null or not is_instance_valid(_manager):
		return []
	var filtered: Variant = _manager.call("safe_actions", actions)
	if typeof(filtered) == TYPE_ARRAY:
		var result: Array[Dictionary] = []
		for item in filtered as Array:
			if typeof(item) == TYPE_DICTIONARY:
				result.append((item as Dictionary).duplicate(true))
		return result
	return []


func _emit_action(action_id: String, payload: Dictionary) -> void:
	action_requested.emit(action_id, payload.duplicate(true))


func _use_suggestion(text: String) -> void:
	_input.text = text
	_submit_message()


func _select_route_mode(mode: String) -> void:
	_route_mode = mode
	_refresh_mode()


func _clear_conversation() -> void:
	if _busy:
		return
	for child in _message_list.get_children():
		child.queue_free()
	if _manager != null and is_instance_valid(_manager):
		_manager.call("clear_history")
	_seed_conversation()


func _cancel_request() -> void:
	if _manager != null and is_instance_valid(_manager):
		_manager.call("cancel_online_request")
	_add_message("luna", "A solicitacao online foi interrompida. O modo local continua disponivel.")
	_set_busy(false)


func _set_busy(value: bool) -> void:
	_busy = value
	_input.editable = not value
	_send_button.disabled = value
	_clear_button.disabled = value
	_auto_mode_button.disabled = value
	_gemini_mode_button.disabled = value
	_stop_button.visible = value
	_processing_row.visible = value
	if value:
		_processing_step = 0
		_processing_timer.start()
	else:
		_processing_timer.stop()


func _animate_processing() -> void:
	_processing_step = (_processing_step + 1) % 4
	_processing_label.text = "Luna analisando%s" % ["", ".", "..", "..."][_processing_step]


func _connect_manager() -> void:
	if _manager == null or not is_instance_valid(_manager):
		return
	var callback := Callable(self, "_on_mode_changed")
	if _manager.has_signal("mode_changed") and not _manager.is_connected("mode_changed", callback):
		_manager.connect("mode_changed", callback)


func _on_mode_changed(_mode: String, _message: String) -> void:
	_refresh_mode()


func _refresh_mode() -> void:
	if _mode_label == null:
		return
	if _manager == null or not is_instance_valid(_manager):
		_mode_label.text = "Indisponivel"
		_mode_label.add_theme_color_override("font_color", COLOR_RED)
		return
	var status: Variant = _manager.call("get_mode_status")
	if typeof(status) != TYPE_DICTIONARY:
		return
	var state := status as Dictionary
	var status_mode := str(state.get("mode", "local"))
	if not _busy and _route_mode == "gemini":
		if bool(state.get("online_enabled", false)) and bool(state.get("key_configured", false)):
			_mode_label.text = "Gemini ativado para esta conversa"
			status_mode = "online"
		else:
			_mode_label.text = "Gemini indisponivel - resposta local"
			status_mode = "configuration_required"
	else:
		_mode_label.text = str(state.get("message", "Luna Local"))
	_mode_label.add_theme_color_override(
		"font_color",
		COLOR_BLUE if status_mode in ["online", "hybrid"] else (COLOR_RED if status_mode == "configuration_required" else COLOR_GREEN)
	)


func _show_inline_error(message: String) -> void:
	_add_message("luna", message)


func _scroll_to_end() -> void:
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _button(text_value: String, background: Color, foreground: Color, minimum: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = minimum
	button.add_theme_stylebox_override("normal", _style(background, background, 1, 7))
	button.add_theme_stylebox_override("hover", _style(background.lightened(0.05), background, 1, 7))
	button.add_theme_stylebox_override("pressed", _style(background.darkened(0.06), background.darkened(0.06), 1, 7))
	button.add_theme_stylebox_override("focus", _style(background, COLOR_BLUE, 2, 7))
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
