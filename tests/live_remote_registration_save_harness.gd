extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


class SanitizedDashboard:
	extends DashboardScript

	var sanitized_log_count := 0
	var warning_count := 0
	var error_count := 0
	var last_warning_title := ""
	var last_error_title := ""

	func _log_system_action(_action: String, _details: String = "", _serial: String = "") -> void:
		sanitized_log_count += 1

	func _show_warning(title: String, _message: String) -> void:
		warning_count += 1
		last_warning_title = title

	func _show_error(title: String, _message: String) -> void:
		error_count += 1
		last_error_title = title

	func _show_error_dialog(_success: bool, _title: String, _message: String) -> void:
		pass

	func _show_success(_title: String, _message: String) -> void:
		pass


var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_environment("GRS_ALLOW_LIVE_WRITE_HARNESS").strip_edges() != "YES":
		_finish(2, {"stage": "guard", "reason": "live_write_harness_disabled"})
		return

	var serial := OS.get_environment("GRS_TEST_SERIAL").strip_edges()
	var chip := OS.get_environment("GRS_TEST_CHIP").strip_edges()
	if serial == "" or chip == "":
		_finish(2, {"stage": "input"})
		return

	var dashboard := SanitizedDashboard.new()
	root.add_child(dashboard)
	await process_frame

	var prepared := await _prepare_dashboard(dashboard)
	if not bool(prepared.get("ok", false)):
		_finish(2, {"stage": "prepare", "reason": str(prepared.get("reason", "")), "state": str(prepared.get("state", ""))})
		dashboard.queue_free()
		return

	var login := await _login_api(dashboard)
	if not bool(login.get("ok", false)):
		_finish(2, {"stage": "api_auth", "code": int(login.get("response_code", 0))})
		dashboard.queue_free()
		return

	var precheck := await _precheck_target(dashboard, serial, chip)
	if not bool(precheck.get("ok", false)):
		_finish(3, precheck)
		dashboard.queue_free()
		return

	var run_result := await _run_save_flow(dashboard, serial, precheck.get("chip", {}) as Dictionary)
	if not bool(run_result.get("ok", false)):
		_finish(4, run_result)
		dashboard.queue_free()
		return

	var local_database_confirm: Variant = await dashboard.call(
		"_ensure_local_database_modification_saved",
		serial,
		run_result.get("product", {}) as Dictionary
	)
	var passed := typeof(local_database_confirm) == TYPE_DICTIONARY and bool((local_database_confirm as Dictionary).get("ok", false))
	_finish(0 if passed else 5, {
		"stage": "final_confirm",
		"api_existing": bool(precheck.get("api_existing", false)),
		"queue_state": str(run_result.get("queue_state", "")),
		"local_database_ok": passed,
		"logs": int(dashboard.sanitized_log_count),
	})
	dashboard.queue_free()


func _prepare_dashboard(dashboard: Node) -> Dictionary:
	var config: Dictionary = dashboard.call("_branch_config", "imperatriz")
	if config.is_empty():
		return {"ok": false, "reason": "branch_config_unavailable"}
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
		return {"ok": false, "reason": "local_database_unavailable"}
	var refresh: Variant = {}
	var refresh_state := ""
	for attempt in range(6):
		refresh = await local_database_sync.call("refresh_remote")
		if typeof(refresh) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "local_database_refresh_invalid"}
		refresh_state = str((refresh as Dictionary).get("state", "")).to_lower()
		if bool((refresh as Dictionary).get("data_available", false)) or refresh_state == "synced":
			break
		if attempt < 5:
			await root.get_tree().create_timer(2.0).timeout
	if not bool((refresh as Dictionary).get("data_available", false)) and refresh_state != "synced":
		return {"ok": false, "reason": "local_database_not_synced", "state": refresh_state}
	return {"ok": true}


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


func _precheck_target(dashboard: Node, serial: String, chip: String) -> Dictionary:
	var chip_lookup: Variant = await dashboard.call("_lookup_registration_chip_parallel", chip)
	if typeof(chip_lookup) != TYPE_DICTIONARY or not bool((chip_lookup as Dictionary).get("ok", false)):
		return {"ok": false, "stage": "chip_lookup", "reason": str((chip_lookup as Dictionary).get("state", "unavailable")) if typeof(chip_lookup) == TYPE_DICTIONARY else "invalid"}
	var full_chip := str((chip_lookup as Dictionary).get("iccid", "")).strip_edges()
	var phone := str((chip_lookup as Dictionary).get("phone", "")).strip_edges()
	var apn := str((chip_lookup as Dictionary).get("apn", "")).strip_edges()
	var operator_name := str((chip_lookup as Dictionary).get("operator", "")).strip_edges()
	if full_chip == "" or phone == "" or apn == "" or operator_name == "":
		return {"ok": false, "stage": "chip_lookup", "reason": "incomplete_chip_identity"}

	var equipment: Variant = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
	if typeof(equipment) != TYPE_DICTIONARY:
		return {"ok": false, "stage": "api_equipment", "reason": "invalid_response"}
	if bool((equipment as Dictionary).get("ok", false)):
		var matches: bool = dashboard.call("_grupo_rs_api_equipment_row_matches_request", (equipment as Dictionary).get("row", {}) as Dictionary, {
			"serial": serial,
			"chip_number": full_chip,
			"phone": phone,
			"apn": apn,
			"operator": operator_name,
		})
		if not matches:
			return {"ok": false, "stage": "api_equipment", "reason": "existing_remote_conflict"}
	elif not bool((equipment as Dictionary).get("not_found", false)):
		return {"ok": false, "stage": "api_equipment", "reason": "lookup_failed", "code": int((equipment as Dictionary).get("response_code", 0))}

	var existing_local: Dictionary = dashboard.get("store").get_product(serial.to_upper())
	if not existing_local.is_empty():
		return {"ok": false, "stage": "local_database_precheck", "reason": "local_or_remote_record_already_exists"}

	var local_database_sync: Node = dashboard.call("_local_database_sync")
	var remote_existing: Variant = await local_database_sync.call("verify_product_persisted", serial, {"sku": serial.to_upper(), "imei": serial})
	if typeof(remote_existing) == TYPE_DICTIONARY and bool((remote_existing as Dictionary).get("ok", false)):
		return {"ok": false, "stage": "local_database_precheck", "reason": "remote_record_already_exists"}

	return {
		"ok": true,
		"api_existing": bool((equipment as Dictionary).get("ok", false)),
		"chip": chip_lookup,
	}


func _run_save_flow(dashboard: Node, serial: String, chip_data: Dictionary) -> Dictionary:
	var request := {
		"local_sku": serial.to_upper(),
		"serial": serial,
		"plate": "",
		"client": "",
		"vehicle_type": "",
		"associate_vehicle": false,
		"chip_number": str(chip_data.get("iccid", "")),
		"phone": str(chip_data.get("phone", "")),
		"apn": str(chip_data.get("apn", "")).to_lower(),
		"model": "RS Novo",
		"operator": str(chip_data.get("operator", "")),
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
		"model": "RS Novo",
		"operator": str(request.get("operator", "")),
		"plate": "",
		"client": "",
		"tracker_status": "Estoque",
		"status": "Estoque",
		"name": "Teste controlado",
		"category": "RS Novo",
		"location": "Estoque",
		"unit": "un",
		"stock": 1,
		"min_stock": 0,
		"cost": 0.0,
		"remote_registration_status": "pendente",
		"notes": "Teste controlado sanitizado",
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
		return {"ok": false, "stage": "queue", "queue_state": state}
	var saved: Dictionary = dashboard.get("store").get_product(serial.to_upper())
	if saved.is_empty():
		return {"ok": false, "stage": "local_store", "reason": "product_missing"}
	return {"ok": true, "queue_state": state, "product": saved}


func _queue_item(queue: Node, queue_id: String) -> Dictionary:
	for item in queue.get("items"):
		if str(item.get("id", "")) == queue_id:
			return item as Dictionary
	return {}


func _finish(exit_code: int, metrics: Dictionary) -> void:
	print("LIVE_REMOTE_REGISTRATION_SAVE_HARNESS=%s" % ("PASS" if exit_code == 0 else "BLOCKED_OR_FAIL"))
	print("stage=%s api_existing=%s queue_state=%s local_database_ok=%s sanitized_logs=%d code=%d state=%s reason=%s" % [
		str(metrics.get("stage", "complete")),
		str(metrics.get("api_existing", false)),
		str(metrics.get("queue_state", "")),
		str(metrics.get("local_database_ok", false)),
		int(metrics.get("logs", 0)),
		int(metrics.get("code", 0)),
		str(metrics.get("state", "")),
		str(metrics.get("reason", "")),
	])
	quit(exit_code)
