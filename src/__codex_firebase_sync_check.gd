extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sync_script := load("res://src/firebase_sync.gd")
	var store_script := load("res://src/inventory_store.gd")
	var dashboard_script := load("res://src/inventory_dashboard.gd")
	if sync_script == null or store_script == null or dashboard_script == null:
		_fail("Dependencias do Firebase nao carregaram.")
		return

	var sync: Node = sync_script.new()
	root.add_child(sync)
	await process_frame

	var snapshot := {
		"schema": 3,
		"products": [
			{"sku": "024300001", "operator": "Claro", "updated_at": "2026-07-24T10:00:00"},
			{"sku": "024300002", "operator": "Tim", "updated_at": "2026-07-24T10:00:00"},
		],
		"movements": [{"id": "mov-1", "sku": "024300001"}],
		"system_logs": [{"id": "log-1", "action": "Teste"}],
		"maintenances": [{"id": "mnt-1", "serial": "024300002"}],
	}
	var encoded: Dictionary = sync.call("_encode_snapshot", snapshot)
	var initial_patch: Dictionary = sync.call(
		"_build_incremental_patch",
		encoded,
		{},
		sync.call("_snapshot_hash", snapshot)
	)
	if _record_write_count(initial_patch) != 5:
		_fail("Carga inicial nao separou os cinco registros: %s" % str(initial_patch.keys()))
		return

	var prior_state := _state_from_encoded(sync, encoded, snapshot)
	var no_change_patch: Dictionary = sync.call(
		"_build_incremental_patch",
		encoded,
		prior_state,
		sync.call("_snapshot_hash", snapshot)
	)
	if _record_write_count(no_change_patch) != 0:
		_fail("Sincronizacao sem mudanca reenviaria registros.")
		return

	var changed_snapshot: Dictionary = snapshot.duplicate(true)
	(changed_snapshot["products"] as Array)[1]["operator"] = "Vivo"
	var changed_encoded: Dictionary = sync.call("_encode_snapshot", changed_snapshot)
	var changed_patch: Dictionary = sync.call(
		"_build_incremental_patch",
		changed_encoded,
		prior_state,
		sync.call("_snapshot_hash", changed_snapshot)
	)
	if _record_write_count(changed_patch) != 1:
		_fail("Uma alteracao local nao gerou exatamente um registro remoto.")
		return

	var remote_snapshot := {
		"schema": 3,
		"products": [{"sku": "024300010", "operator": "Tim"}],
		"movements": [{"id": "remote-movement", "sku": "024300010"}],
		"system_logs": [{"id": "remote-log", "action": "Remoto"}],
		"maintenances": [],
		"runtime": {"remote_state": {"ok": true}},
	}
	var incomplete_pending := {
		"schema": 3,
		"products": [],
		"movements": [],
		"system_logs": [{"id": "pending-log", "action": "Pendente"}],
		"maintenances": [],
		"runtime": {"pending_state": {"queued": true}},
	}
	var merged: Dictionary = sync.call("_merge_pending_snapshot_with_remote", remote_snapshot, incomplete_pending)
	if (merged.get("products", []) as Array).size() != 1 \
			or (merged.get("movements", []) as Array).size() != 1 \
			or (merged.get("system_logs", []) as Array).size() != 2 \
			or not (merged.get("runtime", {}) as Dictionary).has("remote_state") \
			or not (merged.get("runtime", {}) as Dictionary).has("pending_state"):
		_fail("Bootstrap de pendencias descartou dados oficiais: %s" % str(merged))
		return

	sync.set("_config", {
		"enabled": true,
		"database_url": "http://127.0.0.1:9",
		"api_key": "test",
		"refresh_token": "test",
	})
	sync.set("_branch_id", "imperatriz")
	sync.set("_id_token", "test-token")
	sync.set("_token_expires_at", int(Time.get_unix_time_from_system()) + 600)
	var failed_request: Dictionary = await sync.call("_database_request", HTTPClient.METHOD_GET, "health/ping")
	if bool(failed_request.get("ok", false)):
		_fail("Servidor indisponivel foi tratado como online.")
		return
	var failures_before_save := int((sync.call("get_status") as Dictionary).get("failure_count", 0))
	sync.call("on_database_saved", changed_snapshot, "user://test.json")
	await create_timer(0.2).timeout
	var offline_status: Dictionary = sync.call("get_status")
	if str(offline_status.get("state", "")) != "offline" \
			or not bool(offline_status.get("pending", false)) \
			or bool(sync.get("_request_in_flight")) \
			or int(offline_status.get("failure_count", 0)) != failures_before_save:
		_fail("Modo local nao reteve a mudanca sem iniciar requisicao: %s" % str(offline_status))
		return

	# A sonda ativa deve detectar a queda mesmo sem existir uma alteracao pendente.
	# Usa uma instancia isolada e um endpoint local invalido; nenhuma credencial
	# ou dado operacional real e alterado neste caso.
	var probe_sync: Node = sync_script.new()
	root.add_child(probe_sync)
	await process_frame
	var probe_store: RefCounted = store_script.new()
	probe_store.configure("user://__codex_probe.json", "__codex_probe.json", "user://__codex_probe_backups", false)
	probe_store.load_db()
	probe_sync.set("_store", probe_store)
	probe_sync.set("_branch_id", "imperatriz")
	probe_sync.set("_config", {
		"enabled": true,
		"database_url": "http://127.0.0.1:9",
		"api_key": "test",
		"refresh_token": "test",
	})
	probe_sync.set("_id_token", "test-token")
	probe_sync.set("_token_expires_at", int(Time.get_unix_time_from_system()) + 600)
	var probe_status: Dictionary = await probe_sync.call("refresh_remote", true)
	if str(probe_status.get("state", "")) != "offline" or bool(probe_status.get("data_available", true)):
		_fail("Sonda ativa nao sinalizou a queda sem alteracao pendente: %s" % str(probe_status))
		return
	probe_sync.queue_free()
	await process_frame

	var dashboard: Control = dashboard_script.new()
	root.add_child(dashboard)
	var panel: Control = dashboard.call("_build_situation_panel", {})
	dashboard.add_child(panel)
	await process_frame
	if not _has_label_fragment(panel, "Saude do servidor") or not _has_label_fragment(panel, "FIREBASE REALTIME DATABASE"):
		_fail("Painel de saude do servidor nao foi montado: %s" % str(_label_texts(panel)))
		return
	panel.free()
	var operator_panel: Control = dashboard.call(
		"_build_operator_panel",
		{"total": 2, "operators": {"Claro": 1, "Tim": 1}}
	)
	dashboard.add_child(operator_panel)
	await process_frame
	if not _has_label_fragment(operator_panel, "Aparelhos por operadora"):
		_fail("Grafico exclusivo de operadoras nao foi montado: %s" % str(_label_texts(operator_panel)))
	if _has_label_fragment(operator_panel, "Comunicacao dos veiculos") or _has_button_text(operator_panel, "Comunicacao"):
		_fail("Funcao de comunicacao de veiculos ainda apareceu no painel.")
	operator_panel.free()
	dashboard.free()
	sync.free()

	print("FIREBASE_SYNC_CHECK_OK")
	quit(0)


func _state_from_encoded(sync: Node, encoded: Dictionary, snapshot: Dictionary) -> Dictionary:
	var order_hashes: Dictionary = {}
	var orders: Dictionary = encoded.get("order", {})
	for section in ["products", "movements", "system_logs", "maintenances"]:
		order_hashes[section] = sync.call("_value_hash", orders.get(section, []))
	var hash_value: String = sync.call("_snapshot_hash", snapshot)
	return {
		"last_local_hash": hash_value,
		"last_remote_hash": hash_value,
		"record_hashes": encoded.get("record_hashes", {}),
		"order_hashes": order_hashes,
	}


func _record_write_count(patch: Dictionary) -> int:
	var count := 0
	for key in patch.keys():
		if str(key).begins_with("records/"):
			count += 1
	return count


func _has_label_fragment(node: Node, text_value: String) -> bool:
	if node is Label and str((node as Label).text).contains(text_value):
		return true
	for child in node.get_children():
		if _has_label_fragment(child, text_value):
			return true
	return false


func _label_texts(node: Node) -> Array[String]:
	var result: Array[String] = []
	if node is Label:
		result.append(str((node as Label).text))
	for child in node.get_children():
		result.append_array(_label_texts(child))
	return result


func _has_button_text(node: Node, text_value: String) -> bool:
	if node is Button and str((node as Button).text).to_lower().contains(text_value.to_lower()):
		return true
	for child in node.get_children():
		if _has_button_text(child, text_value):
			return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
