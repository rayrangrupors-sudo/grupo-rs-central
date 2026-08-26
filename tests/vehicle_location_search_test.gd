## Busca offline por placa/série: normalização, igualdade e ausência de fallback.
extends SceneTree

const Integration := preload("res://src/features/location/vehicle_location_integration.gd")

var failures: Array[String] = []


func _init() -> void:
	var integration := Integration.new()
	_check(integration.normalize_location_query(" abc-1d23 ") == "ABC1D23", "Placa formatada não foi normalizada.")
	_check(integration.normalize_location_query("ABC1D23") == "ABC1D23", "Placa compacta mudou durante a normalização.")
	_check(integration.normalize_location_query(" sn / 00-42 ") == "SN0042", "Série formatada não foi normalizada.")
	_check(str(integration.describe_location_query("ABC-1D23").get("kind", "")) == Integration.QUERY_KIND_PLATE, "Placa Mercosul não foi identificada.")
	_check(str(integration.describe_location_query("ABC-1234").get("kind", "")) == Integration.QUERY_KIND_PLATE, "Placa antiga não foi identificada.")
	_check(str(integration.describe_location_query("SN-0042").get("kind", "")) == Integration.QUERY_KIND_SERIAL, "Número de série não foi identificado.")

	var rows: Array[Dictionary] = [
		{"plate": "ABC1D23", "serial": "SN-0041"},
		{"plate": "XYZ9K88", "serial": "SN-0042"},
	]
	var by_formatted_plate := integration.find_exact_vehicle(rows, "xyz-9k88")
	_check(str(by_formatted_plate.get("serial", "")) == "SN-0042", "Placa formatada não selecionou a correspondência exata.")
	var by_compact_plate := integration.find_exact_vehicle(rows, "ABC1D23")
	_check(str(by_compact_plate.get("serial", "")) == "SN-0041", "Placa compacta não selecionou a correspondência exata.")
	var by_serial := integration.find_exact_vehicle(rows, "sn 0042")
	_check(str(by_serial.get("plate", "")) == "XYZ9K88", "Série não selecionou a correspondência exata.")
	_check(integration.find_exact_vehicle(rows, "ABC").is_empty(), "Consulta parcial foi aceita como exata.")
	_check(integration.find_exact_vehicle(rows, "ZZZ9Z99").is_empty(), "Consulta inexistente selecionou a primeira linha.")
	var collision_rows: Array[Dictionary] = [
		{"plate": "COL1A23", "serial": "SN-9001"},
		{"plate": "ZZZ9Z99", "serial": "COL1A23"},
	]
	var collision: Dictionary = integration.find_exact_vehicle_result(collision_rows, "COL1A23")
	_check(bool(collision.get("ambiguous", false)), "Colisão exata placa/série não foi sinalizada.")
	_check((collision.get("row", {}) as Dictionary).is_empty(), "Colisão placa/série selecionou um veículo arbitrário.")
	var serial_plate_shape := integration.find_exact_vehicle([{"plate": "ZZZ9Z99", "serial": "SER1A23"}], "SER1A23")
	_check(str(serial_plate_shape.get("serial", "")) == "SER1A23", "Série com formato de placa não foi localizada.")

	if failures.is_empty():
		print("VEHICLE_LOCATION_SEARCH_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
