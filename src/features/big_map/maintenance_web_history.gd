## Read-only fallback with an exact client match, never the first search result.
extends RefCounted


static func fetch(host: Node, location: Dictionary, active: Callable = Callable()) -> Dictionary:
	var client := str(location.get("client", "")).strip_edges()
	var vehicle := str(location.get("vehicle_id", "")).strip_edges()
	var reference: int = host._grupo_rs_datetime_to_unix(str(location.get("updated_at", "")))
	if client == "" or vehicle == "" or reference <= 0:
		return {"ok": false, "message": "Faltam cliente, veículo ou data para consultar o histórico web."}
	var lookup_url: String = host._grupo_rs_client_lookup_url(client)
	if lookup_url == "":
		return {"ok": false, "message": "Consulta de cliente web indisponível."}
	var lookup: Dictionary = await host._modern_grupo_rs_read_get(lookup_url)
	if active.is_valid() and not active.call():
		return {"ok": false, "message": "Consulta cancelada."}
	var payload: Variant = JSON.parse_string(str(lookup.get("body", "")))
	if not lookup.get("ok", false) or not payload is Dictionary:
		return {"ok": false, "message": "Não foi possível confirmar o cliente na plataforma."}
	var candidates := {}
	for item in payload.get("items", payload.get("results", [])):
		if item is Dictionary and host._search_key(str(item.get("text", ""))) == host._search_key(client):
			var id_keys: Array[String] = ["id"]
			var id: String = host._grupo_rs_api_numeric_string_value(item, id_keys)
			if id.is_valid_int() and int(id) > 0:
				candidates[id] = true
	if candidates.size() != 1:
		return {"ok": false, "message": "Cliente ausente ou ambíguo; histórico web não consultado."}
	var client_id := str(candidates.keys()[0])
	var path := "/get_eventos.php?cliente=%s&veiculo=%s&inicio=%s&fim=%s" % [client_id.uri_encode(), vehicle.uri_encode(), host._format_grupo_rs_records_datetime(reference - 604800).uri_encode(), host._format_grupo_rs_records_datetime(reference + 60).uri_encode()]
	var response: Dictionary = await host._modern_grupo_rs_read_get(path)
	if active.is_valid() and not active.call():
		return {"ok": false, "message": "Consulta cancelada."}
	var result: Variant = JSON.parse_string(str(response.get("body", "")))
	if not response.get("ok", false) or not result is Dictionary or not result.get("eventos") is Array:
		return {"ok": false, "message": "Histórico web indisponível ou em formato inesperado."}
	if result.get("eventos").size() > 20000:
		return {"ok": false, "message": "Histórico web excedeu o limite seguro de análise."}
	var records: Array[Dictionary] = []
	var seen := {}
	for raw in result.get("eventos"):
		if not raw is Dictionary:
			continue
		# The web endpoint's id identifies the event, not the vehicle.
		var event: Dictionary = raw.duplicate(true)
		event.erase("id")
		if event.has("cod_veiculo"):
			event["codVeiculo"] = event["cod_veiculo"]
		var row: Dictionary = host._grupo_rs_api_normalize_location(event)
		var row_vehicle := str(row.get("vehicle_id", ""))
		if row_vehicle != vehicle:
			return {"ok": false, "message": "Histórico retornou outro veículo; resposta descartada."}
		var timestamp: int = host._grupo_rs_datetime_to_unix(str(row.get("updated_at", "")))
		if timestamp <= 0:
			return {"ok": false, "message": "Histórico contém datas não interpretáveis; ordem não confirmada."}
		var signature := JSON.stringify(raw).sha256_text()
		if not seen.has(signature):
			seen[signature] = true
			row["history_unix"] = timestamp
			records.append(row)
	records.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.history_unix) > int(b.history_unix))
	return {"ok": true, "records": records.slice(0, 20), "available": records.size(), "source": "Plataforma web · janela de 7 dias"}
