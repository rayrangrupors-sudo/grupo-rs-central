extends SceneTree

const Status := preload("res://src/inventory_communication_status.gd")
var failures: Array[String] = []
var now_unix := 0

func _init() -> void:
	now_unix = Status.parse_datetime("2026-08-26 12:00:00")
	call_deferred("_run")

func _run() -> void:
	_check(now_unix > 0, "Data fixa de teste não foi convertida.")
	_check(Status.parse_datetime("2026-02-30 12:00:00") == 0, "Data inválida foi aceita.")
	_check(Status.parse_datetime("data inválida") == 0, "Texto inválido foi aceito como data.")
	_check(Status.classify(_sample("2026-08-26 11:59:00", "2026-08-26 11:59:00", 1, "-5.5", "-47.4"), {}, now_unix).get("color_key") == "verde", "Ligado recente não ficou verde.")
	_check(Status.classify(_sample("2026-08-26 11:49:59", "2026-08-26 11:49:59", 1, "-5.5", "-47.4"), {}, now_unix).get("color_key") == "amarelo", "Ligado acima de 10 minutos não ficou amarelo.")
	_check(Status.classify(_sample("2026-08-26 11:00:01", "2026-08-26 11:00:01", 0, "-5.5", "-47.4"), {}, now_unix).get("color_key") == "vermelho", "Desligado dentro de uma hora não ficou vermelho.")
	_check(Status.classify(_sample("2026-08-26 10:59:59", "2026-08-26 10:59:59", 0, "-5.5", "-47.4"), {}, now_unix).get("color_key") == "amarelo", "Desligado acima de uma hora não ficou amarelo.")
	var gps_late := Status.classify(_sample("2026-08-26 11:59:00", "2026-08-26 11:40:00", 1, "-5.5", "-47.4"), {}, now_unix)
	_check(gps_late.get("color_key") == "roxo" and bool(gps_late.get("gps_issue")), "Servidor atualizado e GPS atrasado não ficou roxo.")
	var first := Status.classify(_sample("2026-08-26 11:58:00", "2026-08-26 11:58:00", 1, "-5.5", "-47.4"), {}, now_unix)
	var repeated := Status.classify(_sample("2026-08-26 11:59:00", "2026-08-26 11:58:00", 1, "-5.5", "-47.4"), first, now_unix)
	_check(bool(repeated.get("repeated_coordinate")) and repeated.get("color_key") == "roxo", "Coordenada repetida com servidor avançando não ficou roxa.")
	_check(Status.classify(_sample("2026-08-26 11:59:00", "", 1, "-5.5", "-47.4"), {}, now_unix).get("color_key") == "roxo", "Ausência da data GPS não foi sinalizada em roxo.")
	_check(Status.classify(_sample("2026-08-26 11:59:00", "2026-08-26 11:59:00", 1, "fora", "-47.4"), {}, now_unix).get("color_key") == "roxo", "Coordenada inválida não foi sinalizada em roxo.")
	var server_alias := Status.classify({"DataServidor": "2026-08-26 11:59:00", "DataGPS": "2026-08-26 11:59:00", "StatusIgnicao": 1, "latitude": "-5.5", "longitude": "-47.4"}, {}, now_unix)
	_check(server_alias.get("color_key") == "verde" and int(server_alias.get("server_unix", 0)) > 0 and int(server_alias.get("gps_unix", 0)) > 0, "Aliases DataServidor/DataGPS não foram classificados.")
	var empty := Status.classify({}, {}, now_unix)
	_check(empty.get("status_key") == "desatualizado" and empty.get("color_key") == "amarelo", "Resposta vazia não ficou desatualizada.")
	_check(Status.classify({"error": "timeout"}, {}, now_unix).get("status_key") == "desatualizado", "Timeout não ficou desatualizado.")
	_check(Status.classify({"response_code": 401}, {}, now_unix).get("status_key") == "desatualizado", "Erro de autenticação não ficou desatualizado.")
	_finish()

func _sample(server_at: String, gps_at: String, ignition: int, latitude: String, longitude: String) -> Dictionary:
	return {"server_at": server_at, "gps_at": gps_at, "ignition": ignition, "latitude": latitude, "longitude": longitude}

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("INVENTORY_COMMUNICATION_STATUS_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
