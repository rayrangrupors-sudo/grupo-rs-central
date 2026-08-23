extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/estoque_profissional.tscn")
	if scene == null:
		push_error("Cena principal nao carregou.")
		quit(1)
		return

	var dashboard: Node = scene.instantiate()
	root.add_child(dashboard)
	await process_frame

	var serial := OS.get_environment("CODEX_LOCATION_TEST_SERIAL").strip_edges()
	var plate := OS.get_environment("CODEX_LOCATION_TEST_PLATE").strip_edges()
	var client := OS.get_environment("CODEX_LOCATION_TEST_CLIENT").strip_edges()
	if serial == "":
		serial = "024296001"
	if plate == "":
		plate = "PSD - 7H67"
	if client == "":
		client = "FRANCINALDO MIZAEL ARAUJO SOUSA"
	var result: Dictionary = await dashboard.call(
		"_lookup_grupo_rs_location",
		serial,
		Callable(),
		"api",
		plate,
		client
	)
	if not bool(result.get("ok", false)):
		push_error("Consulta de localizacao falhou: %s" % str(result.get("message", "")))
		quit(1)
		return

	if str(result.get("client", "")) != client:
		push_error("Cliente inesperado: %s" % str(result.get("client", "")))
		quit(1)
		return

	if str(result.get("plate", "")).strip_edges() != plate.strip_edges():
		push_error("Placa inesperada: %s" % str(result.get("plate", "")))
		quit(1)
		return

	var lat := float(result.get("lat", 0.0))
	var lng := float(result.get("lng", 0.0))
	if not is_finite(lat) or not is_finite(lng) or (lat == 0.0 and lng == 0.0):
		push_error("Coordenadas invalidas: %s,%s" % [str(lat), str(lng)])
		quit(1)
		return
	if lat < -35.0 or lat > 6.0 or lng < -75.0 or lng > -30.0:
		push_error("Coordenadas fora do Brasil: %s,%s" % [str(lat), str(lng)])
		quit(1)
		return

	var tile: Dictionary = dashboard.call("_lat_lng_to_tile", lat, lng, 15)
	var tile_url := "https://tile.openstreetmap.org/15/%d/%d.png" % [int(tile.get("x", 0)), int(tile.get("y", 0))]
	var tile_response: Dictionary = await dashboard.call("_http_get_bytes", tile_url)
	if not bool(tile_response.get("ok", false)) or (tile_response.get("bytes", PackedByteArray()) as PackedByteArray).size() < 1000:
		push_error("Tile do mapa nao carregou.")
		quit(1)
		return

	print("LOCATION_LOOKUP_CHECK_OK")
	quit(0)
