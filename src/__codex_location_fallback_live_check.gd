extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard: Node = DashboardScript.new()
	root.add_child(dashboard)
	await process_frame

	var serial := OS.get_environment("CODEX_LOCATION_TEST_SERIAL").strip_edges()
	var plate := OS.get_environment("CODEX_LOCATION_TEST_PLATE").strip_edges()
	var client := OS.get_environment("CODEX_LOCATION_TEST_CLIENT").strip_edges()
	if serial == "" or plate == "" or client == "":
		push_error("Informe serie, placa e cliente do caso real para o teste.")
		quit(1)
		return

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

	var lat := float(result.get("lat", 0.0))
	var lng := float(result.get("lng", 0.0))
	var result_plate := str(result.get("plate", "")).strip_edges()
	if result_plate == "" or not is_finite(lat) or not is_finite(lng) or (lat == 0.0 and lng == 0.0):
		push_error("Resultado sem placa/coordenadas validas.")
		quit(1)
		return
	if lat < -35.0 or lat > 6.0 or lng < -75.0 or lng > -30.0:
		push_error("Coordenadas fora do Brasil: %s,%s" % [str(lat), str(lng)])
		quit(1)
		return

	print("LOCATION_FALLBACK_LIVE_CHECK_OK source=%s plate=%s" % [str(result.get("source", "")), result_plate])
	dashboard.queue_free()
	await process_frame
	quit(0)
