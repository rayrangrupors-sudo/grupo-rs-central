extends SceneTree


class RegistrationStub:
	extends "res://src/inventory_dashboard.gd"
	var api_vehicle_calls := 0
	var web_fallback_calls := 0

	func _await_registration_probe_data(request: Dictionary) -> Dictionary:
		return request

	func _remote_queue_stage(_request: Dictionary, _stage: String, _detail: String = "", _state: String = "running", _source: String = "API principal") -> void:
		pass

	func _equipment_registration_timed_out() -> bool:
		return false

	func _register_or_find_modern_equipment(_request: Dictionary) -> Dictionary:
		return {"ok": true, "row": {"codEquipamento": 9001, "numeroSerie": "024313111"}}

	func _confirm_smart_registered_equipment(_request: Dictionary, result: Dictionary) -> Dictionary:
		return {"ok": true, "result": result, "row": result.get("row", {})}

	func _grupo_rs_api_register_vehicle(_request: Dictionary, _equipment_row: Dictionary) -> Dictionary:
		api_vehicle_calls += 1
		return {"ok": true, "response_code": 200}

	func _verify_modern_vehicle_registration(_serial: String, _plate: String) -> Dictionary:
		return {"ok": false, "message": "Confirmacao ainda nao publicada."}

	func _reconcile_pending_equipment_registration(_request: Dictionary, equipment_result: Dictionary, vehicle_result: Dictionary) -> Dictionary:
		return {
			"ok": false,
			"partial": true,
			"confirmation_pending": true,
			"message": "Confirmacao ainda nao publicada; nenhuma repeticao segura disponivel no teste.",
			"equipment": equipment_result,
			"vehicle": vehicle_result,
		}

	func _register_modern_equipment_via_web(_request: Dictionary) -> Dictionary:
		web_fallback_calls += 1
		return {"ok": false, "message": "Fallback nao deveria ser chamado."}

	func _show_equipment_registration_feedback(_title: String, _subtitle: String, _detail: String, _color: Color) -> void:
		pass


class QueueHost:
	extends Node
	var store = null
	var actions: Array[String] = []
	var finalize_calls := 0

	func _dismiss_equipment_registration_feedback() -> void:
		pass

	func _format_grupo_rs_vehicle_plate(value: String) -> String:
		return value.strip_edges()

	func _perform_equipment_registration(_request: Dictionary) -> Dictionary:
		return {
			"ok": true,
			"partial": true,
			"confirmation_pending": true,
			"message": "API aceita; leitura final pendente.",
		}

	func _finalize_local_equipment_registration(_local_product: Dictionary, _request: Dictionary) -> Dictionary:
		finalize_calls += 1
		return {"ok": true}

	func _log_system_action(action: String, _detail: String, _serial: String = "") -> void:
		actions.append(action)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := RegistrationStub.new()
	root.add_child(dashboard)
	await process_frame
	var request := {
		"serial": "024313111",
		"chip_number": "89555483000002065921",
		"phone": "62996187279",
		"apn": "hinova.br",
		"plate": "AAA - 031",
		"tracker_status": "Estoque",
		"equipment_only": false,
	}
	var result: Dictionary = await dashboard.call("_perform_equipment_registration", request)
	_expect(bool(result.get("ok", false)), "Aceitacao da API com confirmacao atrasada foi classificada como falha.")
	_expect(bool(result.get("confirmation_pending", false)), "O resultado nao foi marcado como confirmacao pendente.")
	var prepared_request: Dictionary = result.get("request", {}) as Dictionary
	_expect(bool(prepared_request.get("_smart_confirmation_pending", false)), "A solicitacao nao preservou o estado pendente para a persistencia local.")
	_expect(int(dashboard.api_vehicle_calls) == 1, "A etapa de veiculo nao foi executada exatamente uma vez.")
	_expect(int(dashboard.web_fallback_calls) == 0, "O fallback web repetiu um cadastro que a API ja havia aceitado.")

	var store_script := load("res://src/inventory_store.gd")
	var local_store = store_script.new()
	local_store.configure("user://codex_remote_pending_persistence.json")
	local_store.load_db()
	local_store.mark_remote_available()
	dashboard.set("store", local_store)
	var local_product := {"sku": "024313111", "imei": "024313111", "tracker_status": "Estoque", "status": "Estoque", "location": "Estoque", "stock": 1}
	local_store.upsert_product_replacing_sku("024313111", local_product)
	var finalized: Dictionary = await dashboard.call("_finalize_local_equipment_registration", local_product, prepared_request)
	_expect(bool(finalized.get("ok", false)), "A persistencia local do estado pendente falhou.")
	var saved: Dictionary = local_store.get_product("024313111")
	_expect(str(saved.get("client", "")) == "RS300", "O titular local nao foi normalizado para RS300.")
	_expect(str(saved.get("remote_registration_status", "")) == "confirmacao_pendente", "O status local nao refletiu a confirmacao pendente.")

	var host := QueueHost.new()
	root.add_child(host)
	var queue_script = load("res://src/remote_operation_queue_current.gd")
	var queue = queue_script.new()
	root.add_child(queue)
	queue.configure(host)
	var queue_id: String = queue.enqueue("Cadastro", {}, {"serial": "024313111", "plate": "AAA - 031"})
	_expect(queue_id != "", "A operacao de teste nao entrou na fila remota.")
	for _index in range(20):
		await root.get_tree().create_timer(0.05).timeout
		if not queue.active.has(queue_id):
			break
	var queued_item: Dictionary = {}
	for item in queue.items:
		if str(item.get("id", "")) == queue_id:
			queued_item = item
			break
	_expect(str(queued_item.get("state", "")) == "pending", "A fila nao exibiu a confirmacao atrasada como pendente.")
	_expect(int(host.finalize_calls) == 0, "A fila finalizou localmente um cadastro cuja placa ainda nao foi confirmada.")
	_expect(host.actions.has("Confirmacao remota pendente"), "A fila registrou a confirmacao atrasada como falha ou sucesso comum.")
	_expect(not host.actions.has("Falhou operacao remota"), "A confirmacao atrasada gerou um alerta de falha falso.")

	dashboard.queue_free()
	queue.queue_free()
	host.queue_free()
	print("REMOTE_CONFIRMATION_PENDING_CHECK_OK")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
