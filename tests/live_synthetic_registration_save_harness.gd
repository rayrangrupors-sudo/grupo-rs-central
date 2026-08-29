extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


class SanitizedDashboard:
	extends DashboardScript

	var sanitized_log_count := 0
	var warning_count := 0
	var error_count := 0

	func _log_system_action(_action: String, _details: String = "", _serial: String = "") -> void:
		sanitized_log_count += 1

	func _show_warning(_title: String, _message: String) -> void:
		warning_count += 1

	func _show_error(_title: String, _message: String) -> void:
		error_count += 1

	func _show_error_dialog(_success: bool, _title: String, _message: String) -> void:
		pass

	func _show_success(_title: String, _message: String) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_environment("GRS_ALLOW_LIVE_WRITE_HARNESS").strip_edges() != "YES":
		_finish(2, {"stage": "guard", "reason": "live_write_harness_disabled"})
		return

	var dashboard := SanitizedDashboard.new()
	root.add_child(dashboard)
	await process_frame

	var prepared := await _prepare_dashboard(dashboard)
	if not bool(prepared.get("ok", false)):
		_finish(2, prepared, dashboard)
		dashboard.queue_free()
		return

	var login := await _login_api(dashboard)
	if not bool(login.get("ok", false)):
		_finish(2, {"stage": "api_auth", "code": int(login.get("response_code", 0))}, dashboard)
		dashboard.queue_free()
		return

	var candidate := await _prepare_unique_candidate(dashboard)
	if not bool(candidate.get("ok", false)):
		_finish(3, candidate, dashboard)
		dashboard.queue_free()
		return

	var run_result := await _run_save_flow(dashboard, candidate)
	if not bool(run_result.get("ok", false)):
		_finish(4, run_result, dashboard)
		dashboard.queue_free()
		return

	var serial := str(candidate.get("serial", ""))
	var expected_product := run_result.get("product", {}) as Dictionary
	var api_confirm: Variant = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
	var api_ok := typeof(api_confirm) == TYPE_DICTIONARY and bool((api_confirm as Dictionary).get("ok", false))
	var local_database_sync: Node = dashboard.call("_local_database_sync")
	var local_database_confirm: Variant = await local_database_sync.call("verify_product_persisted", serial, expected_product) if local_database_sync != null else {}
	var local_database_ok := typeof(local_database_confirm) == TYPE_DICTIONARY and bool((local_database_confirm as Dictionary).get("ok", false))
	var remote_read_ok := api_ok and local_database_ok
	_finish(0 if remote_read_ok else 5, {
		"stage": "final_confirm",
		"api_ok": api_ok,
		"queue_state": str(run_result.get("queue_state", "")),
		"local_database_ok": local_database_ok,
		"remote_read_ok": remote_read_ok,
		"precheck_passed": true,
	}, dashboard)
	dashboard.queue_free()


func _prepare_dashboard(dashboard: Node) -> Dictionary:
	var config: Dictionary = dashboard.call("_branch_config", "imperatriz")
	if config.is_empty():
		return {"ok": false, "stage": "prepare", "reason": "branch_config_unavailable"}
	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", str(config.get("grupo_rs_base_url", "")))
	dashboard.set("selected_branch_grupo_rs_platform_url", str(config.get("grupo_rs_base_url", "")))
	dashboard.set("selected_branch_db_path", str(config.get("db_path", "")))
	dashboard.set("selected_branch_backup_name", str(config.get("backup_name", "")))
	dashboard.set("selected_branch_backup_dir", str(config.get("backup_dir", "")))
	dashboard.call("_open_selected_branch")
	await process_frame
	await process_frame
	var local_database_sync: Node = dashboard.call("_local_database_sync")
	if local_database_sync == null:
		return {"ok": false, "stage": "prepare", "reason": "local_database_unavailable"}
	var refresh: Variant = {}
	var refresh_state := ""
	for attempt in range(6):
		refresh = await local_database_sync.call("refresh_remote")
		if typeof(refresh) != TYPE_DICTIONARY:
			return {"ok": false, "stage": "prepare", "reason": "local_database_refresh_invalid"}
		refresh_state = str((refresh as Dictionary).get("state", "")).to_lower()
		if bool((refresh as Dictionary).get("data_available", false)) or refresh_state == "synced":
			break
		if attempt < 5:
			await root.get_tree().create_timer(2.0).timeout
	if not bool((refresh as Dictionary).get("data_available", false)) and refresh_state != "synced":
		return {"ok": false, "stage": "prepare", "reason": "local_database_not_synced", "state": refresh_state}
	return {"ok": true, "stage": "prepare"}


func _login_api(dashboard: Node) -> Dictionary:
	var credentials: Variant = dashboard.call("_grupo_rs_api_credentials")
	if typeof(credentials) != TYPE_DICTIONARY:
		return {"ok": false, "stage": "credentials"}
	var login: Variant = await dashboard.call(
		"_grupo_rs_api_login_with_credentials",
		str((credentials as Dictionary).get("username", "")),
		str((credentials as Dictionary).get("password", ""))
	)
	return login if typeof(login) == TYPE_DICTIONARY else {"ok": false, "stage": "login_invalid"}


func _prepare_unique_candidate(dashboard: Node) -> Dictionary:
	for attempt in range(5):
		var candidate := _synthetic_candidate(attempt)
		var precheck := await _precheck_candidate(dashboard, candidate)
		if bool(precheck.get("ok", false)):
			candidate["ok"] = true
			candidate["stage"] = "precheck"
			return candidate
		if str(precheck.get("reason", "")) != "conflict":
			return precheck
	return {"ok": false, "stage": "precheck", "reason": "unique_candidate_unavailable"}


func _synthetic_candidate(offset: int) -> Dictionary:
	var seed := int(Time.get_unix_time_from_system()) + offset
	var serial := "99%07d" % (seed % 10000000)
	var chip := "89550099%010d" % (seed % 10000000000)
	var phone := "999%08d" % (seed % 100000000)
	return {
		"serial": serial,
		"chip_number": chip,
		"phone": phone,
		"apn": "hinova.br",
		"operator": "TIM",
		"model": "RS Novo",
	}


func _precheck_candidate(dashboard: Node, candidate: Dictionary) -> Dictionary:
	var serial := str(candidate.get("serial", ""))
	var chip := str(candidate.get("chip_number", ""))
	var equipment: Variant = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
	if typeof(equipment) != TYPE_DICTIONARY:
		return {"ok": false, "stage": "precheck", "reason": "api_equipment_invalid"}
	if bool((equipment as Dictionary).get("ok", false)):
		return {"ok": false, "stage": "precheck", "reason": "conflict", "api_conflict": true}
	if not bool((equipment as Dictionary).get("not_found", false)):
		return {"ok": false, "stage": "precheck", "reason": "api_lookup_failed", "code": int((equipment as Dictionary).get("response_code", 0))}

	var store: Variant = dashboard.get("store")
	if store != null and store.has_method("get_product"):
		var local_existing: Dictionary = store.call("get_product", serial.to_upper())
		if not local_existing.is_empty():
			return {"ok": false, "stage": "precheck", "reason": "conflict", "local_conflict": true}

	var local_database_sync: Node = dashboard.call("_local_database_sync")
	if local_database_sync != null:
		var remote_existing: Variant = await local_database_sync.call("verify_product_persisted", serial, {"sku": serial.to_upper(), "imei": serial, "chip_number": chip})
		if typeof(remote_existing) == TYPE_DICTIONARY and bool((remote_existing as Dictionary).get("ok", false)):
			return {"ok": false, "stage": "precheck", "reason": "conflict", "local_database_conflict": true}
	return {"ok": true, "stage": "precheck"}


func _run_save_flow(dashboard: Node, candidate: Dictionary) -> Dictionary:
	var serial := str(candidate.get("serial", ""))
	var request := {
		"local_sku": serial.to_upper(),
		"serial": serial,
		"plate": "",
		"client": "",
		"vehicle_type": "",
		"associate_vehicle": false,
		"chip_number": str(candidate.get("chip_number", "")),
		"phone": str(candidate.get("phone", "")),
		"apn": str(candidate.get("apn", "")),
		"model": str(candidate.get("model", "")),
		"operator": str(candidate.get("operator", "")),
		"tracker_status": "Estoque",
		"equipment_only": true,
		"clear_vehicle_fields": false,
	}
	var product := {
		"sku": serial.to_upper(),
		"imei": serial,
		"equipment_number": serial,
		"apn": str(request.get("apn", "")),
		"chip_number": str(request.get("chip_number", "")),
		"chip_phone": str(request.get("phone", "")),
		"model": str(request.get("model", "")),
		"operator": str(request.get("operator", "")),
		"plate": "",
		"client": "",
		"tracker_status": "Estoque",
		"status": "Estoque",
		"name": "TESTE FICTICIO CODEX",
		"category": "RS Novo",
		"location": "Estoque",
		"unit": "un",
		"stock": 1,
		"min_stock": 0,
		"cost": 0.0,
		"remote_registration_status": "pendente",
		"notes": "TESTE FICTICIO CODEX - MANTER ATE AUTORIZACAO DE REMOCAO",
	}
	var queue: Node = dashboard.get("remote_queue_controller")
	if queue == null:
		return {"ok": false, "stage": "queue", "reason": "queue_unavailable"}
	var queue_id: String = queue.call("enqueue", "Cadastro", product, request)
	if queue_id == "":
		return {"ok": false, "stage": "queue", "reason": "enqueue_rejected"}
	var deadline := Time.get_ticks_msec() + 90000
	var item: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		await root.get_tree().create_timer(0.25).timeout
		item = _queue_item(queue, queue_id)
		if not queue.get("active").has(queue_id):
			break
	if item.is_empty():
		return {"ok": false, "stage": "queue", "reason": "item_missing"}
	var state := str(item.get("state", ""))
	if state != "success":
		return {"ok": false, "stage": "queue", "queue_state": state, "reason": "queue_not_success"}
	var saved: Dictionary = dashboard.get("store").get_product(serial.to_upper())
	if saved.is_empty():
		return {"ok": false, "stage": "local_store", "reason": "product_missing"}
	return {"ok": true, "stage": "queue", "queue_state": state, "product": saved}


func _queue_item(queue: Node, queue_id: String) -> Dictionary:
	for item in queue.get("items"):
		if str(item.get("id", "")) == queue_id:
			return item as Dictionary
	return {}


func _finish(exit_code: int, metrics: Dictionary, dashboard: SanitizedDashboard = null) -> void:
	var log_count := int(dashboard.sanitized_log_count) if dashboard != null else 0
	var warning_count := int(dashboard.warning_count) if dashboard != null else 0
	var error_count := int(dashboard.error_count) if dashboard != null else 0
	print("LIVE_SYNTHETIC_REGISTRATION_SAVE_HARNESS=%s" % ("PASS" if exit_code == 0 else "BLOCKED_OR_FAIL"))
	print("stage=%s precheck_passed=%s api_ok=%s queue_state=%s local_database_ok=%s remote_read_ok=%s sanitized_logs=%d warnings=%d errors=%d code=%d state=%s reason=%s" % [
		str(metrics.get("stage", "")),
		str(metrics.get("precheck_passed", false)),
		str(metrics.get("api_ok", false)),
		str(metrics.get("queue_state", "")),
		str(metrics.get("local_database_ok", false)),
		str(metrics.get("remote_read_ok", false)),
		log_count,
		warning_count,
		error_count,
		int(metrics.get("code", 0)),
		str(metrics.get("state", "")),
		str(metrics.get("reason", "")),
	])
	quit(exit_code)
