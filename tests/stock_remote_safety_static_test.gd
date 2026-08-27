extends SceneTree

var failed := false


func _init() -> void:
	_check_queue_contract("res://src/remote_operation_queue_current.gd")
	_check_queue_contract("res://src/remote_operation_queue.gd")
	_check_queue_contract("res://src/remote_operation_queue_v2.gd")
	_check_live_harness_guards()
	_check_fallback_mapping()
	if failed:
		quit(1)
	else:
		print("STOCK_REMOTE_SAFETY_STATIC_TEST_OK")
		quit(0)


func _check_queue_contract(path: String) -> void:
	var source := FileAccess.get_file_as_string(path)
	_expect(source.contains("_perform_equipment_registration"), "%s: Cadastro nao chama API remota." % path)
	_expect(source.contains("_finalize_local_equipment_registration"), "%s: Cadastro nao atualiza Store local." % path)
	_expect(source.contains("_ensure_firebase_modification_saved"), "%s: fila nao exige confirmacao Firebase." % path)
	_expect(source.contains('"firebase_pending": true'), "%s: fila nao preserva pendencia Firebase." % path)
	_expect(source.contains('"confirmation_pending": true') or source.contains("registration_confirmation_pending"), "%s: fila nao preserva confirmacao remota pendente." % path)
	_expect(source.contains('state_override: String = ""'), "%s: fila nao tem finalizacao pendente segura." % path)
	_expect(source.contains('"pending"'), "%s: fila nao marca pendencia explicitamente." % path)
	_expect(source.contains('["queued", "running", "fallback", "pending"]'), "%s: duplicidade nao considera itens pendentes." % path)
	var finalize_index := source.find("_finalize_local_equipment_registration")
	var firebase_index := source.find("_ensure_firebase_modification_saved", finalize_index)
	var finish_index := source.find("_finish(", firebase_index)
	_expect(finalize_index >= 0 and firebase_index > finalize_index and finish_index > firebase_index, "%s: ordem Store -> Firebase -> finalizacao nao foi provada." % path)


func _check_live_harness_guards() -> void:
	for path in [
		"res://tests/live_remote_registration_save_harness.gd",
		"res://tests/live_synthetic_registration_save_harness.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		_expect(source.contains("GRS_ALLOW_LIVE_WRITE_HARNESS"), "%s: harness live de escrita sem trava explicita." % path)
		_expect(source.contains("live_write_harness_disabled"), "%s: harness live de escrita nao falha fechado." % path)
		_expect(not source.contains("2103"), "%s: harness live contem senha literal." % path)
		_expect(not source.contains("Bearer "), "%s: harness live contem token literal." % path)
		_expect(not source.contains("Authorization:"), "%s: harness live contem header sensivel literal." % path)


func _check_fallback_mapping() -> void:
	var dashboard := FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	_expect(dashboard.contains("_register_modern_equipment_via_web"), "Fallback web de Cadastro nao esta mapeado.")
	_expect(dashboard.contains("_modify_modern_equipment_via_web"), "Fallback web de Modificar nao esta mapeado.")
	_expect(dashboard.contains("_verify_modern_vehicle_registration"), "Fallback web de placa nao exige leitura de confirmacao.")
	_expect(dashboard.contains("_verify_modern_equipment_modification"), "Fallback web de equipamento nao exige leitura de confirmacao.")
	_expect(dashboard.contains("_ensure_firebase_modification_saved"), "Dashboard nao possui barreira Firebase.")
	_expect(dashboard.contains("Nenhum fallback foi repetido"), "Fluxo nao documenta bloqueio contra repeticao de fallback ambiguo.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failed = true
