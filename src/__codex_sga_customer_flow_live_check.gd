extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var client := OS.get_environment("CODEX_SGA_TEST_CLIENT").strip_edges()
	if client == "":
		push_error("CODEX_SGA_TEST_CLIENT nao informado.")
		quit(1)
		return
	var dashboard: Node = DashboardScript.new()
	root.add_child(dashboard)
	var started := Time.get_ticks_msec()
	var result: Dictionary = await dashboard.call("_lookup_sga_status_by_customer", client)
	var elapsed := Time.get_ticks_msec() - started
	print("SGA_CUSTOMER_FLOW_RESULT=%s" % JSON.stringify({
		"elapsed_ms": elapsed,
		"rastreio": result.get("rastreio", {}),
		"protecao": result.get("protecao", {}),
	}))
	if result.is_empty() or not result.has("rastreio") or not result.has("protecao"):
		push_error("Fluxo por cliente nao retornou as duas fontes SGA.")
		dashboard.queue_free()
		quit(1)
		return
	dashboard.queue_free()
	await process_frame
	print("SGA_CUSTOMER_FLOW_LIVE_CHECK_OK")
	quit(0)
