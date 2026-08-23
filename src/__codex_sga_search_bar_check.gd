extends SceneTree


class DashboardStub:
	extends "res://src/inventory_dashboard.gd"
	var plate_lookup_calls := 0
	var refresh_calls := 0

	func _lookup_sga_status_by_plate(plate: String, progress_callback: Callable = Callable()) -> Dictionary:
		plate_lookup_calls += 1
		var rastreio := {"ok": true, "state": "ok", "associate_status": "ATIVO", "vehicle_status": "ATIVO", "financial_status": "ADIMPLENTE"}
		var protecao := {"ok": true, "state": "ok", "associate_status": "ATIVO", "vehicle_status": "ATIVO", "financial_status": "ADIMPLENTE"}
		if progress_callback.is_valid():
			progress_callback.call("rastreio", rastreio)
			progress_callback.call("protecao", protecao)
		return {
			"plate": plate,
			"checked_at": int(Time.get_unix_time_from_system()),
			"resolved_by": "plate",
			"rastreio": rastreio,
			"protecao": protecao,
		}

	func _refresh_sga_status_views() -> void:
		refresh_calls += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := DashboardStub.new()
	root.add_child(dashboard)
	var search := LineEdit.new()
	search.text = "SMW - 6E12"
	root.add_child(search)
	dashboard.search_input = search
	await process_frame

	var queued: Dictionary = {"plate": "SMW - 6E12", "client": "RODRIGO MARTINS BORGES SILVA", "sku": "807383122"}
	var result: Dictionary = await dashboard.call("_lookup_sga_status_for_product", queued)
	if dashboard.plate_lookup_calls != 1:
		_fail(dashboard, "A busca pela barra nao usou a consulta direta por placa.")
		return
	if str(result.get("resolved_by", "")) != "plate":
		_fail(dashboard, "O resultado do SGA nao foi armazenado pela placa.")
		return

	dashboard.queue_free()
	search.queue_free()
	await process_frame
	print("SGA_SEARCH_BAR_CHECK_OK")
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)
