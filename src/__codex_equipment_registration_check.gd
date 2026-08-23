extends SceneTree


class RegistrationDashboard:
	extends "res://src/inventory_dashboard.gd"

	func _ready() -> void:
		pass


var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _has_text_fragment(node: Node, fragment: String) -> bool:
	if node is Label and str((node as Label).text).contains(fragment):
		return true
	if node is Button and str((node as Button).text).contains(fragment):
		return true
	if node is LineEdit and str((node as LineEdit).placeholder_text).contains(fragment):
		return true
	for child in node.get_children():
		if _has_text_fragment(child, fragment):
			return true
	return false


func _run() -> void:
	var dashboard := RegistrationDashboard.new()
	root.add_child(dashboard)
	await process_frame

	var form_html := """
	<form action='veiculos_actions.php' method='post'>
	<input type='hidden' name='acao' value='cadastrar'>
	<select name='CodCliente'><option value='12824'>RS300</option></select>
	<select name='CodTipoVeiculo'><option value='1'>Carro</option></select>
	<select name='TrocarEquip'>
	<option value=''>Selecione</option>
	<option value='024373149'>024373149</option>
	<option value='024373150'>024373150</option>
	</select>
	<input name='Placa' value=''>
	</form>
	"""
	var request := {
		"serial": "024373149",
		"plate": "GRS - T91",
		"local_sku": "024373149",
	}
	var built: Dictionary = dashboard.call("_build_modern_vehicle_registration_fields", form_html, request)
	_expect(bool(built.get("ok", false)), "Formulario remoto nao foi montado.")
	var fields: Dictionary = built.get("fields", {}) as Dictionary
	_expect(str(fields.get("Placa", "")) == "GRS - T91", "Placa nao foi preenchida no cadastro remoto.")
	_expect(str(fields.get("CodCliente", "")) == "12824", "Cliente RS300 nao foi selecionado.")
	_expect(str(fields.get("CodTipoVeiculo", "")) == "1", "Tipo Carro nao foi selecionado.")
	_expect(str(fields.get("TrocarEquip", "")) == "024373149", "Equipamento correto nao foi vinculado.")

	var equipment_form_html := """
	<form action='equipamentos_action.php' method='post'>
	<input type='hidden' name='CodEquipamento' value='0'>
	<input name='NumeroEquipamento' value=''>
	<input name='NumeroSerie' value=''>
	<input name='Apn' value=''>
	<input name='NumeroChip' value=''>
	<input name='NumeroTelefone' value=''>
	<select name='CodModelo'><option value='2122'>RS 300</option></select>
	<select name='CodOperadora'><option value='4'>TIM</option></select>
	</form>
	"""
	var equipment_request := {
		"serial": "024307295",
		"apn": "hinova.br",
		"chip_number": "89555483000027345290",
		"phone": "33991199479",
		"operator": "Tim",
	}
	var built_equipment: Dictionary = dashboard.call("_build_modern_equipment_registration_fields", equipment_form_html, equipment_request)
	_expect(bool(built_equipment.get("ok", false)), "Formulario remoto de equipamento nao foi montado.")
	var equipment_fields: Dictionary = built_equipment.get("fields", {}) as Dictionary
	_expect(str(equipment_fields.get("NumeroEquipamento", "")) == "024307295", "Numero do equipamento nao foi preenchido.")
	_expect(str(equipment_fields.get("NumeroSerie", "")) == "024307295", "Numero de serie remoto nao foi preenchido.")
	_expect(str(equipment_fields.get("Apn", "")) == "hinova.br", "APN remota nao foi preenchida.")
	_expect(str(equipment_fields.get("NumeroChip", "")) == "89555483000027345290", "ICCID remoto nao foi preenchido.")
	_expect(str(equipment_fields.get("NumeroTelefone", "")) == "33991199479", "Telefone remoto nao foi preenchido.")
	_expect(str(equipment_fields.get("CodModelo", "")) == "2122", "Modelo RS 300 nao foi selecionado.")
	_expect(str(equipment_fields.get("CodOperadora", "")) == "4", "Operadora TIM nao foi selecionada.")
	_expect(str(equipment_fields.get("salvar", "")) == "1", "Botao salvar nao foi enviado ao portal.")
	_expect(bool(dashboard.call("_is_modern_equipment_unlinked_plate", "SEM EQUIPAMENTO")), "Equipamento livre nao foi reconhecido.")
	_expect(not bool(dashboard.call("_is_modern_equipment_unlinked_plate", "AAA - T289")), "Equipamento vinculado foi tratado como livre.")

	var snapshot := {"plate": "GRS - T91", "client": "RS300", "vehicle_type": "Carro"}
	_expect(bool(dashboard.call("_modern_vehicle_snapshot_matches_registration", snapshot, "GRS - T91")), "Confirmacao final do veiculo foi rejeitada.")
	var wrong_snapshot := {"plate": "GRS - T91", "client": "OUTRO", "vehicle_type": "Carro"}
	_expect(not bool(dashboard.call("_modern_vehicle_snapshot_matches_registration", wrong_snapshot, "GRS - T91")), "Cliente incorreto passou na confirmacao final.")
	_expect(str(dashboard.call("_registration_final_status", "Manutencao", false)) == "Manutencao", "Status Manutencao foi convertido indevidamente para Instalado.")
	_expect(str(dashboard.call("_registration_final_status", "Estoque", false)) == "Estoque", "Status Estoque foi convertido indevidamente para Instalado.")

	var form: Control = dashboard.call("_build_form_view", "")
	root.add_child(form)
	await process_frame
	_expect(_has_text_fragment(form, "APN / Origem"), "Campo de origem/APN nao apareceu.")
	_expect(_has_text_fragment(form, "Buscar chip"), "Busca de chip nao apareceu.")
	_expect(_has_text_fragment(form, "Numero chip / ICCID"), "Campo de ICCID nao apareceu.")
	_expect(_has_text_fragment(form, "Telefone chip"), "Campo de telefone nao apareceu.")

	_expect(
		str(dashboard.call("_normalize_modern_grupo_rs_base_url", "https://novo.exemplo/cadastro/veiculos_listar.php")) == "https://novo.exemplo/cadastro/",
		"URL do sistema novo nao foi normalizada para a base do portal."
	)
	_expect(
		str(dashboard.call("_normalize_modern_grupo_rs_base_url", "https://novo.exemplo/home_adm.php/")) == "https://novo.exemplo/cadastro/",
		"URL da tela inicial do sistema novo nao foi normalizada para a base do portal."
	)
	_expect(
		str(dashboard.call("_normalize_grupo_rs_api_base_url", "https://novo.exemplo/api_rest_app/docs/index.html")) == "https://novo.exemplo/api_rest_app",
		"URL da documentacao nao foi normalizada para a raiz da API."
	)
	_expect(
		str(dashboard.call("_normalize_grupo_rs_api_base_url", "https://novo.exemplo/api_rest_app/docs/")) == "https://novo.exemplo/api_rest_app",
		"URL /docs da API nao foi normalizada."
	)
	var config_stack := VBoxContainer.new()
	dashboard.call("_build_config_grupo_rs_section", config_stack, {})
	await process_frame
	_expect(_has_text_fragment(config_stack, "URL do sistema novo"), "Campo de URL do sistema novo nao apareceu nas configuracoes.")
	_expect(_has_text_fragment(config_stack, "URL da API oficial"), "Campo separado da URL da API oficial nao apareceu nas configuracoes.")
	_expect(not _has_text_fragment(config_stack, "Grupo RS antigo"), "Bloco do sistema antigo ainda aparece nas configuracoes.")
	_expect(not _has_text_fragment(config_stack, "URL de exclusao no sistema antigo"), "URL do sistema antigo ainda aparece nas configuracoes.")
	dashboard.queue_free()
	form.queue_free()
	config_stack.queue_free()
	await process_frame

	if failures.is_empty():
		print("EQUIPMENT_REGISTRATION_CHECK_OK")
		quit(0)
	else:
		print("EQUIPMENT_REGISTRATION_CHECK_FAILED: %d" % failures.size())
		quit(1)
