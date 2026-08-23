extends SceneTree

const CoverageScript := preload("res://src/anatel_coverage.gd")

func _fail(message: String) -> void:
	push_error("NATIONAL_ANATEL_CHECK: " + message)
	quit(1)

func _pass(message: String) -> void:
	print("NATIONAL_ANATEL_CHECK: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var coverage = CoverageScript.new()
	var loaded: Dictionary = coverage.load_snapshot()
	if not bool(loaded.get("ok", false)):
		_fail(str(loaded.get("message", "catalogo nao carregado")))
	var metadata: Dictionary = loaded.get("metadata", {})
	if str(metadata.get("scope", "")) != "Brasil":
		_fail("metadata.scope nao e Brasil")
	if int(loaded.get("stations", 0)) <= 0:
		_fail("nenhuma ERB nacional carregada")
	var profile: Dictionary = coverage.build_region_profile([], {
		"lat": -5.5264,
		"lng": -47.4919,
		"radius_km": 16.0,
	}, "best", "CLARO", "4G")
	var direct_near: Array = coverage._stations_near(-5.5264, -47.4919, 50.0, "all")
	var direct_4g := 0
	var direct_4g_34 := 0
	for station in direct_near:
		if str(station.get("generation", "")) == "4G":
			direct_4g += 1
			if coverage.distance_km(-5.5264, -47.4919, float(station.get("lat", 0.0)), float(station.get("lng", 0.0))) <= 34.0:
				direct_4g_34 += 1
	print("NATIONAL_ANATEL_CHECK: busca direta em 50 km: %d ERBs, %d 4G" % [direct_near.size(), direct_4g])
	print("NATIONAL_ANATEL_CHECK: busca direta em 34 km: %d 4G" % direct_4g_34)
	print("NATIONAL_ANATEL_CHECK: perfil retornou %d estacoes" % (profile.get("stations", []) as Array).size())
	if not bool(profile.get("ok", false)):
		_fail("perfil de Imperatriz nao foi criado")
	var nearby := 0
	var nearby_4g := 0
	var closest_distance := INF
	var closest_station: Dictionary = {}
	for station in coverage.stations:
		var distance := coverage.distance_km(-5.5264, -47.4919, float(station.get("lat", 0.0)), float(station.get("lng", 0.0)))
		if distance < closest_distance:
			closest_distance = distance
			closest_station = station
		if distance <= 34.0:
			nearby += 1
			if str(station.get("generation", "")) == "4G":
				nearby_4g += 1
		if nearby_4g > 0 and nearby > 0:
			break
	print("NATIONAL_ANATEL_CHECK: ERB mais proxima: %s a %.2f km (%s %s)" % [str(closest_station.get("id", "")), closest_distance, str(closest_station.get("operator", "")), str(closest_station.get("generation", ""))])
	var profile_summary: Dictionary = profile.get("summary", {})
	if int(profile_summary.get("station_count", 0)) <= 0:
		_fail("Imperatriz nao possui ERBs no catalogo nacional; proximas=%d; proximas_4g=%d" % [nearby, nearby_4g])
	_pass("catalogo Brasil carregado: %d ERBs" % int(loaded.get("stations", 0)))
	_pass("perfil inicial Imperatriz carregado: %d ERBs" % int(profile_summary.get("station_count", 0)))
	quit(0)
