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
const MaintenanceLoader := preload("res://src/features/big_map/maintenance_plate_loader.gd")
const MaintenanceBinding := preload("res://src/features/big_map/maintenance_binding.gd")
const MaintenancePanel := preload("res://src/features/big_map/maintenance_panel.gd")
const MaintenanceRadio := preload("res://src/features/big_map/maintenance_radio_context.gd")
var maintenance_operator_catalog: Dictionary = {}
var maintenance_operator_catalog_base := ""
var maintenance_bindings: Dictionary = {}
var maintenance_binding_epoch := 0
var maintenance_binding_busy := false
const MaintenanceSnapshot := preload("res://src/features/big_map/maintenance_snapshot.gd")
var maintenance_loader = MaintenanceLoader.new()
var maintenance_mode := false
const MaintenanceAnalysis := preload("res://src/features/big_map/maintenance_analysis.gd")
const MaintenanceWebHistory := preload("res://src/features/big_map/maintenance_web_history.gd")
var maintenance_analysis_busy := false
var maintenance_chip_results: Dictionary = {}
var maintenance_summaries: Dictionary = {}
var maintenance_reports: Dictionary = {}

var tracking_view: VBoxContainer
var tracking_last_latency_ms := -1
var tracking_last_success_at := ""
var tracking_last_query_signature := ""
var tracking_last_map_signature := ""
var tracking_had_map_rows := false
var tracking_erb_area_stations: Array[Dictionary] = []
var tracking_erb_metadata: Dictionary = {}
var tracking_selected_station: Dictionary = {}
var tracking_reference_vehicle: Dictionary = {}
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
	maintenance_mode = false
	maintenance_loader.cancel()
	maintenance_reports.clear()
	vehicle_location_query_queue.clear()
	vehicle_location_rows.clear()
	vehicle_location_filtered_rows.clear()
	vehicle_location_selected.clear()
	tracking_selected_station.clear()
	tracking_reference_vehicle.clear()
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
	if not maintenance_loader.changed.is_connected(_on_maintenance_changed):
		maintenance_loader.changed.connect(_on_maintenance_changed)
	tracking_view.maintenance_button.pressed.connect(_on_maintenance_pressed)
	tracking_view.tree_exiting.connect(func(): maintenance_mode = false; maintenance_loader.cancel())
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
	_leave_maintenance_mode()
	_add_vehicle_location_query()
	vehicle_location_query_trigger = "button"
	tracking_query_trigger_by_generation[vehicle_location_query_generation] = "button"


func _on_tracking_query_input(event: InputEvent) -> void:
	var is_submit: bool = event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)
	if is_submit:
		_leave_maintenance_mode()
	_on_vehicle_location_query_input(event)
	if is_submit:
		vehicle_location_query_trigger = "enter"
		tracking_query_trigger_by_generation[vehicle_location_query_generation] = "enter"


func _on_tracking_manual_refresh() -> void:
	if maintenance_mode:
		_on_maintenance_pressed()
		return
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
	if current_section != "vehicle_location":
		return
	if expected_generation < 0:
		expected_generation = vehicle_location_query_generation
	if expected_generation != vehicle_location_query_generation:
		return
	if maintenance_mode:
		return
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
	if current_section != "vehicle_location":
		return
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
	if bool(location.get("maintenance", false)):
		var state := MaintenanceSnapshot.ignition(location.get("ignition"))
		return VehicleStatusResolver.apply_state(location, "Ligado" if state == 1 else ("Desligado" if state == 0 else "Ignição não informada"), GREEN if state == 1 else (RED if state == 0 else MUTED))
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
		"Última ignição ligada":
			return MaintenanceSnapshot.ignition(row.get("ignition")) == 1
		"Última ignição desligada":
			return MaintenanceSnapshot.ignition(row.get("ignition")) == 0
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
		if bool(row.get("maintenance", false)) and MaintenanceSnapshot.ignition(row.get("ignition")) < 0:
			continue
		if _tracking_coordinates_valid(row):
			rows.append(row.duplicate(true))
	return rows


func _rows_with_tower_context(rows: Array[Dictionary]) -> Array[Dictionary]:
	# Maintenance selection uses the original snapshot; tower proximity is not
	# a coverage diagnosis. Avoid recomputing every vehicle × tower on zoom.
	if maintenance_mode:
		return rows
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
	if bool(view_override.get("interactive", false)):
		await get_tree().create_timer(0.18).timeout
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
	tracking_reference_vehicle = location.duplicate(true)
	_render_vehicle_location_details(vehicle_location_selected)
	vehicle_location_map_canvas.select_tracking_by_key(str(location.get("serial", location.get("plate", ""))))
	if location.get("plate_only", false):
		_request_maintenance_binding(location)
	# Selecting a marker does not move the camera or request new map tiles.


func _on_vehicle_location_station_selected(station: Dictionary) -> void:
	if station.is_empty():
		return
	vehicle_location_selected.clear()
	maintenance_binding_epoch += 1
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
	if location.get("plate_only", false):
		var key := _normalize_location_plate(str(location.get("plate", "")))
		location = maintenance_bindings.get(key, location)
		if _normalize_location_plate(str(vehicle_location_selected.get("plate", ""))) == key:
			vehicle_location_selected = location.duplicate(true)
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
	if bool(location.get("maintenance", false)):
		_render_maintenance_details(location)
		return
	var identity := Label.new()
	identity.text = _blank(str(location.get("plate", location.get("serial", ""))))
	identity.add_theme_font_override("font", UI_FONT)
	identity.add_theme_font_size_override("font_size", 21)
	identity.add_theme_color_override("font_color", status.get("color", BLUE_DARK))
	vehicle_location_details_body.add_child(identity)
	var status_badge := PanelContainer.new()
	status_badge.add_theme_stylebox_override("panel", tracking_view._panel_style(Color(status.get("color", MUTED), 0.10), Color(status.get("color", MUTED), 0.22), 9))
	var status_label := Label.new()
	status_label.text = "●  " + str(status.get("label", "Sem status"))
	status_label.add_theme_font_override("font", UI_FONT)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", status.get("color", MUTED))
	status_badge.add_child(status_label)
	vehicle_location_details_body.add_child(status_badge)
	var coordinates := "Sem posição válida"
	if _tracking_coordinates_valid(location):
		coordinates = "%.6f, %.6f" % [_tracking_number(location.get("lat", 0.0)), _tracking_number(location.get("lng", 0.0))]
	for item in [
		["Série", str(location.get("serial", ""))],
		["Cliente", str(location.get("client", ""))],
		["Velocidade", _location_speed_display(location.get("speed", ""))],
		["Última comunicação", str(location.get("updated_at", ""))],
	]:
		vehicle_location_details_body.add_child(_tracking_detail_line(str(item[0]), _blank(str(item[1]))))
	var vehicle_technical := VBoxContainer.new()
	vehicle_technical.add_theme_constant_override("separation", 4)
	vehicle_technical.hide()
	for item in [
		["Coordenadas", coordinates],
		["Operadora", str(location.get("tracker_operator", location.get("operator", "Não determinada")))],
		["ERBs na área", str(location.get("nearby_tower_count", vehicle_location_map_canvas.stations.size()))],
		["Fonte", str(location.get("source", vehicle_location_source))],
	]:
		vehicle_technical.add_child(_tracking_detail_line(str(item[0]), _blank(str(item[1]))))
	var vehicle_expand := CheckButton.new()
	vehicle_expand.text = "Ver detalhes técnicos"
	vehicle_expand.add_theme_font_override("font", UI_FONT)
	vehicle_expand.add_theme_font_size_override("font_size", 12)
	vehicle_expand.add_theme_color_override("font_color", BLUE_DARK)
	vehicle_expand.toggled.connect(func(shown: bool): vehicle_technical.visible = shown)
	vehicle_location_details_body.add_child(vehicle_expand)
	vehicle_location_details_body.add_child(vehicle_technical)
	if bool(location.get("maintenance", false)):
		vehicle_location_details_body.add_child(_tracking_detail_line("APN", _blank(str(location.get("apn", "")))))
		vehicle_location_details_body.add_child(_tracking_detail_line("Código da operadora (API)", _blank(str(location.get("operator_code", "")))))
	var center_button := _make_action_button("Centralizar no mapa", Color.WHITE, BLUE, BLUE, Vector2(0, 38), Callable(self, "_center_vehicle_location_selected"))
	center_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vehicle_location_details_body.add_child(center_button)
	if bool(location.get("maintenance", false)):
		var serial := str(location.get("serial", ""))
		var analyze := _make_action_button("Analisar últimas 20 comunicações", BLUE, Color.WHITE, BLUE, Vector2(0, 42), Callable(self, "_analyze_maintenance").bind(location.duplicate(true)))
		analyze.disabled = maintenance_analysis_busy or maintenance_loader.running
		vehicle_location_details_body.add_child(analyze)
		if maintenance_reports.has(serial):
			var report := Label.new()
			report.text = str(maintenance_reports[serial])
			report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			report.add_theme_font_size_override("font_size", 12)
			vehicle_location_details_body.add_child(report)
			var sms := _make_action_button("Revisar configuração por SMS", Color.WHITE, BLUE, BLUE, Vector2(0, 38), Callable(self, "_review_maintenance_sms").bind(location.duplicate(true)))
			vehicle_location_details_body.add_child(sms)


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
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", BLUE_DARK)
	vehicle_location_details_body.add_child(title)
	var technologies := _tracking_source_array(station.get("technologies", []))
	var bands := _tracking_source_array(station.get("bands", []))
	var provider := _tracking_source_value(str(station.get("provider_name", station.get("operator", ""))))
	var generation := _tracking_source_value(str(station.get("generation", "")))
	var situation := _tracking_source_value(str(station.get("status", "")))
	var operator_identity: Dictionary = vehicle_location_map_canvas.call("_station_operator_identity", provider)
	var operator_color: Color = operator_identity.get("color", BLUE)
	var address_parts: Array[String] = []
	for address_field in ["address", "address_number", "address_complement", "district"]:
		var address_value := str(station.get(address_field, "")).strip_edges()
		if address_value != "":
			address_parts.append(address_value)
	var distance_text := "Selecione um veículo para comparar"
	if _tracking_coordinates_valid(tracking_reference_vehicle):
		var distance_km := _smart_4g_distance_km(_tracking_number(tracking_reference_vehicle.get("lat", 0.0)), _tracking_number(tracking_reference_vehicle.get("lng", 0.0)), float(station.get("lat", 0.0)), float(station.get("lng", 0.0)))
		distance_text = "%.2f km" % distance_km
	var status_badge := PanelContainer.new()
	var licensed := situation.to_lower().contains("licen")
	var status_color := GREEN if licensed else ORANGE
	status_badge.add_theme_stylebox_override("panel", tracking_view._panel_style(Color(status_color, 0.10), Color(status_color, 0.20), 10))
	var status_label := Label.new()
	status_label.text = "●  " + situation
	status_label.add_theme_font_override("font", UI_FONT)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", status_color)
	status_badge.add_child(status_label)
	vehicle_location_details_body.add_child(status_badge)

	var operator_card := PanelContainer.new()
	operator_card.add_theme_stylebox_override("panel", tracking_view._panel_style(Color(operator_color, 0.055), Color(operator_color, 0.24), 10))
	var operator_row := HBoxContainer.new()
	operator_row.add_theme_constant_override("separation", 12)
	operator_card.add_child(operator_row)
	var operator_stack := VBoxContainer.new()
	operator_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	operator_stack.add_theme_constant_override("separation", 1)
	operator_row.add_child(operator_stack)
	var operator_name := Label.new()
	operator_name.text = provider
	operator_name.add_theme_font_override("font", UI_FONT)
	operator_name.add_theme_font_size_override("font_size", 18)
	operator_name.add_theme_color_override("font_color", operator_color)
	operator_stack.add_child(operator_name)
	var operator_caption := Label.new()
	operator_caption.text = "Operadora"
	operator_caption.add_theme_font_override("font", UI_FONT)
	operator_caption.add_theme_font_size_override("font_size", 10)
	operator_caption.add_theme_color_override("font_color", MUTED)
	operator_stack.add_child(operator_caption)
	var technology_stack := VBoxContainer.new()
	technology_stack.custom_minimum_size.x = 105
	operator_row.add_child(technology_stack)
	var technology_value := Label.new()
	technology_value.text = technologies
	technology_value.add_theme_font_override("font", UI_FONT)
	technology_value.add_theme_font_size_override("font_size", 15)
	technology_value.add_theme_color_override("font_color", BLUE_DARK)
	technology_stack.add_child(technology_value)
	var technology_caption := Label.new()
	technology_caption.text = "Tecnologia · " + generation
	technology_caption.add_theme_font_override("font", UI_FONT)
	technology_caption.add_theme_font_size_override("font_size", 10)
	technology_caption.add_theme_color_override("font_color", MUTED)
	technology_stack.add_child(technology_caption)
	vehicle_location_details_body.add_child(operator_card)

	var location_card := PanelContainer.new()
	location_card.add_theme_stylebox_override("panel", tracking_view._panel_style(Color("#f7fafd"), Color("#dce7f0"), 9))
	var location_stack := VBoxContainer.new()
	location_stack.add_theme_constant_override("separation", 5)
	location_card.add_child(location_stack)
	var municipality := Label.new()
	municipality.text = "%s · %s" % [_tracking_source_value(str(station.get("city", ""))), _tracking_source_value(str(station.get("uf", "")))]
	municipality.add_theme_font_override("font", UI_FONT)
	municipality.add_theme_font_size_override("font_size", 12)
	municipality.add_theme_color_override("font_color", BLUE_DARK)
	location_stack.add_child(municipality)
	var distance := Label.new()
	distance.text = "Distância do veículo: " + distance_text
	distance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	distance.add_theme_font_override("font", UI_FONT)
	distance.add_theme_font_size_override("font_size", 11)
	distance.add_theme_color_override("font_color", MUTED)
	location_stack.add_child(distance)
	vehicle_location_details_body.add_child(location_card)
	var station_technical := VBoxContainer.new()
	station_technical.add_theme_constant_override("separation", 4)
	station_technical.hide()
	for item in [
		["Entidade", _tracking_source_value(str(station.get("entity", "")))],
		["Geração", _tracking_source_value(str(station.get("generation", "")))],
		["Faixas", bands],
		["Frequência TX / RX", "%s / %s MHz" % [_tracking_source_value(str(station.get("frequency_tx_mhz", ""))), _tracking_source_value(str(station.get("frequency_rx_mhz", "")))]],
		["1º licenciamento", _tracking_source_value(str(station.get("first_license_date", "")))],
		["Licenciamento", _tracking_source_value(str(station.get("license_date", "")))],
		["Validade", _tracking_source_value(str(station.get("license_valid_until", "")))],
		["Infraestrutura", _tracking_source_value(str(station.get("infrastructure_class", "")))],
		["Endereço", " · ".join(address_parts) if not address_parts.is_empty() else "Não informado pela fonte"],
		["Coordenadas", "%.6f, %.6f" % [float(station.get("lat", 0.0)), float(station.get("lng", 0.0))]],
		["Fonte", "Anatel · Estações SMP licenciadas"],
	]:
		station_technical.add_child(_tracking_detail_line(str(item[0]), str(item[1])))
	var station_expand := CheckButton.new()
	station_expand.text = "Ver detalhes técnicos"
	station_expand.add_theme_font_override("font", UI_FONT)
	station_expand.add_theme_font_size_override("font_size", 12)
	station_expand.add_theme_color_override("font_color", BLUE_DARK)
	station_expand.toggled.connect(func(shown: bool): station_technical.visible = shown)
	vehicle_location_details_body.add_child(station_expand)
	vehicle_location_details_body.add_child(station_technical)


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
		child.queue_free()


func _center_vehicle_location_selected() -> void:
	if vehicle_location_selected.is_empty():
		return
	var latitude := _tracking_number(vehicle_location_selected.get("lat", 0.0))
	var longitude := _tracking_number(vehicle_location_selected.get("lng", 0.0))
	if vehicle_location_integration.valid_coordinates(latitude, longitude):
		_on_vehicle_location_map_navigation(latitude, longitude, 16)


func _update_tracking_runtime_from_rows(rows: Array[Dictionary], metrics: Dictionary) -> void:
	if maintenance_mode:
		tracking_view.set_runtime(maintenance_loader.message, MUTED, "Manutenção · sem consulta automática", "Verde: ignição ligada · vermelho: desligada")
		return
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
	if maintenance_mode:
		metadata = "OpenStreetMap · ERBs Anatel · manutenções sem atualização automática"
	var updated := "Aguardando atualização"
	if tracking_last_success_at != "":
		updated = "Atualizado %s · %d ms" % [tracking_last_success_at, tracking_last_latency_ms]
	tracking_view.set_runtime(message, color, metadata, updated)


func _leave_maintenance_mode() -> void:
	if not maintenance_mode:
		return
	maintenance_mode = false
	maintenance_loader.cancel()
	vehicle_location_rows.clear()
	tracking_view.set_maintenance_progress(false, false, {}, "")


func _on_maintenance_pressed() -> void:
	if maintenance_loader.running:
		maintenance_loader.cancel()
		return
	if vehicle_location_refreshing:
		_show_warning("Manutenções", "Aguarde a consulta atual terminar antes de iniciar o levantamento.")
		return
	if maintenance_analysis_busy or maintenance_loader._busy:
		_show_warning("Manutenções", "Aguarde as consultas em andamento encerrarem antes de iniciar outra carga.")
		return
	maintenance_mode = true
	maintenance_binding_epoch += 1
	maintenance_bindings.clear()
	vehicle_location_query_generation += 1
	vehicle_location_query_queue.clear()
	vehicle_location_plate_input.clear()
	vehicle_location_rows.clear()
	vehicle_location_selected.clear()
	maintenance_reports.clear()
	maintenance_chip_results.clear()
	maintenance_summaries.clear()
	tracking_view.monitor_select.select(0)
	await maintenance_loader.start(self)


func _on_maintenance_changed() -> void:
	if not maintenance_mode or tracking_view == null or not is_instance_valid(tracking_view) or not tracking_view.is_inside_tree():
		return
	vehicle_location_rows.assign(maintenance_loader.rows)
	tracking_view.set_maintenance_progress(true, maintenance_loader.running, maintenance_loader.counts(), maintenance_loader.message)
	if maintenance_loader.rows.is_empty():
		return
	_apply_vehicle_location_filters()


func _request_maintenance_binding(location: Dictionary, force: bool = false) -> void:
	maintenance_binding_epoch += 1
	var epoch := maintenance_binding_epoch
	var ticket: int = maintenance_loader.generation
	var key := _normalize_location_plate(str(location.get("plate", "")))
	if not force and maintenance_bindings.has(key) and maintenance_bindings[key].get("binding_state", "") != "loading":
		_render_vehicle_location_details(maintenance_bindings[key])
		return
	var pending := location.duplicate(true)
	pending.binding_state = "loading"
	maintenance_bindings[key] = pending
	_render_vehicle_location_details(pending)
	await get_tree().create_timer(0.15).timeout
	while maintenance_binding_busy and maintenance_mode and ticket == maintenance_loader.generation and epoch == maintenance_binding_epoch:
		await get_tree().process_frame
	if not maintenance_mode or ticket != maintenance_loader.generation or epoch != maintenance_binding_epoch: return
	maintenance_binding_busy = true
	var result: Dictionary = await MaintenanceBinding.resolve(self,location)
	maintenance_binding_busy = false
	if not maintenance_mode or ticket != maintenance_loader.generation: return
	maintenance_bindings[key] = result
	if epoch == maintenance_binding_epoch and tracking_selected_station.is_empty() and _normalize_location_plate(str(vehicle_location_selected.get("plate", ""))) == key:
		vehicle_location_selected = result.duplicate(true)
		_render_vehicle_location_details(result)


func _render_maintenance_details(location: Dictionary) -> void:
	MaintenancePanel.render(self, location)


func _render_maintenance_details_legacy(location: Dictionary) -> void:
	tracking_view.details_title.hide()
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", tracking_view._panel_style(Color("#103f63"), Color("#103f63"), 9))
	var heading := Label.new()
	heading.text = "VEÍCULO SELECIONADO\nAnálise da manutenção"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_color_override("font_color", Color.WHITE)
	heading.add_theme_font_size_override("font_size", 16)
	header.add_child(heading)
	vehicle_location_details_body.add_child(header)
	for item in [["Placa", location.get("plate", "")], ["Número de série", location.get("serial", "")], ["Cliente", location.get("client", "")], ["Operadora", location.get("operator", "")], ["Última comunicação", location.get("updated_at", "")], ["Ignição na última comunicação", _location_monitoring_status(location).get("label", "Não informada")]]:
		vehicle_location_details_body.add_child(_tracking_detail_line(str(item[0]), _blank(str(item[1]))))
	var note := Label.new()
	note.text = "A cor indica somente a ignição. A análise é experimental e não confirma defeito."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color("#a85600"))
	vehicle_location_details_body.add_child(note)
	var binding_ok: bool = not location.get("plate_only", false) or location.get("binding_state", "") == "confirmed"
	if not binding_ok:
		var binding_note := Label.new()
		var state := str(location.get("binding_state", "pending"))
		var labels := {"pending":"Vínculo pendente. Selecione a agulha para consultar.","loading":"Consultando associação desta placa…","not_found":"Não foi encontrada uma associação para esta placa.","error":"Não foi possível consultar a associação. Tente novamente.","ambiguous":"Mais de uma associação encontrada. Análise bloqueada.","conflict":"Associação divergente da lista de manutenção. Análise e SMS bloqueados."}
		binding_note.text = labels.get(state, labels.error)
		binding_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		binding_note.add_theme_color_override("font_color", BLUE_DARK)
		binding_note.add_theme_font_size_override("font_size", 12)
		vehicle_location_details_body.add_child(binding_note)
		if state != "loading":
			var retry: Button = tracking_view._button("Consultar associação", BLUE, Color.WHITE, 0)
			retry.pressed.connect(Callable(self,"_request_maintenance_binding").bind(location.duplicate(true),true), CONNECT_DEFERRED)
			vehicle_location_details_body.add_child(retry)
	var analyze: Button = tracking_view._button("Analisar últimas 20 comunicações", BLUE, Color.WHITE, 0)
	analyze.add_theme_font_size_override("font_size", 11)
	analyze.pressed.connect(Callable(self,"_analyze_maintenance").bind(location.duplicate(true)), CONNECT_DEFERRED)
	analyze.disabled = maintenance_analysis_busy or maintenance_loader.running or not binding_ok
	vehicle_location_details_body.add_child(analyze)
	var serial := str(location.get("serial", ""))
	var apn := str(location.get("apn", ""))
	var provider := "Innova" if _apn_is_hinova(apn) else ("Link Solutions" if _apn_is_linksolutions(apn) else "Não identificado")
	var chip: Dictionary = maintenance_chip_results.get(serial, {})
	var chip_status := str(chip.get("status", ""))
	var status_text := "Não consultado"
	if maintenance_reports.has(serial):
		status_text = "Online" if chip_status == "online" else ("Offline" if chip_status == "offline" else "Consulta indisponível")
		if maintenance_analysis_busy and not maintenance_summaries.has(serial):
			status_text = "Consultando…"
	var chip_card := PanelContainer.new()
	chip_card.add_theme_stylebox_override("panel", tracking_view._panel_style(Color("#edf5fa"), BORDER, 8))
	var chip_row := HBoxContainer.new()
	chip_card.add_child(chip_row)
	var chip_label := Label.new()
	chip_label.text = "%s · %s\nAPN: %s" % [provider, status_text, _blank(apn)]
	chip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip_label.add_theme_color_override("font_color", BLUE_DARK)
	chip_row.add_child(chip_label)
	if binding_ok and chip_status == "online" and not maintenance_analysis_busy:
		var sms := _make_icon_action_button(ICON_DIR + "mensagem.svg", BLUE, BLUE, Vector2(34,34), Callable(self,"_review_maintenance_sms").bind(location.duplicate(true)))
		sms.name = "MaintenanceSms"
		var reason := _maintenance_sms_unavailable_reason(location)
		sms.disabled = reason != ""
		sms.tooltip_text = "Enviar SMS" if reason == "" else reason
		chip_row.add_child(sms)
	vehicle_location_details_body.add_child(chip_card)
	if maintenance_reports.has(serial):
		var report := Label.new()
		report.text = str(maintenance_summaries.get(serial, "Consultando histórico e chip…"))
		report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		report.add_theme_font_size_override("font_size", 12)
		vehicle_location_details_body.add_child(report)
		report.add_theme_color_override("font_color", Color("#182636"))
		var evidence := Label.new()
		evidence.text = str(maintenance_reports[serial])
		evidence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		evidence.add_theme_color_override("font_color", BLUE_DARK)
		evidence.hide()
		var expand := CheckButton.new()
		expand.text = "Ver evidências"
		expand.add_theme_color_override("font_color", BLUE_DARK)
		expand.add_theme_color_override("font_hover_color", BLUE)
		expand.toggled.connect(func(shown: bool): evidence.visible = shown)
		vehicle_location_details_body.add_child(expand)
		vehicle_location_details_body.add_child(evidence)


func _analyze_maintenance(location: Dictionary) -> void:
	if location.get("plate_only", false) and location.get("binding_state", "") != "confirmed":
		return
	if maintenance_analysis_busy or maintenance_loader.running:
		return
	maintenance_analysis_busy = true
	var serial := str(location.get("serial", ""))
	maintenance_chip_results.erase(serial)
	maintenance_summaries.erase(serial)
	var ticket: int = maintenance_loader.generation
	maintenance_reports[serial] = "Consultando histórico e chip em paralelo..."
	_render_vehicle_location_details(location)
	var state := {"history_done": false, "chip_done": false, "radio_done": true, "records": [], "chip": {}, "note": "", "closed": false}
	var deadline := Time.get_ticks_msec() + int(_maintenance_analysis_timeout_seconds() * 1000.0)
	_maintenance_history_task(location, state)
	_maintenance_chip_task(location, state)
	while not state.history_done or not state.chip_done or not state.radio_done:
		if ticket != maintenance_loader.generation or not maintenance_mode or Time.get_ticks_msec() >= deadline:
			break
		await get_tree().process_frame
	state.closed = true
	maintenance_analysis_busy = false
	if ticket != maintenance_loader.generation or not maintenance_mode:
		return
	if not state.history_done:
		state.note += "\nHistórico não concluiu no limite de espera; análise parcial. Tente novamente depois."
	if not state.chip_done:
		state.note += "\nConsulta do chip não concluiu; estado atual indisponível."
	maintenance_reports[serial] = str(state.note) + "\n\n" + MaintenanceAnalysis.summarize(state.records, state.chip)
	maintenance_chip_results[serial] = state.chip.duplicate(true) if state.chip_done else {}
	maintenance_summaries[serial] = MaintenanceAnalysis.compact(state.records, state.chip)
	var radio: Dictionary = state.get("radio", {})
	if not radio.is_empty():
		maintenance_reports[serial] += "\n\n" + str(radio.get("note", ""))
		if radio.get("hypothesis", false) and str(maintenance_summaries[serial]).begins_with("Análise inconclusiva"):
			maintenance_summaries[serial] = "Possível causa: perda de sinal, não confirmada.\nEvidência: ERB da operadora a %.1f km; outra a %.1f km, no recorte consultado.\nPróxima ação: verificar cobertura real e conectividade; distância não mede sinal." % [radio.own_km, radio.other_km]
	elif not state.radio_done:
		maintenance_reports[serial] += "\n\nContexto de ERBs não concluiu no prazo; nenhuma conclusão sobre cobertura."
	var record_index := 0
	for record in state.records:
		record_index += 1
		maintenance_reports[serial] += "\n\nRegistro %d · GPS: %s · Servidor: %s\nIgnição: %s · Tensão: %s V" % [record_index, _blank(str(record.get("gps_at", record.get("updated_at", "")))), _blank(str(record.get("server_at", ""))), str(record.get("ignition", "não informada")), _blank(str(record.get("battery_voltage", "")))]
	if state.has("enriched_location"):
		var enriched: Dictionary = state.enriched_location
		maintenance_bindings[_normalize_location_plate(str(enriched.get("plate", "")))] = enriched
	if not vehicle_location_selected.is_empty() and tracking_selected_station.is_empty():
		_render_vehicle_location_details(vehicle_location_selected)


func _maintenance_analysis_timeout_seconds() -> float:
	return 90.0


func _maintenance_chip_task(location: Dictionary, state: Dictionary) -> void:
	if location.get("plate_only", false):
		var equipment: Dictionary = await _grupo_rs_api_find_equipment(str(location.get("serial", "")), true)
		if state.get("closed", false): return
		if not equipment.get("ok", false): state.chip_done = true; return
		var raw: Dictionary = equipment.get("row", {})
		var details := _grupo_rs_api_normalize_location(raw)
		if str(details.get("serial", "")) != str(location.get("serial", "")):
			state.chip_done = true
			return
		location = location.duplicate(true)
		for field in ["chip", "phone", "apn", "operator"]:
			if str(details.get(field, "")) != "": location[field] = details[field]
		if str(location.get("chip", "")) == "": location.chip = str(raw.get("numeroChip", ""))
		if str(location.get("phone", "")) == "": location.phone = str(raw.get("numeroTelefone", ""))
		if str(location.get("operator", "")) == "":
			if maintenance_operator_catalog_base != selected_branch_grupo_rs_base_url:
				maintenance_operator_catalog.clear()
				maintenance_operator_catalog_base = selected_branch_grupo_rs_base_url
			var code := _grupo_rs_api_integer_value(raw.get("codOperadora", raw.get("CodOperadora", 0)))
			if code > 0 and maintenance_operator_catalog.is_empty():
				var catalog := await _modern_grupo_rs_read_get("equipamentos_editar.php?acao=novo")
				if state.get("closed", false): return
				if catalog.get("ok", false):
					for option in _legacy_select_options(str(catalog.get("body", "")), "CodOperadora"):
						var value := str(option.get("value", ""))
						if value.is_valid_int() and int(value)>0: maintenance_operator_catalog[int(value)] = str(option.get("label", ""))
			location.operator = str(maintenance_operator_catalog.get(code, ""))
		location = _maintenance_complete_sms_phone(location)
		state.enriched_location = location
		_maintenance_radio_task(location, state)
	var chip := str(location.get("chip", "")).strip_edges()
	var apn := str(location.get("apn", ""))
	if chip != "":
		if _apn_is_hinova(apn):
			state.chip = await _lookup_arya_chip_status(chip)
		elif _apn_is_linksolutions(apn):
			state.chip = await _lookup_linksolutions_chip_status(chip, false)
			if str(state.chip.get("status", "")) == "login" and not state.get("closed", false):
				var login := await _request_linksolutions_login()
				if login.get("ok", false) and not state.get("closed", false):
					state.chip = await _lookup_linksolutions_chip_status(chip, false)
	state.chip_done = true


func _maintenance_radio_task(location: Dictionary, state: Dictionary) -> void:
	state.radio_done = false
	var stations: Array = []
	if tracking_erb_index_mode == "national_partitioned" and tracking_national_erb_index != null and str(location.get("lat", "")).is_valid_float() and str(location.get("lng", "")).is_valid_float():
		var lat := float(location.lat)
		var lng := float(location.lng)
		var dx := 15.0 / (111.0 * maxf(cos(deg_to_rad(lat)), 0.1))
		var bounds := {"min_lat":lat-15.0/111.0,"max_lat":lat+15.0/111.0,"min_lng":lng-dx,"max_lng":lng+dx}
		var output := {}
		var task := WorkerThreadPool.add_task(Callable(tracking_national_erb_index,"query_viewport_threadsafe_to").bind(bounds,14,{},output))
		while not WorkerThreadPool.is_task_completed(task): await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		var query: Dictionary = output.get("result", {})
		if not query.get("ok", false):
			if not state.get("closed", false):
				state.radio = {"hypothesis":false,"note":"Consulta de ERBs indisponível; cobertura não avaliada."}
				state.radio_done = true
			return
		stations = query.get("stations", [])
	elif smart_4g_anatel != null:
		stations = smart_4g_anatel.get("stations")
	if state.get("closed", false): return
	if stations.is_empty():
		state.radio = {"hypothesis":false,"note":"Sem ERBs disponíveis no catálogo/recorte consultado; cobertura não avaliada."}
		state.radio_done = true
		return
	state.radio = MaintenanceRadio.evaluate(location, stations)
	state.radio.note = str(state.radio.note) + (" Fonte: catálogo regional Anatel." if tracking_erb_index_mode == "regional_fallback" else " Fonte: índice Anatel.")
	state.radio_done = true


func _maintenance_history_task(location: Dictionary, state: Dictionary) -> void:
	var vehicle := str(location.get("vehicle_id", ""))
	var reference := _grupo_rs_datetime_to_unix(str(location.get("updated_at", "")))
	if vehicle == "" or reference <= 0:
		state.note = "Histórico indisponível: identificação ou horário da última comunicação ausente."
		state.history_done = true
		return
	var ticket: int = maintenance_loader.generation
	var deadline := Time.get_ticks_msec() + 60000
	var records: Array[Dictionary] = []
	var seen := {}
	var complete := false
	var skip := 0
	# Bounded time window. Never label a truncated API page as the last 20.
	while Time.get_ticks_msec() < deadline and ticket == maintenance_loader.generation and not state.get("closed", false) and skip < 5000:
		var path := "/endpoints/v1/registros/listar.php?codVeiculo=%s&dataInicial=%s&dataFinal=%s&skip=%d&take=1000" % [vehicle.uri_encode(), _format_grupo_rs_api_records_datetime(reference - 604800).uri_encode(), _format_grupo_rs_api_records_datetime(reference + 60).uri_encode(), skip]
		var result := await _grupo_rs_api_get(path, true, true)
		if not result.get("ok", false):
			break
		var payload: Variant = JSON.parse_string(str(result.get("body", "")))
		if payload == null:
			break
		var page := _grupo_rs_api_extract_rows(payload)
		for raw in page:
			var normalized := _grupo_rs_api_normalize_location(raw)
			var received_vehicle := str(normalized.get("vehicle_id", ""))
			if received_vehicle != "" and received_vehicle != vehicle:
				continue
			var signature := JSON.stringify(raw).sha256_text()
			if not seen.has(signature):
				seen[signature] = true
				records.append(normalized)
		var pagination := _grupo_rs_api_pagination_state(payload, skip, page.size())
		if (pagination.get("pagination", {}) as Dictionary).is_empty():
			# This endpoint returns success/total/data, unlike the location endpoint.
			if not payload is Dictionary or not bool(payload.get("success", false)) or not payload.get("data") is Array:
				break
			pagination = {"has_more": page.size() >= 1000, "next_skip": skip + page.size()}
		if not pagination.get("has_more", false):
			complete = true
			break
		var next := int(pagination.get("next_skip", skip))
		if next <= skip:
			break
		skip = next
	if complete:
		records.sort_custom(func(a: Dictionary, b: Dictionary): return _grupo_rs_datetime_to_unix(str(a.get("updated_at", ""))) > _grupo_rs_datetime_to_unix(str(b.get("updated_at", ""))))
		state.records = records.slice(0, 20)
		state.note = "Amostra: até 20 registros mais recentes na janela de 7 dias anterior à última comunicação carregada."
	else:
		state.note = "Histórico incompleto ou indisponível; não é possível confirmar os 20 registros mais recentes."
	if (state.records as Array).is_empty() and ticket == maintenance_loader.generation and maintenance_mode and not state.get("closed", false):
		var fallback := await MaintenanceWebHistory.fetch(self, location, func(): return ticket == maintenance_loader.generation and maintenance_mode and not state.get("closed", false))
		if fallback.get("ok", false):
			state.records = fallback.get("records", [])
			state.note = "Histórico complementado pela plataforma web: até 20 registros na janela de 7 dias anterior à última comunicação."
		else:
			state.note += "\n" + str(fallback.get("message", "Histórico web indisponível."))
	state.history_done = true


func _maintenance_complete_sms_phone(location: Dictionary) -> Dictionary:
	var result := location.duplicate(true)
	if str(result.get("phone", "")).strip_edges() != "" or result.get("binding_state", "") != "confirmed":
		return result
	var phones := {}
	for member in result.get("maintenance_members", []):
		if str(member.get("serial", "")) != str(result.get("serial", "")):
			continue
		if _normalize_location_plate(str(member.get("plate", ""))) != _normalize_location_plate(str(result.get("plate", ""))):
			continue
		var phone := _digits_only(str(member.get("phone", "")))
		if phone.length() >= 10 and phone.length() <= 15:
			phones[phone] = true
	if phones.size() == 1:
		result.phone = phones.keys()[0]
		result.phone_source = "Lista web · série e placa confirmadas"
	return result


func _maintenance_sms_unavailable_reason(location: Dictionary) -> String:
	if str(location.get("apn", "")).strip_edges() == "":
		return "APN do aparelho não informada. SMS bloqueado."
	var phone_length := _digits_only(str(location.get("phone", ""))).length()
	if phone_length < 10 or phone_length > 15:
		return "Telefone do chip não confirmado para este aparelho."
	if _rs300_apn_command_for_apn(str(location.get("serial", "")), str(location.get("apn", ""))) == "":
		return "Configuração de SMS não suportada para este aparelho."
	return ""


func _review_maintenance_sms(location: Dictionary) -> void:
	if location.get("plate_only", false) and location.get("binding_state", "") != "confirmed":
		return
	var serial := str(location.get("serial", ""))
	if str((maintenance_chip_results.get(serial, {}) as Dictionary).get("status", "")) != "online" or maintenance_analysis_busy:
		return
	var phone := str(location.get("phone", ""))
	var command := _rs300_apn_command_for_apn(serial, str(location.get("apn", "")))
	var unavailable_reason := _maintenance_sms_unavailable_reason(location)
	if unavailable_reason != "":
		_show_warning("SMS indisponível", unavailable_reason + " Nenhum comando foi enviado.")
		return
	_confirm_action("Revisar SMS de configuração", "Destinatário: %s\nSérie: %s\n\n%s\n\nEnvio sujeito à tarifa da conta; custo não confirmado. Enviar não comprova recuperação. Deseja enviar este comando?" % [phone, serial, command], func(): _send_maintenance_sms(phone, command, serial, str(location.get("apn", ""))))


func _send_maintenance_sms(phone: String, command: String, serial: String, apn: String) -> void:
	var reason := _maintenance_sms_unavailable_reason({"phone": phone, "serial": serial, "apn": apn})
	if reason != "":
		_show_warning("SMS indisponível", reason + " Nenhum comando foi enviado.")
		return
	# The existing SMS workflow owns routing and audit, not the chip-status provider.
	var result := await _send_grupo_rs_sms_manual_queue(phone, serial, apn, command, "Mapa Grande · manual")
	if maintenance_mode and str(vehicle_location_selected.get("serial", "")) == serial and tracking_selected_station.is_empty():
		_render_vehicle_location_details(vehicle_location_selected)
	_show_warning("Resultado do SMS", "Solicitação de SMS aceita; isso não confirma entrega nem recuperação. Consulte o histórico e novas comunicações." if result.get("ok", false) else "Envio não confirmado. Verifique o histórico antes de tentar novamente.")
