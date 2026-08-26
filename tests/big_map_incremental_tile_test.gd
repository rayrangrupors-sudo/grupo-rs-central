## Prova offline de carregamento incremental, cache e preservação das camadas.
extends SceneTree

const Dashboard := preload("res://tests/fixtures/offline_tile_dashboard.gd")
const Canvas := preload("res://src/features/big_map/big_map_canvas.gd")
const Config := preload("res://src/features/big_map/big_map_config.gd")
const TileProvider := preload("res://src/features/big_map/map_tile_provider.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := Dashboard.new()
	root.add_child(dashboard)
	var canvas := Canvas.new()
	dashboard.add_child(canvas)
	canvas.size = Vector2(800, 420)
	await process_frame

	var initial_view := _view(Config.DEFAULT_LATITUDE, Config.DEFAULT_LONGITUDE, Config.DEFAULT_ZOOM)
	await dashboard.call("_load_smart_4g_map_tiles", canvas, [], "all", initial_view)
	var first_state: Dictionary = dashboard.call("_smart_4g_tile_cache_state")
	var first_network := int(first_state.get("network_requests", 0))
	var first_decodes := int(first_state.get("decodes", 0))
	var first_visible := canvas.visible_map_tiles.size()
	_check(first_network > 0 and first_network == first_visible, "Carga inicial não solicitou exatamente os tiles visíveis.")
	_check(first_decodes == first_visible, "Carga inicial não decodificou cada tile uma única vez.")
	_check(str(canvas.basemap_id) == Config.BASEMAP_NORMAL, "Fixture incremental não usa OpenStreetMap.")
	await _test_redraw_coalescing(dashboard, canvas)

	var synthetic_locations: Array[Dictionary] = [
		{"plate": "SYN1A01", "serial": "SYN-1001", "lat": -5.5264, "lng": -47.4919, "ignition": 1},
	]
	canvas.set_tracking_locations(synthetic_locations)
	canvas.set_coverage_profile({"stations": [{"id": "SYN-ERB", "lat": -5.5260, "lng": -47.4920, "operator": "TIM", "generation": "4G"}]})
	var individual_stations: Array[Dictionary] = []
	for index in range(100):
		individual_stations.append({"id": "SYN-ERB-%d" % index, "lat": -5.5260 + index * 0.00001, "lng": -47.4920, "operator": "TIM", "generation": "4G"})
	canvas.set_coverage_profile({"stations": individual_stations})
	_check(not bool(canvas.call("_should_cluster_stations")), "Canvas tentou substituir ERBs individuais por bolhas.")
	var density_metrics: Dictionary = canvas.call("station_render_metrics")
	_check(int(density_metrics.get("source_station_count", 0)) == 100, "Métrica de ERBs-fonte divergiu.")
	_check(int(density_metrics.get("rendered_station_count", 100)) < 100, "Sobreposição visual não foi reduzida no zoom médio.")
	_check(int(density_metrics.get("density_hidden_count", 0)) > 0, "Métrica de ERBs ocultas não foi registrada.")
	var visible_indices: Array = canvas.call("_visible_station_indices")
	var visible_positions: Array = canvas.call("_station_visual_positions")
	for visible_index in visible_indices:
		var visible_station: Dictionary = individual_stations[int(visible_index)]
		_check(not bool(visible_station.get("is_index_cluster", false)), "Declutter incluiu agregado/centroide.")
		_check(str(visible_station.get("id", "")) != "", "Declutter criou marcador sem identidade real.")
	for left_index in range(visible_indices.size()):
		for right_index in range(left_index + 1, visible_indices.size()):
			var left_position: Vector2 = visible_positions[int(visible_indices[left_index])]
			var right_position: Vector2 = visible_positions[int(visible_indices[right_index])]
			_check(left_position.distance_to(right_position) >= 38.0, "Declutter preservou torres visualmente sobrepostas.")
	# Selecionar uma ERB já visível deve alterar somente seu destaque. A lista
	# decluttered, as projeções e a câmera permanecem byte-a-byte equivalentes.
	var visible_before_selection: Array = visible_indices.duplicate()
	var positions_before_selection: Array = visible_positions.duplicate()
	var center_before_selection: Dictionary = canvas.current_map_view().duplicate(true)
	var view_revision_before_selection: int = canvas.map_view_revision
	var station_revision_before_selection: int = canvas.station_data_revision
	var selected_visible_index := int(visible_indices[0])
	var selected_anchor: Vector2 = canvas.call("_station_screen_anchor", visible_positions[selected_visible_index])
	var normal_geometry: Dictionary = canvas.call("_station_marker_visual_geometry", selected_anchor, false)
	var selected_geometry: Dictionary = canvas.call("_station_marker_visual_geometry", selected_anchor, true)
	canvas.select_station_by_id(str(individual_stations[selected_visible_index].get("id", "")))
	var visible_after_selection: Array = canvas.call("_visible_station_indices")
	var positions_after_selection: Array = canvas.call("_station_visual_positions")
	_check(normal_geometry.get("anchor") == selected_geometry.get("anchor"), "Seleção de ERB alterou o ponto de âncora geográfico.")
	_check(normal_geometry.get("center") == selected_geometry.get("center"), "Seleção de ERB deslocou o centro geométrico.")
	_check(selected_geometry.get("halo_center") == selected_anchor, "Halo da ERB não está centralizado no anchor original.")
	_check((normal_geometry.get("rect") as Rect2).get_center() == (selected_geometry.get("rect") as Rect2).get_center(), "Escala selecionada não cresceu ao redor do mesmo pivô.")
	_check(selected_geometry.get("size") == normal_geometry.get("size"), "Seleção de ERB alterou tamanho ou escala.")
	_check(selected_geometry.get("rect") == normal_geometry.get("rect"), "Seleção de ERB alterou sua geometria.")
	_check(canvas.call("_should_draw_station_operator_label", false) == canvas.call("_should_draw_station_operator_label", true), "Seleção de ERB acrescentou etiqueta fora da regra normal de zoom.")
	_check(visible_after_selection == visible_before_selection, "Seleção de ERB alterou o conjunto visível/declutter.")
	_check(positions_after_selection == positions_before_selection, "Seleção de ERB deslocou projeções na tela.")
	_check(canvas.current_map_view() == center_before_selection, "Seleção de ERB alterou centro ou zoom da câmera.")
	_check(canvas.map_view_revision == view_revision_before_selection, "Seleção de ERB alterou a revisão da viewport.")
	_check(canvas.station_data_revision == station_revision_before_selection, "Seleção de ERB recarregou os dados Anatel.")
	_check(int(canvas.call("_nearest_station_index", selected_anchor)) == selected_visible_index, "Hit-test da ERB não usa o mesmo pivô do desenho.")
	for _repeat in range(3):
		canvas.select_station_by_id("")
		canvas.select_station_by_id(str(individual_stations[selected_visible_index].get("id", "")))
		_check(canvas.call("_visible_station_indices") == visible_before_selection, "Seleção repetida da ERB alterou a composição.")
		_check(canvas.call("_station_visual_positions") == positions_before_selection, "Seleção repetida da ERB deslocou posições.")

	# Em sobreposição exata, o clique e a ordem lógica priorizam o veículo.
	var overlap_locations: Array[Dictionary] = [
		{"plate": "SYN1A01", "serial": "SYN-1001", "lat": -5.5260, "lng": -47.4920, "ignition": 1},
	]
	canvas.set_tracking_locations(overlap_locations)
	_check(canvas.call("_tracking_pin_draw_size", false) == canvas.call("_tracking_pin_draw_size", true), "Seleção de veículo alterou o tamanho da agulha.")
	var overlap_position: Vector2 = canvas.call("_tracking_map_position", 0, overlap_locations[0])
	var normal_pin_geometry: Dictionary = canvas.call("_tracking_pin_visual_geometry", overlap_position, false)
	var selected_pin_geometry: Dictionary = canvas.call("_tracking_pin_visual_geometry", overlap_position, true)
	_check(normal_pin_geometry == selected_pin_geometry, "Seleção de veículo alterou rect, escala, anchor ou geometria da agulha.")
	_check(selected_pin_geometry.get("halo_center") == overlap_position, "Halo do veículo não está centralizado no anchor GPS.")
	_check(int(canvas.call("_nearest_tracking_index", overlap_position)) == 0, "Hit-test sobreposto não priorizou o veículo na camada frontal.")
	var tracking_groups_before_selection: Array = canvas.call("_tracking_visual_groups").duplicate(true)
	var tracking_view_before_selection: Dictionary = canvas.current_map_view().duplicate(true)
	var tracking_drag_before_selection: Vector2 = canvas.drag_offset
	var tracking_revision_before_selection: int = canvas.map_view_revision
	for _repeat in range(3):
		canvas.clear_tracking_selection()
		canvas.select_tracking_by_key("SYN-1001")
		var repeated_overlap_position: Vector2 = canvas.call("_tracking_map_position", 0, overlap_locations[0])
		_check(repeated_overlap_position == overlap_position, "Seleção repetida do veículo deslocou a agulha.")
		_check(canvas.call("_tracking_pin_visual_geometry", repeated_overlap_position, true) == normal_pin_geometry, "Seleção repetida do veículo alterou sua geometria.")
		_check(canvas.call("_tracking_visual_groups") == tracking_groups_before_selection, "Seleção repetida do veículo alterou a composição dos grupos.")
		_check(canvas.current_map_view() == tracking_view_before_selection, "Seleção repetida do veículo alterou câmera ou zoom.")
		_check(canvas.drag_offset == tracking_drag_before_selection, "Seleção repetida do veículo alterou o offset.")
		_check(canvas.map_view_revision == tracking_revision_before_selection, "Seleção repetida do veículo alterou a revisão do mapa.")
		_check(int(canvas.call("_nearest_tracking_index", repeated_overlap_position)) == 0, "Seleção repetida alterou o hit-test do veículo.")
	var canvas_source := FileAccess.get_file_as_string("res://src/features/big_map/big_map_canvas.gd")
	var draw_start := canvas_source.find("func _draw() -> void:")
	var draw_end := canvas_source.find("func _draw_loading_state()", draw_start)
	var draw_body := canvas_source.substr(draw_start, draw_end - draw_start)
	var erb_draw_order := draw_body.find("_draw_station_marker(")
	var tracking_draw_order := draw_body.find("_draw_tracking_group(group)")
	var selected_tracking_draw_order := draw_body.find("_draw_tracking_group(selected_tracking_group)")
	var selected_label_draw_order := draw_body.find("_draw_tracking_group_label(selected_tracking_group)")
	_check(erb_draw_order >= 0 and erb_draw_order < tracking_draw_order, "ERB ainda é desenhada acima dos veículos.")
	_check(tracking_draw_order < selected_tracking_draw_order, "Veículo selecionado não é o último veículo desenhado.")
	_check(selected_tracking_draw_order < selected_label_draw_order, "Etiqueta selecionada não ocupa o último passe geográfico.")
	var station_draw_start := canvas_source.find("func _draw_station_marker(")
	var station_draw_end := canvas_source.find("func _station_marker_draw_size(", station_draw_start)
	var station_draw_body := canvas_source.substr(station_draw_start, station_draw_end - station_draw_start)
	var station_selected_start := station_draw_body.find("\tif selected:")
	var station_selected_end := station_draw_body.find("\tvar marker_rect", station_selected_start)
	var station_selected_branch := station_draw_body.substr(station_selected_start, station_selected_end - station_selected_start)
	_check(station_selected_branch.contains("draw_arc"), "Seleção da ERB perdeu o contorno azul.")
	_check(not station_selected_branch.contains("draw_circle"), "Seleção da ERB ainda acrescenta preenchimento que aumenta o marcador.")
	_check(not station_draw_body.contains("if selected or _display_map_zoom()"), "Seleção da ERB ainda força etiqueta fora do zoom normal.")
	var pin_draw_start := canvas_source.find("func _draw_tracking_pin(")
	var pin_draw_end := canvas_source.find("func _tracking_pin_draw_size(", pin_draw_start)
	var pin_draw_body := canvas_source.substr(pin_draw_start, pin_draw_end - pin_draw_start)
	var pin_selected_start := pin_draw_body.find("\tif selected:")
	var pin_selected_end := pin_draw_body.find("\tdraw_texture_rect", pin_selected_start)
	var pin_selected_branch := pin_draw_body.substr(pin_selected_start, pin_selected_end - pin_selected_start)
	_check(pin_selected_branch.contains("draw_arc"), "Seleção do veículo perdeu o contorno azul.")
	_check(not pin_selected_branch.contains("draw_circle"), "Seleção do veículo ainda acrescenta preenchimento que aumenta a agulha.")
	canvas.set_coverage_profile({"stations": [{"id": "SYN-ERB", "lat": -5.5260, "lng": -47.4920, "operator": "TIM", "generation": "4G"}]})

	await dashboard.call("_load_smart_4g_map_tiles", canvas, [], "all", initial_view)
	var repeated_state: Dictionary = dashboard.call("_smart_4g_tile_cache_state")
	_check(int(repeated_state.get("network_requests", 0)) == first_network, "Viewport idêntico baixou tiles novamente.")
	_check(int(repeated_state.get("decodes", 0)) == first_decodes, "Viewport idêntico decodificou tiles novamente.")
	_check(int(repeated_state.get("cache_hits", 0)) >= first_visible, "Viewport idêntico não registrou reutilização do cache.")
	_check(canvas.last_map_view_reused_tile_count == first_visible, "Canvas não preservou as texturas já visíveis.")
	_check(canvas.tracking_locations.size() == 1 and canvas.stations.size() == 1, "Reuso de tiles reconstruiu as camadas de veículo/ERB.")

	var shifted_view := _view(Config.DEFAULT_LATITUDE, Config.DEFAULT_LONGITUDE + 0.05, Config.DEFAULT_ZOOM)
	await dashboard.call("_load_smart_4g_map_tiles", canvas, [], "all", shifted_view)
	var shifted_state: Dictionary = dashboard.call("_smart_4g_tile_cache_state")
	var shifted_delta := int(shifted_state.get("network_requests", 0)) - first_network
	_check(shifted_delta > 0, "Troca real de viewport não solicitou os novos blocos.")
	_check(shifted_delta < canvas.visible_map_tiles.size(), "Troca de viewport baixou novamente todos os blocos.")
	_check(canvas.last_map_view_reused_tile_count > 0, "Troca de viewport não reutilizou a área sobreposta.")

	await dashboard.call("_load_smart_4g_map_tiles", canvas, [], "all", initial_view)
	var returned_state: Dictionary = dashboard.call("_smart_4g_tile_cache_state")
	_check(int(returned_state.get("network_requests", 0)) == int(shifted_state.get("network_requests", 0)), "Retorno ao viewport anterior ignorou o cache.")

	var zoomed_view := _view(Config.DEFAULT_LATITUDE, Config.DEFAULT_LONGITUDE, Config.DEFAULT_ZOOM + 1)
	await dashboard.call("_load_smart_4g_map_tiles", canvas, [], "all", zoomed_view)
	var zoomed_state: Dictionary = dashboard.call("_smart_4g_tile_cache_state")
	_check(int(zoomed_state.get("network_requests", 0)) > int(returned_state.get("network_requests", 0)), "Novo zoom não solicitou sua grade de tiles.")
	_check(canvas.tracking_locations.size() == 1 and canvas.stations.size() == 1, "Zoom reconstruiu as camadas de veículo/ERB.")
	_check(int(zoomed_state.get("entries", 0)) <= int(zoomed_state.get("max_entries", 0)), "Cache ultrapassou seu limite.")
	_test_station_projection_cache(canvas)
	var continuous_state := await _test_continuous_navigation(dashboard, canvas)
	var lru_state := await _test_lru_eviction(dashboard)

	canvas.visible_map_tiles.clear()
	canvas.set_tracking_locations([])
	canvas.set_coverage_profile({"stations": [], "metadata": {}})
	dashboard.smart_4g_tile_texture_cache.clear()
	dashboard.smart_4g_tile_cache.clear()
	dashboard.smart_4g_tile_cache_order.clear()
	dashboard.remove_child(canvas)
	canvas.free()
	root.remove_child(dashboard)
	dashboard.free()
	await process_frame

	if failures.is_empty():
		print("BIG_MAP_INCREMENTAL_TILE_TEST: OK network=%d hits=%d cache_entries=%d cancelled=%d first_tile_ms=%d load_ms=%d lru_hits=%d lru_evictions=%d" % [
			int(zoomed_state.get("network_requests", 0)),
			int(zoomed_state.get("cache_hits", 0)),
			int(zoomed_state.get("entries", 0)),
			int(continuous_state.get("cancelled_loads", 0)),
			int(continuous_state.get("last_first_tile_msec", -1)),
			int(continuous_state.get("last_load_msec", -1)),
			int(lru_state.get("cache_hits", 0)),
			int(lru_state.get("evictions", 0)),
		])
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _test_continuous_navigation(dashboard: Node, canvas: Control) -> Dictionary:
	var navigation_requests: Array[Dictionary] = []
	canvas.navigation_requested.connect(func(latitude: float, longitude: float, zoom: int) -> void:
		navigation_requests.append({"lat": latitude, "lng": longitude, "zoom": zoom})
	)
	var start_zoom := int(canvas.call("_display_map_zoom"))
	canvas.call("_request_zoom", canvas.size * 0.5, 1)
	canvas.call("_request_zoom", canvas.size * 0.5, 1)
	canvas.call("_request_zoom", canvas.size * 0.5, 1)
	_check(int(canvas.navigation_target_zoom) == mini(start_zoom + 3, canvas.MAX_MAP_ZOOM), "Três zoom-ins rápidos não acumularam +3.")
	_check(int(navigation_requests.back().get("zoom", -1)) == int(canvas.navigation_target_zoom), "Último sinal de zoom não representa a câmera desejada.")
	var target_before_pan: Vector2 = canvas.navigation_target_top_left
	canvas.drag_offset = Vector2(24.0, 10.0)
	canvas.call("_request_pan_navigation")
	var target_after_first_pan: Vector2 = canvas.navigation_target_top_left
	canvas.drag_offset = Vector2(16.0, -6.0)
	canvas.call("_request_pan_navigation")
	var target_after_second_pan: Vector2 = canvas.navigation_target_top_left
	_check(navigation_requests.size() == 5, "Gestos de pan/zoom foram descartados durante carregamento.")
	_check(target_after_first_pan != target_before_pan and target_after_second_pan != target_after_first_pan, "Pans pendentes não alteraram cumulativamente a câmera desejada.")
	_check(is_zero_approx(canvas.drag_offset.length()), "Offset transitório não foi incorporado à câmera desejada.")
	canvas.cancel_navigation_load("")

	var previous_revision := int(canvas.map_view_revision)
	var previous_tiles: Dictionary = canvas.visible_map_tiles.duplicate()
	var previous_layers := Vector2i(canvas.tracking_locations.size(), canvas.stations.size())
	var profile_calls_before := int(dashboard.offline_profile_build_calls)
	dashboard.offline_http_delay_msec = 90
	var http_calls_before := int(dashboard.offline_http_calls)
	var superseded_view := _view(Config.DEFAULT_LATITUDE, Config.DEFAULT_LONGITUDE + 0.12, Config.DEFAULT_ZOOM + 2)
	dashboard.call_deferred("_load_smart_4g_map_tiles", canvas, [], "all", superseded_view, true)
	for _frame in range(60):
		await process_frame
		if int(dashboard.offline_http_calls) > http_calls_before:
			break
	_check(int(canvas.map_view_revision) == previous_revision, "Nova grade apagou o mapa antes do primeiro tile.")
	_check(canvas.visible_map_tiles.size() == previous_tiles.size(), "Tiles anteriores sumiram durante a carga progressiva.")

	var winning_view := _view(Config.DEFAULT_LATITUDE + 0.08, Config.DEFAULT_LONGITUDE - 0.08, Config.DEFAULT_ZOOM + 3)
	await dashboard.call("_load_smart_4g_map_tiles", canvas, [], "all", winning_view, true)
	await create_timer(0.15).timeout
	dashboard.offline_http_delay_msec = 0
	var state: Dictionary = dashboard.call("_smart_4g_tile_cache_state")
	_check(int(canvas.map_zoom) == Config.DEFAULT_ZOOM + 3, "Carga obsoleta venceu o último zoom solicitado.")
	_check(int(state.get("cancelled_loads", 0)) >= 1, "Carga obsoleta não foi contabilizada/ignorada.")
	_check(int(state.get("cancelled_http", 0)) >= 1, "HTTP obsoleto não foi cancelado durante a rajada.")
	_check(int(state.get("last_first_tile_msec", -1)) >= 0, "Latência até o primeiro tile não foi medida.")
	_check(int(state.get("last_load_msec", -1)) >= int(state.get("last_first_tile_msec", -1)), "Métrica total é menor que a latência do primeiro tile.")
	_check(int(state.get("last_missing_tiles", 0)) > 0, "Teste contínuo não exercitou tiles ausentes.")
	_check(int(dashboard.offline_profile_build_calls) == profile_calls_before, "Mapa Grande ainda calculou o perfil regional legado.")
	_check(Vector2i(canvas.tracking_locations.size(), canvas.stations.size()) == previous_layers, "Pan/zoom contínuo reconstruiu veículos ou ERBs.")
	return await _test_partial_tile_fallback(dashboard, canvas, previous_layers)


func _test_partial_tile_fallback(dashboard: Node, canvas: Control, previous_layers: Vector2i) -> Dictionary:
	dashboard.offline_fail_every = 3
	var redraws_before := int(canvas.progressive_redraw_count)
	var partial_view := _view(Config.DEFAULT_LATITUDE - 0.11, Config.DEFAULT_LONGITUDE + 0.11, Config.DEFAULT_ZOOM + 4)
	await dashboard.call("_load_smart_4g_map_tiles", canvas, [], "all", partial_view, true)
	_check(canvas.map_tile_loaded_count < canvas.map_tile_total_count, "Fixture de falha parcial não deixou lacunas controladas.")
	_check(not canvas.fallback_map_tiles.is_empty(), "Fallback foi removido apesar de tiles faltantes.")
	_check(Vector2i(canvas.tracking_locations.size(), canvas.stations.size()) == previous_layers, "Falha parcial reconstruiu veículos ou ERBs.")
	dashboard.offline_fail_every = 0
	await dashboard.call("_load_smart_4g_map_tiles", canvas, [], "all", partial_view, true)
	_check(canvas.map_tile_loaded_count == canvas.map_tile_total_count, "Recuperação não completou a grade parcial.")
	_check(canvas.fallback_map_tiles.is_empty(), "Fallback não foi liberado após cobertura completa.")
	var redraw_delta := int(canvas.progressive_redraw_count) - redraws_before
	_check(redraw_delta <= canvas.map_tile_total_count * 2 + 4, "Progresso gerou redraws redundantes além dos tiles.")
	return dashboard.call("_smart_4g_tile_cache_state") as Dictionary


func _test_station_projection_cache(canvas: Control) -> void:
	var synthetic_stations: Array[Dictionary] = []
	for index in range(365):
		synthetic_stations.append({
			"id": "ERB-SYN-%d" % index,
			"lat": Config.DEFAULT_LATITUDE + float(index % 19) * 0.0002,
			"lng": Config.DEFAULT_LONGITUDE + float(index / 19) * 0.0002,
			"operator": "TIM",
			"generation": "4G",
		})
	canvas.set_coverage_profile({"stations": synthetic_stations})
	canvas.call("_station_visual_positions")
	canvas.call("_station_visual_groups")
	var position_rebuilds := int(canvas.station_position_rebuild_count)
	var group_rebuilds := int(canvas.station_group_rebuild_count)
	canvas.drag_offset = Vector2(37.0, -19.0)
	canvas.call("_station_visual_positions")
	canvas.call("_station_visual_groups")
	_check(int(canvas.station_position_rebuild_count) == position_rebuilds, "Drag recalculou 365 projeções de ERB.")
	_check(int(canvas.station_group_rebuild_count) == group_rebuilds, "Drag reagrupou 365 ERBs.")
	canvas.drag_offset = Vector2.ZERO


func _test_redraw_coalescing(dashboard: Node, canvas: Control) -> void:
	var texture_values: Array = dashboard.smart_4g_tile_texture_cache.values()
	_check(not texture_values.is_empty(), "Fixture não possui textura para provar redraw coalescido.")
	if texture_values.is_empty():
		return
	var texture := texture_values[0] as Texture2D
	var previous_tiles: Dictionary = canvas.visible_map_tiles.duplicate(true)
	var previous_loaded := int(canvas.map_tile_loaded_count)
	var previous_total := int(canvas.map_tile_total_count)
	var flushes_before := int(canvas.progressive_redraw_count)
	for index in range(20):
		canvas.set_map_tile("REDRAW/%d" % index, index, 0, texture)
		canvas.set_map_tile_progress(index + 1, 20, "Rajada offline")
	await process_frame
	_check(int(canvas.progressive_redraw_count) - flushes_before == 1, "Callbacks de tile/progresso no mesmo frame geraram mais de um flush.")
	canvas.visible_map_tiles = previous_tiles
	canvas.map_tile_loaded_count = previous_loaded
	canvas.map_tile_total_count = previous_total
	canvas.navigation_loading = false
	canvas.set_process(false)


func _test_lru_eviction(dashboard: Node) -> Dictionary:
	dashboard.smart_4g_tile_texture_cache.clear()
	dashboard.smart_4g_tile_cache.clear()
	dashboard.smart_4g_tile_cache_order.clear()
	dashboard.smart_4g_tile_network_request_count = 0
	dashboard.smart_4g_tile_cache_hit_count = 0
	dashboard.smart_4g_tile_decode_count = 0
	dashboard.smart_4g_tile_cache_eviction_count = 0

	var empty_state: Dictionary = dashboard.call("_smart_4g_tile_cache_state")
	var max_entries := int(empty_state.get("max_entries", 0))
	_check(max_entries == 160, "Fixture LRU não exercitou o limite declarado de 160 entradas.")
	var keys: Array[String] = []
	for tile_x in range(max_entries):
		var response: Dictionary = await dashboard.call(
			"_smart_4g_osm_tile_bytes",
			10,
			tile_x,
			1,
			Config.DEFAULT_BASEMAP
		)
		_check(bool(response.get("ok", false)), "Fixture LRU falhou ao preencher o cache offline.")
		var cache_key := TileProvider.cache_key(10, tile_x, 1, Config.DEFAULT_BASEMAP)
		keys.append(cache_key)
		var texture := dashboard.call(
			"_smart_4g_osm_tile_texture",
			cache_key,
			response.get("bytes", PackedByteArray())
		) as Texture2D
		_check(texture != null, "Fixture LRU não preencheu o cache de texturas.")

	var hot_bytes_key := keys[0]
	var least_recent_after_bytes_hit := keys[1]
	var hot_response: Dictionary = await dashboard.call(
		"_smart_4g_osm_tile_bytes",
		10,
		0,
		1,
		Config.DEFAULT_BASEMAP
	)
	_check(bool(hot_response.get("ok", false)), "Hit da chave quente de bytes falhou.")
	var first_new_key := TileProvider.cache_key(10, max_entries, 1, Config.DEFAULT_BASEMAP)
	var first_new_response: Dictionary = await dashboard.call(
		"_smart_4g_osm_tile_bytes",
		10,
		max_entries,
		1,
		Config.DEFAULT_BASEMAP
	)
	dashboard.call(
		"_smart_4g_osm_tile_texture",
		first_new_key,
		first_new_response.get("bytes", PackedByteArray())
	)
	_check(dashboard.smart_4g_tile_cache.has(hot_bytes_key), "LRU removeu a chave de bytes recém-acessada.")
	_check(not dashboard.smart_4g_tile_cache.has(least_recent_after_bytes_hit), "LRU não removeu a chave de bytes realmente menos recente.")
	_check(dashboard.smart_4g_tile_texture_cache.has(hot_bytes_key), "Evicção de bytes removeu a textura da chave quente.")
	_check(not dashboard.smart_4g_tile_texture_cache.has(least_recent_after_bytes_hit), "Textura da chave expirada permaneceu no cache.")

	var hot_texture_key := keys[2]
	var least_recent_after_texture_hit := keys[3]
	var texture_decode_count_before: int = int(dashboard.smart_4g_tile_decode_count)
	var hot_texture := dashboard.call(
		"_smart_4g_osm_tile_texture",
		hot_texture_key,
		dashboard.smart_4g_tile_cache.get(hot_texture_key, PackedByteArray())
	) as Texture2D
	_check(hot_texture != null, "Hit da chave quente de textura falhou.")
	_check(dashboard.smart_4g_tile_decode_count == texture_decode_count_before, "Hit de textura decodificou o tile novamente.")
	var second_new_key := TileProvider.cache_key(10, max_entries + 1, 1, Config.DEFAULT_BASEMAP)
	var second_new_response: Dictionary = await dashboard.call(
		"_smart_4g_osm_tile_bytes",
		10,
		max_entries + 1,
		1,
		Config.DEFAULT_BASEMAP
	)
	dashboard.call(
		"_smart_4g_osm_tile_texture",
		second_new_key,
		second_new_response.get("bytes", PackedByteArray())
	)
	_check(dashboard.smart_4g_tile_cache.has(hot_texture_key), "LRU removeu a chave de textura recém-acessada.")
	_check(not dashboard.smart_4g_tile_cache.has(least_recent_after_texture_hit), "LRU não removeu a chave realmente menos recente após hit de textura.")
	_check(dashboard.smart_4g_tile_texture_cache.has(hot_texture_key), "Textura quente não sobreviveu à evicção LRU.")
	_check(not dashboard.smart_4g_tile_texture_cache.has(least_recent_after_texture_hit), "Textura menos recente não foi removida.")

	var final_state: Dictionary = dashboard.call("_smart_4g_tile_cache_state")
	var unique_keys := {}
	for cache_key in dashboard.smart_4g_tile_cache_order:
		unique_keys[cache_key] = true
	_check(int(final_state.get("entries", 0)) == max_entries, "Cache LRU não respeitou o limite após evicções.")
	_check(int(final_state.get("texture_entries", 0)) == max_entries, "Cache de texturas divergiu do cache de bytes.")
	_check(dashboard.smart_4g_tile_cache_order.size() == max_entries, "Fila LRU divergiu da quantidade de entradas.")
	_check(unique_keys.size() == max_entries, "Fila LRU contém chaves duplicadas.")
	_check(dashboard.smart_4g_tile_cache_order[max_entries - 2] == hot_texture_key, "Hit de textura não atualizou a recência da chave.")
	_check(dashboard.smart_4g_tile_cache_order.back() == second_new_key, "Nova entrada não ficou no fim da fila LRU.")
	_check(int(final_state.get("network_requests", 0)) == max_entries + 2, "Métrica de rede do teste LRU divergiu.")
	_check(int(final_state.get("cache_hits", 0)) == 1, "Métrica de hits de bytes do teste LRU divergiu.")
	_check(int(final_state.get("evictions", 0)) == 2, "Métrica de evicções do teste LRU divergiu.")
	_check(int(final_state.get("orphan_textures", -1)) == 0, "LRU deixou textura órfã sem bytes correspondentes.")
	return final_state


func _view(latitude: float, longitude: float, zoom: int) -> Dictionary:
	return {
		"center": {"lat": latitude, "lng": longitude},
		"zoom": zoom,
		"basemap": Config.DEFAULT_BASEMAP,
		"interactive": true,
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
