class_name AnatelCoverage
extends RefCounted

const NATIONAL_DATA_PATH := "res://data/anatel_smp_brasil.json"
const REGIONAL_DATA_PATH := "res://data/anatel_smp_regional.json"
const LEGACY_NATIONAL_DATA_PATH := "res://data/anatel_smp_2g4g_brasil.json"
const LEGACY_REGIONAL_DATA_PATH := "res://data/anatel_smp_2g4g_regional.json"
const DEFAULT_DATA_PATH := REGIONAL_DATA_PATH
const OPERATORS := ["CLARO", "TIM", "VIVO"]
const MAP_OPERATORS := ["CLARO", "TIM", "VIVO", "OUTRAS"]
const GENERATIONS := ["2G", "3G", "4G", "5G"]
const EARTH_RADIUS_KM := 6371.0
const REAL_WINDOW_MINUTES := 15
const GRID_STATION_BUCKET_KM := 4.0
const GRID_STATION_SEARCH_RADIUS := 5

var metadata: Dictionary = {}
var stations: Array[Dictionary] = []
var load_error := ""
var loaded_path := ""


func load_snapshot(path: String = "") -> Dictionary:
	var requested_path := path.strip_edges()
	if requested_path == "":
		requested_path = REGIONAL_DATA_PATH
	if not stations.is_empty() and loaded_path == requested_path:
		return {
			"ok": true,
			"metadata": metadata.duplicate(true),
			"stations": stations.size(),
		}
	if not FileAccess.file_exists(requested_path):
		load_error = "Catalogo regional auditavel da Anatel nao encontrado."
		return {"ok": false, "message": load_error}
	stations.clear()
	metadata.clear()
	var file := FileAccess.open(requested_path, FileAccess.READ)
	if file == null:
		load_error = "Catalogo da Anatel nao pode ser aberto."
		return {"ok": false, "message": load_error}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		load_error = "Catalogo da Anatel possui formato invalido."
		return {"ok": false, "message": load_error}
	var payload := parsed as Dictionary
	var raw_stations: Variant = payload.get("stations", [])
	if typeof(raw_stations) != TYPE_ARRAY:
		load_error = "Catalogo da Anatel nao possui ERBs."
		return {"ok": false, "message": load_error}
	metadata = (payload.get("metadata", {}) as Dictionary).duplicate(true)
	for value in raw_stations as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var station := (value as Dictionary).duplicate(true)
		var operator_name := _normalize_operator(str(station.get("operator", "")))
		if operator_name not in MAP_OPERATORS:
			continue
		var generation := _normalize_generation(str(station.get("generation", "4G")))
		if generation not in GENERATIONS:
			continue
		var latitude := float(station.get("lat", 0.0))
		var longitude := float(station.get("lng", 0.0))
		if not _valid_coordinates(latitude, longitude):
			continue
		station["operator"] = operator_name
		station["generation"] = generation
		station["lat"] = latitude
		station["lng"] = longitude
		stations.append(station)
	if stations.is_empty():
		load_error = "Catalogo da Anatel nao retornou ERBs 2G/3G/4G/5G validas."
		return {"ok": false, "message": load_error}
	loaded_path = requested_path
	load_error = ""
	return {
		"ok": true,
		"metadata": metadata.duplicate(true),
		"stations": stations.size(),
	}


func build_region_profile(
	devices: Array[Dictionary],
	region: Dictionary,
	mode: String = "best",
	selected_operator: String = "CLARO",
	generation: String = "4G"
) -> Dictionary:
	var loaded := load_snapshot()
	if not bool(loaded.get("ok", false)):
		return loaded
	var center_lat := float(region.get("lat", -5.5264))
	var center_lng := float(region.get("lng", -47.4919))
	var radius_km := clampf(float(region.get("radius_km", 16.0)), 8.0, 32.0)
	var operator_name := _normalize_operator(selected_operator)
	if operator_name not in OPERATORS:
		operator_name = "CLARO"
	var generation_name := _normalize_generation(generation)
	var nearby_stations: Array[Dictionary] = _stations_near(center_lat, center_lng, radius_km + 18.0, "all")
	if mode == "operator":
		var filtered_stations: Array[Dictionary] = []
		for station in nearby_stations:
			if _normalize_operator(str(station.get("operator", ""))) == operator_name:
				filtered_stations.append(station)
		nearby_stations = filtered_stations
	var generation_counts := {}
	for station in nearby_stations:
		var station_generation := _normalize_generation(str(station.get("generation", generation_name)))
		generation_counts[station_generation] = int(generation_counts.get(station_generation, 0)) + 1
	var regional_stations: Array[Dictionary] = []
	for station in nearby_stations:
		if _normalize_generation(str(station.get("generation", generation_name))) == generation_name:
			regional_stations.append(station)
	var operator_counts := {}
	for station in regional_stations:
		var station_operator := _normalize_operator(str(station.get("operator", "")))
		operator_counts[station_operator] = int(operator_counts.get(station_operator, 0)) + 1
	var best_operator := _top_key(operator_counts)
	var summary := {
		"best_operator": best_operator if best_operator != "" else "--",
		"operator_counts": operator_counts,
		"generation_counts": generation_counts,
		"station_count": regional_stations.size(),
		"operator_count": operator_counts.size(),
		"strong_percent": 0,
		"critical_cells": 0,
		"real_samples": 0,
		"confidence": 100 if not regional_stations.is_empty() else 0,
		"cell_count": 0,
		"total": regional_stations.size(),
	}
	return {
		"ok": true,
		"mode": mode,
		"selected_operator": operator_name,
		"generation": generation_name,
		"center": {"lat": center_lat, "lng": center_lng},
		"radius_km": radius_km,
		"cells": [],
		"stations": regional_stations,
		"summary": summary,
		"metadata": metadata.duplicate(true),
		"method": "Catalogo oficial Anatel de ERBs %s; sem consultas operacionais." % generation_name,
	}


func search_stations(filters: Dictionary, region_catalog: Array = []) -> Dictionary:
	var state_key := _normalize_text(str(filters.get("state", "")))
	var city_key := _normalize_text(str(filters.get("city", "")))
	var place_key := _normalize_text(str(filters.get("place", "")))
	var raw_operator_filter := str(filters.get("operator", "")).strip_edges()
	var operator_key := _normalize_operator(raw_operator_filter)
	var generation_key := _normalize_generation(str(filters.get("generation", "")))
	var status_key := _normalize_text(str(filters.get("status", "")))
	var city_region: Dictionary = {}
	if city_key != "":
		city_region = _find_city_region(city_key, region_catalog)
	var center := {
		"lat": float(city_region.get("lat", -5.5264)),
		"lng": float(city_region.get("lng", -47.4919)),
	}
	var city_radius := float(city_region.get("radius_km", 16.0))
	var result: Array[Dictionary] = []
	for station in stations:
		if str(filters.get("generation", "")).strip_edges() != "" \
				and _normalize_generation(str(station.get("generation", "4G"))) != generation_key:
			continue
		if state_key != "" and not _station_matches_state(station, state_key, region_catalog):
			continue
		if city_key != "":
			# Municipio e filtrado somente pelo valor publicado pela Anatel. A
			# proximidade geografica nunca e usada para preencher campo ausente.
			var station_city := _normalize_text(str(station.get("city", "")))
			if not _area_contains(station_city, city_key):
				continue
		if place_key != "":
			var station_place := "%s %s %s" % [
				str(station.get("district", "")),
				str(station.get("address", "")),
				str(station.get("city", "")),
			]
			if not _area_contains(_normalize_text(station_place), place_key):
				continue
		if raw_operator_filter != "" and operator_key in MAP_OPERATORS \
				and _normalize_operator(str(station.get("operator", ""))) != operator_key:
			continue
		if status_key != "" and not _area_contains(_normalize_text(str(station.get("status", ""))), status_key):
			continue
		var item := station.duplicate(true)
		item["distance_km"] = distance_km(
			float(center.get("lat", -5.5264)),
			float(center.get("lng", -47.4919)),
			float(station.get("lat", 0.0)),
			float(station.get("lng", 0.0))
		)
		result.append(item)

	if city_region.is_empty() and not result.is_empty():
		center = _average_station_center(result)
	if not place_key.is_empty() and not result.is_empty():
		var bounds := _station_bounds(result)
		center = {
			"lat": float(bounds.get("center_lat", center.get("lat", -5.5264))),
			"lng": float(bounds.get("center_lng", center.get("lng", -47.4919))),
		}
		city_radius = clampf(float(bounds.get("radius_km", 6.0)) * 1.35, 3.0, 12.0)
	elif city_region.is_empty() and result.is_empty():
		city_radius = 16.0
	else:
		city_radius = clampf(city_radius * (0.62 if place_key != "" else 0.78), 6.0, 32.0)
	var area_label := "Toda a base Anatel"
	if city_key != "":
		area_label = str(city_region.get("label", str(filters.get("city", "Cidade pesquisada"))))
	if place_key != "":
		area_label += " | %s" % str(filters.get("place", "")).strip_edges()
	return {
		"ok": true,
		"stations": result,
		"station_count": result.size(),
		"center": center,
		"radius_km": city_radius,
		"area_label": area_label,
		"filters": filters.duplicate(true),
		"metadata": metadata.duplicate(true),
		"message": "%d ERB(s) encontradas" % result.size() if not result.is_empty() else "Nenhuma ERB encontrada para os filtros informados.",
	}


func enrich_devices(devices: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not bool(load_snapshot().get("ok", false)):
		for device in devices:
			result.append(device.duplicate(true))
		return result
	var generation_stations := _stations_for_generation("4G")
	for value in devices:
		var device := value.duplicate(true)
		if not bool(device.get("location_available", false)):
			device["recommended_operator"] = "SEM RECOMENDACAO"
			device["recommendation_confidence"] = 0
			device["recommendation_action"] = "Sem localizacao"
			result.append(device)
			continue
		var operator_name := _normalize_operator(str(device.get("operator", "")))
		var latitude := float(device.get("latitude", 0.0))
		var longitude := float(device.get("longitude", 0.0))
		var profiles := {}
		for candidate in OPERATORS:
			profiles[candidate] = _operator_profile_at(
				latitude,
				longitude,
				candidate,
				devices,
				generation_stations
			)
		var recommended := _best_operator(profiles)
		var recommendation: Dictionary = profiles.get(recommended, {})
		var recommendation_confidence := int(recommendation.get("confidence", 0))
		var recommendation_score := int(recommendation.get("score", 0))
		if recommendation_score < 38 or recommendation_confidence < 35:
			device["recommended_operator"] = "SEM RECOMENDACAO"
			device["recommendation_action"] = "Dados insuficientes"
		else:
			device["recommended_operator"] = recommended
			device["recommendation_action"] = (
				"MANTER"
				if operator_name == recommended
				else "AVALIAR TROCA"
			)
		device["recommendation_confidence"] = recommendation_confidence
		device["recommendation_confidence_label"] = "%d%%" % recommendation_confidence
		device["recommendation_score"] = recommendation_score
		device["operator_profiles"] = profiles
		var nearest: Dictionary = profiles.get(operator_name, {})
		if not nearest.is_empty():
			var distance := float(nearest.get("nearest_tower_km", -1.0))
			var theoretical_score := int(nearest.get("tower_score", 0))
			var real_score := int(device.get("estimated_signal_score", 0))
			var hybrid_score := theoretical_score
			if real_score > 0:
				hybrid_score = roundi(float(theoretical_score) * 0.45 + float(real_score) * 0.55)
			device["anatel_station_id"] = str(nearest.get("tower_id", ""))
			device["anatel_station_distance_km"] = distance
			device["anatel_station_distance_label"] = _distance_label(distance)
			device["anatel_bands"] = (nearest.get("bands", []) as Array).duplicate()
			device["anatel_theoretical_score"] = theoretical_score
			device["hybrid_coverage_score"] = clampi(hybrid_score, 0, 100)
			device["hybrid_coverage_label"] = _score_label(hybrid_score)
		result.append(device)
	return result


func _build_hex_cells(
	devices: Array[Dictionary],
	regional_stations: Array[Dictionary],
	center_lat: float,
	center_lng: float,
	radius_km: float,
	mode: String,
	selected_operator: String,
	density_scale: float = 1.0
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var spacing_km := clampf(radius_km / (21.0 * maxf(density_scale, 0.25)), 0.32, 1.2)
	var vertical_km := spacing_km * 0.8660254
	var row_count := ceili(radius_km / vertical_km) + 2
	var column_count := ceili(radius_km / spacing_km) + 2
	var lat_scale := 1.0 / 111.0
	var lng_scale := 1.0 / maxf(111.0 * cos(deg_to_rad(center_lat)), 1.0)
	var stations_by_operator := _grid_stations_by_operator(
		regional_stations,
		center_lat,
		center_lng
	)
	var samples_by_operator := _grid_samples_by_operator(
		devices,
		center_lat,
		center_lng
	)
	for row_index in range(-row_count, row_count + 1):
		var north_km := float(row_index) * vertical_km
		var offset_km := spacing_km * 0.5 if posmod(row_index, 2) != 0 else 0.0
		for column_index in range(-column_count, column_count + 1):
			var east_km := float(column_index) * spacing_km + offset_km
			var latitude := center_lat + north_km * lat_scale
			var longitude := center_lng + east_km * lng_scale
			var operator_profiles := {}
			var profile_operators: Array = [selected_operator] if mode == "operator" else OPERATORS
			for operator_name in profile_operators:
				operator_profiles[operator_name] = _operator_profile_at_grid(
					east_km,
					north_km,
					operator_name,
					stations_by_operator.get(operator_name, {}),
					samples_by_operator.get(operator_name, [])
				)
			var winner := selected_operator if mode == "operator" else _best_operator(operator_profiles)
			var profile: Dictionary = operator_profiles.get(winner, {})
			var nearest: Dictionary = profile.get("_nearest", {})
			var score := int(profile.get("score", 0))
			var data_points := int(profile.get("data_points", 0))
			var status := _score_status(score, data_points)
			result.append({
				"lat": latitude,
				"lng": longitude,
				"operator": winner,
				"score": score,
				"status": status,
				"signal_label": _score_label(score) if data_points > 0 else "Dados insuficientes",
				"confidence": int(profile.get("confidence", 0)),
				"confidence_label": "%d%%" % int(profile.get("confidence", 0)),
				"nearest_tower_km": float(profile.get("nearest_tower_km", -1.0)),
				"nearest_tower_label": _distance_label(float(profile.get("nearest_tower_km", -1.0))),
				"tower_id": str(nearest.get("id", "")),
				"district": str(nearest.get("district", "Area regional")),
				"city": str(nearest.get("city", "")),
				"bands": (nearest.get("bands", []) as Array).duplicate(),
				"real_samples": int(profile.get("real_samples", 0)),
				"data_points": data_points,
				"spacing_km": spacing_km,
				"hex_radius_km": spacing_km / sqrt(3.0),
			})
	return result


func _grid_stations_by_operator(
	source_stations: Array[Dictionary],
	center_lat: float,
	center_lng: float
) -> Dictionary:
	var result := {
		"CLARO": {"buckets": {}},
		"TIM": {"buckets": {}},
		"VIVO": {"buckets": {}},
	}
	var east_scale := maxf(111.0 * cos(deg_to_rad(center_lat)), 1.0)
	for station in source_stations:
		var operator_name := _normalize_operator(str(station.get("operator", "")))
		if not result.has(operator_name):
			continue
		var item := station.duplicate(true)
		item["_grid_east_km"] = (float(station.get("lng", center_lng)) - center_lng) * east_scale
		item["_grid_north_km"] = (float(station.get("lat", center_lat)) - center_lat) * 111.0
		var index := result[operator_name] as Dictionary
		var buckets := index.get("buckets", {}) as Dictionary
		var bucket_x := floori(float(item.get("_grid_east_km", 0.0)) / GRID_STATION_BUCKET_KM)
		var bucket_y := floori(float(item.get("_grid_north_km", 0.0)) / GRID_STATION_BUCKET_KM)
		var bucket_key := "%d:%d" % [bucket_x, bucket_y]
		var bucket := buckets.get(bucket_key, []) as Array
		bucket.append(item)
		buckets[bucket_key] = bucket
		index["buckets"] = buckets
		result[operator_name] = index
	return result


func _grid_samples_by_operator(
	source_devices: Array[Dictionary],
	center_lat: float,
	center_lng: float
) -> Dictionary:
	var result := {"CLARO": [], "TIM": [], "VIVO": []}
	var east_scale := maxf(111.0 * cos(deg_to_rad(center_lat)), 1.0)
	for device in source_devices:
		if not bool(device.get("location_available", false)):
			continue
		var sample_age := int(device.get(
			"platform_delay_minutes",
			device.get("communication_delay_minutes", -1)
		))
		var score := int(device.get("estimated_signal_score", 0))
		if sample_age < 0 or sample_age > REAL_WINDOW_MINUTES or score <= 0:
			continue
		var operator_name := _normalize_operator(str(device.get("operator", "")))
		if not result.has(operator_name):
			continue
		(result[operator_name] as Array).append({
			"east_km": (float(device.get("longitude", center_lng)) - center_lng) * east_scale,
			"north_km": (float(device.get("latitude", center_lat)) - center_lat) * 111.0,
			"score": score,
		})
	return result


func _operator_profile_at_grid(
	east_km: float,
	north_km: float,
	operator_name: String,
	station_index: Dictionary,
	operator_samples: Array
) -> Dictionary:
	var nearest := _nearest_grid_station(east_km, north_km, station_index)
	var nearest_distance := float(nearest.get("distance_km", -1.0))
	var tower_score := _theoretical_score(nearest_distance, nearest) if not nearest.is_empty() else 0
	var real_score_total := 0.0
	var real_weight_total := 0.0
	var real_samples := 0
	for value in operator_samples:
		var sample := value as Dictionary
		var east_delta := east_km - float(sample.get("east_km", 0.0))
		var north_delta := north_km - float(sample.get("north_km", 0.0))
		var distance := sqrt(east_delta * east_delta + north_delta * north_delta)
		if distance > 6.0:
			continue
		var weight := 1.0 / maxf(distance + 0.55, 0.55)
		real_score_total += float(sample.get("score", 0)) * weight
		real_weight_total += weight
		real_samples += 1
	var real_score := roundi(real_score_total / real_weight_total) if real_weight_total > 0.0 else 0
	var score := tower_score
	if tower_score > 0 and real_score > 0:
		var real_share := clampf(0.22 + float(real_samples) * 0.11, 0.22, 0.55)
		score = roundi(float(tower_score) * (1.0 - real_share) + float(real_score) * real_share)
	elif real_score > 0:
		score = real_score
	var data_points := (1 if tower_score > 0 else 0) + real_samples
	var confidence := 0
	if tower_score > 0:
		confidence += 38
		if nearest_distance <= 7.0:
			confidence += 12
		if not (nearest.get("bands", []) as Array).is_empty():
			confidence += 8
	confidence += mini(real_samples * 9, 32)
	if real_samples > 0:
		confidence += 8
	return {
		"operator": operator_name,
		"score": clampi(score, 0, 100),
		"tower_score": tower_score,
		"real_score": real_score,
		"real_samples": real_samples,
		"data_points": data_points,
		"confidence": clampi(confidence, 0, 96),
		"nearest_tower_km": nearest_distance,
		"_nearest": nearest,
	}


func _nearest_grid_station(
	east_km: float,
	north_km: float,
	station_index: Dictionary
) -> Dictionary:
	var buckets := station_index.get("buckets", {}) as Dictionary
	if buckets.is_empty():
		return {}
	var center_x := floori(east_km / GRID_STATION_BUCKET_KM)
	var center_y := floori(north_km / GRID_STATION_BUCKET_KM)
	var nearest: Dictionary = {}
	var nearest_distance_squared := INF
	for radius in range(GRID_STATION_SEARCH_RADIUS + 1):
		for bucket_x in range(center_x - radius, center_x + radius + 1):
			for bucket_y in range(center_y - radius, center_y + radius + 1):
				if radius > 0 \
						and absi(bucket_x - center_x) != radius \
						and absi(bucket_y - center_y) != radius:
					continue
				var bucket_key := "%d:%d" % [bucket_x, bucket_y]
				for value in buckets.get(bucket_key, []) as Array:
					var station := value as Dictionary
					var east_delta := east_km - float(station.get("_grid_east_km", 0.0))
					var north_delta := north_km - float(station.get("_grid_north_km", 0.0))
					var distance_squared := east_delta * east_delta + north_delta * north_delta
					if distance_squared >= nearest_distance_squared:
						continue
					nearest_distance_squared = distance_squared
					nearest = station
		if not nearest.is_empty() \
				and sqrt(nearest_distance_squared) <= float(radius) * GRID_STATION_BUCKET_KM:
			break
	if nearest.is_empty():
		return {}
	var result := nearest.duplicate(true)
	result["distance_km"] = sqrt(nearest_distance_squared)
	return result


func _operator_profile_at(
	latitude: float,
	longitude: float,
	operator_name: String,
	devices: Array[Dictionary],
	regional_stations: Array[Dictionary]
) -> Dictionary:
	var nearest := _nearest_station(latitude, longitude, operator_name, regional_stations)
	var tower_score := 0
	var nearest_distance := -1.0
	if not nearest.is_empty():
		nearest_distance = float(nearest.get("distance_km", -1.0))
		tower_score = _theoretical_score(nearest_distance, nearest)
	var real_score_total := 0.0
	var real_weight_total := 0.0
	var real_samples := 0
	for device in devices:
		if not bool(device.get("location_available", false)):
			continue
		var sample_age := int(device.get(
			"platform_delay_minutes",
			device.get("communication_delay_minutes", -1)
		))
		if sample_age < 0 or sample_age > REAL_WINDOW_MINUTES:
			continue
		if _normalize_operator(str(device.get("operator", ""))) != operator_name:
			continue
		var distance := distance_km(
			latitude,
			longitude,
			float(device.get("latitude", 0.0)),
			float(device.get("longitude", 0.0))
		)
		if distance > 6.0:
			continue
		var score := int(device.get("estimated_signal_score", 0))
		if score <= 0:
			continue
		var weight := 1.0 / maxf(distance + 0.55, 0.55)
		real_score_total += float(score) * weight
		real_weight_total += weight
		real_samples += 1
	var real_score := roundi(real_score_total / real_weight_total) if real_weight_total > 0.0 else 0
	var score := tower_score
	if tower_score > 0 and real_score > 0:
		var real_share := clampf(0.22 + float(real_samples) * 0.11, 0.22, 0.55)
		score = roundi(float(tower_score) * (1.0 - real_share) + float(real_score) * real_share)
	elif real_score > 0:
		score = real_score
	var data_points := (1 if tower_score > 0 else 0) + real_samples
	var confidence := 0
	if tower_score > 0:
		confidence += 38
		if nearest_distance <= 7.0:
			confidence += 12
		if not (nearest.get("bands", []) as Array).is_empty():
			confidence += 8
	confidence += mini(real_samples * 9, 32)
	if real_samples > 0:
		confidence += 8
	confidence = clampi(confidence, 0, 96)
	return {
		"operator": operator_name,
		"score": clampi(score, 0, 100),
		"tower_score": tower_score,
		"real_score": real_score,
		"real_samples": real_samples,
		"data_points": data_points,
		"confidence": confidence,
		"nearest_tower_km": nearest_distance,
		"tower_id": str(nearest.get("id", "")),
		"district": str(nearest.get("district", "Area regional")),
		"city": str(nearest.get("city", "")),
		"bands": (nearest.get("bands", []) as Array).duplicate(),
	}


func _build_profile_summary(
	cells: Array[Dictionary],
	regional_stations: Array[Dictionary],
	devices: Array[Dictionary],
	center_lat: float,
	center_lng: float,
	radius_km: float
) -> Dictionary:
	var operator_cells := {"CLARO": 0, "TIM": 0, "VIVO": 0}
	var strong_cells := 0
	var critical_cells := 0
	var confidence_total := 0
	var confidence_samples := 0
	for cell in cells:
		var operator_name := str(cell.get("operator", ""))
		if operator_cells.has(operator_name):
			operator_cells[operator_name] = int(operator_cells.get(operator_name, 0)) + 1
		var score := int(cell.get("score", 0))
		if score >= 65:
			strong_cells += 1
		elif score > 0 and score < 40:
			critical_cells += 1
		var confidence := int(cell.get("confidence", 0))
		if confidence > 0:
			confidence_total += confidence
			confidence_samples += 1
	var nearby_station_count := 0
	for station in regional_stations:
		if distance_km(
			center_lat,
			center_lng,
			float(station.get("lat", 0.0)),
			float(station.get("lng", 0.0))
		) <= radius_km:
			nearby_station_count += 1
	var real_samples := 0
	for device in devices:
		var sample_age := int(device.get(
			"platform_delay_minutes",
			device.get("communication_delay_minutes", -1)
		))
		if sample_age >= 0 and sample_age <= REAL_WINDOW_MINUTES \
				and bool(device.get("location_available", false)) and distance_km(
			center_lat,
			center_lng,
			float(device.get("latitude", 0.0)),
			float(device.get("longitude", 0.0))
		) <= radius_km:
			real_samples += 1
	var total := maxi(cells.size(), 1)
	return {
		"best_operator": _top_key(operator_cells),
		"operator_cells": operator_cells,
		"strong_percent": roundi(float(strong_cells) * 100.0 / float(total)),
		"critical_cells": critical_cells,
		"station_count": nearby_station_count,
		"real_samples": real_samples,
		"confidence": roundi(float(confidence_total) / float(maxi(confidence_samples, 1))),
		"cell_count": cells.size(),
	}


func _stations_near(
	latitude: float,
	longitude: float,
	radius_km: float,
	generation_filter: String = "all"
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for station in stations:
		if generation_filter != "all" \
				and _normalize_generation(str(station.get("generation", "4G"))) != generation_filter:
			continue
		var distance := distance_km(
			latitude,
			longitude,
			float(station.get("lat", 0.0)),
			float(station.get("lng", 0.0))
		)
		if distance <= radius_km:
			var item := station.duplicate(true)
			item["distance_km"] = distance
			result.append(item)
	return result


func _stations_for_generation(generation: String) -> Array[Dictionary]:
	var generation_key := _normalize_generation(generation)
	var result: Array[Dictionary] = []
	for station in stations:
		if _normalize_generation(str(station.get("generation", "4G"))) == generation_key:
			result.append(station.duplicate(true))
	return result


func _nearest_station(
	latitude: float,
	longitude: float,
	operator_name: String,
	source_stations: Array[Dictionary]
) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for station in source_stations:
		if _normalize_operator(str(station.get("operator", ""))) != operator_name:
			continue
		var distance := distance_km(
			latitude,
			longitude,
			float(station.get("lat", 0.0)),
			float(station.get("lng", 0.0))
		)
		if distance >= nearest_distance:
			continue
		nearest_distance = distance
		nearest = station.duplicate(true)
	if not nearest.is_empty():
		nearest["distance_km"] = nearest_distance
	return nearest


func _theoretical_score(distance: float, station: Dictionary) -> int:
	if distance < 0.0:
		return 0
	var score := 12
	if distance <= 1.0:
		score = 96
	elif distance <= 2.5:
		score = 88
	elif distance <= 4.0:
		score = 76
	elif distance <= 5.5:
		score = 62
	elif distance <= 7.0:
		score = 48
	elif distance <= 10.0:
		score = 30
	var bands: Array = station.get("bands", [])
	for value in bands:
		var band := str(value).to_float()
		if band > 0.0 and band <= 900.0:
			score += 6
			break
	return clampi(score, 0, 100)


func _best_operator(profiles: Dictionary) -> String:
	var winner := "CLARO"
	var best_score := -1
	var best_confidence := -1
	for operator_name in OPERATORS:
		var profile: Dictionary = profiles.get(operator_name, {})
		var score := int(profile.get("score", 0))
		var confidence := int(profile.get("confidence", 0))
		if score > best_score or (score == best_score and confidence > best_confidence):
			winner = operator_name
			best_score = score
			best_confidence = confidence
	return winner


func _top_key(counts: Dictionary) -> String:
	var winner := ""
	var highest := -1
	for key in counts:
		var amount := int(counts.get(key, 0))
		if amount > highest:
			winner = str(key)
			highest = amount
	return winner


func _score_status(score: int, data_points: int) -> String:
	if data_points <= 0:
		return "no_data"
	if score >= 78:
		return "strong"
	if score >= 58:
		return "good"
	if score >= 38:
		return "attention"
	return "insufficient"


func _score_label(score: int) -> String:
	if score >= 78:
		return "Forte"
	if score >= 58:
		return "Boa"
	if score >= 38:
		return "Atencao"
	if score > 0:
		return "Insuficiente"
	return "Sem dados"


func _distance_label(distance: float) -> String:
	if distance < 0.0:
		return "--"
	if distance < 1.0:
		return "%d m" % roundi(distance * 1000.0)
	return "%.1f km" % distance


func _find_city_region(city_key: String, region_catalog: Array) -> Dictionary:
	for value in region_catalog:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var region := value as Dictionary
		var label_key := _normalize_text(str(region.get("label", "")))
		var city_label := label_key.split(" - ", false)[0]
		if _area_contains(city_label, city_key) or _area_contains(city_key, city_label):
			return region.duplicate(true)
	return {}


func _station_matches_state(station: Dictionary, state_key: String, region_catalog: Array) -> bool:
	var station_state := _normalize_text(str(station.get("state", station.get("uf", ""))))
	if station_state != "":
		return _area_contains(station_state, state_key)
	if state_key in ["ma", "maranhao"]:
		return true
	for value in region_catalog:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var label_key := _normalize_text(str((value as Dictionary).get("label", "")))
		if label_key.ends_with(" - " + state_key):
			return true
	return false


func _average_station_center(source: Array[Dictionary]) -> Dictionary:
	if source.is_empty():
		return {"lat": -5.5264, "lng": -47.4919}
	var lat_sum := 0.0
	var lng_sum := 0.0
	for station in source:
		lat_sum += float(station.get("lat", 0.0))
		lng_sum += float(station.get("lng", 0.0))
	return {"lat": lat_sum / float(source.size()), "lng": lng_sum / float(source.size())}


func _station_bounds(source: Array[Dictionary]) -> Dictionary:
	if source.is_empty():
		return {"center_lat": -5.5264, "center_lng": -47.4919, "radius_km": 6.0}
	var min_lat := INF
	var max_lat := -INF
	var min_lng := INF
	var max_lng := -INF
	for station in source:
		min_lat = minf(min_lat, float(station.get("lat", 0.0)))
		max_lat = maxf(max_lat, float(station.get("lat", 0.0)))
		min_lng = minf(min_lng, float(station.get("lng", 0.0)))
		max_lng = maxf(max_lng, float(station.get("lng", 0.0)))
	var center_lat := (min_lat + max_lat) * 0.5
	var center_lng := (min_lng + max_lng) * 0.5
	var radius := distance_km(center_lat, center_lng, max_lat, max_lng)
	return {"center_lat": center_lat, "center_lng": center_lng, "radius_km": maxf(radius, 1.5)}


func _area_contains(value: String, query: String) -> bool:
	var clean_value := _normalize_text(value)
	var clean_query := _normalize_text(query)
	if clean_query == "":
		return true
	if clean_value.contains(clean_query):
		return true
	var street_query := clean_query
	if street_query.begins_with("rua "):
		street_query = "r " + street_query.substr(4)
	elif street_query.begins_with("avenida "):
		street_query = "av " + street_query.substr(8)
	return clean_value.contains(street_query)


func _normalize_text(value: String) -> String:
	var clean := value.strip_edges().to_lower()
	for pair in [
		["á", "a"], ["à", "a"], ["ã", "a"], ["â", "a"], ["ä", "a"],
		["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"],
		["í", "i"], ["ì", "i"], ["î", "i"], ["ï", "i"],
		["ó", "o"], ["ò", "o"], ["õ", "o"], ["ô", "o"], ["ö", "o"],
		["ú", "u"], ["ù", "u"], ["û", "u"], ["ü", "u"], ["ç", "c"],
		["ãƒ", "a"], ["ã‰", "e"], ["ã‚", "i"], ["ãš", "u"], ["ã‡", "c"],
		["�", ""],
	]:
		clean = clean.replace(str(pair[0]), str(pair[1]))
	clean = clean.replace("\t", " ").replace("\r", " ").replace("\n", " ")
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	return clean.strip_edges()


func distance_km(lat_a: float, lng_a: float, lat_b: float, lng_b: float) -> float:
	var lat_delta := deg_to_rad(lat_b - lat_a)
	var lng_delta := deg_to_rad(lng_b - lng_a)
	var sin_lat := sin(lat_delta * 0.5)
	var sin_lng := sin(lng_delta * 0.5)
	var haversine := sin_lat * sin_lat \
		+ cos(deg_to_rad(lat_a)) * cos(deg_to_rad(lat_b)) * sin_lng * sin_lng
	return EARTH_RADIUS_KM * 2.0 * atan2(sqrt(haversine), sqrt(maxf(1.0 - haversine, 0.0)))


func _normalize_operator(value: String) -> String:
	var clean := value.strip_edges().to_upper()
	if clean.contains("CLARO"):
		return "CLARO"
	if clean.contains("TIM"):
		return "TIM"
	if clean.contains("VIVO") or clean.contains("TELEFONICA"):
		return "VIVO"
	return "OUTRAS"


func _normalize_generation(value: String) -> String:
	var clean := value.strip_edges().to_upper()
	if clean.contains("2G") or clean.contains("GSM"):
		return "2G"
	if clean.contains("3G") or clean.contains("WCDMA") or clean.contains("UMTS"):
		return "3G"
	if clean.contains("4G") or clean.contains("LTE"):
		return "4G"
	if clean.contains("5G") or clean.contains("NR"):
		return "5G"
	return "4G"


func _valid_coordinates(latitude: float, longitude: float) -> bool:
	return is_finite(latitude) \
		and is_finite(longitude) \
		and latitude >= -90.0 \
		and latitude <= 90.0 \
		and longitude >= -180.0 \
		and longitude <= 180.0 \
		and not (is_zero_approx(latitude) and is_zero_approx(longitude))
