## Cenários fictícios controlados do Mapa Grande.
## Não usa API real, portal, credenciais, coordenadas reais ou identificadores reais.
extends SceneTree

const Controller := preload("res://tests/fixtures/offline_big_map_controller.gd")
const Integration := preload("res://src/features/location/vehicle_location_integration.gd")
const MapProjection := preload("res://src/features/big_map/map_projection.gd")
const Config := preload("res://src/features/big_map/big_map_config.gd")

class ControlledDashboard:
	extends Controller

	var scenario := "found"
	var scenario_rows: Array[Dictionary] = []
	var delay_frames := 0

	func _fetch_vehicle_location_api_rows_smart(query: String = "") -> Dictionary:
		offline_query_refresh_calls += 1
		for _index in range(delay_frames):
			await get_tree().process_frame
		match scenario:
			"empty":
				return {"ok": true, "rows": [], "not_found": true, "stage": "location", "response_code": 200, "parse_ok": true}
			"timeout":
				return {"ok": false, "rows": [], "timeout": true, "stage": "location"}
			"unauthorized":
				return {"ok": false, "rows": [], "response_code": 401, "stage": "auth", "relogin_attempted": true}
			"stale":
				return {"ok": true, "rows": scenario_rows.duplicate(true), "not_found": false, "stage": "location", "response_code": 200, "parse_ok": true}
			_:
				var matches: Array[Dictionary] = []
				for row in scenario_rows:
					if vehicle_location_integration.row_matches_exact_query(row, query):
						var api_row := row.duplicate(true)
						api_row["source"] = "API Grupo RS"
						matches.append(api_row)
				return {"ok": true, "rows": matches, "not_found": matches.is_empty(), "stage": "location", "response_code": 200, "parse_ok": true}

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := ControlledDashboard.new()
	dashboard.set("vehicle_location_integration", Integration.new())
	var view: Control = dashboard.call("_build_vehicle_location_view")
	root.add_child(dashboard)
	dashboard.add_child(view)
	await process_frame
	var canvas: Control = dashboard.get("vehicle_location_map_canvas")
	_prepare_canvas(canvas)

	await _test_found_location(dashboard, view, canvas)
	await _test_without_position(dashboard, view, canvas)
	await _test_invalid_position(dashboard, view, canvas)
	await _test_empty_response(dashboard, view, canvas)
	await _test_timeout(dashboard, view, canvas)
	await _test_unauthorized_reauth(dashboard, view, canvas)
	await _test_stale_response_discard(dashboard, view, canvas)
	await _test_vehicle_station_overlap_priority(dashboard, view, canvas)

	root.remove_child(dashboard)
	dashboard.queue_free()
	await process_frame
	if failures.is_empty():
		print("BIG_MAP_CONTROLLED_SCENARIOS_TEST: OK scenarios=8 api_real=false sanitized=true")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _prepare_canvas(canvas: Control) -> void:
	var viewport := Vector2(1000, 520)
	var center := MapProjection.lat_lng_to_world_pixel(Config.DEFAULT_LATITUDE, Config.DEFAULT_LONGITUDE, 13)
	canvas.size = viewport
	var no_tiles: Array[Dictionary] = []
	canvas.set_map_view(no_tiles, 13, center - viewport * 0.5, viewport, 0, 0)
	canvas.set_tracking_mode(true)
	canvas.set_station_visibility(true)


func _test_found_location(dashboard: Node, view: Control, canvas: Control) -> void:
	var row := _vehicle("TST1A01", "SN-1001", true, "valid", 1, Time.get_datetime_string_from_system(false, true))
	dashboard.set("scenario", "found")
	dashboard.set("scenario_rows", [row])
	await _apply_synthetic_result(dashboard, view, "TST1A01", [row])
	_check(str(view.query_state_label.text) == "Localização encontrada", "Encontrado não atualizou estado visual.")
	_check(str(view.metric_labels["Total"].text) == "1", "Encontrado não atualizou total.")
	_check(str(view.metric_labels["Com posição"].text) == "1", "Encontrado não contou posição válida.")
	_check(canvas.tracking_locations.size() == 1, "Encontrado não criou marcador.")
	_check(int(canvas.selected_tracking_index) == 0, "Encontrado não selecionou marcador.")
	_check(str((dashboard.get("vehicle_location_selected") as Dictionary).get("source", "")) == "API Grupo RS", "Encontrado perdeu origem sanitizada da API.")
	_check(str((dashboard.call("_location_monitoring_status", row) as Dictionary).get("label", "")) == "Ligado", "Status ligado não foi resolvido.")
	_check(str(view.updated_label.text).strip_edges() != "", "Última atualização visual ficou vazia.")
	_check(str(canvas.basemap_id) == Config.DEFAULT_BASEMAP, "OSM/base do mapa foi alterado.")


func _test_without_position(dashboard: Node, view: Control, canvas: Control) -> void:
	var row := _vehicle("TST1A02", "SN-1002", false, "missing", 0, Time.get_datetime_string_from_system(false, true))
	dashboard.set("scenario", "found")
	dashboard.set("scenario_rows", [row])
	await _apply_synthetic_result(dashboard, view, "SN-1002", [row])
	_check(str(view.query_state_label.text) == "Veículo encontrado sem posição", "Sem posição não mostrou estado correto.")
	_check(str(view.metric_labels["Sem posição"].text) == "1", "Sem posição não atualizou métrica.")
	_check(canvas.tracking_locations.is_empty(), "Sem posição criou marcador indevido.")


func _test_invalid_position(dashboard: Node, view: Control, canvas: Control) -> void:
	var row := _vehicle("TST1A03", "SN-1003", false, "invalid", 1, Time.get_datetime_string_from_system(false, true))
	dashboard.set("scenario", "found")
	dashboard.set("scenario_rows", [row])
	await _apply_synthetic_result(dashboard, view, "TST1A03", [row])
	_check(str(view.query_state_label.text) == "Posição recebida em formato inválido", "Posição inválida não mostrou estado correto.")
	_check(canvas.tracking_locations.is_empty(), "Posição inválida criou marcador indevido.")


func _test_empty_response(dashboard: Node, view: Control, canvas: Control) -> void:
	dashboard.set("scenario", "empty")
	dashboard.set("scenario_rows", [])
	await _apply_synthetic_result(dashboard, view, "ZZZ9Z99", [])
	_check(str(view.query_state_label.text) == "Nenhuma localização encontrada", "Resposta vazia não mostrou not_found.")
	_check((dashboard.get("vehicle_location_query_queue") as Array).is_empty(), "Resposta vazia entrou na fila.")
	_check(canvas.tracking_locations.is_empty(), "Resposta vazia criou marcador.")


func _test_timeout(dashboard: Node, view: Control, _canvas: Control) -> void:
	dashboard.set("scenario", "timeout")
	dashboard.set("scenario_rows", [])
	await _apply_synthetic_result(dashboard, view, "TST1A04", [], {"category": "timeout"})
	_check(str(view.query_state_label.text) == "Tempo limite ao consultar a API Grupo RS", "Timeout não mostrou diagnóstico sanitizado.")


func _test_unauthorized_reauth(dashboard: Node, view: Control, _canvas: Control) -> void:
	dashboard.set("scenario", "unauthorized")
	dashboard.set("scenario_rows", [])
	await _apply_synthetic_result(dashboard, view, "TST1A05", [], {"category": "unauthorized"})
	_check(str(view.query_state_label.text) == "Sessão da API recusada após nova autenticação", "401/reauth simulado não mostrou diagnóstico sanitizado.")


func _test_stale_response_discard(dashboard: Node, view: Control, canvas: Control) -> void:
	var old_row := _vehicle("TST1A06", "SN-1006", true, "valid", 1, "2026-01-01 00:00:00")
	var new_row := _vehicle("TST1A07", "SN-1007", true, "valid", 1, Time.get_datetime_string_from_system(false, true))
	await _apply_synthetic_result(dashboard, view, "TST1A06", [old_row])
	await _apply_synthetic_result(dashboard, view, "TST1A07", [new_row])
	_check(str((dashboard.get("vehicle_location_selected") as Dictionary).get("serial", "")) == "SN-1007", "Resposta obsoleta substituiu a consulta mais recente.")
	_check(canvas.tracking_locations.size() == 1, "Resposta obsoleta alterou quantidade de marcadores.")


func _test_vehicle_station_overlap_priority(dashboard: Node, _view: Control, canvas: Control) -> void:
	var row := _vehicle("TST1A08", "SN-1008", true, "valid", 1, Time.get_datetime_string_from_system(false, true))
	var stations: Array[Dictionary] = [{
		"id": "ERB-FICTICIA-1",
		"operator": "TIM",
		"generation": "4G",
		"city": "Cidade Fictícia",
		"status": "Licenciada",
		"lat": row.get("lat"),
		"lng": row.get("lng"),
	}]
	canvas.set_coverage_profile({"stations": stations, "metadata": {}})
	var rows: Array[Dictionary] = [row]
	canvas.set_tracking_locations(rows)
	var before_zoom := int(canvas.map_zoom)
	var before_top_left: Vector2 = canvas.map_top_left
	var position: Vector2 = canvas.call("_tracking_map_position", 0, row)
	var selected_tracking := int(canvas.call("_nearest_tracking_index", position))
	var selected_station := int(canvas.call("_nearest_station_index", position))
	_check(selected_tracking == 0, "Sobreposição veículo/ERB não priorizou veículo.")
	_check(selected_station >= 0, "ERB sobreposta não ficou selecionável como fallback.")
	canvas.select_tracking_by_key("SN-1008")
	_check(int(canvas.map_zoom) == before_zoom, "Seleção visual alterou escala do mapa.")
	_check((canvas.map_top_left as Vector2).distance_to(before_top_left) < 0.001, "Seleção visual alterou posição do mapa.")


func _apply_synthetic_result(
	dashboard: Node,
	view: Control,
	query: String,
	rows: Array[Dictionary],
	diagnostic: Dictionary = {}
) -> void:
	(dashboard.get("vehicle_location_query_queue") as Array).clear()
	(dashboard.get("vehicle_location_pending_queries") as Array).clear()
	dashboard.set("vehicle_location_rows", rows.duplicate(true))
	dashboard.set("vehicle_location_refreshing", false)
	dashboard.set("vehicle_location_last_query_error_count", 1 if not diagnostic.is_empty() else 0)
	var next_diagnostic := diagnostic.duplicate(true)
	if next_diagnostic.is_empty():
		next_diagnostic["category"] = "found" if not rows.is_empty() else "not_found"
	dashboard.set("vehicle_location_last_query_diagnostic", next_diagnostic)
	var queue: Array = dashboard.get("vehicle_location_query_queue")
	if not rows.is_empty():
		queue.append(query)
	dashboard.call("_refresh_vehicle_location_queue_ui")
	view.query_input.text = query
	view.query_input.text_changed.emit(query)
	dashboard.set("vehicle_location_query_generation", int(dashboard.get("vehicle_location_query_generation")) + 1)
	dashboard.call("_apply_vehicle_location_filters")
	await process_frame


func _wait_query_finished(dashboard: Node, minimum_calls: int = -1) -> void:
	for _frame in range(80):
		await process_frame
		var calls_ok := minimum_calls < 0 or int(dashboard.get("offline_query_refresh_calls")) >= minimum_calls
		if calls_ok \
				and not bool(dashboard.get("vehicle_location_refreshing")) \
				and (dashboard.get("vehicle_location_pending_queries") as Array).is_empty():
			return
	_check(false, "Consulta sintética não encerrou no limite.")


func _vehicle(plate: String, serial: String, valid: bool, coordinate_state: String, ignition: Variant, updated_at: String) -> Dictionary:
	return {
		"plate": plate,
		"serial": serial,
		"client": "Cliente Fictício",
		"lat": -5.5200 if valid else 0.0,
		"lng": -47.4800 if valid else 0.0,
		"coordinates_valid": valid,
		"coordinate_state": coordinate_state,
		"ignition": ignition,
		"speed": "24" if ignition == 1 else "0",
		"updated_at": updated_at,
		"source": "API Grupo RS",
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
