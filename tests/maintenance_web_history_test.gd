extends SceneTree
const History := preload("res://src/features/big_map/maintenance_web_history.gd")
const Dates := preload("res://src/inventory_communication_status.gd")
var failures := 0

class FakeHost extends Node:
	var ambiguous := false
	var history_calls := 0
	var wrong_vehicle := false
	var last_path := ""
	func _grupo_rs_api_numeric_string_value(data: Dictionary, keys: Array[String]) -> String:
		var controller = preload("res://src/features/big_map/big_map_tracking_layout.gd").new()
		var value: String = controller._grupo_rs_api_numeric_string_value(data, keys)
		controller.free()
		return value
	func _grupo_rs_datetime_to_unix(value: String) -> int:
		return Dates.parse_datetime(value)
	func _grupo_rs_client_lookup_url(_name: String) -> String:
		return "lookup"
	func _search_key(value: String) -> String:
		return value.to_lower().strip_edges()
	func _format_grupo_rs_records_datetime(value: int) -> String:
		return Time.get_datetime_string_from_unix_time(value)
	func _grupo_rs_api_normalize_location(row: Dictionary) -> Dictionary:
		var result := row.duplicate(true)
		result["vehicle_id"] = str(row.get("codVeiculo", row.get("id", "")))
		return result
	func _modern_grupo_rs_read_get(path: String) -> Dictionary:
		if path == "lookup":
			var items := [{"id": 1.0, "text": "Cliente teste"}]
			if ambiguous:
				items.append({"id": "2", "text": "Cliente teste"})
			return {"ok": true, "body": JSON.stringify({"items": items})}
		history_calls += 1
		last_path = path
		var events := []
		for index in range(35):
			events.append({"id": index + 100, "cod_veiculo": "99" if wrong_vehicle else "9", "updated_at": Time.get_datetime_string_from_unix_time(1788307200 + index * 60), "ignition": index % 2})
		return {"ok": true, "body": JSON.stringify({"eventos": events})}


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var host := FakeHost.new()
	root.add_child(host)
	var row := {"client": "Cliente teste", "vehicle_id": "9", "updated_at": "2026-09-02 12:00:00"}
	var result := await History.fetch(host, row)
	check(result.get("ok", false) and result.get("records", []).size() == 20, "latest twenty")
	check(host.last_path.contains("cliente=1&"), "numeric JSON client sent as integer")
	check(result.records[0].history_unix > result.records[19].history_unix, "descending order")
	host.ambiguous = true
	result = await History.fetch(host, row)
	check(not result.get("ok", true) and host.history_calls == 1, "ambiguous client never queried")
	host.ambiguous = false
	result = await History.fetch(host, row, func(): return false)
	check(not result.get("ok", true) and host.history_calls == 1, "cancel stops subsequent request")
	host.wrong_vehicle = true
	result = await History.fetch(host, row)
	check(not result.get("ok", true), "wrong vehicle rejected")
	host.queue_free()
	print("MAINTENANCE_WEB_HISTORY_TEST failures=%d" % failures)
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
