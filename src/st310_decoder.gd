class_name ST310Decoder
extends RefCounted

## Decodificador somente leitura para configuracoes e telemetria ST310.
##
## A classe nao envia comandos, nao grava no aparelho e nao altera a API.
## Ela recebe um pacote bruto em texto, JSON ou dicionario e devolve apenas
## campos validados para a camada de localizacao. A API nao e fonte de GPS.

const MIN_LATITUDE := -90.0
const MAX_LATITUDE := 90.0
const MIN_LONGITUDE := -180.0
const MAX_LONGITUDE := 180.0

static func decode(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return decode_packet_dict(value as Dictionary)
	if typeof(value) == TYPE_STRING:
		return decode_text(str(value))
	return {
		"ok": false,
		"protocol": "ST310",
		"kind": "unknown",
		"fields": {},
		"coordinates": {},
		"message": "Entrada ST310 nao reconhecida.",
	}


static func decode_local_product(product: Dictionary) -> Dictionary:
	## Decodifica somente o pacote bruto armazenado localmente/Banco local SQL.
	## A associacao do aparelho nao participa desta leitura.
	var packet_keys := [
		"st310_raw_packet", "st310_packet", "raw_packet", "rawPacket",
		"packet_raw", "payload_raw", "payload_bruto", "communication_packet",
		"last_raw_packet", "ultima_mensagem_bruta"
	]
	for key in packet_keys:
		if not product.has(key):
			continue
		var packet: Variant = product.get(key)
		if packet == null:
			continue
		if typeof(packet) == TYPE_DICTIONARY:
			return decode_packet_dict(packet as Dictionary)
		var text := str(packet).strip_edges()
		if text != "":
			return decode_text(text)

	for key in ["st310", "telemetry_raw", "telemetria_bruta"]:
		var nested: Variant = product.get(key)
		if typeof(nested) == TYPE_DICTIONARY:
			return decode_packet_dict(nested as Dictionary)
		if typeof(nested) == TYPE_STRING and str(nested).strip_edges() != "":
			return decode_text(str(nested))

	return _empty_result("Nenhum pacote bruto ST310 disponivel para decodificacao.")


static func decode_packet_dict(raw: Dictionary) -> Dictionary:
	var data := _flatten_location_dict(raw)
	var coordinates := _extract_coordinates(data)
	var fields := {
		"serial": _string_value(data, ["id", "ID", "serial", "serie", "numeroSerie", "numero_serie", "imei", "IMEI"]),
		"plate": _string_value(data, ["placa", "Placa", "plate"]),
		"communication_at": _string_value(data, ["ultima_comunicacao", "ultimaComunicacao", "data_comunicacao", "DataComunicacao", "updated_at"]),
		"event_at": _string_value(data, ["data_evento", "dataEvento", "DataEvento", "event_at", "event_time"]),
		"ignition": _string_value(data, ["ignicao", "Ignicao", "StatusIgnicao", "status_ignicao", "ignition", "Ignition"]),
		"speed": _string_value(data, ["velocidade", "speed", "Velocidade"]),
		"heading": _string_value(data, ["direcao", "Direcao", "heading", "Heading"]),
		"battery": _string_value(data, ["bateria", "battery", "Bateria", "tensao_bateria", "tensaoBateria", "voltagem", "voltage"]),
		"gps_signal": _string_value(data, ["sinal_gps", "SinalGPS", "gps_signal", "gpsSignal", "signal_gps"]),
		"event_type": _string_value(data, ["tipo_evento", "TipoEvento", "event_type", "eventType"]),
"protocol": _string_value(data, ["protocolo", "protocol", "PROTOCOLO", "PROTOCOL"]),
	}
	var has_coordinates := not coordinates.is_empty()
	return {
		"ok": true,
		"protocol": "ST310",
		"kind": "position" if has_coordinates else "communication",
		"fields": fields,
		"coordinates": coordinates,
		"coordinates_valid": has_coordinates,
		"message": "Posicao ST310 validada." if has_coordinates else "Pacote ST310 sem coordenada valida.",
	}


static func decode_api_row(raw: Dictionary) -> Dictionary:
	# Mantido apenas para compatibilidade com diagnósticos antigos. O mapa não
	# chama esta função; ele usa exclusivamente decode_local_product().
	return decode_packet_dict(raw)


static func decode_text(raw_text: String) -> Dictionary:
	var text := raw_text.strip_edges()
	if text == "":
		return _empty_result("Pacote vazio.")

	if text.begins_with("{") and text.ends_with("}"):
		var json_value: Variant = JSON.parse_string(text)
		if typeof(json_value) == TYPE_DICTIONARY:
			return decode_packet_dict(json_value as Dictionary)

	var nmea := _decode_nmea(text)
	if not nmea.is_empty():
		return nmea

	var st300_report := _decode_st300_report(text)
	if not st300_report.is_empty():
		return st300_report

	var fields := {}
	var coordinates := {}
	var kind := "packet"
	if text.to_upper().contains("<SETTING") or text.to_upper().contains("PROTOCOL:ST310"):
		kind = "configuration"
		fields = _decode_setting_lines(text)
	else:
		fields = _decode_key_value_packet(text)
		coordinates = _extract_coordinates(fields)

	return {
		"ok": true,
		"protocol": "ST310",
		"kind": kind,
		"fields": fields,
		"coordinates": coordinates,
		"coordinates_valid": not coordinates.is_empty(),
		"message": "Configuracao ST310 decodificada." if kind == "configuration" else ("Posicao ST310 validada." if not coordinates.is_empty() else "Pacote ST310 sem nova coordenada."),
	}


static func _decode_st300_report(text: String) -> Dictionary:
	## Relatorio ASCII enviado pelos ST310/ST300.
	##
	## Exemplo de cabecalho real:
	## ST300STT;024306149;01;010;20260819;11:35:06;01454;-5.519330;-47.469007;000.000;000.00;9;1;0;13.00;000001;1;0072;0;0.00;1
	##
	## O mapa usa somente latitude/longitude validadas deste relatorio. Os
	## campos de identidade servem apenas para casar o pacote com o cadastro
	## local; nenhum dado de localizacao da API e copiado para este resultado.
	var normalized := text.replace("\r", "\n")
	for raw_line in normalized.split("\n"):
		var line := str(raw_line).strip_edges()
		if line == "":
			continue
		var parts := line.split(";")
		if parts.size() < 16:
			continue
		var header := str(parts[0]).strip_edges().to_upper()
		if header not in ["ST300STT", "ST300EVT", "ST300EMG", "ST300ALT"]:
			continue

		var serial := str(parts[1]).strip_edges()
		var date_text := str(parts[4]).strip_edges() if parts.size() > 4 else ""
		var time_text := str(parts[5]).strip_edges() if parts.size() > 5 else ""
		var communication_at := "%s %s" % [date_text, time_text] if date_text != "" and time_text != "" else ""
		var latitude_text := str(parts[7]).strip_edges() if parts.size() > 7 else ""
		var longitude_text := str(parts[8]).strip_edges() if parts.size() > 8 else ""
		var coordinates := {
			"lat": _parse_coordinate(latitude_text, MIN_LATITUDE, MAX_LATITUDE),
			"lng": _parse_coordinate(longitude_text, MIN_LONGITUDE, MAX_LONGITUDE),
		}
		if not is_finite(float(coordinates["lat"])) or not is_finite(float(coordinates["lng"])):
			coordinates = {}
		if coordinates.is_empty() or (is_zero_approx(float(coordinates.get("lat", 0.0))) and is_zero_approx(float(coordinates.get("lng", 0.0)))):
			coordinates = {}

		var io := str(parts[15]).strip_edges() if parts.size() > 15 else ""
		var ignition := ""
		if io != "":
			var last_io_bit := io.substr(io.length() - 1, 1)
			if last_io_bit in ["0", "1"]:
				ignition = last_io_bit

		var fields := {
			"serial": serial,
			"report": header,
			"model": str(parts[2]).strip_edges() if parts.size() > 2 else "",
			"software_version": str(parts[3]).strip_edges() if parts.size() > 3 else "",
			"date": date_text,
			"time": time_text,
			"communication_at": communication_at,
			"cell": str(parts[6]).strip_edges() if parts.size() > 6 else "",
			"speed": str(parts[9]).strip_edges() if parts.size() > 9 else "",
			"heading": str(parts[10]).strip_edges() if parts.size() > 10 else "",
			"satellites": str(parts[11]).strip_edges() if parts.size() > 11 else "",
			"gps_fixed": str(parts[12]).strip_edges() if parts.size() > 12 else "",
			"distance": str(parts[13]).strip_edges() if parts.size() > 13 else "",
			"power_voltage": str(parts[14]).strip_edges() if parts.size() > 14 else "",
			"io": io,
			"ignition": ignition,
			"event_type": str(parts[17]).strip_edges() if parts.size() > 17 else "",
			"backup_voltage": str(parts[19]).strip_edges() if parts.size() > 19 else "",
			"real_time": str(parts[20]).strip_edges() if parts.size() > 20 else "",
		}
		return {
			"ok": true,
			"protocol": "ST310",
			"kind": "position" if not coordinates.is_empty() else "communication",
			"fields": fields,
			"coordinates": coordinates,
			"coordinates_valid": not coordinates.is_empty(),
			"message": "Posicao ST310/ST300STT validada." if not coordinates.is_empty() else "Relatorio ST310 sem nova coordenada valida.",
		}
	return {}


static func _empty_result(message: String) -> Dictionary:
	return {
		"ok": false,
		"protocol": "ST310",
		"kind": "unknown",
		"fields": {},
		"coordinates": {},
		"coordinates_valid": false,
		"message": message,
	}


static func _flatten_location_dict(raw: Dictionary) -> Dictionary:
	var data := raw.duplicate(true)
	for key in ["localizacao", "location", "posicao", "ultima_localizacao", "last_location", "telemetria", "telemetry", "dados"]:
		var nested: Variant = raw.get(key)
		if typeof(nested) != TYPE_DICTIONARY:
			continue
		for nested_key in (nested as Dictionary).keys():
			if not data.has(nested_key):
				data[nested_key] = (nested as Dictionary).get(nested_key)
	return data


static func _string_value(data: Dictionary, keys: Array) -> String:
	for key in keys:
		if not data.has(key):
			continue
		var raw: Variant = data.get(key)
		if raw == null:
			continue
		if typeof(raw) == TYPE_DICTIONARY:
			var nested := raw as Dictionary
			for nested_key in ["value", "valor", "name", "nome", "id", "codigo", "code"]:
				var nested_value: Variant = nested.get(nested_key, "")
				if nested_value != null and str(nested_value).strip_edges() != "":
					return str(nested_value).strip_edges()
			continue
		var text := str(raw).strip_edges()
		if text != "":
			return text
	return ""


static func _extract_coordinates(data: Dictionary) -> Dictionary:
	var latitude_text := _string_value(data, ["latitude", "Latitude", "lat", "LAT", "gps_lat", "gpsLatitude"])
	var longitude_text := _string_value(data, ["longitude", "Longitude", "lng", "lon", "LNG", "gps_lng", "gpsLongitude"])
	var latitude := _parse_coordinate(latitude_text, -90.0, 90.0)
	var longitude := _parse_coordinate(longitude_text, -180.0, 180.0)
	if not is_finite(latitude) or not is_finite(longitude):
		return {}
	if is_zero_approx(latitude) and is_zero_approx(longitude):
		return {}
	return {"lat": latitude, "lng": longitude}


static func _parse_coordinate(value: String, minimum: float, maximum: float) -> float:
	var normalized := value.strip_edges().replace(",", ".")
	if normalized == "" or not normalized.is_valid_float():
		return NAN
	var result := float(normalized)
	if not is_finite(result) or result < minimum or result > maximum:
		return NAN
	return result


static func _decode_setting_lines(text: String) -> Dictionary:
	var fields := {}
	for line in text.replace("\r", "").split("\n"):
		var clean := line.strip_edges()
		if clean.begins_with("<"):
			clean = clean.substr(1).strip_edges()
		if clean.ends_with(">"):
			clean = clean.substr(0, clean.length() - 1).strip_edges()
		if clean == "" or clean.to_upper() == "SETTING":
			continue
		var separator := clean.find(":")
		if separator < 1:
			continue
		var key := clean.substr(0, separator).strip_edges().to_lower().replace(" ", "_")
		var value := clean.substr(separator + 1).strip_edges()
		if key == "apn":
			_decode_apn_value(value, fields)
		else:
			fields[key] = value
	return fields


static func _decode_apn_value(value: String, fields: Dictionary) -> void:
	for part in value.split(","):
		var separator := part.find("=")
		if separator < 1:
			continue
		var key := part.substr(0, separator).strip_edges().to_lower()
		var item := part.substr(separator + 1).strip_edges()
		if key in ["pwd", "password", "senha"]:
			fields["apn_password"] = "[oculto]"
		else:
			fields["apn_%s" % key] = item


static func _decode_key_value_packet(text: String) -> Dictionary:
	var fields := {}
	var normalized := text.replace("\r", "").replace("\n", ";")
	for token in normalized.split(";"):
		var part := token.strip_edges()
		if part == "":
			continue
		var separator := part.find("=")
		if separator < 1:
			separator = part.find(":")
		if separator < 1:
			continue
		var key := part.substr(0, separator).strip_edges().to_lower().replace(" ", "_")
		var value := part.substr(separator + 1).strip_edges()
		fields[key] = value
	return fields


static func _decode_nmea(text: String) -> Dictionary:
	for line in text.replace("\r", "").split("\n"):
		var sentence := line.strip_edges()
		var upper := sentence.to_upper()
		if not (upper.contains("RMC") or upper.contains("GGA")):
			continue
		var parts := sentence.split(",")
		if upper.contains("RMC") and parts.size() >= 9:
			if parts[2].strip_edges().to_upper() != "A":
				return {"ok": true, "protocol": "ST310", "kind": "communication", "fields": {}, "coordinates": {}, "coordinates_valid": false, "message": "GPS sem fix valido."}
			var coords := _nmea_coordinates(parts[3], parts[4], parts[5], parts[6])
			if coords.is_empty():
				continue
			var fields := {"nmea_time": parts[1], "speed_knots": parts[7], "heading": parts[8]}
			return {"ok": true, "protocol": "ST310", "kind": "position", "fields": fields, "coordinates": coords, "coordinates_valid": true, "message": "Posicao NMEA/ST310 validada."}
		if upper.contains("GGA") and parts.size() >= 6:
			if parts.size() >= 7 and parts[6].strip_edges() == "0":
				return {"ok": true, "protocol": "ST310", "kind": "communication", "fields": {"nmea_time": parts[1]}, "coordinates": {}, "coordinates_valid": false, "message": "GPS sem fix valido."}
			var gga_coords := _nmea_coordinates(parts[2], parts[3], parts[4], parts[5])
			if not gga_coords.is_empty():
				return {"ok": true, "protocol": "ST310", "kind": "position", "fields": {"nmea_time": parts[1]}, "coordinates": gga_coords, "coordinates_valid": true, "message": "Posicao NMEA/ST310 validada."}
	return {}


static func _nmea_coordinates(latitude_text: String, latitude_hemisphere: String, longitude_text: String, longitude_hemisphere: String) -> Dictionary:
	var latitude := _nmea_coordinate(latitude_text, latitude_hemisphere, 2)
	var longitude := _nmea_coordinate(longitude_text, longitude_hemisphere, 3)
	if not is_finite(latitude) or not is_finite(longitude):
		return {}
	return {"lat": latitude, "lng": longitude}


static func _nmea_coordinate(value: String, hemisphere: String, degree_digits: int) -> float:
	var clean := value.strip_edges().replace(",", ".")
	if clean.length() <= degree_digits or not clean.is_valid_float():
		return NAN
	var degrees := float(clean.substr(0, degree_digits))
	var minutes := float(clean.substr(degree_digits))
	var result := degrees + minutes / 60.0
	var direction := hemisphere.strip_edges().to_upper()
	if direction in ["S", "W"]:
		result = -result
	if direction not in ["N", "S", "E", "W"]:
		return NAN
	return result
