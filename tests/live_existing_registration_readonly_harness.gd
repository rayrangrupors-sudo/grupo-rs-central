extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


class ReadOnlyDashboard:
	extends DashboardScript

	func _log_system_action(_action: String, _details: String = "", _serial: String = "") -> void:
		pass

	func _show_warning(_title: String, _message: String) -> void:
		pass

	func _show_error(_title: String, _message: String) -> void:
		pass

	func _show_success(_title: String, _message: String) -> void:
		pass

	func _show_error_dialog(_success: bool, _title: String, _message: String) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var serial := OS.get_environment("GRS_READONLY_SERIAL").strip_edges()
	var plate := OS.get_environment("GRS_READONLY_PLATE").strip_edges()
	var chip := OS.get_environment("GRS_READONLY_CHIP").strip_edges()
	if serial == "" or plate == "" or chip == "":
		_finish(2, {"stage": "input", "reason": "missing_env"})
		return

	var dashboard := ReadOnlyDashboard.new()
	root.add_child(dashboard)
	await process_frame
	var prepared := await _prepare_dashboard(dashboard)
	if not bool(prepared.get("ok", false)):
		_finish(2, prepared)
		dashboard.queue_free()
		return

	var login := await _login_api(dashboard)
	if not bool(login.get("ok", false)):
		_finish(2, {"stage": "api_auth", "api_ok": false, "code": int(login.get("response_code", 0))})
		dashboard.queue_free()
		return

	var result := await _read_only_checks(dashboard, serial, plate, chip)
	_finish(0 if bool(result.get("ok", false)) else 3, result)
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
	var StoreScript := load("res://src/inventory_store.gd")
	var store: Variant = StoreScript.new()
	store.configure(
		str(config.get("db_path", "")),
		str(config.get("backup_name", "")),
		str(config.get("backup_dir", "")),
		true
	)
	store.load_db()
	dashboard.set("store", store)
	var local_database_sync: Node = dashboard.call("_local_database_sync")
	if local_database_sync != null:
		local_database_sync.call("bind_store", store, "imperatriz")
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


func _read_only_checks(dashboard: Node, serial: String, plate: String, chip: String) -> Dictionary:
	var equipment: Variant = await dashboard.call("_grupo_rs_api_find_equipment", serial, true)
	var equipment_ok := typeof(equipment) == TYPE_DICTIONARY and bool((equipment as Dictionary).get("ok", false))
	var equipment_matches := false
	if equipment_ok:
		equipment_matches = bool(dashboard.call(
			"_grupo_rs_api_equipment_row_matches_request",
			(equipment as Dictionary).get("row", {}) as Dictionary,
			{"serial": serial, "chip_number": chip}
		))

	var vehicle: Variant = await dashboard.call("_grupo_rs_api_find_vehicle", plate, serial, true, false)
	var vehicle_ok := typeof(vehicle) == TYPE_DICTIONARY and bool((vehicle as Dictionary).get("ok", false))
	var vehicle_row: Dictionary = (vehicle as Dictionary).get("row", {}) as Dictionary if vehicle_ok else {}
	var vehicle_matches := false
	if vehicle_ok:
		var normalized_plate := str(dashboard.call("_normalize_location_plate", plate))
		var normalized_row_plate := str(dashboard.call("_normalize_location_plate", str(vehicle_row.get("plate", ""))))
		var row_serial := str(vehicle_row.get("serial", "")).strip_edges()
		vehicle_matches = normalized_plate == normalized_row_plate and (row_serial == "" or str(dashboard.call("_search_key", row_serial)) == str(dashboard.call("_search_key", serial)))

	var vehicle_full: Variant = await dashboard.call("_grupo_rs_api_find_vehicle", plate, serial, true, true)
	var vehicle_full_ok := typeof(vehicle_full) == TYPE_DICTIONARY and bool((vehicle_full as Dictionary).get("ok", false))
	var vehicle_full_matches := false
	if vehicle_full_ok:
		vehicle_full_matches = _vehicle_matches(dashboard, (vehicle_full as Dictionary).get("row", {}) as Dictionary, serial, plate)

	var location: Variant = await dashboard.call("_grupo_rs_api_find_location", serial, plate, "", true)
	var location_ok := typeof(location) == TYPE_DICTIONARY and bool((location as Dictionary).get("ok", false)) and not bool((location as Dictionary).get("not_found", false))
	var location_matches := false
	if location_ok:
		location_matches = _location_matches(dashboard, (location as Dictionary).get("location", {}) as Dictionary, serial, plate)

	var chip_lookup: Variant = await dashboard.call("_lookup_registration_chip_parallel", chip)
	var chip_ok := typeof(chip_lookup) == TYPE_DICTIONARY and bool((chip_lookup as Dictionary).get("ok", false))
	var chip_matches := false
	if chip_ok:
		var lookup_chip := str((chip_lookup as Dictionary).get("iccid", "")).strip_edges()
		chip_matches = lookup_chip.ends_with(chip) or chip.ends_with(lookup_chip)

	var local_database_sync: Node = dashboard.call("_local_database_sync")
	var local_database_checked := false
	var local_database_found := false
	var local_database_matches := false
	if local_database_sync != null:
		var local_database_found_result: Variant = await local_database_sync.call("verify_product_persisted", serial, {"sku": serial, "imei": serial})
		local_database_checked = typeof(local_database_found_result) == TYPE_DICTIONARY
		local_database_found = local_database_checked and bool((local_database_found_result as Dictionary).get("ok", false))
		var local_database_match_result: Variant = await local_database_sync.call("verify_product_persisted", serial, {"sku": serial, "imei": serial, "plate": plate})
		local_database_matches = typeof(local_database_match_result) == TYPE_DICTIONARY and bool((local_database_match_result as Dictionary).get("ok", false))

	var local_database_family := await _local_database_family_scan(dashboard, local_database_sync, serial, plate, chip)
	var local_family := _local_family_scan(dashboard, serial, plate, chip)

	return {
		"ok": equipment_ok and equipment_matches and (vehicle_ok or vehicle_full_ok or location_ok) and chip_ok and chip_matches and (local_database_found or bool(local_database_family.get("serial", false))),
		"stage": "readonly_checks",
		"api_equipment_found": equipment_ok,
		"api_equipment_matches": equipment_matches,
		"api_vehicle_found": vehicle_ok,
		"api_vehicle_matches": vehicle_matches,
		"api_vehicle_full_found": vehicle_full_ok,
		"api_vehicle_full_matches": vehicle_full_matches,
		"api_location_found": location_ok,
		"api_location_matches": location_matches,
		"chip_found": chip_ok,
		"chip_matches": chip_matches,
		"local_database_checked": local_database_checked,
		"local_database_record_found": local_database_found,
		"local_database_record_matches": local_database_matches,
		"local_database_family_serial": bool(local_database_family.get("serial", false)),
		"local_database_family_plate": bool(local_database_family.get("plate", false)),
		"local_database_family_chip": bool(local_database_family.get("chip", false)),
		"local_family_serial": bool(local_family.get("serial", false)),
		"local_family_plate": bool(local_family.get("plate", false)),
		"local_family_chip": bool(local_family.get("chip", false)),
	}


func _vehicle_matches(dashboard: Node, row: Dictionary, serial: String, plate: String) -> bool:
	if row.is_empty():
		return false
	var normalized_plate := str(dashboard.call("_normalize_location_plate", plate))
	var normalized_row_plate := str(dashboard.call("_normalize_location_plate", str(row.get("plate", ""))))
	var row_serial := str(row.get("serial", "")).strip_edges()
	var serial_ok := row_serial == "" or str(dashboard.call("_search_key", row_serial)) == str(dashboard.call("_search_key", serial))
	return normalized_plate == normalized_row_plate and serial_ok


func _location_matches(dashboard: Node, row: Dictionary, serial: String, plate: String) -> bool:
	if row.is_empty():
		return false
	var serial_key := str(dashboard.call("_search_key", serial))
	var plate_key := str(dashboard.call("_normalize_location_plate", plate))
	var row_serial := str(dashboard.call("_search_key", str(row.get("serial", ""))))
	var row_plate := str(dashboard.call("_normalize_location_plate", str(row.get("plate", ""))))
	return (serial_key != "" and row_serial == serial_key) or (plate_key != "" and row_plate == plate_key)


func _local_database_family_scan(dashboard: Node, local_database_sync: Node, serial: String, plate: String, chip: String) -> Dictionary:
	var result := {"serial": false, "plate": false, "chip": false}
	if local_database_sync == null:
		return result
	var response: Variant = await local_database_sync.call("_database_request", HTTPClient.METHOD_GET, "branches/imperatriz/records/products")
	if typeof(response) != TYPE_DICTIONARY or not bool((response as Dictionary).get("ok", false)):
		return result
	var data: Variant = (response as Dictionary).get("data")
	if typeof(data) != TYPE_DICTIONARY:
		return result
	for key in (data as Dictionary).keys():
		var raw_product: Variant = (data as Dictionary).get(key)
		if typeof(raw_product) != TYPE_DICTIONARY:
			continue
		_apply_family_matches(result, dashboard, raw_product as Dictionary, serial, plate, chip)
		if bool(result.get("serial", false)) and bool(result.get("plate", false)) and bool(result.get("chip", false)):
			break
	return result


func _local_family_scan(dashboard: Node, serial: String, plate: String, chip: String) -> Dictionary:
	var result := {"serial": false, "plate": false, "chip": false}
	var store: Variant = dashboard.get("store")
	if store == null or not store.has_method("get_products"):
		return result
	var products: Array = store.call("get_products", "", "all", false)
	for raw_product in products:
		if typeof(raw_product) != TYPE_DICTIONARY:
			continue
		_apply_family_matches(result, dashboard, raw_product as Dictionary, serial, plate, chip)
		if bool(result.get("serial", false)) and bool(result.get("plate", false)) and bool(result.get("chip", false)):
			break
	return result


func _apply_family_matches(result: Dictionary, dashboard: Node, product: Dictionary, serial: String, plate: String, chip: String) -> void:
	var serial_key := str(dashboard.call("_search_key", serial))
	var plate_key := str(dashboard.call("_normalize_location_plate", plate))
	var chip_key := _digits(chip)
	for field in ["sku", "imei", "equipment_number", "serial", "numeroSerie", "numero_serie", "numeroEquipamento", "numero_equipamento"]:
		if serial_key != "" and str(dashboard.call("_search_key", str(product.get(field, "")))) == serial_key:
			result["serial"] = true
	for field in ["plate", "placa", "vehicle_plate"]:
		if plate_key != "" and str(dashboard.call("_normalize_location_plate", str(product.get(field, "")))) == plate_key:
			result["plate"] = true
	for field in ["chip_number", "chip", "iccid", "numero_chip"]:
		var candidate := _digits(str(product.get(field, "")))
		if chip_key != "" and candidate != "" and (candidate == chip_key or candidate.ends_with(chip_key) or chip_key.ends_with(candidate)):
			result["chip"] = true


func _digits(value: String) -> String:
	var out := ""
	for index in value.length():
		var character := value[index]
		if character >= "0" and character <= "9":
			out += character
	return out


func _finish(exit_code: int, metrics: Dictionary) -> void:
	print("LIVE_EXISTING_REGISTRATION_READONLY_HARNESS=%s" % ("PASS" if exit_code == 0 else "CHECK_FAILED"))
	print("stage=%s api_equipment_found=%s api_equipment_matches=%s api_vehicle_found=%s api_vehicle_matches=%s api_vehicle_full_found=%s api_vehicle_full_matches=%s api_location_found=%s api_location_matches=%s chip_found=%s chip_matches=%s local_database_checked=%s local_database_record_found=%s local_database_record_matches=%s local_database_family_serial_state=%s local_database_family_plate_state=%s local_database_family_chip_state=%s local_family_serial_state=%s local_family_plate_state=%s local_family_chip_state=%s code=%d reason=%s" % [
		str(metrics.get("stage", "")),
		str(metrics.get("api_equipment_found", false)),
		str(metrics.get("api_equipment_matches", false)),
		str(metrics.get("api_vehicle_found", false)),
		str(metrics.get("api_vehicle_matches", false)),
		str(metrics.get("api_vehicle_full_found", false)),
		str(metrics.get("api_vehicle_full_matches", false)),
		str(metrics.get("api_location_found", false)),
		str(metrics.get("api_location_matches", false)),
		str(metrics.get("chip_found", false)),
		str(metrics.get("chip_matches", false)),
		str(metrics.get("local_database_checked", false)),
		str(metrics.get("local_database_record_found", false)),
		str(metrics.get("local_database_record_matches", false)),
		str(metrics.get("local_database_family_serial", false)),
		str(metrics.get("local_database_family_plate", false)),
		str(metrics.get("local_database_family_chip", false)),
		str(metrics.get("local_family_serial", false)),
		str(metrics.get("local_family_plate", false)),
		str(metrics.get("local_family_chip", false)),
		int(metrics.get("code", 0)),
		str(metrics.get("reason", "")),
	])
	quit(exit_code)
