extends "res://src/inventory_dashboard.gd"

var offline_pages: Array = []
var offline_requests: Array[String] = []
var offline_refreshes := 0
var offline_in_flight := 0
var offline_max_in_flight := 0

func _grupo_rs_supports_modern_api() -> bool:
	return true

func _grupo_rs_api_reads_enabled() -> bool:
	return true

func _grupo_rs_api_get(path: String, _retry_login: bool = true, _force_read: bool = false) -> Dictionary:
	offline_in_flight += 1
	offline_max_in_flight = maxi(offline_max_in_flight, offline_in_flight)
	offline_requests.append(path)
	var page_index := 1 if path.contains("skip=10") else 0
	var rows: Array = offline_pages[page_index] if page_index < offline_pages.size() else []
	var pagination := {"temMais": page_index == 0, "proximoSkip": 10}
	offline_in_flight -= 1
	return {"ok": true, "response_code": 200, "body": JSON.stringify({"data": rows, "paginacao": pagination})}

func _wait_inventory_communication_interval(generation: int) -> bool:
	await get_tree().process_frame
	return is_inside_tree() and generation == inventory_device_cycle_generation and inventory_device_cycle_running

func _request_inventory_table_refresh() -> void:
	offline_refreshes += 1

func _clear_screen() -> void:
	pass
