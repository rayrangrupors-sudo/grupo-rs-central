## Validação offline do índice nacional: manifesto, viewport, filtros e cache.
extends SceneTree

const NationalIndex := preload("res://src/features/big_map/anatel_national_index.gd")

const MAX_DENSE_QUERY_MSEC := 15000
const MAX_DENSE_MEMORY_DELTA_BYTES := 512 * 1024 * 1024

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := NationalIndex.new()
	var loaded: Dictionary = service.load_manifest()
	_check(bool(loaded.get("ok", false)), "Manifesto nacional não carregou: %s" % str(loaded.get("message", "")))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	var metadata: Dictionary = loaded.get("metadata", {})
	_check(str(metadata.get("scope", "")) == "Brasil", "Escopo nacional ausente.")
	_check(str(metadata.get("source_zip_sha256", "")).length() == 64, "Hash do ZIP oficial ausente.")
	_check(str(metadata.get("index_content_sha256", "")).length() == 64, "Hash agregado do índice ausente.")
	_check(int(metadata.get("unique_station_generations", 0)) == 291348, "Contagem nacional estação/geração divergiu.")
	_check(int(metadata.get("unique_physical_stations", 0)) == 115018, "Contagem nacional de ERBs físicas divergiu.")
	_check((metadata.get("generations", []) as Array).size() == 4, "Catálogo não expõe 2G/3G/4G/5G.")

	for region in [
		{"name": "Imperatriz/MA", "bounds": {"min_lat": -5.62, "max_lat": -5.43, "min_lng": -47.62, "max_lng": -47.36}},
		{"name": "Manaus/AM", "bounds": {"min_lat": -3.25, "max_lat": -2.95, "min_lng": -60.20, "max_lng": -59.82}},
		{"name": "Brasília/DF", "bounds": {"min_lat": -16.05, "max_lat": -15.55, "min_lng": -48.20, "max_lng": -47.55}},
		{"name": "São Paulo/SP", "bounds": {"min_lat": -23.80, "max_lat": -23.35, "min_lng": -46.95, "max_lng": -46.35}},
		{"name": "Porto Alegre/RS", "bounds": {"min_lat": -30.25, "max_lat": -29.80, "min_lng": -51.45, "max_lng": -50.85}},
	]:
		var result := service.query_viewport(region["bounds"], 10)
		_check(bool(result.get("ok", false)), "%s não pôde ser consultada." % region["name"])
		_check(int(result.get("station_count", 0)) > 0, "%s retornou vazio." % region["name"])
		for station in result.get("stations", []) as Array:
			_check(not bool((station as Dictionary).get("is_index_cluster", false)), "%s retornou agregado no zoom mínimo operacional." % region["name"])
			_check(_inside(station as Dictionary, region["bounds"]), "%s retornou ponto fora do viewport." % region["name"])

	var imperatriz_bounds := {"min_lat": -5.62, "max_lat": -5.43, "min_lng": -47.62, "max_lng": -47.36}
	var filtered := service.query_viewport(imperatriz_bounds, 13, {
		"operator": "VIVO", "generation": "5G", "city": "Imperatriz - MA", "status": "Licenciada",
	})
	_check(bool(filtered.get("ok", false)), "Filtro nacional combinado falhou.")
	_check(int(filtered.get("station_count", 0)) > 0, "Filtro 5G/VIVO/Imperatriz retornou vazio.")
	for station in filtered.get("stations", []) as Array:
		var row := station as Dictionary
		_check(str(row.get("operator", "")) == "VIVO", "Filtro de operadora vazou.")
		_check(str(row.get("generation", "")) == "5G", "Filtro de geração vazou.")
		_check(str(row.get("city", "")) == "Imperatriz - MA", "Filtro de município vazou.")

	var ocean := service.query_viewport({
		"min_lat": -40.0, "max_lat": -39.0, "min_lng": -20.0, "max_lng": -19.0,
	}, 13)
	_check(bool(ocean.get("ok", false)) and int(ocean.get("station_count", -1)) == 0, "Viewport sem dados não retornou vazio.")

	await _run_dense_benchmark(service)
	_finish()


func _run_dense_benchmark(service: RefCounted) -> void:
	var largest: Dictionary = {}
	for descriptor_value in service.get("cell_summaries") as Array:
		var descriptor := descriptor_value as Dictionary
		if int(descriptor.get("bytes", 0)) > int(largest.get("bytes", -1)):
			largest = descriptor
	_check(not largest.is_empty(), "Manifesto não declarou células para benchmark.")
	if largest.is_empty():
		return
	service.set("max_cache_cells", 2)
	service.set("max_cache_stations", 20000)
	service.set("max_cache_source_bytes", 8 * 1024 * 1024)
	service.call("clear_cache")
	var before_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var before_peak := int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX))
	var started := Time.get_ticks_msec()
	var task_state := {}
	var task_id := WorkerThreadPool.add_task(
		Callable(service, "query_viewport_threadsafe_to").bind(largest.get("bbox", {}) as Dictionary, 13, {}, task_state),
		true,
		"Teste: viewport Anatel denso"
	)
	var responsive_frames := 0
	while not WorkerThreadPool.is_task_completed(task_id):
		responsive_frames += 1
		await process_frame
	WorkerThreadPool.wait_for_task_completion(task_id)
	var dense: Dictionary = task_state.get("result", {})
	var elapsed := Time.get_ticks_msec() - started
	var after_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var after_peak := int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX))
	var peak_delta := maxi(after_memory - before_memory, after_peak - before_peak)
	var cache: Dictionary = service.call("cache_state")
	print("ANATEL_NATIONAL_RUNTIME_BENCHMARK: shard_bytes=%d records=%d elapsed_ms=%d responsive_frames=%d memory_delta_bytes=%d cache=%s" % [
		int(largest.get("bytes", 0)), int(largest.get("cluster_count", 0)), elapsed, responsive_frames, peak_delta, JSON.stringify(cache),
	])
	_check(bool(dense.get("ok", false)), "Viewport denso falhou.")
	_check(int(dense.get("station_count", 0)) > 0, "Viewport denso não retornou ERBs.")
	_check(responsive_frames > 0, "Consulta densa não devolveu frames à thread principal.")
	_check(elapsed <= MAX_DENSE_QUERY_MSEC, "Viewport denso excedeu %d ms: %d ms." % [MAX_DENSE_QUERY_MSEC, elapsed])
	_check(peak_delta <= MAX_DENSE_MEMORY_DELTA_BYTES, "Viewport denso excedeu o teto de memória do teste.")
	_check(int(cache.get("cells", 99)) <= 2, "LRU excedeu o limite de células.")
	_check(int(cache.get("cache_bytes", 0)) <= int(cache.get("max_cache_bytes", 0)) or bool(cache.get("single_oversized_cell_allowed", false)), "Cache excedeu bytes sem política explícita.")

	# Força uma célula distante para comprovar troca/evicção e recuperação.
	var first_keys: Array = (cache.get("keys", []) as Array).duplicate()
	var replacement: Dictionary = {}
	for descriptor_value in service.get("cell_summaries") as Array:
		var descriptor := descriptor_value as Dictionary
		var key := "%d:%d" % [int(descriptor.get("cell_x", -1)), int(descriptor.get("cell_y", -1))]
		if key not in first_keys and absf(float(descriptor.get("lat", 0.0)) - float(largest.get("lat", 0.0))) > 10.0:
			replacement = descriptor
			break
	_check(not replacement.is_empty(), "Não foi encontrada célula distante para evicção.")
	if not replacement.is_empty():
		var recovered: Dictionary = service.call("query_viewport", replacement.get("bbox", {}) as Dictionary, 13, {})
		var recovered_cache: Dictionary = service.call("cache_state")
		_check(bool(recovered.get("ok", false)) and int(recovered.get("station_count", 0)) > 0, "Troca de célula não recuperou dados.")
		_check(int(recovered_cache.get("cells", 99)) <= 2, "Evicção não respeitou max_cache_cells.")
		_check((recovered_cache.get("keys", []) as Array) != first_keys, "LRU não mudou após troca de viewport.")


func _inside(station: Dictionary, bounds: Dictionary) -> bool:
	var latitude := float(station.get("lat", 0.0))
	var longitude := float(station.get("lng", 0.0))
	return latitude >= float(bounds.get("min_lat", -90.0)) \
			and latitude <= float(bounds.get("max_lat", 90.0)) \
			and longitude >= float(bounds.get("min_lng", -180.0)) \
			and longitude <= float(bounds.get("max_lng", 180.0))


func _finish() -> void:
	if failures.is_empty():
		print("ANATEL_NATIONAL_INDEX_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
