## Conversões geográficas do Mapa Grande.
##
## Este script não conhece interface, API, veículo ou ERB. Ele apenas converte
## coordenadas WGS84 para pixels Web Mercator e executa o caminho inverso.
extends RefCounted

const TILE_SIZE := 256.0
const MAX_MERCATOR_LATITUDE := 85.05112878


static func lat_lng_to_tile(latitude: float, longitude: float, zoom: int) -> Dictionary:
	var safe_latitude := clampf(latitude, -MAX_MERCATOR_LATITUDE, MAX_MERCATOR_LATITUDE)
	var latitude_radians := deg_to_rad(safe_latitude)
	var tile_count := pow(2.0, float(zoom))
	var x_float := (longitude + 180.0) / 360.0 * tile_count
	var y_float := (1.0 - log(tan(latitude_radians) + 1.0 / cos(latitude_radians)) / PI) / 2.0 * tile_count
	var tile_x := floori(x_float)
	var tile_y := floori(y_float)
	return {
		"x": tile_x,
		"y": tile_y,
		"frac_x": clampf(x_float - float(tile_x), 0.0, 1.0),
		"frac_y": clampf(y_float - float(tile_y), 0.0, 1.0),
	}


static func lat_lng_to_world_pixel(latitude: float, longitude: float, zoom: int) -> Vector2:
	var tile := lat_lng_to_tile(latitude, longitude, zoom)
	return Vector2(
		(float(tile.get("x", 0)) + float(tile.get("frac_x", 0.0))) * TILE_SIZE,
		(float(tile.get("y", 0)) + float(tile.get("frac_y", 0.0))) * TILE_SIZE
	)


static func world_pixel_to_lat_lng(point: Vector2, zoom: int) -> Vector2:
	var tile_count := pow(2.0, float(zoom))
	var longitude := point.x / TILE_SIZE / tile_count * 360.0 - 180.0
	var mercator_y := PI * (1.0 - 2.0 * point.y / TILE_SIZE / tile_count)
	var latitude := rad_to_deg(atan(sinh(mercator_y)))
	return Vector2(latitude, longitude)


static func distance_km(lat_a: float, lng_a: float, lat_b: float, lng_b: float) -> float:
	const EARTH_RADIUS_KM := 6371.0
	var latitude_delta := deg_to_rad(lat_b - lat_a)
	var longitude_delta := deg_to_rad(lng_b - lng_a)
	var sin_latitude := sin(latitude_delta * 0.5)
	var sin_longitude := sin(longitude_delta * 0.5)
	var haversine := sin_latitude * sin_latitude \
		+ cos(deg_to_rad(lat_a)) * cos(deg_to_rad(lat_b)) * sin_longitude * sin_longitude
	return EARTH_RADIUS_KM * 2.0 * atan2(sqrt(haversine), sqrt(maxf(1.0 - haversine, 0.0)))
