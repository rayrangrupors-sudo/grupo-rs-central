## Janela isolada para validar OpenStreetMap, índice nacional e as três agulhas.
extends SceneTree

const MapCanvas := preload("res://src/features/big_map/big_map_canvas.gd")
const Config := preload("res://src/features/big_map/big_map_config.gd")
const MapProjection := preload("res://src/features/big_map/map_projection.gd")
const TileProvider := preload("res://src/features/big_map/map_tile_provider.gd")
const NationalIndex := preload("res://src/features/big_map/anatel_national_index.gd")

const DEMO_LAT := -5.5264
const DEMO_LNG := -47.4919
const DEMO_ZOOM := 13

var canvas: Control
var status_label: Label
var demo_load_generation := 0
var national_index: RefCounted
var national_metadata: Dictionary = {}


func _init() -> void:
	call_deferred("_build_window")


func _build_window() -> void:
	DisplayServer.window_set_title("Teste isolado — OpenStreetMap, ERBs Anatel e agulhas")
	DisplayServer.window_set_size(Vector2i(1440, 860))
	var host := Control.new()
	host.name = "MapVisualTest"
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_theme_constant_override("separation", 0)
	root.add_child(host)

	var background := ColorRect.new()
	background.color = Color("#edf3f7")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	host.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)
	var title := Label.new()
	title.text = "Teste isolado — OpenStreetMap + ERBs oficiais + agulhas"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#17344f"))
	stack.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "A posição do veículo é fixa em Imperatriz para validar a ponta exata do marcador. Arraste e use os controles de zoom."
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color("#5f7182"))
	stack.add_child(subtitle)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	stack.add_child(body)

	canvas = MapCanvas.new()
	canvas.name = "IsolatedMapCanvas"
	canvas.custom_minimum_size = Vector2(1050, 650)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.set_city_label("Imperatriz - MA")
	canvas.set_tracking_mode(true)
	canvas.set_station_visibility(true)
	canvas.set_basemap(Config.DEFAULT_BASEMAP)
	canvas.navigation_requested.connect(_on_demo_navigation)
	canvas.reset_requested.connect(_on_demo_reset)
	body.add_child(canvas)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(310, 0)
	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 18)
	panel_margin.add_theme_constant_override("margin_right", 18)
	panel_margin.add_theme_constant_override("margin_top", 18)
	panel_margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(panel_margin)
	var panel_stack := VBoxContainer.new()
	panel_stack.add_theme_constant_override("separation", 10)
	panel_margin.add_child(panel_stack)
	var panel_title := Label.new()
	panel_title.text = "Dados do teste"
	panel_title.add_theme_font_size_override("font_size", 18)
	panel_title.add_theme_color_override("font_color", Color("#17344f"))
	panel_stack.add_child(panel_title)
	for line in [
		"Mapa: OpenStreetMap",
		"Veículo: AAA-087",
		"Estado: Ligado",
		"Coordenada: -5.526400, -47.491900",
		"Agulha: verde",
		"ERBs: índice nacional oficial Anatel",
	]:
		var value := Label.new()
		value.text = line
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.add_theme_font_size_override("font_size", 13)
		value.add_theme_color_override("font_color", Color("#445b70"))
		panel_stack.add_child(value)
	status_label = Label.new()
	status_label.text = "Carregando tiles reais e ERBs oficiais..."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("#0070b8"))
	panel_stack.add_child(status_label)
	var close_button := Button.new()
	close_button.text = "Fechar janela de teste"
	close_button.custom_minimum_size = Vector2(0, 42)
	close_button.pressed.connect(func() -> void: quit(0))
	panel_stack.add_child(close_button)
	body.add_child(panel)
	national_index = NationalIndex.new()
	var loaded: Dictionary = national_index.call("load_manifest")
	if bool(loaded.get("ok", false)):
		national_metadata = (loaded.get("metadata", {}) as Dictionary).duplicate(true)
	else:
		status_label.text = str(loaded.get("message", "Índice nacional indisponível"))
	call_deferred("_load_demo_map")


func _load_demo_map() -> void:
	await _load_demo_map_area(DEMO_LAT, DEMO_LNG, DEMO_ZOOM, false)


func _on_demo_navigation(latitude: float, longitude: float, zoom: int) -> void:
	# O canvas marca a navegacao como pendente antes de emitir este sinal.
	# Recarregar a area aqui e o que libera o estado e permite continuar
	# arrastando ou usando o zoom depois que os tiles terminarem.
	call_deferred("_load_demo_map_area", latitude, longitude, zoom, true)


func _on_demo_reset() -> void:
	call_deferred("_load_demo_map_area", DEMO_LAT, DEMO_LNG, DEMO_ZOOM, true)


func _load_demo_map_area(latitude: float, longitude: float, zoom: int, is_navigation: bool) -> void:
	demo_load_generation += 1
	var current_generation := demo_load_generation
	await process_frame
	await process_frame
	if canvas == null or not is_instance_valid(canvas):
		return
	var viewport_size := Vector2i(maxi(900, roundi(canvas.size.x)), maxi(560, roundi(canvas.size.y)))
	var safe_zoom := clampi(zoom, Config.MIN_ZOOM, Config.MAX_ZOOM)
	var world_pixel := MapProjection.lat_lng_to_world_pixel(latitude, longitude, safe_zoom)
	var top_left := Vector2i(roundi(world_pixel.x - float(viewport_size.x) * 0.5), roundi(world_pixel.y - float(viewport_size.y) * 0.5))
	var first_tile := Vector2i(floori(float(top_left.x) / 256.0), floori(float(top_left.y) / 256.0))
	var last_tile := Vector2i(
		floori(float(top_left.x + viewport_size.x - 1) / 256.0),
		floori(float(top_left.y + viewport_size.y - 1) / 256.0)
	)
	var max_tile := 1 << safe_zoom
	var entries: Array[Dictionary] = []
	for tile_y in range(first_tile.y, last_tile.y + 1):
		for tile_x in range(first_tile.x, last_tile.x + 1):
			if tile_y < 0 or tile_y >= max_tile:
				continue
			var wrapped_x := posmod(tile_x, max_tile)
			entries.append({
				"key": TileProvider.cache_key(safe_zoom, wrapped_x, tile_y, Config.DEFAULT_BASEMAP),
				"x": tile_x,
				"y": tile_y,
			})
	canvas.set_map_view(entries, safe_zoom, Vector2(top_left), Vector2(viewport_size), 0, entries.size())
	var loaded := 0
	for entry in entries:
		var bytes := await _download_tile(safe_zoom, int(posmod(int(entry.get("x", 0)), max_tile)), int(entry.get("y", 0)))
		if current_generation != demo_load_generation:
			return
		var texture := TileProvider.texture_from_bytes(bytes)
		if texture != null:
			canvas.set_map_tile(str(entry.get("key", "")), int(entry.get("x", 0)), int(entry.get("y", 0)), texture)
			loaded += 1
	canvas.finish_map_tile_load(loaded, entries.size())
	if current_generation != demo_load_generation:
		return
	var official_stations: Array[Dictionary] = _official_stations_for_view(Vector2(top_left), Vector2(viewport_size), safe_zoom)
	canvas.set_coverage_profile({"ok": true, "stations": official_stations, "metadata": national_metadata})
	var demo_locations: Array[Dictionary] = []
	demo_locations.append({
		"plate": "AAA-087",
		"serial": "TEST-AGULHA",
		"lat": DEMO_LAT,
		"lng": DEMO_LNG,
		"coordinates_valid": true,
		"communication_state": "Ligado",
		"ignition": "1",
		"updated_at": "agora",
	})
	canvas.set_tracking_locations(demo_locations)
	canvas.set_tracking_mode(true)
	status_label.text = "OpenStreetMap carregado: %d/%d tiles · %d ERBs oficiais · agulha verde posicionada%s." % [
		loaded,
		entries.size(),
		canvas.stations.size(),
		". Area atualizada" if is_navigation else "",
	]
	var station_count := int(canvas.stations.size())
	print("MAP_VISUAL_TEST: osm_tiles=%d/%d official_stations=%d provenance=%s green_pin=true navigation_loading=%s" % [
		loaded,
		entries.size(),
		station_count,
		str(national_metadata.has("source_zip_sha256")),
		str(canvas.navigation_loading),
	])
	if DisplayServer.get_name() == "headless":
		quit(0 if loaded > 0 and station_count > 0 and national_metadata.has("source_zip_sha256") and not canvas.navigation_loading else 1)


func _download_tile(zoom: int, tile_x: int, tile_y: int) -> PackedByteArray:
	var request := HTTPRequest.new()
	root.add_child(request)
	var error := request.request(TileProvider.tile_url(zoom, tile_x, tile_y, Config.DEFAULT_BASEMAP), ["User-Agent: GrupoRSCentral/1.0"])
	if error != OK:
		request.queue_free()
		return PackedByteArray()
	var result: Array = await request.request_completed
	request.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) < 200 or int(result[1]) >= 300:
		return PackedByteArray()
	return result[3] as PackedByteArray


func _official_stations_for_view(top_left: Vector2, viewport_size: Vector2, zoom: int) -> Array[Dictionary]:
	if national_index == null or national_metadata.is_empty():
		return []
	var north_west := MapProjection.world_pixel_to_lat_lng(top_left - Vector2(64, 64), zoom)
	var south_east := MapProjection.world_pixel_to_lat_lng(top_left + viewport_size + Vector2(64, 64), zoom)
	var result: Dictionary = national_index.call("query_viewport", {
		"min_lat": minf(north_west.x, south_east.x),
		"max_lat": maxf(north_west.x, south_east.x),
		"min_lng": minf(north_west.y, south_east.y),
		"max_lng": maxf(north_west.y, south_east.y),
	}, zoom, {})
	var stations: Array[Dictionary] = []
	if bool(result.get("ok", false)):
		for station in result.get("stations", []) as Array:
			if typeof(station) == TYPE_DICTIONARY:
				stations.append((station as Dictionary).duplicate(true))
	return stations
