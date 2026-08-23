extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		_fail("Dashboard nao compilou.")
		return
	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame

	var checks: Array[Callable] = [
		func(): return _check("timer_bateria", (dashboard.call("_guardian_timer_map") as Dictionary).get("bateria", null) == null),
		func():
			dashboard.call("_setup_internal_battery_monitor")
			return _check("monitor_bateria_desligado", dashboard.get("internal_battery_refresh_timer") == null),
		func():
			dashboard.set("internal_battery_queue", [{"serial": "024300001"}])
			var empty_products: Array[Dictionary] = []
			dashboard.call("_schedule_visible_internal_battery_batch", empty_products)
			return _check("fila_bateria_nao_reinicia", (dashboard.get("internal_battery_queue") as Array).is_empty()),
		func():
			dashboard.set("internal_battery_queue", [{"serial": "024300001"}])
			dashboard.set("internal_battery_busy", {"024300001": true})
			dashboard.set("internal_battery_cache", {"024300001": {"value": "100"}})
			dashboard.set("internal_battery_running", 1)
			dashboard.call("_pump_internal_battery_queue")
			return _check("estado_bateria_limpo", (dashboard.get("internal_battery_queue") as Array).is_empty() and (dashboard.get("internal_battery_busy") as Dictionary).is_empty() and (dashboard.get("internal_battery_cache") as Dictionary).is_empty() and int(dashboard.get("internal_battery_running")) == 0),
		func():
			dashboard.set("inventory_device_cycle_generation", 7)
			return _check("geracao_atual_aceita", bool(dashboard.call("_inventory_query_can_continue", 7, {}))),
		func():
			dashboard.set("inventory_device_cycle_generation", 7)
			return _check("geracao_antiga_descartada", not bool(dashboard.call("_inventory_query_can_continue", 6, {}))),
		func():
			dashboard.set("inventory_device_cycle_generation", 7)
			return _check("cancelamento_descarta_resposta", not bool(dashboard.call("_inventory_query_can_continue", 7, {"cancelled": true}))),
		func():
			dashboard.set("inventory_visible_scope_context_signature", "old")
			dashboard.set("internal_battery_queue", [{"serial": "024300001"}])
			dashboard.set("internal_battery_busy", {"024300001": true})
			dashboard.set("internal_battery_cache", {"024300001": {"value": "100"}})
			var next_products: Array[Dictionary] = [{"sku": "024300002", "imei": "024300002", "plate": "AAA - T001"}]
			dashboard.call("_sync_inventory_visible_scope", next_products)
			return _check("troca_de_pagina_limpa_bateria", (dashboard.get("internal_battery_queue") as Array).is_empty() and (dashboard.get("internal_battery_busy") as Dictionary).is_empty() and (dashboard.get("internal_battery_cache") as Dictionary).is_empty()),
		func():
			var queue_state: Dictionary = dashboard.call("_guardian_request_queue_component")
			return _check("diagnostico_ignora_bateria", str(queue_state.get("status", "")) == "ok"),
		func():
			var timers: Dictionary = dashboard.call("_guardian_timer_map")
			return _check("mapa_de_saude_sem_bateria", not timers.has("bateria") and not timers.has("bateria_interna")),
		func():
			var payload: Dictionary = dashboard.call("_grupo_rs_api_vehicle_payload", {"plate": "AAA - T001", "serial": "024300002"}, {}, "AAA - T001", 9021)
			return _check("associacao_sem_bateria", str(payload.get("placa", "")) == "AAAT001" and int(payload.get("codEquipamento", 0)) == 9021 and not payload.has("bateria")),
	]

	var passed := 0
	for index in checks.size():
		var result: Variant = checks[index].call()
		if result:
			passed += 1
			print("SAFE_QUERY_SCENARIO_%02d_OK" % (index + 1))
		else:
			_fail("Cenario %02d falhou." % (index + 1))
			return

	dashboard.queue_free()
	print("SAFE_QUERY_CYCLE_10_CHECK_OK passed=%d total=%d" % [passed, checks.size()])
	quit(0)


func _check(_name: String, value: bool) -> bool:
	return value


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
