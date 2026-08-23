extends SceneTree


class Smart4GDashboardStub:
	extends "res://src/inventory_dashboard.gd"

	func _ready() -> void:
		pass

	func _load_smart_4g_map_tiles(
		_canvas: Smart4GMapCanvas,
		_devices: Array[Dictionary],
		_region_id: String = "all",
		_view_override: Dictionary = {}
	) -> void:
		# O teste de interface nao deve depender de rede ou de tiles externos.
		pass


var test_failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var monitor_script := load("res://src/smart_4g_monitor.gd")
	var anatel_script := load("res://src/anatel_coverage.gd")
	var store_script := load("res://src/inventory_store.gd")
	if monitor_script == null or anatel_script == null or store_script == null:
		push_error("Scripts do monitor 4G nao carregaram.")
		quit(1)
		return

	var monitor = monitor_script.new()
	var products := [
		{"sku": "024100001", "imei": "024100001", "chip_number": "895501", "operator": "TIM", "model": "RS300 4G", "tracker_status": "Instalado", "plate": "AAA - 1A11", "updated_at": "24/07/2026 20:39"},
		{"sku": "024100002", "imei": "024100002", "chip_number": "895502", "operator": "Claro", "model": "RS300 4G", "tracker_status": "Instalado", "plate": "BBB - 2B22", "updated_at": "24/07/2026 20:30"},
		{"sku": "024100003", "imei": "024100003", "chip_number": "895503", "operator": "Vivo", "model": "RS300 4G", "tracker_status": "Instalado", "plate": "CCC - 3C33", "updated_at": "24/07/2026 19:00"},
	]
	var rows_by_interval := {
		"0 - 1 Hora": [{"client": "CLIENTE A", "plate": "AAA - 1A11", "serial": "024100001", "updated_at": "24/07/2026 20:39"}],
		"1 - 6 Horas": [{"client": "CLIENTE B", "plate": "BBB - 2B22", "serial": "024100002", "updated_at": "24/07/2026 20:20"}],
		"Manutencao": [{"client": "CLIENTE C", "plate": "CCC - 3C33", "serial": "024100003", "updated_at": ""}],
	}
	var server_now := int(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 7, "day": 24, "hour": 20, "minute": 40, "second": 0}))
	var snapshot: Dictionary = monitor.analyze(products, rows_by_interval, {}, {"server_now": server_now, "city": "Imperatriz - MA"})
	_expect(bool(snapshot.get("ok", false)), "Analise 4G nao retornou ok.")
	_expect((snapshot.get("devices", []) as Array).size() == 3, "Analise 4G deveria consolidar tres aparelhos.")
	var operators: Dictionary = snapshot.get("operators", {})
	_expect(int((operators.get("TIM", {}) as Dictionary).get("healthy_percent", 0)) == 100, "TIM deveria estar 100% saudavel.")
	_expect(int((snapshot.get("summary", {}) as Dictionary).get("no_comm", 0)) == 1, "Sem comunicacao nao foi classificado.")
	var history: Dictionary = snapshot.get("history_state", {})
	_expect(((history.get("devices", {}) as Dictionary).get("024100001", []) as Array).size() == 1, "Historico por aparelho nao foi salvo.")

	var live_snapshot: Dictionary = monitor.analyze(products, {
		"0 - 1 Hora": [{
			"client": "CLIENTE A",
			"plate": "AAA - 1A11",
			"serial": "024100001",
			"updated_at": "24/07/2026 20:39:58",
			"data_gps": "24/07/2026 20:39:57",
			"data_servidor": "24/07/2026 20:39:58",
			"latitude": -5.5264,
			"longitude": -47.4919,
			"ignition": true,
			"operator": "Claro",
		}],
	}, {}, {
		"server_now": server_now,
		"city": "Imperatriz - MA",
		"live_only": true,
	})
	var live_devices: Array = live_snapshot.get("devices", [])
	_expect(live_devices.size() == 1, "A leitura ao vivo incluiu aparelhos fora da amostra ligada.")
	var live_device := live_devices[0] as Dictionary
	_expect(bool(live_device.get("location_available", false)), "Coordenada real nao foi liberada para o mapa.")
	_expect(int(live_device.get("estimated_signal_score", 0)) >= 85, "Indice 4G recente ficou abaixo do esperado.")
	_expect(str(live_device.get("operator", "")) == "CLARO", "Operadora confirmada no Grupo RS nao prevaleceu sobre o cadastro local.")
	_expect(str(live_device.get("platform_delay_label", "")) != "--", "Defasagem GPS x servidor nao foi calculada.")
	var live_summary: Dictionary = live_snapshot.get("summary", {})
	_expect(int(live_summary.get("communicating", 0)) == 1, "Resumo nao contou a leitura real.")
	_expect(int(live_summary.get("regional_sample", 0)) == 1, "Resumo nao contou a localizacao real.")
	_expect(int(live_summary.get("average_score", 0)) >= 85, "Resumo nao calculou o indice medio.")

	var anatel = anatel_script.new()
	# O mapa operacional usa o recorte regional, que possui os metadados e as
	# coordenadas necessarias para o painel da tela. O catalogo nacional fica
	# coberto pelo teste dedicado de contrato da Anatel.
	var anatel_loaded: Dictionary = anatel.load_snapshot("res://data/anatel_smp_2g4g_regional.json")
	_expect(bool(anatel_loaded.get("ok", false)), "Base regional da Anatel nao carregou.")
	_expect(int(anatel_loaded.get("stations", 0)) >= 200, "Base regional da Anatel ficou incompleta.")
	var search_catalog := [
		{"id": "imperatriz", "label": "Imperatriz - MA", "lat": -5.5264, "lng": -47.4919, "radius_km": 16.0},
	]
	var area_search: Dictionary = anatel.search_stations(
		{"state": "MA", "city": "Imperatriz", "place": "Centro"},
		search_catalog
	)
	_expect(bool(area_search.get("ok", false)), "Busca textual da Anatel nao retornou ok.")
	_expect(int(area_search.get("station_count", 0)) > 0, "Busca por estado, cidade e bairro nao encontrou ERB.")
	var typed_live_devices: Array[Dictionary] = []
	for value in live_devices:
		typed_live_devices.append((value as Dictionary).duplicate(true))
	var stale_device := typed_live_devices[0].duplicate(true)
	stale_device["serial"] = "024100099"
	stale_device["platform_delay_minutes"] = 31
	stale_device["communication_delay_minutes"] = 31
	typed_live_devices.append(stale_device)
	var regional_profile: Dictionary = anatel.build_region_profile(
		typed_live_devices,
		{"lat": -5.5264, "lng": -47.4919, "radius_km": 16.0},
		"best",
		"CLARO"
	)
	_expect(bool(regional_profile.get("ok", false)), "Perfil hibrido de cobertura nao foi criado.")
	_expect(str(regional_profile.get("generation", "")) == "4G", "Perfil padrao nao selecionou 4G.")
	_expect((regional_profile.get("stations", []) as Array).size() > 0, "Malha regional nao retornou ERBs para o mapa.")
	var regional_summary: Dictionary = regional_profile.get("summary", {})
	_expect(int(regional_summary.get("station_count", 0)) >= 50, "ERBs de Imperatriz nao entraram no perfil.")
	_expect(str(regional_summary.get("best_operator", "")) in ["CLARO", "TIM", "VIVO"], "Melhor operadora nao foi calculada.")
	_expect(regional_summary.has("real_samples"), "Resumo regional nao informou a amostra real.")
	var profile_2g: Dictionary = anatel.build_region_profile(
		typed_live_devices,
		{"lat": -5.5264, "lng": -47.4919, "radius_km": 16.0},
		"best",
		"CLARO",
		"2G"
	)
	_expect(bool(profile_2g.get("ok", false)), "Perfil 2G nao foi criado.")
	_expect(str(profile_2g.get("generation", "")) == "2G", "Perfil 2G nao preservou a geracao selecionada.")
	_expect((profile_2g.get("stations", []) as Array).size() > 0, "Base 2G nao encontrou ERBs regionais.")
	var filtered_2g: Dictionary = anatel.search_stations(
		{"state": "MA", "generation": "2G"},
		search_catalog
	)
	_expect(bool(filtered_2g.get("ok", false)), "Filtro de busca 2G nao retornou ok.")
	_expect(int(filtered_2g.get("station_count", 0)) > 0, "Filtro de busca 2G nao encontrou ERBs.")
	var enriched_devices: Array = anatel.enrich_devices(typed_live_devices)
	_expect(
		not enriched_devices.is_empty()
			and str((enriched_devices[0] as Dictionary).get("recommended_operator", "")) in ["CLARO", "TIM", "VIVO", "SEM RECOMENDACAO"],
		"Recomendacao individual de operadora nao foi calculada."
	)
	var operator_profile: Dictionary = anatel.build_region_profile(
		typed_live_devices,
		{"lat": -5.5264, "lng": -47.4919, "radius_km": 16.0},
		"operator",
		"TIM"
	)
	var operator_cells: Array = operator_profile.get("stations", [])
	var operator_filter_ok := not operator_cells.is_empty()
	for station_value in operator_cells:
		if str((station_value as Dictionary).get("operator", "")) != "TIM":
			operator_filter_ok = false
			break
	_expect(operator_filter_ok, "Modo de analise por operadora nao fixou a TIM.")

	var dashboard := Smart4GDashboardStub.new()
	var store = store_script.new()
	dashboard.smart_4g_area_state_filter = "MA"
	dashboard.smart_4g_area_city_filter = "Imperatriz"
	dashboard.smart_4g_area_place_filter = "Santa Rita"
	var geocode: Dictionary = dashboard.call("_parse_smart_4g_geocode_response", [{
		"lat": "-5.5201",
		"lon": "-47.4892",
		"display_name": "Santa Rita, Imperatriz, Maranhao, Brasil",
		"type": "suburb",
		"address": {"suburb": "Santa Rita", "city": "Imperatriz", "state": "Maranhao"},
		"boundingbox": ["-5.535", "-5.505", "-47.510", "-47.470"],
	}])
	_expect(bool(geocode.get("ok", false)), "Geocodificacao da area nao foi interpretada.")
	_expect(str(geocode.get("area_label", "")).contains("Santa Rita"), "Rotulo do bairro nao foi preservado.")
	_expect(float((geocode.get("center", {}) as Dictionary).get("lat", 0.0)) < -5.5, "Centro geocodificado ficou invalido.")
	_remove_test_files()
	store.configure("user://__codex_smart_4g.json", "__codex_smart_4g.json", "user://__codex_smart_4g_backups", false)
	store.load_db()
	for product in products:
		store.upsert_product(product)
	dashboard.store = store
	dashboard.selected_branch_id = "imperatriz"
	dashboard.selected_branch_name = "IMPERATRIZ"
	dashboard.smart_4g_snapshot = snapshot
	dashboard.smart_4g_anatel = anatel
	dashboard.smart_4g_area_search_active = true
	dashboard.smart_4g_area_state_filter = "MA"
	dashboard.smart_4g_area_city_filter = "Imperatriz"
	dashboard.smart_4g_area_place_filter = "Santa Rita"
	dashboard.smart_4g_area_geocode = geocode
	var area_profile: Dictionary = dashboard.call("_build_smart_4g_anatel_profile", typed_live_devices)
	_expect(bool(area_profile.get("ok", false)), "Perfil da area pesquisada nao foi criado.")
	_expect(str(area_profile.get("area_label", "")).contains("Santa Rita"), "Mapa nao recebeu o rotulo da area pesquisada.")
	_expect((area_profile.get("stations", []) as Array).size() > 0, "Perfil pesquisado nao carregou a cobertura do entorno.")
	_expect(not area_profile.has("search_result"), "Perfil da area ainda esta usando a consulta textual de ERBs.")
	dashboard.smart_4g_area_search_active = true
	dashboard.smart_4g_anatel_profile = area_profile
	var area_view: Dictionary = dashboard.call("_smart_4g_map_view", "area_search", typed_live_devices, Vector2i(720, 330))
	var area_center: Dictionary = area_view.get("center", {})
	_expect(absf(float(area_center.get("lat", 0.0)) - (-5.5201)) < 0.01, "Mapa nao foi centralizado no bairro localizado.")
	_expect(int(area_view.get("zoom", 0)) >= 14, "Mapa nao aproximou o enquadramento da area localizada.")
	dashboard.smart_4g_area_search_active = false
	dashboard.smart_4g_area_geocode = {}
	dashboard.smart_4g_refreshing = true
	dashboard.smart_4g_scan_phase = "scanning"
	dashboard.smart_4g_scan_total = 200
	root.add_child(dashboard)
	_expect(str(dashboard.call("_smart_4g_normalize_operator", "TIM S.A.")) == "TIM", "Alias da TIM nao foi normalizado.")
	_expect(str(dashboard.call("_smart_4g_normalize_operator", "Claro Brasil")) == "CLARO", "Alias da Claro nao foi normalizado.")
	_expect(str(dashboard.call("_smart_4g_normalize_operator", "Telefonica Vivo")) == "VIVO", "Alias da Vivo nao foi normalizado.")
	var view: Control = dashboard.call("_build_smart_4g_monitor_view")
	root.add_child(view)
	await process_frame
	_expect(_has_text_fragment(view, "ERBs no recorte"), "Tela de mapa nao montou os indicadores de cobertura.")
	_expect(_has_text_fragment(view, "Fonte: Catálogo oficial Anatel"), "Tela de mapa nao identificou a fonte cadastral.")
	_expect(_has_text_fragment(view, "Cadastro disponível"), "Tela de mapa nao montou o status cadastral da ERB.")
	_expect(_has_text_fragment(view, "Selecione uma torre"), "Tela de mapa nao montou os detalhes da torre.")
	_expect(_has_text_fragment(view, "Localizar por"), "Tela 4G nao montou o localizador de area.")
	_expect(_has_text_fragment(view, "Região"), "Barra compacta nao montou o filtro regional.")
	_expect(_has_text_fragment(view, "Todas"), "Barra compacta nao montou o filtro de operadora.")
	_expect(_has_text_fragment(view, "4G"), "Filtro 4G nao apareceu.")
	_expect(_has_text_fragment(view, "2G"), "Filtro 2G nao apareceu.")
	_expect(_has_text_fragment(view, "Copiar coordenadas"), "Painel da ERB nao montou a acao de copiar coordenadas.")
	_expect(_has_text_fragment(view, "Bairro, rua ou regiao"), "Tela 4G nao montou o campo de bairro e rua.")
	_expect(not _has_text_fragment(view, "Qualidade geral"), "Painel lateral antigo ainda polui o mapa.")
	dashboard.call("_show_smart_4g_station_details", {
		"id": "IM-044",
		"operator": "TIM",
		"generation": "4G LTE",
		"address": "Rua Simplicio Moreira, 1185",
		"bands": ["B1 (2100 MHz)", "B3 (1800 MHz)"],
		"lat": -5.523367,
		"lng": -47.474042,
	})
	await process_frame
	_expect(_has_text_fragment(view, "ERB IM-044"), "Detalhes selecionados nao atualizaram o titulo da ERB.")
	_expect(_has_text_fragment(view, "Cadastro disponível"), "Detalhes selecionados nao mostraram a disponibilidade cadastral.")
	_expect(_has_text_fragment(view, "Faixas cadastradas"), "Detalhes selecionados nao mostraram as faixas.")
	_expect(dashboard.smart_4g_map_canvas != null, "Canvas do mapa nao foi criado.")
	if dashboard.smart_4g_map_canvas != null:
		var first_load_generation := int(dashboard.smart_4g_map_canvas.begin_map_load("Preparando teste"))
		var second_load_generation := int(dashboard.smart_4g_map_canvas.begin_map_load("Atualizando teste"))
		_expect(
			not dashboard.smart_4g_map_canvas.is_load_current(first_load_generation)
				and dashboard.smart_4g_map_canvas.is_load_current(second_load_generation),
			"Carregamento antigo do mapa nao foi invalidado."
		)
		_expect(
			not bool(dashboard.smart_4g_map_canvas.get("map_ready"))
				and str(dashboard.smart_4g_map_canvas.get("loading_stage")) == "Atualizando teste",
			"Animacao nao protege o mapa durante a atualizacao."
		)
	var navigation_canvas = dashboard.Smart4GMapCanvas.new()
	navigation_canvas.size = Vector2(720, 330)
	root.add_child(navigation_canvas)
	var navigation_events: Array[Dictionary] = []
	navigation_canvas.navigation_requested.connect(func(latitude: float, longitude: float, zoom: int):
		navigation_events.append({"lat": latitude, "lng": longitude, "zoom": zoom})
	)
	var navigation_image := Image.create(720, 330, false, Image.FORMAT_RGBA8)
	navigation_image.fill(Color("#edf3f8"))
	navigation_canvas.set_map_texture(
		ImageTexture.create_from_image(navigation_image),
		13,
		Vector2(301511, 268528),
		Vector2(720, 330)
	)
	navigation_canvas.call("_request_zoom", Vector2(360, 165), 1)
	_expect(
		navigation_events.size() == 1
			and int(navigation_events[0].get("zoom", 0)) == 14
			and bool(navigation_canvas.get("navigation_loading")),
		"Zoom do mapa nao solicitou uma nova area preservando a navegacao."
	)
	navigation_canvas.cancel_navigation_load()
	navigation_canvas.set("drag_offset", Vector2(120, 0))
	navigation_canvas.call("_request_pan_navigation")
	_expect(
		navigation_events.size() == 2
			and int(navigation_events[1].get("zoom", 0)) == 13,
		"Arraste do mapa nao solicitou a recomposicao regional."
	)
	navigation_canvas.free()
	var marker_canvas = dashboard.Smart4GMapCanvas.new()
	marker_canvas.size = Vector2(720, 420)
	root.add_child(marker_canvas)
	var marker_image := Image.create(720, 420, false, Image.FORMAT_RGBA8)
	marker_image.fill(Color("#edf3f8"))
	var marker_center := marker_canvas.call("_lat_lng_to_world_pixel", -5.5264, -47.4919, 13) as Vector2
	marker_canvas.set_map_texture(
		ImageTexture.create_from_image(marker_image),
		13,
		marker_center - Vector2(360, 210),
		Vector2(720, 420)
	)
	marker_canvas.set_coverage_profile({
		"generation": "4G",
		"stations": [
			{"id": "marker-a", "operator": "TIM", "generation": "4G", "lat": -5.5264, "lng": -47.4919},
			{"id": "marker-b", "operator": "TIM", "generation": "4G", "lat": -5.5270, "lng": -47.4924},
			{"id": "marker-c", "operator": "CLARO", "generation": "4G", "lat": -5.5268, "lng": -47.4915},
		],
	})
	_expect((marker_canvas.get("stations") as Array).size() == 3, "Marcadores individuais nao foram carregados no mapa.")
	marker_canvas.select_station_by_id("marker-b")
	_expect(int(marker_canvas.get("selected_station_index")) == 1, "Selecao de ERB individual nao foi preservada.")
	marker_canvas.free()
	dashboard.smart_4g_scan_completed = 37
	dashboard.call("_update_smart_4g_status_labels")
	_expect(
		dashboard.smart_4g_refresh_button != null
			and dashboard.smart_4g_refresh_button.disabled
			and dashboard.smart_4g_refresh_button.text == "Atualizando...",
		"Botao de atualizar nao informa o carregamento em andamento."
	)

	await create_timer(1.0).timeout
	view.free()
	dashboard.free()
	_remove_test_files()
	if test_failed:
		quit(1)
		return
	print("SMART_4G_MONITOR_CHECK_OK")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	test_failed = true
	push_error(message)


func _has_text_fragment(node: Node, value: String) -> bool:
	if node is Label and str((node as Label).text).contains(value):
		return true
	if node is Button and str((node as Button).text).contains(value):
		return true
	if node is LineEdit and str((node as LineEdit).placeholder_text).contains(value):
		return true
	if node is OptionButton:
		var option := node as OptionButton
		for index in range(option.item_count):
			if option.get_item_text(index).contains(value):
				return true
	for child in node.get_children():
		if _has_text_fragment(child, value):
			return true
	return false


func _remove_test_files() -> void:
	var path := ProjectSettings.globalize_path("user://__codex_smart_4g.json")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")
	DirAccess.remove_absolute(path + ".tmp")
