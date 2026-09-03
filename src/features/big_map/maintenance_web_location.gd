## Read-only location fallback; exact client and confirmed vehicle association.
extends RefCounted

static func fetch(host: Node, identity: Dictionary, active: Callable) -> Dictionary:
	var client := str(identity.get("client", "")).strip_edges()
	var vehicle := str(identity.get("vehicle_id", ""))
	var serial := str(identity.get("serial", ""))
	var plate := str(identity.get("plate", ""))
	if client == "" or vehicle == "" or serial == "" or plate == "" or not active.call():
		return {"ok":false, "location":{}}
	var lookup: Dictionary = await host._modern_grupo_rs_read_get(host._grupo_rs_client_lookup_url(client))
	if not active.call(): return {"ok":false,"location":{}}
	var payload: Variant = JSON.parse_string(str(lookup.get("body", "")))
	if not lookup.get("ok",false) or not payload is Dictionary:
		return {"ok":false,"location":{}}
	var ids := {}
	var keys: Array[String] = ["id"]
	for item in payload.get("items",payload.get("results",[])):
		if item is Dictionary and host._search_key(str(item.get("text",""))) == host._search_key(client):
			var id: String = host._grupo_rs_api_numeric_string_value(item,keys)
			if id.is_valid_int() and int(id)>0: ids[id]=true
	if ids.size()!=1: return {"ok":false,"location":{}}
	var url: String = host._grupo_rs_vehicle_location_url(str(ids.keys()[0]),plate,host._normalize_location_plate(plate))
	if url == "": return {"ok":false,"location":{}}
	var response: Dictionary = await host._modern_grupo_rs_read_get(url)
	if not active.call(): return {"ok":false,"location":{}}
	payload = JSON.parse_string(str(response.get("body","")))
	if not response.get("ok",false) or not payload is Array:
		return {"ok":false,"location":{}}
	var matches := []
	for raw in payload:
		if not raw is Dictionary: continue
		var row: Dictionary = host._grupo_rs_api_normalize_location(raw)
		if str(row.get("vehicle_id","")) != vehicle: continue
		if str(row.get("serial","")) not in ["",serial]: continue
		if host._normalize_location_plate(str(row.get("plate",""))) != host._normalize_location_plate(plate): continue
		if not host._vehicle_location_has_valid_coordinates(row): continue
		matches.append(row)
	if matches.size()!=1: return {"ok":false,"location":{}}
	return {"ok":true,"location":matches[0],"source":"Plataforma web · localização confirmada"}
