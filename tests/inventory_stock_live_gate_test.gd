extends SceneTree

## Harness read-only do gate real do Estoque.
## Login e o unico POST; depois deste ponto o harness usa somente GET de negocio.
## Usa exclusivamente a sessao oficial e os dados da API do Estoque.

const DashboardScript := preload("res://src/inventory_dashboard.gd")
const StatusScript := preload("res://src/inventory_communication_status.gd")

const PAGE_SIZE := 10
const MAX_LOCATION_PAGES := 5
const MAX_VEHICLE_PAGES := 2
const POLL_CYCLES := 3
const POLL_INTERVAL_SECONDS := 1.0
const LOCATION_PAGE_PAUSE_SECONDS := 0.2
const SAFE_P95_MS := 1000
const LATENCY_RISK_MS := 3000

var failures: Array[String] = []
var risk_detected := false
var running := true
var frame_monitor_started := false
var last_frame_msec := 0
var in_flight := 0
var previous_by_identity: Dictionary = {}
var last_payload_by_identity: Dictionary = {}
var queue_unique_ids: Dictionary = {}
var reason_counts: Dictionary = {}
var latencies_ms: Array[int] = []
var metrics: Dictionary = {
	"location_pages": 0, "location_rows": 0,
	"vehicle_pages": 0, "vehicle_rows": 0,
	"empty_location_pages": 0, "empty_vehicle_pages": 0,
	"parse_errors": 0, "http_errors": 0, "timeouts": 0,
	"auth_errors": 0, "rate_limits": 0, "permission_errors": 0,
	"green": 0, "yellow": 0, "red": 0, "purple": 0,
	"server_present": 0, "server_absent": 0,
	"gps_present": 0, "gps_absent": 0,
	"gps_issue": 0, "repeated_coordinate": 0,
	"position_missing": 0, "position_invalid": 0,
	"latest_comm_present": 0, "latest_comm_absent": 0,
	"existing_targets_updated": 0, "new_targets": 0,
	"queue_unique_count": 0, "same_payload_reobserved": 0,
	"duplicates_within_page": 0, "duplicates_within_cycle": 0,
	"cycles": 0, "in_flight_max": 0, "reauth": 0,
	"max_frame_gap_ms": 0, "rebuilds_observed": 0
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard: Node = DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set_process(false)
	_frame_monitor()

	# O branch e apenas contexto da API oficial do Estoque; nenhum valor e impresso.
	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")

	var credentials_variant: Variant = dashboard.call("_grupo_rs_api_credentials")
	if typeof(credentials_variant) != TYPE_DICTIONARY:
		_fail("credentials_unavailable")
		await _cleanup(dashboard)
		_finish(2)
		return
	var credentials := credentials_variant as Dictionary
	var login_variant: Variant = await dashboard.call(
		"_grupo_rs_api_login_with_credentials",
		str(credentials.get("username", "")),
		str(credentials.get("password", ""))
	)
	if typeof(login_variant) != TYPE_DICTIONARY or not bool((login_variant as Dictionary).get("ok", false)):
		_inc("auth_errors")
		_fail("login_failed")
		await _cleanup(dashboard)
		_finish(2)
		return

	var location_result := await _read_business_pages(dashboard, "/endpoints/localizacao.php", MAX_LOCATION_PAGES, true)
	var vehicle_result := await _read_business_pages(dashboard, "/endpoints/veiculos.php", MAX_VEHICLE_PAGES, false)
	if not bool(location_result.get("usable", false)):
		_fail("location_sample_unusable")
	if not bool(vehicle_result.get("usable", false)):
		_fail("vehicle_sample_unusable")

	# Polling somente quando a amostra controlada permaneceu abaixo do limite seguro.
	if bool(location_result.get("safe_for_polling", false)) and failures.is_empty():
		await _run_short_poll(dashboard)

	await _cleanup(dashboard)
	_finish(1 if not failures.is_empty() else 0)


func _read_business_pages(dashboard: Node, endpoint: String, max_pages: int, is_location: bool) -> Dictionary:
	var current_skip := 0
	var usable := false
	var page_index := 0
	var cycle_seen: Dictionary = {}
	while page_index < max_pages and not risk_detected:
		if is_location and page_index > 0:
			if not _safe_for_more_location_pages():
				break
			await _safe_pause(LOCATION_PAGE_PAUSE_SECONDS)
		var page_seen: Dictionary = {}
		var path_variant: Variant = dashboard.call("_grupo_rs_api_page_path", endpoint, current_skip, PAGE_SIZE)
		var response := await _read_one_get(dashboard, str(path_variant))
		if not bool(response.get("ok", false)):
			return {"usable": usable, "safe_for_polling": _safe_for_more_location_pages() and is_location}
		var body := str(response.get("body", "")).strip_edges()
		var payload: Variant = JSON.parse_string(body)
		if body == "" or payload == null:
			_inc("parse_errors")
			_fail("empty_or_invalid_json")
			return {"usable": usable, "safe_for_polling": false}
		var rows_variant: Variant = dashboard.call("_grupo_rs_api_extract_rows", payload)
		if typeof(rows_variant) != TYPE_ARRAY:
			_inc("parse_errors")
			_fail("rows_parse_failed")
			return {"usable": usable, "safe_for_polling": false}
		var rows := rows_variant as Array
		usable = true
		if is_location:
			_inc("location_pages")
			_inc("location_rows", rows.size())
			if rows.is_empty():
				_inc("empty_location_pages")
		else:
			_inc("vehicle_pages")
			_inc("vehicle_rows", rows.size())
			if rows.is_empty():
				_inc("empty_vehicle_pages")

		for raw_variant in rows:
			if typeof(raw_variant) != TYPE_DICTIONARY:
				_inc("parse_errors")
				continue
			if is_location:
				_process_location_row(dashboard, raw_variant as Dictionary, page_seen, cycle_seen)

		var pagination_variant: Variant = dashboard.call(
			"_grupo_rs_api_pagination_state", payload, current_skip, rows.size()
		)
		var pagination := pagination_variant as Dictionary if typeof(pagination_variant) == TYPE_DICTIONARY else {}
		if not bool(pagination.get("has_more", false)):
			break
		current_skip = int(pagination.get("next_skip", current_skip + PAGE_SIZE))
		page_index += 1

	return {"usable": usable, "safe_for_polling": _safe_for_more_location_pages() and is_location}


func _run_short_poll(dashboard: Node) -> void:
	for cycle in range(POLL_CYCLES):
		if risk_detected or not _safe_for_more_location_pages():
			return
		var page_seen: Dictionary = {}
		var cycle_seen: Dictionary = {}
		var path_variant: Variant = dashboard.call(
			"_grupo_rs_api_page_path", "/endpoints/localizacao.php", 0, PAGE_SIZE
		)
		var response := await _read_one_get(dashboard, str(path_variant))
		if not bool(response.get("ok", false)):
			return
		var body := str(response.get("body", "")).strip_edges()
		var payload: Variant = JSON.parse_string(body)
		if body == "" or payload == null:
			_inc("parse_errors")
			_fail("poll_empty_or_invalid_json")
			return
		var rows_variant: Variant = dashboard.call("_grupo_rs_api_extract_rows", payload)
		if typeof(rows_variant) != TYPE_ARRAY:
			_inc("parse_errors")
			_fail("poll_rows_parse_failed")
			return
		var rows := rows_variant as Array
		_inc("cycles")
		_inc("location_pages")
		_inc("location_rows", rows.size())
		if rows.is_empty():
			_inc("empty_location_pages")
		for raw_variant in rows:
			if typeof(raw_variant) == TYPE_DICTIONARY:
				_process_location_row(dashboard, raw_variant as Dictionary, page_seen, cycle_seen)
		if cycle < POLL_CYCLES - 1:
			await _safe_pause(POLL_INTERVAL_SECONDS)


func _process_location_row(dashboard: Node, raw_row: Dictionary, page_seen: Dictionary, cycle_seen: Dictionary) -> void:
	var normalized_variant: Variant = dashboard.call("_grupo_rs_api_normalize_location", raw_row)
	if typeof(normalized_variant) != TYPE_DICTIONARY:
		_inc("parse_errors")
		return
	var normalized := normalized_variant as Dictionary
	var identity := _stable_identity(normalized, raw_row)
	var payload_fingerprint := JSON.stringify(raw_row).sha256_text()
	if page_seen.has(identity):
		_inc("duplicates_within_page")
	else:
		page_seen[identity] = true
	if cycle_seen.has(identity):
		_inc("duplicates_within_cycle")
	else:
		cycle_seen[identity] = true
	queue_unique_ids[identity] = true
	metrics["queue_unique_count"] = queue_unique_ids.size()
	if last_payload_by_identity.has(identity) and str(last_payload_by_identity.get(identity, "")) == payload_fingerprint:
		_inc("same_payload_reobserved")
	last_payload_by_identity[identity] = payload_fingerprint

	var previous: Dictionary = previous_by_identity.get(identity, {}) as Dictionary
	var status: Dictionary = StatusScript.classify(normalized, previous)
	if previous.is_empty():
		_inc("new_targets")
	else:
		_inc("existing_targets_updated")
	previous_by_identity[identity] = status
	_aggregate_status(status)


func _aggregate_status(status: Dictionary) -> void:
	var color := str(status.get("color_key", ""))
	if color == "verde":
		_inc("green")
	elif color == "amarelo":
		_inc("yellow")
	elif color == "vermelho":
		_inc("red")
	elif color == "roxo":
		_inc("purple")
	var server_unix := int(status.get("server_unix", 0))
	var gps_unix := int(status.get("gps_unix", 0))
	_inc("server_present" if server_unix > 0 else "server_absent")
	_inc("gps_present" if gps_unix > 0 else "gps_absent")
	_inc("latest_comm_present" if server_unix > 0 else "latest_comm_absent")
	if bool(status.get("gps_issue", false)):
		_inc("gps_issue")
	if bool(status.get("repeated_coordinate", false)):
		_inc("repeated_coordinate")
	var coordinate_state := str(status.get("coordinate_state", ""))
	if coordinate_state == "missing":
		_inc("position_missing")
	elif coordinate_state == "invalid":
		_inc("position_invalid")
	var reason := _sanitized_reason(status)
	reason_counts[reason] = int(reason_counts.get(reason, 0)) + 1


func _sanitized_reason(status: Dictionary) -> String:
	var ignition_state := int(status.get("ignition_state", -1))
	var status_key := str(status.get("status_key", ""))
	if bool(status.get("repeated_coordinate", false)):
		return "gps_repetido"
	if bool(status.get("gps_issue", false)):
		if int(status.get("gps_unix", 0)) <= 0:
			return "gps_ausente"
		if int(status.get("gps_lag_seconds", -1)) > int(status.get("gps_lag_limit_seconds", 0)):
			return "gps_atrasado"
		return "gps_anormal"
	if ignition_state == 1 and status_key == "atualizado":
		return "ligado_recente"
	if ignition_state == 1 and status_key == "desatualizado":
		return "ligado_vencido"
	if ignition_state == 0 and status_key == "desligado":
		return "desligado_recente"
	if ignition_state == 0 and status_key == "desatualizado":
		return "desligado_vencido"
	return "ignicao_desconhecida"


func _stable_identity(normalized: Dictionary, raw_row: Dictionary) -> String:
	var parts: Array[String] = []
	for key in ["equipment_id", "vehicle_id", "serial", "plate", "client_id"]:
		var value := str(normalized.get(key, "")).strip_edges()
		if value != "":
			parts.append(key + "=" + value)
	if parts.is_empty():
		for key in ["numeroEquipamento", "codEquipamento", "numeroSerie", "placa", "id"]:
			var value := str(raw_row.get(key, "")).strip_edges()
			if value != "":
				parts.append(key + "=" + value)
	if parts.is_empty():
		parts.append(JSON.stringify(raw_row))
	return ("|".join(parts)).sha256_text()


func _read_one_get(dashboard: Node, path: String) -> Dictionary:
	in_flight += 1
	metrics["in_flight_max"] = maxi(int(metrics.get("in_flight_max", 0)), in_flight)
	var started := Time.get_ticks_msec()
	var response_variant: Variant = await dashboard.call("_grupo_rs_api_get", path, true, true)
	in_flight = maxi(in_flight - 1, 0)
	var elapsed := maxi(Time.get_ticks_msec() - started, 0)
	latencies_ms.append(elapsed)
	if elapsed >= LATENCY_RISK_MS:
		risk_detected = true
		_fail("latency_risk")
	var response := response_variant as Dictionary if typeof(response_variant) == TYPE_DICTIONARY else {}
	if bool(response.get("relogin_attempted", false)):
		_inc("reauth")
	var code := int(response.get("response_code", 0))
	if code == 401 or code == 403:
		_inc("auth_errors")
		if code == 403:
			_inc("permission_errors")
	elif code == 429:
		_inc("rate_limits")
	if bool(response.get("timeout", false)):
		_inc("timeouts")
	if not bool(response.get("ok", false)):
		_inc("http_errors")
		_fail("http_error")
	return response


func _safe_for_more_location_pages() -> bool:
	return not risk_detected and int(metrics.get("http_errors", 0)) == 0 and int(metrics.get("timeouts", 0)) == 0 and int(metrics.get("rate_limits", 0)) == 0 and _percentile(95) < SAFE_P95_MS


func _percentile(percent: int) -> int:
	if latencies_ms.is_empty():
		return 0
	var ordered := latencies_ms.duplicate()
	ordered.sort()
	var index := clampi(int(ceil((float(percent) / 100.0) * float(ordered.size()))) - 1, 0, ordered.size() - 1)
	return int(ordered[index])


func _safe_pause(seconds: float) -> void:
	if seconds > 0.0:
		await create_timer(seconds).timeout


func _frame_monitor() -> void:
	if frame_monitor_started:
		return
	frame_monitor_started = true
	while running:
		await process_frame
		var now := Time.get_ticks_msec()
		if last_frame_msec > 0:
			metrics["max_frame_gap_ms"] = maxi(int(metrics.get("max_frame_gap_ms", 0)), now - last_frame_msec)
		last_frame_msec = now


func _cleanup(dashboard: Node) -> void:
	running = false
	dashboard.set("grupo_rs_api_token", "")
	dashboard.set("grupo_rs_api_logged_in", false)
	dashboard.queue_free()
	await process_frame


func _finish(exit_code: int) -> void:
	print("INVENTORY_STOCK_LIVE_GATE_HARNESS=%s" % ("PASS" if exit_code == 0 else "FAIL"))
	print("pages location=%d vehicle=%d rows location=%d vehicle=%d cycles=%d in_flight_max=%d" % [metrics["location_pages"], metrics["vehicle_pages"], metrics["location_rows"], metrics["vehicle_rows"], metrics["cycles"], metrics["in_flight_max"]])
	print("states green=%d yellow=%d red=%d purple=%d server_present=%d server_absent=%d gps_present=%d gps_absent=%d" % [metrics["green"], metrics["yellow"], metrics["red"], metrics["purple"], metrics["server_present"], metrics["server_absent"], metrics["gps_present"], metrics["gps_absent"]])
	print("gps_issue=%d repeated_coordinate=%d position_missing=%d position_invalid=%d latest_comm_present=%d latest_comm_absent=%d" % [metrics["gps_issue"], metrics["repeated_coordinate"], metrics["position_missing"], metrics["position_invalid"], metrics["latest_comm_present"], metrics["latest_comm_absent"]])
	print("targets existing_updated=%d new=%d queue_unique=%d same_payload_reobserved=%d duplicates_within_page=%d duplicates_within_cycle=%d" % [metrics["existing_targets_updated"], metrics["new_targets"], metrics["queue_unique_count"], metrics["same_payload_reobserved"], metrics["duplicates_within_page"], metrics["duplicates_within_cycle"]])
	print("empty location=%d vehicle=%d parse_errors=%d http_errors=%d timeouts=%d auth_errors=%d permission_errors=%d rate_limits=%d reauth=%d" % [metrics["empty_location_pages"], metrics["empty_vehicle_pages"], metrics["parse_errors"], metrics["http_errors"], metrics["timeouts"], metrics["auth_errors"], metrics["permission_errors"], metrics["rate_limits"], metrics["reauth"]])
	print("latency_ms p50=%d p95=%d max_frame_gap=%d rebuilds_observed=%d" % [_percentile(50), _percentile(95), metrics["max_frame_gap_ms"], metrics["rebuilds_observed"]])
	print("reasons ligado_recente=%d ligado_vencido=%d desligado_recente=%d desligado_vencido=%d gps_atrasado=%d gps_ausente=%d gps_repetido=%d gps_anormal=%d" % [int(reason_counts.get("ligado_recente", 0)), int(reason_counts.get("ligado_vencido", 0)), int(reason_counts.get("desligado_recente", 0)), int(reason_counts.get("desligado_vencido", 0)), int(reason_counts.get("gps_atrasado", 0)), int(reason_counts.get("gps_ausente", 0)), int(reason_counts.get("gps_repetido", 0)), int(reason_counts.get("gps_anormal", 0))])
	quit(exit_code)


func _inc(key: String, amount: int = 1) -> void:
	metrics[key] = int(metrics.get(key, 0)) + amount


func _fail(category: String) -> void:
	if not failures.has(category):
		failures.append(category)
