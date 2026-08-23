extends SceneTree

const StoreScript := preload("res://src/inventory_store.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store := StoreScript.new()
	var db_path := "user://__codex_online_only_inventory.json"
	var backup_name := "__codex_online_only_inventory.json"
	var backup_dir := "user://__codex_online_only_backups"
	_write_legacy_file(db_path)

	store.configure(db_path, backup_name, backup_dir, false)
	store.load_db()
	_check(not store.is_remote_available(), "A base iniciou liberada sem Firebase.")
	_check(store.get_products().is_empty(), "Dados locais antigos foram lidos.")
	var offline_product := store.upsert_product({"sku": "024999999", "name": "Offline"})
	_check(not offline_product.is_empty(), "Gravacao offline nao entrou na fila.")
	_check(int(store.get_pending_sync_status().get("count", 0)) == 1, "Fila offline nao registrou a alteracao.")
	store.clear_pending_sync_queue()

	var firebase := root.get_node_or_null("FirebaseSync")
	if firebase == null:
		var firebase_script := load("res://src/firebase_sync.gd")
		firebase = firebase_script.new() if firebase_script != null else null
		if firebase != null:
			root.add_child(firebase)
			await process_frame
	_check(firebase != null, "FirebaseSync nao foi carregado.")
	if firebase == null:
		_finish()
		return

	firebase.call("bind_store", store, "imperatriz")
	var connected := await _wait_for_data(firebase, 35.0)
	_check(connected, "Firebase nao liberou os dados no tempo esperado.")
	if connected:
		await _wait_for_sync_idle(firebase, 10.0)
		_check(store.is_remote_available(), "Store permaneceu bloqueado depois da leitura remota.")
		_check(not store.get_products().is_empty(), "Firebase retornou sem os cadastros de Imperatriz.")
		_check(store.get_product("024999999").is_empty(), "O teste deixou um registro ficticio na filial real.")
		_check(not FileAccess.file_exists(db_path), "Arquivo operacional local permaneceu no disco.")
		_check(store.get_cloud_backup_path() == "", "Google Drive continuou habilitado.")

		firebase.call("_trip_circuit", "Teste controlado sem internet.")
		await process_frame
		_check(not store.is_remote_available(), "Dados continuaram liberados depois da queda.")
		_check(not store.get_products().is_empty(), "A copia em memoria foi perdida durante a queda.")
		_check(not bool(firebase.call("get_status").get("data_available", true)), "Status ainda informou dados disponiveis.")

		firebase.set("_circuit_open_until", 0)
		await firebase.call("_initial_sync")
		await _wait_for_sync_idle(firebase, 10.0)
		var reconnected := await _wait_for_data(firebase, 20.0)
		_check(reconnected, "Dados nao voltaram apos a reconexao.")
		_check(not store.get_products().is_empty(), "Reconexao nao recarregou a copia oficial.")
		await _check_disposable_online_write(firebase)

	_finish()


func _wait_for_data(firebase: Node, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var status: Dictionary = firebase.call("get_status")
		if bool(status.get("data_available", false)):
			return true
		await create_timer(0.1).timeout
	return false


func _wait_for_sync_idle(firebase: Node, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not bool(firebase.get("_sync_busy")):
			return true
		await create_timer(0.1).timeout
	return not bool(firebase.get("_sync_busy"))


func _check_disposable_online_write(firebase: Node) -> void:
	var write_store := StoreScript.new()
	write_store.configure(
		"user://__codex_online_write.json",
		"__codex_online_write.json",
		"user://__codex_online_write_backups",
		false
	)
	write_store.clear_pending_sync_queue()
	firebase.call("bind_store", write_store, "imperatriz")
	var connected := await _wait_for_data(firebase, 20.0)
	_check(connected, "Filial descartavel nao ficou online.")
	if not connected:
		return
	await _wait_for_sync_idle(firebase, 10.0)

	var marker := "probe-%s" % Time.get_ticks_msec()
	_check(write_store.set_runtime_state("online_only_probe", {"marker": marker}), "Estado online nao entrou na fila.")
	var sync_deadline := Time.get_ticks_msec() + 15000
	var last_sync_status: Dictionary = {}
	while Time.get_ticks_msec() < sync_deadline:
		last_sync_status = firebase.call("get_status")
		if str(last_sync_status.get("state", "")) == "synced" and not bool(last_sync_status.get("pending", true)):
			break
		await create_timer(0.1).timeout
	var deadline := Time.get_ticks_msec() + 10000
	var confirmed := false
	var last_remote: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.2).timeout
		last_remote = await firebase.call(
			"_database_request",
			HTTPClient.METHOD_GET,
			"branches/imperatriz/runtime/online_only_probe"
		)
		if bool(last_remote.get("ok", false)) and typeof(last_remote.get("data")) == TYPE_DICTIONARY \
				and str((last_remote.get("data") as Dictionary).get("marker", "")) == marker:
			confirmed = true
			break
	_check(confirmed, "Firebase nao confirmou a gravacao descartavel.")
	await firebase.call(
		"_database_request",
		HTTPClient.METHOD_DELETE,
		"branches/imperatriz/runtime/online_only_probe"
	)


func _write_legacy_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string('{"schema":3,"products":[{"sku":"024111111","name":"LOCAL PROIBIDO"}]}')


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("ONLINE_ONLY_CHECK_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
