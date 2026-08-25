## Testes determinísticos da camada que integra veículo, ERBs e operadora.
extends SceneTree

const Integration := preload("res://src/features/location/vehicle_location_integration.gd")

var failures: Array[String] = []


func _init() -> void:
	var integration := Integration.new()
	var first_generation := integration.begin_request()
	var second_generation := integration.begin_request()
	_check(first_generation == 1, "A primeira geração de consulta deveria ser 1.")
	_check(not integration.is_current(first_generation), "Resposta antiga não foi invalidada.")
	_check(integration.is_current(second_generation), "Geração atual não foi preservada.")

	var rows: Array[Dictionary] = [
		{"plate": "ABC1D23", "serial": "100", "client": "Cliente A", "lat": -5.5264, "lng": -47.4919},
		{"plate": "XYZ9K88", "serial": "200", "client": "Cliente B", "lat": -5.5300, "lng": -47.4900},
	]
	var selected := integration.select_vehicle(rows, "xyz9k88")
	_check(str(selected.get("serial", "")) == "200", "A pesquisa não selecionou o veículo solicitado.")

	var stations: Array[Dictionary] = [
		{"id": "tower-1", "operator": "TIM", "generation": "4G", "lat": -5.5265, "lng": -47.4920},
		{"id": "tower-1", "operator": "TIM", "generation": "4G", "lat": -5.5265, "lng": -47.4920},
		{"id": "tower-2", "operator": "VIVO", "generation": "2G", "lat": -5.6000, "lng": -47.5000},
	]
	var state := integration.compose_map_state(selected, stations, {"operator": "Claro", "source": "Arya"})
	var integrated: Dictionary = state.get("vehicle", {})
	_check((state.get("stations", []) as Array).size() == 2, "ERBs duplicadas não foram eliminadas.")
	_check(int(integrated.get("nearby_tower_count", 0)) == 2, "A quantidade de ERBs próximas não foi calculada.")
	_check(str(integrated.get("tracker_operator", "")) == "Claro", "A operadora real não foi propagada.")
	_check(float(integrated.get("nearest_tower_distance_km", -1.0)) >= 0.0, "A distância da ERB mais próxima não foi calculada.")

	var no_location := integration.compose_map_state({"plate": "NOPOS", "lat": 0.0, "lng": 0.0}, stations)
	_check(not bool(no_location.get("has_vehicle_location", true)), "Coordenada 0,0 foi tratada como localização válida.")
	_check((no_location.get("stations", []) as Array).is_empty(), "ERBs foram associadas a veículo sem localização.")

	if failures.is_empty():
		print("VEHICLE_LOCATION_INTEGRATION_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
