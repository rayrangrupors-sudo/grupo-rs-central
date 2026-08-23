class_name Smart4GMonitor
extends RefCounted

const STATUS_NORMAL := "normal"
const STATUS_ATTENTION := "attention"
const STATUS_UNSTABLE := "unstable"
const STATUS_CRITICAL := "critical"
const STATUS_NO_COMM := "no_comm"
const HISTORY_LIMIT_PER_DEVICE := 96
const IMPERATRIZ_LAT := -5.5264
const IMPERATRIZ_LNG := -47.4919


func analyze(products: Array, rows_by_interval: Dictionary, history_state: Dictionary = {}, settings: Dictionary = {}) -> Dictionary:
	var server_now := int(settings.get("server_now", _local_now_to_unix_like()))
	var city := str(settings.get("city", "Imperatriz - MA")).strip_edges()
	var devices := _build_devices(
		products,
		rows_by_interval,
		server_now,
		not bool(settings.get("live_only", false))
	)
	var next_history := _append_history(history_state, devices, server_now)
	_apply_history_patterns(devices, next_history)
	var operator_cards := _build_operator_cards(devices)
	var summary := _build_summary(devices)
	var ai_summary := _build_ai_summary(devices, operator_cards, city)
	return {
		"ok": true,
		"city": city,
		"devices": devices,
		"operators": operator_cards,
		"summary": summary,
		"ai_summary": ai_summary,
		"history_state": next_history,
		"updated_at": Time.get_datetime_string_from_system(),
		"updated_time": Time.get_time_string_from_system().substr(0, 5),
	}


func _build_devices(
	products: Array,
	rows_by_interval: Dictionary,
	server_now: int,
	include_catalog_devices: bool = true
) -> Array[Dictionary]:
	var product_index := _index_products(products)
	var devices: Array[Dictionary] = []
	var seen := {}

	for interval_name in rows_by_interval.keys():
		var interval_rows: Variant = rows_by_interval.get(interval_name)
		if typeof(interval_rows) != TYPE_ARRAY:
			continue
		for row_value in interval_rows:
			if typeof(row_value) != TYPE_DICTIONARY:
				continue
			var row := row_value as Dictionary
			var serial := _digits_only(_first_text(row, ["serial", "imei", "equipment", "equipamento"]))
			var plate := _first_text(row, ["plate", "placa"]).to_upper()
			if serial == "" and plate == "":
				continue
			var product := _lookup_product(product_index, serial, plate)
			var device := _device_from_sources(product, row, str(interval_name), server_now, true, devices.size())
			var key := str(device.get("serial", ""))
			if key == "":
				key = str(device.get("plate", ""))
			if key == "":
				continue
			seen[key] = true
			devices.append(device)

	if include_catalog_devices:
		for product_value in products:
			if typeof(product_value) != TYPE_DICTIONARY:
				continue
			var product := product_value as Dictionary
			if not _is_4g_candidate(product):
				continue
			var serial := _digits_only(_first_text(product, ["imei", "sku", "equipment_number", "numero_serie"]))
			var plate := _first_text(product, ["plate", "placa"]).to_upper()
			var key := serial if serial != "" else plate
			if key == "" or seen.has(key):
				continue
			var device := _device_from_sources(product, {}, "", server_now, false, devices.size())
			seen[key] = true
			devices.append(device)

	devices.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_rank := _status_rank(str(left.get("status", STATUS_NORMAL)))
		var right_rank := _status_rank(str(right.get("status", STATUS_NORMAL)))
		if left_rank != right_rank:
			return left_rank > right_rank
		return int(left.get("delay_minutes", 0)) > int(right.get("delay_minutes", 0))
	)
	return devices


func _index_products(products: Array) -> Dictionary:
	var by_serial := {}
	var by_plate := {}
	for product_value in products:
		if typeof(product_value) != TYPE_DICTIONARY:
			continue
		var product := product_value as Dictionary
		var serial := _digits_only(_first_text(product, ["imei", "sku", "equipment_number", "numero_serie"]))
		var plate := _search_key(_first_text(product, ["plate", "placa"]))
		if serial != "":
			by_serial[serial] = product
		if plate != "":
			by_plate[plate] = product
	return {"serial": by_serial, "plate": by_plate}


func _lookup_product(index: Dictionary, serial: String, plate: String) -> Dictionary:
	var by_serial: Dictionary = index.get("serial", {})
	if serial != "" and by_serial.has(serial):
		return (by_serial.get(serial) as Dictionary).duplicate(true)
	var by_plate: Dictionary = index.get("plate", {})
	var plate_key := _search_key(plate)
	if plate_key != "" and by_plate.has(plate_key):
		return (by_plate.get(plate_key) as Dictionary).duplicate(true)
	return {}


func _device_from_sources(product: Dictionary, live_row: Dictionary, interval_name: String, server_now: int, live: bool, index: int) -> Dictionary:
	var serial := _digits_only(_first_text(live_row, ["serial", "imei", "equipment", "equipamento"]))
	if serial == "":
		serial = _digits_only(_first_text(product, ["imei", "sku", "equipment_number", "numero_serie"]))
	var plate := _first_text(live_row, ["plate", "placa"]).to_upper()
	if plate == "":
		plate = _first_text(product, ["plate", "placa"]).to_upper()
	var iccid := _first_text(product, ["chip_number", "iccid", "chip", "sku"])
	var operator_name := _normalize_operator(_first_text(live_row, ["operator", "operadora"]))
	if operator_name == "NAO IDENTIFICADA":
		operator_name = _normalize_operator(_first_text(product, ["operator", "operadora"]))
	var model := _first_text(product, ["model", "category", "tipo"])
	var client := _first_text(live_row, ["client", "cliente"])
	if client == "":
		client = _first_text(product, ["client", "cliente", "name"])
	var gps_at := _first_text(live_row, ["data_gps", "gps_at", "data", "data_completa"])
	var server_at := _first_text(live_row, [
		"data_servidor",
		"server_at",
		"data_comunicacao",
		"DataComunicacao",
	])
	var last_comm := server_at
	if last_comm == "":
		last_comm = _first_text(live_row, ["updated_at", "ultima_comunicacao", "last_communication_at"])
	if last_comm == "":
		last_comm = _first_text(product, [
			"last_communication_at",
			"ultima_comunicacao",
			"last_position_at",
			"last_movement_at",
			"updated_at",
			"created_at",
		])
	var tracker_at := gps_at if gps_at != "" else last_comm
	var platform_delay := _delay_minutes(tracker_at, server_now)
	if platform_delay < 0 and live:
		platform_delay = _interval_default_delay(interval_name)
	var communication_delay := _delay_minutes(last_comm, server_now)
	var ignition := _ignition_is_on(_first_variant(live_row, product, ["ignition", "ignicao", "ligado"]))
	var status := _classify_monitor_delay(platform_delay, tracker_at, interval_name) \
		if live else _classify_delay(communication_delay, ignition, last_comm, interval_name)
	var coordinates := _coordinates_for(product, live_row, index)
	var location_available := bool(coordinates.get("available", false))
	var region := _region_for(coordinates) if location_available else "sem localizacao"
	var last_parts := _split_datetime_label(last_comm)
	var signal_score := _estimated_signal_score(platform_delay) if live else 0
	return {
		"serial": serial,
		"iccid": iccid,
		"plate": plate,
		"client": client,
		"operator": operator_name,
		"model": model,
		"network": "4G",
		"last_communication": last_comm,
		"last_date": str(last_parts.get("date", "")),
		"last_time": str(last_parts.get("time", "")),
		"delay_minutes": platform_delay,
		"delay_label": _format_delay(platform_delay),
		"communication_delay_minutes": communication_delay,
		"data_gps": gps_at,
		"data_servidor": server_at,
		"platform_delay_minutes": platform_delay,
		"platform_delay_label": _format_delay(platform_delay),
		"estimated_signal_score": signal_score,
		"signal_label": _signal_label(status),
		"signal_confidence": _signal_confidence(live, gps_at, server_at, location_available),
		"ignition": ignition,
		"ignition_label": "Ligado" if ignition else "Desligado",
		"status": status,
		"status_label": _status_label(status),
		"status_color": _status_color_hex(status),
		"interval": interval_name,
		"latitude": float(coordinates.get("lat", IMPERATRIZ_LAT)),
		"longitude": float(coordinates.get("lng", IMPERATRIZ_LNG)),
		"location_available": location_available,
		"region": region,
		"source": "Grupo RS" if live else "Cadastro",
	}


func _append_history(history_state: Dictionary, devices: Array[Dictionary], server_now: int) -> Dictionary:
	var result := history_state.duplicate(true)
	var devices_history: Dictionary = result.get("devices", {})
	for device in devices:
		var serial := str(device.get("serial", "")).strip_edges()
		if serial == "":
			continue
		var entries: Array = devices_history.get(serial, [])
		entries.append({
			"server_at": Time.get_datetime_string_from_unix_time(server_now),
			"last_communication": str(device.get("last_communication", "")),
			"delay_minutes": int(device.get("delay_minutes", 0)),
			"platform_delay_minutes": int(device.get("platform_delay_minutes", -1)),
			"estimated_signal_score": int(device.get("estimated_signal_score", 0)),
			"operator": str(device.get("operator", "")),
			"latitude": float(device.get("latitude", 0.0)),
			"longitude": float(device.get("longitude", 0.0)),
			"ignition": bool(device.get("ignition", false)),
			"status": str(device.get("status", "")),
		})
		while entries.size() > HISTORY_LIMIT_PER_DEVICE:
			entries.pop_front()
		devices_history[serial] = entries
	result["devices"] = devices_history
	result["updated_at"] = Time.get_datetime_string_from_system()
	return result


func _apply_history_patterns(devices: Array[Dictionary], history_state: Dictionary) -> void:
	var operator_totals := {}
	var operator_affected := {}
	for device in devices:
		var operator_name := str(device.get("operator", "NAO IDENTIFICADA"))
		operator_totals[operator_name] = int(operator_totals.get(operator_name, 0)) + 1
		if _is_affected(str(device.get("status", STATUS_NORMAL))):
			operator_affected[operator_name] = int(operator_affected.get(operator_name, 0)) + 1

	var histories: Dictionary = history_state.get("devices", {})
	for device in devices:
		var serial := str(device.get("serial", ""))
		var operator_name := str(device.get("operator", "NAO IDENTIFICADA"))
		var affected_total := int(operator_affected.get(operator_name, 0))
		var operator_total := maxi(int(operator_totals.get(operator_name, 0)), 1)
		var affected_ratio := float(affected_total) / float(operator_total)
		var status := str(device.get("status", STATUS_NORMAL))
		var entries: Array = histories.get(serial, [])
		var recurrent := _recent_affected_count(entries) >= 3
		var pattern := "Normal"
		if _is_affected(status) and affected_total >= 3 and affected_ratio >= 0.35:
			pattern = "Provavel instabilidade regional da operadora"
		elif _is_affected(status) and affected_ratio < 0.20 and operator_total >= 4:
			pattern = "Possivel defeito individual"
		elif recurrent:
			pattern = "Atraso recorrente"
		elif _is_affected(status):
			pattern = "Acompanhar"
		device["pattern"] = pattern
		device["history_points"] = entries.size()
		device["recurrent"] = recurrent


func _build_operator_cards(devices: Array[Dictionary]) -> Dictionary:
	var result := {}
	for operator_name in ["TIM", "CLARO", "VIVO", "NAO IDENTIFICADA"]:
		result[operator_name] = {
			"name": operator_name,
			"total": 0,
			"normal": 0,
			"delayed": 0,
			"healthy_percent": 0,
			"average_score": 0,
			"quality": "Sem dados",
			"status": STATUS_NO_COMM,
			"score_total": 0,
			"score_samples": 0,
		}
	for device in devices:
		var operator_name := str(device.get("operator", "NAO IDENTIFICADA"))
		if not result.has(operator_name):
			operator_name = "NAO IDENTIFICADA"
		var card: Dictionary = result.get(operator_name, {})
		card["total"] = int(card.get("total", 0)) + 1
		if str(device.get("status", STATUS_NORMAL)) == STATUS_NORMAL:
			card["normal"] = int(card.get("normal", 0)) + 1
		else:
			card["delayed"] = int(card.get("delayed", 0)) + 1
		var score := int(device.get("estimated_signal_score", 0))
		if score > 0:
			card["score_total"] = int(card.get("score_total", 0)) + score
			card["score_samples"] = int(card.get("score_samples", 0)) + 1
		result[operator_name] = card
	for operator_name in result.keys():
		var card: Dictionary = result.get(operator_name)
		var total := int(card.get("total", 0))
		var normal := int(card.get("normal", 0))
		var healthy := int(round((float(normal) / float(maxi(total, 1))) * 100.0)) if total > 0 else 0
		var score_samples := int(card.get("score_samples", 0))
		var average_score := roundi(
			float(card.get("score_total", 0)) / float(maxi(score_samples, 1))
		) if score_samples > 0 else 0
		card["healthy_percent"] = healthy
		card["average_score"] = average_score
		card["quality"] = _score_quality_label(average_score, score_samples)
		card["status"] = _score_quality_status(average_score, score_samples)
		card.erase("score_total")
		card.erase("score_samples")
		result[operator_name] = card
	return result


func _build_summary(devices: Array[Dictionary]) -> Dictionary:
	var counts := {
		STATUS_NORMAL: 0,
		STATUS_ATTENTION: 0,
		STATUS_UNSTABLE: 0,
		STATUS_CRITICAL: 0,
		STATUS_NO_COMM: 0,
	}
	for device in devices:
		var status := str(device.get("status", STATUS_NORMAL))
		counts[status] = int(counts.get(status, 0)) + 1
	var score_total := 0
	var score_samples := 0
	var regional_sample := 0
	for device in devices:
		var score := int(device.get("estimated_signal_score", 0))
		if score > 0:
			score_total += score
			score_samples += 1
		if bool(device.get("location_available", false)):
			regional_sample += 1
	var average_score := roundi(float(score_total) / float(maxi(score_samples, 1))) \
		if score_samples > 0 else 0
	return {
		"total": devices.size(),
		"communicating": score_samples,
		"average_score": average_score,
		"average_label": _score_quality_label(average_score, score_samples),
		"regional_sample": regional_sample,
		"regional_coverage_percent": roundi(
			float(regional_sample) * 100.0 / float(maxi(score_samples, 1))
		) if score_samples > 0 else 0,
		"normal": int(counts.get(STATUS_NORMAL, 0)),
		"attention": int(counts.get(STATUS_ATTENTION, 0)),
		"unstable": int(counts.get(STATUS_UNSTABLE, 0)),
		"critical": int(counts.get(STATUS_CRITICAL, 0)),
		"no_comm": int(counts.get(STATUS_NO_COMM, 0)),
		"counts": counts,
	}


func _build_ai_summary(devices: Array[Dictionary], operator_cards: Dictionary, city: String) -> String:
	if devices.is_empty():
		return "Ainda nao ha aparelhos 4G suficientes para gerar analise."
	var affected_by_operator := {}
	var affected_by_region := {}
	var isolated := 0
	for device in devices:
		var status := str(device.get("status", STATUS_NORMAL))
		if not _is_affected(status):
			continue
		var operator_name := str(device.get("operator", "NAO IDENTIFICADA"))
		var region := str(device.get("region", "centro"))
		affected_by_operator[operator_name] = int(affected_by_operator.get(operator_name, 0)) + 1
		affected_by_region[region] = int(affected_by_region.get(region, 0)) + 1
		if str(device.get("pattern", "")).contains("individual"):
			isolated += 1
	var top_operator := _top_key(affected_by_operator)
	var top_region := _top_key(affected_by_region)
	if top_operator == "":
		return "A comunicacao 4G em %s esta majoritariamente normal. Nenhum agrupamento critico foi detectado nesta leitura." % city
	var card: Dictionary = operator_cards.get(top_operator, {})
	var quality := str(card.get("quality", "Atencao"))
	var affected := int(affected_by_operator.get(top_operator, 0))
	var message := "Foram detectados %d aparelho(s) da operadora %s com atraso acima do padrao em %s." % [affected, top_operator, city]
	if top_region != "":
		message += " A maior concentracao aparece na regiao %s." % top_region
	message += " O status geral da operadora esta como %s." % quality
	if isolated > 0:
		message += " Tambem ha %d caso(s) com perfil de possivel defeito individual." % isolated
	return message


func _split_datetime_label(value: String) -> Dictionary:
	var text := value.strip_edges().replace("T", " ")
	if text == "":
		return {"date": "--", "time": "--"}
	var parts := text.split(" ", false)
	if parts.size() <= 0:
		return {"date": "--", "time": "--"}
	var date_text := str(parts[0]).strip_edges()
	var time_text := "--"
	if parts.size() > 1:
		time_text = str(parts[1]).strip_edges()
		if time_text.length() >= 5:
			time_text = time_text.substr(0, 5)
	return {"date": date_text if date_text != "" else "--", "time": time_text}


func _is_4g_candidate(product: Dictionary) -> bool:
	var text := "%s %s %s %s %s" % [
		_first_text(product, ["model", "modelo", "tipo"]),
		_first_text(product, ["category"]),
		_first_text(product, ["notes"]),
		_first_text(product, ["apn"]),
		_first_text(product, ["name"]),
	]
	var key := _search_key(text)
	if key.contains("4g") or key.contains("rs300") or key.contains("st300") or key.contains("lte"):
		return true
	var status_key := _search_key(_first_text(product, ["tracker_status", "status"]))
	return status_key == "instalado"


func _classify_delay(delay_minutes: int, ignition: bool, last_comm: String, interval_name: String) -> String:
	if last_comm.strip_edges() == "" or interval_name == "Manutencao":
		return STATUS_NO_COMM
	if delay_minutes < 0:
		return STATUS_NO_COMM
	if ignition:
		if delay_minutes <= 5:
			return STATUS_NORMAL
		if delay_minutes <= 15:
			return STATUS_ATTENTION
		if delay_minutes <= 30:
			return STATUS_UNSTABLE
		return STATUS_CRITICAL
	if delay_minutes <= 15:
		return STATUS_NORMAL
	if delay_minutes <= 60:
		return STATUS_ATTENTION
	if delay_minutes <= 180:
		return STATUS_UNSTABLE
	if delay_minutes > 720:
		return STATUS_NO_COMM
	return STATUS_CRITICAL


func _classify_monitor_delay(delay_minutes: int, tracker_at: String, interval_name: String) -> String:
	if tracker_at.strip_edges() == "" or interval_name == "Manutencao" or delay_minutes < 0:
		return STATUS_NO_COMM
	if delay_minutes <= 5:
		return STATUS_NORMAL
	if delay_minutes <= 15:
		return STATUS_ATTENTION
	if delay_minutes <= 20:
		return STATUS_UNSTABLE
	return STATUS_CRITICAL


func _estimated_signal_score(delay_minutes: int) -> int:
	if delay_minutes < 0:
		return 0
	if delay_minutes <= 5:
		return clampi(100 - delay_minutes * 3, 85, 100)
	if delay_minutes <= 15:
		return clampi(85 - (delay_minutes - 5) * 2, 65, 85)
	if delay_minutes <= 20:
		return clampi(65 - (delay_minutes - 15) * 4, 45, 65)
	return clampi(45 - (delay_minutes - 20), 1, 44)


func _signal_label(status: String) -> String:
	match status:
		STATUS_NORMAL:
			return "Excelente"
		STATUS_ATTENTION:
			return "Boa"
		STATUS_UNSTABLE:
			return "Atencao"
		STATUS_CRITICAL:
			return "Possivel problema"
	return "Sem leitura"


func _signal_confidence(
	live: bool,
	gps_at: String,
	server_at: String,
	location_available: bool
) -> String:
	if not live:
		return "Sem leitura"
	if gps_at != "" and server_at != "" and location_available:
		return "Alta"
	if gps_at != "" or server_at != "":
		return "Media"
	return "Baixa"


func _delay_minutes(datetime_text: String, server_now: int) -> int:
	var unix_time := _unix_from_datetime(datetime_text, server_now)
	if unix_time <= 0:
		return -1
	return maxi(0, int(round(float(server_now - unix_time) / 60.0)))


func _unix_from_datetime(value: String, server_now: int) -> int:
	var text := value.strip_edges()
	if text == "":
		return -1
	var lowered := text.to_lower()
	if lowered == "agora" or lowered == "online":
		return server_now
	if text.contains("/"):
		var br_regex := RegEx.new()
		if br_regex.compile("^(\\d{1,2})/(\\d{1,2})/(\\d{2,4})\\s+(\\d{1,2}):(\\d{2})(?::(\\d{2}))?") != OK:
			return -1
		var br_match := br_regex.search(text)
		if br_match == null:
			return -1
		var year := int(br_match.get_string(3))
		if year < 100:
			year += 2000
		return int(Time.get_unix_time_from_datetime_dict({
			"year": year,
			"month": int(br_match.get_string(2)),
			"day": int(br_match.get_string(1)),
			"hour": int(br_match.get_string(4)),
			"minute": int(br_match.get_string(5)),
			"second": int(br_match.get_string(6)) if br_match.get_string(6) != "" else 0,
		}))
	if text.contains("-"):
		var iso := text.replace(" ", "T")
		var unix_time := int(Time.get_unix_time_from_datetime_string(iso))
		if unix_time > 0:
			return unix_time
	return -1


func _local_now_to_unix_like() -> int:
	return int(Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system()))


func _interval_default_delay(interval_name: String) -> int:
	match interval_name:
		"0 - 1 Hora":
			return 4
		"1 - 6 Horas":
			return 90
		"6 - 24 Horas":
			return 480
		"24 - 72 Horas":
			return 1800
		"Manutencao":
			return 4320
	return 0


func _coordinates_for(product: Dictionary, live_row: Dictionary, index: int) -> Dictionary:
	var lat_text := _first_text(live_row, ["lat", "latitude"])
	if lat_text == "":
		lat_text = _first_text(product, ["lat", "latitude"])
	var lng_text := _first_text(live_row, ["lng", "lon", "longitude"])
	if lng_text == "":
		lng_text = _first_text(product, ["lng", "lon", "longitude"])
	if lat_text.is_valid_float() and lng_text.is_valid_float():
		var latitude := float(lat_text)
		var longitude := float(lng_text)
		var valid := is_finite(latitude) \
			and is_finite(longitude) \
			and latitude >= -90.0 \
			and latitude <= 90.0 \
			and longitude >= -180.0 \
			and longitude <= 180.0 \
			and not (is_zero_approx(latitude) and is_zero_approx(longitude))
		if valid:
			return {"lat": latitude, "lng": longitude, "available": true}
	return {"lat": 0.0, "lng": 0.0, "available": false}


func _region_for(coordinates: Dictionary) -> String:
	var lat := float(coordinates.get("lat", IMPERATRIZ_LAT))
	var lng := float(coordinates.get("lng", IMPERATRIZ_LNG))
	if lat > IMPERATRIZ_LAT + 0.006:
		return "norte"
	if lat < IMPERATRIZ_LAT - 0.006:
		return "sul"
	if lng > IMPERATRIZ_LNG + 0.006:
		return "leste"
	if lng < IMPERATRIZ_LNG - 0.006:
		return "oeste"
	return "central"


func _normalize_operator(value: String) -> String:
	var key := _search_key(value)
	if key.contains("tim"):
		return "TIM"
	if key.contains("claro"):
		return "CLARO"
	if key.contains("vivo"):
		return "VIVO"
	if key.contains("telefonica"):
		return "VIVO"
	return "NAO IDENTIFICADA"


func _quality_label(healthy_percent: int, total: int) -> String:
	if total <= 0:
		return "Sem dados"
	if healthy_percent >= 75:
		return "Bom"
	if healthy_percent >= 55:
		return "Atencao"
	if healthy_percent >= 35:
		return "Instavel"
	return "Critico"


func _quality_status(healthy_percent: int, total: int) -> String:
	if total <= 0:
		return STATUS_NO_COMM
	if healthy_percent >= 75:
		return STATUS_NORMAL
	if healthy_percent >= 55:
		return STATUS_ATTENTION
	if healthy_percent >= 35:
		return STATUS_UNSTABLE
	return STATUS_CRITICAL


func _score_quality_label(average_score: int, samples: int) -> String:
	if samples <= 0:
		return "Sem dados"
	if average_score >= 85:
		return "Excelente"
	if average_score >= 65:
		return "Boa"
	if average_score >= 45:
		return "Atencao"
	return "Possivel problema"


func _score_quality_status(average_score: int, samples: int) -> String:
	if samples <= 0:
		return STATUS_NO_COMM
	if average_score >= 85:
		return STATUS_NORMAL
	if average_score >= 65:
		return STATUS_ATTENTION
	if average_score >= 45:
		return STATUS_UNSTABLE
	return STATUS_CRITICAL


func _status_label(status: String) -> String:
	match status:
		STATUS_NORMAL:
			return "Normal"
		STATUS_ATTENTION:
			return "Atencao"
		STATUS_UNSTABLE:
			return "Instavel"
		STATUS_CRITICAL:
			return "Critico"
		STATUS_NO_COMM:
			return "Sem Com."
	return "Normal"


func _status_color_hex(status: String) -> String:
	match status:
		STATUS_NORMAL:
			return "#43c751"
		STATUS_ATTENTION:
			return "#ffd21f"
		STATUS_UNSTABLE:
			return "#ff8315"
		STATUS_CRITICAL:
			return "#ff382c"
		STATUS_NO_COMM:
			return "#8d98a6"
	return "#43c751"


func _status_rank(status: String) -> int:
	match status:
		STATUS_NO_COMM:
			return 5
		STATUS_CRITICAL:
			return 4
		STATUS_UNSTABLE:
			return 3
		STATUS_ATTENTION:
			return 2
	return 1


func _is_affected(status: String) -> bool:
	return status in [STATUS_ATTENTION, STATUS_UNSTABLE, STATUS_CRITICAL, STATUS_NO_COMM]


func _recent_affected_count(entries: Array) -> int:
	var count := 0
	var start := maxi(entries.size() - 6, 0)
	for index in range(start, entries.size()):
		var entry: Variant = entries[index]
		if typeof(entry) == TYPE_DICTIONARY and _is_affected(str((entry as Dictionary).get("status", ""))):
			count += 1
	return count


func _format_delay(delay_minutes: int) -> String:
	if delay_minutes < 0:
		return "--"
	if delay_minutes < 60:
		return "%d min" % delay_minutes
	var hours := int(floor(float(delay_minutes) / 60.0))
	var minutes := delay_minutes % 60
	if hours < 24:
		return "%d h %02d min" % [hours, minutes]
	var days := int(floor(float(hours) / 24.0))
	return "%d d %d h" % [days, hours % 24]


func _top_key(values: Dictionary) -> String:
	var best_key := ""
	var best_value := -1
	for key in values.keys():
		var amount := int(values.get(key, 0))
		if amount > best_value:
			best_value = amount
			best_key = str(key)
	return best_key


func _first_text(source: Dictionary, keys: Array) -> String:
	for key_value in keys:
		var text := str(source.get(str(key_value), "")).strip_edges()
		if text != "":
			return text
	return ""


func _first_variant(primary: Dictionary, secondary: Dictionary, keys: Array) -> Variant:
	for key_value in keys:
		var key := str(key_value)
		if primary.has(key):
			return primary.get(key)
		if secondary.has(key):
			return secondary.get(key)
	return false


func _ignition_is_on(value: Variant) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return bool(value)
		TYPE_INT:
			return int(value) > 0
		TYPE_FLOAT:
			return float(value) > 0.0
	var text := str(value).strip_edges().to_lower()
	if text == "":
		return false
	if text.contains("deslig") or text in ["0", "false", "off", "nao", "no"]:
		return false
	if text.contains("ligad") or text in ["1", "true", "on", "sim", "yes"]:
		return true
	if text.is_valid_float():
		return float(text) > 0.0
	return false


func _digits_only(value: String) -> String:
	var result := ""
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if character >= "0" and character <= "9":
			result += character
	return result


func _search_key(value: String) -> String:
	return value.strip_edges().to_lower() \
		.replace(" ", "") \
		.replace("/", "") \
		.replace("-", "") \
		.replace("_", "") \
		.replace(".", "") \
		.replace(":", "") \
		.replace("(", "") \
		.replace(")", "") \
		.replace("\n", "") \
		.replace("\t", "") \
		.replace("á", "a") \
		.replace("à", "a") \
		.replace("ã", "a") \
		.replace("â", "a") \
		.replace("é", "e") \
		.replace("ê", "e") \
		.replace("í", "i") \
		.replace("ó", "o") \
		.replace("õ", "o") \
		.replace("ô", "o") \
		.replace("ú", "u") \
		.replace("ç", "c")
