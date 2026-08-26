## Controller de teste que captura navegação sem rede, tiles ou API.
extends "res://src/features/big_map/big_map_tracking_layout.gd"

const GeoProjection := preload("res://src/features/big_map/map_projection.gd")

var offline_reload_calls := 0
var offline_query_refresh_calls := 0
var offline_last_view: Dictionary = {}
var offline_api_rows: Array[Dictionary] = []


func _ready() -> void:
	# O controller entra na SceneTree para exercitar o callback real de teclado,
	# mas nenhuma inicialização global/remota do dashboard pode ser iniciada.
	pass


func _initialize_tracking_erb_layer() -> void:
	# O teste injeta um índice sintético; não lê o catálogo nacional em disco.
	pass


func _fetch_vehicle_location_api_rows_smart(query: String = "") -> Dictionary:
	# Mock exclusivo da API: nenhum Store, portal, decoder local ou rede.
	offline_query_refresh_calls += 1
	var matches: Array[Dictionary] = []
	for row in offline_api_rows:
		var client_match := query.strip_edges().to_lower().begins_with("cliente:") \
				and _search_key(str(row.get("client", ""))) == _search_key(query.substr(query.find(":") + 1))
		if client_match or vehicle_location_integration.row_matches_exact_query(row, query):
			var api_row := row.duplicate(true)
			api_row["source"] = "API Grupo RS"
			matches.append(api_row)
	return {
		"ok": true,
		"rows": matches,
		"not_found": matches.is_empty(),
		"stage": "location",
		"response_code": 200,
		"parse_ok": true,
	}


func _debounced_vehicle_location_query(_generation: int) -> void:
	# Digitação preserva o callback real e o loading imediato, sem agendar rede.
	pass


func _reload_vehicle_location_map(generation: int, rows: Array, view_override: Dictionary = {}) -> void:
	if generation != vehicle_location_map_generation or vehicle_location_map_canvas == null:
		return
	offline_reload_calls += 1
	offline_last_view = view_override.duplicate(true)
	if offline_last_view.is_empty():
		offline_last_view = _vehicle_location_map_view(rows)
	var center: Dictionary = offline_last_view.get("center", {})
	var zoom := int(offline_last_view.get("zoom", 13))
	var viewport := Vector2(1000, 520)
	var center_world: Vector2 = GeoProjection.lat_lng_to_world_pixel(float(center.get("lat", 0.0)), float(center.get("lng", 0.0)), zoom)
	vehicle_location_map_canvas.set_basemap(str(offline_last_view.get("basemap", vehicle_location_map_canvas.basemap_id)))
	vehicle_location_map_canvas.set_map_view([], zoom, center_world - viewport * 0.5, viewport, 0, 0)
	vehicle_location_map_canvas.set_tracking_locations(rows)
	if not vehicle_location_selected.is_empty():
		vehicle_location_map_canvas.select_tracking_by_key(str(vehicle_location_selected.get("serial", vehicle_location_selected.get("plate", ""))))
