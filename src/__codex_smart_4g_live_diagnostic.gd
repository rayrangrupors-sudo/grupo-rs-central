extends SceneTree


class LiveDashboard:
	extends "res://src/inventory_dashboard.gd"

	func _ready() -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := LiveDashboard.new()
	dashboard.selected_branch_id = "imperatriz"
	dashboard.selected_branch_name = "IMPERATRIZ"
	dashboard.selected_branch_grupo_rs_mode = "modern"
	dashboard.selected_branch_grupo_rs_base_url = "https://novogrupors.ddns.net/cadastro/"
	root.add_child(dashboard)
	await process_frame

	var response: Dictionary = await dashboard.call(
		"_fetch_dashboard_communication_interval",
		"0 - 1 Hora",
		2
	)
	if not bool(response.get("ok", false)):
		_fail("Faixa 0-1h indisponivel: %s" % str(response.get("message", "")))
		return
	var rows: Array[Dictionary] = dashboard.call(
		"_parse_dashboard_communication_rows",
		str(response.get("body", "")),
		"0 - 1 Hora"
	)
	var candidates: Array[Dictionary] = dashboard.call("_smart_4g_first_candidates", rows, 12)
	if candidates.is_empty():
		_fail("Nenhum candidato 024 encontrado.")
		return

	var login: Dictionary = await dashboard.call("_modern_grupo_rs_login")
	if not bool(login.get("ok", false)):
		_fail("Login de leitura falhou: %s" % str(login.get("message", "")))
		return

	var failures := {}
	for row in candidates:
		var client_name := str(row.get("client", "")).strip_edges()
		var plate := str(row.get("plate", "")).strip_edges()
		var client_id: String = await dashboard.call("_fetch_grupo_rs_client_id", client_name)
		if client_id == "":
			failures["cliente"] = int(failures.get("cliente", 0)) + 1
			continue
		var vehicle_id: String = await dashboard.call(
			"_fetch_smart_4g_records_vehicle_id",
			client_id,
			plate
		)
		if vehicle_id == "":
			failures["veiculo"] = int(failures.get("veiculo", 0)) + 1
			continue
		var event_result: Dictionary = await dashboard.call(
			"_fetch_smart_4g_latest_event",
			client_id,
			vehicle_id,
			str(row.get("updated_at", ""))
		)
		if not bool(event_result.get("ok", false)):
			var message := str(event_result.get("message", "evento"))
			failures[message] = int(failures.get(message, 0)) + 1
			continue
		var event: Dictionary = event_result.get("event", {})
		var report := {
			"event_keys": event.keys(),
			"gps_at": event.get("data", event.get("data_completa", null)),
			"server_at": event.get(
				"data_comunicacao",
				event.get("DataComunicacao", event.get("data_servidor", event.get("DataServidor", null)))
			),
			"latitude": event.get("lat", event.get("latitude", null)),
			"longitude": event.get("lng", event.get("lon", event.get("longitude", null))),
			"ignition": event.get("ignicao", event.get("Ignicao", null)),
		}
		var live_row := row.duplicate(true)
		live_row["updated_at"] = report.get("server_at")
		live_row["data_gps"] = report.get("gps_at")
		live_row["data_servidor"] = report.get("server_at")
		live_row["latitude"] = report.get("latitude")
		live_row["longitude"] = report.get("longitude")
		live_row["ignition"] = report.get("ignition")
		var monitor_script := load("res://src/smart_4g_monitor.gd")
		var monitor = monitor_script.new()
		var snapshot: Dictionary = monitor.analyze([], {
			"0 - 1 Hora": [live_row],
		}, {}, {
			"city": "Imperatriz - MA",
			"live_only": true,
		})
		var devices: Array = snapshot.get("devices", [])
		if devices.size() != 1:
			_fail("Analisador nao preservou a leitura real.")
			return
		var device := devices[0] as Dictionary
		if not bool(device.get("location_available", false)):
			_fail("Analisador descartou a coordenada real.")
			return
		if int(device.get("estimated_signal_score", 0)) <= 0:
			_fail("Analisador nao calculou o indice 4G.")
			return
		var summary: Dictionary = snapshot.get("summary", {})
		if int(summary.get("communicating", 0)) != 1 \
				or int(summary.get("regional_sample", 0)) != 1:
			_fail("Resumo real nao contou comunicacao e localizacao.")
			return
		print("SMART_4G_LIVE_EVENT=", JSON.stringify(report))
		print(
			"SMART_4G_LIVE_DIAGNOSTIC_OK score=%d delay=%s failures_before_success=%s" % [
				int(device.get("estimated_signal_score", 0)),
				str(device.get("platform_delay_label", "--")),
				str(failures),
			]
		)
		quit(0)
		return

	_fail("A amostra nao resolveu nenhum evento: %s" % str(failures))


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
