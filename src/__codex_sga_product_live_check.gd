extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard: Node = DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	var plate := OS.get_environment("CODEX_SGA_TEST_PLATE").strip_edges()
	var serial := OS.get_environment("CODEX_SGA_TEST_SERIAL").strip_edges()
	var client := OS.get_environment("CODEX_SGA_TEST_CLIENT").strip_edges()
	var result: Dictionary = await dashboard.call("_lookup_sga_status_for_product", {
		"sku": serial,
		"serial": serial,
		"plate": plate,
		"client": client,
	})
	var failed := false
	for source in ["rastreio", "protecao"]:
		var source_result: Dictionary = result.get(source, {})
		var state := str(source_result.get("state", ""))
		if state in ["loading", ""]:
			failed = true
		print("SGA_PRODUCT_%s=%s" % [source.to_upper(), state if state != "" else "INVALIDO"])
	if str(result.get("resolved_by", "")) != "plate":
		failed = true
		print("SGA_PRODUCT_RESOLUCAO=FALHA")
	else:
		print("SGA_PRODUCT_RESOLUCAO=PLACA")
	dashboard.queue_free()
	await process_frame
	quit(1 if failed else 0)
