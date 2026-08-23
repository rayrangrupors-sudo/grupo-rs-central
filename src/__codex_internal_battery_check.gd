extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if source == "":
		push_error("Nao foi possivel ler o painel principal.")
		quit(1)
		return

	var header_start := source.find("func _build_table_header()")
	var header_end := source.find("func _refresh_table()", header_start)
	var row_start := source.find("func _make_table_row(product: Dictionary)")
	var row_end := source.find("func _make_arya_status_cell", row_start)
	var schedule_start := source.find("func _schedule_visible_internal_battery_batch")
	var schedule_end := source.find("func _schedule_online_tracker_records", schedule_start)
	if header_start < 0 or header_end < 0 or row_start < 0 or row_end < 0 or schedule_start < 0 or schedule_end < 0:
		push_error("As secoes da tabela e do ciclo de bateria nao foram encontradas.")
		quit(1)
		return

	var header_section := source.substr(header_start, header_end - header_start)
	var row_section := source.substr(row_start, row_end - row_start)
	var schedule_section := source.substr(schedule_start, schedule_end - schedule_start)
	if header_section.contains("Bat. Int") or header_section.contains("Bateria"):
		push_error("A coluna de bateria interna ainda aparece no cabecalho.")
		quit(1)
		return
	if row_section.contains("_make_internal_battery_cell") or row_section.contains("Bat. Int"):
		push_error("A linha ainda renderiza a bateria interna.")
		quit(1)
		return
	if not schedule_section.contains("_pump_internal_battery_queue"):
		push_error("O legado de bateria nao esta neutralizado pelo agendador.")
		quit(1)
		return

	var dashboard_script := load("res://src/inventory_dashboard.gd")
	if dashboard_script == null:
		push_error("O painel principal nao carregou.")
		quit(1)
		return
	var dashboard: Node = dashboard_script.new()
	dashboard.set("internal_battery_queue", [{"imei": "024123456"}])
	dashboard.set("internal_battery_cache", {"024123456": {"percent": 98}})
	dashboard.set("internal_battery_busy", {"024123456": true})
	dashboard.set("internal_battery_running", 1)
	dashboard.call("_pump_internal_battery_queue")
	if not (dashboard.get("internal_battery_queue") as Array).is_empty():
		_fail(dashboard, "A fila de bateria interna nao foi neutralizada.")
		return
	dashboard.free()
	print("INTERNAL_BATTERY_REMOVAL_CHECK_OK table=without_battery queue=disabled")
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	push_error(message)
	dashboard.free()
	quit(1)
