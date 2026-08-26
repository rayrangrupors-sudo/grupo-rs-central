extends "res://src/inventory_dashboard.gd"

var offline_pages: Array = []
var offline_requests: Array[String] = []
var offline_refreshes := 0
var offline_in_flight := 0
var offline_max_in_flight := 0
var offline_stop_after_batch := false

func _grupo_rs_supports_modern_api() -> bool:
	return true

func _grupo_rs_api_reads_enabled() -> bool:
	return true

func _grupo_rs_api_get(path: String, _retry_login: bool = true, _force_read: bool = false) -> Dictionary:
	offline_in_flight += 1
	offline_max_in_flight = maxi(offline_max_in_flight, offline_in_flight)
	offline_requests.append(path)
	var rows: Array = _rows_for_query(path)
	var pagination := {"temMais": path.contains("skip=0") and not path.contains("q="), "proximoSkip": 10}
	offline_in_flight -= 1
	return {"ok": true, "response_code": 200, "body": JSON.stringify({"data": rows, "paginacao": pagination})}


func _rows_for_query(path: String) -> Array:
	var page_index := 1 if path.contains("skip=10") else 0
	var source_rows: Array = offline_pages[page_index] if page_index < offline_pages.size() else []
	if not path.contains("q="):
		return source_rows
	var encoded_query := path.get_slice("q=", 1).get_slice("&", 0)
	var query := encoded_query.uri_decode()
	var matches: Array = []
	for page in offline_pages:
		for row in page:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var candidate := row as Dictionary
			var serial := str(candidate.get("numeroSerie", candidate.get("serial", candidate.get("imei", ""))))
			var plate := str(candidate.get("placa", candidate.get("plate", "")))
			if _search_key(serial) == _search_key(query) or _normalize_location_plate(plate) == _normalize_location_plate(query):
				matches.append(candidate)
	return matches

func _wait_inventory_communication_interval(generation: int) -> bool:
	if offline_stop_after_batch:
		inventory_device_cycle_running = false
		return false
	await get_tree().process_frame
	return is_inside_tree() and generation == inventory_device_cycle_generation and inventory_device_cycle_running

func _request_inventory_table_refresh() -> void:
	offline_refreshes += 1

func _clear_screen() -> void:
	pass
