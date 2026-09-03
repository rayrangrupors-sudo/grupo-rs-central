## Geographic triage only. Distances do not estimate radio coverage.
extends RefCounted
static func carrier(value: String) -> String:
	var text:=value.strip_edges().to_upper()
	if text.contains("VIVO") or text.contains("TELEFONICA"): return "VIVO"
	if text.contains("CLARO"): return "CLARO"
	if text=="TIM" or text.begins_with("TIM "): return "TIM"
	return ""
static func evaluate(location: Dictionary,stations: Array) -> Dictionary:
	var op:=carrier(str(location.get("operator","")))
	if op=="" or not str(location.get("lat","")).is_valid_float() or not str(location.get("lng","")).is_valid_float():
		return {"hypothesis":false,"note":"Contexto de ERBs indisponível: operadora ou posição não identificada."}
	var lat:=float(location.lat)
	var lng:=float(location.lng)
	if absf(lat)>90 or absf(lng)>180: return {"hypothesis":false,"note":"Posição inválida para comparar ERBs."}
	var own:=INF
	var other:=INF
	for station in stations:
		if station.get("is_index_cluster",false): continue
		var station_op:=carrier(str(station.get("operator","")))
		if station_op=="" or not str(station.get("lat","")).is_valid_float() or not str(station.get("lng","")).is_valid_float(): continue
		var dlat:=deg_to_rad(float(station.lat)-lat)
		var dlng:=deg_to_rad(float(station.lng)-lng)
		var a:=sin(dlat/2)*sin(dlat/2)+cos(deg_to_rad(lat))*cos(deg_to_rad(float(station.lat)))*sin(dlng/2)*sin(dlng/2)
		var distance:=6371.0*2.0*asin(sqrt(clampf(a,0,1)))
		if distance>15.0: continue
		if station_op==op: own=minf(own,distance)
		else: other=minf(other,distance)
	# Explicit heuristic for triage, NOT a technical coverage radius.
	var hypothesis:=is_finite(own) and is_finite(other) and own>=5.0 and other<=1.0
	var note:="ERBs consultadas até 15 km: "
	note+="%s a %.1f km"%[op,own] if is_finite(own) else "nenhuma ERB da operadora encontrada no recorte"
	note+=", outra operadora a %.1f km."%other if is_finite(other) else "; outra operadora não localizada."
	note+=" Distâncias geográficas de cadastro, não sinal medido. Ausência no recorte não comprova ausência de cobertura. Tecnologia, relevo, roaming e estado da rede não foram confirmados."
	if hypothesis: note="Possível perda de sinal, não confirmada. "+note+" Critério experimental: ERB da operadora ≥5 km e outra ≤1 km; não representa limite de cobertura."
	return {"hypothesis":hypothesis,"note":note,"own_km":own if is_finite(own) else -1.0,"other_km":other if is_finite(other) else -1.0}
