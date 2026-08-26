extends "res://src/inventory_dashboard.gd"

## Observador exclusivamente test-only. A decisao de associacao/classificacao
## continua sendo executada pelos metodos da producao via super.

var observer_active := false
var observer_in_flight := 0
var observer_latencies_ms: Array[int] = []
var observer_pending_signatures: Dictionary = {}
var observer_seen_cycle: Dictionary = {}
var observer_last_payload_by_identity: Dictionary = {}
var observer_queue_unique: Dictionary = {}
var observer_page_matched := 0
var observer_metrics: Dictionary = {
	"api_rows": 0, "normalized_rows": 0, "normalized_valid": 0,
	"position_missing": 0, "position_invalid": 0,
	"visible_products": 0, "matched_products": 0, "unmatched_rows": 0,
	"ambiguous_rows": 0, "equipment_only_identities": 0,
	"cache_created": 0, "cache_changed": 0, "cache_unchanged": 0,
	"classified": 0, "green": 0, "red": 0, "yellow": 0, "purple": 0,
	"signatures_changed": 0, "signatures_unchanged": 0,
	"refresh_requested": 0, "refresh_flushed": 0,
	"rows_updated": 0, "rows_redrawn": 0,
	"table_refreshes": 0, "incremental_refreshes": 0,
	"full_rebuilds": 0, "location_pages": 0, "poll_cycles": 0,
	"duplicates_within_page": 0, "duplicates_within_cycle": 0,
	"existing_targets_updated": 0, "new_targets": 0,
	"queue_unique_count": 0, "same_payload_reobserved": 0,
	"in_flight_max": 0, "http_errors": 0, "timeouts": 0, "rate_limits": 0,
	"reauth": 0, "empty_responses": 0,
	"server_present": 0, "server_absent": 0, "gps_present": 0, "gps_absent": 0,
	"latest_comm_present": 0, "latest_comm_absent": 0, "gps_issue": 0,
	"repeated_coordinate": 0, "status_atualizado": 0, "status_desligado": 0,
	"status_desatualizado": 0,
	"serial_keys": 0, "plate_keys": 0, "vehicle_id_keys": 0,
	"equipment_id_keys": 0, "equipment_number_keys": 0, "none_keys": 0,
	"server_alias_present": 0, "server_alias_absent": 0,
	"gps_alias_present": 0, "gps_alias_absent": 0,
	"ignition_alias_present": 0, "ignition_alias_absent": 0
}
var observer_key_family_counts: Dictionary = {}
var observer_transition_counts: Dictionary = {}


func _ready() -> void:
	vehicle_location_integration = VehicleLocationIntegration.new()


func _schedule_sga_status_for_products(_products: Array[Dictionary]) -> void:
	# Impede consultas de outras areas durante este observador do Estoque.
	return


func observer_prepare_visible_inventory() -> Dictionary:
	var config := _branch_config("imperatriz")
	if config.is_empty():
		return {"ok": false, "reason": "branch_config_unavailable"}
	selected_branch_id = "imperatriz"
	selected_branch_grupo_rs_mode = "modern"
	selected_branch_grupo_rs_base_url = str(config.get("grupo_rs_base_url", GRUPO_RS_BASE_URL))
	selected_branch_grupo_rs_platform_url = selected_branch_grupo_rs_base_url
	selected_status_filter_key = "all"
	table_current_page = 0
	store = StoreScript.new()
	store.configure(
		str(config.get("db_path", "")),
		str(config.get("backup_name", "")),
		str(config.get("backup_dir", "")),
		true
	)
	store.load_db()
	online_data_available = true
	online_services_initialized = true
	current_section = "inventory"
	_build_ui()
	_set_page_context("inventory", "Estoque de equipamentos", "Observacao test-only")
	_set_content_margins(22, 16, 22, 14)
	_set_content(_build_list_view())
	return {"ok": is_instance_valid(table_body)}


func observer_load_firebase_products_read_only() -> Dictionary:
	var firebase_sync := _firebase_sync()
	if firebase_sync == null:
		return {"ok": false, "reason": "firebase_unavailable"}
	# Usa somente a leitura da filial. Nao chama refresh_remote(), pois essa
	# rotina tambem executa a verificacao de conectividade com escrita.
	var response_variant: Variant = await firebase_sync.call(
		"_database_request",
		HTTPClient.METHOD_GET,
		"branches/%s" % selected_branch_id
	)
	if typeof(response_variant) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "firebase_response_invalid"}
	var response := response_variant as Dictionary
	if not bool(response.get("ok", false)):
		return {"ok": false, "reason": "firebase_read_failed"}
	var snapshot_variant: Variant = firebase_sync.call("_decode_remote_snapshot", response.get("data", null))
	if typeof(snapshot_variant) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "firebase_snapshot_invalid"}
	var snapshot := snapshot_variant as Dictionary
	var products_variant: Variant = snapshot.get("products", [])
	if typeof(products_variant) != TYPE_ARRAY:
		return {"ok": false, "reason": "firebase_products_invalid"}
	# O Store serve somente como recipiente da lista oficial de produtos/linhas.
	# Nenhum campo de telemetria, GPS ou status e lido dele.
	if not store.replace_from_remote(snapshot):
		return {"ok": false, "reason": "firebase_products_not_applied"}
	return {"ok": true, "product_rows": (products_variant as Array).size()}


func _grupo_rs_api_normalize_location(raw: Dictionary) -> Dictionary:
	_inc("api_rows")
	_inc_alias("server", raw, ["server_at", "serverAt", "data_servidor", "dataServidor", "DataServidor", "server_time", "communication_at", "ultima_comunicacao", "ultimaComunicacao", "data_comunicacao", "DataComunicacao", "updated_at"])
	_inc_alias("gps", raw, ["gps_at", "gpsAt", "data_gps", "dataGps", "DataGPS", "data_completa", "dataCompleta", "gps_time", "gpsTime", "data_evento", "dataEvento", "DataEvento", "event_at", "event_time", "data"])
	_inc_alias("ignition", raw, ["ignition", "Ignition", "ignicao", "Ignicao", "StatusIgnicao", "status_ignicao", "ignicao_status", "ignition_status"])
	var normalized := super._grupo_rs_api_normalize_location(raw)
	_inc("normalized_rows")
	var coordinate_state := str(normalized.get("coordinate_state", "missing"))
	if coordinate_state == "valid":
		_inc("normalized_valid")
	elif coordinate_state == "invalid":
		_inc("position_invalid")
	else:
		_inc("position_missing")
	return normalized


func _grupo_rs_api_get(path: String, retry_login: bool = true, force_read: bool = false) -> Dictionary:
	observer_in_flight += 1
	observer_metrics["in_flight_max"] = maxi(int(observer_metrics.get("in_flight_max", 0)), observer_in_flight)
	if path.contains("skip=0"):
		_inc("poll_cycles")
		observer_seen_cycle.clear()
	var started := Time.get_ticks_msec()
	var response := await super._grupo_rs_api_get(path, retry_login, force_read)
	observer_in_flight = maxi(observer_in_flight - 1, 0)
	observer_latencies_ms.append(maxi(Time.get_ticks_msec() - started, 0))
	if bool(response.get("relogin_attempted", false)):
		_inc("reauth")
	var code := int(response.get("response_code", 0))
	if code == 429:
		_inc("rate_limits")
	if bool(response.get("timeout", false)) or bool(response.get("timed_out", false)):
		_inc("timeouts")
	if not bool(response.get("ok", false)):
		_inc("http_errors")
	return response


func _process_inventory_communication_page(page_rows: Array[Dictionary]) -> void:
	if not observer_active:
		super._process_inventory_communication_page(page_rows)
		return
	_inc("location_pages")
	if page_rows.is_empty():
		_inc("empty_responses")
	observer_page_matched = 0
	var seen_page: Dictionary = {}
	for location in page_rows:
		var identity := _observer_identity_fingerprint(location)
		if identity != "":
			if seen_page.has(identity):
				_inc("duplicates_within_page")
			else:
				seen_page[identity] = true
			if observer_seen_cycle.has(identity):
				_inc("duplicates_within_cycle")
			else:
				observer_seen_cycle[identity] = true
			observer_queue_unique[identity] = true
			observer_metrics["queue_unique_count"] = observer_queue_unique.size()
			var payload_fingerprint := JSON.stringify(location.get("raw", location)).sha256_text()
			if observer_last_payload_by_identity.get(identity, "") == payload_fingerprint and identity != "":
				_inc("same_payload_reobserved")
			if identity != "":
				observer_last_payload_by_identity[identity] = payload_fingerprint
		var candidate_count := _observer_candidate_count(location)
		if candidate_count > 1:
			_inc("ambiguous_rows")
		if candidate_count == 0:
			_inc("unmatched_rows")
		_record_key_family(location)
	super._process_inventory_communication_page(page_rows)
	# O hook de update confirma quantas linhas chegaram ao produto pelo matcher real.
	if observer_page_matched > 0:
		observer_metrics["matched_products"] = int(observer_metrics.get("matched_products", 0)) + observer_page_matched


func _update_inventory_communication_status(product: Dictionary, location: Dictionary) -> void:
	if not observer_active:
		super._update_inventory_communication_status(product, location)
		return
	observer_page_matched += 1
	var cache_key := _inventory_communication_cache_key_for_product(product)
	var before_cache: Dictionary = inventory_communication_status_cache.get(cache_key, {})
	var signature_before := _inventory_row_signature(product)
	var old_category := _category_from_status(before_cache)
	super._update_inventory_communication_status(product, location)
	var after_cache: Dictionary = inventory_communication_status_cache.get(cache_key, {})
	var signature_after := _inventory_row_signature(product)
	if before_cache.is_empty():
		_inc("cache_created")
	elif JSON.stringify(before_cache) == JSON.stringify(after_cache):
		_inc("cache_unchanged")
	else:
		_inc("cache_changed")
	if signature_before == signature_after:
		_inc("signatures_unchanged")
	else:
		_inc("signatures_changed")
	var new_category := _category_from_status(after_cache)
	var transition := "%s>%s" % [old_category, new_category]
	observer_transition_counts[transition] = int(observer_transition_counts.get(transition, 0)) + 1
	_inc("classified")
	_inc_color(str(after_cache.get("color_key", "")))
	var status_key := str(after_cache.get("status_key", ""))
	if status_key in ["atualizado", "desligado", "desatualizado"]:
		_inc("status_" + status_key)
	var server_present := int(after_cache.get("server_unix", 0)) > 0
	var gps_present := int(after_cache.get("gps_unix", 0)) > 0
	_inc("server_present" if server_present else "server_absent")
	_inc("latest_comm_present" if server_present else "latest_comm_absent")
	_inc("gps_present" if gps_present else "gps_absent")
	if bool(after_cache.get("gps_issue", false)):
		_inc("gps_issue")
	if bool(after_cache.get("repeated_coordinate", false)):
		_inc("repeated_coordinate")
	_inc("rows_updated")
	var sku := str(product.get("sku", "")).strip_edges()
	if sku != "":
		observer_pending_signatures[sku] = signature_after


func _request_inventory_table_refresh() -> void:
	if observer_active:
		_inc("refresh_requested")
	super._request_inventory_table_refresh()


func _flush_inventory_table_refresh() -> void:
	if observer_active:
		_inc("refresh_flushed")
	super._flush_inventory_table_refresh()


func _refresh_table() -> void:
	var before_nodes: Dictionary = {}
	var before_count := 0
	if observer_active and table_body != null and is_instance_valid(table_body):
		for child in table_body.get_children():
			var sku := str(child.get_meta("inventory_sku", ""))
			if sku != "":
				before_nodes[sku] = child
		before_count = before_nodes.size()
	super._refresh_table()
	if not observer_active:
		return
	_inc("table_refreshes")
	var redraw_count := 0
	for raw_sku in observer_pending_signatures.keys():
		var sku := str(raw_sku)
		var node: Variant = table_row_nodes.get(sku, null)
		if node is Control and is_instance_valid(node) and str((node as Control).get_meta("inventory_signature", "")) == str(observer_pending_signatures.get(sku, "")):
			redraw_count += 1
	observer_pending_signatures.clear()
	_inc("rows_redrawn", redraw_count)
	var after_count := table_row_nodes.size()
	var replaced := 0
	for sku in before_nodes.keys():
		var current: Variant = table_row_nodes.get(sku, null)
		if current == null or current != before_nodes[sku]:
			replaced += 1
	if before_count > 0 and after_count == before_count and replaced == before_count:
		_inc("full_rebuilds")
	elif redraw_count > 0:
		_inc("incremental_refreshes")


func _observer_identity_fingerprint(location: Dictionary) -> String:
	for product in inventory_device_cycle_products:
		var family := _inventory_match_family(product, location)
		if family != "":
			var cache_key := _inventory_communication_cache_key_for_product(product)
			if cache_key != "":
				return cache_key.sha256_text()
	var raw: Variant = location.get("raw", location)
	if typeof(raw) == TYPE_DICTIONARY:
		return JSON.stringify(raw).sha256_text()
	return ""


func _observer_candidate_count(location: Dictionary) -> int:
	var count := 0
	for product in inventory_device_cycle_products:
		if _inventory_match_family(product, location) != "":
			count += 1
	return count


func _record_key_family(location: Dictionary) -> void:
	var family := "none"
	for product in inventory_device_cycle_products:
		var matched_family := _inventory_match_family(product, location)
		if matched_family != "":
			family = matched_family
			break
	if family == "none" and str(location.get("equipment_id", "")) != "":
		family = "equipment_id"
	if family == "none" and _raw_has_key(location, ["numeroEquipamento", "numero_equipamento"]):
		family = "equipment_number"
	_inc_family(family)
	if family in ["equipment_id", "equipment_number"]:
		_inc("equipment_only_identities")


func _raw_has_key(location: Dictionary, keys: Array[String]) -> bool:
	var raw: Variant = location.get("raw", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	for key in keys:
		if (raw as Dictionary).has(key):
			return true
	return false


func _inc_alias(kind: String, raw: Dictionary, keys: Array[String]) -> void:
	var present := false
	for key in keys:
		if raw.has(key) and raw.get(key) != null and str(raw.get(key)).strip_edges() != "":
			present = true
			break
	_inc((kind + "_alias_present") if present else (kind + "_alias_absent"))


func _category_from_status(status: Dictionary) -> String:
	var color := str(status.get("color_key", ""))
	return color if color in ["verde", "vermelho", "amarelo", "roxo"] else "none"


func _inc_color(color: String) -> void:
	match color:
		"verde":
			_inc("green")
		"vermelho":
			_inc("red")
		"amarelo":
			_inc("yellow")
		"roxo":
			_inc("purple")


func _inc_family(family: String) -> void:
	observer_key_family_counts[family] = int(observer_key_family_counts.get(family, 0)) + 1


func _inc(key: String, amount: int = 1) -> void:
	observer_metrics[key] = int(observer_metrics.get(key, 0)) + amount
