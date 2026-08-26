## Controlador reconstruido do Mapa Grande.
##
## A interface vive em BigMapTrackingView, os dados continuam vindo das
## integracoes autenticadas do dashboard e o canvas recebe somente estado
## pronto para desenhar. Atualizacoes comuns nao recarregam tiles nem ERBs.
extends "res://src/inventory_dashboard.gd"

const TrackingView := preload("res://src/features/big_map/big_map_tracking_view.gd")
const VehicleStatusResolver := preload("res://src/features/big_map/vehicle_status_resolver.gd")
const TrackingAnatelCoverage := preload("res://src/anatel_coverage.gd")
const TrackingNationalErbIndex := preload("res://src/features/big_map/anatel_national_index.gd")

const TRACKING_POLL_MOVING_SECONDS := 5.0
const TRACKING_POLL_DEFAULT_SECONDS := 20.0

var tracking_view: VBoxContainer
var tracking_last_latency_ms := -1
var tracking_last_success_at := ""
var tracking_last_query_signature := ""
var tracking_last_map_signature := ""
var tracking_had_map_rows := false
var tracking_erb_area_stations: Array[Dictionary] = []
var tracking_erb_metadata: Dictionary = {}
var tracking_selected_station: Dictionary = {}
var tracking_last_focused_query_signature := ""
var tracking_query_ambiguous := false
var tracking_national_erb_index: RefCounted
var tracking_erb_index_mode := ""
var tracking_erb_query_generation := 0
var tracking_last_erb_query_msec := -1
var tracking_cancelled_erb_query_count := 0
var tracking_erb_query_coordinator_running := false
var tracking_erb_query_in_flight := false
var tracking_erb_pending_request: Dictionary = {}
var tracking_erb_query_finished_generation := 0
var tracking_erb_query_requested_count := 0
var tracking_erb_query_actual_count := 0
var tracking_erb_query_coalesced_count := 0
var tracking_erb_query_stale_count := 0
var tracking_erb_latest_request_latency_msec := -1
var tracking_query_trigger_by_generation: Dictionary = {}


func _setup_st310_location_poll_timer() -> void:
	super._setup_st310_location_poll_timer()
	_update_tracking_poll_interval()


func _show_vehicle_location_monitor() -> void:
	_set_page_context("vehicle_location", "Mapa Grande", "OpenStreetMap, ERBs Anatel e rastreamento operacional")
	_set_content_margins(28, 14, 28, 16)
	_reset_tracking_start_state()
	_set_content(_build_vehicle_location_view())
	_apply_vehicle_location_filters()
	call_deferred("_ensure_vehicle_location_map_ready")


func _reset_tracking_start_state() -> void:
	vehicle_location_query_queue.clear()
	vehicle_location_rows.clear()
	vehicle_location_filtered_rows.clear()
	vehicle_location_selected.clear()
	tracking_selected_station.clear()
	tracking_last_focused_query_signature = ""
	tracking_last_query_signature = ""
	tracking_had_map_rows = false
	if vehicle_location_plate_input != null and is_instance_valid(vehicle_location_plate_input):
		vehicle_location_plate_input.clear()
	if vehicle_location_map_canvas != null and is_instance_valid(vehicle_location_map_canvas):
		var empty_rows: Array[Dictionary] = []
		vehicle_location_map_canvas.set_tracking_locations(empty_rows)


func _show_smart_4g_monitor() -> void:
	if not _branch_supports_monitor_4g():
		_show_warning("Mapa Grande", "Este recurso esta disponivel somente para a base de Imperatriz.")
		return
	_show_vehicle_location_monitor()


func _build_vehicle_location_view() -> Control:
	# No Mapa Grande a consulta remota somente começa por Adicionar ou Enter.
	# Isso evita que o debounce de text_changed dispute geração/estado com o
	# gesto explícito e garante que a fila seja consolidada primeiro.
	vehicle_location_debounce_enabled = false
	vehicle_location_api_exclusive = true
	vehicle_location_queue_after_api_success_only = true
	tracking_view = TrackingView.new()
	vehicle_location_view_root = tracking_view
	vehicle_location_plate_input = tracking_view.query_input
	vehicle_location_monitor_select = tracking_view.monitor_select
	vehicle_location_status_label = tracking_view.status_label
	vehicle_location_updated_label = tracking_view.updated_label
	# A view nova usa metric_labels; não crie um Label legado sem parent.
	vehicle_location_summary_label = null
	vehicle_location_list_body = tracking_view.list_body
	vehicle_location_details_body = tracking_view.details_body
	vehicle_location_details_panel = tracking_view.details_panel
	vehicle_location_list_panel = tracking_view.list_panel
	vehicle_location_map_list_toggle = tracking_view.list_toggle
	vehicle_location_queue_body = tracking_view.queue_body
	vehicle_location_queue_count_label = tracking_view.queue_count_label
	vehicle_location_add_button = tracking_view.add_button
	vehicle_location_map_canvas = tracking_view.map_canvas
	vehicle_location_summary_value_labels = tracking_view.metric_labels
	vehicle_location_list_expanded = false

	tracking_view.query_input.text_changed.connect(_on_vehicle_location_query_changed)
	tracking_view.query_input.gui_input.connect(_on_tracking_query_input)
	tracking_view.add_button.pressed.connect(_on_tracking_add_pressed)
	tracking_view.clear_queue_button.pressed.connect(_clear_vehicle_location_queue)
	tracking_view.monitor_select.item_selected.connect(_on_tracking_filter_selected)
	tracking_view.camera_lock_check.toggled.connect(_on_tracking_camera_lock_toggled)
	tracking_view.erb_layer_check.toggled.connect(_on_tracking_erb_layer_toggled)
	tracking_view.erb_operator_select.item_selected.connect(_on_tracking_erb_filter_selected)
	tracking_view.erb_generation_select.item_selected.connect(_on_tracking_erb_filter_selected)
	tracking_view.erb_city_select.item_selected.connect(_on_tracking_erb_filter_selected)
	tracking_view.erb_status_select.item_selected.connect(_on_tracking_erb_filter_selected)
	tracking_view.basemap_select.item_selected.connect(_on_tracking_basemap_selected)
	tracking_view.refresh_button.pressed.connect(_on_tracking_manual_refresh)
	tracking_view.list_toggle.pressed.connect(_toggle_vehicle_location_list)
	vehicle_location_map_canvas.tracking_selected.connect(_on_vehicle_location_map_selected)
	vehicle_location_map_canvas.station_selected.connect(_on_vehicle_location_station_selected)
	vehicle_location_map_canvas.navigation_requested.connect(_on_vehicle_location_map_navigation)
	vehicle_location_map_canvas.reset_requested.connect(_on_vehicle_location_map_reset)
	_refresh_vehicle_location_queue_ui()
	_render_vehicle_location_details({})
	tracking_view.set_query_state("idle")
	_update_tracking_runtime("Informe uma placa, número de série ou cliente para iniciar", MUTED)
	call_deferred("_initialize_tracking_erb_layer")
	return tracking_view


func _on_vehicle_location_query_changed(value: String) -> void:
	super._on_vehicle_location_query_changed(value)
	tracking_query_trigger_by_generation[vehicle_location_query_generation] = "debounce"
	if tracking_view == null or not is_instance_valid(tracking_view) or not vehicle_location_query_queue.is_empty():
		return
	var descriptor := vehicle_location_integration.describe_location_query(value)
	if str(descriptor.get("normalized", "")) == "":
		tracking_view.set_query_state("idle")
	elif bool(descriptor.get("valid", false)):
		tracking_view.set_query_state("loading")


func _on_tracking_add_pressed() -> void:
	_add_vehicle_location_query()
	vehicle_location_query_trigger = "button"
	tracking_query_trigger_by_generation[vehicle_location_query_generation] = "button"


func _on_tracking_query_input(event: InputEvent) -> void:
	var is_submit: bool = event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)
	_on_vehicle_location_query_input(event)
	if is_submit:
		vehicle_location_query_trigger = "enter"
		tracking_query_trigger_by_generation[vehicle_location_query_generation] = "enter"


func _on_tracking_manual_refresh() -> void:
	vehicle_location_query_trigger = "manual_refresh"
	_refresh_vehicle_location_view(-1)


func _on_tracking_filter_selected(_index: int) -> void:
	_update_tracking_poll_interval()
	_apply_vehicle_location_filters()


func _on_tracking_camera_lock_toggled(enabled: bool) -> void:
	if not enabled:
		return
	var rows := _vehicle_location_rows_for_map()
	if rows.is_empty():
		return
	vehicle_location_map_generation += 1
	_reload_vehicle_location_map(vehicle_location_map_generation, rows, _vehicle_location_map_view(rows))


func _on_tracking_erb_layer_toggled(enabled: bool) -> void:
	if vehicle_location_map_canvas != null and is_instance_valid(vehicle_location_map_canvas):
		vehicle_location_map_canvas.set_station_visibility(enabled)


func _on_tracking_erb_filter_selected(_index: int) -> void:
	_apply_tracking_erb_filters()


func _on_tracking_basemap_selected(_index: int) -> void:
	if vehicle_location_map_canvas == null:
		return
	# Compatibilidade do sinal público da view. OSM é único e selecionar o
	# controle não provoca reload, troca de câmera ou reconstrução do canvas.
	vehicle_location_map_canvas.set_basemap(BigMapConfig.DEFAULT_BASEMAP)


func _initialize_tracking_erb_layer() -> void:
	tracking_national_erb_index = TrackingNationalErbIndex.new()
	var national_loaded: Dictionary = tracking_national_erb_index.call("load_manifest")
	if bool(national_loaded.get("ok", false)):
		tracking_erb_index_mode = "national_partitioned"
		tracking_erb_metadata = (national_loaded.get("metadata", {}) as Dictionary).duplicate(true)
		tracking_erb_metadata["manifest_sha256"] = str(national_loaded.get("manifest_sha256", ""))
		_update_tracking_erb_source_state()
		var national_view := vehicle_location_map_canvas.current_map_view() if vehicle_location_map_canvas != null else {}
		if national_view.is_empty():
			national_view = _vehicle_location_map_view([])
		await _refresh_tracking_erb_area(national_view)
		return

	# O catálogo regional só permanece como fallback explícito durante a
	# migração. Ele nunca é apresentado como catálogo nacional.
	_ensure_smart_4g_anatel()
	if smart_4g_anatel == null:
		_set_tracking_erb_source_error(str(national_loaded.get("message", "Catálogo Anatel indisponível.")))
		return
	var loaded: Dictionary = smart_4g_anatel.call("load_snapshot", TrackingAnatelCoverage.REGIONAL_DATA_PATH)
	if not bool(loaded.get("ok", false)):
		_set_tracking_erb_source_error(str(loaded.get("message", "Catálogo Anatel indisponível.")))
		return
	tracking_erb_index_mode = "regional_fallback"
	tracking_erb_metadata = (loaded.get("metadata", {}) as Dictionary).duplicate(true)
	_update_tracking_erb_source_state()
	var view := vehicle_location_map_canvas.current_map_view() if vehicle_location_map_canvas != null else {}
	if view.is_empty():
		view = _vehicle_location_map_view([])
	await _refresh_tracking_erb_area(view)


func _set_tracking_erb_source_error(message: String) -> void:
	if tracking_view == null:
		return
	tracking_view.set_erb_source(
		"ERBs: %s" % message,
		"A camada foi mantida vazia; nenhuma coordenada não verificada é exibida.",
		RED
	)


func _update_tracking_erb_source_state() -> void:
	if tracking_view == null:
		return
	var source_date := str(tracking_erb_metadata.get("source_last_modified", tracking_erb_metadata.get("generated_at", ""))).strip_edges()
	var scope := str(tracking_erb_metadata.get("coverage", "Recorte regional")).strip_edges()
	var station_count := int(tracking_erb_metadata.get("unique_station_generations", tracking_erb_metadata.get("unique_stations", 0)))
	var physical_count := int(tracking_erb_metadata.get("unique_physical_stations", 0))
	var count_text := "%d registros estação/geração" % station_count
	if physical_count > 0:
		count_text += " · %d ERBs físicas" % physical_count
	tracking_view.set_erb_source(
		"Anatel SMP · %s · fonte %s · %s" % [scope, _tracking_source_value(source_date), count_text],
		"Licenciamento/presença de ERB não representa intensidade de sinal em tempo real.",
		GREEN
	)
	tracking_view.erb_source_label.tooltip_text = "%s\nSHA-256 ZIP: %s\nSHA-256 índice: %s\nSHA-256 manifesto: %s\nRegra: %s" % [
		str(tracking_erb_metadata.get("source_url", "")),
		str(tracking_erb_metadata.get("source_zip_sha256", "")),
		str(tracking_erb_metadata.get("index_content_sha256", "não aplicável ao fallback regional")),
		str(tracking_erb_metadata.get("manifest_sha256", "não aplicável ao fallback regional")),
		str(tracking_erb_metadata.get("selection_rule", "")),
	]


func _refresh_tracking_erb_area(view: Dictionary, expected_map_generation: int = -1) -> void:
	if vehicle_location_map_canvas == null:
		tracking_erb_area_stations.clear()
		_apply_tracking_erb_filters()
		return
	if tracking_erb_index_mode == "national_partitioned" and tracking_national_erb_index == null:
		_apply_tracking_erb_filters()
		return
	if tracking_erb_index_mode != "national_partitioned" and smart_4g_anatel == null:
		_apply_tracking_erb_filters()
		return
	var center: Dictionary = view.get("center", {"lat": BigMapConfig.DEFAULT_LATITUDE, "lng": BigMapConfig.DEFAULT_LONGITUDE})
	var zoom := clampi(int(view.get("zoom", BigMapConfig.DEFAULT_ZOOM)), BigMapConfig.MIN_ZOOM, BigMapConfig.MAX_ZOOM)
	var viewport := Vector2(maxf(vehicle_location_map_canvas.size.x, 720.0), maxf(vehicle_location_map_canvas.size.y, 360.0))
	var center_world := BigMapProjection.lat_lng_to_world_pixel(float(center.get("lat", BigMapConfig.DEFAULT_LATITUDE)), float(center.get("lng", BigMapConfig.DEFAULT_LONGITUDE)), zoom)
	var padding := Vector2(64.0, 64.0)
	var north_west := BigMapProjection.world_pixel_to_lat_lng(center_world - viewport * 0.5 - padding, zoom)
	var south_east := BigMapProjection.world_pixel_to_lat_lng(center_world + viewport * 0.5 + padding, zoom)
	var min_lat := minf(north_west.x, south_east.x)
	var max_lat := maxf(north_west.x, south_east.x)
	var min_lng := minf(north_west.y, south_east.y)
	var max_lng := maxf(north_west.y, south_east.y)
	if tracking_erb_index_mode == "national_partitioned" and tracking_national_erb_index != null:
		tracking_erb_query_generation += 1
		var request_generation := tracking_erb_query_generation
		tracking_erb_query_requested_count += 1
		if tracking_erb_query_coordinator_running:
			tracking_erb_query_coalesced_count += 1
		tracking_erb_pending_request = {
			"generation": request_generation,
			"expected_map_generation": expected_map_generation,
			"requested_msec": Time.get_ticks_msec(),
			"bounds": {
				"min_lat": min_lat,
				"max_lat": max_lat,
				"min_lng": min_lng,
				"max_lng": max_lng,
			},
			"zoom": zoom,
		}
		if not tracking_erb_query_coordinator_running:
			tracking_erb_query_coordinator_running = true
			call_deferred("_drain_tracking_erb_queries")
		while request_generation == tracking_erb_query_generation \
				and tracking_erb_query_finished_generation < request_generation:
			await (Engine.get_main_loop() as SceneTree).process_frame
		return
	tracking_erb_query_generation += 1
	tracking_erb_area_stations.clear()
	var source_stations: Array = smart_4g_anatel.get("stations")
	for raw_station in source_stations:
		if typeof(raw_station) != TYPE_DICTIONARY:
			continue
		var station := raw_station as Dictionary
		var latitude := float(station.get("lat", 0.0))
		var longitude := float(station.get("lng", 0.0))
		if latitude >= min_lat and latitude <= max_lat and longitude >= min_lng and longitude <= max_lng:
			tracking_erb_area_stations.append(station.duplicate(true))
	_populate_tracking_erb_filters()
	_apply_tracking_erb_filters()


func _drain_tracking_erb_queries() -> void:
	# Política latest-only: no máximo uma tarefa em voo e uma solicitação
	# pendente, substituída por qualquer gesto mais recente.
	while not tracking_erb_pending_request.is_empty():
		var request := tracking_erb_pending_request.duplicate(true)
		tracking_erb_pending_request.clear()
		tracking_erb_query_in_flight = true
		tracking_erb_query_actual_count += 1
		var task_started_msec := Time.get_ticks_msec()
		var task_state := {}
		var task_id := WorkerThreadPool.add_task(
			Callable(tracking_national_erb_index, "query_viewport_threadsafe_to").bind(
				request.get("bounds", {}) as Dictionary,
				int(request.get("zoom", BigMapConfig.DEFAULT_ZOOM)),
				{},
				task_state
			),
			true,
			"Mapa Grande: consultar ERBs nacionais"
		)
		while not WorkerThreadPool.is_task_completed(task_id):
			await (Engine.get_main_loop() as SceneTree).process_frame
		WorkerThreadPool.wait_for_task_completion(task_id)
		tracking_erb_query_in_flight = false
		tracking_last_erb_query_msec = Time.get_ticks_msec() - task_started_msec
		var request_generation := int(request.get("generation", 0))
		var expected_map_generation := int(request.get("expected_map_generation", -1))
		var stale := request_generation != tracking_erb_query_generation \
				or (expected_map_generation >= 0 and expected_map_generation != vehicle_location_map_generation)
		if stale:
			tracking_cancelled_erb_query_count += 1
			tracking_erb_query_stale_count += 1
			tracking_erb_query_finished_generation = maxi(tracking_erb_query_finished_generation, request_generation)
			continue
		tracking_erb_latest_request_latency_msec = Time.get_ticks_msec() - int(request.get("requested_msec", Time.get_ticks_msec()))
		var result: Dictionary = task_state.get("result", {})
		if not bool(result.get("ok", false)):
			_set_tracking_erb_source_error(str(result.get("message", "Falha ao consultar células nacionais.")))
			_apply_tracking_erb_filters()
			tracking_erb_query_finished_generation = maxi(tracking_erb_query_finished_generation, request_generation)
			continue
		var next_stations: Array[Dictionary] = []
		for value in result.get("stations", []) as Array:
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var station := value as Dictionary
			if bool(station.get("is_index_cluster", false)):
				continue
			next_stations.append(station.duplicate(true))
		tracking_erb_area_stations = next_stations
		_populate_tracking_erb_filters()
		_apply_tracking_erb_filters()
		tracking_erb_query_finished_generation = maxi(tracking_erb_query_finished_generation, request_generation)
	tracking_erb_query_in_flight = false
	tracking_erb_query_coordinator_running = false


func _tracking_erb_query_state() -> Dictionary:
	return {
		"requested": tracking_erb_query_requested_count,
		"actual_queries": tracking_erb_query_actual_count,
		"coalesced": tracking_erb_query_coalesced_count,
		"stale_discarded": tracking_erb_query_stale_count,
		"in_flight": tracking_erb_query_in_flight,
		"pending": not tracking_erb_pending_request.is_empty(),
		"last_query_msec": tracking_last_erb_query_msec,
		"latest_request_latency_msec": tracking_erb_latest_request_latency_msec,
	}


func _populate_tracking_erb_filters() -> void:
	if tracking_view == null:
		return
	var operators: Array[String] = []
	var generations: Array[String] = []
	var cities: Array[String] = []
	var statuses: Array[String] = []
	for station in tracking_erb_area_stations:
		if bool(station.get("is_index_cluster", false)):
			_tracking_append_entry_filter_values(operators, station.get("operators", []))
			_tracking_append_entry_filter_values(generations, station.get("generations", []))
			_tracking_append_entry_filter_values(cities, station.get("cities", []))
			_tracking_append_entry_filter_values(statuses, station.get("statuses", []))
		else:
			_tracking_append_unique(operators, str(station.get("operator", "")))
			_tracking_append_unique(generations, str(station.get("generation", "")))
			_tracking_append_unique(cities, str(station.get("city", "")))
			_tracking_append_unique(statuses, str(station.get("status", "")))
	tracking_view.set_erb_filter_values(operators, generations, cities, statuses)


func _tracking_append_entry_filter_values(values: Array[String], source: Variant) -> void:
	if typeof(source) != TYPE_ARRAY:
		return
	for value in source as Array:
		_tracking_append_unique(values, str(value))


func _tracking_append_unique(values: Array[String], value: String) -> void:
	var clean := value.strip_edges()
	if clean not in values:
		values.append(clean)


func _apply_tracking_erb_filters() -> void:
	if tracking_view == null or vehicle_location_map_canvas == null:
		return
	var filters: Dictionary = tracking_view.selected_erb_filters()
	var filtered: Array[Dictionary] = []
	if tracking_erb_index_mode == "national_partitioned" and tracking_national_erb_index != null:
		filtered = tracking_national_erb_index.call("filter_entries", tracking_erb_area_stations, filters)
	else:
		for station in tracking_erb_area_stations:
			if not _tracking_station_filter_matches(station, "operator", str(filters.get("operator", ""))):
				continue
			if not _tracking_station_filter_matches(station, "generation", str(filters.get("generation", ""))):
				continue
			if not _tracking_station_filter_matches(station, "city", str(filters.get("city", ""))):
				continue
			if not _tracking_station_filter_matches(station, "status", str(filters.get("status", ""))):
				continue
			filtered.append(station.duplicate(true))
	vehicle_location_map_canvas.set_coverage_profile({
		"ok": true,
		"stations": filtered,
		"metadata": tracking_erb_metadata.duplicate(true),
	})
	vehicle_location_map_canvas.set_station_visibility(tracking_view.erb_layer_check.button_pressed)
	if not tracking_selected_station.is_empty():
		var selected_id := str(tracking_selected_station.get("id", ""))
		var selection_visible := false
		for station in filtered:
			if str(station.get("id", "")) == selected_id:
				tracking_selected_station = station.duplicate(true)
				selection_visible = true
				break
		if selection_visible:
			vehicle_location_map_canvas.select_station_by_id(selected_id)
			_render_tracking_station_details(tracking_selected_station)
		else:
			tracking_selected_station.clear()
			_render_vehicle_location_details({})
	if filtered.is_empty():
		tracking_view.erb_caveat_label.text = "Nenhuma ERB oficial corresponde aos filtros. Ajuste os filtros ou navegue para outra área."
	else:
		tracking_view.erb_caveat_label.text = "%d ERB(s) oficiais no recorte · licenciamento não representa sinal em tempo real." % filtered.size()


func _tracking_station_filter_matches(station: Dictionary, field: String, expected: String) -> bool:
	if expected == "":
		return true
	var actual := str(station.get(field, "")).strip_edges()
	if expected == "__missing__":
		return actual == ""
	return actual.casecmp_to(expected) == 0


func _update_tracking_poll_interval() -> void:
	if st310_location_poll_timer == null or not is_instance_valid(st310_location_poll_timer):
		return
	var selected_filter := _tracking_selected_filter()
	st310_location_poll_timer.wait_time = TRACKING_POLL_MOVING_SECONDS if selected_filter == "Em movimento" else TRACKING_POLL_DEFAULT_SECONDS


func _tracking_selected_filter() -> String:
	if vehicle_location_monitor_select == null or not is_instance_valid(vehicle_location_monitor_select):
		return "Todos"
	return vehicle_location_monitor_select.get_item_text(vehicle_location_monitor_select.selected)


func _refresh_vehicle_location_view(expected_generation: int = -1) -> void:
	if vehicle_location_refreshing:
		return
	vehicle_location_query_trigger = str(tracking_query_trigger_by_generation.get(
		expected_generation,
		vehicle_location_query_trigger if vehicle_location_query_trigger != "unknown" else "poll"
	))
	var requested_queries := _tracking_search_queries()
	if tracking_view != null and not requested_queries.is_empty():
		tracking_view.set_query_state("loading")
	grupo_rs_api_location_cache_checked_at = 0
	var query_signature := _tracking_query_signature()
	var started_at := Time.get_ticks_msec()
	await super._refresh_vehicle_location_view(expected_generation)
	if expected_generation >= 0 and expected_generation != vehicle_location_query_generation:
		return
	tracking_last_latency_ms = maxi(0, Time.get_ticks_msec() - started_at)
	tracking_last_success_at = Time.get_time_string_from_system().substr(0, 8)

	# No modo API-exclusiva, uma resposta sem posição não reutiliza coordenadas
	# anteriores nem qualquer cache local como substituto da fonte oficial.
	tracking_last_query_signature = query_signature
	_apply_vehicle_location_filters()


func _tracking_query_signature() -> String:
	if not vehicle_location_query_queue.is_empty():
		var queries: Array[String] = []
		for query in vehicle_location_query_queue:
			queries.append(vehicle_location_integration.normalize_location_query(query))
		queries.sort()
		return "|".join(queries)
	return vehicle_location_integration.normalize_location_query(vehicle_location_plate_input.text) if vehicle_location_plate_input != null else ""


func _tracking_search_queries() -> Array[String]:
	var queries: Array[String] = []
	if not vehicle_location_query_queue.is_empty():
		for value in vehicle_location_query_queue:
			if bool(vehicle_location_integration.describe_location_query(value).get("valid", false)):
				queries.append(value)
		return queries
	if vehicle_location_plate_input != null and is_instance_valid(vehicle_location_plate_input):
		var value := vehicle_location_plate_input.text.strip_edges()
		if bool(vehicle_location_integration.describe_location_query(value).get("valid", false)):
			queries.append(value)
	return queries


func _tracking_row_matches_exact_queries(row: Dictionary, queries: Array[String]) -> bool:
	if queries.is_empty():
		return true
	for query in queries:
		if query.strip_edges().to_lower().begins_with("cliente:"):
			var expected_client := _search_key(query.substr(query.find(":") + 1))
			if expected_client != "" and _search_key(str(row.get("client", ""))) == expected_client:
				return true
		if vehicle_location_integration.row_matches_exact_query(row, query):
			return true
	return false


func _tracking_coordinates_valid(location: Dictionary) -> bool:
	var latitude := _tracking_number(location.get("lat", 0.0))
	var longitude := _tracking_number(location.get("lng", 0.0))
	return vehicle_location_integration.valid_coordinates(latitude, longitude)


func _tracking_number(value: Variant) -> float:
	var text := str(value).replace(",", ".").strip_edges()
	return text.to_float() if text.is_valid_float() else 0.0


func _location_monitoring_status(location: Dictionary) -> Dictionary:
	var updated_at := str(location.get("updated_at", "")).strip_edges()
	return VehicleStatusResolver.resolve(
		location,
		_tracking_coordinates_valid(location),
		_hours_since_grupo_rs_datetime(updated_at),
		_location_ignition_state(location.get("ignition", null)),
		{"on": GREEN, "off": RED, "stale": YELLOW, "unknown": MUTED}
	)


func _apply_vehicle_location_filters() -> void:
	if tracking_view == null or not is_instance_valid(tracking_view):
		return
	var previous_selected_key := _vehicle_location_row_key(vehicle_location_selected)
	var exact_queries := _tracking_search_queries()
	var scope_rows: Array[Dictionary] = []
	for raw_row in vehicle_location_rows:
		var row := raw_row
		if not _tracking_row_matches_exact_queries(row, exact_queries):
			continue
		_location_monitoring_status(row)
		scope_rows.append(row)

	var metrics := _tracking_metrics(scope_rows)
	tracking_view.set_metrics(metrics)
	vehicle_location_filtered_rows.clear()
	var selected_filter := _tracking_selected_filter()
	for row in scope_rows:
		if _tracking_row_matches_filter(row, selected_filter):
			vehicle_location_filtered_rows.append(row)

	_render_tracking_list()
	if not exact_queries.is_empty():
		tracking_selected_station.clear()
		vehicle_location_map_canvas.select_station_by_id("")
	_sync_tracking_selection(previous_selected_key, exact_queries)
	var map_rows := _vehicle_location_rows_for_map()
	var integrated_rows := _rows_with_tower_context(map_rows)
	vehicle_location_map_canvas.set_tracking_mode(true)
	vehicle_location_map_canvas.set_station_visibility(tracking_view.erb_layer_check.button_pressed)
	vehicle_location_map_canvas.set_tracking_locations(integrated_rows)
	if not vehicle_location_selected.is_empty():
		vehicle_location_map_canvas.select_tracking_by_key(str(vehicle_location_selected.get("serial", vehicle_location_selected.get("plate", ""))))

	var had_rows_before := tracking_had_map_rows
	tracking_had_map_rows = not map_rows.is_empty()
	if not vehicle_location_map_canvas.map_ready:
		vehicle_location_map_generation += 1
		call_deferred("_reload_vehicle_location_map", vehicle_location_map_generation, map_rows, _vehicle_location_map_view(map_rows))
	elif not had_rows_before and tracking_had_map_rows:
		vehicle_location_map_generation += 1
		call_deferred("_reload_vehicle_location_map", vehicle_location_map_generation, map_rows, _vehicle_location_map_view(map_rows))
	elif tracking_view.camera_lock_check.button_pressed and _tracking_map_signature(map_rows) != tracking_last_map_signature:
		vehicle_location_map_generation += 1
		call_deferred("_reload_vehicle_location_map", vehicle_location_map_generation, map_rows, _vehicle_location_map_view(map_rows))
	_focus_exact_tracking_result(exact_queries)
	_update_tracking_query_state(exact_queries, scope_rows)
	_update_tracking_runtime_from_rows(scope_rows, metrics)


func _tracking_row_matches_filter(row: Dictionary, selected_filter: String) -> bool:
	var label := str(_location_monitoring_status(row).get("label", ""))
	match selected_filter:
		"Em movimento":
			return label == "Ligado"
		"Parados":
			return label == "Desligado"
		"Desatualizados":
			return label == "Desatualizado" or label == "Sem comunicação"
		"Sem posição":
			return not _tracking_coordinates_valid(row)
	return true


func _tracking_metrics(rows: Array[Dictionary]) -> Dictionary:
	var metrics := {"Total": rows.size(), "Com posição": 0, "Em movimento": 0, "Parados": 0, "Desatualizados": 0, "Sem posição": 0}
	for row in rows:
		if _tracking_coordinates_valid(row):
			metrics["Com posição"] = int(metrics["Com posição"]) + 1
		else:
			metrics["Sem posição"] = int(metrics["Sem posição"]) + 1
		var label := str(_location_monitoring_status(row).get("label", ""))
		if label == "Ligado":
			metrics["Em movimento"] = int(metrics["Em movimento"]) + 1
		elif label == "Desligado":
			metrics["Parados"] = int(metrics["Parados"]) + 1
		elif label == "Desatualizado" or label == "Sem comunicação":
			metrics["Desatualizados"] = int(metrics["Desatualizados"]) + 1
	return metrics


func _render_tracking_list() -> void:
	for child in vehicle_location_list_body.get_children():
		vehicle_location_list_body.remove_child(child)
		child.free()
	for row in vehicle_location_filtered_rows:
		vehicle_location_list_body.add_child(_make_vehicle_location_row(row))
	if not vehicle_location_filtered_rows.is_empty():
		return
	var empty := Label.new()
	empty.text = "Nenhum veículo encontrado neste recorte."
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.add_theme_font_override("font", UI_FONT)
	empty.add_theme_font_size_override("font_size", 13)
	empty.add_theme_color_override("font_color", MUTED)
	vehicle_location_list_body.add_child(empty)


func _sync_tracking_selection(previous_key: String, exact_queries: Array[String] = []) -> void:
	tracking_query_ambiguous = false
	if not tracking_selected_station.is_empty():
		vehicle_location_selected.clear()
		_render_tracking_station_details(tracking_selected_station)
		return
	var selected: Dictionary = {}
	if exact_queries.size() == 1:
		var exact_result: Dictionary = vehicle_location_integration.find_exact_vehicle_result(vehicle_location_filtered_rows, exact_queries[0])
		tracking_query_ambiguous = bool(exact_result.get("ambiguous", false))
		selected = (exact_result.get("row", {}) as Dictionary).duplicate(true)
	else:
		for row in vehicle_location_filtered_rows:
			if previous_key != "" and _vehicle_location_row_key(row) == previous_key:
				selected = row.duplicate(true)
				break
	vehicle_location_selected = selected
	_render_vehicle_location_details(vehicle_location_selected)


func _focus_exact_tracking_result(exact_queries: Array[String]) -> void:
	if exact_queries.size() != 1 or vehicle_location_selected.is_empty():
		if exact_queries.is_empty():
			tracking_last_focused_query_signature = ""
		return
	var signature := _tracking_query_signature()
	if signature == "" or signature == tracking_last_focused_query_signature:
		return
	if not _tracking_coordinates_valid(vehicle_location_selected):
		return
	tracking_last_focused_query_signature = signature
	vehicle_location_map_generation += 1
	var selected_rows: Array[Dictionary] = [vehicle_location_selected.duplicate(true)]
	call_deferred(
		"_reload_vehicle_location_map",
		vehicle_location_map_generation,
		_vehicle_location_rows_for_map(),
		_vehicle_location_map_view(selected_rows)
	)


func _update_tracking_query_state(exact_queries: Array[String], scope_rows: Array[Dictionary]) -> void:
	if tracking_view == null or not is_instance_valid(tracking_view):
		return
	if vehicle_location_refreshing:
		tracking_view.set_query_state("loading")
		return
	if tracking_query_ambiguous:
		tracking_view.set_query_state("error", "Pesquisa ambígua; refine placa ou número de série")
		return
	if int(vehicle_location_last_query_error_count) > 0 and scope_rows.is_empty():
		tracking_view.set_query_state("error", _tracking_query_diagnostic_message())
		return
	if exact_queries.is_empty() \
			and str(vehicle_location_last_query_diagnostic.get("category", "")) == "not_found" \
			and vehicle_location_query_trigger in ["button", "enter"]:
		tracking_view.set_query_state("not_found")
		return
	if exact_queries.is_empty():
		tracking_view.set_query_state("idle")
		return
	if scope_rows.is_empty():
		tracking_view.set_query_state("not_found")
		return
	if _vehicle_location_rows_for_map().is_empty():
		var coordinate_state := str(scope_rows[0].get("coordinate_state", "missing"))
		tracking_view.set_query_state(
			"not_found",
			"Posição recebida em formato inválido" if coordinate_state == "invalid" else "Veículo encontrado sem posição"
		)
		return
	tracking_view.set_query_state("found")


func _tracking_query_diagnostic_message() -> String:
	match str(vehicle_location_last_query_diagnostic.get("category", "network_error")):
		"not_configured":
			return "Credenciais da API Grupo RS não configuradas"
		"unauthorized":
			return "Sessão da API recusada após nova autenticação"
		"forbidden":
			return "Perfil sem permissão para esta consulta"
		"timeout":
			return "Tempo limite ao consultar a API Grupo RS"
		"invalid_json":
			return "Resposta inválida recebida da API Grupo RS"
		"disabled":
			return "Leitura da API Grupo RS está desativada"
		_:
			return "Falha de comunicação com a API Grupo RS"


func _vehicle_location_rows_for_map() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in vehicle_location_filtered_rows:
		if _tracking_coordinates_valid(row):
			rows.append(row.duplicate(true))
	return rows


func _rows_with_tower_context(rows: Array[Dictionary]) -> Array[Dictionary]:
	var integrated: Array[Dictionary] = []
	var station_rows: Array = vehicle_location_map_canvas.stations if vehicle_location_map_canvas != null else []
	for row in rows:
		var operator_info := {
			"operator": str(row.get("tracker_operator", row.get("operator", ""))),
			"source": str(row.get("tracker_operator_source", "")),
		}
		var state := vehicle_location_integration.compose_map_state(row, station_rows, operator_info)
		integrated.append((state.get("vehicle", row) as Dictionary).duplicate(true))
	return integrated


func _reload_vehicle_location_map(generation: int, rows: Array, view_override: Dictionary = {}) -> void:
	if generation != vehicle_location_map_generation or vehicle_location_map_canvas == null or not is_instance_valid(vehicle_location_map_canvas):
		return
	var valid_rows: Array[Dictionary] = []
	for raw in rows:
		if typeof(raw) == TYPE_DICTIONARY and _tracking_coordinates_valid(raw as Dictionary):
			valid_rows.append((raw as Dictionary).duplicate(true))
	var view := view_override.duplicate(true)
	if view.is_empty():
		view = vehicle_location_map_canvas.current_map_view()
	if view.is_empty():
		view = _vehicle_location_map_view(valid_rows)
	var devices: Array[Dictionary] = []
	for row in valid_rows:
		devices.append(vehicle_location_integration.map_device(row))
	var basemap := str(view.get("basemap", vehicle_location_map_canvas.basemap_id))
	vehicle_location_map_canvas.set_basemap(basemap)
	# O controller já consulta a camada nacional/regional correspondente. O
	# loader fica responsável apenas pelos tiles e não monta o perfil legado.
	await _load_smart_4g_map_tiles(vehicle_location_map_canvas, devices, "all", view, true)
	if generation != vehicle_location_map_generation or vehicle_location_map_canvas == null or not is_instance_valid(vehicle_location_map_canvas):
		return
	await _refresh_tracking_erb_area(view, generation)
	if generation != vehicle_location_map_generation or vehicle_location_map_canvas == null or not is_instance_valid(vehicle_location_map_canvas):
		return
	vehicle_location_map_canvas.set_station_visibility(tracking_view.erb_layer_check.button_pressed if tracking_view != null else true)
	vehicle_location_map_canvas.set_tracking_mode(true)
	var integrated_rows := _rows_with_tower_context(valid_rows)
	vehicle_location_map_canvas.set_tracking_locations(integrated_rows)
	tracking_last_map_signature = _tracking_map_signature(valid_rows)
	if not vehicle_location_selected.is_empty():
		var selected_key := _vehicle_location_row_key(vehicle_location_selected)
		for row in integrated_rows:
			if _vehicle_location_row_key(row) == selected_key:
				vehicle_location_selected = row.duplicate(true)
				break
		vehicle_location_map_canvas.select_tracking_by_key(str(vehicle_location_selected.get("serial", vehicle_location_selected.get("plate", ""))))
		_render_vehicle_location_details(vehicle_location_selected)


func _vehicle_location_map_view(rows: Array[Dictionary]) -> Dictionary:
	if rows.is_empty():
		return {"center": {"lat": BigMapConfig.DEFAULT_LATITUDE, "lng": BigMapConfig.DEFAULT_LONGITUDE}, "zoom": BigMapConfig.DEFAULT_ZOOM, "basemap": _tracking_current_basemap(), "interactive": true}
	var min_lat := INF
	var max_lat := -INF
	var min_lng := INF
	var max_lng := -INF
	for row in rows:
		var lat := _tracking_number(row.get("lat", 0.0))
		var lng := _tracking_number(row.get("lng", 0.0))
		min_lat = minf(min_lat, lat)
		max_lat = maxf(max_lat, lat)
		min_lng = minf(min_lng, lng)
		max_lng = maxf(max_lng, lng)
	var center_lat := (min_lat + max_lat) * 0.5
	var center_lng := (min_lng + max_lng) * 0.5
	var viewport := Vector2(900, 500)
	if vehicle_location_map_canvas != null and is_instance_valid(vehicle_location_map_canvas):
		viewport = Vector2(maxf(720.0, vehicle_location_map_canvas.size.x), maxf(360.0, vehicle_location_map_canvas.size.y))
	var zoom := BigMapConfig.MIN_ZOOM
	for candidate in range(BigMapConfig.MAX_ZOOM, BigMapConfig.MIN_ZOOM - 1, -1):
		var a := BigMapProjection.lat_lng_to_world_pixel(min_lat, min_lng, candidate)
		var b := BigMapProjection.lat_lng_to_world_pixel(max_lat, max_lng, candidate)
		if absf(b.x - a.x) <= viewport.x - 160.0 and absf(b.y - a.y) <= viewport.y - 140.0:
			zoom = candidate
			break
	if rows.size() == 1:
		zoom = 16
	return {"center": {"lat": center_lat, "lng": center_lng}, "zoom": zoom, "basemap": _tracking_current_basemap(), "interactive": true}


func _tracking_current_basemap() -> String:
	return BigMapConfig.DEFAULT_BASEMAP


func _tracking_map_signature(rows: Array[Dictionary]) -> String:
	if rows.is_empty():
		return "empty"
	var view := _vehicle_location_map_view(rows)
	var center: Dictionary = view.get("center", {})
	return "%.3f|%.3f|%d|%d" % [float(center.get("lat", 0.0)), float(center.get("lng", 0.0)), int(view.get("zoom", 0)), rows.size()]


func _ensure_vehicle_location_map_ready() -> void:
	if vehicle_location_map_canvas == null or not is_instance_valid(vehicle_location_map_canvas) or vehicle_location_map_canvas.map_ready:
		return
	vehicle_location_map_generation += 1
	await _reload_vehicle_location_map(vehicle_location_map_generation, [], _vehicle_location_map_view([]))


func _on_vehicle_location_map_navigation(latitude: float, longitude: float, zoom: int) -> void:
	vehicle_location_map_generation += 1
	_reload_vehicle_location_map(vehicle_location_map_generation, _vehicle_location_rows_for_map(), {"center": {"lat": latitude, "lng": longitude}, "zoom": zoom, "basemap": _tracking_current_basemap(), "interactive": true})


func _on_vehicle_location_map_reset() -> void:
	var rows := _vehicle_location_rows_for_map()
	vehicle_location_map_generation += 1
	_reload_vehicle_location_map(vehicle_location_map_generation, rows, _vehicle_location_map_view(rows))


func _on_vehicle_location_map_selected(location: Dictionary) -> void:
	if location.is_empty():
		return
	tracking_selected_station.clear()
	vehicle_location_map_canvas.select_station_by_id("")
	vehicle_location_selected = location.duplicate(true)
	_render_vehicle_location_details(vehicle_location_selected)
	vehicle_location_map_canvas.select_tracking_by_key(str(location.get("serial", location.get("plate", ""))))
	var latitude := _tracking_number(location.get("lat", 0.0))
	var longitude := _tracking_number(location.get("lng", 0.0))
	if vehicle_location_integration.valid_coordinates(latitude, longitude):
		_on_vehicle_location_map_navigation(latitude, longitude, 16)


func _on_vehicle_location_station_selected(station: Dictionary) -> void:
	if station.is_empty():
		return
	vehicle_location_selected.clear()
	tracking_selected_station = station.duplicate(true)
	vehicle_location_map_canvas.clear_tracking_selection()
	_render_tracking_station_details(tracking_selected_station)


func _toggle_vehicle_location_list() -> void:
	vehicle_location_list_expanded = not vehicle_location_list_panel.visible
	tracking_view.set_list_expanded(vehicle_location_list_expanded)


func _sync_vehicle_location_map_list_toggle() -> void:
	if tracking_view != null:
		tracking_view.set_list_expanded(vehicle_location_list_panel.visible)


func _make_vehicle_location_row(location: Dictionary) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 40)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _style_box(Color.WHITE, Color("#e2eaf1"), 1, 6))
	button.add_theme_stylebox_override("hover", _style_box(Color("#eef7fc"), BLUE, 1, 6))
	button.pressed.connect(func() -> void: _on_vehicle_location_map_selected(location))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 7)
	button.add_child(row)
	var status := _location_monitoring_status(location)
	var status_box := HBoxContainer.new()
	status_box.custom_minimum_size = Vector2(120, 0)
	status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.color = status.get("color", MUTED)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_box.add_child(dot)
	status_box.add_child(_tracking_table_label(str(status.get("label", "Sem status")), 0, true, status.get("color", MUTED), 10))
	row.add_child(status_box)
	row.add_child(_tracking_table_label(_blank(str(location.get("plate", ""))), 115, false, TEXT, 11))
	row.add_child(_tracking_table_label(_blank(str(location.get("serial", ""))), 125, false, TEXT, 11))
	row.add_child(_tracking_table_label(_blank(str(location.get("client", ""))), 210, true, TEXT, 11))
	row.add_child(_tracking_table_label(str(status.get("label", "Sem posição")), 120, false, status.get("color", MUTED), 10))
	row.add_child(_tracking_table_label(_blank(str(location.get("updated_at", ""))), 165, false, MUTED, 10))
	row.add_child(_tracking_table_label(_location_speed_display(location.get("speed", "")), 95, false, TEXT, 10))
	return button


func _tracking_table_label(value: String, width: int, expand: bool, color: Color, font_size: int) -> Label:
	var label := _make_table_label(value, width, expand, color, HORIZONTAL_ALIGNMENT_LEFT, font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _render_vehicle_location_details(location: Dictionary) -> void:
	if vehicle_location_details_body == null or not is_instance_valid(vehicle_location_details_body):
		return
	_clear_control(vehicle_location_details_body)
	if tracking_view != null:
		tracking_view.set_details_title("Veículo selecionado")
	if location.is_empty():
		var empty := Label.new()
		empty.text = "Selecione uma agulha, uma ERB ou uma linha para ver os dados."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_override("font", UI_FONT)
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", MUTED)
		vehicle_location_details_body.add_child(empty)
		return
	var status := _location_monitoring_status(location)
	var identity := Label.new()
	identity.text = _blank(str(location.get("plate", location.get("serial", ""))))
	identity.add_theme_font_override("font", UI_FONT)
	identity.add_theme_font_size_override("font_size", 21)
	identity.add_theme_color_override("font_color", status.get("color", BLUE_DARK))
	vehicle_location_details_body.add_child(identity)
	var coordinates := "Sem posição válida"
	if _tracking_coordinates_valid(location):
		coordinates = "%.6f, %.6f" % [_tracking_number(location.get("lat", 0.0)), _tracking_number(location.get("lng", 0.0))]
	for item in [
		["Status", str(status.get("label", "Sem status"))],
		["Série", str(location.get("serial", ""))],
		["Cliente", str(location.get("client", ""))],
		["Velocidade", _location_speed_display(location.get("speed", ""))],
		["Última comunicação", str(location.get("updated_at", ""))],
		["Coordenadas", coordinates],
		["Operadora", str(location.get("tracker_operator", location.get("operator", "Não determinada")))],
		["ERBs na área", str(location.get("nearby_tower_count", vehicle_location_map_canvas.stations.size()))],
		["Fonte", str(location.get("source", vehicle_location_source))],
	]:
		vehicle_location_details_body.add_child(_tracking_detail_line(str(item[0]), _blank(str(item[1]))))
	var center_button := _make_action_button("Centralizar no mapa", Color.WHITE, BLUE, BLUE, Vector2(0, 38), Callable(self, "_center_vehicle_location_selected"))
	center_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vehicle_location_details_body.add_child(center_button)


func _render_tracking_station_details(station: Dictionary) -> void:
	_clear_control(vehicle_location_details_body)
	if bool(station.get("is_index_cluster", false)):
		_render_tracking_station_cluster_details(station)
		return
	if tracking_view != null:
		tracking_view.set_details_title("ERB licenciada selecionada")
	var title := Label.new()
	title.text = "ERB  " + _tracking_source_value(str(station.get("id", station.get("code", ""))))
	title.add_theme_font_override("font", UI_FONT)
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", BLUE_DARK)
	vehicle_location_details_body.add_child(title)
	var technologies := _tracking_source_array(station.get("technologies", []))
	var bands := _tracking_source_array(station.get("bands", []))
	var address_parts: Array[String] = []
	for address_field in ["address", "address_number", "address_complement", "district"]:
		var address_value := str(station.get(address_field, "")).strip_edges()
		if address_value != "":
			address_parts.append(address_value)
	for item in [
		["Município / UF", "%s / %s" % [_tracking_source_value(str(station.get("city", ""))), _tracking_source_value(str(station.get("uf", "")))]],
		["Prestadora", _tracking_source_value(str(station.get("provider_name", station.get("operator", ""))))],
		["Entidade", _tracking_source_value(str(station.get("entity", "")))],
		["Geração", _tracking_source_value(str(station.get("generation", "")))],
		["Tecnologias", technologies],
		["Faixas", bands],
		["Frequência TX / RX", "%s / %s MHz" % [_tracking_source_value(str(station.get("frequency_tx_mhz", ""))), _tracking_source_value(str(station.get("frequency_rx_mhz", "")))]],
		["Situação", _tracking_source_value(str(station.get("status", "")))],
		["1º licenciamento", _tracking_source_value(str(station.get("first_license_date", "")))],
		["Licenciamento", _tracking_source_value(str(station.get("license_date", "")))],
		["Validade", _tracking_source_value(str(station.get("license_valid_until", "")))],
		["Infraestrutura", _tracking_source_value(str(station.get("infrastructure_class", "")))],
		["Endereço", " · ".join(address_parts) if not address_parts.is_empty() else "Não informado pela fonte"],
		["Coordenadas", "%.6f, %.6f" % [float(station.get("lat", 0.0)), float(station.get("lng", 0.0))]],
		["Fonte", "Anatel · Estações SMP licenciadas"],
	]:
		vehicle_location_details_body.add_child(_tracking_detail_line(str(item[0]), str(item[1])))


func _render_tracking_station_cluster_details(station: Dictionary) -> void:
	if tracking_view != null:
		tracking_view.set_details_title("Agrupamento de ERBs licenciadas")
	var title := Label.new()
	title.text = "%d registros de estação/geração" % int(station.get("cluster_count", 0))
	title.add_theme_font_override("font", UI_FONT)
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", BLUE_DARK)
	vehicle_location_details_body.add_child(title)
	for item in [
		["ERBs físicas", str(station.get("physical_count", "Não informado pela fonte"))],
		["Operadoras", _tracking_source_array(station.get("operators", []))],
		["Gerações", _tracking_source_array(station.get("generations", []))],
		["Situações", _tracking_source_array(station.get("statuses", []))],
		["Municípios", _tracking_source_array(station.get("cities", []))],
		["UFs", _tracking_source_array(station.get("ufs", []))],
		["Nível do índice", "z%s" % str(station.get("cell_zoom", "não informado"))],
		["Fonte", "Anatel · Estações SMP licenciadas"],
	]:
		vehicle_location_details_body.add_child(_tracking_detail_line(str(item[0]), str(item[1])))
	var caveat := Label.new()
	caveat.text = "Amplie o mapa para ver ERBs individuais. Licenciamento/presença não representa intensidade de sinal em tempo real."
	caveat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caveat.add_theme_font_override("font", UI_FONT)
	caveat.add_theme_font_size_override("font_size", 11)
	caveat.add_theme_color_override("font_color", MUTED)
	vehicle_location_details_body.add_child(caveat)


func _tracking_source_value(value: String) -> String:
	var clean := value.strip_edges()
	return clean if clean != "" else "Não informado pela fonte"


func _tracking_source_array(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "Não informado pela fonte"
	var parts: Array[String] = []
	for item in value as Array:
		var clean := str(item).strip_edges()
		if clean != "" and clean not in parts:
			parts.append(clean)
	return ", ".join(parts) if not parts.is_empty() else "Não informado pela fonte"


func _tracking_detail_line(caption_text: String, value_text: String) -> Control:
	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(0, 37)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(row)
	var caption := Label.new()
	caption.text = caption_text
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_theme_font_override("font", UI_FONT)
	caption.add_theme_font_size_override("font_size", 10)
	caption.add_theme_color_override("font_color", MUTED)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption)
	var value := Label.new()
	value.text = value_text
	value.custom_minimum_size = Vector2(165, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_font_override("font", UI_FONT)
	value.add_theme_font_size_override("font_size", 11)
	value.add_theme_color_override("font_color", TEXT)
	row.add_child(value)
	var divider := HSeparator.new()
	divider.add_theme_color_override("separator_color", Color("#e4ebf1"))
	stack.add_child(divider)
	return stack


func _clear_control(control: Control) -> void:
	for child in control.get_children():
		control.remove_child(child)
		child.free()


func _center_vehicle_location_selected() -> void:
	if vehicle_location_selected.is_empty():
		return
	var latitude := _tracking_number(vehicle_location_selected.get("lat", 0.0))
	var longitude := _tracking_number(vehicle_location_selected.get("lng", 0.0))
	if vehicle_location_integration.valid_coordinates(latitude, longitude):
		_on_vehicle_location_map_navigation(latitude, longitude, 16)


func _update_tracking_runtime_from_rows(rows: Array[Dictionary], metrics: Dictionary) -> void:
	var query := _tracking_query_signature()
	if query == "":
		_update_tracking_runtime("Informe uma placa, número de série ou cliente para iniciar", MUTED)
		return
	var message := "%d veículo(s) · %d com posição · %d ERBs carregadas" % [rows.size(), int(metrics.get("Com posição", 0)), vehicle_location_map_canvas.stations.size()]
	var color := GREEN if int(metrics.get("Com posição", 0)) > 0 else YELLOW
	_update_tracking_runtime(message, color)


func _update_tracking_runtime(message: String, color: Color) -> void:
	if tracking_view == null or not is_instance_valid(tracking_view):
		return
	var interval := TRACKING_POLL_MOVING_SECONDS if _tracking_selected_filter() == "Em movimento" else TRACKING_POLL_DEFAULT_SECONDS
	var metadata := "OpenStreetMap · ERBs Anatel · atualização a cada %d s" % int(interval)
	var updated := "Aguardando atualização"
	if tracking_last_success_at != "":
		updated = "Atualizado %s · %d ms" % [tracking_last_success_at, tracking_last_latency_ms]
	tracking_view.set_runtime(message, color, metadata, updated)
