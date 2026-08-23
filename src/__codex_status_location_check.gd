extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		push_error("Script principal nao compilou.")
		quit(1)
		return

	var dashboard: Node = dashboard_script.new()

	if str(dashboard.call("_arya_status_label", "online")) != "Online":
		_fail(dashboard, "Chip online nao esta com label Online.")
		return
	if str(dashboard.call("_arya_status_label", "offline")) != "Off":
		_fail(dashboard, "Chip offline nao esta com label Off.")
		return
	if str(dashboard.call("_normalize_arya_connection_status", true)) != "online":
		_fail(dashboard, "Arya true deveria virar online.")
		return
	if str(dashboard.call("_normalize_arya_connection_status", false)) != "offline":
		_fail(dashboard, "Arya false deveria virar offline.")
		return
	if str(dashboard.call("_normalize_linksolutions_status", "desconectado remoto")) != "offline":
		_fail(dashboard, "Linksolutions desconectado deveria virar offline.")
		return
	if str(dashboard.call("_normalize_linksolutions_status", "connected")) != "online":
		_fail(dashboard, "Linksolutions connected deveria virar online.")
		return

	var json_online := '{"status":true,"data":{"iccid":"8955548300001234567","imei":"024376142","msisdn":"5599999999999","conn_status":true,"last_conn_update":"17/07/2026 09:00:00","rat_type":"6"}}'
	var parsed_online: Dictionary = dashboard.call("_parse_rs300_arya_response", json_online, "8955548300001234567")
	if str(parsed_online.get("status", "")) != "online":
		_fail(dashboard, "JSON Arya online nao foi interpretado como online.")
		return

	var json_off := '{"status":true,"data":{"iccid":"8955548300007654321","imei":"024302023","msisdn":"5599888877777","conn_status":false,"last_conn_update":"17/07/2026 09:00:00","rat_type":"6"}}'
	var parsed_off: Dictionary = dashboard.call("_parse_rs300_arya_response", json_off, "8955548300007654321")
	if str(parsed_off.get("status", "")) != "offline":
		_fail(dashboard, "JSON Arya off nao foi interpretado como offline.")
		return

	var current_date := _current_grupo_rs_datetime()
	var ligado: Dictionary = dashboard.call("_location_monitoring_status", {
		"updated_at": current_date,
		"ignition": "Ligado",
		"speed": "0",
	})
	if str(ligado.get("label", "")) != "Ligado":
		_fail(dashboard, "Aparelho ligado nao apareceu como Ligado.")
		return

	var desligado: Dictionary = dashboard.call("_location_monitoring_status", {
		"updated_at": current_date,
		"ignition": "Desligado",
		"speed": "0",
	})
	if str(desligado.get("label", "")) != "Desligado":
		_fail(dashboard, "Aparelho desligado nao apareceu como Desligado.")
		return

	var desligado_numeric: Dictionary = dashboard.call("_location_monitoring_status", {
		"updated_at": current_date,
		"ignition": 0.0,
		"speed": "0",
	})
	if str(desligado_numeric.get("label", "")) != "Desligado":
		_fail(dashboard, "Ignicao numerica 0 nao apareceu como Desligado.")
		return

	var desatualizado: Dictionary = dashboard.call("_location_monitoring_status", {
		"updated_at": "01/01/2020 00:00:00",
		"ignition": "Ligado",
		"speed": "0",
	})
	if str(desatualizado.get("label", "")) != "Desatualizado":
		_fail(dashboard, "Aparelho antigo nao apareceu como Desatualizado.")
		return

	var sem_data: Dictionary = dashboard.call("_location_monitoring_status", {
		"updated_at": "",
		"ignition": "Ligado",
		"speed": "0",
	})
	if str(sem_data.get("label", "")) != "Sem data":
		_fail(dashboard, "Localizacao sem data nao apareceu como Sem data.")
		return

	if int(dashboard.call("_grupo_rs_datetime_to_unix", "2026-07-17T09:30:00")) <= 0:
		_fail(dashboard, "Data ISO do Grupo RS nao foi interpretada.")
		return
	if str(dashboard.call("_location_status_short_label", "Consultar localizacao")) != "Verificar":
		_fail(dashboard, "Texto curto de localizacao inicial incorreto.")
		return

	dashboard.free()
	print("STATUS_LOCATION_CHECK_OK")
	quit(0)


func _current_grupo_rs_datetime() -> String:
	var now := Time.get_datetime_dict_from_system(false)
	return "%02d/%02d/%04d %02d:%02d:%02d" % [
		int(now.get("day", 1)),
		int(now.get("month", 1)),
		int(now.get("year", 2026)),
		int(now.get("hour", 0)),
		int(now.get("minute", 0)),
		int(now.get("second", 0)),
	]


func _fail(dashboard: Node, message: String) -> void:
	if is_instance_valid(dashboard):
		dashboard.free()
	push_error(message)
	quit(1)
