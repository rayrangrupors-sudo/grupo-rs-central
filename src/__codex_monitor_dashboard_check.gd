extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := load("res://src/__codex_auto_sms_dashboard_stub.gd")
	var store_script := load("res://src/inventory_store.gd")
	if dashboard_script == null or store_script == null:
		push_error("Scripts do monitor nao carregaram.")
		quit(1)
		return

	var dashboard: Node = dashboard_script.new()
	var test_store = store_script.new()
	_remove_test_files()
	test_store.configure("user://__codex_monitor_dashboard.json", "__codex_monitor_dashboard.json", "user://__codex_monitor_dashboard_backups", false)
	test_store.load_db()
	test_store.clear_pending_sync_queue()
	dashboard.set("store", test_store)
	dashboard.set("selected_branch_id", "__codex_monitor_dashboard")
	dashboard.set("selected_branch_name", "Imperatriz")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")

	test_store.add_system_log("Monitor enviou SMS Grupo RS", "Teste 1", "024300001")
	test_store.add_system_log("Monitor enviou SMS Grupo RS", "Teste 2", "024300002")
	test_store.add_system_log("Monitor recuperado", "Cliente: TESTE | Placa: ABC - 1234", "024300001")
	var metrics: Dictionary = dashboard.call("_auto_reset_log_metrics", test_store.get_system_logs(0))
	if int(metrics.get("sms", 0)) != 2 or absf(float(metrics.get("cost", 0.0)) - 0.046) > 0.0001:
		push_error("Metricas de SMS/custo incorretas: %s" % str(metrics))
		_cleanup(dashboard)
		quit(1)
		return
	if int(metrics.get("recovered", 0)) != 1:
		push_error("Recuperado nao entrou nas metricas: %s" % str(metrics))
		_cleanup(dashboard)
		quit(1)
		return

	dashboard.set("auto_reset_enabled", false)
	var monitor_view: Control = dashboard.call("_build_auto_reset_dashboard_view")
	if not _has_text(monitor_view, "Monitor automatico") \
		or not _has_text(monitor_view, "Visao geral") \
		or not _has_text(monitor_view, "Custos") \
		or not _has_text(monitor_view, "Ligar monitor"):
		push_error("Central do monitor nao montou os controles esperados.")
		monitor_view.free()
		_cleanup(dashboard)
		quit(1)
		return
	monitor_view.free()

	var online_panel: Control = dashboard.call("_build_online_lookup_panel")
	var online_rows: Array[Dictionary] = [{
		"serial": "02430556",
		"plate": "AAA - T250",
		"client": "CLIENTE SOMENTE GRUPO RS",
		"chip": "8955000000000000000",
		"phone": "(62) 99862-7283",
		"status": "Instalado",
	}]
	dashboard.call("_render_online_lookup_rows", online_rows)
	var location_button := _find_button_by_tooltip(online_panel, "Ver localizacao no Grupo RS")
	var sms_button := _find_button_by_tooltip(online_panel, "Enviar comando SMS")
	if location_button == null or sms_button == null:
		push_error("Resultado online nao recebeu os botoes de localizacao e SMS.")
		online_panel.free()
		_cleanup(dashboard)
		quit(1)
		return
	location_button.pressed.emit()
	sms_button.pressed.emit()
	if int(dashboard.get("test_location_button_calls")) != 1 \
		or int(dashboard.get("test_sms_dialog_calls")) != 1 \
		or str(dashboard.get("test_last_action_serial")) != "02430556":
		push_error("Botoes online nao encaminharam a serie correta.")
		online_panel.free()
		_cleanup(dashboard)
		quit(1)
		return
	online_panel.free()

	dashboard.set("auto_reset_enabled", true)
	dashboard.set("auto_reset_running", true)
	dashboard.call("_request_auto_reset_safe_stop")
	if not bool(dashboard.get("auto_reset_enabled")) or not bool(dashboard.get("auto_reset_stop_requested")):
		push_error("Parada segura interrompeu o ciclo antes da operacao atual terminar.")
		_cleanup(dashboard)
		quit(1)
		return
	dashboard.set("auto_reset_running", false)
	dashboard.call("_complete_auto_reset_safe_stop")
	if bool(dashboard.get("auto_reset_enabled")) or bool(dashboard.get("auto_reset_stop_requested")):
		push_error("Parada segura nao desligou o monitor ao final da operacao.")
		_cleanup(dashboard)
		quit(1)
		return

	_cleanup(dashboard)
	print("MONITOR_DASHBOARD_CHECK_OK")
	quit(0)


func _find_button_by_tooltip(node: Node, tooltip: String) -> Button:
	if node is Button and (node as Button).tooltip_text == tooltip:
		return node as Button
	for child in node.get_children():
		var found := _find_button_by_tooltip(child, tooltip)
		if found != null:
			return found
	return null


func _has_text(node: Node, expected: String) -> bool:
	if node is Label and (node as Label).text == expected:
		return true
	if node is Button and (node as Button).text == expected:
		return true
	for child in node.get_children():
		if _has_text(child, expected):
			return true
	return false


func _cleanup(dashboard: Node) -> void:
	_remove_test_files()
	var settings_path := ProjectSettings.globalize_path("user://app_settings.json")
	if FileAccess.file_exists(settings_path):
		var file := FileAccess.open(settings_path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else {}
		if typeof(parsed) == TYPE_DICTIONARY:
			var settings := parsed as Dictionary
			var states: Dictionary = settings.get("auto_reset_monitor_state_by_branch", {})
			states.erase("__codex_monitor_dashboard")
			settings["auto_reset_monitor_state_by_branch"] = states
			var writer := FileAccess.open(settings_path, FileAccess.WRITE)
			if writer != null:
				writer.store_string(JSON.stringify(settings, "\t"))
	dashboard.free()


func _remove_test_files() -> void:
	var path := ProjectSettings.globalize_path("user://__codex_monitor_dashboard.json")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")
	DirAccess.remove_absolute(path + ".tmp")
	DirAccess.remove_absolute(path + ".pending.json")
	DirAccess.remove_absolute(path + ".pending.json.bak")
	DirAccess.remove_absolute(path + ".pending.json.tmp")
