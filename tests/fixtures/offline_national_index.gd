## Índice nacional sintético para testar coalescência sem ler disco ou rede.
extends RefCounted

var delay_msec := 120
var query_calls := 0
var state_mutex := Mutex.new()


func query_viewport_threadsafe_to(
	bounds: Dictionary,
	zoom: int,
	_filters: Dictionary,
	result_target: Dictionary
) -> void:
	OS.delay_msec(delay_msec)
	state_mutex.lock()
	query_calls += 1
	state_mutex.unlock()
	var latitude := (float(bounds.get("min_lat", 0.0)) + float(bounds.get("max_lat", 0.0))) * 0.5
	var longitude := (float(bounds.get("min_lng", 0.0)) + float(bounds.get("max_lng", 0.0))) * 0.5
	result_target["result"] = {
		"ok": true,
		"stations": [{
			"id": "OFFLINE-%d-%d" % [zoom, roundi(longitude * 100000.0)],
			"lat": latitude,
			"lng": longitude,
			"operator": "TIM",
			"generation": "4G",
			"city": "Município sintético",
			"status": "Licenciada",
		}],
	}


func call_count() -> int:
	state_mutex.lock()
	var result := query_calls
	state_mutex.unlock()
	return result


func filter_entries(source: Array, _filters: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in source:
		if typeof(value) == TYPE_DICTIONARY:
			result.append((value as Dictionary).duplicate(true))
	return result
