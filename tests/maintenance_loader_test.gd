extends SceneTree
const Loader := preload("res://src/features/big_map/maintenance_loader.gd")
const Analysis := preload("res://src/features/big_map/maintenance_analysis.gd")
var failures := 0

class FakeHost extends Node:
	var active := 0
	var peak := 0
	var calls := 0
	func _vehicle_location_has_valid_coordinates(row: Dictionary) -> bool:
		return row.has("lat") and row.has("lng")
	func _modern_grupo_rs_read_get(_path: String) -> Dictionary:
		return {"ok": true, "body": "<tbody></tbody>"}
	func _parse_dashboard_communication_rows(_body: String, _interval: String) -> Array:
		return [{"serial": "0241", "client": "WEB_MUST_NOT_LEAK"}, {"serial": "0242", "client": "WEB_FALLBACK"}, {"serial": "0243"}]
	func _legacy_select_options(_html: String, _name: String) -> Array:
		return [{"value": "1", "label": "Vivo"}]
	func _grupo_rs_api_get(_path: String, _retry: bool, _force: bool) -> Dictionary:
		active += 1
		calls += 1
		peak = maxi(peak, active)
		await get_tree().create_timer(0.01).timeout
		active -= 1
		var rows := [{"serial": "0241", "vehicle_id": "1"}, {"serial": "0242", "vehicle_id": "2"}]
		if _path.contains("equipamentos"):
			rows = [{"serial": "0241", "client": "API", "codOperadora": 1}, {"serial": "0242", "codOperadora": 1}]
		if _path.contains("localizacao"):
			rows = [{"vehicle_id": "1", "ignition": 1}, {"vehicle_id": "2", "ignition": 0}]
		return {"ok": true, "body": JSON.stringify({"rows": rows})}
	func _grupo_rs_api_extract_rows(payload: Dictionary) -> Array:
		return payload.rows
	func _grupo_rs_api_equipment_rows(payload: Dictionary) -> Array:
		return payload.rows
	func _grupo_rs_api_normalize_location(row: Dictionary) -> Dictionary:
		var result := row.duplicate(true)
		result["raw"] = row.duplicate(true)
		return result
	func _grupo_rs_api_pagination_state(_payload: Variant, _skip: int, _size: int) -> Dictionary:
		return {"pagination": {"temMais": false}, "has_more": false}
	func _grupo_rs_api_find_equipment(serial: String, _force: bool) -> Dictionary:
		active += 1
		calls += 1
		peak = maxi(peak, active)
		await get_tree().create_timer(0.01).timeout
		active -= 1
		return {"ok": true, "row": {"serial": serial, "client": "API" if serial == "0241" else "", "codOperadora": 1}}
	func _grupo_rs_api_find_vehicle(_plate: String, serial: String, _force: bool, scan: bool) -> Dictionary:
		assert(not scan)
		if serial == "0243":
			return {"ok": false}
		return {"ok": true, "row": {"serial": serial, "vehicle_id": serial.right(1)}}
	func _grupo_rs_api_find_location(_serial: String, _plate: String, vehicle: String, _scan: bool) -> Dictionary:
		active += 1
		calls += 1
		peak = maxi(peak, active)
		await get_tree().create_timer(0.01).timeout
		active -= 1
		return {"ok": true, "location": {"vehicle_id": vehicle, "ignition": int(vehicle) % 2,"lat":-5.5,"lng":-47.5}}
	func _vehicle_location_merge_identity(location: Dictionary, identity: Dictionary) -> Dictionary:
		var merged := identity.duplicate(true)
		merged.merge(location, true)
		return merged


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var host := FakeHost.new()
	root.add_child(host)
	var loader := Loader.new()
	var progressive := {"seen":false}
	loader.changed.connect(func():
		if loader.running and not loader.rows.is_empty() and loader.processed < loader.total:
			progressive.seen = true
	)
	await loader.start(host)
	check(progressive.seen,"publishes before all devices finish")
	check(not loader.running and loader.processed == 3, "completed")
	check(loader.failures == 1, "missing identity explicit")
	check(host.peak <= 2, "bounded concurrency")
	check(host.calls == 4, "bounded targeted equipment/location queries")
	check(loader.counts()["Ignição ligada"] == 1 and loader.counts()["Ignição desligada"] == 1, "ignition counts")
	check(not JSON.stringify(loader.rows).contains("WEB_MUST_NOT_LEAK"), "API identity takes precedence")
	check(JSON.stringify(loader.rows).contains("WEB_FALLBACK"), "authorized web client fallback")
	check(str(loader.rows[1].get("operator", "")) == "Vivo", "web operator catalog")
	var calls := host.calls
	await create_timer(0.3).timeout
	check(host.calls == calls, "no automatic polling")
	loader.start(host)
	loader.cancel()
	await create_timer(0.3).timeout
	check(not loader.running, "cancellation")
	var summary := Analysis.summarize([{"battery_voltage": "5", "ignition": 1, "server_at": "2026-09-02 15:00:00", "gps_at": "2026-09-02 12:00:00"}], {"status": "erro"})
	check(summary.contains("abaixo de 9 V") and summary.contains("superior a 2 h"), "evidence")
	check(summary.contains("Chip agora: indisponível"), "error is not offline")
	host.queue_free()
	print("MAINTENANCE_LOADER_TEST failures=%d" % failures)
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
