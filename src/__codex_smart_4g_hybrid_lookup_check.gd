extends SceneTree


class DashboardStub:
	extends "res://src/inventory_dashboard.gd"
	var api_mode := "empty"
	var platform_calls := 0

	func _grupo_rs_api_find_vehicle(_plate: String = "", _serial: String = "", _force_read: bool = true, _allow_full_scan: bool = true) -> Dictionary:
		if api_mode == "no_coords":
			return {"ok": true, "row": {"plate": "SMW - 6E12", "serial": "024400001", "vehicle_id": "19402"}}
		if api_mode == "success":
			return {"ok": true, "row": {"plate": "SMW - 6E12", "serial": "024400001", "lat": -5.5264, "lng": -47.4919}}
		if api_mode == "ambiguous":
			return {"ok": false, "not_found": false, "rows": [{}, {}], "message": "A API retornou 2 veiculos."}
		return {"ok": false, "not_found": true, "rows": [], "message": "A API retornou 0 veiculos."}

	func _grupo_rs_api_find_location(_serial: String, _plate: String, _vehicle_id: String = "") -> Dictionary:
		return {"ok": false, "message": "API sem coordenadas no teste."}

	func _smart_4g_platform_vehicle_by_plate(_plate: String) -> Dictionary:
		platform_calls += 1
		return {
			"ok": true,
			"source": "grupo_rs_platform",
			"row": {
				"plate": "SMW - 6E12",
				"serial": "024400001",
				"client": "CLIENTE TESTE",
				"lat": -5.5201,
				"lng": -47.4892,
				"resolution_source": "grupo_rs_platform",
			},
		}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := DashboardStub.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.selected_branch_grupo_rs_mode = "modern"

	var empty_result: Dictionary = await dashboard.call("_smart_4g_hybrid_vehicle_by_plate", "SMW - 6E12")
	if not bool(empty_result.get("ok", false)) or str(empty_result.get("source", "")) != "grupo_rs_platform":
		_fail(dashboard, "API vazia nao caiu para o portal: %s" % str(empty_result))
		return
	if dashboard.platform_calls != 1:
		_fail(dashboard, "Portal nao foi consultado uma vez no fallback da API vazia.")
		return

	dashboard.api_mode = "ambiguous"
	var ambiguous_result: Dictionary = await dashboard.call("_smart_4g_hybrid_vehicle_by_plate", "SMW - 6E12")
	if not bool(ambiguous_result.get("ok", false)) or str(ambiguous_result.get("source", "")) != "grupo_rs_platform":
		_fail(dashboard, "API ambigua nao caiu para o portal: %s" % str(ambiguous_result))
		return

	dashboard.api_mode = "success"
	var api_result: Dictionary = await dashboard.call("_smart_4g_hybrid_vehicle_by_plate", "SMW - 6E12")
	if not bool(api_result.get("ok", false)) or str(api_result.get("source", "")) != "grupo_rs_api":
		_fail(dashboard, "API valida nao foi priorizada: %s" % str(api_result))
		return
	if dashboard.platform_calls != 2:
		_fail(dashboard, "Portal foi consultado mesmo quando a API estava valida.")
		return

	dashboard.api_mode = "no_coords"
	var no_coords_result: Dictionary = await dashboard.call("_smart_4g_hybrid_vehicle_by_plate", "SMW - 6E12")
	if not bool(no_coords_result.get("ok", false)) or str(no_coords_result.get("source", "")) != "grupo_rs_platform":
		_fail(dashboard, "API sem coordenadas nao caiu para o portal: %s" % str(no_coords_result))
		return
	if dashboard.platform_calls != 3:
		_fail(dashboard, "Portal nao foi consultado quando a API nao tinha coordenadas.")
		return

	dashboard.queue_free()
	print("SMART_4G_HYBRID_LOOKUP_CHECK_OK")
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)
