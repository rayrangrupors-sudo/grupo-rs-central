## Controlador visual da funcionalidade de localização de veículos.
##
## Responsabilidades: montar a tela de localização, coordenar consultas já
## fornecidas pelo dashboard e apresentar status, lista e detalhes.
extends "res://src/inventory_dashboard.gd"

## Camada visual da tela de Localização.
## A lógica de consulta, seleção, API e mapa continua no dashboard base.

const VehicleStatusResolver := preload("res://src/features/big_map/vehicle_status_resolver.gd")

var location_runtime_panel: PanelContainer
var location_runtime_meta_label: Label
var location_runtime_refresh_label: Label
var location_summary_cards: HBoxContainer
var location_last_latency_ms := -1
var location_last_query := ""
var location_last_refresh_at := ""
var location_last_error := ""
var location_last_valid_rows: Array[Dictionary] = []


func _setup_st310_location_poll_timer() -> void:
	# A tela de Localizacao precisa refletir rapidamente a leitura da API. O
	# override tambem protege contra instancias antigas do dashboard que ainda
	# tenham o intervalo padrao de 15 s carregado em cache.
	super._setup_st310_location_poll_timer()
	if st310_location_poll_timer != null and is_instance_valid(st310_location_poll_timer):
		st310_location_poll_timer.wait_time = 1.0


func _show_vehicle_location_monitor() -> void:
	_set_page_context("vehicle_location", "Mapa Grande", "ERBs Anatel e localização de veículos em tempo real")
	_set_content_margins(28, 20, 28, 18)
	_set_content(_build_vehicle_location_view())
	if not vehicle_location_refreshing:
		call_deferred("_refresh_vehicle_location_view")
	call_deferred("_ensure_vehicle_location_map_ready")


func _show_smart_4g_monitor() -> void:
	# O item antigo de Mapa Grande e a antiga tela Localização agora abrem a
	# mesma composição, com camadas de ERBs e veículos no mesmo canvas.
	if not _branch_supports_monitor_4g():
		_show_warning("Mapa Grande", "Este recurso esta disponivel somente para a base de Imperatriz.")
		return
	_show_vehicle_location_monitor()


func _build_vehicle_location_view() -> Control:
	vehicle_location_summary_value_labels.clear()
	vehicle_location_view_root = VBoxContainer.new()
	vehicle_location_view_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vehicle_location_view_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vehicle_location_view_root.add_theme_constant_override("separation", 12)

	var filters := PanelContainer.new()
	filters.add_theme_stylebox_override("panel", _style_box(Color("#ffffff"), Color("#d8e5ef"), 1, 10))
	vehicle_location_view_root.add_child(filters)
	var filter_margin := MarginContainer.new()
	filter_margin.add_theme_constant_override("margin_left", 14)
	filter_margin.add_theme_constant_override("margin_right", 14)
	filter_margin.add_theme_constant_override("margin_top", 12)
	filter_margin.add_theme_constant_override("margin_bottom", 12)
	filters.add_child(filter_margin)
	# MarginContainer organiza apenas um filho. Manter a barra e a fila como
	# filhos diretos fazia o Godot posicionar ambos no mesmo retângulo, o que
	# deixava os textos e botões sobrepostos na abertura da tela.
	var filter_stack := VBoxContainer.new()
	filter_stack.add_theme_constant_override("separation", 8)
	filter_margin.add_child(filter_stack)
	var filter_row := HBoxContainer.new()
	filter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_theme_constant_override("separation", 12)
	filter_stack.add_child(filter_row)

	vehicle_location_plate_input = LineEdit.new()
	vehicle_location_plate_input.placeholder_text = "Placa, equipamento ou cliente"
	vehicle_location_plate_input.custom_minimum_size = Vector2(370, 48)
	vehicle_location_plate_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vehicle_location_plate_input.add_theme_font_override("font", UI_FONT)
	vehicle_location_plate_input.add_theme_font_size_override("font_size", 15)
	vehicle_location_plate_input.add_theme_color_override("font_color", TEXT)
	vehicle_location_plate_input.add_theme_color_override("font_placeholder_color", MUTED)
	vehicle_location_plate_input.add_theme_stylebox_override("normal", _style_box(SURFACE, BORDER, 1, 7))
	vehicle_location_plate_input.add_theme_stylebox_override("focus", _style_box(SURFACE, BLUE, 1, 7))
	vehicle_location_plate_input.text_changed.connect(_on_vehicle_location_query_changed)
	vehicle_location_plate_input.gui_input.connect(_on_vehicle_location_query_input)
	filter_row.add_child(vehicle_location_plate_input)
	vehicle_location_add_button = _make_action_button(
		"Adicionar", GREEN, GREEN, Color.WHITE, Vector2(138, 48), Callable(self, "_add_vehicle_location_query")
	)
	vehicle_location_add_button.tooltip_text = "Adiciona a placa ou série à fila sem remover os aparelhos já selecionados"
	filter_row.add_child(vehicle_location_add_button)

	vehicle_location_monitor_select = OptionButton.new()
	vehicle_location_monitor_select.custom_minimum_size = Vector2(350, 48)
	vehicle_location_monitor_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in ["Todos os monitoramentos", "Ligado", "Desligado", "Sem leitura"]:
		vehicle_location_monitor_select.add_item(item)
	vehicle_location_monitor_select.item_selected.connect(func(_index: int) -> void: _apply_vehicle_location_filters())
	_style_smart_4g_option(vehicle_location_monitor_select)
	filter_row.add_child(vehicle_location_monitor_select)

	var refresh_button := _make_action_button("Atualizar agora", BLUE, BLUE, Color.WHITE, Vector2(210, 48), Callable(self, "_refresh_vehicle_location_view"))
	refresh_button.tooltip_text = "Atualiza a leitura pela API oficial"
	filter_row.add_child(refresh_button)

	var queue_row := HBoxContainer.new()
	queue_row.custom_minimum_size = Vector2(0, 44)
	queue_row.add_theme_constant_override("separation", 10)
	filter_stack.add_child(queue_row)
	vehicle_location_queue_count_label = Label.new()
	vehicle_location_queue_count_label.custom_minimum_size = Vector2(190, 0)
	vehicle_location_queue_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vehicle_location_queue_count_label.add_theme_font_override("font", UI_FONT)
	vehicle_location_queue_count_label.add_theme_font_size_override("font_size", 13)
	vehicle_location_queue_count_label.add_theme_color_override("font_color", BLUE_DARK)
	queue_row.add_child(vehicle_location_queue_count_label)
	var queue_scroll := ScrollContainer.new()
	queue_scroll.name = "VehicleLocationQueueScroll"
	queue_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	queue_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	queue_scroll.custom_minimum_size = Vector2(0, 42)
	queue_row.add_child(queue_scroll)
	vehicle_location_queue_body = HBoxContainer.new()
	vehicle_location_queue_body.name = "VehicleLocationQueue"
	vehicle_location_queue_body.add_theme_constant_override("separation", 8)
	queue_scroll.add_child(vehicle_location_queue_body)
	var clear_queue_button := _make_action_button(
		"Limpar fila", BUTTON_GRAY, BUTTON_GRAY_BORDER, BLUE_DARK, Vector2(126, 40), Callable(self, "_clear_vehicle_location_queue")
	)
	clear_queue_button.name = "VehicleLocationClearQueue"
	queue_row.add_child(clear_queue_button)
	_refresh_vehicle_location_queue_ui()

	vehicle_location_status_label = Label.new()
	vehicle_location_status_label.text = "Preparando consulta..."
	vehicle_location_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vehicle_location_status_label.add_theme_font_override("font", UI_FONT)
	vehicle_location_status_label.add_theme_font_size_override("font_size", 13)
	vehicle_location_status_label.add_theme_color_override("font_color", BLUE_DARK)
	vehicle_location_updated_label = Label.new()
	vehicle_location_updated_label.text = "Aguardando a primeira consulta"
	vehicle_location_updated_label.add_theme_font_override("font", UI_FONT)
	vehicle_location_updated_label.add_theme_font_size_override("font_size", 11)
	vehicle_location_updated_label.add_theme_color_override("font_color", MUTED)
	vehicle_location_summary_label = Label.new()

	location_runtime_panel = PanelContainer.new()
	location_runtime_panel.add_theme_stylebox_override("panel", _style_box(Color("#f4f9fd"), Color("#cfe2f0"), 1, 10))
	vehicle_location_view_root.add_child(location_runtime_panel)
	var runtime_margin := MarginContainer.new()
	runtime_margin.add_theme_constant_override("margin_left", 14)
	runtime_margin.add_theme_constant_override("margin_right", 14)
	runtime_margin.add_theme_constant_override("margin_top", 9)
	runtime_margin.add_theme_constant_override("margin_bottom", 9)
	location_runtime_panel.add_child(runtime_margin)
	var runtime_row := HBoxContainer.new()
	runtime_row.add_theme_constant_override("separation", 10)
	runtime_margin.add_child(runtime_row)
	var runtime_dot := ColorRect.new()
	runtime_dot.custom_minimum_size = Vector2(9, 9)
	runtime_dot.color = GREEN
	runtime_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	runtime_row.add_child(runtime_dot)
	runtime_row.add_child(vehicle_location_status_label)
	location_runtime_meta_label = Label.new()
	location_runtime_meta_label.text = "API oficial · atualização automática a cada 1 s · sem bateria"
	location_runtime_meta_label.add_theme_font_override("font", UI_FONT)
	location_runtime_meta_label.add_theme_font_size_override("font_size", 11)
	location_runtime_meta_label.add_theme_color_override("font_color", MUTED)
	runtime_row.add_child(location_runtime_meta_label)
	location_runtime_refresh_label = vehicle_location_updated_label
	runtime_row.add_child(location_runtime_refresh_label)

	location_summary_cards = HBoxContainer.new()
	location_summary_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	location_summary_cards.add_theme_constant_override("separation", 10)
	vehicle_location_view_root.add_child(location_summary_cards)
	for metric in [
		["Aparelhos", "Aparelhos", BLUE, "0"],
		["Ligados", "Ligados", GREEN, "0"],
		["Desligados", "Desligados", RED, "0"],
		["Desatualizados", "Desatualizados", YELLOW, "0"],
		["Sem posição", "Sem posição", MUTED, "0"],
	]:
		var metric_data: Array = metric
		location_summary_cards.add_child(_make_location_metric_card(str(metric_data[0]), str(metric_data[1]), metric_data[2]))

	var workspace := HSplitContainer.new()
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Reduz a altura mínima do mapa para reservar espaço visível à lista de
	# veículos. A lista tem rolagem própria para quantidades maiores.
	workspace.custom_minimum_size = Vector2(0, 360)
	workspace.split_offset = 980
	vehicle_location_view_root.add_child(workspace)

	var map_panel := PanelContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_theme_stylebox_override("panel", _style_box(Color("#eef4f8"), Color("#d8e5ef"), 1, 10))
	workspace.add_child(map_panel)
	var map_overlay := Control.new()
	map_overlay.name = "VehicleLocationMapOverlay"
	map_overlay.custom_minimum_size = Vector2(650, 360)
	map_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_panel.add_child(map_overlay)
	vehicle_location_map_canvas = Smart4GMapCanvas.new()
	vehicle_location_map_canvas.name = "VehicleLocationMap"
	vehicle_location_map_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vehicle_location_map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vehicle_location_map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vehicle_location_map_canvas.set_tracking_mode(true)
	vehicle_location_map_canvas.set_station_visibility(true)
	vehicle_location_map_canvas.tracking_selected.connect(_on_vehicle_location_map_selected)
	vehicle_location_map_canvas.station_selected.connect(_on_vehicle_location_station_selected)
	vehicle_location_map_canvas.navigation_requested.connect(_on_vehicle_location_map_navigation)
	vehicle_location_map_canvas.reset_requested.connect(_on_vehicle_location_map_reset)
	map_overlay.add_child(vehicle_location_map_canvas)
	vehicle_location_map_list_toggle = _make_action_button(
		"☰  Veículos", BLUE, BLUE, Color.WHITE, Vector2(156, 40), Callable(self, "_toggle_vehicle_location_list")
	)
	vehicle_location_map_list_toggle.name = "VehicleLocationMapListToggle"
	vehicle_location_map_list_toggle.tooltip_text = "Abrir ou ocultar a lista de veículos localizados"
	vehicle_location_map_list_toggle.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	vehicle_location_map_list_toggle.position = Vector2(-170, -52)
	map_overlay.add_child(vehicle_location_map_list_toggle)

	vehicle_location_details_panel = PanelContainer.new()
	vehicle_location_details_panel.name = "VehicleLocationDetailsPanel"
	vehicle_location_details_panel.custom_minimum_size = Vector2(365, 0)
	vehicle_location_details_panel.add_theme_stylebox_override("panel", _style_box(Color("#ffffff"), Color("#d8e5ef"), 1, 10))
	workspace.add_child(vehicle_location_details_panel)
	var details_margin := MarginContainer.new()
	details_margin.add_theme_constant_override("margin_left", 16)
	details_margin.add_theme_constant_override("margin_right", 16)
	details_margin.add_theme_constant_override("margin_top", 14)
	details_margin.add_theme_constant_override("margin_bottom", 14)
	vehicle_location_details_panel.add_child(details_margin)
	var details_stack := VBoxContainer.new()
	details_stack.add_theme_constant_override("separation", 9)
	details_margin.add_child(details_stack)
	var details_header := HBoxContainer.new()
	details_header.custom_minimum_size = Vector2(0, 36)
	details_header.add_theme_constant_override("separation", 8)
	details_stack.add_child(details_header)
	var details_title := Label.new()
	details_title.text = "Veículo selecionado"
	details_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	details_title.add_theme_font_override("font", UI_FONT)
	details_title.add_theme_font_size_override("font_size", 19)
	details_title.add_theme_color_override("font_color", TEXT)
	details_header.add_child(details_title)
	var details_close := Button.new()
	details_close.name = "VehicleLocationDetailsClose"
	details_close.text = "×"
	details_close.custom_minimum_size = Vector2(34, 34)
	details_close.focus_mode = Control.FOCUS_NONE
	details_close.tooltip_text = "Fechar detalhes; o painel será reaberto ao selecionar outro aparelho"
	details_close.add_theme_font_override("font", UI_FONT)
	details_close.add_theme_font_size_override("font_size", 24)
	details_close.add_theme_color_override("font_color", MUTED)
	details_close.add_theme_color_override("font_hover_color", RED)
	details_close.add_theme_stylebox_override("normal", _style_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 6))
	details_close.add_theme_stylebox_override("hover", _style_box(Color("#f2f6fa"), Color("#d8e5ef"), 1, 6))
	details_close.pressed.connect(_close_vehicle_location_details)
	details_header.add_child(details_close)
	vehicle_location_details_body = VBoxContainer.new()
	vehicle_location_details_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vehicle_location_details_body.add_theme_constant_override("separation", 0)
	details_stack.add_child(vehicle_location_details_body)
	_render_vehicle_location_details({})

	var list_panel := PanelContainer.new()
	vehicle_location_list_panel = list_panel
	# Reserva uma área confortável para várias linhas; filas maiores continuam
	# roláveis dentro do painel.
	list_panel.custom_minimum_size = Vector2(0, 280)
	list_panel.add_theme_stylebox_override("panel", _style_box(Color("#ffffff"), Color("#d8e5ef"), 1, 10))
	vehicle_location_view_root.add_child(list_panel)
	var list_margin := MarginContainer.new()
	list_margin.add_theme_constant_override("margin_left", 14)
	list_margin.add_theme_constant_override("margin_right", 14)
	list_margin.add_theme_constant_override("margin_top", 11)
	list_margin.add_theme_constant_override("margin_bottom", 11)
	list_panel.add_child(list_margin)
	var list_stack := VBoxContainer.new()
	list_stack.add_theme_constant_override("separation", 6)
	list_margin.add_child(list_stack)
	var list_header := HBoxContainer.new()
	list_header.add_theme_constant_override("separation", 8)
	list_stack.add_child(list_header)
	var list_title := Label.new()
	list_title.text = "Veículos localizados"
	list_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_title.add_theme_font_override("font", UI_FONT)
	list_title.add_theme_font_size_override("font_size", 16)
	list_title.add_theme_color_override("font_color", TEXT)
	list_header.add_child(list_title)
	var list_note := Label.new()
	list_note.text = "Clique em uma linha para abrir os detalhes"
	list_note.add_theme_font_override("font", UI_FONT)
	list_note.add_theme_font_size_override("font_size", 11)
	list_note.add_theme_color_override("font_color", MUTED)
	list_header.add_child(list_note)
	# Compatibilidade com layouts antigos que ainda possam ter criado o
	# comando duplicado no cabeçalho. O controle oficial fica sobre o mapa.
	for obsolete in vehicle_location_view_root.find_children("VehicleLocationListToggle", "Button", true, false):
		var obsolete_parent := obsolete.get_parent()
		if obsolete_parent != null:
			obsolete_parent.remove_child(obsolete)
		obsolete.queue_free()

	var table_header := PanelContainer.new()
	table_header.custom_minimum_size = Vector2(0, 34)
	table_header.add_theme_stylebox_override("panel", _style_box(Color("#f5f8fb"), Color("#e1eaf2"), 1, 6))
	list_stack.add_child(table_header)
	var table_header_row := HBoxContainer.new()
	table_header_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	table_header_row.add_theme_constant_override("separation", 8)
	table_header.add_child(table_header_row)
	for header in [["Status", 120, false], ["Placa", 125, false], ["Série", 125, false], ["Cliente", 220, true], ["Posição", 125, false], ["Última comunicação", 170, false], ["Velocidade", 105, false], ["Fonte", 120, false]]:
		var header_data: Array = header
		table_header_row.add_child(_make_table_label(str(header_data[0]), int(header_data[1]), bool(header_data[2]), BLUE_DARK, HORIZONTAL_ALIGNMENT_LEFT, 11))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# A lista continua rolável, mas o indicador visual fica oculto: o controle
	# flutuante sobre o mapa é o único comando de abrir/recolher.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	list_stack.add_child(scroll)
	vehicle_location_list_body = VBoxContainer.new()
	vehicle_location_list_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vehicle_location_list_body.add_theme_constant_override("separation", 4)
	scroll.add_child(vehicle_location_list_body)
	for obsolete in vehicle_location_view_root.find_children("VehicleLocationListToggle", "Button", true, false):
		var obsolete_parent := obsolete.get_parent()
		if obsolete_parent != null:
			obsolete_parent.remove_child(obsolete)
		obsolete.queue_free()
	return vehicle_location_view_root


func _make_location_metric_card(title_text: String, key: String, accent: Color) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(145, 72)
	card.add_theme_stylebox_override("panel", _style_box(Color.WHITE, Color("#d8e5ef"), 1, 9))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)
	var accent_bar := ColorRect.new()
	accent_bar.custom_minimum_size = Vector2(4, 45)
	accent_bar.color = accent
	accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(accent_bar)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 2)
	row.add_child(stack)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_override("font", UI_FONT)
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", MUTED)
	stack.add_child(title)
	var value := Label.new()
	value.text = "0"
	value.add_theme_font_override("font", UI_FONT)
	value.add_theme_font_size_override("font_size", 22)
	value.add_theme_color_override("font_color", accent)
	stack.add_child(value)
	vehicle_location_summary_value_labels[key] = value
	return card


func _refresh_vehicle_location_view(expected_generation: int = -1) -> void:
	if vehicle_location_refreshing:
		return
	# A consulta de Localizacao nao reutiliza a leitura anterior: o polling de
	# 1 s deve consultar novamente a API para receber uma nova coordenada.
	grupo_rs_api_location_cache_checked_at = 0
	var lookup_query := vehicle_location_plate_input.text.strip_edges() if vehicle_location_plate_input != null else ""
	var previous_query := location_last_query
	var previous_rows := _clone_location_rows(location_last_valid_rows)
	var started_at := Time.get_ticks_msec()
	await super._refresh_vehicle_location_view(expected_generation)
	if expected_generation >= 0 and expected_generation != vehicle_location_query_generation:
		return
	location_last_latency_ms = maxi(0, Time.get_ticks_msec() - started_at)
	location_last_refresh_at = Time.get_time_string_from_system()
	location_last_query = lookup_query
	if lookup_query == "":
		location_last_error = ""
		_update_location_runtime_banner("Digite uma placa ou série")
		return

	# A API pode devolver a identidade antes de devolver uma nova posição. Nessa
	# janela, mantemos a última coordenada confirmada, mas marcamos a linha como
	# antiga para nunca apresentar a posição anterior como se fosse atual.
	if previous_query == lookup_query and not previous_rows.is_empty():
		if vehicle_location_rows.is_empty():
			vehicle_location_rows = _clone_location_rows(previous_rows)
			for row in vehicle_location_rows:
				row["position_preserved"] = true
				row["refresh_error"] = "A consulta não trouxe uma nova leitura; última posição válida mantida."
			vehicle_location_source = "API oficial"
			_apply_vehicle_location_filters()
		else:
			var merged_rows := _merge_last_valid_positions(previous_rows, vehicle_location_rows)
			if merged_rows.size() > 0:
				vehicle_location_rows = merged_rows
				_apply_vehicle_location_filters()

	if _has_valid_location_row(vehicle_location_rows):
		location_last_valid_rows = _clone_location_rows(vehicle_location_rows)
		location_last_error = ""
	else:
		location_last_error = "Nenhuma coordenada válida retornada pela API."
	_update_location_runtime_banner("")


func _clone_location_rows(rows: Array[Dictionary]) -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for row in rows:
		copied.append(row.duplicate(true))
	return copied


func _location_row_key(location: Dictionary) -> String:
	var serial := _search_key(str(location.get("serial", "")))
	if serial != "":
		return "serial:" + serial
	return "plate:" + _normalize_location_plate(str(location.get("plate", "")))


func _merge_last_valid_positions(previous_rows: Array[Dictionary], current_rows: Array[Dictionary]) -> Array[Dictionary]:
	var previous_by_key: Dictionary = {}
	for row in previous_rows:
		if _location_coordinates_valid(row):
			previous_by_key[_location_row_key(row)] = row
	var merged: Array[Dictionary] = []
	for row in current_rows:
		var next_row := row.duplicate(true)
		var previous: Dictionary = previous_by_key.get(_location_row_key(next_row), {})
		if not _location_coordinates_valid(next_row) and not previous.is_empty():
			next_row["lat"] = previous.get("lat", 0.0)
			next_row["lng"] = previous.get("lng", 0.0)
			next_row["position_preserved"] = true
			next_row["refresh_error"] = "A API ainda não confirmou uma nova posição."
		merged.append(next_row)
	return merged


func _location_coordinates_valid(location: Dictionary) -> bool:
	if bool(location.get("coordinates_valid", false)):
		return true
	var latitude := float(str(location.get("lat", "0")).replace(",", "."))
	var longitude := float(str(location.get("lng", "0")).replace(",", "."))
	return abs(latitude) > 0.000001 and abs(longitude) > 0.000001


func _has_valid_location_row(rows: Array[Dictionary]) -> bool:
	for row in rows:
		if _location_coordinates_valid(row):
			return true
	return false


func _update_location_runtime_banner(message: String) -> void:
	if vehicle_location_status_label == null or not is_instance_valid(vehicle_location_status_label):
		return
	var valid_count := 0
	var old_count := 0
	var no_position_count := 0
	for row in vehicle_location_rows:
		if _location_coordinates_valid(row):
			valid_count += 1
		if bool(row.get("position_preserved", false)):
			old_count += 1
		if not _location_coordinates_valid(row):
			no_position_count += 1
	var query := vehicle_location_plate_input.text.strip_edges() if vehicle_location_plate_input != null else ""
	if query == "":
		vehicle_location_status_label.text = "Informe uma placa ou número de série para iniciar"
		vehicle_location_status_label.add_theme_color_override("font_color", MUTED)
	else:
		var summary := "%d aparelho(s) · %d posição(ões) válida(s)" % [vehicle_location_rows.size(), valid_count]
		if old_count > 0:
			summary += " · %d desatualizado(s)" % old_count
		if no_position_count > 0:
			summary += " · %d sem posição" % no_position_count
		vehicle_location_status_label.text = message if message != "" else summary
		vehicle_location_status_label.add_theme_color_override("font_color", YELLOW if old_count > 0 else (ORANGE if no_position_count > 0 else GREEN))
	if location_runtime_meta_label != null and is_instance_valid(location_runtime_meta_label):
		location_runtime_meta_label.text = "API oficial · atualização automática a cada 1 s · sem bateria"
	if location_runtime_refresh_label != null and is_instance_valid(location_runtime_refresh_label):
		if location_last_latency_ms >= 0:
			location_runtime_refresh_label.text = "Atualizado %s · %d ms" % [location_last_refresh_at.substr(0, 8), location_last_latency_ms]
		else:
			location_runtime_refresh_label.text = "Aguardando atualização"


func _location_age_text(location: Dictionary) -> String:
	var updated_at := str(location.get("updated_at", "")).strip_edges()
	if updated_at == "":
		return "Sem data"
	var hours := _hours_since_grupo_rs_datetime(updated_at)
	if hours < 0.0:
		return "Data inválida"
	var seconds := int(hours * 3600.0)
	if seconds < 60:
		return "agora"
	if seconds < 3600:
		return "%d min" % int(seconds / 60)
	if seconds < 86400:
		return "%d h" % int(seconds / 3600)
	return "%d d" % int(seconds / 86400)


func _location_device_status(location: Dictionary) -> Dictionary:
	var ignition_state := _location_ignition_state(location.get("ignition", null))
	if ignition_state == 1:
		return {"label": "Ligado", "color": GREEN}
	if ignition_state == 0:
		return {"label": "Desligado", "color": RED}
	var speed := str(location.get("speed", "0")).replace(",", ".").strip_edges()
	if speed.is_valid_float() and speed.to_float() > 0.0:
		return {"label": "Ligado", "color": GREEN}
	return {"label": "Sem status", "color": MUTED}


func _location_monitoring_status(location: Dictionary) -> Dictionary:
	var updated_at := str(location.get("updated_at", "")).strip_edges()
	var ignition_state := _location_ignition_state(location.get("ignition", null))
	return VehicleStatusResolver.resolve(
		location,
		_location_coordinates_valid(location),
		_hours_since_grupo_rs_datetime(updated_at),
		ignition_state,
		{"on": GREEN, "off": RED, "stale": YELLOW, "unknown": MUTED}
	)


func _set_location_communication_state(location: Dictionary, label: String, color: Color) -> Dictionary:
	return VehicleStatusResolver.apply_state(location, label, color)


func _update_vehicle_location_summary(_counts: Dictionary) -> void:
	var all_count := vehicle_location_filtered_rows.size()
	var on_count := 0
	var off_count := 0
	var old_count := 0
	var no_position_count := 0
	for location in vehicle_location_filtered_rows:
		var status := _location_monitoring_status(location)
		var label := str(status.get("label", ""))
		if label == "Ligado":
			on_count += 1
		elif label == "Desligado":
			off_count += 1
		elif label == "Desatualizado":
			old_count += 1
		elif label == "Sem posição" or label == "Sem comunicação":
			no_position_count += 1
		if bool(location.get("position_preserved", false)):
			if label != "Desatualizado":
				old_count += 1
	var labels := {
		"Aparelhos": str(all_count),
		"Ligados": str(on_count),
		"Desligados": str(off_count),
		"Desatualizados": str(old_count),
		"Sem posição": str(no_position_count),
	}
	for key in labels.keys():
		var value_label: Variant = vehicle_location_summary_value_labels.get(key, null)
		if value_label is Label and is_instance_valid(value_label):
			(value_label as Label).text = str(labels[key])


func _make_vehicle_location_row(location: Dictionary) -> Control:
	var button := Button.new()
	button.text = ""
	button.custom_minimum_size = Vector2(0, 44)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _style_box(Color.WHITE, Color("#e2ebf2"), 1, 7))
	button.add_theme_stylebox_override("hover", _style_box(Color("#f2f8fc"), BLUE, 1, 7))
	button.add_theme_stylebox_override("pressed", _style_box(Color("#e3f1fa"), BLUE, 1, 7))
	button.pressed.connect(func() -> void: _on_vehicle_location_map_selected(location))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	button.add_child(row)
	var status := _location_device_status(location)
	var status_box := HBoxContainer.new()
	status_box.custom_minimum_size = Vector2(120, 0)
	status_box.add_theme_constant_override("separation", 7)
	status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.color = status.get("color", MUTED)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_box.add_child(dot)
	var status_text := _make_table_label(str(status.get("label", "Sem leitura")), 0, true, status.get("color", MUTED), HORIZONTAL_ALIGNMENT_LEFT, 11)
	status_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_box.add_child(status_text)
	row.add_child(status_box)
	row.add_child(_make_location_row_label(_blank(str(location.get("plate", ""))), 125, false, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 12))
	row.add_child(_make_location_row_label(_blank(str(location.get("serial", ""))), 125, false, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 12))
	row.add_child(_make_location_row_label(_blank(str(location.get("client", ""))), 220, true, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 12))
	var position_status := _location_monitoring_status(location)
	row.add_child(_make_location_row_label(str(position_status.get("label", "Sem posição")), 125, false, position_status.get("color", MUTED), HORIZONTAL_ALIGNMENT_LEFT, 11))
	row.add_child(_make_location_row_label(_blank(str(location.get("updated_at", ""))), 170, false, MUTED, HORIZONTAL_ALIGNMENT_LEFT, 11))
	row.add_child(_make_location_row_label(_location_speed_display(location.get("speed", "")), 105, false, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 11))
	row.add_child(_make_location_row_label(_blank(str(location.get("source", vehicle_location_source))), 120, false, BLUE, HORIZONTAL_ALIGNMENT_LEFT, 11))
	return button


func _make_location_row_label(text_value: String, width: int, expand: bool, color: Color, alignment: HorizontalAlignment, font_size: int) -> Label:
	var label := _make_table_label(text_value, width, expand, color, alignment, font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _render_vehicle_location_details(location: Dictionary) -> void:
	if vehicle_location_details_body == null or not is_instance_valid(vehicle_location_details_body):
		return
	for child in vehicle_location_details_body.get_children():
		vehicle_location_details_body.remove_child(child)
		child.queue_free()
	if location.is_empty():
		var empty := Label.new()
		empty.text = "Selecione um marcador ou uma linha para ver os dados."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_override("font", UI_FONT)
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", MUTED)
		vehicle_location_details_body.add_child(empty)
		return
	var status := _location_monitoring_status(location)
	var identity_row := HBoxContainer.new()
	identity_row.custom_minimum_size = Vector2(0, 46)
	identity_row.add_theme_constant_override("separation", 8)
	vehicle_location_details_body.add_child(identity_row)
	var identity := Label.new()
	identity.text = _blank(str(location.get("plate", location.get("serial", ""))))
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity.add_theme_font_override("font", UI_FONT)
	identity.add_theme_font_size_override("font_size", 21)
	identity.add_theme_color_override("font_color", BLUE_DARK)
	identity_row.add_child(identity)
	var status_pill := PanelContainer.new()
	status_pill.custom_minimum_size = Vector2(112, 30)
	var status_color: Color = status.get("color", MUTED)
	status_pill.add_theme_stylebox_override("panel", _style_box(Color(status_color.r, status_color.g, status_color.b, 0.10), Color.TRANSPARENT, 0, 7))
	identity_row.add_child(status_pill)
	var pill_center := CenterContainer.new()
	status_pill.add_child(pill_center)
	var status_text := Label.new()
	status_text.text = str(status.get("label", "Sem leitura"))
	status_text.add_theme_font_override("font", UI_FONT)
	status_text.add_theme_font_size_override("font_size", 12)
	status_text.add_theme_color_override("font_color", status_color)
	pill_center.add_child(status_text)
	var top_divider := HSeparator.new()
	top_divider.add_theme_color_override("separator_color", Color("#dce7f0"))
	vehicle_location_details_body.add_child(top_divider)
	var position_state := _location_monitoring_status(location)
	var coordinate_text := "%s, %s" % [str(location.get("lat", "")), str(location.get("lng", ""))] if _location_coordinates_valid(location) else "Sem posição válida"
	for item in [
		["Série", str(location.get("serial", ""))],
		["Placa", str(location.get("plate", ""))],
		["Cliente", str(location.get("client", ""))],
		["Status", str(position_state.get("label", "Sem posição"))],
		["Idade da posição", _location_age_text(location)],
		["Velocidade", _location_speed_display(location.get("speed", ""))],
		["Última comunicação", str(location.get("updated_at", ""))],
		["Coordenadas", coordinate_text],
		["Operadora do rastreador", _location_operator_text(location)],
		["ERBs próximas", str(location.get("nearby_tower_count", "0"))],
		["ERB mais próxima", _location_nearest_tower_text(location)],
		["Fonte", str(location.get("source", vehicle_location_source))],
		["Latência", "%d ms" % location_last_latency_ms if location_last_latency_ms >= 0 else "aguardando"],
	]:
		var item_data: Array = item
		vehicle_location_details_body.add_child(_make_location_detail_line(str(item_data[0]), _blank(str(item_data[1]))))
	var center_button := _make_action_button("Centralizar no mapa", Color.WHITE, BLUE, BLUE, Vector2(0, 38), Callable(self, "_center_vehicle_location_selected"))
	center_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_button.add_theme_font_size_override("font_size", 13)
	vehicle_location_details_body.add_child(center_button)


func _location_operator_text(location: Dictionary) -> String:
	var operator_name := str(location.get("tracker_operator", location.get("operator", ""))).strip_edges()
	if operator_name == "":
		return "Não determinada"
	var source := str(location.get("tracker_operator_source", "")).strip_edges()
	return "%s (%s)" % [operator_name, source] if source != "" else operator_name


func _location_nearest_tower_text(location: Dictionary) -> String:
	var tower_value: Variant = location.get("selected_tower", location.get("nearest_tower", {}))
	var tower: Dictionary = tower_value if typeof(tower_value) == TYPE_DICTIONARY else {}
	if tower.is_empty():
		return "Nenhuma ERB catalogada"
	var tower_id := str(tower.get("id", tower.get("code", ""))).strip_edges()
	var operator_name := str(tower.get("operator", "")).strip_edges()
	var distance := float(tower.get("distance_km", -1.0))
	var distance_text := "--" if distance < 0.0 else ("%d m" % roundi(distance * 1000.0) if distance < 1.0 else "%.1f km" % distance)
	var label := tower_id if tower_id != "" else "ERB sem identificação"
	if operator_name != "":
		label += " · " + operator_name
	return "%s · %s" % [label, distance_text]


func _center_vehicle_location_selected() -> void:
	if vehicle_location_selected.is_empty():
		return
	var latitude := float(str(vehicle_location_selected.get("lat", "0")))
	var longitude := float(str(vehicle_location_selected.get("lng", "0")))
	if is_zero_approx(latitude) or is_zero_approx(longitude):
		return
	_on_vehicle_location_map_navigation(latitude, longitude, 16)


func _make_location_detail_line(caption_text: String, value_text: String) -> Control:
	var row := VBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 34)
	var line := HBoxContainer.new()
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.add_theme_constant_override("separation", 8)
	row.add_child(line)
	var caption := Label.new()
	caption.text = caption_text
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font", UI_FONT)
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", MUTED)
	line.add_child(caption)
	var value := Label.new()
	value.text = value_text
	value.custom_minimum_size = Vector2(170, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_font_override("font", UI_FONT)
	value.add_theme_font_size_override("font_size", 12)
	value.add_theme_color_override("font_color", TEXT)
	line.add_child(value)
	var divider := HSeparator.new()
	divider.add_theme_color_override("separator_color", Color("#e3ebf2"))
	row.add_child(divider)
	return row
