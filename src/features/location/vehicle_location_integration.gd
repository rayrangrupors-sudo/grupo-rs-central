## Coordenador puro da integração entre localização, ERBs e operadora.
##
## Não acessa API nem cria nós. Recebe dados já obtidos pelos módulos
## especializados e produz o estado que a única instância do mapa deve exibir.
class_name VehicleLocationIntegration
extends RefCounted

const GeoProjection := preload("res://src/features/big_map/map_projection.gd")

var request_generation := 0


func begin_request() -> int:
	request_generation += 1
	return request_generation


func is_current(generation: int) -> bool:
	return generation == request_generation


func select_vehicle(rows: Array, preferred_key: String = "") -> Dictionary:
	var preferred := preferred_key.strip_edges().to_lower()
	var fallback: Dictionary = {}
	for value in rows:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var row := (value as Dictionary).duplicate(true)
		if fallback.is_empty():
			fallback = row
		if preferred != "":
			for field in ["vehicle_id", "equipment_id", "serial", "plate", "client", "client_id"]:
				if str(row.get(field, "")).strip_edges().to_lower() == preferred:
					return row
	return fallback


func map_device(location: Dictionary) -> Dictionary:
	var latitude := _number(location.get("lat", 0.0))
	var longitude := _number(location.get("lng", 0.0))
	return {
		"serial": str(location.get("serial", "")),
		"plate": str(location.get("plate", "")),
		"location_available": valid_coordinates(latitude, longitude),
		"latitude": latitude,
		"longitude": longitude,
		"operator": str(location.get("operator", "")),
		"platform_delay_minutes": -1,
		"estimated_signal_score": 0,
	}


func compose_map_state(location: Dictionary, stations: Array, operator_info: Dictionary = {}) -> Dictionary:
	var vehicle := location.duplicate(true)
	var nearby: Array[Dictionary] = []
	var seen: Dictionary = {}
	var latitude := _number(vehicle.get("lat", 0.0))
	var longitude := _number(vehicle.get("lng", 0.0))
	if valid_coordinates(latitude, longitude):
		for value in stations:
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var station := (value as Dictionary).duplicate(true)
			var station_lat := _number(station.get("lat", 0.0))
			var station_lng := _number(station.get("lng", 0.0))
			if not valid_coordinates(station_lat, station_lng):
				continue
			var key := "%s|%s|%s" % [
				str(station.get("id", station.get("code", ""))),
				str(station.get("generation", "")),
				"%.6f,%.6f" % [station_lat, station_lng],
			]
			if seen.has(key):
				continue
			seen[key] = true
			station["distance_km"] = GeoProjection.distance_km(latitude, longitude, station_lat, station_lng)
			nearby.append(station)
	nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance_km", INF)) < float(b.get("distance_km", INF))
	)
	var nearest: Dictionary = nearby[0] if not nearby.is_empty() else {}
	vehicle["nearby_towers"] = nearby
	vehicle["nearby_tower_count"] = nearby.size()
	vehicle["nearest_tower"] = nearest.duplicate(true)
	vehicle["nearest_tower_distance_km"] = float(nearest.get("distance_km", -1.0))
	vehicle["tracker_operator"] = str(operator_info.get("operator", vehicle.get("operator", ""))).strip_edges()
	vehicle["tracker_operator_source"] = str(operator_info.get("source", "")).strip_edges()
	vehicle["tracker_operator_known"] = vehicle["tracker_operator"] != ""
	return {
		"vehicle": vehicle,
		"stations": nearby,
		"operator": operator_info.duplicate(true),
		"has_vehicle_location": valid_coordinates(latitude, longitude),
	}


func valid_coordinates(latitude: float, longitude: float) -> bool:
	return is_finite(latitude) and is_finite(longitude) \
			and latitude >= -90.0 and latitude <= 90.0 \
			and longitude >= -180.0 and longitude <= 180.0 \
			and not (is_zero_approx(latitude) and is_zero_approx(longitude))


func _number(value: Variant) -> float:
	var text := str(value).replace(",", ".").strip_edges()
	return text.to_float() if text.is_valid_float() else 0.0
