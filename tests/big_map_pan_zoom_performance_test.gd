## Benchmark offline do caminho real de canvas/loader durante rajada de gestos.
extends SceneTree

const Dashboard := preload("res://tests/fixtures/offline_tile_dashboard.gd")
const Canvas := preload("res://src/features/big_map/big_map_canvas.gd")
const Config := preload("res://src/features/big_map/big_map_config.gd")

var failures: Array[String] = []
var dashboard: Node
var canvas: Control
var navigation_requests := 0
var navigation_loads_in_flight := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	dashboard = Dashboard.new()
	root.add_child(dashboard)
	canvas = Canvas.new()
	dashboard.add_child(canvas)
	canvas.size = Vector2(960, 540)
	await process_frame
	canvas.set_tracking_mode(true)
	var tracking_locations: Array[Dictionary] = [
		{"plate": "SYN0A00", "serial": "SYN-0000", "lat": Config.DEFAULT_LATITUDE, "lng": Config.DEFAULT_LONGITUDE, "ignition": 1},
	]
	canvas.set_tracking_locations(tracking_locations)
	canvas.set_coverage_profile({"stations": _synthetic_stations(365)})
	canvas.navigation_requested.connect(_on_navigation)
	dashboard.offline_http_delay_msec = 35
	await _run_scenario("distante", 10, 1, Vector2(0.02, -0.02))
	await _run_scenario("medio", 12, 1, Vector2(-0.03, 0.03))
	await _run_scenario("proximo", 13, 3, Vector2(0.04, 0.04))
	_check(int(dashboard.offline_profile_build_calls) == 0, "Benchmark executou o perfil regional legado.")

	var empty_tracking_locations: Array[Dictionary] = []
	canvas.set_tracking_locations(empty_tracking_locations)
	canvas.set_coverage_profile({"stations": []})
	dashboard.smart_4g_tile_texture_cache.clear()
	dashboard.smart_4g_tile_cache.clear()
	dashboard.smart_4g_tile_cache_order.clear()
	dashboard.remove_child(canvas)
	canvas.free()
	root.remove_child(dashboard)
	dashboard.free()
	await process_frame
	if failures.is_empty():
		print("BIG_MAP_PAN_ZOOM_PERFORMANCE_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _run_scenario(label: String, start_zoom: int, zoom_steps: int, center_offset: Vector2) -> void:
	var latitude := Config.DEFAULT_LATITUDE + center_offset.x
	var longitude := Config.DEFAULT_LONGITUDE + center_offset.y
	await dashboard.call("_load_smart_4g_map_tiles", canvas, [], "all", _view(latitude, longitude, start_zoom), true)
	canvas.call("_station_visual_positions")
	canvas.call("_station_visual_groups")
	var position_rebuilds_before := int(canvas.station_position_rebuild_count)
	var group_rebuilds_before := int(canvas.station_group_rebuild_count)
	var requests_before := navigation_requests
	var before_state: Dictionary = dashboard.call("_smart_4g_tile_cache_state")
	var before_network := int(before_state.get("network_requests", 0))
	var before_decodes := int(before_state.get("decodes", 0))
	var cancelled_before := int(before_state.get("cancelled_loads", 0))
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var memory_peak_before := int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX))
	var input_started_usec := Time.get_ticks_usec()
	for _step in range(zoom_steps):
		canvas.call("_request_zoom", canvas.size * 0.5, 1)
	canvas.drag_offset = Vector2(30.0, 12.0)
	canvas.call("_request_pan_navigation")
	canvas.drag_offset = Vector2(18.0, -8.0)
	canvas.call("_request_pan_navigation")
	var input_preview_msec := float(Time.get_ticks_usec() - input_started_usec) / 1000.0
	var expected_zoom := mini(start_zoom + zoom_steps, canvas.MAX_MAP_ZOOM)
	var request_delta := navigation_requests - requests_before
	_check(int(canvas.call("_display_map_zoom")) == expected_zoom, "%s: preview não acumulou o zoom esperado." % label)
	_check(request_delta == zoom_steps + 2, "%s: canvas descartou gestos da rajada." % label)

	var frame_intervals: Array[float] = []
	var last_frame_usec := Time.get_ticks_usec()
	var fallback_seen := false
	var load_settled := false
	var stable_settle_frames := 0
	var last_settlement_signature := ""
	for _frame in range(900):
		await process_frame
		var now_usec := Time.get_ticks_usec()
		frame_intervals.append(float(now_usec - last_frame_usec) / 1000.0)
		last_frame_usec = now_usec
		fallback_seen = fallback_seen or not canvas.fallback_map_tiles.is_empty()
		var settle_state: Dictionary = dashboard.call("_smart_4g_tile_cache_state")
		var settlement_signature := "%d:%d:%d:%d:%d:%d" % [
			int(settle_state.get("network_requests", 0)),
			int(settle_state.get("decodes", 0)),
			int(settle_state.get("cancelled_loads", 0)),
			int(settle_state.get("last_load_msec", -1)),
			int(settle_state.get("last_missing_tiles", -1)),
			navigation_loads_in_flight,
		]
		var winning_load_finished: bool = (
			not canvas.navigation_loading
			and int(canvas.map_zoom) == expected_zoom
			and not bool(canvas.navigation_target_active)
			and canvas.fallback_map_tiles.is_empty()
			and navigation_loads_in_flight == 0
		)
		if winning_load_finished and settlement_signature == last_settlement_signature:
			stable_settle_frames += 1
		else:
			stable_settle_frames = 0
		last_settlement_signature = settlement_signature
		if stable_settle_frames >= 3:
			load_settled = true
			break
	var final_state: Dictionary = dashboard.call("_smart_4g_tile_cache_state")
	var network_delta := int(final_state.get("network_requests", 0)) - before_network
	var decode_delta := int(final_state.get("decodes", 0)) - before_decodes
	var missing_tiles := int(final_state.get("last_missing_tiles", 0))
	var extra_downloads := maxi(0, network_delta - missing_tiles)
	var memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var memory_peak_after := int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX))
	var memory_delta := maxi(memory_after - memory_before, memory_peak_after - memory_peak_before)
	var p50 := _percentile(frame_intervals, 0.50)
	var p95 := _percentile(frame_intervals, 0.95)
	var max_frame := _percentile(frame_intervals, 1.0)

	_check(input_preview_msec < 20.0, "%s: resposta visual excedeu 20 ms." % label)
	_check(load_settled, "%s: carga vencedora não liquidou dentro do timeout." % label)
	_check(navigation_loads_in_flight == 0, "%s: coroutine de navegação permaneceu ativa." % label)
	_check(int(canvas.map_zoom) == expected_zoom, "%s: última viewport não venceu a rajada." % label)
	_check(int(final_state.get("cancelled_loads", 0)) - cancelled_before >= request_delta - 1, "%s: loads intermediários não foram coalescidos." % label)
	_check(network_delta == missing_tiles, "%s: mais de uma viewport iniciou downloads." % label)
	_check(decode_delta == network_delta, "%s: tiles foram decodificados mais de uma vez." % label)
	_check(int(final_state.get("orphan_textures", -1)) == 0, "%s: decode deixou textura órfã." % label)
	_check(int(final_state.get("last_first_tile_msec", -1)) >= 0, "%s: first-paint não foi medido." % label)
	_check(fallback_seen, "%s: fallback não permaneceu durante a transição." % label)
	_check(canvas.fallback_map_tiles.is_empty(), "%s: fallback não foi liberado após grade completa." % label)
	_check(int(canvas.station_position_rebuild_count) <= position_rebuilds_before + request_delta, "%s: ERBs foram reprojetadas além de uma vez por gesto." % label)
	_check(int(canvas.station_group_rebuild_count) <= group_rebuilds_before + request_delta, "%s: ERBs foram reagrupadas além de uma vez por gesto." % label)
	_check(p95 <= 50.0 and max_frame <= 150.0, "%s: frames excederam o teto: p95=%.2f max=%.2f ms." % [label, p95, max_frame])
	_check(memory_delta <= 256 * 1024 * 1024, "%s: delta/pico de memória excedeu 256 MiB." % label)

	print("BIG_MAP_PAN_ZOOM_PERFORMANCE: scenario=%s start_zoom=%d final_zoom=%d requests=%d winning_missing_tiles=%d extra_downloads=%d tiles=%d first_paint_ms=%d total_ms=%d input_preview_ms=%.3f frame_p50_ms=%.3f frame_p95_ms=%.3f frame_max_ms=%.3f memory_delta_bytes=%d memory_static_bytes=%d memory_static_peak_bytes=%d source_bytes=%d texture_entries=%d network=%d hits=%d decodes=%d decode_max_ms=%d evictions=%d cancelled_loads=%d cancelled_http=%d redraws=%d station_position_rebuilds=%d station_group_rebuilds=%d" % [
		label, start_zoom, expected_zoom, request_delta, missing_tiles, extra_downloads, int(final_state.get("last_total_tiles", 0)), int(final_state.get("last_first_tile_msec", -1)), int(final_state.get("last_load_msec", -1)), input_preview_msec, p50, p95, max_frame, memory_delta, memory_after, memory_peak_after, int(final_state.get("source_bytes", 0)), int(final_state.get("texture_entries", 0)), network_delta, int(final_state.get("cache_hits", 0)), decode_delta, int(final_state.get("decode_max_msec", 0)), int(final_state.get("evictions", 0)), int(final_state.get("cancelled_loads", 0)) - cancelled_before, int(final_state.get("cancelled_http", 0)), int(canvas.progressive_redraw_count), int(canvas.station_position_rebuild_count), int(canvas.station_group_rebuild_count),
	])


func _on_navigation(latitude: float, longitude: float, zoom: int) -> void:
	navigation_requests += 1
	call_deferred("_run_navigation_load", latitude, longitude, zoom)


func _run_navigation_load(latitude: float, longitude: float, zoom: int) -> void:
	navigation_loads_in_flight += 1
	await dashboard.call("_load_smart_4g_map_tiles", canvas, [], "all", _view(latitude, longitude, zoom), true)
	navigation_loads_in_flight -= 1


func _view(latitude: float, longitude: float, zoom: int) -> Dictionary:
	return {
		"center": {"lat": latitude, "lng": longitude},
		"zoom": zoom,
		"basemap": Config.DEFAULT_BASEMAP,
		"interactive": true,
	}


func _synthetic_stations(amount: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(amount):
		result.append({
			"id": "PERF-%d" % index,
			"lat": Config.DEFAULT_LATITUDE + float(index % 19) * 0.00018,
			"lng": Config.DEFAULT_LONGITUDE + float(index / 19) * 0.00018,
			"operator": "TIM",
			"generation": "4G",
		})
	return result


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(ceili(float(sorted.size()) * ratio) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
