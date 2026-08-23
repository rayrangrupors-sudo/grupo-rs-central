extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		_fail("Script principal nao compilou.")
		return
	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame

	dashboard.set("smart_4g_snapshot", {
		"updated_at": "05/08/2026 10:52:08",
		"devices": [{
			"serial": "024288677",
			"plate": "AAA - C40",
			"operator": "TIM",
			"network": "4G",
			"estimated_signal_score": 72,
			"signal_label": "Boa",
			"signal_confidence": "Alta",
			"last_communication": "05/08/2026 10:52:08",
		}],
	})

	var forecast: Dictionary = dashboard.call("_build_monitor_4g_signal_forecast", "024288677", {
		"plate": "AAA - C40",
		"lat": -5.5264,
		"lng": -47.4919,
	})
	if str(forecast.get("label", "")) != "Boa":
		_fail("Leitura recente do Monitor 4G nao retornou Boa.")
		return
	var detail := str(forecast.get("detail", ""))
	if not detail.contains("Monitor 4G") or not detail.contains("TIM 4G"):
		_fail("Detalhe nao identifica a fonte Monitor 4G e a rede.")
		return
	if detail.to_lower().contains("arya") or detail.to_lower().contains("linksolutions"):
		_fail("Previsao ainda referencia Arya ou Linksolutions.")
		return
	if bool(forecast.get("is_estimate", true)):
		_fail("Leitura recente foi marcada como previsao.")
		return

	dashboard.free()
	print("MONITOR_SIGNAL_FORECAST_CHECK_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
