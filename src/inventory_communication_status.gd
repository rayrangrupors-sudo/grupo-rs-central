extends RefCounted

## Classificação pura usada somente pelo Estoque.
## Não lê nem compartilha estado com o Mapa Grande.

const ON_COMMUNICATION_LIMIT_SECONDS := 10 * 60
const OFF_COMMUNICATION_LIMIT_SECONDS := 60 * 60
const GPS_LAG_LIMIT_ON_SECONDS := 10 * 60
const GPS_LAG_LIMIT_OFF_SECONDS := 60 * 60

static func classify(sample: Dictionary, previous: Dictionary = {}, now_unix: int = 0) -> Dictionary:
	var reference_now := now_unix if now_unix > 0 else _now_unix()
	var server_at := _first_value(sample, ["server_at", "serverAt", "data_servidor", "dataServidor", "server_time", "communication_at", "ultima_comunicacao", "ultimaComunicacao", "data_comunicacao", "DataComunicacao", "updated_at"])
	var gps_at := _first_value(sample, ["gps_at", "gpsAt", "data_gps", "dataGps", "data_completa", "dataCompleta", "gps_time", "data_evento", "dataEvento", "DataEvento", "event_at", "event_time", "data"])
	var server_unix := parse_datetime(server_at)
	var gps_unix := parse_datetime(gps_at)
	var ignition_state := ignition(sample.get("ignition", sample.get("ignicao", null)))
	var coordinate := _coordinate_state(sample)
	var communication_limit := OFF_COMMUNICATION_LIMIT_SECONDS if ignition_state == 0 else ON_COMMUNICATION_LIMIT_SECONDS
	var gps_lag_limit := GPS_LAG_LIMIT_OFF_SECONDS if ignition_state == 0 else GPS_LAG_LIMIT_ON_SECONDS
	var communication_age := reference_now - server_unix if server_unix > 0 else -1
	var gps_age := reference_now - gps_unix if gps_unix > 0 else -1
	var gps_lag := server_unix - gps_unix if server_unix > 0 and gps_unix > 0 else -1
	var server_is_stale := server_unix <= 0 or communication_age > communication_limit
	var gps_issue := false
	var gps_reason := ""
	if server_unix > 0:
		if gps_unix <= 0:
			gps_issue = true
			gps_reason = "Possível falha no GPS: data do GPS ausente ou inválida."
		elif gps_lag > gps_lag_limit:
			gps_issue = true
			gps_reason = "Possível falha no GPS: data do GPS atrasada em relação ao servidor."
		elif coordinate["state"] != "valid":
			gps_issue = true
			gps_reason = "Possível falha no GPS: coordenada ausente ou inválida."

	var coordinate_fingerprint := str(coordinate.get("fingerprint", ""))
	var repeated_coordinate := _repeated_coordinate_with_server_progress(previous, coordinate_fingerprint, server_unix, gps_unix)
	if repeated_coordinate:
		gps_issue = true
		gps_reason = "Possível falha no GPS: coordenada repetida enquanto o servidor avança."

	# Prioridade documentada: comunicação vencida = amarelo; GPS anormal com
	# servidor atualizado = roxo; desligado atualizado = vermelho; ligado = verde.
	var status_key := "desatualizado"
	var color_key := "amarelo"
	var label := "Desatualizado"
	if not server_is_stale and gps_issue:
		color_key = "roxo"
	elif not server_is_stale and ignition_state == 0:
		status_key = "desligado"
		color_key = "vermelho"
		label = "Desligado"
	elif not server_is_stale and ignition_state == 1:
		status_key = "atualizado"
		color_key = "verde"
		label = "Atualizado"

	var reason := gps_reason if gps_issue else ""
	if server_unix <= 0:
		reason = "Data do servidor ausente ou inválida."
	elif server_is_stale:
		reason = "Comunicação acima do limite esperado para o estado do aparelho."
	return {
		"status_key": status_key, "label": label, "color_key": color_key,
		"server_at": server_at, "gps_at": gps_at, "server_unix": server_unix,
		"gps_unix": gps_unix, "communication_age_seconds": communication_age,
		"gps_age_seconds": gps_age, "gps_lag_seconds": gps_lag,
		"communication_limit_seconds": communication_limit, "gps_lag_limit_seconds": gps_lag_limit,
		"ignition_state": ignition_state, "coordinate_state": coordinate["state"],
		"coordinate_fingerprint": coordinate_fingerprint, "repeated_coordinate": repeated_coordinate,
		"gps_issue": gps_issue, "gps_reason": gps_reason, "reason": reason,
		"checked_at": reference_now,
	}


static func parse_datetime(value: Variant) -> int:
	if value == null:
		return 0
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var numeric := int(value)
		return numeric if numeric > 0 else 0
	var text := str(value).strip_edges().replace("T", " ")
	var space_index := text.find(" ")
	if space_index < 0:
		return 0
	var date_text := text.substr(0, space_index)
	var time_text := text.substr(space_index + 1).strip_edges()
	var timezone_index := time_text.find("+")
	if timezone_index > 0:
		time_text = time_text.substr(0, timezone_index)
	var z_index := time_text.find("Z")
	if z_index > 0:
		time_text = time_text.substr(0, z_index)
	var date_parts := date_text.split("-") if date_text.contains("-") else date_text.split("/")
	var time_parts := time_text.split(":")
	if date_parts.size() != 3 or time_parts.size() < 2:
		return 0
	var year := 0
	var month := 0
	var day := 0
	if str(date_parts[0]).length() == 4:
		year = int(date_parts[0])
		month = int(date_parts[1])
		day = int(date_parts[2])
	else:
		day = int(date_parts[0])
		month = int(date_parts[1])
		year = int(date_parts[2])
	var hour := int(time_parts[0])
	var minute := int(time_parts[1])
	var second := int(str(time_parts[2]).split(".")[0]) if time_parts.size() > 2 else 0
	if not _valid_date(year, month, day) or hour < 0 or hour > 23 or minute < 0 or minute > 59 or second < 0 or second > 59:
		return 0
	var unix := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": second})
	var round_trip := Time.get_datetime_dict_from_unix_time(unix)
	if int(round_trip.get("year", 0)) != year or int(round_trip.get("month", 0)) != month or int(round_trip.get("day", 0)) != day:
		return 0
	return unix


static func ignition(value: Variant) -> int:
	if value == null:
		return -1
	if typeof(value) == TYPE_BOOL:
		return 1 if bool(value) else 0
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return 1 if float(value) > 0.0 else 0
	var text := str(value).strip_edges().to_lower()
	if text == "":
		return -1
	if text.contains("deslig") or text in ["0", "false", "off", "nao", "não", "no"]:
		return 0
	if text.contains("ligad") or text in ["1", "true", "on", "sim", "yes"]:
		return 1
	return 1 if text.is_valid_float() and text.to_float() > 0.0 else (0 if text.is_valid_float() else -1)


static func _coordinate_state(sample: Dictionary) -> Dictionary:
	var latitude_text := _first_value(sample, ["latitude", "lat", "gps_lat", "gpsLatitude"])
	var longitude_text := _first_value(sample, ["longitude", "lng", "lon", "gps_lng", "gpsLongitude"])
	if latitude_text == "" or longitude_text == "":
		return {"state": "missing", "fingerprint": ""}
	var normalized_latitude := latitude_text.replace(",", ".")
	var normalized_longitude := longitude_text.replace(",", ".")
	if not normalized_latitude.is_valid_float() or not normalized_longitude.is_valid_float():
		return {"state": "invalid", "fingerprint": ""}
	var latitude := normalized_latitude.to_float()
	var longitude := normalized_longitude.to_float()
	if not is_finite(latitude) or not is_finite(longitude) or latitude < -90.0 or latitude > 90.0 or longitude < -180.0 or longitude > 180.0 or (is_zero_approx(latitude) and is_zero_approx(longitude)):
		return {"state": "invalid", "fingerprint": ""}
	# O histórico precisa comparar coordenadas, mas não deve armazenar a posição
	# em claro. O fingerprint sanitizado também não vai para logs ou métricas.
	return {"state": "valid", "fingerprint": ("%0.6f|%0.6f" % [latitude, longitude]).sha256_text()}


static func _repeated_coordinate_with_server_progress(previous: Dictionary, fingerprint: String, server_unix: int, gps_unix: int) -> bool:
	if fingerprint == "" or previous.is_empty() or server_unix <= 0 or str(previous.get("coordinate_fingerprint", "")) != fingerprint:
		return false
	var previous_server := int(previous.get("server_unix", 0))
	if previous_server <= 0 or server_unix <= previous_server:
		return false
	var previous_gps := int(previous.get("gps_unix", 0))
	return gps_unix <= 0 or previous_gps <= 0 or gps_unix <= previous_gps


static func _first_value(data: Dictionary, keys: Array) -> String:
	for key in keys:
		if data.has(key) and data.get(key) != null and str(data.get(key)).strip_edges() != "":
			return str(data.get(key)).strip_edges()
	for container_key in ["raw", "records", "event", "ultimo_evento", "latest_event"]:
		var container: Variant = data.get(container_key, null)
		if typeof(container) != TYPE_DICTIONARY:
			continue
		for key in keys:
			if (container as Dictionary).has(key) and (container as Dictionary).get(key) != null and str((container as Dictionary).get(key)).strip_edges() != "":
				return str((container as Dictionary).get(key)).strip_edges()
	return ""


static func _valid_date(year: int, month: int, day: int) -> bool:
	if year < 2000 or year > 2200 or month < 1 or month > 12 or day < 1:
		return false
	var days := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month == 2 and (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)):
		days[1] = 29
	return day <= int(days[month - 1])


static func _now_unix() -> int:
	return Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system(false))
