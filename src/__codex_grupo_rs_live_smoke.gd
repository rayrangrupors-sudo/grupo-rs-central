extends SceneTree

class DashboardStub:
	extends "res://src/inventory_dashboard.gd"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var dashboard := DashboardStub.new()
	root.add_child(dashboard)
	await process_frame
	var credentials: Dictionary = await dashboard.call("_grupo_rs_api_login_with_credentials", OS.get_environment("GRUPO_RS_API_USER"), OS.get_environment("GRUPO_RS_API_PASSWORD"))
	if not bool(credentials.get("ok", false)):
		push_error("LIVE_SMOKE_LOGIN_FAILED code=%s message=%s" % [str(credentials.get("response_code", 0)), str(credentials.get("message", ""))])
		dashboard.queue_free()
		quit(1)
		return
	var query := OS.get_environment("TEST_SERIAL") if OS.get_environment("TEST_SERIAL").strip_edges() != "" else "990000000001"
	var probe: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", query, true)
	var vehicle_probe: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", OS.get_environment("TEST_PLATE"), query, true) if OS.get_environment("TEST_PLATE").strip_edges() != "" else {}
	print("LIVE_SMOKE_OK login=true serial=%s read_ok=%s not_found=%s response_code=%s vehicle_ok=%s" % [query, str(bool(probe.get("ok", false))), str(bool(probe.get("not_found", false))), str(probe.get("response_code", 0)), str(bool(vehicle_probe.get("ok", false)))])
	dashboard.queue_free()
	quit(0)
