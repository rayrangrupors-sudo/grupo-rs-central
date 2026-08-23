extends Node

signal status_changed(status: Dictionary)

const SecretVaultScript := preload("res://src/security/secret_vault.gd")
const CONFIG_PATH := "user://firebase_sync_config.json"
const LEGACY_STATE_PATH := "user://firebase_sync_state.json"
const SYNC_DEBOUNCE_SECONDS := 0.15
const REQUEST_TIMEOUT_SECONDS := 18.0
const SYNC_FORCE_WAIT_SECONDS := 90.0
const INITIAL_RETRY_SECONDS := 15.0
const MAX_RETRY_SECONDS := 300.0
const CONNECTION_PROBE_ROOT := "health/connection_probe"
const DEFAULT_DATABASE_URL := "https://grupo-rs-central-165dc-default-rtdb.firebaseio.com"
const SECTIONS := ["products", "movements", "system_logs", "maintenances"]

var _store: Variant = null
var _branch_id := ""
var _config: Dictionary = {}
var _state: Dictionary = {}
var _pending_snapshot: Dictionary = {}
var _pending_dirty := false
var _change_generation := 0
var _binding_generation := 0
var _sync_timer: Timer
var _probe_timer: Timer
var _sync_busy := false
var _request_in_flight := false
var _id_token := ""
var _refresh_token := ""
var _token_expires_at := 0
var _failure_count := 0
var _circuit_open_until := 0
var _last_latency_ms := -1
var _last_sync_at := ""
var _read_verified := false
var _write_verified := false
var _last_probe_at := ""
var _last_probe_message := ""
var _status := {
	"state": "not_configured",
	"message": "Firebase ainda nao configurado.",
	"pending": false,
	"latency_ms": -1,
	"last_sync_at": "",
	"failure_count": 0,
	"retry_at": 0,
	"read_ok": false,
	"write_ok": false,
	"verified_at": "",
	"probe_message": "",
}


func _ready() -> void:
	_sync_timer = Timer.new()
	_sync_timer.one_shot = true
	_sync_timer.wait_time = SYNC_DEBOUNCE_SECONDS
	_sync_timer.timeout.connect(_on_sync_timer_timeout)
	add_child(_sync_timer)

	_probe_timer = Timer.new()
	_probe_timer.one_shot = true
	_probe_timer.timeout.connect(_on_probe_timer_timeout)
	add_child(_probe_timer)

	_config = _read_json_dictionary(CONFIG_PATH)
	_hydrate_configuration_from_vault()
	_state = {}
	if FileAccess.file_exists(LEGACY_STATE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_STATE_PATH))
	_refresh_token = str(_config.get("refresh_token", "")).strip_edges()
	if _is_configured():
		_set_status("idle", "Servidor pronto para conectar.")


func _hydrate_configuration_from_vault() -> void:
	## Recupera a configuracao operacional quando uma versao de teste ou uma
	## migracao antiga deixou apenas um endpoint temporario no arquivo local.
	## As credenciais continuam vindo exclusivamente do cofre criptografado.
	var vault := get_node_or_null("/root/SecretVault")
	if vault == null or not vault.has_method("get_secret"):
		return
	var vault_api_key := str(vault.call("get_secret", "firebase", "api_key", "")).strip_edges()
	var vault_refresh_token := str(vault.call("get_secret", "firebase", "refresh_token", "")).strip_edges()
	var database_url := str(_config.get("database_url", "")).strip_edges().trim_suffix("/")
	var is_loopback := database_url.to_lower().begins_with("http://127.0.0.1") \
		or database_url.to_lower().begins_with("http://localhost") \
		or database_url.to_lower().begins_with("https://127.0.0.1") \
		or database_url.to_lower().begins_with("https://localhost")
	var changed := false
	if database_url == "" or is_loopback:
		_config["database_url"] = DEFAULT_DATABASE_URL
		changed = true
	if str(_config.get("api_key", "")).strip_edges() == "" and vault_api_key != "":
		_config["api_key"] = vault_api_key
		changed = true
	if str(_config.get("refresh_token", "")).strip_edges() == "" and vault_refresh_token != "":
		_config["refresh_token"] = vault_refresh_token
		changed = true
	if changed:
		_config["enabled"] = true
		_write_json_dictionary(CONFIG_PATH, _config)
	_refresh_token = str(_config.get("refresh_token", "")).strip_edges()


func uses_encrypted_secret_vault() -> bool:
	return true


func bind_store(store: Variant, branch_id: String) -> void:
	if _store != null and _store.has_signal("database_saved"):
		var old_callable := Callable(self, "on_database_saved")
		if _store.database_saved.is_connected(old_callable):
			_store.database_saved.disconnect(old_callable)
		var old_private_callable := Callable(self, "_on_database_saved")
		if _store.database_saved.is_connected(old_private_callable):
			_store.database_saved.disconnect(old_private_callable)

	_store = store
	_branch_id = _normalize_branch_id(branch_id)
	_binding_generation += 1
	_pending_snapshot = {}
	_pending_dirty = false
	_read_verified = false
	_write_verified = false
	_last_probe_at = ""
	_last_probe_message = ""
	if _store != null and _store.has_method("get_pending_sync_snapshot"):
		var queued_snapshot: Variant = _store.call("get_pending_sync_snapshot")
		if typeof(queued_snapshot) == TYPE_DICTIONARY and not (queued_snapshot as Dictionary).is_empty():
			_pending_snapshot = (queued_snapshot as Dictionary).duplicate(true)
			_pending_dirty = true
	_mark_store_unavailable()
	if _store != null and _store.has_signal("database_saved"):
		var save_callable := Callable(self, "on_database_saved")
		if not _store.database_saved.is_connected(save_callable):
			_store.database_saved.connect(save_callable)

	if not _is_configured():
		_set_status("not_configured", "Firebase ainda nao configurado.")
		return

	# Pending snapshots can be incomplete when they were captured before the
	# official remote data finished loading. Always bootstrap from Firebase first.
	_set_status("connecting", "Verificando o servidor...")
	call_deferred("_initial_sync")


func configure_account(config: Dictionary) -> bool:
	var next_config := config.duplicate(true)
	var database_url := str(next_config.get("database_url", "")).strip_edges().trim_suffix("/")
	var api_key := str(next_config.get("api_key", "")).strip_edges()
	var refresh_token := str(next_config.get("refresh_token", "")).strip_edges()
	if database_url == "":
		database_url = str(_config.get("database_url", "")).strip_edges().trim_suffix("/")
	if api_key == "":
		api_key = str(_config.get("api_key", "")).strip_edges()
	if refresh_token == "":
		refresh_token = str(_config.get("refresh_token", "")).strip_edges()
	if database_url == "" or api_key == "" or refresh_token == "":
		return false

	next_config["database_url"] = database_url
	next_config["api_key"] = api_key
	next_config["refresh_token"] = refresh_token
	next_config["enabled"] = true
	next_config.erase("password")
	_config = next_config
	_refresh_token = refresh_token
	_id_token = ""
	_token_expires_at = 0
	_read_verified = false
	_write_verified = false
	_last_probe_at = ""
	_last_probe_message = ""
	if not _write_json_dictionary(CONFIG_PATH, _config):
		return false
	_set_status("idle", "Configuracao do Firebase salva.")
	if _store != null and _branch_id != "":
		call_deferred("_initial_sync")
	return true


func get_status() -> Dictionary:
	var result := _status.duplicate(true)
	result["branch"] = _branch_id
	result["configured"] = _is_configured()
	result["database_url"] = str(_config.get("database_url", ""))
	result["pending"] = _pending_dirty or not _pending_snapshot.is_empty()
	result["latency_ms"] = _last_latency_ms
	result["last_sync_at"] = _last_sync_at
	result["failure_count"] = _failure_count
	result["retry_at"] = _circuit_open_until
	result["read_ok"] = _read_verified
	result["write_ok"] = _write_verified
	result["verified_at"] = _last_probe_at
	result["probe_message"] = _last_probe_message
	result["pending_count"] = _pending_sync_count()
	result["pending_limit"] = _pending_sync_limit()
	result["data_available"] = _store != null \
		and _store.has_method("is_remote_available") \
		and bool(_store.call("is_remote_available")) \
		and _read_verified \
		and _write_verified
	return result


func get_configuration_summary() -> Dictionary:
	return {
		"database_url": str(_config.get("database_url", "")),
		"api_key": str(_config.get("api_key", "")),
		"has_refresh_token": str(_config.get("refresh_token", "")).strip_edges() != "",
		"configured": _is_configured(),
	}


func force_sync() -> void:
	if _store == null or not _is_configured():
		return
	if _store.has_method("is_remote_available") and not bool(_store.call("is_remote_available")):
		call_deferred("_initial_sync")
		return
	_pending_snapshot = _store.get_sync_snapshot()
	_pending_dirty = true
	_change_generation += 1
	if _circuit_is_open():
		_set_status("offline", "Sem internet. Os dados permanecem indisponiveis ate a reconexao.")
		return
	_sync_timer.stop()
	call_deferred("_perform_pending_sync")


func sync_now() -> Dictionary:
	## Flush a alteracao operacional atual e somente retorna quando o Firebase
	## confirmou a gravacao ou informou uma falha explicita.
	if _store == null or _branch_id == "":
		return {"ok": false, "state": "not_configured", "message": "Base Firebase nao vinculada."}
	if not _is_configured():
		return {"ok": false, "state": "not_configured", "message": "Firebase nao configurado."}
	# Operacoes acionadas pelo operador nao devem falhar instantaneamente apenas
	# porque o circuito abriu durante uma requisicao anterior. Aguarde a janela
	# curta de recuperacao e tente a verificacao novamente antes de devolver erro.
	var circuit_deadline := Time.get_ticks_msec() + int(SYNC_FORCE_WAIT_SECONDS * 1000.0)
	while _circuit_is_open() and Time.get_ticks_msec() < circuit_deadline:
		await get_tree().create_timer(0.5).timeout
	if _sync_busy:
		var wait_deadline := Time.get_ticks_msec() + int(SYNC_FORCE_WAIT_SECONDS * 1000.0)
		while _sync_busy and Time.get_ticks_msec() < wait_deadline:
			await get_tree().create_timer(0.1).timeout
		if _sync_busy:
			return {"ok": false, "state": "pending", "pending": true, "message": "O Firebase ainda esta processando outra sincronizacao."}
	if _store.has_method("is_remote_available") and not bool(_store.call("is_remote_available")):
		# Uma modificacao pode chegar imediatamente depois da reconexao. Faça
		# uma verificacao de leitura/escrita antes de desistir; sem isso o fluxo
		# local fica correto, mas a alteracao nunca chega ao Firebase.
		var probe: Dictionary = await refresh_remote(true)
		var probe_ok := str(probe.get("state", "")).to_lower() == "synced" and bool(probe.get("write_ok", false))
		if not probe_ok:
			return {"ok": false, "state": str(probe.get("state", "offline")), "pending": true, "message": "Firebase indisponivel para confirmar a gravacao."}
	_pending_snapshot = _store.get_sync_snapshot()
	_pending_dirty = true
	_change_generation += 1
	_sync_timer.stop()
	await _perform_pending_sync()
	var result := get_status()
	result["ok"] = str(result.get("state", "")).to_lower() == "synced" and not bool(result.get("pending", false))
	return result


func verify_product_persisted(serial: String, expected_product: Dictionary = {}) -> Dictionary:
	## Confirma no registro remoto o produto que acabou de ser alterado.
	## O PATCH HTTP 2xx sozinho nao basta: regras/proxies podem aceitar a
	## requisicao sem que o registro esperado esteja disponivel na leitura.
	if _store == null or _branch_id == "" or not _is_configured():
		return {"ok": false, "message": "Base Firebase nao vinculada para confirmar o produto."}
	var clean_serial := serial.strip_edges()
	var identities: Array[String] = []
	for candidate in [
		str(expected_product.get("sku", "")),
		clean_serial,
		str(expected_product.get("imei", "")),
		str(expected_product.get("equipment_number", "")),
	]:
		var identity: String = candidate.strip_edges()
		if identity != "" and not identities.has(identity):
			identities.append(identity)
	for identity in identities:
		var key := _record_key("products", {"sku": identity}, 0)
		var response: Dictionary = await _database_request(HTTPClient.METHOD_GET, "branches/%s/records/products/%s" % [_branch_id, key])
		if not bool(response.get("ok", false)):
			continue
		var data: Variant = response.get("data")
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var remote := data as Dictionary
		if _product_matches_expected(remote, clean_serial, expected_product):
			return {"ok": true, "record": remote, "key": key}
	# A branch may have been written by an older build whose record key was
	# derived from another identity (for example IMEI before SKU normalization).
	# In that case the direct key lookup is not enough; read the products map and
	# match the immutable serial/IMEI plus the fields just submitted.
	var branch_response: Dictionary = await _database_request(HTTPClient.METHOD_GET, "branches/%s/records/products" % _branch_id)
	if bool(branch_response.get("ok", false)):
		var branch_data: Variant = branch_response.get("data")
		if typeof(branch_data) == TYPE_DICTIONARY:
			for remote_key in (branch_data as Dictionary).keys():
				var candidate: Variant = (branch_data as Dictionary).get(remote_key)
				if typeof(candidate) != TYPE_DICTIONARY:
					continue
				var remote_product := candidate as Dictionary
				if _product_matches_expected(remote_product, clean_serial, expected_product):
					return {"ok": true, "record": remote_product, "key": str(remote_key)}
	return {"ok": false, "message": "O Firebase respondeu, mas nao encontrou a alteracao da serie %s na leitura de confirmacao." % clean_serial}


func _product_matches_expected(remote: Dictionary, serial: String, expected: Dictionary) -> bool:
	var remote_serials: Array[String] = []
	for field in ["sku", "imei", "equipment_number", "serial"]:
		var value := str(remote.get(field, "")).strip_edges()
		if value != "":
			remote_serials.append(value)
	if serial != "" and not remote_serials.has(serial) and not remote_serials.has(serial.to_upper()):
		return false
	for field in ["plate", "client", "status", "tracker_status", "chip_number", "chip_phone", "apn", "operator"]:
		var expected_value := str(expected.get(field, "")).strip_edges()
		if expected_value == "":
			continue
		var remote_value := str(remote.get(field, "")).strip_edges()
		if field in ["chip_number", "chip_phone"]:
			expected_value = "".join(expected_value.split(" ")).replace("-", "").replace("(", "").replace(")", "")
			remote_value = "".join(remote_value.split(" ")).replace("-", "").replace("(", "").replace(")", "")
		if field == "apn":
			expected_value = expected_value.to_lower()
			remote_value = remote_value.to_lower()
		if expected_value != remote_value:
			return false
	return true


func refresh_remote(health_only: bool = false) -> Dictionary:
	## Releitura segura da filial remota, sem transformar a leitura em escrita.
	## Usada pelo monitor ST310 para enxergar um pacote bruto que chegou em
	## segundo plano enquanto o operador permanece na tela de localizacao.
	if _store == null or _branch_id == "" or not _is_configured():
		return get_status()
	if health_only:
		if _sync_busy or _request_in_flight or _circuit_is_open():
			return get_status()
		_sync_busy = true
		_set_status("connecting", "Verificando a conexao com o Firebase...")
		var verification := await _verify_connection_read_write()
		_sync_busy = false
		if bool(verification.get("ok", false)):
			_restore_connection()
			_set_status("synced", str(verification.get("message", "Firebase confirmado.")))
			return get_status()
		_mark_store_unavailable()
		var verification_state := str(verification.get("state", "degraded"))
		if bool(verification.get("offline", false)):
			verification_state = "offline"
		_set_status(verification_state, str(verification.get("message", "Nao foi possivel confirmar o Firebase.")))
		return get_status()
	if _sync_busy:
		return get_status()
	await _initial_sync()
	return get_status()


func on_database_saved(snapshot: Dictionary, _db_path: String) -> void:
	if _branch_id == "":
		return
	if not snapshot.is_empty():
		_pending_snapshot = snapshot.duplicate(true)
	_pending_dirty = true
	_change_generation += 1
	if not _is_configured():
		_mark_store_unavailable()
		_set_status("not_configured", "Firebase nao configurado. Nenhuma alteracao foi salva.")
		return
	if _circuit_is_open():
		_keep_pending_snapshot(_pending_snapshot)
		_mark_store_unavailable()
		_set_status("offline", "Sem internet. Alteracao preservada para reenviar.")
		return
	_set_status("pending", "Enviando alteracao ao Firebase...")
	_sync_timer.start(SYNC_DEBOUNCE_SECONDS)


func _on_database_saved(snapshot: Dictionary, db_path: String) -> void:
	on_database_saved(snapshot, db_path)


func _on_sync_timer_timeout() -> void:
	await _perform_pending_sync()


func _on_probe_timer_timeout() -> void:
	if not _is_configured() or _sync_busy:
		return
	_circuit_open_until = 0
	_set_status("connecting", "Testando a conexao com o Firebase...")
	var result := await _database_request(HTTPClient.METHOD_GET, "health/ping")
	if bool(result.get("ok", false)):
		_restore_connection()
		await _initial_sync()
	elif not _circuit_is_open():
		_trip_circuit("O servidor ainda esta indisponivel.")


func _initial_sync() -> void:
	if _sync_busy or _store == null or _branch_id == "" or not _is_configured():
		return
	if _circuit_is_open():
		return

	var binding_generation := _binding_generation
	var change_generation := _change_generation
	var bound_store: Variant = _store
	var bound_branch := _branch_id
	var pending_before_sync := _pending_snapshot.duplicate(true)
	var had_pending := _pending_dirty or not pending_before_sync.is_empty()
	_sync_busy = true
	_set_status("connecting", "Consultando a base remota...")
	var result := await _database_request(HTTPClient.METHOD_GET, "branches/%s" % bound_branch)
	if binding_generation != _binding_generation or bound_store != _store or bound_branch != _branch_id:
		_sync_busy = false
		return
	if not bool(result.get("ok", false)):
		_mark_store_unavailable()
		_sync_busy = false
		return
	if change_generation != _change_generation:
		_sync_busy = false
		if _pending_dirty or not _pending_snapshot.is_empty():
			_sync_timer.start(SYNC_DEBOUNCE_SECONDS)
		return

	var remote_value: Variant = result.get("data")
	var remote_snapshot := _empty_snapshot()
	var remote_hash := ""
	if remote_value != null and typeof(remote_value) == TYPE_DICTIONARY and not (remote_value as Dictionary).is_empty():
		var remote_envelope := remote_value as Dictionary
		remote_snapshot = _decode_remote_snapshot(remote_envelope)
		if remote_snapshot.is_empty():
			_mark_store_unavailable()
			_set_status("error", "A base remota possui um formato invalido. Os dados ficaram bloqueados.")
			_sync_busy = false
			return
		remote_hash = str((remote_envelope.get("meta", {}) as Dictionary).get("content_hash", ""))
		if remote_hash == "":
			remote_hash = _snapshot_hash(remote_snapshot)

	if not _store.replace_from_remote(remote_snapshot):
		_mark_store_unavailable()
		_set_status("error", "Nao foi possivel aplicar os dados recebidos do Firebase.")
		_sync_busy = false
		return

	_record_synced_state(remote_snapshot, remote_hash if remote_hash != "" else _snapshot_hash(remote_snapshot), remote_hash if remote_hash != "" else _snapshot_hash(remote_snapshot))
	_last_sync_at = Time.get_datetime_string_from_system(false, true)
	var verification := await _verify_connection_read_write()
	if not bool(verification.get("ok", false)):
		_mark_store_unavailable()
		if had_pending:
			_pending_snapshot = pending_before_sync.duplicate(true)
			_pending_dirty = not _pending_snapshot.is_empty()
			_keep_pending_snapshot(_pending_snapshot)
		_sync_busy = false
		var verification_state := str(verification.get("state", "degraded"))
		_set_status(verification_state, str(verification.get("message", "Nao foi possivel confirmar leitura e alteracao no Firebase.")))
		return

	if had_pending and not pending_before_sync.is_empty():
		# Merge the queued snapshot only after the official branch is in memory.
		_pending_snapshot = _merge_pending_snapshot_with_remote(remote_snapshot, pending_before_sync)
		_pending_dirty = not _pending_snapshot.is_empty()
		_keep_pending_snapshot(_pending_snapshot)
		_sync_busy = false
		_set_status("pending", "Base oficial carregada. Aplicando alteracoes pendentes...")
		call_deferred("_perform_pending_sync", true)
		return

	_pending_snapshot = {}
	_pending_dirty = false
	_clear_pending_sync_queue()
	_set_status("synced", "Dados carregados diretamente do Firebase." if remote_value != null else "Firebase online. Esta base ainda nao possui registros.")

	_sync_busy = false


func _merge_pending_snapshot_with_remote(remote_snapshot: Dictionary, pending_snapshot: Dictionary) -> Dictionary:
	var merged := _ensure_snapshot_shape(remote_snapshot)
	var pending := _ensure_snapshot_shape(pending_snapshot)
	for section in SECTIONS:
		var remote_rows: Array = merged.get(section, [])
		var pending_rows: Array = pending.get(section, [])
		merged[section] = _merge_pending_rows(section, remote_rows, pending_rows)
	var remote_runtime: Dictionary = merged.get("runtime", {})	
	var pending_runtime: Dictionary = pending.get("runtime", {})
	if not pending_runtime.is_empty():
		remote_runtime.merge(pending_runtime, true)
	merged["runtime"] = remote_runtime
	return merged


func _ensure_snapshot_shape(snapshot: Dictionary) -> Dictionary:
	var normalized := _empty_snapshot()
	for section in SECTIONS:
		var rows: Variant = snapshot.get(section, [])
		normalized[section] = rows.duplicate(true) if typeof(rows) == TYPE_ARRAY else []
	normalized["schema"] = int(snapshot.get("schema", 3))
	var runtime: Variant = snapshot.get("runtime", {})
	normalized["runtime"] = runtime.duplicate(true) if typeof(runtime) == TYPE_DICTIONARY else {}
	return normalized


func _merge_pending_rows(section: String, remote_rows: Array, pending_rows: Array) -> Array:
	var result: Array = remote_rows.duplicate(true)
	var indexes := {}
	for index in range(result.size()):
		var row: Variant = result[index]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var identity := _pending_row_identity(section, row as Dictionary, index)
		if identity != "":
			indexes[identity] = index
	for index in range(pending_rows.size()):
		var row: Variant = pending_rows[index]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var identity := _pending_row_identity(section, row as Dictionary, index)
		if identity != "" and indexes.has(identity):
			result[int(indexes[identity])] = (row as Dictionary).duplicate(true)
		else:
			if identity != "":
				indexes[identity] = result.size()
			result.append((row as Dictionary).duplicate(true))
	return result


func _pending_row_identity(section: String, row: Dictionary, index: int) -> String:
	var identity := ""
	match section:
		"products":
			identity = str(row.get("sku", row.get("imei", ""))).strip_edges()
		"movements", "system_logs", "maintenances":
			identity = str(row.get("id", "")).strip_edges()
	if identity == "":
		return "%s:%d:%s" % [section, index, _value_hash(row)]
	return "%s:%s" % [section, identity]


func _perform_pending_sync(initial_upload: bool = false) -> void:
	if _sync_busy or (not _pending_dirty and _pending_snapshot.is_empty()) or not _is_configured():
		return
	if _store == null:
		return
	if _store.has_method("is_remote_available") and not bool(_store.call("is_remote_available")) and _pending_snapshot.is_empty():
		return
	if _circuit_is_open():
		_keep_pending_snapshot(_pending_snapshot)
		_mark_store_unavailable()
		_set_status("offline", "Sem internet. Alteracao preservada para reenviar.")
		return

	_sync_busy = true
	var upload_generation := _change_generation
	var snapshot: Dictionary = _pending_snapshot.duplicate(true) \
		if not _pending_snapshot.is_empty() else _store.get_sync_snapshot()
	var local_hash := _snapshot_hash(snapshot)
	_set_status("syncing", "Enviando somente as alteracoes para o Firebase...")

	var branch_state := _branch_state()
	if not initial_upload:
		var meta_result := await _database_request(
			HTTPClient.METHOD_GET,
			"branches/%s/meta/content_hash" % _branch_id
		)
		if not bool(meta_result.get("ok", false)):
			_keep_pending_snapshot(snapshot)
			_set_status("offline", "Firebase indisponivel. Alteracao preservada para reenviar.")
			_sync_busy = false
			return
		var remote_hash_value: Variant = meta_result.get("data")
		var current_remote_hash := "" if remote_hash_value == null else str(remote_hash_value).strip_edges()
		var expected_remote_hash := str(branch_state.get("last_remote_hash", "")).strip_edges()
		if current_remote_hash != "" and expected_remote_hash != "" \
				and current_remote_hash != expected_remote_hash and current_remote_hash != local_hash:
			_keep_pending_snapshot(snapshot)
			_mark_store_unavailable()
			_set_status("conflict", "Existe uma alteracao local aguardando revisao. A fila foi preservada.")
			_sync_busy = false
			return

	var encoded := _encode_snapshot(snapshot)
	var patch := _build_incremental_patch(encoded, branch_state, local_hash)
	if patch.is_empty():
		_record_synced_state(snapshot, local_hash, local_hash)
		var changes_during_noop := upload_generation != _change_generation
		if not changes_during_noop:
			_pending_snapshot = {}
			_pending_dirty = false
		if _store.has_method("mark_remote_available"):
			_store.call("mark_remote_available")
		if not changes_during_noop:
			_restore_store_from_snapshot(snapshot)
			_clear_pending_sync_queue()
		_set_status("synced", "Firebase atualizado.")
		_sync_busy = false
		return

	var upload_result := await _database_request(
		HTTPClient.METHOD_PATCH,
		"branches/%s" % _branch_id,
		patch
	)
	if not bool(upload_result.get("ok", false)):
		_keep_pending_snapshot(snapshot)
		_mark_store_unavailable()
		_set_status("offline", "Firebase indisponivel. Alteracao preservada para reenviar.")
		_sync_busy = false
		return

	_record_synced_state(snapshot, local_hash, local_hash, encoded)
	var changes_during_upload := upload_generation != _change_generation
	if not changes_during_upload:
		_pending_snapshot = {}
		_pending_dirty = false
	_last_sync_at = Time.get_datetime_string_from_system(false, true)
	_restore_connection()
	if _store.has_method("mark_remote_available"):
		_store.call("mark_remote_available")
	if not changes_during_upload:
		_restore_store_from_snapshot(snapshot)
		_clear_pending_sync_queue()
	_set_status("synced", "Firebase atualizado com seguranca.")
	_sync_busy = false
	if _pending_dirty or not _pending_snapshot.is_empty():
		_sync_timer.start(SYNC_DEBOUNCE_SECONDS)


func _build_incremental_patch(encoded: Dictionary, branch_state: Dictionary, content_hash: String) -> Dictionary:
	var patch: Dictionary = {}
	var records: Dictionary = encoded.get("records", {})
	var orders: Dictionary = encoded.get("order", {})
	var current_hashes: Dictionary = encoded.get("record_hashes", {})
	var previous_hashes: Dictionary = branch_state.get("record_hashes", {})
	var previous_order_hashes: Dictionary = branch_state.get("order_hashes", {})

	for section in SECTIONS:
		var current_section: Dictionary = records.get(section, {})
		var current_section_hashes: Dictionary = current_hashes.get(section, {})
		var previous_section_hashes: Dictionary = previous_hashes.get(section, {})
		for key in current_section.keys():
			if str(previous_section_hashes.get(key, "")) != str(current_section_hashes.get(key, "")):
				patch["records/%s/%s" % [section, key]] = current_section.get(key)
		for key in previous_section_hashes.keys():
			if not current_section_hashes.has(key):
				patch["records/%s/%s" % [section, key]] = null

		var order: Array = orders.get(section, [])
		var order_hash := _value_hash(order)
		if str(previous_order_hashes.get(section, "")) != order_hash:
			patch["order/%s" % section] = order

	var runtime: Dictionary = encoded.get("runtime", {})
	var runtime_hash := _value_hash(runtime)
	if str(branch_state.get("runtime_hash", "")) != runtime_hash:
		patch["runtime"] = runtime

	patch["schema"] = int(encoded.get("schema", 0))
	patch["meta/content_hash"] = content_hash
	patch["meta/updated_at_ms"] = {".sv": "timestamp"}
	patch["meta/updated_by"] = _device_id()
	patch["meta/app_version"] = str(ProjectSettings.get_setting("application/config/version", ""))
	patch["meta/format"] = 1
	return patch


func _encode_snapshot(snapshot: Dictionary) -> Dictionary:
	var records: Dictionary = {}
	var orders: Dictionary = {}
	var record_hashes: Dictionary = {}
	for section in SECTIONS:
		var section_records: Dictionary = {}
		var section_order: Array[String] = []
		var section_hashes: Dictionary = {}
		var rows: Array = snapshot.get(section, [])
		for index in range(rows.size()):
			if typeof(rows[index]) != TYPE_DICTIONARY:
				continue
			var row := (rows[index] as Dictionary).duplicate(true)
			var key := _record_key(section, row, index)
			if section_records.has(key):
				key = "%s_%d" % [key, index]
			section_records[key] = row
			section_order.append(key)
			section_hashes[key] = _value_hash(row)
		records[section] = section_records
		orders[section] = section_order
		record_hashes[section] = section_hashes
	return {
		"schema": int(snapshot.get("schema", 0)),
		"records": records,
		"order": orders,
		"record_hashes": record_hashes,
		"runtime": (snapshot.get("runtime", {}) as Dictionary).duplicate(true) \
			if typeof(snapshot.get("runtime", {})) == TYPE_DICTIONARY else {},
	}


func _decode_remote_snapshot(envelope: Dictionary) -> Dictionary:
	var records: Dictionary = envelope.get("records", {})
	var orders: Dictionary = envelope.get("order", {})
	var snapshot := {
		"schema": int(envelope.get("schema", 0)),
		"products": [],
		"movements": [],
		"system_logs": [],
		"maintenances": [],
		"runtime": (envelope.get("runtime", {}) as Dictionary).duplicate(true) \
			if typeof(envelope.get("runtime", {})) == TYPE_DICTIONARY else {},
	}
	if records.is_empty():
		return {}
	for section in SECTIONS:
		var section_records: Dictionary = records.get(section, {})
		var section_order: Array = orders.get(section, [])
		var rows: Array = []
		for key_value in section_order:
			var key := str(key_value)
			if section_records.has(key) and typeof(section_records.get(key)) == TYPE_DICTIONARY:
				rows.append((section_records.get(key) as Dictionary).duplicate(true))
		if rows.is_empty() and not section_records.is_empty():
			var fallback_keys := section_records.keys()
			fallback_keys.sort()
			for key in fallback_keys:
				if typeof(section_records.get(key)) == TYPE_DICTIONARY:
					rows.append((section_records.get(key) as Dictionary).duplicate(true))
		snapshot[section] = rows
	return snapshot


func _record_synced_state(
		snapshot: Dictionary,
		local_hash: String,
		remote_hash: String,
		encoded: Dictionary = {}
	) -> void:
	var prepared := encoded if not encoded.is_empty() else _encode_snapshot(snapshot)
	var order_hashes: Dictionary = {}
	var orders: Dictionary = prepared.get("order", {})
	for section in SECTIONS:
		order_hashes[section] = _value_hash(orders.get(section, []))
	var branches: Dictionary = _state.get("branches", {})
	branches[_branch_id] = {
		"last_local_hash": local_hash,
		"last_remote_hash": remote_hash,
		"record_hashes": prepared.get("record_hashes", {}),
		"order_hashes": order_hashes,
		"runtime_hash": _value_hash(prepared.get("runtime", {})),
		"last_sync_at": Time.get_datetime_string_from_system(false, true),
	}
	_state["branches"] = branches
	_last_sync_at = str((branches[_branch_id] as Dictionary).get("last_sync_at", ""))


func _branch_state() -> Dictionary:
	var branches: Dictionary = _state.get("branches", {})
	var value: Variant = branches.get(_branch_id, {})
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


func _database_request(method: int, path: String, body: Variant = null) -> Dictionary:
	if _circuit_is_open():
		return {"ok": false, "offline": true}
	if not await _ensure_auth():
		return {"ok": false, "auth": true}

	var clean_path := path.strip_edges().trim_prefix("/")
	var silent_suffix := "&print=silent" \
		if method == HTTPClient.METHOD_PATCH or method == HTTPClient.METHOD_PUT or method == HTTPClient.METHOD_DELETE \
		else ""
	var url := "%s/%s.json?auth=%s%s" % [
		str(_config.get("database_url", "")).trim_suffix("/"),
		clean_path,
		_id_token.uri_encode(),
		silent_suffix,
	]
	var headers := PackedStringArray(["Accept: application/json"])
	var request_body := ""
	if body != null:
		headers.append("Content-Type: application/json")
		request_body = JSON.stringify(body)
	var result := await _raw_request(url, method, headers, request_body)
	if int(result.get("code", 0)) == 401:
		_id_token = ""
		_token_expires_at = 0
		if await _ensure_auth():
			url = "%s/%s.json?auth=%s%s" % [
				str(_config.get("database_url", "")).trim_suffix("/"),
				clean_path,
				_id_token.uri_encode(),
				silent_suffix,
			]
			result = await _raw_request(url, method, headers, request_body)
	if not bool(result.get("ok", false)):
		var response_code := int(result.get("code", 0))
		if response_code == 401 or response_code == 403:
			_mark_store_unavailable()
			_set_status("auth_error", "O Firebase recusou a credencial. Dados indisponiveis.")
		return result
	var text := str(result.get("body", "")).strip_edges()
	result["data"] = JSON.parse_string(text) if text != "" else null
	return result


func _ensure_auth() -> bool:
	if _id_token != "" and Time.get_unix_time_from_system() < _token_expires_at - 60:
		return true
	if _refresh_token == "":
		_mark_store_unavailable()
		_set_status("auth_error", "Credencial do Firebase ausente.")
		return false
	if _circuit_is_open():
		return false

	var api_key := str(_config.get("api_key", "")).strip_edges()
	var url := "https://securetoken.googleapis.com/v1/token?key=%s" % api_key.uri_encode()
	var form := "grant_type=refresh_token&refresh_token=%s" % _refresh_token.uri_encode()
	var result := await _raw_request(
		url,
		HTTPClient.METHOD_POST,
		PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),
		form
	)
	if not bool(result.get("ok", false)):
		if not bool(result.get("offline", false)):
			_mark_store_unavailable()
			_set_status("auth_error", "O Firebase recusou a credencial de sincronizacao.")
		return false
	var parsed: Variant = JSON.parse_string(str(result.get("body", "")))
	if typeof(parsed) != TYPE_DICTIONARY:
		_mark_store_unavailable()
		_set_status("auth_error", "Resposta de autenticacao invalida.")
		return false
	var auth := parsed as Dictionary
	_id_token = str(auth.get("id_token", "")).strip_edges()
	_refresh_token = str(auth.get("refresh_token", _refresh_token)).strip_edges()
	_token_expires_at = int(Time.get_unix_time_from_system()) + int(str(auth.get("expires_in", "3600")))
	if _id_token == "":
		_mark_store_unavailable()
		_set_status("auth_error", "Token do Firebase nao recebido.")
		return false
	_config["refresh_token"] = _refresh_token
	_write_json_dictionary(CONFIG_PATH, _config)
	return true


func _raw_request(url: String, method: int, headers: PackedStringArray, body: String) -> Dictionary:
	var wait_deadline := Time.get_ticks_msec() + int(REQUEST_TIMEOUT_SECONDS * 1000.0)
	while _request_in_flight and Time.get_ticks_msec() < wait_deadline:
		await get_tree().process_frame
	if _request_in_flight:
		return {"ok": false, "busy": true}
	_request_in_flight = true
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(http)
	var started_at := Time.get_ticks_msec()
	var start_error := http.request(url, headers, method, body)
	if start_error != OK:
		http.queue_free()
		_request_in_flight = false
		_trip_circuit("Sem conexao com o servidor.")
		return {"ok": false, "offline": true, "error": start_error}

	var completed: Array = await http.request_completed
	_last_latency_ms = maxi(Time.get_ticks_msec() - started_at, 0)
	http.queue_free()
	_request_in_flight = false
	var request_result := int(completed[0])
	var response_code := int(completed[1])
	var response_headers: PackedStringArray = completed[2]
	var response_body: PackedByteArray = completed[3]
	var body_text := response_body.get_string_from_utf8()
	if request_result != HTTPRequest.RESULT_SUCCESS or response_code == 0 \
			or response_code == 408 or response_code == 429 or response_code >= 500:
		_trip_circuit("Conexao instavel. O acesso remoto foi pausado.")
		return {
			"ok": false,
			"offline": true,
			"result": request_result,
			"code": response_code,
			"body": body_text,
		}
	var ok := response_code >= 200 and response_code < 300
	if ok:
		_restore_connection()
	return {
		"ok": ok,
		"code": response_code,
		"headers": response_headers,
		"body": body_text,
	}


func _trip_circuit(message: String) -> void:
	_failure_count += 1
	_read_verified = false
	_write_verified = false
	var delay := minf(INITIAL_RETRY_SECONDS * pow(2.0, float(_failure_count - 1)), MAX_RETRY_SECONDS)
	_circuit_open_until = int(Time.get_unix_time_from_system() + delay)
	_probe_timer.start(delay)
	_mark_store_unavailable()
	_set_status("offline", message)


func _restore_connection() -> void:
	_failure_count = 0
	_circuit_open_until = 0
	if _probe_timer != null:
		_probe_timer.stop()


func _circuit_is_open() -> bool:
	return _circuit_open_until > int(Time.get_unix_time_from_system())


func _set_status(state: String, message: String) -> void:
	_status = {
		"state": state,
		"message": message,
		"pending": _pending_dirty or not _pending_snapshot.is_empty(),
		"latency_ms": _last_latency_ms,
		"last_sync_at": _last_sync_at,
		"failure_count": _failure_count,
		"retry_at": _circuit_open_until,
		"read_ok": _read_verified,
		"write_ok": _write_verified,
		"verified_at": _last_probe_at,
		"probe_message": _last_probe_message,
	}
	status_changed.emit(get_status())


func _verify_connection_read_write() -> Dictionary:
	var probe_id := _device_id().sha256_text().left(24)
	var probe_path := "%s/%s" % [CONNECTION_PROBE_ROOT, probe_id]
	var probe_time := Time.get_datetime_string_from_system(false, true)
	var nonce := "%s-%s" % [str(Time.get_ticks_msec()), probe_id]
	var payload := {
		"client": "Grupo RS Central",
		"app_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"branch": _branch_id,
		"verified_at": probe_time,
		"nonce": nonce,
	}

	var write_result := await _database_request(HTTPClient.METHOD_PUT, probe_path, payload)
	var read_result := await _database_request(HTTPClient.METHOD_GET, probe_path)
	var returned: Variant = read_result.get("data")
	var readback_ok := typeof(returned) == TYPE_DICTIONARY \
		and str((returned as Dictionary).get("nonce", "")) == nonce
	var cleanup_result := await _database_request(HTTPClient.METHOD_DELETE, probe_path)

	_read_verified = bool(read_result.get("ok", false)) and readback_ok
	_write_verified = bool(write_result.get("ok", false)) and readback_ok
	_last_probe_at = Time.get_datetime_string_from_system(false, true)
	var cleanup_text := ""
	if not bool(cleanup_result.get("ok", false)):
		cleanup_text = " O registro temporario sera limpo na proxima verificacao."

	if _read_verified and _write_verified:
		var heartbeat := await _write_health_heartbeat()
		if not bool(heartbeat.get("ok", false)):
			_last_probe_message = "Consulta e alteracao confirmadas, mas o pulso nao foi atualizado."
			return {
				"ok": false,
				"state": "offline",
				"message": "Firebase confirmou consulta e alteracao, mas nao atualizou o pulso de saude.",
			}
		# A limpeza do probe e uma rotina de manutencao. Algumas regras do
		# Firebase permitem PUT/GET em health, mas bloqueiam DELETE; isso nao
		# pode transformar uma conexao operacionalmente valida em indisponivel.
		if _store != null and _store.has_method("mark_remote_available"):
			_store.call("mark_remote_available")
		_last_probe_message = "Consulta e alteracao autenticadas confirmadas.%s" % cleanup_text
		return {
			"ok": true,
			"state": "synced",
			"message": "Firebase confirmado: consulta e alteracao funcionando.%s" % cleanup_text,
		}

	var transport_offline := bool(write_result.get("offline", false)) \
		or bool(read_result.get("offline", false))
	var auth_failure := int(write_result.get("code", 0)) in [401, 403] \
		or int(read_result.get("code", 0)) in [401, 403]
	var state := "offline" if transport_offline else ("auth_error" if auth_failure else "degraded")
	_last_probe_message = "Consulta=%s | Alteracao=%s" % [
		"OK" if _read_verified else "falhou",
		"OK" if _write_verified else "falhou",
	]
	return {
		"ok": false,
		"state": state,
		"offline": transport_offline,
		"message": "Consulta=%s | Alteracao=%s. Dados bloqueados ate a verificacao passar." % [
			"OK" if _read_verified else "falhou",
			"OK" if _write_verified else "falhou",
		],
	}


func _write_health_heartbeat() -> Dictionary:
	return await _database_request(
		HTTPClient.METHOD_PATCH,
		"health/ping",
		{
			"app_version": str(ProjectSettings.get_setting("application/config/version", "")),
			"client": "Grupo RS Central Desktop",
			"status": "healthy",
			"tested_at": Time.get_datetime_string_from_system(false, true),
			"verified_at": Time.get_unix_time_from_system() * 1000,
		}
	)


func _keep_pending_snapshot(snapshot: Dictionary = {}) -> void:
	var preserved := snapshot.duplicate(true)
	if preserved.is_empty() and not _pending_snapshot.is_empty():
		preserved = _pending_snapshot.duplicate(true)
	if preserved.is_empty() and _store != null \
			and _store.has_method("is_remote_available") \
			and bool(_store.call("is_remote_available")) \
			and _store.has_method("get_sync_snapshot"):
		preserved = _store.call("get_sync_snapshot")
	if preserved.is_empty():
		return
	_pending_snapshot = preserved
	_pending_dirty = true
	if _store != null and _store.has_method("queue_pending_sync_snapshot"):
		_store.call("queue_pending_sync_snapshot", preserved)


func _pending_sync_count() -> int:
	if _store != null and _store.has_method("get_pending_sync_status"):
		var status: Variant = _store.call("get_pending_sync_status")
		if typeof(status) == TYPE_DICTIONARY:
			return int((status as Dictionary).get("count", 0))
	return 1 if _pending_dirty or not _pending_snapshot.is_empty() else 0


func _pending_sync_limit() -> int:
	if _store != null and _store.has_method("get_pending_sync_status"):
		var status: Variant = _store.call("get_pending_sync_status")
		if typeof(status) == TYPE_DICTIONARY:
			return int((status as Dictionary).get("limit", 10))
	return 10


func _clear_pending_sync_queue() -> void:
	if _store != null and _store.has_method("clear_pending_sync_queue"):
		_store.call("clear_pending_sync_queue")


func _restore_store_from_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.is_empty() or _store == null or not _store.has_method("replace_from_remote"):
		return false
	return bool(_store.call("replace_from_remote", snapshot))


func _mark_store_unavailable() -> void:
	if _store != null and _store.has_method("mark_remote_unavailable"):
		_store.call("mark_remote_unavailable")


func _empty_snapshot() -> Dictionary:
	return {
		"schema": 3,
		"products": [],
		"movements": [],
		"system_logs": [],
		"maintenances": [],
		"runtime": {},
	}


func _snapshot_hash(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return ""
	return _value_hash(snapshot)


func _value_hash(value: Variant) -> String:
	return JSON.stringify(_canonicalize(value)).sha256_text()


func _canonicalize(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var source := value as Dictionary
		var keys := source.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var result: Dictionary = {}
		for key in keys:
			result[str(key)] = _canonicalize(source.get(key))
		return result
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item in value as Array:
			result.append(_canonicalize(item))
		return result
	return value


func _record_key(section: String, row: Dictionary, index: int) -> String:
	var identity := ""
	match section:
		"products":
			identity = str(row.get("sku", row.get("imei", "")))
		"movements", "system_logs", "maintenances":
			identity = str(row.get("id", ""))
	if identity.strip_edges() == "":
		identity = "%s:%d:%s" % [section, index, _value_hash(row)]
	return "%s_%s" % [section.left(1), identity.sha256_text().left(32)]


func _normalize_branch_id(value: String) -> String:
	var clean := value.strip_edges().to_lower()
	if clean == "":
		return "imperatriz"
	return clean


func _device_id() -> String:
	var device_id := str(_config.get("device_id", "")).strip_edges()
	if device_id != "":
		return device_id
	device_id = "windows-%s" % str(OS.get_unique_id()).sha256_text().left(16)
	_config["device_id"] = device_id
	_write_json_dictionary(CONFIG_PATH, _config)
	return device_id


func _is_configured() -> bool:
	return bool(_config.get("enabled", false)) \
		and str(_config.get("database_url", "")).strip_edges() != "" \
		and str(_config.get("api_key", "")).strip_edges() != "" \
		and str(_config.get("refresh_token", "")).strip_edges() != ""


func _read_json_dictionary(path: String) -> Dictionary:
	var result := _read_json_dictionary_raw(path)
	if path != CONFIG_PATH:
		return result
	var vault := _secret_vault()
	if vault == null:
		return result
	var sanitized: Dictionary = vault.call(
		"extract_secrets",
		"firebase",
		result,
		SecretVaultScript.FIREBASE_SECRET_KEYS
	)
	if sanitized != result:
		_write_json_dictionary_raw(path, sanitized)
	return vault.call(
		"merge_secrets",
		"firebase",
		sanitized,
		SecretVaultScript.FIREBASE_SECRET_KEYS
	)


func _read_json_dictionary_raw(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file = null
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _write_json_dictionary(path: String, data: Dictionary) -> bool:
	var stored_data := data.duplicate(true)
	if path == CONFIG_PATH:
		var vault := _secret_vault()
		if vault != null:
			stored_data = vault.call(
				"extract_secrets",
				"firebase",
				stored_data,
				SecretVaultScript.FIREBASE_SECRET_KEYS
			)
	return _write_json_dictionary_raw(path, stored_data)


func _write_json_dictionary_raw(path: String, data: Dictionary) -> bool:
	var temp_path := "%s.tmp" % path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file = null
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var rename_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(path)
	)
	return rename_error == OK


func _secret_vault() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var vault := tree.root.get_node_or_null("SecretVault")
	if vault != null:
		return vault
	vault = SecretVaultScript.new()
	vault.name = "SecretVault"
	tree.root.add_child(vault)
	return vault
