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

	var page_state: Dictionary = dashboard.call("_inventory_communication_page_state", {"data": first_page, "paginacao": {"temMais": true}}, 0, 10)
	_check(bool(page_state.get("has_more", false)) and int(page_state.get("next_skip", -1)) == 10, "Paginação de 10 linhas não avançou para skip=10.")
	_check(dashboard.offline_refreshes >= 1, "Processamento não atualizou a tabela sem bloquear a interface.")
	dashboard.call("_inventory_communication_record_error", {"timeout": true, "response_code": 401})
	dashboard.call("_inventory_communication_record_error", {"response_code": 429})
	var metrics: Dictionary = dashboard.get("inventory_device_cycle_metrics")
	_check(int(metrics.get("timeouts", 0)) >= 1 and int(metrics.get("auth_errors", 0)) >= 1 and int(metrics.get("rate_limits", 0)) >= 1, "Métricas de timeout, autenticação e limite não foram sanitizadas/contabilizadas.")
	await _check_visible_round(dashboard)
	_check_identity_matching(dashboard)
	_check_icon_palette(dashboard)
	_check_latest_api_record_wins(dashboard)
	_check_inventory_temporal_order_matrix(dashboard)
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


func _check_visible_round(dashboard: Node) -> void:
	dashboard.inventory_device_cycle_running = false
	dashboard.inventory_device_cycle_generation += 1
	await process_frame
	dashboard.offline_requests.clear()
	dashboard.offline_pages = []
	dashboard.offline_stop_after_batch = true
	dashboard.inventory_communication_status_cache.clear()
	dashboard.inventory_communication_history.clear()
	var visible_products: Array[Dictionary] = []
	var visible_rows: Array[Dictionary] = []
	for index in range(4):
		var serial := "200%d" % index
		visible_products.append({"sku": "SKU-VISIBLE-%s" % serial, "imei": serial, "plate": "VIS-%03d" % index})
		visible_rows.append(_api_row(serial, "VIS-%03d" % index))
	dashboard.offline_pages = [visible_rows]
	dashboard.schedule_visible_inventory_device_cycle(visible_products, 0, 4, 4)
	for _frame in range(8):
		await process_frame
	_check(dashboard.inventory_communication_status_cache.size() == 4, "A primeira rodada visível não promoveu os quatro matches exatos.")
	_check(dashboard.offline_max_in_flight <= 1, "A rodada visível abriu mais de uma requisição em voo.")
	_check(dashboard.offline_requests.size() == 4, "A rodada visível não consultou exatamente as quatro linhas.")
	for request in dashboard.offline_requests:
		_check(str(request).contains("q=") and str(request).contains("take=10") and not str(request).contains("skip=10"), "A rodada visível não usou consulta q com take=10.")

	dashboard.inventory_device_cycle_running = false
	dashboard.inventory_device_cycle_generation += 1
	dashboard.inventory_communication_status_cache.clear()
	dashboard.inventory_communication_history.clear()
	dashboard.offline_refreshes = 0
	var one_product: Dictionary = visible_products[0]
	var one_row_variant: Variant = dashboard.call("_grupo_rs_api_normalize_location", visible_rows[0])
	if typeof(one_row_variant) == TYPE_DICTIONARY:
		var one_row := one_row_variant as Dictionary
		var one_page: Array[Dictionary] = [one_row]
		var before_signature := str(dashboard.call("_inventory_row_signature", one_product))
		dashboard.call("_process_inventory_communication_page", one_page)
		var after_signature := str(dashboard.call("_inventory_row_signature", one_product))
		var first_refreshes: int = dashboard.offline_refreshes
		dashboard.call("_process_inventory_communication_page", one_page)
		var final_signature := str(dashboard.call("_inventory_row_signature", one_product))
		_check(before_signature != after_signature and after_signature == final_signature, "A assinatura não refletiu corretamente a alteração/estabilidade do cache.")
		_check(first_refreshes == dashboard.offline_refreshes, "Cache inalterado forçou novo redraw.")
	var before_empty_count: int = dashboard.inventory_communication_status_cache.size()
	var empty_page: Array[Dictionary] = []
	dashboard.call("_process_inventory_communication_page", empty_page)
	_check(dashboard.inventory_communication_status_cache.size() == before_empty_count, "Resposta vazia alterou o cache de forma indevida.")
	dashboard.offline_stop_after_batch = false


func _check_icon_palette(dashboard: Node) -> void:
	var soft_button: Button = dashboard.call("_make_icon_action_button", "res://assets/icons/editar.svg", Color("#f8fbfe"), Color("#c9d9e8"), Vector2(42, 34), Callable())
	var blue_button: Button = dashboard.call("_make_icon_action_button", "res://assets/icons/mensagem.svg", Color("#0b6fae"), Color("#0b6fae"), Vector2(34, 34), Callable())
	var red_button: Button = dashboard.call("_make_icon_action_button", "res://assets/icons/deletar.svg", Color("#b64747"), Color("#b64747"), Vector2(34, 34), Callable())
	var soft_icon := (soft_button.get_child(0) as CenterContainer).get_child(0) as TextureRect
	var blue_icon := (blue_button.get_child(0) as CenterContainer).get_child(0) as TextureRect
	var red_icon := (red_button.get_child(0) as CenterContainer).get_child(0) as TextureRect
	_check(soft_icon.texture != null, "Ícone Editar não carregou textura.")
	_check(soft_icon.modulate != Color.WHITE, "Ícone Editar não recebeu contraste no fundo soft.")
	_check(blue_icon.texture != null and blue_icon.modulate == Color.WHITE, "Ícone azul deixou de permanecer branco.")
	_check(red_icon.texture != null and red_icon.modulate == Color.WHITE, "Ícone vermelho deixou de permanecer branco.")
	soft_button.queue_free()
	blue_button.queue_free()
	red_button.queue_free()

func _check_latest_api_record_wins(dashboard: Node) -> void:
	dashboard.inventory_communication_status_cache.clear()
	dashboard.inventory_communication_history.clear()
	var product: Dictionary = {"imei": "9901", "plate": "API-001"}
	var active_products: Array[Dictionary] = [product]
	dashboard.set("inventory_device_cycle_products", active_products)
	var newer_variant: Variant = dashboard.call("_grupo_rs_api_normalize_location", {"numeroSerie": "9901", "data_servidor": "2026-08-26 12:50:30", "data_gps": "2026-08-26 12:50:30", "ignicao": 0, "latitude": "-5.5", "longitude": "-47.4"})
	var older_variant: Variant = dashboard.call("_grupo_rs_api_normalize_location", {"numeroSerie": "9901", "data_servidor": "2026-08-26 11:00:00", "data_gps": "2002-08-26 12:49:02", "ignicao": 1, "latitude": "-5.5", "longitude": "-47.4"})
	if typeof(newer_variant) == TYPE_DICTIONARY and typeof(older_variant) == TYPE_DICTIONARY:
		_check(str((newer_variant as Dictionary).get("server_at", "")) != "" and str((newer_variant as Dictionary).get("gps_at", "")) != "", "Normalização removeu as datas sintéticas da amostra recente.")
		_check(str(dashboard.call("_inventory_match_family", product, newer_variant as Dictionary)) == "serial", "A amostra sintética recente não correspondeu ao produto por série.")
		var newer_page: Array[Dictionary] = [newer_variant as Dictionary]
		var older_page: Array[Dictionary] = [older_variant as Dictionary]
		dashboard.call("_process_inventory_communication_page", newer_page)
		var synthetic_key := str(dashboard.call("_inventory_communication_cache_key_for_product", product))
		_check(dashboard.inventory_communication_status_cache.has(synthetic_key), "A amostra sintética recente não foi promovida para a chave esperada.")
		var first_status: Dictionary = dashboard.inventory_communication_status_cache.get(synthetic_key, {}) as Dictionary
		_check(int(first_status.get("server_unix", 0)) > 0 and int(first_status.get("gps_unix", 0)) > 0, "A amostra sintética mais recente não produziu timestamps válidos.")
		dashboard.call("_process_inventory_communication_page", older_page)
		var status: Dictionary = dashboard.inventory_communication_status_cache.get(synthetic_key, {}) as Dictionary
		_check(str(status.get("server_at", "")) == "2026-08-26 12:50:30", "Registro histórico substituiu a comunicação mais recente.")
		_check(str(status.get("gps_at", "")) == "2026-08-26 12:50:30", "DataGPS histórica substituiu o registro atual.")


func _check_inventory_temporal_order_matrix(dashboard: Node) -> void:
	var base := {"server_unix": 200, "gps_unix": 150, "label": "confirmado", "coordinate_state": "valid", "coordinate_fingerprint": "base", "ignition_state": 1}
	var cases: Array[Dictionary] = [
		{"name": "ordem normal", "incoming": {"server_unix": 201, "gps_unix": 151}, "expected": 1},
		{"name": "resposta fora de ordem", "incoming": {"server_unix": 199, "gps_unix": 149}, "expected": -1},
		{"name": "servidor antigo gps novo", "incoming": {"server_unix": 199, "gps_unix": 999}, "expected": -1},
		{"name": "servidor novo gps antigo", "incoming": {"server_unix": 201, "gps_unix": 1}, "expected": 1},
		{"name": "datas invalidas", "incoming": {"server_unix": 0, "gps_unix": 0}, "expected": -1},
		{"name": "servidor ausente gps novo", "current": {"server_unix": 0, "gps_unix": 150}, "incoming": {"server_unix": 0, "gps_unix": 151}, "expected": 1},
		{"name": "igualdade", "incoming": {"server_unix": 200, "gps_unix": 150}, "expected": 0},
	]
	for item in cases:
		var current: Dictionary = (item.get("current", base) as Dictionary).duplicate(true)
		var incoming: Dictionary = (item.get("incoming", {}) as Dictionary).duplicate(true)
		var order := int(dashboard.call("_inventory_communication_temporal_order", current, incoming))
		_check(order == int(item.get("expected", 99)), "Ordem temporal incorreta: %s." % str(item.get("name", "caso")))

	var equal_incoming := base.duplicate(true)
	equal_incoming["label"] = "regressao"
	equal_incoming["optional_detail"] = "complemento"
	var merged: Dictionary = dashboard.call("_merge_equal_inventory_communication_status", base, equal_incoming)
	_check(str(merged.get("label", "")) == "confirmado", "Empate substituiu estado já confirmado.")
	_check(str(merged.get("optional_detail", "")) == "complemento", "Empate não completou campo antes ausente.")

func _api_row(serial: String, plate: String) -> Dictionary:
	return {"numeroSerie": serial, "placa": plate, "data_servidor": "2026-08-26 11:59:00", "data_gps": "2026-08-26 11:59:00", "ignicao": 1, "latitude": "-5.5", "longitude": "-47.4"}


func _check_identity_matching(dashboard: Node) -> void:
	var cases: Array[Dictionary] = [
		{"family": "serial", "product": {"sku": "SKU-SERIAL", "imei": "7001"}, "row": {"numeroSerie": "7001"}},
		{"family": "plate", "product": {"sku": "SKU-PLATE", "plate": "ABC-1234"}, "row": {"placa": "ABC1234"}},
		{"family": "vehicle_id", "product": {"sku": "SKU-VEHICLE", "vehicle_id": "88"}, "row": {"vehicle_id": "88"}},
		{"family": "equipment_id", "product": {"sku": "SKU-EQUIPMENT-ID", "equipment_id": "42"}, "row": {"equipmentId": "42"}},
		{"family": "equipment_number", "product": {"sku": "SKU-EQUIPMENT-NUMBER", "equipment_number": "9002"}, "row": {"numeroEquipamento": "9002"}},
	]
	for item in cases:
		dashboard.inventory_communication_status_cache.clear()
		dashboard.inventory_communication_history.clear()
		var product_page: Array[Dictionary] = [item["product"] as Dictionary]
		dashboard.set("inventory_device_cycle_products", product_page)
		var normalized_variant: Variant = dashboard.call("_grupo_rs_api_normalize_location", item["row"])
		_check(typeof(normalized_variant) == TYPE_DICTIONARY, "Normalização falhou para a família %s." % item["family"])
		if typeof(normalized_variant) != TYPE_DICTIONARY:
			continue
		var normalized := normalized_variant as Dictionary
		_check(str(dashboard.call("_inventory_match_family", item["product"], normalized)) == item["family"], "Matcher não reconheceu a família %s." % item["family"])
		var active_products_variant: Variant = dashboard.get("inventory_device_cycle_products")
		_check(typeof(active_products_variant) == TYPE_ARRAY and (active_products_variant as Array).size() == 1, "Coleção ativa não recebeu o produto da família %s." % item["family"])
		if typeof(active_products_variant) == TYPE_ARRAY and (active_products_variant as Array).size() == 1:
			_check(str(dashboard.call("_inventory_match_family", (active_products_variant as Array)[0] as Dictionary, normalized)) == item["family"], "Matcher não usou a coleção ativa para a família %s." % item["family"])
		var before_signature := str(dashboard.call("_inventory_row_signature", item["product"]))
		var page: Array[Dictionary] = [normalized]
		dashboard.call("_process_inventory_communication_page", page)
		var cache_key := str(dashboard.call("_inventory_communication_cache_key_for_product", item["product"]))
		_check(dashboard.inventory_communication_status_cache.has(cache_key), "Cache não foi criado para a família %s." % item["family"])
		var after_signature := str(dashboard.call("_inventory_row_signature", item["product"]))
		_check(before_signature != after_signature, "Assinatura não mudou para a família %s." % item["family"])

	dashboard.inventory_communication_status_cache.clear()
	dashboard.inventory_communication_history.clear()
	var ambiguous_products: Array[Dictionary] = [{"sku": "SKU-A", "imei": "7333"}, {"sku": "SKU-B", "imei": "7333"}]
	dashboard.set("inventory_device_cycle_products", ambiguous_products)
	var ambiguous_variant: Variant = dashboard.call("_grupo_rs_api_normalize_location", {"numeroSerie": "7333"})
	if typeof(ambiguous_variant) == TYPE_DICTIONARY:
		var ambiguous_page: Array[Dictionary] = [ambiguous_variant as Dictionary]
		dashboard.call("_process_inventory_communication_page", ambiguous_page)
	_check(dashboard.inventory_communication_status_cache.is_empty(), "Colisão de identidade promoveu status indevidamente.")

	var unmatched_products: Array[Dictionary] = [{"sku": "SKU-NO-MATCH", "imei": "7444"}]
	dashboard.set("inventory_device_cycle_products", unmatched_products)
	var unmatched_variant: Variant = dashboard.call("_grupo_rs_api_normalize_location", {"numeroSerie": "7555"})
	if typeof(unmatched_variant) == TYPE_DICTIONARY:
		var unmatched_page: Array[Dictionary] = [unmatched_variant as Dictionary]
		dashboard.call("_process_inventory_communication_page", unmatched_page)
	_check(dashboard.inventory_communication_status_cache.is_empty(), "Linha sem correspondência alterou o cache.")

	var alias_variant: Variant = dashboard.call("_grupo_rs_api_normalize_location", {"numeroEquipamento": "9003", "DataServidor": "2026-08-26 11:59:00", "DataGPS": "2026-08-26 11:59:00"})
	if typeof(alias_variant) == TYPE_DICTIONARY:
		var alias_row := alias_variant as Dictionary
		_check(str(alias_row.get("equipment_number", "")) == "9003", "numeroEquipamento top-level não foi normalizado.")
		_check(str(alias_row.get("server_at", "")) != "" and str(alias_row.get("gps_at", "")) != "", "Aliases de servidor/GPS não foram preservados.")
	var nested_alias_variant: Variant = dashboard.call("_grupo_rs_api_normalize_location", {"equipamento": {"numeroEquipamento": "9004", "numeroSerie": "7004"}})
	if typeof(nested_alias_variant) == TYPE_DICTIONARY:
		var nested_alias_row := nested_alias_variant as Dictionary
		_check(str(nested_alias_row.get("equipment_number", "")) == "9004" and str(nested_alias_row.get("serial", "")) == "7004", "Aliases aninhados de equipamento/série não foram normalizados.")

	dashboard.set("inventory_device_cycle_products", unmatched_products)
	var partial_variant: Variant = dashboard.call("_grupo_rs_api_normalize_location", {"numeroSerie": "744"})
	if typeof(partial_variant) == TYPE_DICTIONARY:
		_check(str(dashboard.call("_inventory_match_family", unmatched_products[0], partial_variant as Dictionary)) == "", "Matcher aceitou correspondência parcial de identidade.")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
