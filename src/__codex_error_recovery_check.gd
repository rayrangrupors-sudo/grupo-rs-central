extends SceneTree


class LogHost:
	extends Node
	var events: Array[Dictionary] = []

	func _dismiss_equipment_registration_feedback() -> void:
		pass

	func _log_system_action_event(action: String, details: String, serial: String, metadata: Dictionary) -> void:
		events.append({"action": action, "details": details, "serial": serial, "metadata": metadata.duplicate(true)})

	func _log_system_action(action: String, details: String = "", serial: String = "") -> void:
		events.append({"action": action, "details": details, "serial": serial, "metadata": {}})


class ConfirmationStub:
	extends "res://src/inventory_dashboard.gd"
	var read_count := 0

	func _fetch_modern_grupo_rs_equipment_rows(serial: String, _force_refresh: bool = false) -> Array[Dictionary]:
		read_count += 1
		var chip := "89555483000000000000" if read_count < 3 else "89555483000002065921"
		return [{"serial": serial, "chip": chip, "phone": "62996187279", "edit_href": ""}]

	func _fetch_grupo_rs_equipment_details(row: Dictionary) -> Dictionary:
		return {"chip": str(row.get("chip", "")), "phone": "62996187279", "apn": "hinova.br", "operator": "Vivo"}


class AssociationStub:
	extends "res://src/inventory_dashboard.gd"
	var update_calls := 0

	func _grupo_rs_api_find_vehicle(plate: String = "", serial: String = "", _force_read: bool = true, _allow_full_scan: bool = true) -> Dictionary:
		if serial.strip_edges() != "":
			return {"ok": true, "row": {"vehicle_id": "77", "plate": "AAA - 030", "serial": serial, "equipment_id": "900"}, "response_code": 200}
		return {"ok": false, "not_found": true, "response_code": 200, "message": "Placa livre"}

	func _grupo_rs_api_json_request(_path: String, _method: int, _payload: Dictionary, _retry_login: bool = true) -> Dictionary:
		return {"ok": false, "response_code": 409, "body": "{\"message\":\"Equipamento ja esta associado a outro veiculo\"}"}

	func _grupo_rs_api_resolve_rs300_client_id() -> Dictionary:
		return {"ok": true, "client_id": "12824"}

	func _grupo_rs_api_update_vehicle(_request: Dictionary, _existing: Dictionary, new_plate: String) -> Dictionary:
		update_calls += 1
		return {"ok": true, "api": true, "row": {"vehicle_id": "77", "plate": new_plate, "serial": "024323557"}}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var store_script := load("res://src/inventory_store.gd")
	var store = store_script.new()
	store.configure("user://__codex_error_recovery_log.json", "__codex_error_recovery_log.json", "user://__codex_error_recovery_backups", false)
	store.load_db()
	store.mark_remote_available()
	store.add_system_log("Sincronizacao Grupo RS", "intervalo | verificados: 40 | estoque/reserva: 40 | baixas: 0 | atualizados: 0 | erros: 0")
	var legacy_ok := store.get_system_logs(1)[0] as Dictionary
	_expect(str(legacy_ok.get("status", "")) == "completed", "Sincronizacao antiga com erros: 0 ainda foi classificada como falha.")
	store.add_system_log_event("Sincronizacao Grupo RS", "intervalo | erros: 2", "", {"status": "failed", "error_count": 2, "phase": "sincronizacao"})
	var failed_sync := store.get_system_logs(1)[0] as Dictionary
	_expect(str(failed_sync.get("status", "")) == "failed", "Sincronizacao com erro deixou de ser classificada como falha.")
	_expect(int(failed_sync.get("error_count", 0)) == 2, "O contador estruturado de erros nao foi preservado.")

	var log_host := LogHost.new()
	root.add_child(log_host)
	var queue_script := load("res://src/remote_operation_queue_current.gd")
	var queue = queue_script.new()
	root.add_child(queue)
	queue.configure(log_host)
	queue.call("_log_remote_operation_event", "Cadastro", "024323557", {"ok": true, "response_code": 200, "message": "Cadastro confirmado"}, "remote-test-1", Time.get_ticks_msec() - 12, false)
	var queue_event: Dictionary = log_host.events[-1]
	_expect(str((queue_event.get("metadata", {}) as Dictionary).get("status", "")) == "completed", "A fila nao registrou cadastro concluido como completed.")
	_expect(int((queue_event.get("metadata", {}) as Dictionary).get("http_code", 0)) == 200, "A fila perdeu o HTTP da operacao remota.")

	var confirmation := ConfirmationStub.new()
	root.add_child(confirmation)
	var confirmation_result: Dictionary = await confirmation.call("_verify_modern_equipment_modification", "024323557", {
		"serial": "024323557",
		"chip_number": "89555483000002065921",
		"phone": "62996187279",
		"apn": "hinova.br",
		"operator": "Vivo",
	})
	_expect(bool(confirmation_result.get("ok", false)), "A confirmacao atrasada do chip foi marcada como falha antes da propagacao.")
	_expect(int(confirmation.read_count) == 3, "A confirmacao nao repetiu a leitura controlada do portal.")
	_expect(int(confirmation_result.get("attempt", 0)) == 3, "A tentativa que confirmou o chip nao foi registrada.")

	var association := AssociationStub.new()
	root.add_child(association)
	var association_result: Dictionary = await association.call("_grupo_rs_api_register_vehicle", {
		"serial": "024323557",
		"plate": "AAA - 031",
		"vehicle_type": "Carro",
	}, {"codEquipamento": 900})
	_expect(bool(association_result.get("ok", false)), "O conflito de associacao nao foi convertido em atualizacao segura.")
	_expect(bool(association_result.get("reassigned_existing_vehicle", false)), "A recuperacao nao identificou a associacao existente pelo serial.")
	_expect(int(association.update_calls) == 1, "A associacao existente nao foi atualizada exatamente uma vez.")

	queue.queue_free()
	log_host.queue_free()
	confirmation.queue_free()
	association.queue_free()
	_cleanup()
	print("ERROR_RECOVERY_CHECK_OK")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		_cleanup()
		quit(1)


func _cleanup() -> void:
	for path in [
		"user://__codex_error_recovery_log.json",
		"user://__codex_error_recovery_log.json.tmp",
		"user://__codex_error_recovery_log.json.bak",
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
