## Coordenador puro da integração entre localização, ERBs e operadora.
##
## Não acessa API nem cria nós. Recebe dados já obtidos pelos módulos
## especializados e produz o estado que a única instância do mapa deve exibir.
class_name VehicleLocationIntegration
extends RefCounted

const GeoProjection := preload("res://src/features/big_map/map_projection.gd")

var request_generation := 0

const QUERY_KIND_PLATE := "plate"
const QUERY_KIND_SERIAL := "serial"
const QUERY_KIND_CLIENT := "client"
const QUERY_ALLOWED_CHARACTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const QUERY_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const QUERY_DIGITS := "0123456789"


func begin_request() -> int:
	request_generation += 1
	return request_generation


func is_current(generation: int) -> bool:
	return generation == request_generation


func select_vehicle(rows: Array, preferred_key: String = "") -> Dictionary:
	## Seleção visual tolerante: preserva o comportamento legado de usar a
	## primeira linha quando não existe uma preferência. Não usar como busca.
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


func normalize_location_query(value: String) -> String:
	## Placas formatadas e séries são comparadas sem máscara, espaços ou caixa.
	## Somente caracteres ASCII alfanuméricos entram na chave de correspondência.
	var normalized := ""
	var upper := value.strip_edges().to_upper()
	for index in range(upper.length()):
		var character := upper.substr(index, 1)
		if QUERY_ALLOWED_CHARACTERS.contains(character):
			normalized += character
	return normalized


func describe_location_query(value: String) -> Dictionary:
	var normalized := normalize_location_query(value)
	return {
		"normalized": normalized,
		"kind": QUERY_KIND_PLATE if _looks_like_brazilian_plate(normalized) else QUERY_KIND_SERIAL,
		"valid": normalized.length() >= 2,
	}


func row_matches_exact_query(row: Dictionary, query: String) -> bool:
	var descriptor := describe_location_query(query)
	var expected := str(descriptor.get("normalized", ""))
	if not bool(descriptor.get("valid", false)):
		return false
	return _row_matches_normalized_fields(row, expected, _plate_fields()) \
			or _row_matches_normalized_fields(row, expected, _serial_fields())


func find_exact_vehicle_result(rows: Array, query: String) -> Dictionary:
	var descriptor := describe_location_query(query)
	var expected := str(descriptor.get("normalized", ""))
	if not bool(descriptor.get("valid", false)):
		return {"found": false, "ambiguous": false, "row": {}}
	var plate_matches: Array[Dictionary] = []
	var serial_matches: Array[Dictionary] = []
	for value in rows:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var row := value as Dictionary
		if _row_matches_normalized_fields(row, expected, _plate_fields()):
			plate_matches.append(row)
		if _row_matches_normalized_fields(row, expected, _serial_fields()):
			serial_matches.append(row)
	var unique_matches: Array[Dictionary] = []
	var seen: Dictionary = {}
	for row in plate_matches + serial_matches:
		var key := _stable_row_key(row)
		if not seen.has(key):
			seen[key] = true
			unique_matches.append(row)
	if unique_matches.size() != 1:
		return {
			"found": false,
			"ambiguous": unique_matches.size() > 1,
			"row": {},
			"plate_matches": plate_matches.size(),
			"serial_matches": serial_matches.size(),
		}
	return {
		"found": true,
		"ambiguous": false,
		"row": unique_matches[0].duplicate(true),
		"match_kind": "both" if not plate_matches.is_empty() and not serial_matches.is_empty() else ("plate" if not plate_matches.is_empty() else "serial"),
	}


func find_exact_vehicle(rows: Array, query: String) -> Dictionary:
	## Busca estrita: ausência de correspondência retorna vazio e jamais usa a
	## primeira linha como fallback.
	return (find_exact_vehicle_result(rows, query).get("row", {}) as Dictionary).duplicate(true)


func _plate_fields() -> Array[String]:
	return ["plate", "placa", "Placa"]


func _serial_fields() -> Array[String]:
	return [
		"serial", "serie", "série", "numero_serie", "numeroSerie",
		"equipment_serial", "equipment_number", "equipment_id",
	]


func _row_matches_normalized_fields(row: Dictionary, expected: String, fields: Array[String]) -> bool:
	for field in fields:
		var candidate := normalize_location_query(str(row.get(field, "")))
		if candidate != "" and candidate == expected:
			return true
	return false


func _stable_row_key(row: Dictionary) -> String:
	for field in ["vehicle_id", "equipment_id", "serial", "plate"]:
		var value := normalize_location_query(str(row.get(field, "")))
		if value != "":
			return "%s:%s" % [field, value]
	return "row:%s" % JSON.stringify(row)


func _looks_like_brazilian_plate(value: String) -> bool:
	if value.length() != 7:
		return false
	return QUERY_LETTERS.contains(value.substr(0, 1)) \
			and QUERY_LETTERS.contains(value.substr(1, 1)) \
			and QUERY_LETTERS.contains(value.substr(2, 1)) \
			and QUERY_DIGITS.contains(value.substr(3, 1)) \
			and QUERY_ALLOWED_CHARACTERS.contains(value.substr(4, 1)) \
			and QUERY_DIGITS.contains(value.substr(5, 1)) \
			and QUERY_DIGITS.contains(value.substr(6, 1))


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
