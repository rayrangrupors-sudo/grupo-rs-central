## Canvas visual e interativo do Mapa Grande.
##
## Responsabilidades: desenhar tiles, ERBs e veículos; controlar zoom,
## arraste, seleção, legendas e animações dos marcadores.
## Não realiza consultas de rede nem acessa estoque/API.
extends Control

const Config := preload("res://src/features/big_map/big_map_config.gd")
const GeoProjection := preload("res://src/features/big_map/map_projection.gd")
const VehicleStatus := preload("res://src/features/big_map/vehicle_status_resolver.gd")


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
var drag_offset := Vector2.ZERO
var drag_distance := 0.0
var visible_map_tiles: Dictionary = {}
var map_tile_loaded_count := 0
var map_tile_total_count := 0
var map_tile_size := 256
var tracking_motion: Dictionary = {}

const MIN_MAP_ZOOM := Config.MIN_ZOOM
const MAX_MAP_ZOOM := Config.MAX_ZOOM
const MAP_CONTROL_SIZE := 36.0
const MAP_CONTROL_GAP := 5.0
const TRACKING_ANIMATION_DURATION_MSEC := 850.0

func _init() -> void:
	custom_minimum_size = Vector2(720, 330)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	set_process(_tracking_animation_in_progress())

func _process(delta: float) -> void:
	if map_ready and not navigation_loading and not _tracking_animation_in_progress():
		set_process(false)
		return
	loading_phase = fmod(loading_phase + delta * 0.85, 1.0)
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
	var center_world := _screen_to_world(size * 0.5)
	var center_geo := _world_pixel_to_lat_lng(center_world, map_zoom)
	return {
		"center": {"lat": center_geo.x, "lng": center_geo.y},
		"zoom": map_zoom,
		"interactive": true,
	}

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

func set_map_texture(texture: Texture2D, zoom: int, top_left: Vector2, viewport_size: Vector2) -> void:
	map_texture = texture
	visible_map_tiles.clear()
	map_zoom = zoom
	map_top_left = top_left
	map_viewport_size = viewport_size
	map_ready = texture != null and viewport_size.x > 0.0 and viewport_size.y > 0.0
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
	visible_map_tiles.clear()
	for tile in tiles:
		var key := str(tile.get("key", ""))
		if key != "":
			visible_map_tiles[key] = tile.duplicate(true)
	map_zoom = zoom
	map_top_left = top_left
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
	queue_redraw()

func finish_map_tile_load(loaded_count: int, total_count: int) -> void:
	map_tile_loaded_count = loaded_count
	map_tile_total_count = total_count
	navigation_loading = false
	set_process(_tracking_animation_in_progress())
	queue_redraw()

func set_map_tile_progress(loaded_count: int, total_count: int, stage: String) -> void:
	map_tile_loaded_count = loaded_count
	map_tile_total_count = total_count
	loading_stage = stage
	navigation_loading = loaded_count < total_count
	set_process(navigation_loading or _tracking_animation_in_progress())
	queue_redraw()

func begin_map_load(
	stage: String = "Carregando mapa e analisando cobertura",
	preserve_current_map: bool = false
) -> int:
	load_generation += 1
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
		drag_offset = motion_event.position - drag_start
		drag_distance = maxf(drag_distance, drag_offset.length())
		selected_cell_index = -1
		selected_station_index = -1
		queue_redraw()
		accept_event()

func _nearest_station_index(point: Vector2) -> int:
	var nearest := -1
	var nearest_distance := INF
	for station_index in range(stations.size()):
		var station: Dictionary = stations[station_index]
		var position := _map_position(float(station.get("lat", 0.0)), float(station.get("lng", 0.0)))
		if position.x < 4.0 or position.y < 4.0 or position.x > size.x - 4.0 or position.y > size.y - 4.0:
			continue
		var radius := 18.0
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
			if candidate_position.distance_to(position) <= 24.0:
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
	var drawn_tiles := 0
	for tile_value in visible_map_tiles.values():
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile := tile_value as Dictionary
		var texture: Texture2D = tile.get("texture") as Texture2D
		if texture == null:
			continue
		var tile_position := Vector2(
			float(tile.get("x", 0)) * float(map_tile_size) - map_top_left.x,
			float(tile.get("y", 0)) * float(map_tile_size) - map_top_left.y
		) + drag_offset
		draw_texture_rect(
			texture,
			Rect2(tile_position, Vector2(map_tile_size, map_tile_size)),
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
	if show_stations:
		# Keep every tower visible as an individual marker. The map no longer
		# replaces nearby towers with count bubbles, so each ERB remains
		# directly selectable and the legend keeps its normal meaning.
		for station_index in range(stations.size()):
			_draw_station_marker(stations[station_index], station_index)
	if tracking_mode:
		for group_value in _tracking_visual_groups():
			var group: Dictionary = group_value
			var indices: Array = group.get("indices", [])
			if indices.size() > 1:
				_draw_tracking_cluster_marker(group)
			elif not indices.is_empty():
				var location_index := int(indices[0])
				_draw_tracking_marker(tracking_locations[location_index], location_index)
		_draw_tracking_legend()
	else:
		_draw_map_legend()
	draw_string(font, Vector2(18, size.y - 18), Config.TILE_ATTRIBUTION, HORIZONTAL_ALIGNMENT_LEFT, 300.0, 11, Color("#657487"))
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

func _draw_station_marker(station: Dictionary, station_index: int = -1) -> void:
	var position := _map_position(float(station.get("lat", 0.0)), float(station.get("lng", 0.0)))
	if position.x < -18.0 or position.y < -18.0 or position.x > size.x + 18.0 or position.y > size.y + 18.0:
		return
	# Pixel snapping keeps the glyph crisp and prevents fractional-coordinate shimmer.
	position = Vector2(roundf(position.x), roundf(position.y))
	var color := _operator_color(str(station.get("operator", "")))
	var selected := station_index == selected_station_index
	var generation_color := Color("#ff7a00") if str(station.get("generation", generation)) == "4G" else Color("#0a2b4a")
	if selected:
		draw_circle(position, 18.0, Color(0.0, 0.44, 0.72, 0.10))
		draw_arc(position, 18.0, 0.0, TAU, 32, Color("#0070b8"), 1.6, true)
	# Ground shadow and the tower's three-legged silhouette.
	draw_line(position + Vector2(-9, 11), position + Vector2(9, 11), Color(0.03, 0.12, 0.20, 0.24), 3.0, true)
	draw_line(position + Vector2(0, -13), position + Vector2(-8, 11), color, 2.4, true)
	draw_line(position + Vector2(0, -13), position + Vector2(8, 11), color, 2.4, true)
	draw_line(position + Vector2(0, -13), position + Vector2(0, 11), color, 2.2, true)
	draw_line(position + Vector2(-5, -1), position + Vector2(5, -1), color, 1.6, true)
	draw_line(position + Vector2(-6, 5), position + Vector2(6, 5), color, 1.6, true)
	draw_line(position + Vector2(-9, 11), position + Vector2(9, 11), color, 2.4, true)
	# Small generation signal above the mast; it is not a second marker.
	draw_arc(position + Vector2(0, -14), 6.0, -PI * 0.82, -PI * 0.18, 12, generation_color, 1.6, true)
	draw_arc(position + Vector2(0, -14), 10.0, -PI * 0.78, -PI * 0.22, 14, Color(generation_color.r, generation_color.g, generation_color.b, 0.55), 1.2, true)

func _draw_tracking_marker(location: Dictionary, location_index: int = -1) -> void:
	var target_geo := _tracking_target_geo(location)
	if is_zero_approx(target_geo.x) and is_zero_approx(target_geo.y):
		return
	var position := _tracking_map_position(location_index, location)
	if position.x < -22.0 or position.y < -22.0 or position.x > size.x + 22.0 or position.y > size.y + 22.0:
		return
	var color := _tracking_marker_color(location)
	var selected := location_index == selected_tracking_index
	_draw_tracking_pin(position, color, _tracking_plate_label(location), selected, 0)

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
	_draw_tracking_pin(position, color, _tracking_plate_label(representative), selected, indices.size())

func _tracking_plate_label(location: Dictionary) -> String:
	var plate := str(location.get("plate", "")).strip_edges()
	if plate == "":
		plate = str(location.get("serial", "Aparelho")).strip_edges()
	return plate if plate != "" else "Aparelho"

func _draw_tracking_pin(position: Vector2, color: Color, plate: String, selected: bool, badge_count: int) -> void:
	# Pino de rastreamento moderno: etiqueta legivel, corpo colorido bem
	# definido e um veiculo grande no centro, sem excesso de contornos.
	var anchor := Vector2(roundf(position.x), roundf(position.y))
	var pin_center := anchor + Vector2(0.0, -16.0)
	var label_width := clampf(float(plate.length()) * 7.4 + 42.0, 96.0, 182.0)
	var label_size := Vector2(label_width, 30.0)
	var label_position := Vector2(roundf(anchor.x - label_size.x * 0.5), roundf(anchor.y - 75.0))
	var label_style := StyleBoxFlat.new()
	label_style.bg_color = Color("#0d263b")
	label_style.border_color = Color("#52728a") if not selected else Color("#19a8e0")
	label_style.set_border_width_all(1)
	label_style.set_corner_radius_all(10)
	label_style.shadow_color = Color(0.02, 0.08, 0.14, 0.34)
	label_style.shadow_size = 6
	draw_style_box(label_style, Rect2(label_position, label_size))
	var font := get_theme_default_font()
	draw_circle(label_position + Vector2(14.0, 15.0), 4.0, color)
	draw_string(font, label_position + Vector2(25.0, 20.0), plate, HORIZONTAL_ALIGNMENT_LEFT, label_size.x - 32.0, 12, Color("#f7fbff"))
	# Haste de ligacao curta e discreta entre a placa e a localizacao exata.
	draw_line(Vector2(anchor.x, label_position.y + label_size.y), pin_center + Vector2(0.0, -23.0), Color(0.05, 0.15, 0.23, 0.55), 1.2, true)
	if selected:
		draw_circle(pin_center, 31.0, Color(color.r, color.g, color.b, 0.14))
		draw_arc(pin_center, 30.0, 0.0, TAU, 48, Color("#19a8e0"), 2.0, true)
	else:
		draw_circle(pin_center, 26.0, Color(color.r, color.g, color.b, 0.10))
	# Contorno branco faz o pino destacar tanto em ruas claras quanto escuras.
	var outer := PackedVector2Array([
		pin_center + Vector2(-16.0, -11.0), pin_center + Vector2(-11.0, -20.0),
		pin_center + Vector2(0.0, -24.0), pin_center + Vector2(11.0, -20.0),
		pin_center + Vector2(16.0, -11.0), pin_center + Vector2(16.0, -1.0),
		pin_center + Vector2(10.0, 8.0), pin_center + Vector2(0.0, 31.0),
		pin_center + Vector2(-10.0, 8.0), pin_center + Vector2(-16.0, -1.0),
	])
	var shadow := PackedVector2Array()
	for point in outer:
		shadow.append(point + Vector2(1.5, 3.0))
	draw_colored_polygon(shadow, Color(0.02, 0.08, 0.14, 0.30))
	draw_colored_polygon(outer, Color.WHITE)
	var body := PackedVector2Array([
		pin_center + Vector2(-13.0, -10.0), pin_center + Vector2(-9.0, -17.0),
		pin_center + Vector2(0.0, -20.0), pin_center + Vector2(9.0, -17.0),
		pin_center + Vector2(13.0, -10.0), pin_center + Vector2(13.0, -1.0),
		pin_center + Vector2(8.0, 6.0), pin_center + Vector2(0.0, 25.0),
		pin_center + Vector2(-8.0, 6.0), pin_center + Vector2(-13.0, -1.0),
	])
	draw_colored_polygon(body, color)
	# Disco branco e carro navy: leitura imediata mesmo quando o mapa esta cheio.
	var icon_center := pin_center + Vector2(0.0, -7.0)
	draw_circle(icon_center, 12.5, Color.WHITE)
	var car := PackedVector2Array([
		icon_center + Vector2(-8.0, -2.0), icon_center + Vector2(-5.0, -7.0),
		icon_center + Vector2(4.5, -7.0), icon_center + Vector2(8.0, -2.0),
		icon_center + Vector2(8.0, 5.0), icon_center + Vector2(-8.0, 5.0),
	])
	draw_colored_polygon(car, Color("#12344e"))
	draw_colored_polygon(PackedVector2Array([
		icon_center + Vector2(-4.0, -5.5), icon_center + Vector2(3.5, -5.5),
		icon_center + Vector2(5.0, -2.0), icon_center + Vector2(-5.0, -2.0),
	]), Color("#d8eef7"))
	draw_circle(icon_center + Vector2(-4.5, 5.0), 2.0, Color("#12344e"))
	draw_circle(icon_center + Vector2(4.5, 5.0), 2.0, Color("#12344e"))
	if badge_count > 1:
		var badge_position := pin_center + Vector2(20.0, -25.0)
		draw_circle(badge_position + Vector2(1.0, 2.0), 12.0, Color(0.02, 0.08, 0.14, 0.28))
		draw_circle(badge_position, 12.0, Color("#0d2941"))
		draw_arc(badge_position, 12.0, 0.0, TAU, 24, Color.WHITE, 1.0, true)
		draw_string(font, badge_position + Vector2(-8.0, 4.0), str(badge_count), HORIZONTAL_ALIGNMENT_CENTER, 16.0, 11, Color.WHITE)

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
	var legend_size := Vector2(286, 86)
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
	draw_string(font, legend_position + Vector2(12, 67), "Bolha numerada: clique para alternar aparelhos", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#657487"))

func _station_visual_groups() -> Array[Dictionary]:
	var groups_by_key: Dictionary = {}
	var cell_size := 52.0 if map_zoom <= 13 else (38.0 if map_zoom <= 15 else 28.0)
	for station_index in range(stations.size()):
		var station: Dictionary = stations[station_index]
		var position := _map_position(float(station.get("lat", 0.0)), float(station.get("lng", 0.0)))
		if position.x < 4.0 or position.y < 4.0 or position.x > size.x - 4.0 or position.y > size.y - 4.0:
			continue
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
	return result

func _draw_station_cluster(group: Dictionary) -> void:
	var position: Vector2 = group.get("position", Vector2.ZERO)
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
	var legend_size := Vector2(236, 88)
	var legend_position := Vector2(14, maxf(12.0, size.y - legend_size.y - 34.0))
	var legend_style := StyleBoxFlat.new()
	legend_style.bg_color = Color(1, 1, 1, 0.94)
	legend_style.border_color = Color("#dbe5ee")
	legend_style.set_border_width_all(1)
	legend_style.set_corner_radius_all(7)
	draw_style_box(legend_style, Rect2(legend_position, legend_size))
	var font := get_theme_default_font()
	draw_string(font, legend_position + Vector2(12, 19), "Legenda", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#23364a"))
	draw_circle(legend_position + Vector2(17, 37), 5.0, Color("#ff7a00"))
	draw_string(font, legend_position + Vector2(29, 41), "4G LTE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#657487"))
	draw_circle(legend_position + Vector2(91, 37), 5.0, Color("#0a2b4a"))
	draw_string(font, legend_position + Vector2(103, 41), "2G GSM", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#657487"))
	var operator_x := legend_position.x + 12.0
	for operator_name in ["TIM", "CLARO", "VIVO", "OUTRAS"]:
		draw_circle(Vector2(operator_x, legend_position.y + 57.0), 4.0, _operator_color(operator_name))
		draw_string(font, Vector2(operator_x + 9.0, legend_position.y + 60.0), operator_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#657487"))
		operator_x += 57.0 if operator_name != "OUTRAS" else 62.0

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
		var world_pixel := _lat_lng_to_world_pixel(latitude, longitude, map_zoom)
		var raw := world_pixel - map_top_left
		return Vector2(
			size.x * raw.x / map_viewport_size.x,
			size.y * raw.y / map_viewport_size.y
		) + drag_offset
	return Vector2(-10000.0, -10000.0)

func _operator_color(operator_name: String) -> Color:
	match operator_name.to_upper():
		"CLARO":
			return Color("#df3434")
		"TIM":
			return Color("#2f83ff")
		"VIVO":
			return Color("#8b5ad9")
	return Color("#7d8792")

func _lat_lng_to_world_pixel(lat: float, lng: float, zoom: int) -> Vector2:
	return GeoProjection.lat_lng_to_world_pixel(lat, lng, zoom)

func _world_pixel_to_lat_lng(point: Vector2, zoom: int) -> Vector2:
	return GeoProjection.world_pixel_to_lat_lng(point, zoom)

func _screen_to_world(point: Vector2) -> Vector2:
	var safe_size := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	var local_point := point - drag_offset
	return map_top_left + Vector2(
		local_point.x * map_viewport_size.x / safe_size.x,
		local_point.y * map_viewport_size.y / safe_size.y
	)

func _request_pan_navigation() -> void:
	if navigation_loading:
		drag_offset = Vector2.ZERO
		queue_redraw()
		return
	var safe_size := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	var world_delta := Vector2(
		drag_offset.x * map_viewport_size.x / safe_size.x,
		drag_offset.y * map_viewport_size.y / safe_size.y
	)
	var center_world := map_top_left + map_viewport_size * 0.5 - world_delta
	var center_geo := _world_pixel_to_lat_lng(center_world, map_zoom)
	navigation_loading = true
	loading_stage = "Atualizando a area selecionada..."
	navigation_requested.emit(center_geo.x, center_geo.y, map_zoom)
	queue_redraw()

func _request_zoom(anchor: Vector2, zoom_delta: int) -> void:
	if navigation_loading:
		return
	var next_zoom := clampi(map_zoom + zoom_delta, MIN_MAP_ZOOM, MAX_MAP_ZOOM)
	if next_zoom == map_zoom:
		return
	var anchor_world := _screen_to_world(anchor)
	var anchor_geo := _world_pixel_to_lat_lng(anchor_world, map_zoom)
	var next_anchor_world := _lat_lng_to_world_pixel(anchor_geo.x, anchor_geo.y, next_zoom)
	var safe_size := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	var anchor_ratio := Vector2(anchor.x / safe_size.x, anchor.y / safe_size.y)
	var next_top_left := next_anchor_world - Vector2(
		anchor_ratio.x * map_viewport_size.x,
		anchor_ratio.y * map_viewport_size.y
	)
	var next_center := _world_pixel_to_lat_lng(
		next_top_left + map_viewport_size * 0.5,
		next_zoom
	)
	selected_cell_index = -1
	navigation_loading = true
	loading_stage = "Aproximando o mapa..."
	navigation_requested.emit(next_center.x, next_center.y, next_zoom)
	queue_redraw()

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
			if navigation_loading:
				return
			selected_cell_index = -1
			navigation_loading = true
			loading_stage = "Retornando para a regiao inicial..."
			reset_requested.emit()
			queue_redraw()

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
		"Z%d" % map_zoom,
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
	var center_geo := _world_pixel_to_lat_lng(center_world, map_zoom)
	var meters_per_pixel := (
		156543.03392
		* cos(deg_to_rad(center_geo.x))
		/ pow(2.0, float(map_zoom))
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
