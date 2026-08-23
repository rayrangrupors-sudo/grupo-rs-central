extends SceneTree


class PlatformOnlyDashboard:
	extends "res://src/inventory_dashboard.gd"

	func _grupo_rs_api_reads_enabled() -> bool:
		return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := PlatformOnlyDashboard.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.selected_branch_id = "imperatriz"
	dashboard.selected_branch_grupo_rs_mode = "modern"
	dashboard.selected_branch_grupo_rs_base_url = "https://novogrupors.ddns.net/cadastro/"
	var result: Dictionary = await dashboard.call("_smart_4g_platform_vehicle_by_plate", "SMW - 6E12")
	print("SMART_4G_PLATFORM_FALLBACK_LIVE_RESULT=%s" % JSON.stringify(result))
	if not bool(result.get("ok", false)):
		_fail("Portal nao localizou SMW - 6E12: %s" % str(result))
		return
	var row := result.get("row", {}) as Dictionary
	var lat := str(row.get("lat", "")).replace(",", ".").to_float()
	var lng := str(row.get("lng", "")).replace(",", ".").to_float()
	if not is_finite(lat) or not is_finite(lng) or lat == 0.0 or lng == 0.0:
		_fail("Portal localizou a placa sem coordenadas validas: %s" % str(row))
		return
	print("SMART_4G_PLATFORM_FALLBACK_LIVE_CHECK_OK source=%s serial=%s client=%s lat=%s lng=%s" % [str(result.get("source", "")), str(row.get("serial", "")), str(row.get("client", "")), str(lat), str(lng)])
	dashboard.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
