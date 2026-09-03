## Web supplies membership and missing identity fields; API confirms association.
## Two workers maximum; no polling, history, chip lookup or commands here.
extends RefCounted

signal changed
var host: Node
var running := false
var generation := 0
var total := 0
var processed := 0
var failures := 0
var message := ""
var rows: Array[Dictionary] = []
var _busy := false
var _workers := 0
var _queue: Array[Dictionary] = []
var _deadline := 0
var _network_errors := 0
var _operator_catalog: Dictionary = {}
const Bulk := preload("res://src/features/big_map/maintenance_bulk.gd")
var _catalogs := {}
var request_count := 0
const Snapshot := preload("res://src/features/big_map/maintenance_snapshot.gd")
const WebLocation := preload("res://src/features/big_map/maintenance_web_location.gd")


func cancel() -> void:
	generation += 1
	running = false
	message = "Busca cancelada; resultados recebidos preservados."
	changed.emit()


func current(ticket: int) -> bool:
	return running and ticket == generation and is_instance_valid(host) and Time.get_ticks_msec() < _deadline


func start(owner: Node) -> void:
	if _busy:
		return
	host = owner
	_busy = true
	running = true
	generation += 1
	var ticket := generation
	_deadline = Time.get_ticks_msec() + 900000
	rows.clear()
	_queue.clear()
	total = 0
	processed = 0
	failures = 0
	_network_errors = 0
	_operator_catalog.clear()
	_catalogs.clear()
	request_count = 0
	message = "Buscando a lista de séries em manutenção..."
	changed.emit()
	var response: Dictionary = await host._modern_grupo_rs_read_get("/get_veiculos_intervalo.php?intervalo=Manutencao")
	if not current(ticket):
		_finish(ticket)
		return
	if not response.get("ok", false) or not str(response.get("body", "")).to_lower().contains("<tbody"):
		message = "Não foi possível carregar a lista de manutenção."
		_finish(ticket)
		return
	var membership := {}
	for row in host._parse_dashboard_communication_rows(str(response.get("body", "")), "Manutencao"):
		var serial := str(row.get("serial", "")).strip_edges()
		if serial != "":
			membership[serial] = row.duplicate(true) if not membership.has(serial) else {}
	total = membership.size()
	message = "Relacionando %d séries com os cadastros da API..." % total
	changed.emit()
	var catalog: Dictionary = await host._modern_grupo_rs_read_get("equipamentos_editar.php?acao=novo")
	if not current(ticket):
		_finish(ticket)
		return
	if catalog.get("ok", false):
		for option in host._legacy_select_options(str(catalog.get("body", "")), "CodOperadora"):
			var code := str(option.get("value", ""))
			if code.is_valid_int() and int(code) > 0:
				_operator_catalog[int(code)] = str(option.get("label", "")).strip_edges()
	# Two serial workers; each issues one narrow read at a time, never a
	# global catalog scan. Completed devices are published immediately.
	for serial in membership:
		_queue.append({"serial": serial, "web": membership[serial]})
	_workers = 2
	_worker(ticket)
	_worker(ticket)
	while _workers > 0:
		await host.get_tree().process_frame
	if current(ticket):
		message = "Consulta concluída: %d/%d processados; %d com dados indisponíveis. Sem atualização automática." % [processed, total, failures]
	_finish(ticket)


func _worker(ticket: int) -> void:
	while current(ticket) and not _queue.is_empty():
		var identity: Dictionary = _queue.pop_front()
		var serial := str(identity.get("serial", ""))
		var web: Dictionary = identity.get("web", {})
		request_count += 1
		var vehicle: Dictionary = await host._grupo_rs_api_find_vehicle("", serial, true, false)
		if not current(ticket):
			break
		if _should_stop(vehicle):
			break
		var confirmed: Dictionary = vehicle.get("row", {})
		if not vehicle.get("ok", false) or str(confirmed.get("serial", "")) != serial:
			rows.append({"serial": serial, "maintenance": true, "source": "API: associação ausente ou ambígua"})
			processed += 1
			failures += 1
			changed.emit()
			continue
		identity = confirmed.duplicate(true)
		request_count += 1
		var equipment: Dictionary = await host._grupo_rs_api_find_equipment(serial, true)
		if not current(ticket):
			break
		if _should_stop(equipment):
			break
		if equipment.get("ok", false):
			identity = host._vehicle_location_merge_identity(identity, host._grupo_rs_api_normalize_location(equipment.get("row", {})))
			var equipment_row: Dictionary = equipment.get("row", {})
			if str(identity.get("chip", "")) == "":
				identity["chip"] = str(equipment_row.get("numeroChip", ""))
			if str(identity.get("phone", "")) == "":
				identity["phone"] = str(equipment_row.get("numeroTelefone", ""))
			identity["operator_code"] = str(equipment_row.get("codOperadora", ""))
			var raw_code := str(equipment_row.get("codOperadora", ""))
			var code := int(raw_code.to_float()) if raw_code.is_valid_float() else 0
			if str(identity.get("operator", "")) == "" and _operator_catalog.has(code):
				identity["operator"] = _operator_catalog[code]
				identity["tracker_operator_source"] = "Código API + catálogo web"
		for field in ["client", "apn", "phone"]:
			if str(identity.get(field, "")).strip_edges() == "" and str(web.get(field, "")).strip_edges() != "":
				identity[field] = web[field]
				identity[field + "_source"] = "Plataforma web · série confirmada"
		request_count += 1
		var location: Dictionary = await host._grupo_rs_api_find_location(serial, str(identity.get("plate", "")), str(identity.get("vehicle_id", "")), false)
		var location_row: Dictionary = location.get("location", {})
		if str(location_row.get("serial", "")) not in ["", serial] or str(location_row.get("vehicle_id", "")) != str(identity.get("vehicle_id", "")):
			location = {"ok": false, "location": {}}
		if not current(ticket):
			break
		if _should_stop(location):
			break
		if not location.get("ok",false) or not host._vehicle_location_has_valid_coordinates(location.get("location",{})):
			location = await WebLocation.fetch(host,identity,func(): return current(ticket))
			if not current(ticket): break
		var row: Dictionary = host._vehicle_location_merge_identity(location.get("location", {}), identity)
		for field in ["operator_code", "tracker_operator_source", "client_source", "apn_source", "phone_source"]:
			if identity.has(field):
				row[field] = identity[field]
		if str(row.get("vehicle_id", "")) != str(identity.get("vehicle_id", "")):
			row = identity.duplicate(true)
			location = {"ok": false}
		row["maintenance"] = true
		row["source"] = "API Grupo RS + complemento web"
		if location.has("source"):
			row["location_source"] = location.source
			row["source"] = "API: cadastro · Web: localização"
		if not equipment.get("ok", false) or not location.get("ok", false) or (location.get("location", {}) as Dictionary).is_empty():
			failures += 1
		rows.append(row)
		processed += 1
		message = "%d de %d processados · duas consultas simultâneas no máximo" % [processed, total]
		changed.emit()
		await host.get_tree().process_frame
	_workers -= 1


func counts() -> Dictionary:
	var on := 0
	var off := 0
	for row in rows:
		var state := Snapshot.ignition(row.get("ignition"))
		on += int(state == 1)
		off += int(state == 0)
	return {"total": total, "processed": processed, "Processados": processed,
		"Ignição ligada": on, "Ignição desligada": off, "Aguardando busca": maxi(0, total - processed)}


func _fetch_catalog(endpoint: String, ticket: int) -> void:
	var result := await Bulk.fetch(host, endpoint, func(): return current(ticket), func(name: String, page: int):
		request_count += 1
		message = "Cadastros compartilhados · %s · página %d · %d consultas" % [name, page, request_count]
		changed.emit()
	)
	_catalogs[endpoint] = Bulk.index(result.get("rows", []), "vehicle_id" if endpoint == "localizacao" else "serial")
	if not result.get("ok", false) and current(ticket):
		running = false
		message = str(result.get("message", "Consulta incompleta."))


func _should_stop(result: Dictionary) -> bool:
	if result.get("ok", false) or result.get("not_found", false):
		_network_errors = 0
		return false
	var code := int(result.get("response_code", 0))
	_network_errors += 1
	if code in [401, 403, 429] or _network_errors >= 3:
		running = false
		message = "Consulta interrompida por limite, autorização ou falhas da API. Resultado parcial preservado; tente novamente depois."
		return true
	return false


func _finish(ticket: int) -> void:
	_busy = false
	if ticket == generation:
		if Time.get_ticks_msec() >= _deadline:
			message = "Limite de tempo atingido; resultado parcial preservado."
		running = false
	changed.emit()
