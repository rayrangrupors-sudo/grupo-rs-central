## Canvas visual e interativo do Mapa Grande.
##
## Responsabilidades: desenhar tiles, ERBs e veículos; controlar zoom,
## arraste, seleção, legendas e animações dos marcadores.
## Não realiza consultas de rede nem acessa estoque/API.
extends Control

const Config := preload("res://src/features/big_map/big_map_config.gd")
const GeoProjection := preload("res://src/features/big_map/map_projection.gd")
const VehicleStatus := preload("res://src/features/big_map/vehicle_status_resolver.gd")
const TRACKING_PIN_YELLOW_PATH := "res://assets/maps/agulha_localizacao_amarela.svg"
const TRACKING_PIN_GREEN_PATH := "res://assets/maps/agulha_localizacao_verde.svg"
const TRACKING_PIN_RED_PATH := "res://assets/maps/agulha_localizacao_vermelha.svg"
const ERB_MARKER_CLARO_PATH := "res://assets/maps/erb_markers_v3/production/compact/erb-marker-claro-v3.png"
const ERB_MARKER_NEUTRAL_PATH := "res://assets/maps/erb_markers_v3/production/compact/erb-marker-neutro-v3.png"
const ERB_MARKER_TIM_PATH := "res://assets/maps/erb_markers_v3/production/compact/erb-marker-tim-v3.png"
const ERB_MARKER_VIVO_PATH := "res://assets/maps/erb_markers_v3/production/compact/erb-marker-vivo-v3.png"


signal navigation_requested(latitude: float, longitude: float, zoom: int)
signal reset_requested
signal station_selected(station: Dictionary)
signal tracking_selected(location: Dictionary)

var devices: Array[Dictionary] = []
var coverage_cells: Array[Dictionary] = []
var stations: Array[Dictionary] = []
var tracking_locations: Array[Dictionary] = []
var selected_index := -1
var selected_cell_index := -1
var selected_station_index := -1
var selected_tracking_index := -1
var map_texture: Texture2D
var map_zoom := 15
var map_top_left := Vector2.ZERO
var map_viewport_size := Vector2.ZERO
var city_label := Config.DEFAULT_CITY_LABEL
var coverage_mode := "best"
var analyzed_operator := "CLARO"
var generation := "4G"
var dataset_updated_at := "--"
var basemap_id := Config.DEFAULT_BASEMAP
var map_ready := false
var map_error := ""
var loading_stage := "Preparando mapa e cobertura"
var loading_phase := 0.0
var show_stations := true
var tracking_mode := false
var load_generation := 0
var navigation_loading := false
var dragging := false
var drag_start := Vector2.ZERO
var drag_start_offset := Vector2.ZERO
var drag_offset := Vector2.ZERO
var drag_distance := 0.0
var navigation_target_active := false
var navigation_target_zoom := 15
var navigation_target_top_left := Vector2.ZERO
var navigation_preview_revision := 0
var visible_map_tiles: Dictionary = {}
var fallback_map_tiles: Dictionary = {}
var fallback_map_zoom := 0
var map_tile_loaded_count := 0
var map_tile_total_count := 0
var map_tile_size := 256
var map_view_revision := 0
var last_map_view_reused_tile_count := 0
var loading_redraw_elapsed := 0.0
var progressive_redraw_pending := false
var progressive_redraw_count := 0
var station_data_revision := 0
var station_group_cache_key := ""
var station_group_cache: Array[Dictionary] = []
var station_group_rebuild_count := 0
var station_position_cache_key := ""
var station_position_cache: Array[Vector2] = []
var station_position_rebuild_count := 0
var station_visible_cache_key := ""
var station_visible_indices: Array[int] = []
var station_source_count := 0
var station_rendered_count := 0
var station_density_hidden_count := 0
var station_label_rects: Array[Rect2] = []
var station_cluster_cache_key := ""
var station_cluster_cache_value := false
var tracking_motion: Dictionary = {}
var tracking_pin_yellow: Texture2D
var tracking_pin_green: Texture2D
var tracking_pin_red: Texture2D
var erb_marker_claro: Texture2D
var erb_marker_neutral: Texture2D
var erb_marker_tim: Texture2D
var erb_marker_vivo: Texture2D

const MIN_MAP_ZOOM := Config.MIN_ZOOM
const MAX_MAP_ZOOM := Config.MAX_ZOOM
const MAP_CONTROL_SIZE := 36.0
const MAP_CONTROL_GAP := 5.0
const TRACKING_ANIMATION_DURATION_MSEC := 850.0
# O SVG original e 64x80. Estes tamanhos preservam sua proporcao e mantem a
# ponta inferior exatamente na coordenada GPS, com leitura operacional melhor.
const TRACKING_PIN_DRAW_SIZE := Vector2(30.0, 38.0)
const ERB_MARKER_FAR_SIZE := 34.0
const ERB_MARKER_MID_SIZE := 40.0
const ERB_MARKER_NEAR_SIZE := 48.0
const ERB_MARKER_CLOSE_SIZE := 56.0
const NAVIGATION_REDRAW_INTERVAL_SECONDS := 0.10

func _init() -> void:
	custom_minimum_size = Vector2(720, 330)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	set_process(_tracking_animation_in_progress())

func _process(delta: float) -> void:
	var tracking_animation := _tracking_animation_in_progress()
	if not navigation_loading and not tracking_animation:
		set_process(false)
		return
	var redraw_requested := false
	if navigation_loading:
		loading_phase = fmod(loading_phase + delta * 0.85, 1.0)
		loading_redraw_elapsed += delta
		if loading_redraw_elapsed >= NAVIGATION_REDRAW_INTERVAL_SECONDS:
			loading_redraw_elapsed = 0.0
			redraw_requested = true
	if tracking_animation:
		redraw_requested = true
	if redraw_requested:
		queue_redraw()

func set_devices(next_devices: Array[Dictionary]) -> void:
	# O Monitor 4G usa somente a malha Anatel; nenhum aparelho e consultado ou desenhado aqui.
	devices.clear()
	selected_index = -1
	queue_redraw()

func set_tracking_locations(next_locations: Array[Dictionary]) -> void:
	var previous_motion: Dictionary = {}
	for previous_index in range(tracking_locations.size()):
		var previous_location := tracking_locations[previous_index]
		var previous_key := _tracking_location_key(previous_location, previous_index)
		previous_motion[previous_key] = _tracking_display_geo(previous_index, previous_location)
	var now_msec := Time.get_ticks_msec()
	var next_motion: Dictionary = {}
	tracking_locations.clear()
	for location_index in range(next_locations.size()):
		var location := next_locations[location_index].duplicate(true)
		tracking_locations.append(location)
		var target_geo := _tracking_target_geo(location)
		if is_zero_approx(target_geo.x) and is_zero_approx(target_geo.y):
			continue
		var location_key := _tracking_location_key(location, location_index)
		var start_geo: Vector2 = previous_motion.get(location_key, target_geo)
		if start_geo.distance_to(target_geo) > 0.000001:
			next_motion[location_key] = {
				"from": start_geo,
				"to": target_geo,
				"started_msec": now_msec,
				"duration_msec": TRACKING_ANIMATION_DURATION_MSEC,
			}
	tracking_motion = next_motion
	selected_tracking_index = -1
	if map_ready and _tracking_animation_in_progress():
		set_process(true)
	queue_redraw()

func _tracking_location_key(location: Dictionary, location_index: int) -> String:
	for field in ["vehicle_id", "equipment_id", "serial", "plate"]:
		var value := str(location.get(field, "")).strip_edges()
		if value != "":
			return "%s:%s" % [field, value.to_lower()]
	return "index:%d" % location_index

func _tracking_target_geo(location: Dictionary) -> Vector2:
	return Vector2(
		float(str(location.get("lat", "0"))),
		float(str(location.get("lng", "0"))),
	)

func _tracking_display_geo(location_index: int, location: Dictionary) -> Vector2:
	var target_geo := _tracking_target_geo(location)
	var location_key := _tracking_location_key(location, location_index)
	var motion: Dictionary = tracking_motion.get(location_key, {})
	if motion.is_empty():
		return target_geo
	var from_geo: Vector2 = motion.get("from", target_geo)
	var to_geo: Vector2 = motion.get("to", target_geo)
	var duration := maxf(float(motion.get("duration_msec", TRACKING_ANIMATION_DURATION_MSEC)), 1.0)
	var elapsed := float(Time.get_ticks_msec() - int(motion.get("started_msec", 0)))
	return from_geo.lerp(to_geo, clampf(elapsed / duration, 0.0, 1.0))

func _tracking_animation_in_progress() -> bool:
	if tracking_motion.is_empty():
		return false
	var now_msec := Time.get_ticks_msec()
	for motion_value in tracking_motion.values():
		var motion: Dictionary = motion_value
		var from_geo: Vector2 = motion.get("from", Vector2.ZERO)
		var to_geo: Vector2 = motion.get("to", from_geo)
		var duration := maxf(float(motion.get("duration_msec", TRACKING_ANIMATION_DURATION_MSEC)), 1.0)
		var elapsed := float(now_msec - int(motion.get("started_msec", 0)))
		if elapsed < duration and from_geo.distance_to(to_geo) > 0.000001:
			return true
	return false

func _tracking_map_position(location_index: int, location: Dictionary) -> Vector2:
	var display_geo := _tracking_display_geo(location_index, location)
	return _map_position(display_geo.x, display_geo.y)

func set_tracking_mode(enabled: bool) -> void:
	tracking_mode = enabled
	selected_tracking_index = -1
	queue_redraw()

func current_map_view() -> Dictionary:
	# Atualizacoes de dados devem trocar apenas os marcadores. Expor o
	# enquadramento atual permite que a consulta seguinte reutilize exatamente
	# o centro e o zoom escolhidos pelo usuario.
	if not map_ready or map_viewport_size.x <= 0.0 or map_viewport_size.y <= 0.0:
		return {}
	var display_zoom := _display_map_zoom()
	var center_world := _display_map_top_left() + map_viewport_size * 0.5
	var center_geo := _world_pixel_to_lat_lng(center_world, display_zoom)
	return {
		"center": {"lat": center_geo.x, "lng": center_geo.y},
		"zoom": display_zoom,
		"basemap": basemap_id,
		"interactive": true,
	}


func set_basemap(_value: String) -> void:
	# OSM é o único mapa-base. Estados antigos nunca reativam satélite/Esri.
	if basemap_id == Config.BASEMAP_NORMAL:
		return
	basemap_id = Config.BASEMAP_NORMAL
	queue_redraw()

func set_coverage_profile(profile: Dictionary) -> void:
	coverage_cells.clear()
	stations.clear()
	var next_stations: Variant = profile.get("stations", [])
	if typeof(next_stations) == TYPE_ARRAY:
		for station in next_stations as Array:
			if typeof(station) == TYPE_DICTIONARY:
				stations.append((station as Dictionary).duplicate(true))
	coverage_mode = str(profile.get("mode", "best"))
	analyzed_operator = str(profile.get("selected_operator", "CLARO"))
	generation = str(profile.get("generation", "4G"))
	var profile_metadata: Dictionary = profile.get("metadata", {})
	dataset_updated_at = str(profile_metadata.get(
		"source_last_modified",
		profile_metadata.get("generated_at", "--")
	))
	selected_cell_index = -1
	selected_station_index = -1
	station_data_revision += 1
	_invalidate_station_visual_cache()
	queue_redraw()

func select_station_by_id(station_id: String) -> void:
	selected_station_index = -1
	var target := station_id.strip_edges()
	if target != "":
		for index in range(stations.size()):
			var station := stations[index]
			if str(station.get("id", station.get("code", ""))).strip_edges() == target:
				selected_station_index = index
				break
	queue_redraw()

func select_tracking_by_key(key: String) -> void:
	selected_tracking_index = -1
	var target := key.strip_edges()
	if target != "":
		for index in range(tracking_locations.size()):
			var location := tracking_locations[index]
			var candidate := str(location.get("serial", location.get("plate", ""))).strip_edges()
			if candidate == target:
				selected_tracking_index = index
				break
	queue_redraw()


func clear_tracking_selection() -> void:
	selected_tracking_index = -1
	queue_redraw()

func set_map_texture(texture: Texture2D, zoom: int, top_left: Vector2, viewport_size: Vector2) -> void:
	map_texture = texture
	visible_map_tiles.clear()
	fallback_map_tiles.clear()
	map_zoom = zoom
	map_top_left = top_left
	_reset_navigation_target()
	map_viewport_size = viewport_size
	map_ready = texture != null and viewport_size.x > 0.0 and viewport_size.y > 0.0
	map_view_revision += 1
	_invalidate_station_visual_cache()
	map_error = ""
	navigation_loading = false
	set_process(_tracking_animation_in_progress())
	dragging = false
	drag_offset = Vector2.ZERO
	drag_distance = 0.0
	queue_redraw()

func set_map_view(
	tiles: Array[Dictionary],
	zoom: int,
	top_left: Vector2,
	viewport_size: Vector2,
	loaded_count: int,
	total_count: int
) -> void:
	map_texture = null
	var previous_tiles := visible_map_tiles
	var previous_zoom := map_zoom
	if navigation_loading and map_ready and fallback_map_tiles.is_empty() and not previous_tiles.is_empty():
		fallback_map_tiles = previous_tiles.duplicate(true)
		fallback_map_zoom = previous_zoom
	var next_tiles: Dictionary = {}
	last_map_view_reused_tile_count = 0
	for tile in tiles:
		var key := str(tile.get("key", ""))
		if key != "":
			var next_tile := tile.duplicate(true)
			var previous_tile: Dictionary = previous_tiles.get(key, {})
			var previous_texture: Texture2D = previous_tile.get("texture") as Texture2D
			if previous_texture != null:
				last_map_view_reused_tile_count += 1
				if next_tile.get("texture") == null:
					next_tile["texture"] = previous_texture
			next_tiles[key] = next_tile
	visible_map_tiles = next_tiles
	map_view_revision += 1
	_invalidate_station_visual_cache()
	map_zoom = zoom
	map_top_left = top_left
	_reset_navigation_target()
	map_viewport_size = viewport_size
	map_tile_loaded_count = loaded_count
	map_tile_total_count = total_count
	map_ready = viewport_size.x > 0.0 and viewport_size.y > 0.0
	map_error = ""
	navigation_loading = loaded_count < total_count
	set_process(navigation_loading or _tracking_animation_in_progress())
	dragging = false
	drag_offset = Vector2.ZERO
	drag_distance = 0.0
	queue_redraw()

func set_map_tile(key: String, tile_x: int, tile_y: int, texture: Texture2D) -> void:
	if texture == null or key == "":
		return
	visible_map_tiles[key] = {
		"key": key,
		"x": tile_x,
		"y": tile_y,
		"texture": texture,
	}
	map_tile_loaded_count += 1
	navigation_loading = map_tile_loaded_count < map_tile_total_count
	set_process(navigation_loading or _tracking_animation_in_progress())
	_request_progressive_redraw()

func finish_map_tile_load(loaded_count: int, total_count: int) -> void:
	map_tile_loaded_count = loaded_count
	map_tile_total_count = total_count
	navigation_loading = false
	if total_count <= 0 or loaded_count >= total_count:
		fallback_map_tiles.clear()
	set_process(_tracking_animation_in_progress())
	queue_redraw()

func set_map_tile_progress(loaded_count: int, total_count: int, stage: String) -> void:
	map_tile_loaded_count = loaded_count
	map_tile_total_count = total_count
	loading_stage = stage
	navigation_loading = loaded_count < total_count
	set_process(navigation_loading or _tracking_animation_in_progress())
	_request_progressive_redraw()

func begin_map_load(
	stage: String = "Carregando mapa e analisando cobertura",
	preserve_current_map: bool = false
) -> int:
	load_generation += 1
	loading_redraw_elapsed = 0.0
	navigation_loading = preserve_current_map and map_ready
	if not navigation_loading:
		map_ready = false
		map_texture = null
		visible_map_tiles.clear()
	map_error = ""
	loading_stage = stage
	set_process(true)
	queue_redraw()
	return load_generation

func set_loading_stage(stage: String, preserve_current_map: bool = false) -> void:
	if preserve_current_map:
		navigation_loading = map_ready
	else:
		# A scan de dados nao deve desmontar um mapa que ja esta navegavel.
		navigation_loading = false
	set_process(navigation_loading or _tracking_animation_in_progress())
	map_error = ""
	loading_stage = stage
	queue_redraw()

func is_load_current(generation: int) -> bool:
	return generation == load_generation

func set_map_error(message: String) -> void:
	load_generation += 1
	map_ready = false
	map_error = message.strip_edges()
	navigation_loading = false
	set_process(false)
	dragging = false
	drag_offset = Vector2.ZERO
	queue_redraw()

func cancel_navigation_load(message: String = "") -> void:
	load_generation += 1
	navigation_loading = false
	set_process(false)
	dragging = false
	drag_offset = Vector2.ZERO
	map_error = message.strip_edges()
	queue_redraw()


func _request_progressive_redraw() -> void:
	if progressive_redraw_pending:
		return
	progressive_redraw_pending = true
	call_deferred("_flush_progressive_redraw")


func _flush_progressive_redraw() -> void:
	progressive_redraw_pending = false
	progressive_redraw_count += 1
	queue_redraw()


func _invalidate_station_visual_cache() -> void:
	station_group_cache_key = ""
	station_group_cache.clear()
	station_position_cache_key = ""
	station_position_cache.clear()
	station_visible_cache_key = ""
	station_visible_indices.clear()
	station_cluster_cache_key = ""


func _reset_navigation_target() -> void:
	navigation_target_active = false
	navigation_target_zoom = map_zoom
	navigation_target_top_left = map_top_left
	drag_offset = Vector2.ZERO


func _ensure_navigation_target() -> void:
	if navigation_target_active:
		return
	navigation_target_active = true
	navigation_target_zoom = map_zoom
	navigation_target_top_left = map_top_left


func _display_map_zoom() -> int:
	return navigation_target_zoom if navigation_target_active else map_zoom


func _display_map_top_left() -> Vector2:
	return navigation_target_top_left if navigation_target_active else map_top_left


func _commit_navigation_preview_change() -> void:
	navigation_preview_revision += 1
	map_view_revision += 1
	_invalidate_station_visual_cache()
	queue_redraw()

func set_station_visibility(visible: bool) -> void:
	show_stations = visible
	queue_redraw()

func set_city_label(value: String) -> void:
	city_label = value.strip_edges() if value.strip_edges() != "" else "Cidade nao informada"
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not map_ready:
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_request_zoom(mouse_event.position, 1)
			accept_event()
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_request_zoom(mouse_event.position, -1)
			accept_event()
			return
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			var control_action := _map_control_action(mouse_event.position)
			if control_action != "":
				_activate_map_control(control_action)
				accept_event()
				return
			dragging = true
			drag_start = mouse_event.position
			drag_start_offset = drag_offset
			drag_distance = 0.0
			mouse_default_cursor_shape = Control.CURSOR_MOVE
			accept_event()
			return
		if not dragging:
			return
		dragging = false
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		if drag_distance < 6.0:
			drag_offset = Vector2.ZERO
			if tracking_mode:
				selected_tracking_index = _nearest_tracking_index(mouse_event.position)
				if selected_tracking_index >= 0:
					tracking_selected.emit(tracking_locations[selected_tracking_index].duplicate(true))
				else:
					selected_station_index = _nearest_station_index(mouse_event.position)
					station_selected.emit(
						stations[selected_station_index].duplicate(true)
						if selected_station_index >= 0
						else {}
					)
				queue_redraw()
				return
			selected_station_index = _nearest_station_index(mouse_event.position)
			station_selected.emit(
				stations[selected_station_index].duplicate(true)
				if selected_station_index >= 0
				else {}
			)
			queue_redraw()
			return
		_request_pan_navigation()
		accept_event()
	elif event is InputEventMouseMotion and dragging and map_ready:
		var motion_event := event as InputEventMouseMotion
		drag_offset = drag_start_offset + motion_event.position - drag_start
		drag_distance = maxf(drag_distance, drag_offset.length())
		selected_cell_index = -1
		selected_station_index = -1
		queue_redraw()
		accept_event()

func _nearest_station_index(point: Vector2) -> int:
	if _should_cluster_stations():
		var nearest_group: Dictionary = {}
		var nearest_group_distance := INF
		for group_value in _station_visual_groups():
			var group := group_value as Dictionary
			var group_position: Vector2 = (group.get("position", Vector2(-10000, -10000)) as Vector2) + drag_offset
			var distance := group_position.distance_to(point)
			if distance <= 25.0 and distance < nearest_group_distance:
				nearest_group = group
				nearest_group_distance = distance
		if not nearest_group.is_empty():
			var indices: Array = nearest_group.get("indices", [])
			if not indices.is_empty():
				var current_position := indices.find(selected_station_index)
				return int(indices[(current_position + 1) % indices.size()]) if current_position >= 0 else int(indices[0])
	var nearest := -1
	var nearest_distance := INF
	var station_positions := _station_visual_positions()
	for station_index in _visible_station_indices():
		var station: Dictionary = stations[station_index]
		if bool(station.get("is_index_cluster", false)):
			continue
		var position := _station_screen_anchor(station_positions[station_index] + drag_offset)
		if position.x < 4.0 or position.y < 4.0 or position.x > size.x - 4.0 or position.y > size.y - 4.0:
			continue
		var radius := _station_marker_hit_radius()
		var distance := position.distance_to(point)
		if distance > radius or distance >= nearest_distance:
			continue
		nearest_distance = distance
		nearest = station_index
	return nearest

func _nearest_tracking_index(point: Vector2) -> int:
	var nearest_group: Dictionary = {}
	var nearest_distance := INF
	for group_value in _tracking_visual_groups():
		var group: Dictionary = group_value
		var position: Vector2 = group.get("position", Vector2(-10000, -10000))
		if position.x < 4.0 or position.y < 4.0 or position.x > size.x - 4.0 or position.y > size.y - 4.0:
			continue
		var distance := position.distance_to(point)
		if distance > 30.0 or distance >= nearest_distance:
			continue
		nearest_distance = distance
		nearest_group = group
	if nearest_group.is_empty():
		return -1
	var indices: Array = nearest_group.get("indices", [])
	if indices.is_empty():
		return -1
	# Quando vários aparelhos ocupam a mesma coordenada, cada clique no
	# agrupamento avança para o próximo aparelho em vez de deixar somente o
	# último marcador desenhado selecionável.
	var current_position := indices.find(selected_tracking_index)
	if current_position >= 0:
		return int(indices[(current_position + 1) % indices.size()])
	return int(indices[0])

func _tracking_visual_groups() -> Array:
	var groups: Array = []
	for location_index in range(tracking_locations.size()):
		var location := tracking_locations[location_index]
		var target_geo := _tracking_target_geo(location)
		if is_zero_approx(target_geo.x) and is_zero_approx(target_geo.y):
			continue
		var position := _tracking_map_position(location_index, location)
		if position.x < -24.0 or position.y < -24.0 or position.x > size.x + 24.0 or position.y > size.y + 24.0:
			continue
		var matching_group := -1
		for group_index in range(groups.size()):
			var candidate: Dictionary = groups[group_index]
			var candidate_position: Vector2 = candidate.get("position", Vector2.ZERO)
			# Agrupa apenas coordenadas praticamente identicas. Veiculos proximos
			# continuam aparecendo como agulhas independentes.
			if candidate_position.distance_to(position) <= 3.0:
				matching_group = group_index
				break
		if matching_group < 0:
			groups.append({"indices": [location_index], "position": position})
			continue
		var group: Dictionary = groups[matching_group]
		var indices: Array = group.get("indices", [])
		var current_group_position: Vector2 = group.get("position", Vector2.ZERO)
		indices.append(location_index)
		group["indices"] = indices
		# Recalcula o centro para que a bolha fique entre os aparelhos quando
		# eles estiverem muito próximos, mas não exatamente no mesmo ponto.
		group["position"] = (current_group_position * float(indices.size() - 1) + position) / float(indices.size())
		groups[matching_group] = group
	return groups

func _draw() -> void:
	if not map_ready:
		_draw_loading_state()
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#eef4f8"), true)
	var drawn_tiles := _draw_fallback_tile_layer()
	var display_zoom := _display_map_zoom()
	var display_top_left := _display_map_top_left()
	var visible_scale := pow(2.0, float(display_zoom - map_zoom))
	for tile_value in visible_map_tiles.values():
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile := tile_value as Dictionary
		var texture: Texture2D = tile.get("texture") as Texture2D
		if texture == null:
			continue
		var tile_position := Vector2(
			float(tile.get("x", 0)) * float(map_tile_size),
			float(tile.get("y", 0)) * float(map_tile_size)
		) * visible_scale - display_top_left + drag_offset
		draw_texture_rect(
			texture,
			Rect2(tile_position, Vector2(map_tile_size, map_tile_size) * visible_scale),
			false
		)
		drawn_tiles += 1
	if drawn_tiles == 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#eef4f8"), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.025), true)
	var font := get_theme_default_font()
	# A tela de Localizacao usa somente os aparelhos retornados pela API. Nao
	# exiba aqui o estado vazio do catalogo de ERBs, pois ele nao representa
	# uma falha de rastreamento e acaba cobrindo os marcadores.
	if stations.is_empty() and show_stations:
		draw_string(font, Vector2(size.x * 0.5 - 190.0, size.y * 0.48), "Nenhuma ERB Anatel encontrada nesta area", HORIZONTAL_ALIGNMENT_CENTER, 380.0, 15, Color("#657487"))
	# ERBs formam a camada geográfica inferior. Veículos são desenhados depois
	# e, portanto, nunca ficam escondidos por uma torre sobreposta.
	if show_stations:
		station_label_rects.clear()
		var station_positions := _station_visual_positions()
		for station_index in _visible_station_indices():
			_draw_station_marker(stations[station_index], station_index, station_positions[station_index])
	if tracking_mode:
		var selected_tracking_group: Dictionary = {}
		for group_value in _tracking_visual_groups():
			var group: Dictionary = group_value
			var indices: Array = group.get("indices", [])
			if indices.has(selected_tracking_index):
				selected_tracking_group = group
				continue
			_draw_tracking_group(group)
		# O veículo selecionado, incluindo agulha e etiqueta, é a última entidade
		# geográfica desenhada e ocupa a camada frontal.
		if not selected_tracking_group.is_empty():
			_draw_tracking_group(selected_tracking_group)
			_draw_tracking_group_label(selected_tracking_group)
	if tracking_mode:
		_draw_tracking_legend()
	else:
		_draw_map_legend()
	draw_string(font, Vector2(18, size.y - 18), str(Config.basemap(basemap_id).get("attribution", Config.TILE_ATTRIBUTION)), HORIZONTAL_ALIGNMENT_LEFT, 520.0, 10, Color("#657487"))
	_draw_map_scale()
	_draw_map_controls()
	if navigation_loading:
		_draw_navigation_loading()

func _draw_loading_state() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#eef4f8"), true)
	var center := size * 0.5
	var font := get_theme_default_font()
	if map_error != "":
		draw_circle(center + Vector2(0, -28), 20.0, Color("#d64545"))
		draw_string(font, center + Vector2(-180, 25), map_error, HORIZONTAL_ALIGNMENT_CENTER, 360.0, 15, Color("#5f6d7c"))
		return
	draw_arc(center + Vector2(0, -22), 22.0, 0.0, TAU, 54, Color("#cfdae5"), 5.0, true)
	var start_angle := loading_phase * TAU - PI * 0.5
	draw_arc(center + Vector2(0, -22), 22.0, start_angle, start_angle + PI * 0.86, 26, Color("#0070b8"), 5.0, true)
	draw_string(font, center + Vector2(-210, 31), loading_stage, HORIZONTAL_ALIGNMENT_CENTER, 420.0, 16, Color("#23364a"))


func _draw_fallback_tile_layer() -> int:
	if fallback_map_tiles.is_empty():
		return 0
	var drawn := 0
	var display_zoom := _display_map_zoom()
	var display_top_left := _display_map_top_left()
	var scale := pow(2.0, float(display_zoom - fallback_map_zoom))
	for tile_value in fallback_map_tiles.values():
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile := tile_value as Dictionary
		var texture: Texture2D = tile.get("texture") as Texture2D
		if texture == null:
			continue
		var fallback_world := Vector2(
			float(tile.get("x", 0)) * float(map_tile_size),
			float(tile.get("y", 0)) * float(map_tile_size)
		) * scale
		var tile_position := fallback_world - display_top_left + drag_offset
		draw_texture_rect(
			texture,
			Rect2(tile_position, Vector2(map_tile_size, map_tile_size) * scale),
			false
		)
		drawn += 1
	return drawn

func _draw_station_marker(
	station: Dictionary,
	station_index: int = -1,
	base_position: Vector2 = Vector2(INF, INF)
) -> void:
	var position := (
		base_position + drag_offset
		if base_position.is_finite()
		else _map_position(float(station.get("lat", 0.0)), float(station.get("lng", 0.0)))
	)
	# Um único pivô, compartilhado por textura, halo, badges, label e hit-test.
	position = _station_screen_anchor(position)
	var selected := station_index == selected_station_index
	var geometry := _station_marker_visual_geometry(position, selected)
	var marker_size: Vector2 = geometry.get("size", Vector2.ZERO)
	var margin := marker_size.x
	if position.x < -margin or position.y < -margin or position.x > size.x + margin or position.y > size.y + margin:
		return
	if bool(station.get("is_index_cluster", false)):
		# Centroides agregados não são ERBs reais e jamais viram torre/bolha.
		return
	var operator_identity := _station_operator_identity(str(station.get("operator", "")))
	var color: Color = operator_identity.get("color", Color("#697684"))
	var generation_color := _generation_color(str(station.get("generation", generation)))
	# O pivô visual coincide sempre com a projeção da coordenada licenciada.
	# A seleção mantém essa geometria intacta e acrescenta somente o halo.
	var icon_center: Vector2 = geometry.get("center", position)
	var identity_radius := marker_size.x * 0.48
	draw_circle(icon_center + Vector2(1.0, 2.0), identity_radius + 2.0, Color(0.02, 0.08, 0.14, 0.24))
	draw_circle(icon_center, identity_radius + 1.0, Color(1.0, 1.0, 1.0, 0.96))
	draw_arc(icon_center, identity_radius - 1.0, 0.0, TAU, 40, color, maxf(3.0, marker_size.x * 0.095), true)
	if selected:
		var selection_radius := marker_size.x * 0.60
		draw_arc(icon_center, selection_radius, 0.0, TAU, 40, Color("#0070b8"), 2.2, true)
	var marker_rect: Rect2 = geometry.get("rect", Rect2(position, Vector2.ZERO))
	draw_texture_rect(_station_marker_texture(str(station.get("operator", ""))), marker_rect, false)
	# O monograma de alto contraste identifica a prestadora mesmo quando a arte
	# da torre fica pequena. O nome completo aparece somente no zoom proximo;
	# selecionar não acrescenta área visual além do contorno azul.
	var monogram_position := position + Vector2(marker_size.x * 0.31, -marker_size.y * 0.69)
	var monogram_radius := clampf(marker_size.x * 0.19, 7.0, 11.0)
	draw_circle(monogram_position + Vector2(1.0, 2.0), monogram_radius + 1.0, Color(0.02, 0.08, 0.14, 0.28))
	draw_circle(monogram_position, monogram_radius, color)
	draw_arc(monogram_position, monogram_radius, 0.0, TAU, 28, Color.WHITE, 1.3, true)
	draw_string(
		get_theme_default_font(),
		monogram_position + Vector2(-monogram_radius, 4.0),
		str(operator_identity.get("short", "?")),
		HORIZONTAL_ALIGNMENT_CENTER,
		monogram_radius * 2.0,
		8 if str(operator_identity.get("short", "?")).length() <= 2 else 7,
		Color.WHITE
	)
	# A geração permanece visível sem transformar a ERB em um segundo marcador.
	var badge_position := position + Vector2(marker_size.x * 0.32, -marker_size.y * 0.15)
	draw_circle(badge_position, 3.8, Color.WHITE)
	draw_circle(badge_position, 2.8, generation_color)
	if _should_draw_station_operator_label(selected):
		_draw_station_operator_label(position, marker_size, operator_identity, false)


func _station_marker_draw_size(selected: bool = false) -> Vector2:
	# Seleção não altera geometria. O parâmetro permanece no contrato interno
	# para deixar explícito que normal/selecionada usam exatamente a mesma área.
	var _selection_does_not_scale := selected
	var base_size := ERB_MARKER_FAR_SIZE
	if _display_map_zoom() >= 16:
		base_size = ERB_MARKER_CLOSE_SIZE
	elif _display_map_zoom() >= 15:
		base_size = ERB_MARKER_NEAR_SIZE
	elif _display_map_zoom() >= 13:
		base_size = ERB_MARKER_MID_SIZE
	return Vector2(base_size, base_size)


func _station_marker_visual_geometry(geo_anchor: Vector2, selected: bool = false) -> Dictionary:
	var marker_size := _station_marker_draw_size(selected)
	return {
		"anchor": geo_anchor,
		"center": geo_anchor,
		"halo_center": geo_anchor,
		"size": marker_size,
		"rect": Rect2(geo_anchor - marker_size * 0.5, marker_size),
	}


func _station_screen_anchor(projected_position: Vector2) -> Vector2:
	return Vector2(roundf(projected_position.x), roundf(projected_position.y))


func _should_draw_station_operator_label(_selected: bool = false) -> bool:
	return _display_map_zoom() >= 16


func _station_marker_hit_radius() -> float:
	# A área clicável é deliberadamente maior que o desenho, inclusive em z10.
	return maxf(28.0, _station_marker_draw_size(false).x * 0.68)


func _draw_tracking_group(group: Dictionary) -> void:
	var indices: Array = group.get("indices", [])
	if indices.size() > 1:
		_draw_tracking_cluster_marker(group)
	elif not indices.is_empty():
		var location_index := int(indices[0])
		_draw_tracking_marker(tracking_locations[location_index], location_index)


func _draw_station_operator_label(position: Vector2, marker_size: Vector2, identity: Dictionary, selected: bool = false) -> void:
	var label := str(identity.get("label", "N/D"))
	var color: Color = identity.get("color", Color("#697684"))
	var label_width := clampf(float(label.length()) * 7.0 + 22.0, 54.0, 132.0)
	var label_size := Vector2(label_width, 22.0)
	var safe_margin := 16.0
	var candidates: Array[Vector2] = [
		Vector2(position.x - label_size.x * 0.5, position.y - marker_size.y - label_size.y - 5.0),
		Vector2(position.x - label_size.x * 0.5, position.y + 8.0),
		Vector2(position.x + marker_size.x * 0.55, position.y - label_size.y * 0.5),
		Vector2(position.x - marker_size.x * 0.55 - label_size.x, position.y - label_size.y * 0.5),
	]
	var label_rect := Rect2()
	for candidate in candidates:
		var clamped := Vector2(
			clampf(roundf(candidate.x), safe_margin, maxf(safe_margin, size.x - label_size.x - safe_margin)),
			clampf(roundf(candidate.y), safe_margin, maxf(safe_margin, size.y - label_size.y - safe_margin))
		)
		var candidate_rect := Rect2(clamped, label_size).grow(3.0)
		var overlaps := false
		for used_rect in station_label_rects:
			if used_rect.intersects(candidate_rect):
				overlaps = true
				break
		if not overlaps:
			label_rect = Rect2(clamped, label_size)
			break
	if label_rect.size == Vector2.ZERO:
		if not selected:
			return
		var fallback_position := Vector2(
			clampf(position.x - label_size.x * 0.5, safe_margin, maxf(safe_margin, size.x - label_size.x - safe_margin)),
			clampf(position.y + 8.0, safe_margin, maxf(safe_margin, size.y - label_size.y - safe_margin))
		)
		label_rect = Rect2(fallback_position, label_size)
	station_label_rects.append(label_rect.grow(3.0))
	var label_position := label_rect.position
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.96)
	style.border_color = Color.WHITE
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0.02, 0.08, 0.14, 0.30)
	style.shadow_size = 3
	draw_style_box(style, Rect2(label_position, label_size))
	draw_string(
		get_theme_default_font(),
		label_position + Vector2(8.0, 15.5),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		label_size.x - 16.0,
		9,
		Color.WHITE
	)


func _station_operator_identity(operator_name: String) -> Dictionary:
	var clean := operator_name.strip_edges().to_upper()
	if clean == "":
		return {"key": "UNDETERMINED", "label": "NÃO DETERMINADA", "short": "?", "color": Color("#566574")}
	if clean.contains("CLARO"):
		return {"key": "CLARO", "label": "CLARO", "short": "C", "color": Color("#e32636")}
	if clean.contains("TIM"):
		return {"key": "TIM", "label": "TIM", "short": "T", "color": Color("#1268d6")}
	if clean.contains("VIVO") or clean.contains("TELEFONICA") or clean.contains("TELEFÔNICA"):
		return {"key": "VIVO", "label": "VIVO", "short": "V", "color": Color("#7c3fc4")}
	return {"key": "OTHER", "label": "OUTRAS", "short": "O", "color": Color("#526f7f")}


func _station_marker_texture(operator_name: String) -> Texture2D:
	if erb_marker_claro == null:
		erb_marker_claro = load(ERB_MARKER_CLARO_PATH) as Texture2D
	if erb_marker_neutral == null:
		erb_marker_neutral = load(ERB_MARKER_NEUTRAL_PATH) as Texture2D
	if erb_marker_tim == null:
		erb_marker_tim = load(ERB_MARKER_TIM_PATH) as Texture2D
	if erb_marker_vivo == null:
		erb_marker_vivo = load(ERB_MARKER_VIVO_PATH) as Texture2D
	match operator_name.strip_edges().to_upper():
		"CLARO":
			return erb_marker_claro
		"TIM":
			return erb_marker_tim
		"VIVO":
			return erb_marker_vivo
	return erb_marker_neutral


func _draw_index_station_cluster(station: Dictionary, position: Vector2, selected: bool) -> void:
	var cluster_count := maxi(1, int(station.get("cluster_count", 1)))
	var operators: Array = station.get("operators", [])
	var operator_name := str(station.get("operator", ""))
	if operator_name == "" and operators.size() == 1:
		operator_name = str(operators[0])
	var accent := _operator_color(operator_name)
	var radius := clampf(13.0 + log(float(cluster_count) + 1.0) * 1.5, 15.0, 25.0)
	draw_circle(position + Vector2(1.0, 2.0), radius + 2.0, Color(0.03, 0.12, 0.20, 0.24))
	draw_circle(position, radius + 2.0, Color.WHITE)
	draw_circle(position, radius, Color(accent.r, accent.g, accent.b, 0.94))
	draw_arc(position, radius - 3.0, -PI * 0.5, PI * 0.5, 20, Color("#ff7a00"), 2.0, true)
	if selected:
		draw_arc(position, radius + 5.0, 0.0, TAU, 32, Color("#19a8e0"), 2.0, true)
	var count_text := str(cluster_count)
	var text_width := maxf(34.0, radius * 2.0 - 6.0)
	draw_string(
		get_theme_default_font(),
		position + Vector2(-text_width * 0.5, 5.0),
		count_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		text_width,
		11 if count_text.length() <= 4 else 9,
		Color.WHITE
	)

func _draw_tracking_marker(location: Dictionary, location_index: int = -1) -> void:
	var target_geo := _tracking_target_geo(location)
	if is_zero_approx(target_geo.x) and is_zero_approx(target_geo.y):
		return
	var position := _tracking_map_position(location_index, location)
	if position.x < -22.0 or position.y < -22.0 or position.x > size.x + 22.0 or position.y > size.y + 22.0:
		return
	var color := _tracking_marker_color(location)
	var selected := location_index == selected_tracking_index
	_draw_tracking_pin(position, color, _tracking_plate_label(location), selected, 0, location)

func _draw_tracking_cluster_marker(group: Dictionary) -> void:
	var indices: Array = group.get("indices", [])
	if indices.is_empty():
		return
	var position: Vector2 = group.get("position", Vector2.ZERO)
	if position.x < -22.0 or position.y < -22.0 or position.x > size.x + 22.0 or position.y > size.y + 22.0:
		return
	var representative_index := int(indices[0])
	if indices.has(selected_tracking_index):
		representative_index = selected_tracking_index
	var representative: Dictionary = tracking_locations[representative_index]
	var color := _tracking_marker_color(representative)
	var selected := indices.has(selected_tracking_index)
	_draw_tracking_pin(position, color, _tracking_plate_label(representative), selected, indices.size(), representative)

func _tracking_plate_label(location: Dictionary) -> String:
	var plate := str(location.get("plate", "")).strip_edges()
	if plate == "":
		plate = str(location.get("serial", "Aparelho")).strip_edges()
	return plate if plate != "" else "Aparelho"

func _draw_tracking_pin(
	position: Vector2,
	_color: Color,
	_plate: String,
	selected: bool,
	badge_count: int,
	location: Dictionary
) -> void:
	# A ponta inferior da agulha precisa coincidir exatamente com a coordenada
	# GPS recebida. O centro visual fica acima desse ponto, como num pin de mapa.
	var anchor := Vector2(roundf(position.x), roundf(position.y))
	var pin_texture := _tracking_pin_texture(location)
	var pin_geometry := _tracking_pin_visual_geometry(anchor, selected)
	var pin_rect: Rect2 = pin_geometry.get("rect", Rect2())
	if selected:
		# Única diferença visual da seleção: contorno azul no anchor GPS original.
		draw_arc(anchor, 18.0, 0.0, TAU, 48, Color("#19a8e0"), 1.6, true)
	draw_texture_rect(pin_texture, pin_rect, false)
	if badge_count > 1:
		var font := get_theme_default_font()
		var badge_position := anchor + Vector2(12.0, -32.0)
		draw_circle(badge_position + Vector2(1.0, 2.0), 12.0, Color(0.02, 0.08, 0.14, 0.28))
		draw_circle(badge_position, 12.0, Color("#0d2941"))
		draw_arc(badge_position, 12.0, 0.0, TAU, 24, Color.WHITE, 1.0, true)
		draw_string(font, badge_position + Vector2(-8.0, 4.0), str(badge_count), HORIZONTAL_ALIGNMENT_CENTER, 16.0, 11, Color.WHITE)


func _tracking_pin_draw_size(selected: bool = false) -> Vector2:
	# Assim como nas ERBs, a seleção da agulha acrescenta apenas o halo azul.
	var _selection_does_not_scale := selected
	return TRACKING_PIN_DRAW_SIZE


func _tracking_pin_visual_geometry(gps_anchor: Vector2, selected: bool = false) -> Dictionary:
	var pin_size := _tracking_pin_draw_size(selected)
	return {
		"anchor": gps_anchor,
		"halo_center": gps_anchor,
		"size": pin_size,
		"rect": Rect2(gps_anchor - Vector2(pin_size.x * 0.5, pin_size.y), pin_size),
	}


func _draw_tracking_group_label(group: Dictionary) -> void:
	var indices: Array = group.get("indices", [])
	if indices.is_empty() or not indices.has(selected_tracking_index):
		return
	var representative_index := selected_tracking_index
	var position: Vector2 = (
		group.get("position", Vector2.ZERO) as Vector2
		if indices.size() > 1
		else _tracking_map_position(representative_index, tracking_locations[representative_index])
	)
	var location: Dictionary = tracking_locations[representative_index]
	_draw_tracking_label(
		position,
		_tracking_marker_color(location),
		_tracking_plate_label(location)
	)


func _draw_tracking_label(position: Vector2, color: Color, plate: String) -> void:
	# Último passe do canvas: a etiqueta selecionada fica acima de ERBs,
	# agulhas, badges e demais veículos.
	var anchor := Vector2(roundf(position.x), roundf(position.y))
	var label_width := clampf(float(plate.length()) * 6.6 + 30.0, 82.0, 150.0)
	var label_size := Vector2(label_width, 24.0)
	var label_position := Vector2(roundf(anchor.x - label_size.x * 0.5), roundf(anchor.y - 66.0))
	var label_style := StyleBoxFlat.new()
	label_style.bg_color = Color("#0d263b")
	label_style.border_color = Color("#19a8e0")
	label_style.set_border_width_all(1)
	label_style.set_corner_radius_all(8)
	label_style.shadow_color = Color(0.02, 0.08, 0.14, 0.30)
	label_style.shadow_size = 4
	draw_style_box(label_style, Rect2(label_position, label_size))
	draw_circle(label_position + Vector2(11.0, 12.0), 3.0, color)
	draw_string(get_theme_default_font(), label_position + Vector2(20.0, 16.5), plate, HORIZONTAL_ALIGNMENT_LEFT, label_size.x - 26.0, 10, Color("#f7fbff"))


func _tracking_pin_texture(location: Dictionary) -> Texture2D:
	if tracking_pin_yellow == null:
		tracking_pin_yellow = load(TRACKING_PIN_YELLOW_PATH) as Texture2D
	if tracking_pin_green == null:
		tracking_pin_green = load(TRACKING_PIN_GREEN_PATH) as Texture2D
	if tracking_pin_red == null:
		tracking_pin_red = load(TRACKING_PIN_RED_PATH) as Texture2D
	match str(location.get("communication_state", "")).strip_edges().to_lower():
		"ligado":
			return tracking_pin_green
		"desligado":
			return tracking_pin_red
		"desatualizado":
			return tracking_pin_yellow
	var ignition := str(location.get("ignition", "")).strip_edges().to_lower()
	if ignition in ["1", "on", "ligado", "true"]:
		return tracking_pin_green
	if ignition in ["0", "off", "desligado", "false"]:
		return tracking_pin_red
	return tracking_pin_yellow

func _tracking_marker_color(location: Dictionary) -> Color:
	var communication_state := str(location.get("communication_state", "")).strip_edges()
	if communication_state != "":
		return VehicleStatus.color_for_state(location)
	# Compatibilidade com linhas antigas ou telas que ainda nao passaram pela
	# classificacao da Localizacao.
	var status := str(location.get("monitoring_status", location.get("status", ""))).to_lower()
	var ignition := str(location.get("ignition", "")).strip_edges().to_lower()
	if ignition in ["1", "on", "ligado", "true"] or status.contains("ligado"):
		return Color("#16a673")
	if ignition in ["0", "off", "desligado", "false"] or status.contains("desligado"):
		return Color("#dc3545")
	if status.contains("desatual") or status.contains("antiga"):
		return Color("#f2b233")
	return Color("#8b98a6")

func _draw_tracking_legend() -> void:
	var legend_size := Vector2(430 if show_stations else 316, 132 if show_stations else 86)
	var legend_position := Vector2(14, maxf(12.0, size.y - legend_size.y - 34.0))
	var legend_style := StyleBoxFlat.new()
	legend_style.bg_color = Color(1, 1, 1, 0.94)
	legend_style.border_color = Color("#dbe5ee")
	legend_style.set_border_width_all(1)
	legend_style.set_corner_radius_all(7)
	draw_style_box(legend_style, Rect2(legend_position, legend_size))
	var font := get_theme_default_font()
	draw_string(font, legend_position + Vector2(12, 19), "Legenda", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#23364a"))
	for item in [["Ligado", Color("#16a673")], ["Desligado", Color("#dc3545")], ["Desatualizado", Color("#f2b233")]]:
		var item_data: Array = item
		var item_index := ["Ligado", "Desligado", "Desatualizado"].find(str(item_data[0]))
		var x := legend_position.x + 12.0 + float(item_index) * 88.0
		draw_circle(Vector2(x, legend_position.y + 40.0), 5.0, item_data[1])
		draw_string(font, Vector2(x + 9.0, legend_position.y + 44.0), str(item_data[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#657487"))
	draw_string(font, legend_position + Vector2(12, 67), "Veículos sobrepostos: clique para alternar", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#657487"))
	if show_stations:
		draw_string(font, legend_position + Vector2(12, 88), "ERBs", HORIZONTAL_ALIGNMENT_LEFT, 42.0, 9, Color("#23364a"))
		_draw_operator_legend_items(legend_position + Vector2(55, 84), font)
		draw_string(font, legend_position + Vector2(12, 116), "ERB licenciada Anatel · não representa intensidade de sinal", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#657487"))


func _should_cluster_stations() -> bool:
	# ERBs são sempre marcadores individuais. Agregados do índice nunca são
	# representados visualmente como bolhas ou como torres inferidas.
	station_cluster_cache_key = "%d:%d" % [station_data_revision, _display_map_zoom()]
	station_cluster_cache_value = false
	return false

func _station_visual_groups() -> Array[Dictionary]:
	var cache_key := "%d:%d:%d:%d:%d" % [
		station_data_revision,
		map_view_revision,
		_display_map_zoom(),
		roundi(size.x),
		roundi(size.y),
	]
	if station_group_cache_key == cache_key:
		return station_group_cache
	var groups_by_key: Dictionary = {}
	var display_zoom := _display_map_zoom()
	var cell_size := 52.0 if display_zoom <= 13 else (38.0 if display_zoom <= 15 else 28.0)
	var positions := _station_visual_positions()
	for station_index in range(stations.size()):
		var station: Dictionary = stations[station_index]
		var position: Vector2 = positions[station_index]
		var key := "%d:%d" % [floori(position.x / cell_size), floori(position.y / cell_size)]
		if not groups_by_key.has(key):
			groups_by_key[key] = {
				"indices": [],
				"position": Vector2.ZERO,
				"operator_counts": {},
				"generation_counts": {},
			}
		var group: Dictionary = groups_by_key[key]
		var indices: Array = group.get("indices", [])
		indices.append(station_index)
		group["indices"] = indices
		group["position"] = (group.get("position", Vector2.ZERO) as Vector2) + position
		var operator_name := str(station.get("operator", "OUTRAS"))
		var operator_counts: Dictionary = group.get("operator_counts", {})
		operator_counts[operator_name] = int(operator_counts.get(operator_name, 0)) + 1
		group["operator_counts"] = operator_counts
		var generation_name := str(station.get("generation", "4G"))
		var generation_counts: Dictionary = group.get("generation_counts", {})
		generation_counts[generation_name] = int(generation_counts.get(generation_name, 0)) + 1
		group["generation_counts"] = generation_counts
		groups_by_key[key] = group
	var result: Array[Dictionary] = []
	for group_value in groups_by_key.values():
		var group: Dictionary = group_value
		var count: int = maxi(1, (group.get("indices", []) as Array).size())
		group["position"] = (group.get("position", Vector2.ZERO) as Vector2) / float(count)
		result.append(group)
	station_group_cache_key = cache_key
	station_group_cache = result
	station_group_rebuild_count += 1
	return station_group_cache


func _station_visual_positions() -> Array[Vector2]:
	var cache_key := "%d:%d:%d:%d:%d" % [
		station_data_revision,
		map_view_revision,
		_display_map_zoom(),
		roundi(size.x),
		roundi(size.y),
	]
	if station_position_cache_key == cache_key:
		return station_position_cache
	var result: Array[Vector2] = []
	for station in stations:
		result.append(
			_map_position(float(station.get("lat", 0.0)), float(station.get("lng", 0.0))) - drag_offset
		)
	station_position_cache_key = cache_key
	station_position_cache = result
	station_position_rebuild_count += 1
	return station_position_cache


func _visible_station_indices() -> Array[int]:
	var display_zoom := _display_map_zoom()
	var cache_key := "%d:%d:%d:%d:%d" % [
		station_data_revision,
		map_view_revision,
		display_zoom,
		roundi(size.x),
		roundi(size.y),
	]
	if station_visible_cache_key == cache_key:
		return station_visible_indices
	var positions := _station_visual_positions()
	var result: Array[int] = []
	var occupied: Dictionary = {}
	var accepted_positions: Array[Vector2] = []
	var marker_size := _station_marker_draw_size(false).x
	var cell_size := maxf(marker_size * 1.35, 46.0)
	var minimum_distance := marker_size * 1.12
	for station_index in range(stations.size()):
		var station: Dictionary = stations[station_index]
		if bool(station.get("is_index_cluster", false)):
			continue
		var position: Vector2 = positions[station_index]
		# A seleção é somente aparência. Visibilidade, culling e declutter usam
		# sempre o mesmo tamanho-base para que os demais pontos não saltem.
		var current_marker_size := _station_marker_draw_size(false)
		var marker_rect := Rect2(
			position - Vector2(current_marker_size.x * 0.76, current_marker_size.y * 1.18),
			Vector2(current_marker_size.x * 1.52, current_marker_size.y * 1.56)
		)
		if not Rect2(Vector2(14.0, 14.0), size - Vector2(28.0, 28.0)).encloses(marker_rect):
			continue
		if display_zoom >= 16:
			result.append(station_index)
			accepted_positions.append(position)
			continue
		var operator_key := str(_station_operator_identity(str(station.get("operator", ""))).get("key", "OUTRAS"))
		var cell_key := "%s:%d:%d" % [operator_key, floori(position.x / cell_size), floori(position.y / cell_size)]
		if occupied.has(cell_key):
			continue
		var overlaps_visible_marker := false
		for accepted_position in accepted_positions:
			if accepted_position.distance_to(position) < minimum_distance:
				overlaps_visible_marker = true
				break
		if overlaps_visible_marker:
			continue
		occupied[cell_key] = station_index
		result.append(station_index)
		accepted_positions.append(position)
	station_visible_cache_key = cache_key
	station_visible_indices = result
	station_source_count = stations.size()
	station_rendered_count = result.size()
	station_density_hidden_count = maxi(0, station_source_count - station_rendered_count)
	return station_visible_indices


func station_render_metrics() -> Dictionary:
	_visible_station_indices()
	return {
		"source_station_count": station_source_count,
		"rendered_station_count": station_rendered_count,
		"density_hidden_count": station_density_hidden_count,
	}

func _draw_station_cluster(group: Dictionary) -> void:
	var position: Vector2 = (group.get("position", Vector2.ZERO) as Vector2) + drag_offset
	var indices: Array = group.get("indices", [])
	if position.x < 4.0 or position.y < 4.0 or position.x > size.x - 4.0 or position.y > size.y - 4.0:
		return
	var operator_counts: Dictionary = group.get("operator_counts", {})
	var dominant_operator := "OUTRAS"
	var dominant_count := 0
	for operator_name in operator_counts.keys():
		var amount := int(operator_counts[operator_name])
		if amount > dominant_count:
			dominant_operator = str(operator_name)
			dominant_count = amount
	var accent := _operator_color(dominant_operator)
	var radius := clampf(12.0 + sqrt(float(indices.size())) * 1.4, 14.0, 24.0)
	var selected := selected_station_index >= 0 and indices.has(selected_station_index)
	draw_circle(position + Vector2(1.0, 2.0), radius + 2.0, Color(0.03, 0.12, 0.2, 0.20))
	draw_circle(position, radius + 2.0, Color.WHITE)
	draw_circle(position, radius, Color(accent.r, accent.g, accent.b, 0.94))
	draw_arc(position, radius - 3.0, -PI * 0.5, PI * 0.5, 20, Color("#ff7a00"), 2.0, true)
	if selected:
		draw_arc(position, radius + 5.0, 0.0, TAU, 32, Color("#0070b8"), 2.0, true)
	var font := get_theme_default_font()
	var count_text := str(indices.size())
	draw_string(font, position + Vector2(-14.0, 5.0), count_text, HORIZONTAL_ALIGNMENT_CENTER, 28.0, 12, Color.WHITE)

func _draw_map_legend() -> void:
	var legend_size := Vector2(430, 112)
	var legend_position := Vector2(14, maxf(12.0, size.y - legend_size.y - 34.0))
	var legend_style := StyleBoxFlat.new()
	legend_style.bg_color = Color(1, 1, 1, 0.94)
	legend_style.border_color = Color("#dbe5ee")
	legend_style.set_border_width_all(1)
	legend_style.set_corner_radius_all(7)
	draw_style_box(legend_style, Rect2(legend_position, legend_size))
	var font := get_theme_default_font()
	draw_string(font, legend_position + Vector2(12, 19), "Legenda", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#23364a"))
	var generation_x := legend_position.x + 12.0
	for generation_name in ["2G", "3G", "4G", "5G"]:
		draw_circle(Vector2(generation_x, legend_position.y + 37.0), 5.0, _generation_color(generation_name))
		draw_string(font, Vector2(generation_x + 9.0, legend_position.y + 41.0), generation_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#657487"))
		generation_x += 52.0
	_draw_operator_legend_items(legend_position + Vector2(12, 55), font)
	draw_string(font, legend_position + Vector2(12, 88), "ERB licenciada Anatel · não representa intensidade de sinal", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#657487"))


func _draw_operator_legend_items(origin: Vector2, font: Font) -> void:
	var x := origin.x
	for operator_name in _operator_legend_labels():
		var identity := _station_operator_identity("" if operator_name == "N/D" else operator_name)
		var color: Color = identity.get("color", Color("#697684"))
		draw_circle(Vector2(x + 6.0, origin.y + 6.0), 6.0, color)
		draw_arc(Vector2(x + 6.0, origin.y + 6.0), 6.0, 0.0, TAU, 20, Color.WHITE, 1.0, true)
		draw_string(font, Vector2(x + 15.0, origin.y + 10.0), operator_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#42566a"))
		x += 66.0 if operator_name in ["TIM", "VIVO", "N/D"] else 82.0


func _operator_legend_labels() -> Array[String]:
	return ["TIM", "CLARO", "VIVO", "OUTRAS", "N/D"]


func _generation_color(value: String) -> Color:
	match value.strip_edges().to_upper():
		"2G":
			return Color("#566b7f")
		"3G":
			return Color("#7b61d1")
		"5G":
			return Color("#0aa37f")
	return Color("#ff7a00")

func _draw_station_popup(station: Dictionary, position: Vector2) -> void:
	var panel_size := Vector2(366, 196)
	var panel_position := position + Vector2(18, -panel_size.y - 10)
	if panel_position.x + panel_size.x > size.x - 8:
		panel_position.x = size.x - panel_size.x - 8
	if panel_position.y < 8:
		panel_position.y = position.y + 18
	var rect := Rect2(panel_position, panel_size)
	draw_rect(rect, Color.WHITE, true)
	draw_rect(rect, Color("#dfe7ef"), false, 1.0)
	var font := get_theme_default_font()
	var bands: Array = station.get("bands", [])
	var lines := [
		"ERB %s | %s" % [
			str(station.get("id", station.get("code", "--"))),
			str(station.get("operator", "--")),
		],
		"Tecnologia: %s" % str(station.get("generation", generation)),
		"Cidade: %s | Bairro: %s" % [
			str(station.get("city", "--")),
			str(station.get("district", "--")),
		],
		"Endereco: %s" % str(station.get("address", "--")),
		"Faixas: %s MHz" % (", ".join(bands) if not bands.is_empty() else "--"),
		"Coordenadas: %.6f, %.6f" % [
			float(station.get("lat", 0.0)),
			float(station.get("lng", 0.0)),
		],
		"Fonte: Anatel | Base: %s" % dataset_updated_at,
	]
	for line_index in range(lines.size()):
		var line_color := _operator_color(str(station.get("operator", ""))) if line_index == 0 else Color("#121c28")
		draw_string(
			font,
			panel_position + Vector2(13, 24 + line_index * 21),
			str(lines[line_index]),
			HORIZONTAL_ALIGNMENT_LEFT,
			panel_size.x - 26,
			12,
			line_color
		)

func _map_position(latitude: float, longitude: float) -> Vector2:
	if map_ready and map_viewport_size.x > 0.0 and map_viewport_size.y > 0.0:
		var world_pixel := _lat_lng_to_world_pixel(latitude, longitude, _display_map_zoom())
		var raw := world_pixel - _display_map_top_left()
		return Vector2(
			size.x * raw.x / map_viewport_size.x,
			size.y * raw.y / map_viewport_size.y
		) + drag_offset
	return Vector2(-10000.0, -10000.0)

func _operator_color(operator_name: String) -> Color:
	return _station_operator_identity(operator_name).get("color", Color("#697684"))

func _lat_lng_to_world_pixel(lat: float, lng: float, zoom: int) -> Vector2:
	return GeoProjection.lat_lng_to_world_pixel(lat, lng, zoom)

func _world_pixel_to_lat_lng(point: Vector2, zoom: int) -> Vector2:
	return GeoProjection.world_pixel_to_lat_lng(point, zoom)

func _screen_to_world(point: Vector2) -> Vector2:
	var safe_size := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	var local_point := point - drag_offset
	return _display_map_top_left() + Vector2(
		local_point.x * map_viewport_size.x / safe_size.x,
		local_point.y * map_viewport_size.y / safe_size.y
	)

func _request_pan_navigation() -> void:
	_ensure_navigation_target()
	var safe_size := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	var world_delta := Vector2(
		drag_offset.x * map_viewport_size.x / safe_size.x,
		drag_offset.y * map_viewport_size.y / safe_size.y
	)
	navigation_target_top_left -= world_delta
	drag_offset = Vector2.ZERO
	var center_world := navigation_target_top_left + map_viewport_size * 0.5
	var center_geo := _world_pixel_to_lat_lng(center_world, navigation_target_zoom)
	navigation_loading = true
	loading_stage = "Atualizando a area selecionada..."
	navigation_requested.emit(center_geo.x, center_geo.y, navigation_target_zoom)
	_commit_navigation_preview_change()

func _request_zoom(anchor: Vector2, zoom_delta: int) -> void:
	_ensure_navigation_target()
	var current_target_zoom := navigation_target_zoom
	var next_zoom := clampi(current_target_zoom + zoom_delta, MIN_MAP_ZOOM, MAX_MAP_ZOOM)
	if next_zoom == current_target_zoom:
		return
	var safe_size := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	var anchor_ratio := Vector2(anchor.x / safe_size.x, anchor.y / safe_size.y)
	var anchor_world := navigation_target_top_left + Vector2(
		anchor_ratio.x * map_viewport_size.x,
		anchor_ratio.y * map_viewport_size.y
	)
	var anchor_geo := _world_pixel_to_lat_lng(anchor_world, current_target_zoom)
	var next_anchor_world := _lat_lng_to_world_pixel(anchor_geo.x, anchor_geo.y, next_zoom)
	var next_top_left := next_anchor_world - Vector2(
		anchor_ratio.x * map_viewport_size.x,
		anchor_ratio.y * map_viewport_size.y
	)
	var next_center := _world_pixel_to_lat_lng(
		next_top_left + map_viewport_size * 0.5,
		next_zoom
	)
	selected_cell_index = -1
	navigation_target_zoom = next_zoom
	navigation_target_top_left = next_top_left
	navigation_loading = true
	loading_stage = "Aproximando o mapa..."
	navigation_requested.emit(next_center.x, next_center.y, next_zoom)
	_commit_navigation_preview_change()

func _map_control_rect(index: int) -> Rect2:
	return Rect2(
		Vector2(16.0, 16.0 + float(index) * (MAP_CONTROL_SIZE + MAP_CONTROL_GAP)),
		Vector2(MAP_CONTROL_SIZE, MAP_CONTROL_SIZE)
	)

func _map_control_action(point: Vector2) -> String:
	if _map_control_rect(0).has_point(point):
		return "zoom_in"
	if _map_control_rect(1).has_point(point):
		return "zoom_out"
	if _map_control_rect(2).has_point(point):
		return "reset"
	return ""

func _activate_map_control(action: String) -> void:
	match action:
		"zoom_in":
			_request_zoom(size * 0.5, 1)
		"zoom_out":
			_request_zoom(size * 0.5, -1)
		"reset":
			selected_cell_index = -1
			navigation_target_active = true
			navigation_target_zoom = Config.DEFAULT_ZOOM
			var reset_center := _lat_lng_to_world_pixel(Config.DEFAULT_LATITUDE, Config.DEFAULT_LONGITUDE, navigation_target_zoom)
			navigation_target_top_left = reset_center - map_viewport_size * 0.5
			navigation_loading = true
			loading_stage = "Retornando para a regiao inicial..."
			reset_requested.emit()
			_commit_navigation_preview_change()

func _draw_map_controls() -> void:
	var font := get_theme_default_font()
	for index in range(3):
		var rect := _map_control_rect(index)
		draw_rect(rect, Color(1, 1, 1, 0.96), true)
		draw_rect(rect, Color("#cbd7e2"), false, 1.0)
		var center := rect.get_center()
		if index == 0:
			draw_line(center + Vector2(-7, 0), center + Vector2(7, 0), Color("#17344f"), 2.0, true)
			draw_line(center + Vector2(0, -7), center + Vector2(0, 7), Color("#17344f"), 2.0, true)
		elif index == 1:
			draw_line(center + Vector2(-7, 0), center + Vector2(7, 0), Color("#17344f"), 2.0, true)
		else:
			draw_circle(center, 8.0, Color.TRANSPARENT, false, 2.0, true)
			draw_circle(center, 2.5, Color("#17344f"))
			draw_line(center + Vector2(0, -12), center + Vector2(0, -7), Color("#17344f"), 1.5, true)
			draw_line(center + Vector2(0, 7), center + Vector2(0, 12), Color("#17344f"), 1.5, true)
			draw_line(center + Vector2(-12, 0), center + Vector2(-7, 0), Color("#17344f"), 1.5, true)
			draw_line(center + Vector2(7, 0), center + Vector2(12, 0), Color("#17344f"), 1.5, true)
	draw_string(
		font,
		Vector2(17, _map_control_rect(2).end.y + 20),
		"Z%d" % _display_map_zoom(),
		HORIZONTAL_ALIGNMENT_CENTER,
		MAP_CONTROL_SIZE,
		11,
		Color("#31465b")
	)

func _draw_navigation_loading() -> void:
	var panel_size := Vector2(226, 40)
	var panel_position := Vector2((size.x - panel_size.x) * 0.5, 14)
	draw_rect(Rect2(panel_position, panel_size), Color(1, 1, 1, 0.96), true)
	draw_rect(Rect2(panel_position, panel_size), Color("#cbd9e6"), false, 1.0)
	var spinner_center := panel_position + Vector2(22, 20)
	draw_arc(spinner_center, 8.0, 0.0, TAU, 24, Color("#d5e1ec"), 2.5, true)
	var start_angle := loading_phase * TAU - PI * 0.5
	draw_arc(spinner_center, 8.0, start_angle, start_angle + PI * 0.8, 12, Color("#0877bd"), 2.5, true)
	draw_string(
		get_theme_default_font(),
		panel_position + Vector2(39, 25),
		loading_stage,
		HORIZONTAL_ALIGNMENT_LEFT,
		panel_size.x - 48,
		11,
		Color("#20374e")
	)

func _draw_map_scale() -> void:
	var center_world := _screen_to_world(size * 0.5)
	var display_zoom := _display_map_zoom()
	var center_geo := _world_pixel_to_lat_lng(center_world, display_zoom)
	var meters_per_pixel := (
		156543.03392
		* cos(deg_to_rad(center_geo.x))
		/ pow(2.0, float(display_zoom))
	)
	var target_pixels := 110.0
	var target_km := meters_per_pixel * target_pixels / 1000.0
	var scale_km := 0.5
	for candidate in [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0]:
		if float(candidate) <= target_km:
			scale_km = float(candidate)
	var scale_pixels := scale_km * 1000.0 / maxf(meters_per_pixel, 0.01)
	var origin := Vector2((size.x - scale_pixels) * 0.5, size.y - 22)
	draw_line(origin, origin + Vector2(scale_pixels, 0), Color("#17344f"), 3.0, true)
	draw_line(origin, origin + Vector2(0, -6), Color("#17344f"), 2.0, true)
	draw_line(origin + Vector2(scale_pixels, 0), origin + Vector2(scale_pixels, -6), Color("#17344f"), 2.0, true)
	draw_string(
		get_theme_default_font(),
		origin + Vector2(0, -8),
		"%.1f km" % scale_km if scale_km < 1.0 else "%d km" % int(scale_km),
		HORIZONTAL_ALIGNMENT_CENTER,
		scale_pixels,
		10,
		Color("#17344f")
	)
