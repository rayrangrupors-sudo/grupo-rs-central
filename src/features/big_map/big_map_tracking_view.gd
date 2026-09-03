## Interface autocontida do novo Mapa Grande.
##
## Nao conhece API, estoque ou autenticacao. Expoe os controles necessarios ao
## controlador e mantem a composicao visual testavel em uma janela isolada.
class_name BigMapTrackingView
extends VBoxContainer

const MapCanvas := preload("res://src/features/big_map/big_map_canvas.gd")
const UI_FONT := preload("res://assets/fonts/Noto_Sans/static/NotoSans-SemiBold.ttf")
const UI_FONT_REGULAR := preload("res://assets/fonts/Noto_Sans/static/NotoSans_SemiCondensed-Regular.ttf")

const BLUE := Color("#0879bd")
const BLUE_DARK := Color("#102f4a")
const GREEN := Color("#11a86d")
const RED := Color("#dc3f4b")
const YELLOW := Color("#e89a18")
const MUTED := Color("#64758a")
const TEXT := Color("#182636")
const BORDER := Color("#d6e2ec")
const SURFACE := Color("#ffffff")
const CANVAS_SURFACE := Color("#edf4f8")

var query_input: LineEdit
var query_state_label: Label
var add_button: Button
var monitor_select: OptionButton
var camera_lock_check: CheckButton
var erb_layer_check: Button
var refresh_button: Button
var queue_count_label: Label
var queue_body: HBoxContainer
var clear_queue_button: Button
var status_label: Label
var runtime_meta_label: Label
var updated_label: Label
var runtime_indicator: ColorRect
var basemap_select: OptionButton
var erb_operator_select: OptionButton
var erb_generation_select: OptionButton
var erb_city_select: OptionButton
var erb_status_select: OptionButton
var erb_source_label: Label
var erb_caveat_label: Label
var metric_labels: Dictionary = {}
var map_canvas: Control
var list_toggle: Button
var details_panel: PanelContainer
var details_body: VBoxContainer
var details_title: Label
var list_panel: PanelContainer
var list_body: VBoxContainer
var workspace_split: HSplitContainer
var _popup_clear_icon: ImageTexture
var maintenance_button: Button
var maintenance_progress: ProgressBar
var maintenance_status: Label
var maintenance_cards: HBoxContainer
var maintenance_values: Dictionary = {}
var advanced_button: Button
var _queue_row: HBoxContainer
var _action_row: HBoxContainer


func _init() -> void:
	name = "BigMapTrackingView"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 7)
	_build_toolbar()
	_build_runtime_strip()
	_build_erb_filters()
	_build_metrics()
	_build_maintenance_progress()
	_build_map_workspace()
	_build_vehicle_list()
	_set_advanced(false)
	resized.connect(_apply_responsive_layout)


func set_metrics(values: Dictionary) -> void:
	for key in metric_labels.keys():
		var value_label: Variant = metric_labels.get(key)
		if value_label is Label and is_instance_valid(value_label):
			(value_label as Label).text = str(values.get(key, 0))
	if list_toggle != null:
		list_toggle.text = "Veículos  %s" % str(values.get("Total", 0))


func set_runtime(message: String, color: Color, metadata: String, updated: String) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", color)
	if runtime_indicator != null:
		runtime_indicator.color = color
	runtime_meta_label.text = metadata
	updated_label.text = updated


func set_erb_source(source_text: String, caveat_text: String, state_color: Color = MUTED) -> void:
	erb_source_label.text = source_text
	erb_source_label.add_theme_color_override("font_color", state_color)
	erb_caveat_label.text = caveat_text


func set_erb_filter_values(operators: Array[String], generations: Array[String], cities: Array[String], statuses: Array[String]) -> void:
	_set_filter_items(erb_operator_select, "Todas as prestadoras", operators)
	_set_filter_items(erb_generation_select, "Todas as tecnologias", generations)
	_set_filter_items(erb_city_select, "Todos os municípios", cities)
	_set_filter_items(erb_status_select, "Todas as situações", statuses)


func selected_erb_filters() -> Dictionary:
	return {
		"operator": _selected_filter_value(erb_operator_select),
		"generation": _selected_filter_value(erb_generation_select),
		"city": _selected_filter_value(erb_city_select),
		"status": _selected_filter_value(erb_status_select),
	}


func set_details_title(value: String) -> void:
	if details_title != null:
		details_title.show()
		details_title.text = value


func set_list_expanded(expanded: bool) -> void:
	list_panel.visible = expanded
	list_toggle.text = ("Ocultar veículos  %s" if expanded else "Veículos  %s") % _current_total()


func set_query_state(state: String, detail: String = "") -> void:
	if query_state_label == null:
		return
	var normalized := state.strip_edges().to_lower()
	var message := detail.strip_edges()
	var color := MUTED
	match normalized:
		"loading", "carregando", "searching", "buscando":
			message = message if message != "" else "Buscando localização..."
			color = BLUE
		"found", "encontrado", "ok":
			message = message if message != "" else "Localização encontrada"
			color = GREEN
		"not_found", "nao_encontrado", "não_encontrado", "empty":
			message = message if message != "" else "Nenhuma localização encontrada"
			color = YELLOW
		"error", "erro":
			message = message if message != "" else "Erro ao buscar localização"
			color = RED
		_:
			message = message if message != "" else "Aguardando pesquisa"
	query_state_label.text = message
	query_state_label.add_theme_color_override("font_color", color)


func _current_total() -> String:
	var label: Variant = metric_labels.get("Total", null)
	return (label as Label).text if label is Label else "0"


func _build_toolbar() -> void:
	var panel := PanelContainer.new()
	panel.name = "TrackingToolbar"
	panel.add_theme_stylebox_override("panel", _panel_style(SURFACE, Color("#cddde8"), 12))
	add_child(panel)
	var margin := _margin(10, 10, 8, 8)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	stack.add_child(row)
	query_input = LineEdit.new()
	query_input.name = "TrackingQuery"
	query_input.placeholder_text = "Pesquisar por placa, número de série ou cliente"
	query_input.tooltip_text = "Pesquise por placa, número de série ou cliente cadastrado."
	query_input.clear_button_enabled = true
	query_input.custom_minimum_size = Vector2(380, 44)
	query_input.size_flags_horizontal = Control.SIZE_FILL
	_style_input(query_input)
	row.add_child(query_input)
	add_button = _button("ADICIONAR", BLUE, Color.WHITE, 120)
	row.add_child(add_button)
	refresh_button = _button("Atualizar mapa", BLUE, Color.WHITE, 125)
	row.add_child(refresh_button)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(space)
	advanced_button = _button("Filtros", Color("#f3f7fb"), BLUE_DARK, 65)
	advanced_button.toggle_mode = true
	advanced_button.toggled.connect(_set_advanced)
	row.add_child(advanced_button)
	maintenance_button = _button("Pontuar manutenções", YELLOW, Color.WHITE, 190)
	row.add_child(maintenance_button)
	var action_row := HBoxContainer.new()
	_action_row = action_row
	action_row.name = "TrackingActionRow"
	action_row.add_theme_constant_override("separation", 8)
	stack.add_child(action_row)
	monitor_select = OptionButton.new()
	monitor_select.name = "TrackingFilter"
	monitor_select.custom_minimum_size = Vector2(176, 38)
	for item in ["Todos", "Última ignição ligada", "Última ignição desligada", "Desatualizados", "Sem posição"]:
		monitor_select.add_item(item)
	_style_option(monitor_select)
	action_row.add_child(monitor_select)
	query_state_label = _label("Aguardando pesquisa", 10, MUTED)
	query_state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	query_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	query_state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	query_state_label.clip_text = true
	action_row.add_child(query_state_label)

	var queue_row := HBoxContainer.new()
	_queue_row = queue_row
	queue_row.custom_minimum_size = Vector2(0, 27)
	queue_row.add_theme_constant_override("separation", 7)
	stack.add_child(queue_row)
	queue_count_label = _label("Fila: 0 aparelhos", 11, BLUE_DARK)
	queue_count_label.custom_minimum_size = Vector2(135, 0)
	queue_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	queue_row.add_child(queue_count_label)
	var queue_scroll := ScrollContainer.new()
	queue_scroll.name = "TrackingQueueScroll"
	queue_scroll.custom_minimum_size = Vector2(0, 27)
	queue_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	queue_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	queue_row.add_child(queue_scroll)
	queue_body = HBoxContainer.new()
	queue_body.name = "TrackingQueue"
	queue_body.add_theme_constant_override("separation", 6)
	queue_scroll.add_child(queue_body)
	camera_lock_check = CheckButton.new()
	camera_lock_check.name = "TrackingCameraLock"
	camera_lock_check.text = "Travar câmera"
	camera_lock_check.custom_minimum_size.x = 102
	camera_lock_check.tooltip_text = "Mantém todos os veículos do filtro enquadrados"
	_style_check(camera_lock_check)
	queue_row.add_child(camera_lock_check)
	erb_layer_check = _button("ERBs visíveis", Color("#e8f4fb"), BLUE_DARK, 100)
	erb_layer_check.name = "TrackingErbLayer"
	erb_layer_check.toggle_mode = true
	erb_layer_check.button_pressed = true
	erb_layer_check.custom_minimum_size.y = 30
	queue_row.add_child(erb_layer_check)
	clear_queue_button = _button("Limpar fila", Color("#e9f0f6"), BLUE_DARK, 98)
	clear_queue_button.custom_minimum_size.y = 30
	queue_row.add_child(clear_queue_button)


func _build_runtime_strip() -> void:
	var panel := PanelContainer.new()
	panel.name = "TrackingRuntime"
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#f3f9fc"), Color("#cfe2ef"), 10))
	add_child(panel)
	var margin := _margin(9, 9, 4, 4)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	runtime_indicator = ColorRect.new()
	runtime_indicator.name = "TrackingRuntimeIndicator"
	runtime_indicator.custom_minimum_size = Vector2(4, 18)
	runtime_indicator.color = GREEN
	runtime_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(runtime_indicator)
	status_label = _label("Informe uma placa, série ou cliente para iniciar", 11, MUTED)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(status_label)
	runtime_meta_label = _label("OpenStreetMap · ERBs Anatel · API oficial", 10, MUTED)
	runtime_meta_label.custom_minimum_size.x = 175
	runtime_meta_label.clip_text = true
	row.add_child(runtime_meta_label)
	updated_label = _label("Aguardando a primeira consulta", 10, MUTED)
	updated_label.custom_minimum_size.x = 165
	updated_label.clip_text = true
	row.add_child(updated_label)


func _build_erb_filters() -> void:
	var panel := PanelContainer.new()
	panel.name = "TrackingErbFilters"
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#fbfdff"), BORDER, 10))
	add_child(panel)
	var margin := _margin(10, 10, 6, 6)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	var row := HBoxContainer.new()
	row.name = "ErbFilterRow"
	row.add_theme_constant_override("separation", 6)
	stack.add_child(row)
	var title := _label("ERBs licenciadas", 11, BLUE_DARK)
	title.custom_minimum_size.x = 112
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	erb_operator_select = _filter_select("ErbOperatorFilter", 120)
	erb_generation_select = _filter_select("ErbGenerationFilter", 120)
	erb_city_select = _filter_select("ErbCityFilter", 176)
	erb_status_select = _filter_select("ErbStatusFilter", 128)
	row.add_child(erb_operator_select)
	row.add_child(erb_generation_select)
	row.add_child(erb_city_select)
	row.add_child(erb_status_select)
	var meta_row := HBoxContainer.new()
	meta_row.name = "ErbMetaRow"
	meta_row.add_theme_constant_override("separation", 6)
	stack.add_child(meta_row)
	basemap_select = _filter_select("BasemapFilter", 190)
	basemap_select.add_item("OpenStreetMap")
	basemap_select.set_item_metadata(0, "normal")
	basemap_select.select(0)
	basemap_select.disabled = true
	basemap_select.set_item_text(0, "Mapa-base · OpenStreetMap")
	basemap_select.tooltip_text = "Mapa-base oficial desta tela: OpenStreetMap"
	meta_row.add_child(basemap_select)
	erb_source_label = _label("Fonte Anatel: carregando catálogo auditável...", 9, MUTED)
	erb_source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	erb_source_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	erb_source_label.clip_text = true
	meta_row.add_child(erb_source_label)
	erb_caveat_label = _label("Licenciamento/presença de ERB não representa intensidade de sinal em tempo real.", 9, MUTED)
	erb_caveat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	erb_caveat_label.custom_minimum_size = Vector2(250, 28)
	erb_caveat_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	meta_row.add_child(erb_caveat_label)


func _build_metrics() -> void:
	var row := HBoxContainer.new()
	row.name = "TrackingMetrics"
	row.add_theme_constant_override("separation", 7)
	add_child(row)
	for metric in [
		["Total", BLUE],
		["Com posição", Color("#2f85c4")],
		["Em movimento", GREEN],
		["Parados", RED],
		["Desatualizados", YELLOW],
		["Sem posição", MUTED],
	]:
		row.add_child(_metric_card(str(metric[0]), metric[1]))


func _build_maintenance_progress() -> void:
	maintenance_status = _label("", 12, MUTED)
	add_child(maintenance_status)
	maintenance_status.hide()
	maintenance_progress = ProgressBar.new()
	maintenance_progress.custom_minimum_size.y = 6
	maintenance_progress.show_percentage = false
	maintenance_progress.add_theme_stylebox_override("background", _panel_style(Color("#e2ebf2"), Color.TRANSPARENT, 4))
	maintenance_progress.add_theme_stylebox_override("fill", _panel_style(Color("#f59a20"), Color.TRANSPARENT, 4))
	add_child(maintenance_progress)
	maintenance_progress.hide()
	maintenance_cards = HBoxContainer.new()
	maintenance_cards.add_theme_constant_override("separation", 10)
	add_child(maintenance_cards)
	maintenance_cards.hide()
	for definition in [["Processados", BLUE], ["Ignição ligada", GREEN], ["Ignição desligada", RED], ["Aguardando busca", Color("#7554bd")]]:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.y = 104
		card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		maintenance_cards.add_child(card)
		var background := ColorRect.new()
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = preload("res://src/features/big_map/maintenance_card.gdshader")
		material.set_shader_parameter("accent", definition[1])
		background.material = material
		card.add_child(background)
		background.resized.connect(func(): material.set_shader_parameter("dimensions", background.size))
		var margin := _margin(16, 16, 10, 10)
		card.add_child(margin)
		var stack := VBoxContainer.new()
		margin.add_child(stack)
		var value := _label("0", 32, Color.WHITE)
		stack.add_child(value)
		stack.add_child(_label(str(definition[0]).to_upper(), 11, Color.WHITE))
		maintenance_values[definition[0]] = value


func set_maintenance_progress(active: bool, running: bool, counts: Dictionary, message: String) -> void:
	maintenance_status.visible = active
	maintenance_progress.visible = active
	maintenance_cards.visible = active
	get_node("TrackingMetrics").visible = not active
	get_node("TrackingRuntime").visible = not active and advanced_button.button_pressed
	maintenance_button.text = "Cancelar busca" if running else "Pontuar manutenções"
	maintenance_status.text = message
	maintenance_progress.max_value = maxi(1, int(counts.get("total", 0)))
	maintenance_progress.value = int(counts.get("processed", 0))
	for key in ["Processados", "Ignição ligada", "Ignição desligada", "Aguardando busca"]:
		maintenance_values[key].text = str(counts.get(key, 0))


func _metric_card(title_text: String, accent: Color) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(122, 48)
	panel.add_theme_stylebox_override("panel", _panel_style(SURFACE, BORDER, 9))
	var margin := _margin(7, 7, 4, 4)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(3, 30)
	bar.color = accent
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	row.add_child(stack)
	stack.add_child(_label(title_text, 10, MUTED))
	var value := _label("0", 17, accent)
	stack.add_child(value)
	metric_labels[title_text] = value
	return panel


func _build_map_workspace() -> void:
	workspace_split = HSplitContainer.new()
	workspace_split.name = "TrackingWorkspace"
	workspace_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_split.custom_minimum_size = Vector2(0, 465)
	# Começa no mínimo visual do mapa; o callback responsivo recalcula a
	# divisão depois que a janela informa sua largura real.
	workspace_split.split_offset = 720
	add_child(workspace_split)

	var map_panel := PanelContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_theme_stylebox_override("panel", _panel_style(CANVAS_SURFACE, BORDER, 11))
	workspace_split.add_child(map_panel)
	var overlay := Control.new()
	overlay.name = "TrackingMapOverlay"
	overlay.custom_minimum_size = Vector2(720, 465)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_panel.add_child(overlay)
	map_canvas = MapCanvas.new()
	map_canvas.name = "TrackingMapCanvas"
	map_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_canvas.set_tracking_mode(true)
	map_canvas.set_station_visibility(true)
	overlay.add_child(map_canvas)
	list_toggle = _button("Veículos  0", BLUE, Color.WHITE, 138)
	list_toggle.name = "TrackingListToggle"
	list_toggle.custom_minimum_size.y = 36
	list_toggle.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	list_toggle.position = Vector2(-150, -47)
	overlay.add_child(list_toggle)
	list_toggle.position = Vector2(-302, -47)
	erb_layer_check.reparent(overlay)
	erb_layer_check.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	erb_layer_check.position = Vector2(-155, -47)
	erb_layer_check.custom_minimum_size = Vector2(145,36)
	erb_layer_check.text = "Ocultar ERBs"
	erb_layer_check.toggled.connect(func(enabled: bool): erb_layer_check.text = "Ocultar ERBs" if enabled else "Mostrar ERBs")

	details_panel = PanelContainer.new()
	details_panel.name = "TrackingDetailsPanel"
	details_panel.custom_minimum_size = Vector2(320, 0)
	details_panel.add_theme_stylebox_override("panel", _panel_style(SURFACE, BORDER, 11))
	workspace_split.add_child(details_panel)
	var detail_margin := _margin(11, 11, 9, 9)
	details_panel.add_child(detail_margin)
	var detail_stack := VBoxContainer.new()
	detail_stack.add_theme_constant_override("separation", 5)
	detail_margin.add_child(detail_stack)
	details_title = _label("Seleção no mapa", 15, TEXT)
	detail_stack.add_child(details_title)
	var divider := HSeparator.new()
	divider.add_theme_color_override("separator_color", BORDER)
	detail_stack.add_child(divider)
	details_body = VBoxContainer.new()
	details_body.name = "TrackingDetailsBody"
	details_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_body.add_theme_constant_override("separation", 3)
	var details_scroll := ScrollContainer.new()
	details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	detail_stack.add_child(details_scroll)
	details_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_scroll.add_child(details_body)
	var empty_title := _label("Selecione um veículo ou ERB licenciada", 12, TEXT)
	empty_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_body.add_child(empty_title)
	var empty_hint := _label("Clique em uma agulha, torre ou linha da lista para ver os detalhes.", 11, MUTED)
	empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_body.add_child(empty_hint)


func _build_vehicle_list() -> void:
	list_panel = PanelContainer.new()
	list_panel.name = "TrackingVehicleList"
	list_panel.custom_minimum_size = Vector2(0, 230)
	list_panel.visible = false
	list_panel.add_theme_stylebox_override("panel", _panel_style(SURFACE, BORDER, 9))
	add_child(list_panel)
	var margin := _margin(12, 12, 9, 9)
	list_panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	var heading := HBoxContainer.new()
	stack.add_child(heading)
	var title := _label("Veículos no recorte", 15, TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(_label("Clique em uma linha para localizar", 10, MUTED))
	var header := PanelContainer.new()
	header.custom_minimum_size = Vector2(0, 30)
	header.add_theme_stylebox_override("panel", _panel_style(Color("#f3f7fa"), BORDER, 5))
	stack.add_child(header)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 7)
	header.add_child(header_row)
	for item in [["Status", 120, false], ["Placa", 115, false], ["Série", 125, false], ["Cliente", 210, true], ["Posição", 120, false], ["Última comunicação", 165, false], ["Velocidade", 95, false]]:
		header_row.add_child(_table_label(str(item[0]), int(item[1]), bool(item[2]), BLUE_DARK, 10))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	stack.add_child(scroll)
	list_body = VBoxContainer.new()
	list_body.name = "TrackingVehicleListBody"
	list_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_body.add_theme_constant_override("separation", 3)
	scroll.add_child(list_body)


func _button(text_value: String, background: Color, foreground: Color, width: int) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(width, 44)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", UI_FONT)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", foreground)
	button.add_theme_color_override("font_hover_color", foreground)
	button.add_theme_stylebox_override("normal", _panel_style(background, background.darkened(0.08), 7))
	button.add_theme_stylebox_override("hover", _panel_style(background.lightened(0.06), background.darkened(0.12), 7))
	button.add_theme_stylebox_override("pressed", _panel_style(background.darkened(0.05), background.darkened(0.15), 7))
	button.add_theme_stylebox_override("focus", _panel_style(background.lightened(0.08), BLUE, 7))
	return button


func _style_input(input: LineEdit) -> void:
	input.add_theme_font_override("font", UI_FONT)
	input.add_theme_font_size_override("font_size", 13)
	input.add_theme_color_override("font_color", TEXT)
	input.add_theme_color_override("font_placeholder_color", MUTED)
	input.add_theme_stylebox_override("normal", _panel_style(SURFACE, BORDER, 7))
	input.add_theme_stylebox_override("focus", _panel_style(SURFACE, BLUE, 7))


func _style_option(option: OptionButton) -> void:
	option.focus_mode = Control.FOCUS_ALL
	option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	option.add_theme_font_override("font", UI_FONT)
	option.add_theme_font_size_override("font_size", 12)
	option.add_theme_color_override("font_color", TEXT)
	option.add_theme_color_override("font_hover_color", TEXT)
	option.add_theme_color_override("font_focus_color", TEXT)
	option.add_theme_color_override("font_pressed_color", TEXT)
	option.add_theme_color_override("font_hover_pressed_color", TEXT)
	option.add_theme_color_override("font_disabled_color", BLUE_DARK)
	option.add_theme_constant_override("h_separation", 6)
	option.add_theme_stylebox_override("normal", _panel_style(Color("#fbfdff"), Color("#c9d9e5"), 8))
	option.add_theme_stylebox_override("hover", _panel_style(Color("#eff8fc"), BLUE, 8))
	option.add_theme_stylebox_override("focus", _panel_style(Color("#eaf6fb"), BLUE, 8))
	option.add_theme_stylebox_override("pressed", _panel_style(Color("#e3f1f8"), BLUE, 8))
	option.add_theme_stylebox_override("disabled", _panel_style(Color("#eaf4f8"), Color("#b9d0df"), 8))
	_style_option_popup(option.get_popup())


func _style_option_popup(popup: PopupMenu) -> void:
	popup.add_theme_font_override("font", UI_FONT_REGULAR)
	popup.add_theme_font_size_override("font_size", 12)
	popup.add_theme_color_override("font_color", TEXT)
	popup.add_theme_color_override("font_hover_color", TEXT)
	popup.add_theme_color_override("font_pressed_color", TEXT)
	popup.add_theme_color_override("font_disabled_color", MUTED)
	popup.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	popup.add_theme_constant_override("item_start_padding", 10)
	popup.add_theme_constant_override("item_end_padding", 10)
	popup.add_theme_constant_override("h_separation", 8)
	popup.add_theme_constant_override("v_separation", 4)
	popup.add_theme_constant_override("icon_max_width", 0)
	popup.add_theme_stylebox_override("panel", _panel_style(SURFACE, Color("#c4d7e4"), 10))
	popup.add_theme_stylebox_override("hovered", _panel_style(Color("#eaf6fb"), Color("#b7d7e8"), 6))
	popup.add_theme_stylebox_override("hover", _panel_style(Color("#eaf6fb"), Color("#b7d7e8"), 6))
	popup.add_theme_stylebox_override("pressed", _panel_style(Color("#dceff8"), BLUE, 6))
	popup.add_theme_stylebox_override("focus", _panel_style(Color("#eaf6fb"), BLUE, 6))
	popup.add_theme_stylebox_override("separator", _panel_style(Color("#f4f8fb"), Color("#d9e5ec"), 0))
	var clear_icon := _popup_clear_icon_texture()
	for icon_name in ["check", "checked", "radio_checked", "radio_unchecked"]:
		popup.add_theme_icon_override(icon_name, clear_icon)


func _popup_clear_icon_texture() -> ImageTexture:
	if _popup_clear_icon != null:
		return _popup_clear_icon
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_popup_clear_icon = ImageTexture.create_from_image(image)
	return _popup_clear_icon


func _filter_select(control_name: String, width: int) -> OptionButton:
	var option := OptionButton.new()
	option.name = control_name
	option.custom_minimum_size = Vector2(width, 36)
	_style_option(option)
	return option


func _set_filter_items(option: OptionButton, all_label: String, values: Array[String]) -> void:
	var previous: String = _selected_filter_value(option)
	option.clear()
	option.add_item(all_label)
	option.set_item_metadata(0, "")
	var sorted_values: Array[String] = values.duplicate()
	sorted_values.sort()
	for value: String in sorted_values:
		var clean: String = value.strip_edges()
		var label: String = clean if clean != "" else "Não informado pela fonte"
		option.add_item(label)
		var metadata_value: String = clean if clean != "" else "__missing__"
		option.set_item_metadata(option.item_count - 1, metadata_value)
		if metadata_value == previous:
			option.select(option.item_count - 1)


func _selected_filter_value(option: OptionButton) -> String:
	if option == null or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected)).strip_edges()


func _apply_responsive_layout() -> void:
	if workspace_split == null or details_panel == null:
		return
	var compact := size.x < 1250.0
	var very_compact := size.x < 1050.0
	var details_width := 250.0 if very_compact else (285.0 if compact else 325.0)
	query_input.custom_minimum_size.x = clampf(size.x * 0.36, 250, 590)
	details_panel.custom_minimum_size.x = details_width
	var available_map_width := maxf(0.0, size.x - details_width - 18.0)
	var desired_split := size.x - details_width - 18.0
	workspace_split.split_offset = roundi(clampf(desired_split, 0.0, maxf(0.0, size.x)))
	var available_workspace_height := maxf(340.0, size.y - 250.0)
	var workspace_height := minf(550.0, available_workspace_height)
	workspace_split.custom_minimum_size.y = workspace_height
	if map_canvas != null:
		map_canvas.custom_minimum_size = Vector2(minf(720.0, available_map_width), workspace_height)


func _set_advanced(expanded: bool) -> void:
	if _action_row == null or not has_node("TrackingErbFilters"):
		return
	_action_row.visible = true
	_queue_row.visible = expanded
	get_node("TrackingErbFilters").visible = expanded
	get_node("TrackingRuntime").visible = expanded and not maintenance_cards.visible


func _style_check(check: CheckButton) -> void:
	check.add_theme_font_override("font", UI_FONT)
	check.add_theme_font_size_override("font_size", 11)
	check.add_theme_color_override("font_color", BLUE_DARK)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _table_label(text_value: String, width: int, expand: bool, color: Color, font_size: int) -> Label:
	var label := _label(text_value, font_size, color)
	label.custom_minimum_size.x = width
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _margin(left: int, right: int, top: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin


func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style
