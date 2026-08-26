## Janela isolada do estado inicial do Mapa Grande: zero veículos, tiles reais
## e ERBs derivadas do catálogo oficial auditado da Anatel.
extends SceneTree

const TrackingView := preload("res://src/features/big_map/big_map_tracking_view.gd")
const Config := preload("res://src/features/big_map/big_map_config.gd")
const MapProjection := preload("res://src/features/big_map/map_projection.gd")
const TileProvider := preload("res://src/features/big_map/map_tile_provider.gd")
const NationalIndex := preload("res://src/features/big_map/anatel_national_index.gd")

const TEST_LAT := -5.5264
const TEST_LNG := -47.4919
const TEST_ZOOM := 13

var view: VBoxContainer
var canvas: Control
var anatel: RefCounted
var anatel_metadata: Dictionary = {}
var area_stations: Array[Dictionary] = []
var load_generation := 0
var visual_tile_cache: Dictionary = {}
var visual_tile_network_requests := 0
var visual_tile_cache_hits := 0
var visual_tile_cancelled_requests := 0
var visual_decode_max_msec := 0
var headless_first_network_requests := -1
var isolated_query_feedback_ok := false
var initial_zoom := TEST_ZOOM
var capture_path := ""
var capture_size := Vector2i(1600, 940)


func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--zoom="):
			initial_zoom = clampi(int(argument.trim_prefix("--zoom=")), Config.MIN_ZOOM, Config.MAX_ZOOM)
		elif argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--size="):
			var dimensions := argument.trim_prefix("--size=").split("x", false)
			if dimensions.size() == 2:
				capture_size = Vector2i(maxi(960, int(dimensions[0])), maxi(640, int(dimensions[1])))
	call_deferred("_build_window")


func _build_window() -> void:
	DisplayServer.window_set_title("Mapa Grande — validação operacional · zoom %d" % initial_zoom)
	DisplayServer.window_set_size(capture_size)
	var background := ColorRect.new()
	background.color = Color("#edf3f7")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	root.add_child(margin)
	view = TrackingView.new()
	margin.add_child(view)
	canvas = view.map_canvas
	view.query_input.text = ""
	view.set_metrics({"Total": 0, "Com posição": 0, "Em movimento": 0, "Parados": 0, "Desatualizados": 0, "Sem posição": 0})
	view.set_runtime("Carregando mapa operacional...", Color("#e89a18"), "OpenStreetMap · ERBs oficiais Anatel", "Carregando catálogo e tiles")
	_load_official_catalog()
	view.refresh_button.pressed.connect(_reload_test)
	view.add_button.pressed.connect(_on_isolated_query_requested)
	view.query_input.text_submitted.connect(func(_value: String) -> void: _on_isolated_query_requested())
	view.list_toggle.pressed.connect(func() -> void: view.set_list_expanded(not view.list_panel.visible))
	view.erb_layer_check.toggled.connect(func(enabled: bool) -> void: canvas.set_station_visibility(enabled))
	view.camera_lock_check.toggled.connect(func(_enabled: bool) -> void: _reload_test())
	for filter in [view.erb_operator_select, view.erb_generation_select, view.erb_city_select, view.erb_status_select]:
		(filter as OptionButton).item_selected.connect(func(_index: int) -> void: _apply_station_filters())
	canvas.navigation_requested.connect(_on_navigation)
	canvas.reset_requested.connect(func() -> void: _load_area(TEST_LAT, TEST_LNG, initial_zoom))
	canvas.tracking_selected.connect(_show_vehicle)
	canvas.station_selected.connect(_show_station)
	_show_empty_details()
	if DisplayServer.get_name() == "headless":
		isolated_query_feedback_ok = _verify_isolated_query_feedback()
	call_deferred("_load_area", TEST_LAT, TEST_LNG, initial_zoom)


func _on_isolated_query_requested() -> void:
	if view.query_input.text.strip_edges().is_empty():
		view.set_query_state("error", "Informe uma placa, número de série ou cliente")
		return
	view.set_query_state("error", "Pesquisa online indisponível nesta janela isolada sem sessão autorizada")


func _verify_isolated_query_feedback() -> bool:
	view.query_input.text = ""
	view.add_button.pressed.emit()
	var empty_feedback: bool = view.query_state_label.text.contains("Informe uma placa")
	view.query_input.text = "CONSULTA-TESTE"
	view.add_button.pressed.emit()
	var click_feedback: bool = view.query_state_label.text.contains("indisponível nesta janela isolada")
	view.query_input.text = "CONSULTA-ENTER"
	view.query_input.text_submitted.emit(view.query_input.text)
	var enter_feedback: bool = view.query_state_label.text.contains("indisponível nesta janela isolada")
	view.query_input.text = ""
	view.set_query_state("idle")
	return empty_feedback and click_feedback and enter_feedback


func _load_official_catalog() -> void:
	anatel = NationalIndex.new()
	var loaded: Dictionary = anatel.call("load_manifest")
	if not bool(loaded.get("ok", false)):
		view.set_erb_source("ERBs: %s" % str(loaded.get("message", "fonte indisponível")), "A camada permanece vazia sem dados oficiais verificáveis.", Color("#dc3f4b"))
		return
	anatel_metadata = (loaded.get("metadata", {}) as Dictionary).duplicate(true)
	anatel_metadata["manifest_sha256"] = str(loaded.get("manifest_sha256", ""))
	view.set_erb_source(
		"Anatel SMP · Brasil · %s registros estação/geração" % str(anatel_metadata.get("unique_station_generations", "não informado")),
		"Licenciamento/presença de ERB não representa intensidade de sinal em tempo real.",
		Color("#11a86d")
	)
	view.erb_source_label.tooltip_text = "%s\nSHA-256 ZIP: %s\nSHA-256 índice: %s" % [anatel_metadata.get("source_url", ""), anatel_metadata.get("source_zip_sha256", ""), anatel_metadata.get("index_content_sha256", "")]


func _reload_test() -> void:
	var current: Dictionary = canvas.current_map_view()
	var center: Dictionary = current.get("center", {"lat": TEST_LAT, "lng": TEST_LNG})
	_load_area(float(center.get("lat", TEST_LAT)), float(center.get("lng", TEST_LNG)), int(current.get("zoom", TEST_ZOOM)))


func _on_navigation(latitude: float, longitude: float, zoom: int) -> void:
	call_deferred("_load_area", latitude, longitude, zoom)


func _load_area(latitude: float, longitude: float, zoom: int) -> void:
	load_generation += 1
	var current_generation := load_generation
	var preserve_current_map: bool = bool(canvas.map_ready)
	var canvas_generation: int = int(canvas.begin_map_load("Atualizando mapa OpenStreetMap...", preserve_current_map))
	await process_frame
	await process_frame
	if preserve_current_map:
		await create_timer(0.075).timeout
	if current_generation != load_generation or not canvas.is_load_current(canvas_generation):
		return
	var load_started_msec := Time.get_ticks_msec()
	var viewport_size := Vector2i(maxi(900, roundi(canvas.size.x)), maxi(500, roundi(canvas.size.y)))
	var safe_zoom := clampi(zoom, Config.MIN_ZOOM, Config.MAX_ZOOM)
	var center_world := MapProjection.lat_lng_to_world_pixel(latitude, longitude, safe_zoom)
	var top_left := Vector2i(roundi(center_world.x - viewport_size.x * 0.5), roundi(center_world.y - viewport_size.y * 0.5))
	var first_tile := Vector2i(floori(top_left.x / 256.0), floori(top_left.y / 256.0))
	var last_tile := Vector2i(floori((top_left.x + viewport_size.x - 1) / 256.0), floori((top_left.y + viewport_size.y - 1) / 256.0))
	var max_tile := 1 << safe_zoom
	var basemap := str(canvas.basemap_id)
	var entries: Array[Dictionary] = []
	var missing_entries: Array[Dictionary] = []
	var loaded_tiles := 0
	for tile_y in range(first_tile.y, last_tile.y + 1):
		for tile_x in range(first_tile.x, last_tile.x + 1):
			if tile_y < 0 or tile_y >= max_tile:
				continue
			var entry := {"key": TileProvider.cache_key(safe_zoom, posmod(tile_x, max_tile), tile_y, basemap), "x": tile_x, "y": tile_y}
			var cached_texture: Texture2D = visual_tile_cache.get(str(entry.key)) as Texture2D
			if cached_texture != null:
				entry["texture"] = cached_texture
				loaded_tiles += 1
				visual_tile_cache_hits += 1
			else:
				missing_entries.append(entry)
			entries.append(entry)
	var view_started: bool = not preserve_current_map or loaded_tiles > 0
	if view_started:
		canvas.set_map_view(entries, safe_zoom, Vector2(top_left), Vector2(viewport_size), loaded_tiles, entries.size())
	canvas.set_map_tile_progress(loaded_tiles, entries.size(), "Mapa %d/%d tiles" % [loaded_tiles, entries.size()])
	var tile_state := {
		"next_index": 0,
		"active": mini(4, missing_entries.size()),
		"loaded": loaded_tiles,
		"new_tiles": 0,
		"view_started": view_started,
		"first_tile_msec": Time.get_ticks_msec() - load_started_msec if loaded_tiles > 0 else -1,
	}
	for _worker_index in range(int(tile_state.get("active", 0))):
		call_deferred(
			"_visual_tile_worker",
			missing_entries,
			entries,
			safe_zoom,
			max_tile,
			basemap,
			Vector2(top_left),
			Vector2(viewport_size),
			current_generation,
			canvas_generation,
			load_started_msec,
			tile_state
		)
	var frame_intervals: Array[float] = []
	var last_frame_usec := Time.get_ticks_usec()
	while int(tile_state.get("active", 0)) > 0:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		frame_intervals.append(float(now_usec - last_frame_usec) / 1000.0)
		last_frame_usec = now_usec
	if current_generation != load_generation or not canvas.is_load_current(canvas_generation):
		return
	loaded_tiles = int(tile_state.get("loaded", loaded_tiles))
	var new_tiles := int(tile_state.get("new_tiles", 0))
	canvas.finish_map_tile_load(loaded_tiles, entries.size())
	await create_timer(0.075).timeout
	if current_generation != load_generation:
		return
	await _refresh_official_area_stations(Vector2(top_left), Vector2(viewport_size), safe_zoom, current_generation)
	if current_generation != load_generation:
		return
	canvas.set_tracking_mode(true)
	var empty_locations: Array[Dictionary] = []
	canvas.set_tracking_locations(empty_locations)
	canvas.set_station_visibility(view.erb_layer_check.button_pressed)
	view.set_runtime(
		"0 veículos · %d ERBs oficiais visíveis" % canvas.stations.size(),
		Color("#11a86d"),
		"OpenStreetMap real · camada Anatel independente",
		"Tiles %d/%d · novos %d · cache %d" % [loaded_tiles, entries.size(), new_tiles, entries.size() - new_tiles]
	)
	print("BIG_MAP_REBUILD_VISUAL_TEST: osm_tiles=%d/%d new=%d cache_hits=%d network=%d cancelled_http=%d first_tile_ms=%d total_ms=%d frame_p50_ms=%.3f frame_p95_ms=%.3f frame_max_ms=%.3f decode_max_ms=%d vehicles=%d official_stations=%d provenance=%s navigation_loading=%s" % [loaded_tiles, entries.size(), new_tiles, visual_tile_cache_hits, visual_tile_network_requests, visual_tile_cancelled_requests, int(tile_state.get("first_tile_msec", -1)), Time.get_ticks_msec() - load_started_msec, _percentile(frame_intervals, 0.50), _percentile(frame_intervals, 0.95), _percentile(frame_intervals, 1.0), visual_decode_max_msec, canvas.tracking_locations.size(), canvas.stations.size(), str(anatel_metadata.has("source_zip_sha256")), str(canvas.navigation_loading)])
	if capture_path != "":
		await process_frame
		await process_frame
		var capture_image := root.get_texture().get_image()
		var capture_error := capture_image.save_png(capture_path)
		var capture_ok: bool = capture_error == OK and loaded_tiles > 0 and canvas.tracking_locations.is_empty() and canvas.stations.size() > 0
		print("BIG_MAP_REBUILD_CAPTURE: zoom=%d size=%dx%d path=%s ok=%s" % [safe_zoom, capture_size.x, capture_size.y, capture_path, str(capture_ok)])
		quit(0 if capture_ok else 1)
		return
	if DisplayServer.get_name() == "headless":
		if headless_first_network_requests < 0:
			headless_first_network_requests = visual_tile_network_requests
			call_deferred("_load_area", latitude, longitude, safe_zoom)
			return
		var cache_reused := new_tiles == 0 \
			and visual_tile_network_requests == headless_first_network_requests \
			and visual_tile_cache_hits >= entries.size()
		print("BIG_MAP_REBUILD_VISUAL_CACHE: repeated_view_network_delta=%d reused=%d ok=%s" % [
			visual_tile_network_requests - headless_first_network_requests,
			visual_tile_cache_hits,
			str(cache_reused),
		])
		print("BIG_MAP_REBUILD_QUERY_FEEDBACK: empty_click_enter=%s" % str(isolated_query_feedback_ok))
		quit(0 if loaded_tiles > 0 and canvas.tracking_locations.is_empty() and canvas.stations.size() > 0 and anatel_metadata.has("source_zip_sha256") and not canvas.navigation_loading and cache_reused and isolated_query_feedback_ok else 1)


func _visual_tile_worker(
	missing_entries: Array[Dictionary],
	entries: Array[Dictionary],
	zoom: int,
	max_tile: int,
	basemap: String,
	top_left: Vector2,
	viewport_size: Vector2,
	current_generation: int,
	canvas_generation: int,
	load_started_msec: int,
	state: Dictionary
) -> void:
	while true:
		if current_generation != load_generation or not canvas.is_load_current(canvas_generation):
			state["active"] = maxi(int(state.get("active", 1)) - 1, 0)
			return
		var index := int(state.get("next_index", 0))
		state["next_index"] = index + 1
		if index >= missing_entries.size():
			state["active"] = maxi(int(state.get("active", 1)) - 1, 0)
			return
		var entry := missing_entries[index]
		var bytes := await _download_tile(zoom, posmod(int(entry.x), max_tile), int(entry.y), basemap, current_generation)
		if current_generation != load_generation or not canvas.is_load_current(canvas_generation):
			state["active"] = maxi(int(state.get("active", 1)) - 1, 0)
			return
		var decode_started := Time.get_ticks_msec()
		var decode_state := {}
		var task_id := WorkerThreadPool.add_task(
			Callable(self, "_decode_visual_tile_to").bind(bytes, decode_state),
			true,
			"Janela Mapa Grande: decodificar tile OSM"
		)
		while not WorkerThreadPool.is_task_completed(task_id):
			await process_frame
		WorkerThreadPool.wait_for_task_completion(task_id)
		visual_decode_max_msec = maxi(visual_decode_max_msec, Time.get_ticks_msec() - decode_started)
		if current_generation != load_generation or not canvas.is_load_current(canvas_generation):
			state["active"] = maxi(int(state.get("active", 1)) - 1, 0)
			return
		var texture := TileProvider.texture_from_image(decode_state.get("image") as Image)
		if texture == null:
			continue
		visual_tile_cache[str(entry.key)] = texture
		if not bool(state.get("view_started", false)):
			canvas.set_map_view(entries, zoom, top_left, viewport_size, 0, entries.size())
			state["view_started"] = true
			state["first_tile_msec"] = Time.get_ticks_msec() - load_started_msec
		canvas.set_map_tile(str(entry.key), int(entry.x), int(entry.y), texture)
		state["loaded"] = int(state.get("loaded", 0)) + 1
		state["new_tiles"] = int(state.get("new_tiles", 0)) + 1
		canvas.set_map_tile_progress(int(state.get("loaded", 0)), entries.size(), "Mapa %d/%d tiles" % [int(state.get("loaded", 0)), entries.size()])


func _decode_visual_tile_to(bytes: PackedByteArray, result_target: Dictionary) -> void:
	result_target["image"] = TileProvider.image_from_bytes(bytes)


func _refresh_official_area_stations(top_left: Vector2, viewport_size: Vector2, zoom: int, current_generation: int) -> void:
	if anatel == null:
		_apply_station_filters()
		return
	var north_west := MapProjection.world_pixel_to_lat_lng(top_left - Vector2(64, 64), zoom)
	var south_east := MapProjection.world_pixel_to_lat_lng(top_left + viewport_size + Vector2(64, 64), zoom)
	var query_state := {}
	var task_id := WorkerThreadPool.add_task(
		Callable(anatel, "query_viewport_threadsafe_to").bind({
		"min_lat": minf(north_west.x, south_east.x),
		"max_lat": maxf(north_west.x, south_east.x),
		"min_lng": minf(north_west.y, south_east.y),
		"max_lng": maxf(north_west.y, south_east.y),
		}, zoom, {}, query_state),
		true,
		"Janela Mapa Grande: consultar ERBs nacionais"
	)
	while not WorkerThreadPool.is_task_completed(task_id):
		await process_frame
	WorkerThreadPool.wait_for_task_completion(task_id)
	if current_generation != load_generation:
		return
	var result: Dictionary = query_state.get("result", {})
	if not bool(result.get("ok", false)):
		view.set_erb_source("ERBs: %s" % str(result.get("message", "falha no índice nacional")), "A camada permanece vazia sem dados oficiais verificáveis.", Color("#dc3f4b"))
		_apply_station_filters()
		return
	area_stations.clear()
	for raw_station in result.get("stations", []) as Array:
		if typeof(raw_station) == TYPE_DICTIONARY:
			area_stations.append((raw_station as Dictionary).duplicate(true))
	var operators: Array[String] = []
	var generations: Array[String] = []
	var cities: Array[String] = []
	var statuses: Array[String] = []
	for station in area_stations:
		_append_unique(operators, str(station.get("operator", "")))
		_append_unique(generations, str(station.get("generation", "")))
		_append_unique(cities, str(station.get("city", "")))
		_append_unique(statuses, str(station.get("status", "")))
	view.set_erb_filter_values(operators, generations, cities, statuses)
	_apply_station_filters()


func _append_unique(values: Array[String], value: String) -> void:
	var clean := value.strip_edges()
	if clean not in values:
		values.append(clean)


func _apply_station_filters() -> void:
	var filters: Dictionary = view.selected_erb_filters()
	var filtered: Array[Dictionary] = []
	for station in area_stations:
		var matches := true
		for field in ["operator", "generation", "city", "status"]:
			var expected := str(filters.get(field, ""))
			var actual := str(station.get(field, "")).strip_edges()
			if expected == "__missing__" and actual != "":
				matches = false
			elif expected not in ["", "__missing__"] and actual.casecmp_to(expected) != 0:
				matches = false
		if matches:
			filtered.append(station.duplicate(true))
	canvas.set_coverage_profile({"ok": true, "stations": filtered, "metadata": anatel_metadata})
	canvas.set_station_visibility(view.erb_layer_check.button_pressed)


func _download_tile(zoom: int, tile_x: int, tile_y: int, basemap: String, current_generation: int) -> PackedByteArray:
	visual_tile_network_requests += 1
	var request := HTTPRequest.new()
	root.add_child(request)
	var state := {"done": false, "result": HTTPRequest.RESULT_CONNECTION_ERROR, "code": 0, "bytes": PackedByteArray()}
	request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		state["done"] = true
		state["result"] = result
		state["code"] = response_code
		state["bytes"] = body
	)
	var start_error := request.request(TileProvider.tile_url(zoom, tile_x, tile_y, basemap), ["User-Agent: GrupoRSCentral/1.0"])
	if start_error != OK:
		request.queue_free()
		return PackedByteArray()
	while not bool(state.get("done", false)):
		await process_frame
		if current_generation != load_generation:
			request.cancel_request()
			request.queue_free()
			visual_tile_cancelled_requests += 1
			return PackedByteArray()
	request.queue_free()
	if int(state.get("result", HTTPRequest.RESULT_CONNECTION_ERROR)) != HTTPRequest.RESULT_SUCCESS or int(state.get("code", 0)) < 200 or int(state.get("code", 0)) >= 300:
		return PackedByteArray()
	return state.get("bytes", PackedByteArray()) as PackedByteArray


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(ceili(float(sorted.size()) * ratio) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _clear_details() -> void:
	for child in view.details_body.get_children():
		view.details_body.remove_child(child)
		child.queue_free()


func _show_empty_details() -> void:
	_clear_details()
	var label := Label.new()
	label.text = "Selecione um veículo ou uma ERB licenciada no mapa.\n\nUse arraste, zoom, filtros e a lista para navegar pelo recorte operacional."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("#64758a"))
	view.details_body.add_child(label)


func _show_vehicle(location: Dictionary) -> void:
	_clear_details()
	view.set_details_title("Veículo selecionado")
	canvas.select_station_by_id("")
	canvas.select_tracking_by_key(str(location.serial))
	for text in [str(location.plate), "Estado: " + str(location.communication_state), "Série: " + str(location.serial), "Cliente: " + str(location.client), "Coordenada: %.6f, %.6f" % [location.lat, location.lng]]:
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 17 if text == str(location.plate) else 12)
		view.details_body.add_child(label)


func _show_station(station: Dictionary) -> void:
	if station.is_empty():
		return
	_clear_details()
	view.set_details_title("ERB licenciada selecionada")
	canvas.clear_tracking_selection()
	for text in [
		"ERB " + _source_value(station.get("id", "")),
		"Prestadora: " + _source_value(station.get("provider_name", station.get("operator", ""))),
		"Tecnologia: " + _source_value(station.get("generation", "")),
		"Município/UF: %s / %s" % [_source_value(station.get("city", "")), _source_value(station.get("uf", ""))],
		"Situação: " + _source_value(station.get("status", "")),
		"Coordenada oficial: %.6f, %.6f" % [station.lat, station.lng],
	]:
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 16 if text.begins_with("ERB") else 12)
		view.details_body.add_child(label)


func _source_value(value: Variant) -> String:
	var clean := str(value).strip_edges()
	return clean if clean != "" else "Não informado pela fonte"
