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
	var now := int(Time.get_unix_time_from_system())
	dashboard.set("arya_status_busy", {"a": 1, "b": 1})
	dashboard.set("arya_status_cache", {
		"a": {"checked_at": now, "status": "consultando"},
		"b": {"checked_at": now, "status": "consultando"},
	})
	dashboard.set("location_status_busy", {"c": 1})
	dashboard.set("location_status_cache", {"c": {"checked_at": now, "label": "Consultando"}})
	dashboard.set("internal_battery_busy", {"d": true})
	dashboard.set("internal_battery_cache", {"d": {"checked_at": now}})
	dashboard.set("arya_auto_running", 2)
	dashboard.set("location_auto_running", 1)
	dashboard.set("internal_battery_running", 1)

	var normal: Dictionary = dashboard.call("_guardian_request_queue_component")
	if str(normal.get("status", "")) != "ok":
		_fail(dashboard, "Fila temporaria normal virou alerta: %s" % str(normal))
		return

	dashboard.set("arya_status_cache", {
		"a": {"checked_at": now - 300, "status": "consultando"},
		"b": {"checked_at": now, "status": "consultando"},
	})
	var stale: Dictionary = dashboard.call("_guardian_request_queue_component")
	if str(stale.get("status", "")) != "warning":
		_fail(dashboard, "Fila travada nao virou alerta: %s" % str(stale))
		return

	if str(dashboard.call("_http_result_message", HTTPRequest.RESULT_NO_RESPONSE, 0)) != "Servidor nao respondeu.":
		_fail(dashboard, "Mensagem HTTP 0 nao foi normalizada.")
		return
	if not bool(dashboard.call("_linksolutions_message_is_transient", "Servidor nao respondeu.")):
		_fail(dashboard, "Falha transitoria da Link Solutions nao foi reconhecida.")
		return

	dashboard.free()
	print("GUARDIAN_QUEUE_CHECK_OK")
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	if is_instance_valid(dashboard):
		dashboard.free()
	push_error(message)
	quit(1)
