extends SceneTree

var failed := false


func _init() -> void:
	_check_queue_contract("res://src/remote_operation_queue_current.gd")
	_check_queue_contract("res://src/remote_operation_queue.gd")
	_check_queue_contract("res://src/remote_operation_queue_v2.gd")
	_check_live_harness_guards()
	_check_fallback_mapping()
	_check_api_first_online_lookup_contract()
	_check_online_table_presentation_contract()
	_check_query_only_registration_contract()
	_check_inventory_log_sanitization_contract()
	_check_discharge_contract()
	if failed:
		quit(1)
	else:
		print("STOCK_REMOTE_SAFETY_STATIC_TEST_OK")
		quit(0)


func _check_queue_contract(path: String) -> void:
	var source := FileAccess.get_file_as_string(path)
	_expect(source.contains("_perform_equipment_registration"), "%s: Cadastro nao chama API remota." % path)
	_expect(source.contains("_finalize_local_equipment_registration"), "%s: Cadastro nao atualiza Store local." % path)
	_expect(source.contains("_ensure_local_database_modification_saved"), "%s: fila nao exige confirmacao Banco local SQL." % path)
	_expect(source.contains('"local_database_pending": true'), "%s: fila nao preserva pendencia Banco local SQL." % path)
	_expect(source.contains('"confirmation_pending": true') or source.contains("registration_confirmation_pending"), "%s: fila nao preserva confirmacao remota pendente." % path)
	_expect(source.contains('state_override: String = ""'), "%s: fila nao tem finalizacao pendente segura." % path)
	_expect(source.contains('"pending"'), "%s: fila nao marca pendencia explicitamente." % path)
	_expect(source.contains('["queued", "running", "fallback", "pending"]'), "%s: duplicidade nao considera itens pendentes." % path)
	var finalize_index := source.find("_finalize_local_equipment_registration")
	var local_database_index := source.find("_ensure_local_database_modification_saved", finalize_index)
	var finish_index := source.find("_finish(", local_database_index)
	_expect(finalize_index >= 0 and local_database_index > finalize_index and finish_index > local_database_index, "%s: ordem Store -> Banco local SQL -> finalizacao nao foi provada." % path)


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
	_expect(dashboard.contains("_ensure_local_database_modification_saved"), "Dashboard nao possui barreira Banco local SQL.")
	_expect(dashboard.contains("Nenhum fallback foi repetido"), "Fluxo nao documenta bloqueio contra repeticao de fallback ambiguo.")


func _check_api_first_online_lookup_contract() -> void:
	var dashboard := FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	var lookup_index := dashboard.find("func _request_online_lookup_from_search")
	_expect(lookup_index >= 0, "Busca online nao foi encontrada.")
	if lookup_index < 0:
		return
	var lookup_block := dashboard.substr(lookup_index, 1400)
	var fetch_index := lookup_block.find("_fetch_grupo_rs_equipment_rows")
	var url_index := lookup_block.find("_grupo_rs_lookup_url")
	var request_index := lookup_block.find("online_lookup_request.request")
	_expect(fetch_index >= 0, "Tabela Grupo RS online nao usa caminho API-first.")
	_expect(url_index < 0 or fetch_index < url_index, "Tabela Grupo RS online monta URL web antes da API.")
	_expect(request_index < 0 or fetch_index < request_index, "Tabela Grupo RS online dispara HTTP web antes da API.")
	_expect(dashboard.contains("_fetch_grupo_rs_equipment_rows(serial)") and dashboard.contains("_modern_grupo_rs_read_get"), "Fallback web de leitura nao esta isolado dentro do caminho API-first.")


func _check_online_table_presentation_contract() -> void:
	var dashboard := FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	_expect(dashboard.contains("func _grupo_rs_registration_status_label"), "Tabela online nao normaliza status cadastral.")
	_expect(dashboard.contains("func _grupo_rs_online_field_label"), "Tabela online nao diferencia campo ausente de erro.")
	for label in ["Ativo", "Inativo", "Reserva", "Não informado", "Não consultado"]:
		_expect(dashboard.contains(label), "Tabela online nao contem rotulo esperado: %s." % label)
	_expect(dashboard.contains("_grupo_rs_registration_status_label(str(product.get(\"status\", \"\")))"), "Coluna Cadastro ainda usa status bruto.")
	_expect(dashboard.contains("_grupo_rs_online_field_label(str(product.get(\"chip\", \"\")))"), "Coluna Chip nao usa rotulo de ausencia.")
	_expect(dashboard.contains("_grupo_rs_online_field_label(str(product.get(\"phone\", \"\")))"), "Coluna Telefone nao usa rotulo de ausencia.")
	_expect(dashboard.contains("_make_table_label(\"Status atual\", 150") and dashboard.contains("Vector2(150, 0)") and dashboard.contains("Vector2(142, 36)"), "Coluna Status atual nao foi alargada para Nao consultado.")


func _check_query_only_registration_contract() -> void:
	var dashboard := FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	var registration_index := dashboard.find("func _perform_equipment_registration")
	var modification_index := dashboard.find("func _perform_equipment_modification")
	_expect(registration_index >= 0 and modification_index >= 0, "Fluxos Cadastro/Modificar nao foram localizados.")
	if registration_index >= 0:
		var registration_end := dashboard.find("func _register_or_find_modern_equipment", registration_index)
		var registration_block := dashboard.substr(registration_index, registration_end - registration_index)
		_expect(registration_block.contains("_grupo_rs_api_find_equipment"), "Cadastro nao consulta API Grupo RS.")
		_expect(registration_block.contains('"query_only": true'), "Cadastro nao declara contrato API somente consulta.")
		_expect(not registration_block.contains("_grupo_rs_api_register_equipment"), "Cadastro ainda chama criacao de negocio na API.")
		_expect(not registration_block.contains("_grupo_rs_api_register_vehicle"), "Cadastro ainda chama vinculacao de negocio na API.")
		_expect(not registration_block.contains("_register_modern_equipment_via_web"), "Cadastro ainda usa portal web para gravar negocio.")
	if modification_index >= 0:
		var modification_end := dashboard.find("func _perform_api_vehicle_modification", modification_index)
		var modification_block := dashboard.substr(modification_index, modification_end - modification_index)
		_expect(modification_block.contains("_grupo_rs_api_find_equipment"), "Modificar nao consulta API Grupo RS.")
		_expect(modification_block.contains('"query_only": true'), "Modificar nao declara contrato API somente consulta.")
		_expect(not modification_block.contains("_grupo_rs_api_patch_equipment"), "Modificar ainda chama alteracao de negocio na API.")
		_expect(not modification_block.contains("_perform_api_vehicle_modification"), "Modificar ainda chama alteracao de veiculo na API.")
		_expect(not modification_block.contains("_modify_modern_equipment_via_web"), "Modificar ainda usa portal web para gravar negocio.")


func _check_inventory_log_sanitization_contract() -> void:
	var dashboard := FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	_expect(dashboard.contains("_sanitize_inventory_log_details"), "Logs internos do Estoque nao possuem sanitizador de detalhes.")
	_expect(dashboard.contains("_sanitize_inventory_log_metadata"), "Logs internos do Estoque nao possuem sanitizador de metadados.")
	_expect(dashboard.contains("store.add_system_log(action, _sanitize_inventory_log_details(details), sku)"), "Log simples nao sanitiza detalhes antes do Store.")
	_expect(dashboard.contains("add_system_log_event") and dashboard.contains("_sanitize_inventory_log_metadata(metadata)"), "Log estruturado nao sanitiza metadados antes do Store.")
	_expect(dashboard.contains('"sku"') and dashboard.contains('"technical_key"') and dashboard.contains('"payload"'), "Sanitizador de metadados nao cobre sku/chave tecnica/payload.")
	_expect(dashboard.contains("SKU") and dashboard.contains("Payload") and dashboard.contains("Detalhes"), "Sanitizador de detalhes nao cobre SKU/payload/detalhes.")


func _check_discharge_contract() -> void:
	var dashboard := FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	var install_index := dashboard.find("func _install_equipment_confirmed")
	var stock_index := dashboard.find("func _send_to_stock_confirmed")
	_expect(install_index >= 0, "Dar baixa nao possui helper confirmado.")
	_expect(stock_index >= 0, "Voltar ao estoque nao possui helper confirmado.")
	if install_index >= 0:
		var install_block := dashboard.substr(install_index, 1400)
		var local_database_index := install_block.find("_ensure_local_database_modification_saved")
		var refresh_index := install_block.find("_refresh_table", local_database_index)
		var success_index := install_block.find("_show_success", local_database_index)
		_expect(install_block.contains("store.install_tracker"), "Dar baixa nao grava Store antes do Banco local SQL.")
		_expect(local_database_index >= 0, "Dar baixa nao confirma Banco local SQL.")
		_expect(install_block.contains('"local_database_pending": true'), "Dar baixa nao preserva pendencia Banco local SQL.")
		_expect(refresh_index > local_database_index and success_index > local_database_index, "Dar baixa atualiza tabela/sucesso antes do Banco local SQL.")
	if stock_index >= 0:
		var stock_block := dashboard.substr(stock_index, 1300)
		var local_database_index := stock_block.find("_ensure_local_database_modification_saved")
		var refresh_index := stock_block.find("_refresh_table", local_database_index)
		var success_index := stock_block.find("_show_success", local_database_index)
		_expect(stock_block.contains("store.set_tracker_status"), "Voltar ao estoque nao grava Store antes do Banco local SQL.")
		_expect(local_database_index >= 0, "Voltar ao estoque nao confirma Banco local SQL.")
		_expect(stock_block.contains('"local_database_pending": true'), "Voltar ao estoque nao preserva pendencia Banco local SQL.")
		_expect(refresh_index > local_database_index and success_index > local_database_index, "Voltar ao estoque atualiza tabela/sucesso antes do Banco local SQL.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failed = true
