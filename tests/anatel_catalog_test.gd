## Auditoria automatizada do catálogo regional derivado da base oficial SMP.
extends SceneTree

const AnatelCoverage := preload("res://src/anatel_coverage.gd")

var failures: Array[String] = []


func _init() -> void:
	var catalog := AnatelCoverage.new()
	var loaded: Dictionary = catalog.load_snapshot(AnatelCoverage.REGIONAL_DATA_PATH)
	_check(bool(loaded.get("ok", false)), "Catálogo regional não carregou: %s" % loaded.get("message", ""))
	if bool(loaded.get("ok", false)):
		_validate_metadata(loaded.get("metadata", {}) as Dictionary)
		_validate_stations(catalog.stations)
		_validate_filters(catalog)
	if failures.is_empty():
		print("ANATEL_CATALOG_TEST: OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _validate_metadata(metadata: Dictionary) -> void:
	for key in ["provider", "dataset", "source_url", "source_last_modified", "source_zip_sha256", "source_zip_bytes", "source_entry", "generated_at", "scope", "coverage", "selection_rule", "source_rows", "selected_rows", "unique_stations"]:
		_check(metadata.has(key) and str(metadata.get(key, "")).strip_edges() != "", "Metadado de proveniência ausente: %s" % key)
	_check(str(metadata.get("source_url", "")).begins_with("https://www.anatel.gov.br/"), "URL não aponta para a fonte oficial Anatel.")
	_check(str(metadata.get("source_zip_sha256", "")).length() == 64, "SHA-256 do ZIP inválido.")
	_check(int(metadata.get("source_rows", 0)) == 3292893, "Quantidade auditada de linhas divergiu da varredura completa.")
	_check(str(metadata.get("scope", "")) == "Regional", "Recorte regional não está explícito.")
	for generation in ["2G", "3G", "4G", "5G"]:
		_check(generation in (metadata.get("generations", []) as Array), "Geração oficial ausente do metadado: %s" % generation)


func _validate_stations(stations: Array[Dictionary]) -> void:
	_check(stations.size() == 667, "Quantidade de ERBs deduplicadas inesperada: %d" % stations.size())
	var generation_counts := {"2G": 0, "3G": 0, "4G": 0, "5G": 0}
	var has_missing_source_field := false
	var has_informed_source_field := false
	var has_informed_city := false
	for station in stations:
		var latitude := float(station.get("lat", 0.0))
		var longitude := float(station.get("lng", 0.0))
		_check(latitude >= -7.25 and latitude <= -4.0, "Latitude fora do recorte oficial: %s" % latitude)
		_check(longitude >= -49.0 and longitude <= -46.5, "Longitude fora do recorte oficial: %s" % longitude)
		_check(not (is_zero_approx(latitude) and is_zero_approx(longitude)), "Coordenada fictícia 0,0 encontrada.")
		_check(str(station.get("status", "")).to_lower() == "licenciada", "Situação não licenciada entrou no catálogo.")
		var generation := str(station.get("generation", ""))
		_check(generation_counts.has(generation), "Geração não reconhecida: %s" % generation)
		generation_counts[generation] = int(generation_counts.get(generation, 0)) + 1
		var city := str(station.get("city", "")).strip_edges()
		has_informed_city = has_informed_city or city != ""
		var infrastructure_class := str(station.get("infrastructure_class", "")).strip_edges()
		has_missing_source_field = has_missing_source_field or infrastructure_class == ""
		has_informed_source_field = has_informed_source_field or infrastructure_class != ""
	for generation in generation_counts:
		_check(int(generation_counts[generation]) > 0, "Catálogo não contém ERBs %s." % generation)
	_check(has_missing_source_field, "Teste precisa cobrir campo ausente da fonte.")
	_check(has_informed_source_field, "Nenhum valor informado da classe de infraestrutura foi preservado.")
	_check(has_informed_city, "Nenhum município informado pela fonte foi preservado.")


func _validate_filters(catalog: RefCounted) -> void:
	var result_5g: Dictionary = catalog.search_stations({"generation": "5G"})
	_check(bool(result_5g.get("ok", false)) and int(result_5g.get("station_count", 0)) > 0, "Filtro 5G não retornou estações.")
	for station in result_5g.get("stations", []) as Array:
		_check(str((station as Dictionary).get("generation", "")) == "5G", "Filtro 5G vazou outra geração.")
	var result_city: Dictionary = catalog.search_stations({"city": "Imperatriz - MA"})
	_check(int(result_city.get("station_count", 0)) > 0, "Filtro de município exato não retornou Imperatriz.")
	for station in result_city.get("stations", []) as Array:
		_check(str((station as Dictionary).get("city", "")).to_lower().contains("imperatriz"), "Filtro de município inferiu ERB sem campo oficial.")
	_check((result_city.get("metadata", {}) as Dictionary).has("source_zip_sha256"), "Pesquisa perdeu proveniência da fonte.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
