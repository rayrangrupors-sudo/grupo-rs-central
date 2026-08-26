## Testes rápidos e determinísticos dos módulos puros do Mapa Grande.
extends SceneTree

const Config := preload("res://src/features/big_map/big_map_config.gd")
const GeoProjection := preload("res://src/features/big_map/map_projection.gd")
const RegionService := preload("res://src/features/big_map/map_region_service.gd")
const TileProvider := preload("res://src/features/big_map/map_tile_provider.gd")
const VehicleStatus := preload("res://src/features/big_map/vehicle_status_resolver.gd")
const BigMapCanvas := preload("res://src/features/big_map/big_map_canvas.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_default_region()
	_test_projection_round_trip()
	_test_tile_provider()
	_test_vehicle_status()
	_test_canvas_contract()
	if failures.is_empty():
		print("BIG_MAP_MODULE_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _test_default_region() -> void:
	var region := RegionService.definition(Config.DEFAULT_CITY_ID)
	_check(not region.is_empty(), "Região padrão não encontrada.")
	_check(str(region.get("label", "")) == Config.DEFAULT_CITY_LABEL, "Rótulo de Imperatriz divergente.")
	var region_id := RegionService.region_id_for_coordinates(Config.DEFAULT_LATITUDE, Config.DEFAULT_LONGITUDE)
	_check(region_id == Config.DEFAULT_CITY_ID, "Coordenada central não foi classificada como Imperatriz.")
	var default_view := Config.default_view()
	_check(str(default_view.get("basemap", "")) == Config.BASEMAP_NORMAL, "Mapa Grande não inicia no OpenStreetMap.")
	_check(Config.BASEMAPS.size() == 1, "Configuração ainda expõe mais de um mapa-base.")
	_check(float((default_view.get("center", {}) as Dictionary).get("lat", 0.0)) == Config.DEFAULT_LATITUDE, "Mapa padrão não inicia em Imperatriz.")


func _test_projection_round_trip() -> void:
	var pixel := GeoProjection.lat_lng_to_world_pixel(Config.DEFAULT_LATITUDE, Config.DEFAULT_LONGITUDE, Config.DEFAULT_ZOOM)
	var restored := GeoProjection.world_pixel_to_lat_lng(pixel, Config.DEFAULT_ZOOM)
	# A precisão de Vector2 é suficiente para poucos centímetros neste zoom.
	_check(absf(restored.x - Config.DEFAULT_LATITUDE) < 0.00001, "Latitude não sobreviveu à projeção.")
	_check(absf(restored.y - Config.DEFAULT_LONGITUDE) < 0.00001, "Longitude não sobreviveu à projeção.")


func _test_tile_provider() -> void:
	var url := TileProvider.tile_url(13, 3015, 4210)
	_check(url.begins_with("https://"), "Provedor de tiles não usa HTTPS.")
	_check(url.ends_with("/13/3015/4210.png"), "OpenStreetMap recebeu x/y na ordem errada.")
	_check(TileProvider.cache_key(13, 3015, 4210).begins_with(Config.TILE_PROVIDER_ID), "Cache não inclui o provedor.")
	_check(TileProvider.attribution().strip_edges() != "", "Atribuição do mapa está vazia.")
	var legacy_url := TileProvider.tile_url(13, 3015, 4210, "satellite")
	_check(legacy_url == url, "Estado legado de satélite não convergiu para OpenStreetMap.")
	_check(TileProvider.attribution("satellite").contains("OpenStreetMap"), "Atribuição OSM foi perdida no fallback legado.")
	var jpeg_image := Image.create(2, 2, false, Image.FORMAT_RGB8)
	jpeg_image.fill(Color("#1976b8"))
	var jpeg_bytes := jpeg_image.save_jpg_to_buffer(0.85)
	var jpeg_texture := TileProvider.texture_from_bytes(jpeg_bytes)
	_check(jpeg_texture != null, "Tile JPEG do provedor não foi decodificado.")
	if jpeg_texture != null:
		jpeg_texture = null
	jpeg_image = null


func _test_vehicle_status() -> void:
	var colors := {
		"on": Color("#16a673"),
		"off": Color("#dc3545"),
		"stale": Color("#f2b233"),
		"unknown": Color("#8b98a6"),
	}
	var on_row := {"updated_at": "agora", "speed": "0"}
	var on_status := VehicleStatus.resolve(on_row, true, 0.01, 1, colors)
	_check(str(on_status.get("label", "")) == "Ligado", "Ignição ligada não gerou status Ligado.")
	var off_row := {"updated_at": "agora", "speed": "0"}
	var off_status := VehicleStatus.resolve(off_row, true, 0.25, 0, colors)
	_check(str(off_status.get("label", "")) == "Desligado", "Ignição desligada não gerou status Desligado.")
	var stale_row := {"updated_at": "antiga", "speed": "0"}
	var recent_off_status := VehicleStatus.resolve(stale_row.duplicate(true), true, 3.0, 0, colors)
	_check(str(recent_off_status.get("label", "")) == "Desligado", "Veiculo parado ha 3 h foi marcado como desatualizado.")
	var stale_status := VehicleStatus.resolve(stale_row, true, 25.0, 0, colors)
	_check(str(stale_status.get("label", "")) == "Desatualizado", "Leitura antiga não gerou status Desatualizado.")


func _test_canvas_contract() -> void:
	var canvas := BigMapCanvas.new()
	_check(canvas.basemap_id == Config.BASEMAP_NORMAL, "Canvas não inicia no OpenStreetMap.")
	_check(canvas.has_signal("navigation_requested"), "Canvas perdeu o sinal de navegação.")
	_check(canvas.has_method("set_coverage_profile"), "Canvas perdeu a camada de ERBs.")
	_check(canvas.has_method("set_tracking_locations"), "Canvas perdeu a camada de veículos.")
	_check(canvas.has_method("set_basemap"), "Canvas perdeu o contrato de mapa-base.")
	canvas.set_basemap("satellite")
	_check(canvas.basemap_id == Config.BASEMAP_NORMAL, "Canvas aceitou reativar um provedor removido.")
	canvas.map_zoom = 10
	var far_size: Vector2 = canvas.call("_station_marker_draw_size", false)
	canvas.map_zoom = 13
	var mid_size: Vector2 = canvas.call("_station_marker_draw_size", false)
	canvas.map_zoom = 16
	var close_size: Vector2 = canvas.call("_station_marker_draw_size", false)
	_check(far_size.x < mid_size.x and mid_size.x < close_size.x, "Escala responsiva das ERBs não cresce com o zoom.")
	_check(far_size.x >= 34.0 and close_size.x >= 56.0, "Escala operacional das ERBs continua pequena para identificar a prestadora.")
	_check(float(canvas.call("_station_marker_hit_radius")) >= 28.0, "Hit-area da ERB ficou menor que o mínimo acessível.")
	var claro_identity: Dictionary = canvas.call("_station_operator_identity", "Claro S.A.")
	var unknown_identity: Dictionary = canvas.call("_station_operator_identity", "Prestadora regional")
	var missing_identity: Dictionary = canvas.call("_station_operator_identity", "")
	_check(str(claro_identity.get("label", "")) == "CLARO" and str(claro_identity.get("short", "")) == "C", "Identidade visual da Claro não é explícita.")
	_check(str(unknown_identity.get("label", "")) == "OUTRAS" and str(unknown_identity.get("short", "")) == "O", "Fallback visual OUTRAS não é explícito.")
	_check(str(missing_identity.get("label", "")) == "NÃO DETERMINADA" and str(missing_identity.get("short", "")) == "?", "Prestadora ausente não é identificada como não determinada.")
	var operator_legend: Array[String] = canvas.call("_operator_legend_labels")
	_check(operator_legend == ["TIM", "CLARO", "VIVO", "OUTRAS", "N/D"], "Legenda do modo tracking não cobre todas as identidades de ERB.")
	var canvas_constants: Dictionary = canvas.get_script().get_script_constant_map()
	_check((canvas_constants.get("TRACKING_PIN_DRAW_SIZE", Vector2.ZERO) as Vector2).x >= 30.0, "Agulha normal continua pequena para uso operacional.")
	_check((canvas_constants.get("TRACKING_PIN_SELECTED_SIZE", Vector2.ZERO) as Vector2).y >= 48.0, "Agulha selecionada continua pequena para uso operacional.")
	var tile_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	tile_image.fill(Color.WHITE)
	var tile_texture := ImageTexture.create_from_image(tile_image)
	canvas.set_map_view([{"key": "openstreetmap/13/1/1", "x": 1, "y": 1, "texture": tile_texture}], 13, Vector2.ZERO, Vector2(720, 330), 1, 1)
	canvas.set_tracking_locations([{"plate": "SYN1A01", "lat": -5.5, "lng": -47.5}])
	canvas.set_coverage_profile({"stations": [{"id": "SYN-ERB", "lat": -5.5, "lng": -47.5}]})
	canvas.set_map_view([{"key": "openstreetmap/13/1/1", "x": 1, "y": 1}], 13, Vector2.ZERO, Vector2(720, 330), 1, 1)
	_check(canvas.last_map_view_reused_tile_count == 1, "Canvas não reutilizou textura já visível.")
	_check(canvas.tracking_locations.size() == 1 and canvas.stations.size() == 1, "Troca incremental de viewport reconstruiu marcadores.")
	canvas.map_zoom = 13
	for index in range(80):
		canvas.stations.append({"id": str(index), "lat": Config.DEFAULT_LATITUDE, "lng": Config.DEFAULT_LONGITUDE, "operator": "TIM", "generation": "4G"})
	_check(Config.MIN_ZOOM == 10, "Mapa expõe zoom abaixo do mínimo individual auditável.")
	_check(not bool(canvas.call("_should_cluster_stations")), "ERBs foram substituídas por bolhas no zoom distante.")
	canvas.map_zoom = 16
	_check(not bool(canvas.call("_should_cluster_stations")), "ERBs foram agrupadas no zoom próximo.")
	canvas.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
