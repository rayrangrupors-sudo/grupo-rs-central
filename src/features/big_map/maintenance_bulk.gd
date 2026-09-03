## Read each shared catalog once, with strict pagination and duplicate detection.
extends RefCounted
static func fetch(host: Node, endpoint: String, active: Callable, progress: Callable) -> Dictionary:
	var skip := 0
	var signatures := {}
	var rows: Array[Dictionary] = []
	for page_number in range(500):
		if not active.call():
			return {"ok": false, "message": "Consulta cancelada."}
		var response: Dictionary = await host._grupo_rs_api_get("/endpoints/%s.php?skip=%d&take=50" % [endpoint, skip], true, true)
		if not active.call() or not response.get("ok", false):
			return {"ok": false, "message": "Consulta compartilhada interrompida: %s." % endpoint}
		var payload: Variant = JSON.parse_string(str(response.get("body", "")))
		if not payload is Dictionary:
			return {"ok": false, "message": "Resposta inválida: %s." % endpoint}
		if payload.get("ok", true) == false or payload.get("success", true) == false:
			return {"ok": false, "message": "A API recusou a consulta: %s." % endpoint}
		var page: Array = host._grupo_rs_api_equipment_rows(payload) if endpoint == "equipamentos" else host._grupo_rs_api_extract_rows(payload)
		var signature := JSON.stringify(page).sha256_text()
		if signatures.has(signature) and not page.is_empty():
			return {"ok": false, "message": "Página repetida: %s." % endpoint}
		signatures[signature] = true
		for raw in page:
			rows.append(host._grupo_rs_api_normalize_location(raw))
		progress.call(endpoint, page_number + 1)
		var pagination: Dictionary = host._grupo_rs_api_pagination_state(payload, skip, page.size())
		if (pagination.get("pagination", {}) as Dictionary).is_empty() and not page.is_empty():
			return {"ok": false, "message": "Paginação não confirmada: %s." % endpoint}
		if not pagination.get("has_more", false):
			return {"ok": true, "rows": rows}
		var next := int(pagination.get("next_skip", skip))
		if next <= skip:
			return {"ok": false, "message": "Próxima página inválida."}
		skip = next
	return {"ok": false, "message": "Limite de páginas atingido."}

static func index(rows: Array, field: String) -> Dictionary:
	var result := {}
	for row in rows:
		var key := str(row.get(field, ""))
		if key != "":
			result[key] = row if not result.has(key) else {}
	return result
