extends SceneTree


class DashboardStub:
	extends "res://src/inventory_dashboard.gd"
	var started_at := {}

	func _lookup_sga_source_by_plate(plate: String, source: String) -> Dictionary:
		started_at[source] = Time.get_ticks_msec()
		await get_tree().create_timer(0.25 if source == "rastreio" else 0.40).timeout
		return {
			"ok": true,
			"state": "ok",
			"source": source,
			"plate": plate,
			"summary": "ATIVO",
		}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := DashboardStub.new()
	root.add_child(dashboard)
	await process_frame
	var started := Time.get_ticks_msec()
	var result: Dictionary = await dashboard.call("_lookup_sga_status_by_plate", "ROZ-6E10")
	var elapsed := Time.get_ticks_msec() - started
	var rastreio: Dictionary = result.get("rastreio", {})
	var protecao: Dictionary = result.get("protecao", {})
	var start_gap := absi(int(dashboard.started_at.get("rastreio", 0)) - int(dashboard.started_at.get("protecao", 0)))
	if not bool(rastreio.get("ok", false)) or not bool(protecao.get("ok", false)):
		_fail(dashboard, "A prova paralela nao recebeu os dois retornos.")
		return
	if start_gap > 150:
		_fail(dashboard, "As duas fontes nao foram iniciadas juntas.")
		return
	if elapsed >= 650:
		_fail(dashboard, "As consultas foram executadas em serie: %d ms." % elapsed)
		return
	dashboard.queue_free()
	await process_frame
	print("SGA_PARALLEL_LOGIC_CHECK_OK elapsed_ms=%d start_gap_ms=%d" % [elapsed, start_gap])
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)
