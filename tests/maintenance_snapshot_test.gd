extends SceneTree

const Snapshot := preload("res://src/features/big_map/maintenance_snapshot.gd")
var failures := 0


func _init() -> void:
	var snapshot := Snapshot.new()
	var ticket := snapshot.begin()
	for offset in [0, 50, 100]:
		var rows: Array[Dictionary] = []
		for index in range(offset, mini(offset + 50, 123)):
			rows.append({"serial": "024%06d" % index, "ignition": index % 2})
		check(snapshot.accept_page(ticket, offset, {"ok": true, "rows": rows,
			"has_more": offset < 100, "next_offset": offset + 50, "total": 123}), "page")
	check(not snapshot.running and snapshot.rows.size() == 123, "stops after last page")
	check(snapshot.counters()["awaiting"] == 0, "nothing awaiting")
	check(not snapshot.accept_page(ticket, 150, {}), "no polling after completion")
	check(Snapshot.marker_color({"ignition": true, "updated_at": "old"}) == Color("#16a673"), "old ignition on stays green")
	check(Snapshot.marker_color({"ignition": false}) == Color("#dc3545"), "off red")
	check(Snapshot.ignition("1.0") == 1 and Snapshot.ignition("0.0") == 0, "API float encoding")
	check(Snapshot.marker_color({"speed": 70}) == null, "speed does not invent ignition")
	ticket = snapshot.begin()
	snapshot.cancel()
	check(not snapshot.accept_page(ticket, 0, {}), "late response ignored after cancel")
	ticket = snapshot.begin()
	check(not snapshot.accept_page(ticket, 0, {"ok": true, "rows": []}), "missing pagination rejected")
	ticket = snapshot.begin()
	check(not snapshot.accept_page(ticket, 0, {"ok": true, "rows": [], "has_more": true, "next_offset": 50}), "empty endless page rejected")
	ticket = snapshot.begin()
	check(not snapshot.accept_page(ticket, 0, {"ok": false}), "network failure stops")
	print("MAINTENANCE_SNAPSHOT_TEST failures=%d" % failures)
	quit(1 if failures else 0)


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
