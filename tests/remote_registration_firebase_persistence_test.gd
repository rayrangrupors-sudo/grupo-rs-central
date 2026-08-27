extends SceneTree

var failed := false


class QueueHost:
	extends Node

	var scenario := "success"
	var api_calls := 0
	var finalize_calls := 0
	var firebase_calls := 0
	var records: Array[Dictionary] = []
	var table_rows: Array[Dictionary] = []

	func _dismiss_equipment_registration_feedback() -> void:
		pass

	func _format_grupo_rs_vehicle_plate(value: String) -> String:
		return value.strip_edges()

	func _perform_equipment_registration(_request: Dictionary) -> Dictionary:
		api_calls += 1
		if scenario == "duplicate_guard":
			await get_tree().create_timer(0.1).timeout
		if scenario == "api_error":
			return {"ok": false, "message": "API recusou o cadastro."}
		if scenario == "confirmation_pending":
			return {
				"ok": true,
				"partial": true,
				"confirmation_pending": true,
				"message": "API aceitou, mas leitura remota ainda pendente.",
				"request": _request.duplicate(true),
			}
		return {"ok": true, "api_vehicle": true}

	func _finalize_local_equipment_registration(_local_product: Dictionary, request: Dictionary) -> Dictionary:
		finalize_calls += 1
		var serial := str(request.get("serial", ""))
		for record in records:
			if str(record.get("serial", "")) == serial:
				return {"ok": true, "product": record}
		var product := {"sku": serial, "imei": serial, "plate": str(request.get("plate", "")), "serial": serial}
		records.append(product)
		table_rows = records.duplicate(true)
		return {"ok": true, "product": product}

	func _ensure_firebase_modification_saved(_serial: String, _expected_product: Dictionary) -> Dictionary:
		firebase_calls += 1
		if scenario == "firebase_error":
			return {"ok": false, "message": "Firebase indisponivel para confirmacao."}
		return {"ok": true}

	func _log_system_action(_action: String, _details: String, _serial: String = "") -> void:
		pass

	func simulate_reopen_and_sync() -> void:
		table_rows = records.duplicate(true)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for queue_path in [
		"res://src/remote_operation_queue_current.gd",
		"res://src/remote_operation_queue.gd",
	]:
		await _check_successful_new_registration(queue_path)
		await _check_api_failure(queue_path)
		await _check_firebase_failure(queue_path)
		await _check_confirmation_pending(queue_path)
		await _check_duplicate_guard(queue_path)
		await _check_reopen_sync_and_table_after_confirmation(queue_path)
	if failed:
		quit(1)
	else:
		print("REMOTE_REGISTRATION_FIREBASE_PERSISTENCE_TEST_OK")
		quit(0)


func _new_queue(host: QueueHost, queue_path: String) -> Node:
	var queue_script = load(queue_path)
	var queue: Node = queue_script.new()
	root.add_child(queue)
	queue.configure(host)
	return queue


func _wait_for_queue(queue: Node, queue_id: String) -> Dictionary:
	for _index in range(30):
		await root.get_tree().create_timer(0.02).timeout
		if not queue.active.has(queue_id):
			break
	for item in queue.items:
		if str(item.get("id", "")) == queue_id:
			return item
	return {}


func _enqueue(host: QueueHost, queue: Node, serial: String) -> String:
	return queue.enqueue("Cadastro", {}, {"serial": serial, "plate": "TEST-01"})


func _check_successful_new_registration(queue_path: String) -> void:
	var host := QueueHost.new()
	root.add_child(host)
	var queue := _new_queue(host, queue_path)
	var queue_id := _enqueue(host, queue, "100000001")
	_expect(queue_id != "", "%s: cadastro novo nao entrou na fila." % queue_path)
	var item := await _wait_for_queue(queue, queue_id)
	_expect(str(item.get("state", "")) == "success", "%s: cadastro confirmado nao terminou com sucesso." % queue_path)
	_expect(int(host.api_calls) == 1, "%s: cadastro novo nao chamou a API uma vez." % queue_path)
	_expect(int(host.finalize_calls) == 1, "%s: cadastro novo nao atualizou o registro local uma vez." % queue_path)
	_expect(int(host.firebase_calls) == 1, "%s: cadastro novo nao confirmou a persistencia no Firebase." % queue_path)
	_expect(host.records.size() == 1, "%s: cadastro novo gerou mais de um registro local." % queue_path)
	queue.queue_free()
	host.queue_free()


func _check_api_failure(queue_path: String) -> void:
	var host := QueueHost.new()
	host.scenario = "api_error"
	root.add_child(host)
	var queue := _new_queue(host, queue_path)
	var queue_id := _enqueue(host, queue, "100000002")
	var item := await _wait_for_queue(queue, queue_id)
	_expect(str(item.get("state", "")) == "error", "%s: falha da API nao foi apresentada como erro." % queue_path)
	_expect(int(host.finalize_calls) == 0, "%s: falha da API finalizou cadastro local." % queue_path)
	_expect(int(host.firebase_calls) == 0, "%s: falha da API tentou gravar no Firebase." % queue_path)
	queue.queue_free()
	host.queue_free()


func _check_firebase_failure(queue_path: String) -> void:
	var host := QueueHost.new()
	host.scenario = "firebase_error"
	root.add_child(host)
	var queue := _new_queue(host, queue_path)
	var queue_id := _enqueue(host, queue, "100000003")
	var item := await _wait_for_queue(queue, queue_id)
	_expect(str(item.get("state", "")) == "pending", "%s: falha do Firebase nao preservou a operacao como pendente." % queue_path)
	_expect(int(host.finalize_calls) == 1, "%s: falha do Firebase descartou a atualizacao local." % queue_path)
	_expect(int(host.firebase_calls) == 1, "%s: falha do Firebase nao foi confirmada uma vez." % queue_path)
	_expect(host.records.size() == 1, "%s: falha do Firebase duplicou o registro local." % queue_path)
	_expect(host.table_rows.size() == 1, "%s: tabela local nao preservou o registro pendente para sincronizacao posterior." % queue_path)
	queue.queue_free()
	host.queue_free()


func _check_confirmation_pending(queue_path: String) -> void:
	var host := QueueHost.new()
	host.scenario = "confirmation_pending"
	root.add_child(host)
	var queue := _new_queue(host, queue_path)
	var queue_id := _enqueue(host, queue, "100000005")
	var item := await _wait_for_queue(queue, queue_id)
	_expect(str(item.get("state", "")) == "pending", "%s: confirmacao remota pendente nao ficou como pendente." % queue_path)
	_expect(int(host.finalize_calls) == 0, "%s: confirmacao remota pendente finalizou Store local." % queue_path)
	_expect(int(host.firebase_calls) == 0, "%s: confirmacao remota pendente tentou Firebase antes da leitura remota." % queue_path)
	_expect(host.table_rows.is_empty(), "%s: tabela foi atualizada antes da confirmacao remota." % queue_path)
	queue.queue_free()
	host.queue_free()


func _check_duplicate_guard(queue_path: String) -> void:
	var host := QueueHost.new()
	host.scenario = "duplicate_guard"
	root.add_child(host)
	var queue := _new_queue(host, queue_path)
	var first_id := _enqueue(host, queue, "100000004")
	_expect(first_id != "", "%s: primeiro cadastro do teste de duplicidade nao entrou na fila." % queue_path)
	var second_id := _enqueue(host, queue, "100000004")
	_expect(second_id == "", "%s: repeticao durante a operacao nao foi bloqueada." % queue_path)
	await _wait_for_queue(queue, first_id)
	_expect(int(host.api_calls) == 1, "%s: a repeticao provocou uma segunda chamada da API." % queue_path)
	_expect(host.records.size() == 1, "%s: a repeticao gerou duplicidade local." % queue_path)
	queue.queue_free()
	host.queue_free()


func _check_reopen_sync_and_table_after_confirmation(queue_path: String) -> void:
	var host := QueueHost.new()
	root.add_child(host)
	var queue := _new_queue(host, queue_path)
	var queue_id := _enqueue(host, queue, "100000006")
	var item := await _wait_for_queue(queue, queue_id)
	_expect(str(item.get("state", "")) == "success", "%s: cadastro confirmado nao concluiu antes da simulacao de reabertura." % queue_path)
	_expect(host.table_rows.size() == 1, "%s: tabela nao foi atualizada apos API, Store e Firebase confirmados." % queue_path)
	host.table_rows.clear()
	host.simulate_reopen_and_sync()
	_expect(host.table_rows.size() == 1, "%s: reabertura/sincronizacao nao preservou registro confirmado." % queue_path)
	_expect(str(host.table_rows[0].get("plate", "")) != "", "%s: tabela sincronizada perdeu a placa confirmada." % queue_path)
	queue.queue_free()
	host.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failed = true
