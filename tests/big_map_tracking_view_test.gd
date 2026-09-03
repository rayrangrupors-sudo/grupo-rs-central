## Contrato deterministico da interface reconstruida do Mapa Grande.
extends SceneTree

const TrackingView := preload("res://src/features/big_map/big_map_tracking_view.gd")

var failures: Array[String] = []


func _init() -> void:
	var view := TrackingView.new()
	_check(view.query_input != null, "Campo de consulta nao foi criado.")
	var query_placeholder := view.query_input.placeholder_text.to_lower()
	_check(query_placeholder.contains("placa") and query_placeholder.contains("série") and query_placeholder.contains("cliente"), "Placeholder não explicita placa, número de série e cliente.")
	_check(view.monitor_select.item_count == 5, "Filtros operacionais incompletos.")
	_check(view.camera_lock_check != null, "Controle de camera ausente.")
	_check(view.add_button.get_parent() == view.query_input.get_parent() and view.refresh_button.get_parent() == view.query_input.get_parent(), "Pesquisa e ações não estão na mesma linha.")
	_check(not view.get_node("TrackingErbFilters").visible, "Filtros deveriam começar recolhidos.")
	view.advanced_button.button_pressed = true
	_check(view.get_node("TrackingErbFilters").visible, "Botão Filtros não expande os controles.")
	view.advanced_button.button_pressed = false
	_check(view.erb_layer_check.get_parent().name == "TrackingMapOverlay", "ERBs não estão sobre o mapa.")
	view.erb_layer_check.button_pressed = false
	_check(view.erb_layer_check.text == "Mostrar ERBs", "Rótulo de ERBs não alterna.")
	view.erb_layer_check.button_pressed = true
	_check(view.maintenance_button != null, "Botão de manutenção ausente.")
	view.set_maintenance_progress(true, true, {"total": 10, "processed": 4, "Processados": 4}, "4 de 10")
	_check(view.maintenance_button.text == "Cancelar busca", "Cancelamento não aparece.")
	_check(view.maintenance_progress.value == 4, "Progresso não atualiza.")
	view.set_maintenance_progress(false, false, {}, "")
	_check(view.erb_layer_check.button_pressed, "Camada de ERBs deveria iniciar ligada.")
	_check(view.basemap_select.item_count == 1, "Interface ainda expõe mais de um mapa-base.")
	_check(str(view.basemap_select.get_item_metadata(view.basemap_select.selected)) == "normal", "Interface não fixa OpenStreetMap.")
	_check(view.basemap_select.disabled, "Seletor de mapa único deveria estar bloqueado.")
	_check(view.basemap_select.get_item_text(0) == "Mapa-base · OpenStreetMap", "Mapa-base fixo ainda parece um seletor quebrado.")
	_check(view.erb_operator_select != null and view.erb_generation_select != null, "Filtros de prestadora/tecnologia ausentes.")
	_check(view.erb_city_select != null and view.erb_status_select != null, "Filtros de município/situação ausentes.")
	for option in [view.erb_operator_select, view.erb_generation_select, view.erb_city_select, view.erb_status_select]:
		_check(option.has_theme_color_override("font_focus_color"), "Select focado não fixa cor tipográfica legível.")
		_check(option.has_theme_color_override("font_hover_pressed_color"), "Select hover+pressed não fixa cor tipográfica legível.")
		_check(option.get_theme_color("font_focus_color") == option.get_theme_color("font_color"), "Texto focado diverge da cor normal do select.")
		_check(option.get_theme_color("font_hover_pressed_color") == option.get_theme_color("font_color"), "Texto hover+pressed diverge da cor normal do select.")
	_check(not view.list_panel.visible, "Lista deveria iniciar recolhida.")
	_check(view.map_canvas.has_signal("tracking_selected"), "Canvas perdeu selecao de veiculo.")
	_check(view.map_canvas.has_signal("station_selected"), "Canvas perdeu selecao de ERB.")
	view.set_metrics({"Total": 8, "Com posição": 6, "Em movimento": 2, "Parados": 3, "Desatualizados": 1, "Sem posição": 2})
	_check(str(view.metric_labels["Total"].text) == "8", "Total nao atualizou.")
	_check(str(view.metric_labels["Sem posição"].text) == "2", "Contagem sem posicao nao atualizou.")
	view.set_runtime("6 posições válidas", Color.GREEN, "OpenStreetMap", "Atualizado agora")
	_check(view.status_label.text == "6 posições válidas", "Faixa operacional nao atualizou.")
	view.set_query_state("loading")
	_check(view.query_state_label.text == "Buscando localização...", "Estado de carregamento da pesquisa não atualizou.")
	view.set_query_state("found")
	_check(view.query_state_label.text == "Localização encontrada", "Estado encontrado da pesquisa não atualizou.")
	view.set_query_state("not_found")
	_check(view.query_state_label.text == "Nenhuma localização encontrada", "Estado não encontrado da pesquisa não atualizou.")
	view.set_query_state("error")
	_check(view.query_state_label.text == "Erro ao buscar localização", "Estado de erro da pesquisa não atualizou.")
	view.set_erb_source("Anatel SMP", "Licenciamento não é sinal em tempo real.", Color.GREEN)
	_check(view.erb_source_label.text == "Anatel SMP", "Fonte Anatel não atualizou.")
	var operators: Array[String] = ["TIM", "CLARO"]
	var generations: Array[String] = ["2G", "3G", "4G", "5G"]
	var cities: Array[String] = ["", "Imperatriz - MA"]
	var statuses: Array[String] = ["Licenciada"]
	view.set_erb_filter_values(operators, generations, cities, statuses)
	_check(view.erb_generation_select.item_count == 5, "Filtro não preservou 2G/3G/4G/5G.")
	_check(view.erb_city_select.get_item_text(1) == "Não informado pela fonte", "Campo ausente não foi sinalizado.")
	view.erb_city_select.select(1)
	_check(str(view.selected_erb_filters().get("city", "")) == "__missing__", "Filtro de campo ausente perdeu o contrato.")
	view.set_list_expanded(true)
	_check(view.list_panel.visible, "Lista nao abriu.")
	view.size = Vector2(1366, 768)
	view.call("_apply_responsive_layout")
	_check(view.details_panel.custom_minimum_size.x == 325.0, "Painel lateral não respeitou o contrato de 1366 px.")
	_check(view.workspace_split.custom_minimum_size.y >= 465.0, "Mapa ficou abaixo da altura mínima em 1366x768.")
	view.size = Vector2(1920, 1080)
	view.call("_apply_responsive_layout")
	_check(view.details_panel.custom_minimum_size.x == 325.0, "Painel lateral não respeitou o contrato de 1920 px.")
	_check(view.map_canvas.custom_minimum_size.x >= 720.0, "Mapa ficou abaixo da largura mínima em 1920x1080.")
	view.free()
	if failures.is_empty():
		print("BIG_MAP_TRACKING_VIEW_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
