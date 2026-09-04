extends SceneTree

class ParallelFlowProbe extends "res://src/inventory_dashboard.gd":
	var starts: Array[String] = []
	var finishes: Array[String] = []
	var events: Array[String] = []
	var records_calls := 0
	var refresh_calls := 0

	func _inventory_query_location_with_retries(_product: Dictionary, _generation: int, _worker_state: Dictionary, _source_mode: String) -> Dictionary:
		starts.append("aparelho")
		events.append("iniciou_aparelho")
		await get_tree().create_timer(0.05).timeout
		finishes.append("aparelho")
		events.append("terminou_aparelho")
		return {
			"ok": true,
			"updated_at": "2026-09-04 08:00:00",
			"ignition": "Ligado",
			"latitude": "-5.5",
			"longitude": "-47.4",
			"vehicle_id": "fixture-vehicle",
			"plate": "TST-0001",
		}

	func _inventory_query_chip_with_retries(_product: Dictionary, _generation: int, _worker_state: Dictionary) -> Dictionary:
		starts.append("chip")
		events.append("iniciou_chip")
		await get_tree().create_timer(0.05).timeout
		finishes.append("chip")
		events.append("terminou_chip")
		return {"ok": true, "status": "online", "apn": "hinova.br"}

	func _inventory_query_records_with_retries(_product: Dictionary, _location_result: Dictionary, _generation: int, _worker_state: Dictionary) -> Dictionary:
		records_calls += 1
		return {"ok": true, "event": {"gps_issue": false}}

	func _request_inventory_table_refresh() -> void:
		refresh_calls += 1


func _initialize() -> void:
	call_deferred("_run")


func _run_lookup_task(dashboard: Node, product: Dictionary, state: Dictionary, task: Dictionary) -> void:
	task["ok"] = await dashboard._run_visible_inventory_device_lookup(product, 12, state)
	task["done"] = true


func _run() -> void:
	var dashboard := ParallelFlowProbe.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set_process(false)
	dashboard.current_section = "inventory"
	dashboard.inventory_device_cycle_generation = 12
	dashboard.inventory_device_cycle_running = true
	var product := {
		"sku": "024300001",
		"imei": "024300001",
		"chip_number": "895500000000000001",
		"apn": "hinova.br",
		"plate": "TST-0001",
	}
	var state := {"cancelled": false}
	var communication_key := str(dashboard._inventory_communication_cache_key_for_product(product))
	dashboard.location_status_cache["024300001"] = {"ok": true, "stale": true}
	dashboard.arya_status_cache["895500000000000001"] = {"status": "offline", "stale": true}
	dashboard.inventory_communication_status_cache[communication_key] = {"label": "antigo"}
	dashboard.inventory_communication_history[communication_key] = {"server_unix": 1}
	dashboard.arya_resolve_cache[str(dashboard._arya_product_query_key(product))] = {"checked_at": 1}
	var round_products: Array[Dictionary] = [product]
	dashboard._clear_inventory_device_round_results(round_products)
	assert(not dashboard.location_status_cache.has("024300001"), "A rodada nova reutilizou localizacao antiga.")
	assert(not dashboard.arya_status_cache.has("895500000000000001"), "A rodada nova reutilizou status antigo do chip.")
	assert(not dashboard.inventory_communication_status_cache.has(communication_key), "A rodada nova reutilizou diagnostico antigo.")
	assert(not dashboard.inventory_communication_history.has(communication_key), "A rodada nova reutilizou historico temporal antigo.")
	dashboard.refresh_calls = 0
	var task := {"done": false, "ok": false}
	_run_lookup_task(dashboard, product, state, task)
	await process_frame
	assert(dashboard.starts == ["aparelho", "chip"], "Aparelho e chip nao iniciaram em paralelo na mesma linha.")
	while not bool(task.get("done", false)):
		await process_frame
	assert(bool(task.get("ok", false)), "O pacote da linha nao foi consolidado.")
	assert(dashboard.events.find("iniciou_chip") < dashboard.events.find("terminou_aparelho"), "O chip so iniciou depois da comunicacao terminar.")
	assert(dashboard.events.find("iniciou_aparelho") < dashboard.events.find("terminou_chip"), "A comunicacao so iniciou depois do chip terminar.")
	assert(dashboard.finishes.has("aparelho") and dashboard.finishes.has("chip"), "Uma das consultas paralelas nao terminou.")
	assert(dashboard.records_calls == 1, "Os registros do aparelho nao foram analisados apos a comunicacao.")
	assert(dashboard.refresh_calls == 1, "A linha nao foi atualizada uma unica vez ao consolidar os resultados.")
	assert(str((dashboard.arya_status_cache.get("895500000000000001", {}) as Dictionary).get("status", "")) == "online", "O status do chip nao foi salvo pelo ICCID.")
	assert(not (dashboard.location_status_cache.get("024300001", {}) as Dictionary).is_empty(), "O status do aparelho nao foi salvo pela serie.")

	dashboard.inventory_device_cycle_running = false
	dashboard.free()
	await process_frame
	print("INVENTORY_DEVICE_PARALLEL_FLOW_TEST: OK")
	quit(0)
