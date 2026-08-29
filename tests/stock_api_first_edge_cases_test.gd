extends SceneTree

const DashboardScript := preload("res://tests/fixtures/offline_inventory_dashboard.gd")
const StoreScript := preload("res://src/inventory_store.gd")

var failures: Array[String] = []


class EdgeDashboard:
	extends DashboardScript

	var login_calls := 0
	var http_calls := 0
	var web_read_calls := 0
	var web_write_calls := 0
	var sync_calls := 0
	var verify_calls := 0
	var table_refreshes := 0
	var scenario := "ok"
	var force_location_stale := false

	func _ready() -> void:
		pass

	func _grupo_rs_api_get(path: String, retry_login: bool = true, force_read: bool = false) -> Dictionary:
		if not force_read and not _grupo_rs_api_reads_enabled():
			return {"ok": false, "state": "disabled", "message": "fixture_disabled"}
		if not grupo_rs_api_logged_in or grupo_rs_api_token.strip_edges() == "":
			var login := await _grupo_rs_api_login()
			if not bool(login.get("ok", false)):
				login["stage"] = "auth"
				return login
		var response := await _http_get_text_with_headers("fixture://grupo-rs%s" % path, PackedStringArray())
		if bool(response.get("ok", false)):
			return response
		if retry_login and int(response.get("response_code", 0)) == 401:
			grupo_rs_api_logged_in = false
			grupo_rs_api_token = ""
			var relogin := await _grupo_rs_api_login()
			if bool(relogin.get("ok", false)):
				var retried := await _grupo_rs_api_get(path, false, force_read)
				retried["relogin_attempted"] = true
				return retried
			relogin["stage"] = "auth"
			relogin["relogin_attempted"] = true
			return relogin
		response["relogin_attempted"] = false
		return response

	func _grupo_rs_api_login() -> Dictionary:
		login_calls += 1
		grupo_rs_api_logged_in = true
		grupo_rs_api_token = "fixture-token"
		return {"ok": true}

	func _http_get_text_with_headers(_url: String, _headers: PackedStringArray, _timeout_seconds: float = 15.0) -> Dictionary:
		http_calls += 1
		if scenario == "401" and http_calls == 1:
			return {"ok": false, "response_code": 401, "body": ""}
		if scenario == "timeout":
			return {"ok": false, "response_code": 0, "timeout": true, "message": "fixture_timeout"}
		if scenario == "rate_limit":
			return {"ok": false, "response_code": 429, "message": "fixture_rate_limit"}
		if scenario == "invalid_json":
			return {"ok": true, "response_code": 200, "body": "{invalid"}
		if scenario == "empty":
			return {"ok": true, "response_code": 200, "body": JSON.stringify({"data": []})}
		if scenario == "multi":
			return {"ok": true, "response_code": 200, "body": JSON.stringify({"data": [_api_location("910000201", "EDG-200"), _api_location("910000202", "EDG-200")]})}
		return {"ok": true, "response_code": 200, "body": JSON.stringify({"data": [_api_location("910000200", "EDG-200")]})}

	func _modern_grupo_rs_read_get(_path: String) -> Dictionary:
		web_read_calls += 1
		return {"ok": true, "body": "<tbody></tbody>", "fallback_web": true, "read_only": true}

	func _modern_grupo_rs_post_form(_path: String, _fields: Dictionary, _referer_path: String = "", _retry_login: bool = true, _max_redirects: int = 8) -> Dictionary:
		web_write_calls += 1
		return {"ok": false, "message": "fixture_web_write_blocked"}

	func _lookup_grupo_rs_location(serial: String, _progress_callback: Callable = Callable(), _source_mode: String = "", _fallback_plate: String = "", _fallback_client: String = "") -> Dictionary:
		http_calls += 1
		if force_location_stale:
			return {"ok": false, "message": "fixture_indisponivel"}
		return {
			"ok": true,
			"serial": serial,
			"equipment_serial": serial,
			"plate": "EDG-200",
			"updated_at": Time.get_datetime_string_from_system(false, true),
			"ignition": true,
			"speed": "0",
			"monitoring_status": "ligado",
		}

	func _local_database_sync() -> Node:
		return self

	func sync_now() -> Dictionary:
		sync_calls += 1
		if scenario == "local_database_refused":
			return {"ok": false, "state": "error"}
		return {"ok": true, "state": "synced"}

	func verify_product_persisted(_serial: String, _expected_product: Dictionary) -> Dictionary:
		verify_calls += 1
		if scenario == "local_database_verify_refused":
			return {"ok": false, "message": "fixture_verify_refused"}
		return {"ok": true}

	func _refresh_table() -> void:
		table_refreshes += 1

	func _api_location(serial: String, plate: String) -> Dictionary:
		return {
			"numeroSerie": serial,
			"placa": plate,
			"codVeiculo": "200",
			"data_servidor": Time.get_datetime_string_from_system(false, true),
			"data_gps": Time.get_datetime_string_from_system(false, true),
			"ignicao": true,
			"velocidade": "0",
			"status_monitoramento": "ligado",
			"latitude": "-1.0000",
			"longitude": "-1.0000",
		}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_envelopes_and_aliases()
	await _check_online_table_display_labels()
	await _check_cache_states_and_auto_query()
	await _check_api_error_categories_block_success()
	await _check_reauth_once()
	await _check_fallback_web_read_only()
	await _check_store_newer_not_overwritten()
	await _check_log_sanitization()
	if failures.is_empty():
		print("STOCK_API_FIRST_EDGE_CASES_TEST_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _check_envelopes_and_aliases() -> void:
	var dashboard := EdgeDashboard.new()
	root.add_child(dashboard)
	await process_frame
	for envelope in ["data", "dados", "results", "records"]:
		var payload := {}
		payload[envelope] = [_equipment_alias_row()]
		var rows: Array[Dictionary] = dashboard._grupo_rs_api_equipment_rows(payload)
		_check(rows.size() == 1, "Envelope %s não extraiu uma linha." % envelope)
		var normalized: Dictionary = dashboard._grupo_rs_api_inventory_equipment_row(rows[0])
		_check(str(normalized.get("status", "")) == "Ativo", "Envelope %s perdeu status." % envelope)
		_check(str(normalized.get("apn", "")) == "linksolutions.br", "Envelope %s perdeu APN." % envelope)
		_check(str(normalized.get("operator", "")) == "Claro", "Envelope %s perdeu operadora." % envelope)
		_check(str(normalized.get("client", "")) == "CLIENTE TESTE", "Envelope %s perdeu cliente." % envelope)
		_check(str(normalized.get("chip", "")) != "", "Envelope %s perdeu chip." % envelope)
		_check(str(normalized.get("phone", "")) != "", "Envelope %s perdeu telefone." % envelope)
	dashboard.queue_free()
	await process_frame


func _equipment_alias_row() -> Dictionary:
	return {
		"NumeroSerie": "910000300",
		"PLACA": "EDG-300",
		"CLIENTE": "CLIENTE TESTE",
		"ICCID": "89550000000000000300",
		"Telefone": "99999999300",
		"ApN": "linksolutions.br",
		"Operadora": "Claro",
		"STATUS": "Ativo",
		"CodEquipamento": 300,
	}


func _check_online_table_display_labels() -> void:
	var dashboard := EdgeDashboard.new()
	root.add_child(dashboard)
	await process_frame
	_check(dashboard._grupo_rs_registration_status_label("A") == "Ativo", "Código cadastral A não virou Ativo.")
	_check(dashboard._grupo_rs_registration_status_label("a") == "Ativo", "Código cadastral minúsculo não virou Ativo.")
	_check(dashboard._grupo_rs_registration_status_label("I") == "Inativo", "Código cadastral I não virou Inativo.")
	_check(dashboard._grupo_rs_registration_status_label("R") == "Reserva", "Código cadastral R não virou Reserva.")
	_check(dashboard._grupo_rs_registration_status_label("reserva") == "Reserva", "Status reserva textual não foi normalizado.")
	_check(dashboard._grupo_rs_registration_status_label("X9") == "X9", "Status cadastral desconhecido não preservou fallback original.")
	_check(dashboard._grupo_rs_registration_status_label("") == "Não informado", "Status cadastral ausente não virou Não informado.")
	_check(dashboard._grupo_rs_online_field_label("") == "Não informado", "Campo online vazio não virou Não informado.")
	_check(dashboard._grupo_rs_online_field_label("-") == "Não informado", "Campo online '-' não virou Não informado.")
	_check(dashboard._grupo_rs_online_field_label("null") == "Não informado", "Campo online null textual não virou Não informado.")
	_check(dashboard._grupo_rs_online_field_label("89550000000000000301") == "89550000000000000301", "Campo online informado foi alterado.")
	_check(dashboard._location_status_short_label("Não consultado") == "Não consultado", "Status atual não consultado foi abreviado.")
	_check(dashboard._location_status_short_label("Nao consultado") == "Não consultado", "Status atual legado sem acento não foi normalizado.")
	_check(dashboard._location_status_short_label("Indisponivel") == "Indisponivel", "Status atual indisponível foi alterado indevidamente.")
	dashboard.queue_free()
	await process_frame


func _check_cache_states_and_auto_query() -> void:
	var dashboard := EdgeDashboard.new()
	root.add_child(dashboard)
	await process_frame
	var serial := "910000200"
	_check(str((dashboard._cached_location_status_for_serial(serial) as Dictionary).get("label", "")) == "Não consultado", "Cache limpo não retorna Não consultado.")
	dashboard.location_visible_batch_id = 1
	dashboard._start_visible_location_status_batch([{"sku": serial, "imei": serial, "plate": "EDG-200"}], 1)
	await create_timer(0.05).timeout
	_check(dashboard.http_calls == 1, "Consulta automática não disparou exatamente uma busca com cache limpo.")
	_check(str((dashboard.location_status_cache.get(serial, {}) as Dictionary).get("label", "")) == "Ligado", "Status real não foi cacheado após consulta automática.")
	dashboard._start_visible_location_status_batch([{"sku": serial, "imei": serial, "plate": "EDG-200"}], 1)
	await create_timer(0.05).timeout
	_check(dashboard.http_calls == 1, "Cache fresco gerou consulta duplicada.")
	var stale_entry: Dictionary = dashboard.location_status_cache.get(serial, {}) as Dictionary
	stale_entry["checked_at"] = Time.get_unix_time_from_system() - 999999
	dashboard.location_status_cache[serial] = stale_entry
	dashboard._start_visible_location_status_batch([{"sku": serial, "imei": serial, "plate": "EDG-200"}], 1)
	await create_timer(0.05).timeout
	_check(dashboard.http_calls == 2, "Cache expirado/obsoleto não disparou nova consulta.")
	dashboard.force_location_stale = true
	stale_entry = dashboard.location_status_cache.get(serial, {}) as Dictionary
	stale_entry["checked_at"] = Time.get_unix_time_from_system() - 999999
	dashboard.location_status_cache[serial] = stale_entry
	dashboard._start_visible_location_status_batch([{"sku": serial, "imei": serial, "plate": "EDG-200"}], 1)
	await create_timer(0.05).timeout
	var unavailable: Dictionary = dashboard.location_status_cache.get(serial, {}) as Dictionary
	_check(str(unavailable.get("label", "")) in ["Revalidando", "Aguardando API"], "Indisponibilidade não ficou marcada como pendência/revalidação.")
	dashboard.queue_free()
	await process_frame


func _check_api_error_categories_block_success() -> void:
	for scenario in ["timeout", "rate_limit", "invalid_json", "empty", "multi"]:
		var dashboard := EdgeDashboard.new()
		root.add_child(dashboard)
		await process_frame
		dashboard.scenario = scenario
		var result: Dictionary = await dashboard._grupo_rs_api_find_location("910000200", "EDG-200", "", false, 50)
		if scenario in ["empty"]:
			_check(bool(result.get("not_found", false)) and not bool(result.get("ok", false)) or (bool(result.get("ok", false)) and bool(result.get("not_found", false))), "%s não retornou not_found/pendente controlado." % scenario)
		else:
			_check(not bool(result.get("ok", false)), "%s virou sucesso falso." % scenario)
		dashboard.queue_free()
		await process_frame


func _check_reauth_once() -> void:
	var dashboard := EdgeDashboard.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.scenario = "401"
	dashboard.grupo_rs_api_logged_in = true
	dashboard.grupo_rs_api_token = "expired-fixture"
	var result: Dictionary = await dashboard._grupo_rs_api_get("/endpoints/localizacao.php?q=EDG-200&skip=0&take=50", true, true)
	_check(bool(result.get("ok", false)), "401 com reauth não recuperou leitura fixture.")
	_check(dashboard.login_calls == 1, "401 executou mais de uma reautenticação.")
	_check(bool(result.get("relogin_attempted", false)), "401 não marcou tentativa de reauth.")
	dashboard.queue_free()
	await process_frame


func _check_fallback_web_read_only() -> void:
	var dashboard := EdgeDashboard.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.offline_pages = []
	dashboard.scenario = "empty"
	var rows: Array[Dictionary] = await dashboard._fetch_grupo_rs_equipment_rows("910000404")
	_check(rows.is_empty(), "Fallback web vazio não deveria inventar linha.")
	_check(dashboard.web_read_calls >= 1, "Fallback web de equipamento não foi explicitamente marcado como leitura.")
	_check(dashboard.web_write_calls == 0, "Fallback web de busca executou escrita.")
	dashboard.queue_free()
	await process_frame


func _check_store_newer_not_overwritten() -> void:
	var dashboard := EdgeDashboard.new()
	var store := StoreScript.new()
	root.add_child(dashboard)
	await process_frame
	store.configure_isolated_sqlite_for_testing("C:/GRUPO RS CENTRAL/test_artifacts/edge_store_newer.sqlite", "edge_store_newer")
	store.replace_from_remote({
		"products": [{
			"sku": "910000500",
			"imei": "910000500",
			"plate": "NEW-500",
			"updated_at": "2026-08-28 12:00:00",
			"tracker_status": "Instalado",
			"status": "Instalado",
		}],
		"movements": [],
		"maintenance": [],
		"logs": [],
		"sms_logs": [],
	})
	dashboard.store = store
	dashboard.online_lookup_last_query = "910000500"
	dashboard._schedule_online_lookup_confirmed_api_reconcile([{"serial": "910000500", "plate": "OLD-500", "status": "Ativo"}])
	await process_frame
	var product: Dictionary = store.get_product("910000500")
	_check(str(product.get("plate", "")) == "NEW-500", "Reconciliação sobrescreveu Store mais novo existente.")
	_check(dashboard.sync_calls == 0 and dashboard.verify_calls == 0, "Reconciliação tentou Banco local SQL mesmo com Store existente.")
	dashboard.queue_free()
	await process_frame


func _check_log_sanitization() -> void:
	var dashboard := EdgeDashboard.new()
	root.add_child(dashboard)
	await process_frame
	var store := StoreScript.new()
	var db_name := "edge_log_sanitization_%d" % Time.get_ticks_usec()
	store.configure_isolated_sqlite_for_testing("C:/GRUPO RS CENTRAL/test_artifacts/%s.sqlite" % db_name, db_name)
	store.replace_from_remote({"products": [], "movements": [], "maintenance": [], "system_logs": [], "logs": [], "sms_logs": []})
	dashboard.store = store
	var exposed_details := "Serie: 910000600 | SKU: 910000600 | Placa: ABC-1234 | Chip: 89550000000000000600 | Telefone: 99999999600 | Payload: {secret:true} | Detalhes: corpo completo"
	var exposed_metadata := {
		"serial": "910000600",
		"serie": "910000600",
		"sku": "910000600",
		"technical_key": "local_database/path/910000600",
		"plate": "ABC-1234",
		"placa": "ABC-1234",
		"chip": "89550000000000000600",
		"iccid": "89550000000000000600",
		"phone": "99999999600",
		"telefone": "99999999600",
		"payload": {"body": "secret"},
		"details": "Serie 910000600 Placa ABC-1234",
		"message": "Payload com Serie 910000600 e Placa ABC-1234",
		"safe": "ok",
	}
	var sanitized_metadata: Dictionary = dashboard._sanitize_inventory_log_metadata(exposed_metadata)
	for key in ["serial", "serie", "sku", "technical_key", "plate", "placa", "chip", "iccid", "phone", "telefone", "payload", "details", "message"]:
		_check(str(sanitized_metadata.get(key, "")) == "[dado_sanitizado]", "Sanitizador direto não cobriu chave técnica '%s'." % key)
	_check(str(sanitized_metadata.get("safe", "")) == "ok", "Sanitizador direto alterou metadado seguro.")
	dashboard._log_system_action_event("Fixture log Estoque", exposed_details, "910000600", exposed_metadata)
	var logs: Array[Dictionary] = store.get_system_logs(1)
	_check(logs.size() == 1, "Wrapper de log não gravou fixture sanitizada.")
	var log: Dictionary = logs[0] if logs.size() == 1 else {}
	var serialized := JSON.stringify(log)
	_check(str(log.get("sku", "")) == "910000600", "Chave operacional interna sku não foi preservada para indexação do Store.")
	_check(not str(log.get("details", "")).contains("910000600"), "Detalhes expostos mantiveram série/SKU.")
	_check(not str(log.get("details", "")).contains("ABC-1234"), "Detalhes expostos mantiveram placa.")
	_check(not str(log.get("details", "")).contains("89550000000000000600"), "Detalhes expostos mantiveram chip.")
	_check(not str(log.get("details", "")).contains("99999999600"), "Detalhes expostos mantiveram telefone.")
	for key in ["plate", "message"]:
		if log.has(key):
			_check(str(log.get(key, "")) == "[dado_sanitizado]", "Metadado exposto '%s' não foi sanitizado no log gravado." % key)
	_check(not serialized.contains("ABC-1234") and not serialized.contains("89550000000000000600") and not serialized.contains("99999999600"), "Log serializado expõe placa/chip/telefone.")
	dashboard.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
