extends SceneTree

const Dashboard := preload("res://tests/fixtures/offline_inventory_dashboard.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dashboard := Dashboard.new()
	root.add_child(dashboard)
	await process_frame
	await process_frame
	dashboard.set_process(false)
	var products: Array[Dictionary] = []
	var first_page: Array = []
	for index in range(10):
		var serial := "100%d" % index
		products.append({"sku": "SKU-%s" % serial, "imei": serial, "plate": "AAA-%03d" % index})
		first_page.append(_api_row(serial, "AAA-%03d" % index))
	dashboard.offline_pages = [first_page, [_api_row("10010", "AAA-010")]]
	var second_products: Array[Dictionary] = products.duplicate(true)
	second_products.append({"sku": "SKU-10010", "imei": "10010", "plate": "AAA-010"})

	dashboard.schedule_visible_inventory_device_cycle(products, 0, 10, 11)
	dashboard.schedule_visible_inventory_device_cycle(products, 0, 10, 11)
	await process_frame
	await process_frame
	_check(int(dashboard.get("offline_max_in_flight")) <= 1, "Fila abriu consultas concorrentes.")
	_check(bool(dashboard.get("inventory_device_cycle_running")), "Fila não ficou contínua após a primeira página.")

	dashboard.schedule_visible_inventory_device_cycle(second_products, 0, 11, 11)
	await process_frame
	await process_frame
	_check(int(dashboard.get("inventory_device_cycle_generation")) > 1, "Novo contexto não substituiu a geração antiga.")
	_check(dashboard.offline_requests.size() <= 4, "Substituição criou uma rajada de requisições.")

	var page_state: Dictionary = dashboard.call("_inventory_communication_page_state", {"data": first_page, "paginacao": {"temMais": true}}, 0, 10)
	_check(bool(page_state.get("has_more", false)) and int(page_state.get("next_skip", -1)) == 10, "Paginação de 10 linhas não avançou para skip=10.")
	_check(dashboard.offline_refreshes >= 1, "Processamento não atualizou a tabela sem bloquear a interface.")
	dashboard.call("_inventory_communication_record_error", {"timeout": true, "response_code": 401})
	dashboard.call("_inventory_communication_record_error", {"response_code": 429})
	var metrics: Dictionary = dashboard.get("inventory_device_cycle_metrics")
	_check(int(metrics.get("timeouts", 0)) >= 1 and int(metrics.get("auth_errors", 0)) >= 1 and int(metrics.get("rate_limits", 0)) >= 1, "Métricas de timeout, autenticação e limite não foram sanitizadas/contabilizadas.")
	_check(dashboard.has_method("_show_form"), "Ação Editar deixou de existir no Estoque.")
	_check(dashboard.has_method("_request_delete"), "Ação Excluir deixou de existir no Estoque.")
	_check(dashboard.has_method("_install_equipment"), "Ação Dar baixa deixou de existir no Estoque.")
	_check(dashboard.has_method("_send_to_stock"), "Ação Estoque deixou de existir no Estoque.")
	dashboard.inventory_device_cycle_running = false
	dashboard.inventory_device_cycle_generation += 1
	dashboard.queue_free()
	await process_frame
	if failures.is_empty():
		print("INVENTORY_DASHBOARD_STOCK_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)

func _api_row(serial: String, plate: String) -> Dictionary:
	return {"numeroSerie": serial, "placa": plate, "data_servidor": "2026-08-26 11:59:00", "data_gps": "2026-08-26 11:59:00", "ignicao": 1, "latitude": "-5.5", "longitude": "-47.4"}

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
