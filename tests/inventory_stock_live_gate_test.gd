extends SceneTree

## Harness read-only do gate real do Estoque.
## Login e o unico POST; depois deste ponto o harness usa somente GET de negocio.
## Usa exclusivamente a sessao oficial e os dados da API do Estoque.

const DashboardScript := preload("res://tests/fixtures/live_inventory_dashboard_observer.gd")
var failures: Array[String] = []
var running := true
var frame_monitor_started := false
var last_frame_msec := 0
var max_frame_gap_ms := 0
var frame_gap_risk_count := 0
var report_metrics: Dictionary = {}
var report_key_families: Dictionary = {}
var report_transitions: Dictionary = {}
var report_latencies_ms: Array[int] = []
var report_page := 0
var report_filter := "all"
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard: Node = DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set_process(false)
	_frame_monitor()

	# A fixture carrega somente a lista de produtos visiveis; status e datas
	# continuam vindo exclusivamente da API oficial no ciclo de producao.
	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	var view_variant: Variant = dashboard.call("observer_prepare_visible_inventory")
	if typeof(view_variant) != TYPE_DICTIONARY or not bool((view_variant as Dictionary).get("ok", false)):
		_fail("visible_inventory_unavailable")
		_capture_observer_report(dashboard)
		await _cleanup(dashboard)
		_finish(2)
		return
	var firebase_variant: Variant = await dashboard.call("observer_load_firebase_products_read_only")
	if typeof(firebase_variant) != TYPE_DICTIONARY or not bool((firebase_variant as Dictionary).get("ok", false)):
		_fail("firebase_products_unavailable")
		_capture_observer_report(dashboard)
		await _cleanup(dashboard)
		_finish(2)
		return

	var credentials_variant: Variant = dashboard.call("_grupo_rs_api_credentials")
	if typeof(credentials_variant) != TYPE_DICTIONARY:
		_fail("credentials_unavailable")
		_capture_observer_report(dashboard)
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
		var observed_metrics: Variant = dashboard.get("observer_metrics")
		if typeof(observed_metrics) == TYPE_DICTIONARY:
			(observed_metrics as Dictionary)["auth_errors"] = int((observed_metrics as Dictionary).get("auth_errors", 0)) + 1
		_fail("login_failed")
		_capture_observer_report(dashboard)
		await _cleanup(dashboard)
		_finish(2)
		return

	dashboard.set("observer_active", true)
	dashboard.call("_refresh_table")
	await process_frame
	await process_frame
	var visible_products: Variant = dashboard.get("inventory_device_cycle_products")
	if typeof(visible_products) == TYPE_ARRAY:
		var observed_metrics: Variant = dashboard.get("observer_metrics")
		if typeof(observed_metrics) == TYPE_DICTIONARY:
			var visible_count := (visible_products as Array).size()
			(observed_metrics as Dictionary)["visible_products"] = visible_count
			if visible_count == 0:
				_fail("visible_products_empty")
	else:
		_fail("visible_products_unavailable")
	_capture_observer_report(dashboard)
	await _safe_pause(5.2)
	dashboard.call("_invalidate_visible_inventory_device_cycle")
	await process_frame
	await process_frame
	await process_frame

	_capture_observer_report(dashboard)
	await _cleanup(dashboard)
	_finish(1 if not failures.is_empty() else 0)


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
			# O gap de frame e observado apenas para detectar congelamento; nao e
			# misturado com latencia da API.
			var gap := now - last_frame_msec
			max_frame_gap_ms = maxi(max_frame_gap_ms, gap)
			if gap > 3000:
				frame_gap_risk_count += 1
				_fail("frame_gap_risk")
		last_frame_msec = now


func _cleanup(dashboard: Node) -> void:
	running = false
	dashboard.set("grupo_rs_api_token", "")
	dashboard.set("grupo_rs_api_logged_in", false)
	dashboard.queue_free()
	await process_frame


func _capture_observer_report(dashboard: Node) -> void:
	var raw_metrics: Variant = dashboard.get("observer_metrics")
	if typeof(raw_metrics) == TYPE_DICTIONARY:
		report_metrics = (raw_metrics as Dictionary).duplicate(true)
	var raw_families: Variant = dashboard.get("observer_key_family_counts")
	if typeof(raw_families) == TYPE_DICTIONARY:
		report_key_families = (raw_families as Dictionary).duplicate(true)
	var raw_transitions: Variant = dashboard.get("observer_transition_counts")
	if typeof(raw_transitions) == TYPE_DICTIONARY:
		report_transitions = (raw_transitions as Dictionary).duplicate(true)
	var raw_latencies: Variant = dashboard.get("observer_latencies_ms")
	if typeof(raw_latencies) == TYPE_ARRAY:
		report_latencies_ms = (raw_latencies as Array).duplicate()
	report_page = int(dashboard.get("table_current_page"))
	report_filter = str(dashboard.get("selected_status_filter_key"))


func _report_percentile(percent: int) -> int:
	if report_latencies_ms.is_empty():
		return 0
	var ordered := report_latencies_ms.duplicate()
	ordered.sort()
	var index := clampi(int(ceil((float(percent) / 100.0) * float(ordered.size()))) - 1, 0, ordered.size() - 1)
	return int(ordered[index])


func _finish(exit_code: int) -> void:
	print("INVENTORY_STOCK_LIVE_GATE_HARNESS=%s" % ("PASS" if exit_code == 0 else "FAIL"))
	print("trace page=%d page_size=10 filter=%s visible_products=%d api_rows=%d normalized_rows=%d valid=%d missing_position=%d invalid_position=%d" % [report_page, report_filter, int(report_metrics.get("visible_products", 0)), int(report_metrics.get("api_rows", 0)), int(report_metrics.get("normalized_rows", 0)), int(report_metrics.get("normalized_valid", 0)), int(report_metrics.get("position_missing", 0)), int(report_metrics.get("position_invalid", 0))])
	print("association matched_products=%d unmatched_rows=%d ambiguous_rows=%d equipment_only=%d cache_created=%d cache_changed=%d cache_unchanged=%d" % [int(report_metrics.get("matched_products", 0)), int(report_metrics.get("unmatched_rows", 0)), int(report_metrics.get("ambiguous_rows", 0)), int(report_metrics.get("equipment_only_identities", 0)), int(report_metrics.get("cache_created", 0)), int(report_metrics.get("cache_changed", 0)), int(report_metrics.get("cache_unchanged", 0))])
	print("classified=%d colors green=%d red=%d yellow=%d purple=%d status_updated=%d status_off=%d status_stale=%d server_present=%d server_absent=%d gps_present=%d gps_absent=%d gps_issue=%d repeated=%d signatures_changed=%d unchanged=%d" % [int(report_metrics.get("classified", 0)), int(report_metrics.get("green", 0)), int(report_metrics.get("red", 0)), int(report_metrics.get("yellow", 0)), int(report_metrics.get("purple", 0)), int(report_metrics.get("status_atualizado", 0)), int(report_metrics.get("status_desligado", 0)), int(report_metrics.get("status_desatualizado", 0)), int(report_metrics.get("server_present", 0)), int(report_metrics.get("server_absent", 0)), int(report_metrics.get("gps_present", 0)), int(report_metrics.get("gps_absent", 0)), int(report_metrics.get("gps_issue", 0)), int(report_metrics.get("repeated_coordinate", 0)), int(report_metrics.get("signatures_changed", 0)), int(report_metrics.get("signatures_unchanged", 0))])
	print("refresh requested=%d flushed=%d rows_updated=%d rows_redrawn=%d table_refreshes=%d incremental=%d full_rebuilds=%d" % [int(report_metrics.get("refresh_requested", 0)), int(report_metrics.get("refresh_flushed", 0)), int(report_metrics.get("rows_updated", 0)), int(report_metrics.get("rows_redrawn", 0)), int(report_metrics.get("table_refreshes", 0)), int(report_metrics.get("incremental_refreshes", 0)), int(report_metrics.get("full_rebuilds", 0))])
	print("keys serial=%d plate=%d vehicle_id=%d equipment_id=%d equipment_number=%d none=%d" % [int(report_key_families.get("serial", 0)), int(report_key_families.get("plate", 0)), int(report_key_families.get("vehicle_id", 0)), int(report_key_families.get("equipment_id", 0)), int(report_key_families.get("equipment_number", 0)), int(report_key_families.get("none", 0))])
	print("aliases server_present=%d server_absent=%d gps_present=%d gps_absent=%d ignition_present=%d ignition_absent=%d" % [int(report_metrics.get("server_alias_present", 0)), int(report_metrics.get("server_alias_absent", 0)), int(report_metrics.get("gps_alias_present", 0)), int(report_metrics.get("gps_alias_absent", 0)), int(report_metrics.get("ignition_alias_present", 0)), int(report_metrics.get("ignition_alias_absent", 0))])
	print("transitions none_green=%d none_red=%d none_yellow=%d none_purple=%d green_green=%d red_red=%d yellow_yellow=%d purple_purple=%d" % [int(report_transitions.get("none>verde", 0)), int(report_transitions.get("none>vermelho", 0)), int(report_transitions.get("none>amarelo", 0)), int(report_transitions.get("none>roxo", 0)), int(report_transitions.get("verde>verde", 0)), int(report_transitions.get("vermelho>vermelho", 0)), int(report_transitions.get("amarelo>amarelo", 0)), int(report_transitions.get("roxo>roxo", 0))])
	print("poll cycles=%d location_pages=%d in_flight_max=%d p50=%d p95=%d http_errors=%d timeouts=%d rate_limits=%d reauth=%d empty=%d duplicates_page=%d duplicates_cycle=%d queue_unique=%d same_payload=%d new_targets=%d existing_targets=%d" % [int(report_metrics.get("poll_cycles", 0)), int(report_metrics.get("location_pages", 0)), int(report_metrics.get("in_flight_max", 0)), _report_percentile(50), _report_percentile(95), int(report_metrics.get("http_errors", 0)), int(report_metrics.get("timeouts", 0)), int(report_metrics.get("rate_limits", 0)), int(report_metrics.get("reauth", 0)), int(report_metrics.get("empty_responses", 0)), int(report_metrics.get("duplicates_within_page", 0)), int(report_metrics.get("duplicates_within_cycle", 0)), int(report_metrics.get("queue_unique_count", 0)), int(report_metrics.get("same_payload_reobserved", 0)), int(report_metrics.get("new_targets", 0)), int(report_metrics.get("existing_targets_updated", 0))])
	print("runtime max_frame_gap_ms=%d freeze_risk=%d" % [max_frame_gap_ms, frame_gap_risk_count])
	quit(exit_code)
func _fail(category: String) -> void:
	if not failures.has(category):
		failures.append(category)
