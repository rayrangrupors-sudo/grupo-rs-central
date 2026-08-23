extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := load("res://src/inventory_dashboard.gd")
	if dashboard_script == null:
		push_error("Dashboard nao carregou.")
		quit(1)
		return

	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set("selected_branch_id", "__codex_auto_sms_live")
	dashboard.set("selected_branch_name", "Teste")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")

	var status: Dictionary = await dashboard.call("_fetch_grupo_rs_maintenance_rows_with_status")
	if not bool(status.get("ok", false)):
		_fail(dashboard, "Lista grafica do Grupo RS nao respondeu: %s" % str(status.get("message", "")))
		return

	var rows: Array = status.get("rows", [])
	if rows.is_empty():
		_fail(dashboard, "Lista grafica respondeu, mas nenhum aparelho 024 Hinova/Link foi encontrado.")
		return

	var has_hinova := false
	var has_link := false
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var item := row as Dictionary
		var serial := str(item.get("serial", ""))
		if not bool(dashboard.call("_auto_reset_serial_is_024", serial)):
			_fail(dashboard, "Lista trouxe serie invalida para o monitor: %s" % serial)
			return
		var apn := str(item.get("apn", ""))
		if bool(dashboard.call("_apn_is_hinova", apn)):
			has_hinova = true
		if bool(dashboard.call("_apn_is_linksolutions", apn)):
			has_link = true

	if not has_hinova and not has_link:
		_fail(dashboard, "Lista viva nao trouxe APN Hinova nem Link Solutions.")
		return

	print("AUTO_SMS_LIVE_READONLY_CHECK_OK rows=%d hinova=%s link=%s" % [rows.size(), str(has_hinova), str(has_link)])
	dashboard.queue_free()
	await process_frame
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	if is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)
