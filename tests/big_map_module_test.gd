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


func _test_projection_round_trip() -> void:
	var pixel := GeoProjection.lat_lng_to_world_pixel(Config.DEFAULT_LATITUDE, Config.DEFAULT_LONGITUDE, Config.DEFAULT_ZOOM)
	var restored := GeoProjection.world_pixel_to_lat_lng(pixel, Config.DEFAULT_ZOOM)
	# A precisão de Vector2 é suficiente para poucos centímetros neste zoom.
	_check(absf(restored.x - Config.DEFAULT_LATITUDE) < 0.00001, "Latitude não sobreviveu à projeção.")
	_check(absf(restored.y - Config.DEFAULT_LONGITUDE) < 0.00001, "Longitude não sobreviveu à projeção.")


func _test_tile_provider() -> void:
	var url := TileProvider.tile_url(13, 3015, 4210)
	_check(url.begins_with("https://"), "Provedor de tiles não usa HTTPS.")
	_check(url.ends_with("/13/4210/3015"), "World Imagery recebeu x/y na ordem errada.")
	_check(TileProvider.cache_key(13, 3015, 4210).begins_with(Config.TILE_PROVIDER_ID), "Cache não inclui o provedor.")
	_check(TileProvider.attribution().strip_edges() != "", "Atribuição do mapa está vazia.")
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
	var stale_status := VehicleStatus.resolve(stale_row, true, 3.0, 0, colors)
	_check(str(stale_status.get("label", "")) == "Desatualizado", "Leitura antiga não gerou status Desatualizado.")


func _test_canvas_contract() -> void:
	var canvas := BigMapCanvas.new()
	_check(canvas.has_signal("navigation_requested"), "Canvas perdeu o sinal de navegação.")
	_check(canvas.has_method("set_coverage_profile"), "Canvas perdeu a camada de ERBs.")
	_check(canvas.has_method("set_tracking_locations"), "Canvas perdeu a camada de veículos.")
	canvas.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
