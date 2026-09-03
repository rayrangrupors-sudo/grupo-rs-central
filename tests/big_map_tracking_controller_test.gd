## Exercita o controlador ativo sem rede: filtros, contagens e todos os pins.
extends SceneTree

const Controller := preload("res://tests/fixtures/offline_big_map_controller.gd")
const Integration := preload("res://src/features/location/vehicle_location_integration.gd")
const OfflineNationalIndex := preload("res://tests/fixtures/offline_national_index.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# O controlador e instanciado sem _ready para isolar somente o Mapa Grande;
	# isso evita iniciar timers e servicos globais do dashboard durante o teste.
	var dashboard := Controller.new()
	dashboard.current_section = "vehicle_location"
	dashboard.set("vehicle_location_integration", Integration.new())
	var view: Control = dashboard.call("_build_vehicle_location_view")
	root.add_child(dashboard)
	dashboard.add_child(view)
	await process_frame
	var operators: Array[String] = []
	var generations: Array[String] = []
	var cities: Array[String] = []
	var statuses: Array[String] = []
	view.set_erb_filter_values(operators, generations, cities, statuses)
	var canvas: Control = dashboard.get("vehicle_location_map_canvas")
	var no_tiles: Array[Dictionary] = []
	canvas.set_map_view(no_tiles, 13, Vector2.ZERO, Vector2(1000, 520), 0, 0)
	_check(canvas.tracking_locations.is_empty(), "Estado inicial contém veículos pré-carregados.")
	_check(str(view.metric_labels["Total"].text) == "0", "Estado inicial não começou com métrica zero.")
	var initial_load_generation := int(canvas.load_generation)
	dashboard.set("tracking_had_map_rows", true)
	var initial_reload_calls := int(dashboard.get("offline_reload_calls"))
	var initial_view_revision := int(canvas.map_view_revision)
	var now := Time.get_datetime_string_from_system(false, true)
	var rows: Array[Dictionary] = [
		{"plate": "TST1A01", "serial": "SN-1001", "client": "Cliente A", "lat": -5.5264, "lng": -47.4919, "coordinates_valid": true, "ignition": 1, "speed": "35", "updated_at": now},
		{"plate": "TST1A02", "serial": "SN-1002", "client": "Cliente B", "lat": -5.5310, "lng": -47.4860, "coordinates_valid": true, "ignition": 0, "speed": "0", "updated_at": now},
		{"plate": "TST1A03", "serial": "SN-1003", "client": "Cliente C", "lat": -5.5200, "lng": -47.5000, "coordinates_valid": true, "ignition": 0, "speed": "0", "updated_at": "2026-08-23 10:00:00"},
		{"plate": "TST1A04", "serial": "SN-1004", "client": "Cliente D", "lat": 0.0, "lng": 0.0, "coordinates_valid": false, "ignition": null, "speed": "0", "updated_at": now},
	]
	dashboard.set("vehicle_location_rows", rows.duplicate(true))
	_check(not view.add_button.disabled, "Botão Adicionar ficou desabilitado.")
	_check(view.add_button.mouse_filter != Control.MOUSE_FILTER_IGNORE, "Botão Adicionar não recebe interação do mouse.")
	await _test_query_ui_gestures(dashboard, view, rows)
	dashboard.set("vehicle_location_rows", rows.duplicate(true))
	initial_load_generation = int(canvas.load_generation)
	initial_reload_calls = int(dashboard.get("offline_reload_calls"))
	initial_view_revision = int(canvas.map_view_revision)
	dashboard.call("_apply_vehicle_location_filters")
	var filtered: Array = dashboard.get("vehicle_location_filtered_rows")
	var selected: Dictionary = {}
	_check(filtered.size() == 4, "Filtro Todos perdeu veiculos.")
	_check(canvas.tracking_locations.size() == 3, "Mapa nao recebeu todas as posicoes validas.")
	_check(str(view.metric_labels["Total"].text) == "4", "Total do recorte incorreto.")
	_check(str(view.metric_labels["Sem posição"].text) == "1", "Sem posicao incorreto.")
	_check(str(view.metric_labels["Desatualizados"].text) == "1", "Desatualizados incorreto.")
	_check(int(canvas.load_generation) == initial_load_generation, "Atualização de veículos reconstruiu tiles/ERBs.")
	_check(int(dashboard.get("offline_reload_calls")) == initial_reload_calls, "Atualização comum chamou o carregador de mapa.")
	_check(int(canvas.map_view_revision) == initial_view_revision, "Atualização comum reconstruiu o viewport.")
	view.monitor_select.select(1)
	dashboard.call("_apply_vehicle_location_filters")
	filtered = dashboard.get("vehicle_location_filtered_rows")
	_check(filtered.size() == 1, "Filtro Em movimento incorreto.")
	_check(canvas.tracking_locations.size() == 1, "Canvas nao respeitou o filtro operacional.")
	_check(int(dashboard.get("offline_reload_calls")) == initial_reload_calls, "Filtro operacional recarregou o mapa.")
	view.monitor_select.select(4)
	dashboard.call("_apply_vehicle_location_filters")
	filtered = dashboard.get("vehicle_location_filtered_rows")
	_check(filtered.size() == 1, "Filtro Sem posicao incorreto.")
	_check(canvas.tracking_locations.is_empty(), "Veiculo sem coordenada virou pin.")
	var stations_before_filter: int = canvas.stations.size()
	view.erb_generation_select.select(0)
	dashboard.call("_on_tracking_erb_filter_selected", 0)
	_check(int(canvas.load_generation) == initial_load_generation, "Filtro de ERB recarregou tiles.")
	_check(canvas.stations.size() == stations_before_filter, "Filtro Todos alterou a camada de ERBs.")

	# O Mapa Grande não possui resolvedor local de cliente nem Store como fonte.
	_check(not dashboard.has_method("_tracking_local_products"), "Mapa Grande ainda expõe Store como fonte de localização.")
	_check(bool(dashboard.get("vehicle_location_api_exclusive")), "Modo API exclusiva não foi ativado.")
	_check(bool(dashboard.get("vehicle_location_queue_after_api_success_only")), "Fila ainda aceita consulta antes da API.")

	# A pesquisa exata não usa o fallback visual da primeira linha.
	view.monitor_select.select(0)
	view.query_input.set_block_signals(true)
	view.query_input.text = "tst-1a02"
	view.query_input.set_block_signals(false)
	dashboard.call("_apply_vehicle_location_filters")
	await process_frame
	filtered = dashboard.get("vehicle_location_filtered_rows")
	selected = dashboard.get("vehicle_location_selected")
	_check(filtered.size() == 1 and str(selected.get("serial", "")) == "SN-1002", "Placa formatada não selecionou o veículo exato.")
	_check(int(canvas.selected_tracking_index) == 0, "Seleção exata não foi refletida no canvas.")
	_check(view.query_state_label.text == "Localização encontrada", "Controller não propagou o estado encontrado.")
	var focused_view: Dictionary = dashboard.get("offline_last_view")
	_check(int(dashboard.get("offline_reload_calls")) > 0, "Pesquisa exata não solicitou navegação real.")
	_check(int(focused_view.get("zoom", 0)) == 16 and int(canvas.map_zoom) == 16, "Pesquisa exata não centralizou no zoom 16.")
	var focused_center: Dictionary = focused_view.get("center", {})
	_check(absf(float(focused_center.get("lat", 0.0)) - float(selected.get("lat", 1.0))) < 0.000001, "Centro do foco não corresponde ao veículo.")

	view.query_input.set_block_signals(true)
	view.query_input.text = "SN 1003"
	view.query_input.set_block_signals(false)
	dashboard.call("_apply_vehicle_location_filters")
	await process_frame
	selected = dashboard.get("vehicle_location_selected")
	_check(str(selected.get("plate", "")) == "TST1A03", "Série não selecionou o veículo exato.")

	view.query_input.set_block_signals(true)
	view.query_input.text = "ZZZ9Z99"
	view.query_input.set_block_signals(false)
	dashboard.call("_apply_vehicle_location_filters")
	await process_frame
	selected = dashboard.get("vehicle_location_selected")
	_check(selected.is_empty(), "Consulta inexistente selecionou o primeiro veículo.")
	_check(int(canvas.selected_tracking_index) == -1, "Canvas manteve seleção após consulta inexistente.")
	_check(view.query_state_label.text == "Nenhuma localização encontrada", "Controller não propagou o estado não encontrado.")

	dashboard.set("vehicle_location_last_query_error_count", 1)
	dashboard.call("_apply_vehicle_location_filters")
	_check(view.query_state_label.text == "Falha de comunicação com a API Grupo RS", "Controller não propagou o diagnóstico sanitizado.")
	dashboard.set("vehicle_location_last_query_error_count", 0)
	_test_sanitized_query_diagnostics(dashboard)
	await _test_erb_query_burst(dashboard)
	var maintenance_rows: Array[Dictionary] = [
		{"serial": "024TEST1", "lat": -5.5, "lng": -47.5, "ignition": 1, "maintenance": true, "updated_at": "2000-01-01 00:00:00"},
		{"serial": "024TEST2", "lat": -5.5, "lng": -47.5, "ignition": 0, "maintenance": true},
		{"serial": "024TEST3", "lat": -5.5, "lng": -47.5, "maintenance": true},
	]
	_check(dashboard._location_monitoring_status(maintenance_rows[0]).label == "Ligado", "Manutenção antiga não pode amarelar a ignição ligada.")
	_check(dashboard._location_monitoring_status(maintenance_rows[1]).label == "Desligado", "Ignição desligada deve permanecer vermelha.")
	dashboard.vehicle_location_filtered_rows = maintenance_rows
	_check(dashboard._vehicle_location_rows_for_map().size() == 2, "Ignição desconhecida não deve inventar uma agulha colorida.")
	# Os filtros substituem linhas com queue_free; deixa a fila ser drenada antes
	# de desmontar a arvore para que o teste tambem detecte vazamentos reais.
	await process_frame
	await process_frame
	var empty_tracking_locations: Array[Dictionary] = []
	canvas.set_tracking_locations(empty_tracking_locations)
	canvas.set_coverage_profile({"stations": [], "metadata": {}})
	canvas.set("tracking_pin_green", null)
	canvas.set("tracking_pin_red", null)
	canvas.set("tracking_pin_yellow", null)
	canvas.set("erb_marker_claro", null)
	canvas.set("erb_marker_neutral", null)
	canvas.set("erb_marker_tim", null)
	canvas.set("erb_marker_vivo", null)
	dashboard.remove_child(view)
	view.free()
	root.remove_child(dashboard)
	dashboard.free()
	await process_frame
	if failures.is_empty():
		print("BIG_MAP_TRACKING_CONTROLLER_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _test_query_ui_gestures(dashboard: Node, view: Control, rows: Array[Dictionary]) -> void:
	var queue: Array = dashboard.get("vehicle_location_query_queue")
	queue.clear()
	view.query_input.text = "tst-1a02"
	view.query_input.text_changed.emit(view.query_input.text)
	_check(view.query_state_label.text == "Buscando localização...", "Digitação não mostrou loading imediato.")
	dashboard.set("offline_api_rows", rows.duplicate(true))
	view.add_button.pressed.emit()
	await _wait_query_finished(dashboard)
	_check(queue.size() == 1, "Clique em Adicionar não incluiu a placa na fila.")
	_check(view.queue_count_label.text == "Fila: 1 aparelho", "Resultado encontrado não sincronizou o contador visual da fila.")
	_check(str(dashboard.get("vehicle_location_query_trigger")) == "button", "Clique não registrou origem sanitizada.")
	_check(int(dashboard.get("offline_query_refresh_calls")) == 1, "Clique em Adicionar não agendou refresh offline.")
	_check(view.query_state_label.text == "Localização encontrada", "Clique por placa não mostrou found.")
	queue.clear()
	dashboard.call("_refresh_vehicle_location_queue_ui")

	# Cliente explícito é resolvido pelo mock da API e convertido em identidades
	# técnicas; o nome nunca vira item da fila nem seleciona o primeiro.
	var client_rows: Array[Dictionary] = [
		{"plate": "API1A01", "serial": "API-1001", "client": "Cliente API", "lat": -5.52, "lng": -47.49, "coordinates_valid": true, "coordinate_state": "valid"},
		{"plate": "API1A02", "serial": "API-1002", "client": "Cliente API", "lat": 0.0, "lng": 0.0, "coordinates_valid": false, "coordinate_state": "missing"},
		{"plate": "", "serial": "API-1003", "client": "Cliente API", "lat": -5.53, "lng": -47.48, "coordinates_valid": true, "coordinate_state": "valid"},
	]
	dashboard.set("offline_api_rows", client_rows)
	queue.append("API-1A01")
	dashboard.call("_refresh_vehicle_location_queue_ui")
	view.query_input.text = "cliente: Cliente API"
	view.query_input.text_changed.emit(view.query_input.text)
	view.add_button.pressed.emit()
	await _wait_query_finished(dashboard)
	_check(queue.size() == 3, "Cliente API não consolidou placa/série ou duplicou identidade mascarada.")
	_check(not queue.has("cliente: Cliente API"), "Nome do cliente foi usado como identidade da fila.")
	_check(queue.has("API-1003"), "Cliente API com placa vazia não usou a série como identidade.")
	_check(not queue.has("API1A01"), "Placa formatada e compacta foram duplicadas na fila.")
	_check((dashboard.get("vehicle_location_filtered_rows") as Array).size() == 3, "Cliente API perdeu veículo confirmado sem posição ou só com série.")
	_check((view.map_canvas as Control).tracking_locations.size() == 2, "Cliente API alterou incorretamente o conjunto de marcadores.")
	queue.clear()
	dashboard.call("_refresh_vehicle_location_queue_ui")

	dashboard.set("offline_api_rows", client_rows)
	view.query_input.text = "cliente: Cliente inexistente"
	view.query_input.text_changed.emit(view.query_input.text)
	view.add_button.pressed.emit()
	await _wait_query_finished(dashboard)
	_check(queue.is_empty(), "Cliente inexistente criou itens na fila.")

	var calls_before_enter := int(dashboard.get("offline_query_refresh_calls"))
	view.query_input.text = "SN 1003"
	view.query_input.text_changed.emit(view.query_input.text)
	dashboard.set("offline_api_rows", rows.duplicate(true))
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	view.query_input.gui_input.emit(enter)
	await _wait_query_finished(dashboard)
	_check(queue.size() == 1, "Enter não incluiu a série na fila.")
	_check(view.queue_count_label.text == "Fila: 1 aparelho", "Enter encontrou a série, mas deixou o contador da fila em zero.")
	_check(str(dashboard.get("vehicle_location_query_trigger")) == "enter", "Enter não registrou origem sanitizada.")
	_check(int(dashboard.get("offline_query_refresh_calls")) == calls_before_enter + 1, "Enter não executou o mesmo refresh do botão.")
	_check(view.query_state_label.text == "Localização encontrada", "Enter por série não mostrou found.")
	queue.clear()
	dashboard.call("_refresh_vehicle_location_queue_ui")

	view.query_input.text = "ZZZ9Z99"
	view.query_input.text_changed.emit(view.query_input.text)
	dashboard.set("offline_api_rows", rows.duplicate(true))
	view.add_button.pressed.emit()
	await _wait_query_finished(dashboard)
	_check((dashboard.get("vehicle_location_selected") as Dictionary).is_empty(), "Consulta inexistente selecionou o primeiro veículo pelo botão.")
	_check(view.query_state_label.text == "Nenhuma localização encontrada", "Consulta inexistente não mostrou not_found.")
	_check(queue.is_empty(), "Consulta inexistente entrou na fila confirmada.")
	queue.clear()
	dashboard.call("_refresh_vehicle_location_queue_ui")

	view.query_input.text = "TST1A04"
	view.query_input.text_changed.emit(view.query_input.text)
	dashboard.set("offline_api_rows", rows.duplicate(true))
	view.add_button.pressed.emit()
	await _wait_query_finished(dashboard)
	_check((dashboard.get("vehicle_location_filtered_rows") as Array).size() == 1, "Veículo sem posição não permaneceu no resultado.")
	_check((view.map_canvas as Control).tracking_locations.is_empty(), "Veículo sem posição virou marcador no mapa.")
	_check(queue.size() == 1, "Veículo confirmado pela API sem posição não entrou na fila.")
	_check(str((dashboard.get("vehicle_location_filtered_rows") as Array)[0].get("source", "")) == "API Grupo RS", "Origem API Grupo RS não ficou visível no resultado.")
	queue.clear()
	dashboard.call("_refresh_vehicle_location_queue_ui")

	view.query_input.text = ""
	view.add_button.pressed.emit()
	await process_frame
	_check(queue.is_empty(), "Campo vazio adicionou item falso à fila.")
	_check(view.status_label.text.contains("Digite uma placa"), "Campo vazio não mostrou erro orientativo.")
	view.query_input.text = ""

	# Clique e Enter no mesmo gesto não duplicam uma consulta pendente.
	var calls_before_dedup := int(dashboard.get("offline_query_refresh_calls"))
	view.query_input.text = "TST1A01"
	view.query_input.text_changed.emit(view.query_input.text)
	view.add_button.pressed.emit()
	view.query_input.gui_input.emit(enter)
	await _wait_query_finished(dashboard)
	_check(queue.size() == 1, "Clique + Enter duplicaram a fila confirmada.")
	_check(int(dashboard.get("offline_query_refresh_calls")) == calls_before_dedup + 1, "Clique + Enter iniciaram consultas duplicadas.")
	queue.clear()
	dashboard.call("_refresh_vehicle_location_queue_ui")


func _wait_query_finished(dashboard: Node) -> void:
	for _frame in range(30):
		await process_frame
		if not bool(dashboard.get("vehicle_location_refreshing")) \
				and (dashboard.get("vehicle_location_pending_queries") as Array).is_empty():
			return
	_check(false, "Consulta offline não encerrou dentro do limite.")


func _test_sanitized_query_diagnostics(dashboard: Node) -> void:
	var cases: Array[Dictionary] = [
		{"result": {"ok": false, "state": "not_configured", "stage": "auth"}, "category": "not_configured"},
		{"result": {"ok": false, "response_code": 401, "stage": "auth", "relogin_attempted": true}, "category": "unauthorized"},
		{"result": {"ok": false, "response_code": 403, "stage": "equipment"}, "category": "forbidden"},
		{"result": {"ok": true, "response_code": 404, "not_found": true, "rows": []}, "category": "not_found"},
		{"result": {"ok": false, "timeout": true, "stage": "location"}, "category": "timeout"},
		{"result": {"ok": false, "parse_ok": false, "stage": "location_parse"}, "category": "invalid_json"},
		{"result": {"ok": true, "rows": [], "not_found": true}, "category": "not_found"},
	]
	for test_case in cases:
		var diagnostic: Dictionary = dashboard.call(
			"_vehicle_location_sanitized_diagnostic",
			test_case.get("result", {}) as Dictionary,
			7,
			"button",
			1
		)
		_check(str(diagnostic.get("category", "")) == str(test_case.get("category", "")), "Diagnóstico sanitizado classificou uma falha incorretamente.")
		_check(not diagnostic.has("body") and not diagnostic.has("token") and not diagnostic.has("query"), "Diagnóstico sanitizado reteve dado proibido.")
	_check(bool((dashboard.call("_vehicle_location_sanitized_diagnostic", {"ok": false, "response_code": 401, "relogin_attempted": true}, 8, "enter", 1) as Dictionary).get("relogin_attempted", false)), "Relogin único não foi preservado no diagnóstico.")


func _test_erb_query_burst(dashboard: Node) -> void:
	var service := OfflineNationalIndex.new()
	dashboard.set("tracking_national_erb_index", service)
	dashboard.set("tracking_erb_index_mode", "national_partitioned")
	var first_view := {
		"center": {"lat": -5.5264, "lng": -47.4919},
		"zoom": 13,
		"interactive": true,
	}
	dashboard.call_deferred("_refresh_tracking_erb_area", first_view)
	var in_flight_seen := false
	for _frame in range(60):
		await process_frame
		var state: Dictionary = dashboard.call("_tracking_erb_query_state")
		if bool(state.get("in_flight", false)):
			in_flight_seen = true
			break
	_check(in_flight_seen, "Consulta nacional sintética não entrou em voo.")

	var latest_longitude := -47.40
	for index in range(10):
		latest_longitude = -47.48 + float(index) * 0.008
		dashboard.call("_refresh_tracking_erb_area", {
			"center": {"lat": -5.52 + float(index) * 0.002, "lng": latest_longitude},
			"zoom": 13 + (index % 2),
			"interactive": true,
		})
	for _frame in range(240):
		await process_frame
		var state: Dictionary = dashboard.call("_tracking_erb_query_state")
		if not bool(state.get("in_flight", false)) and not bool(state.get("pending", false)) \
				and not bool(dashboard.get("tracking_erb_query_coordinator_running")):
			break
	var final_state: Dictionary = dashboard.call("_tracking_erb_query_state")
	var stations: Array = dashboard.get("tracking_erb_area_stations")
	_check(int(final_state.get("requested", 0)) == 11, "Rajada não contabilizou todas as solicitações.")
	_check(int(final_state.get("actual_queries", 99)) <= 2, "Rajada enfileirou mais de uma consulta em voo e uma pendente.")
	_check(service.call_count() <= 2, "Worker pool executou consultas nacionais obsoletas em sequência.")
	_check(int(final_state.get("coalesced", 0)) >= 10, "Solicitações intermediárias não foram coalescidas.")
	_check(int(final_state.get("stale_discarded", 0)) == 1, "Resultado em voo obsoleto não foi descartado uma única vez.")
	_check(not bool(final_state.get("in_flight", true)) and not bool(final_state.get("pending", true)), "Fila nacional não foi drenada/joinada.")
	_check(int(final_state.get("latest_request_latency_msec", -1)) >= 0, "Latência do pedido mais recente não foi medida.")
	_check(stations.size() == 1, "Somente a última viewport deveria produzir a camada sintética.")
	if stations.size() == 1:
		_check(absf(float((stations[0] as Dictionary).get("lng", 0.0)) - latest_longitude) < 0.000001, "Viewport intermediária foi aplicada no lugar da mais recente.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
