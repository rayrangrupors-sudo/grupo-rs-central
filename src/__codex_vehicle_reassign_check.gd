extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := ResourceLoader.load("res://src/inventory_dashboard.gd", "GDScript", ResourceLoader.CACHE_MODE_REPLACE)
	var stub_script := load("res://src/__codex_vehicle_reassign_stub.gd")
	var post_stub_script := load("res://src/__codex_vehicle_post_stub.gd")
	if dashboard_script == null or stub_script == null or post_stub_script == null:
		_fail(null, "Scripts da alteracao de placa nao carregaram.")
		return
	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame

	if str(dashboard.call("_format_grupo_rs_vehicle_plate", "aaa0a00")) != "AAA - 0A00":
		_fail(dashboard, "A nova placa nao foi formatada corretamente.")
		return
	if not bool(dashboard.call("_is_valid_grupo_rs_vehicle_reassignment_plate", "AAA - 0A00")):
		_fail(dashboard, "Uma placa valida foi recusada.")
		return
	if str(dashboard.call("_format_grupo_rs_vehicle_plate", "aaa-c31")) != "AAA - C31" \
			or not bool(dashboard.call("_is_valid_grupo_rs_vehicle_reassignment_plate", "AAA - C31")):
		_fail(dashboard, "A placa interna curta AAA - C31 foi recusada.")
		return
	if bool(dashboard.call("_is_valid_grupo_rs_vehicle_reassignment_plate", "AAA-00")):
		_fail(dashboard, "Uma placa curta foi aceita.")
		return

	dashboard.set("selected_branch_grupo_rs_base_url", "https://sis.sosrastrear.com.br/Cadastros/EquipamentosListar")
	if str(dashboard.call("_legacy_grupo_rs_root_url")) != "https://sis.sosrastrear.com.br":
		_fail(dashboard, "A URL da pagina de equipamentos nao foi reduzida para a raiz correta.")
		return
	if str(dashboard.call("_legacy_grupo_rs_url", "/Login/Login")) != "https://sis.sosrastrear.com.br/Login/Login":
		_fail(dashboard, "O login da base antiga foi montado em um caminho invalido.")
		return
	if str(dashboard.call("_legacy_grupo_rs_url", "/Cadastros/EquipamentosListar")) != "https://sis.sosrastrear.com.br/Cadastros/EquipamentosListar":
		_fail(dashboard, "A consulta de equipamentos nao preservou a rota nova.")
		return
	dashboard.set("selected_branch_grupo_rs_base_url", "https://sis.sosrastrear.com.br/Base/FrmPrincipal")
	if str(dashboard.call("_legacy_grupo_rs_root_url")) != "https://sis.sosrastrear.com.br":
		_fail(dashboard, "A URL antiga anterior deixou de ser aceita.")
		return

	var edit_html := _vehicle_form_html("PSO - 8628", "JOAO DA SILVA SOARES", "Moto", false)
	var built: Dictionary = dashboard.call("_build_modern_vehicle_reassignment_fields", edit_html, "AAA - 0A00")
	if not bool(built.get("ok", false)):
		_fail(dashboard, "Os campos de alteracao nao foram montados.")
		return
	var fields: Dictionary = built.get("fields", {})
	if str(fields.get("Placa", "")) != "AAA - 0A00" or str(fields.get("CodCliente", "")) != "12824" or str(fields.get("CodTipoVeiculo", "")) != "1":
		_fail(dashboard, "Placa, titular RS300 ou tipo Carro nao foram preparados.")
		return
	for field_name in ["Modelo", "Marca", "Ano", "Cor", "Chassi", "DataCompra", "Observacao"]:
		if str(fields.get(field_name, "")) != "":
			_fail(dashboard, "O campo %s nao foi limpo." % field_name)
			return
	if str(fields.get("CodVeiculo", "")) != "77" or str(fields.get("acao", "")) != "editar":
		_fail(dashboard, "A identidade segura do veiculo nao foi preservada.")
		return

	# A troca de aparelho deve transferir o titular real da placa cliente,
	# inclusive quando ele nao e o cliente padrao RS300.
	var source_swap_html := _vehicle_form_html("PSO - 8628", "JOAO DA SILVA SOARES", "Moto", false)
	var target_swap_html := _vehicle_form_html("AAA - 0A00", "RS300", "Carro", false)
	var source_swap_fields: Dictionary = dashboard.call("_legacy_form_fields", source_swap_html)
	var replacement_payload: Dictionary = dashboard.call(
		"_replacement_vehicle_payload",
		{"form_html": target_swap_html, "fields": dashboard.call("_legacy_form_fields", target_swap_html)},
		"PSO - 8628",
		"JOAO DA SILVA SOARES",
		source_swap_fields
	)
	if not bool(replacement_payload.get("ok", false)):
		_fail(dashboard, "O payload da troca nao foi montado para o titular real da placa cliente.")
		return
	var replacement_fields: Dictionary = replacement_payload.get("fields", {})
	if str(replacement_fields.get("CodCliente", "")) != "9" or str(replacement_fields.get("Placa", "")) != "PSO - 8628":
		_fail(dashboard, "A troca nao transferiu o titular real e a placa cliente para o destino.")
		return
	if str(replacement_fields.get("Modelo", "")) != "DADO ANTIGO" or str(replacement_fields.get("CodTipoVeiculo", "")) != "2":
		_fail(dashboard, "Os dados cadastrais da placa cliente nao foram copiados para o destino.")
		return

	var verified_html := _vehicle_form_html("AAA - 0A00", "RS300", "Carro", true)
	var snapshot: Dictionary = dashboard.call("_modern_vehicle_edit_snapshot", verified_html)
	if str(snapshot.get("client", "")) != "RS300" or str(snapshot.get("vehicle_type", "")) != "Carro":
		_fail(dashboard, "A verificacao final nao reconheceu RS300 e Carro.")
		return
	if str(snapshot.get("model", "")) != "":
		_fail(dashboard, "A verificacao final nao reconheceu os campos limpos.")
		return
	if not bool(dashboard.call("_modern_vehicle_snapshot_matches_reassignment", snapshot, "AAA - 0A00")):
		_fail(dashboard, "O estado final correto nao foi reconhecido.")
		return
	var server_dated_snapshot := snapshot.duplicate(true)
	server_dated_snapshot["purchase_date"] = "22/07/2026 11:41:22"
	if not bool(dashboard.call("_modern_vehicle_snapshot_matches_reassignment", server_dated_snapshot, "AAA - 0A00")):
		_fail(dashboard, "A data automatica do servidor bloqueou um estado final correto.")
		return

	var post_stub: Node = post_stub_script.new()
	root.add_child(post_stub)
	await process_frame
	var recovered: Dictionary = await post_stub.call("_update_modern_grupo_rs_vehicle_reassignment", {
		"new_plate": "AAA - 0A00",
		"remote_serial": "024288081",
		"edit_href": "veiculos_editar.php?id=77",
		"edit_html": edit_html,
	})
	if not bool(recovered.get("ok", false)) or int(post_stub.get("post_calls")) != 1 or int(post_stub.get("verify_calls")) != 1:
		post_stub.queue_free()
		_fail(dashboard, "O POST encerrado pelo servidor nao foi recuperado pela verificacao final.")
		return
	post_stub.queue_free()

	var legacy_equipment_html := "<form><button onclick=\"__doPostBack('ctl07','')\"><img src='/img/chip.png'><b>Equipamentos</b></button><button id='btnDeletar'>Deletar Equipamento</button></form>"
	var clear_events_fields: Dictionary = dashboard.call("_legacy_clear_equipment_events_fields", legacy_equipment_html)
	if str(clear_events_fields.get("__EVENTTARGET", "")) != "ctl07":
		_fail(dashboard, "O botao correto de limpar eventos nao foi identificado.")
		return
	if str(clear_events_fields.get("__EVENTTARGET", "")) == "btnDeletar":
		_fail(dashboard, "A limpeza de eventos selecionou indevidamente Deletar Equipamento.")
		return

	var rows: Array[Dictionary] = [
		{"serial": "024288081", "plate": "PSO - 8628", "edit_id": "77"},
		{"serial": "024999999", "plate": "OUT - 0001", "edit_id": "78"},
	]
	var exact: Dictionary = dashboard.call("_choose_modern_grupo_rs_vehicle_row_exact", rows, "024288081", "PSO8628")
	if str(exact.get("edit_id", "")) != "77":
		_fail(dashboard, "A selecao exata nao encontrou o veiculo correto.")
		return
	if not (dashboard.call("_choose_modern_grupo_rs_vehicle_row_exact", rows, "024288081", "OUT - 0001") as Dictionary).is_empty():
		_fail(dashboard, "Serie e placa de veiculos diferentes foram combinadas.")
		return

	var request := {
		"remote_serial": "024288081",
		"old_plate": "PSO - 8628",
		"new_plate": "AAA - 0A00",
	}
	var form_view: Control = dashboard.call("_build_form_view", "")
	var reassign_button := _find_button(form_view, "Modificar")
	if reassign_button == null or not reassign_button.disabled:
		form_view.free()
		_fail(dashboard, "O botao remoto deveria iniciar bloqueado ate a consulta do Grupo RS.")
		return
	form_view.free()
	dashboard.call("_show_vehicle_reassignment_password_dialog", request)
	var password_input := _find_line_edit(dashboard, "Senha para modificar no RS")
	if password_input == null or not password_input.secret:
		_fail(dashboard, "O dialogo nao protegeu a operacao com senha.")
		return
	password_input.text = "0000"
	password_input.text_submitted.emit(password_input.text)
	await process_frame
	if not _has_label_fragment(dashboard, "continua bloqueada"):
		_fail(dashboard, "Uma senha incorreta nao bloqueou a modificacao remota.")
		return
	var password_layer := password_input.get_parent()
	while password_layer != null and not password_layer is CanvasLayer:
		password_layer = password_layer.get_parent()
	if password_layer != null:
		password_layer.queue_free()
	await process_frame

	var stub: Node = stub_script.new()
	root.add_child(stub)
	await process_frame
	var success: Dictionary = await stub.call("_perform_vehicle_reassignment", request, null)
	var expected_order: Array[String] = ["prepare_modern", "update_modern", "finalize_local"]
	if not bool(success.get("ok", false)) or stub.get("test_events") != expected_order:
		_fail_pair(dashboard, stub, "A alteracao web/API nao seguiu a ordem esperada sem exclusao de registros.")
		return

	var failed_stub: Node = stub_script.new()
	failed_stub.set("test_fail_stage", "update_modern")
	root.add_child(failed_stub)
	await process_frame
	var failed: Dictionary = await failed_stub.call("_perform_vehicle_reassignment", request, null)
	var failed_events: Array[String] = failed_stub.get("test_events")
	if bool(failed.get("ok", false)) or failed_events.has("finalize_local") or failed_events.has("clear_legacy_events") or failed_events.has("rollback_modern"):
		failed_stub.queue_free()
		_fail_pair(dashboard, stub, "Uma falha web/API alterou o cadastro local indevidamente. Resultado: %s | Eventos: %s" % [str(failed), str(failed_events)])
		return

	dashboard.queue_free()
	stub.queue_free()
	failed_stub.queue_free()
	await process_frame
	print("VEHICLE_REASSIGN_CHECK_OK")
	quit(0)


func _vehicle_form_html(plate: String, selected_client: String, selected_type: String, cleared: bool) -> String:
	var text_value := "" if cleared else "DADO ANTIGO"
	var rs300_selected := " selected" if selected_client == "RS300" else ""
	var old_client_selected := " selected" if selected_client != "RS300" else ""
	var car_selected := " selected" if selected_type == "Carro" else ""
	var moto_selected := " selected" if selected_type != "Carro" else ""
	return """<form action='veiculos_actions.php' method='post'>
	<input type='hidden' name='acao' value='editar'>
	<input type='hidden' name='CodVeiculo' value='77'>
	<input type='hidden' name='status' value='A'>
	<input name='Placa' value='%s'>
	<input name='Modelo' value='%s'>
	<input name='Marca' value='%s'>
	<input name='Ano' value='%s'>
	<input name='Cor' value='%s'>
	<input name='Chassi' value='%s'>
	<input name='DataCompra' value='%s'>
	<select name='TipoIdentificacao'><option value='placa' selected>Placa</option></select>
	<select name='CodCliente'><option value='9'%s>JOAO DA SILVA SOARES</option><option value='12824'%s>RS300</option></select>
	<select name='CodTipoVeiculo'><option value='2'%s>Moto</option><option value='1'%s>Carro</option></select>
	<select name='TrocarEquip'><option value='' selected>Selecione</option></select>
	<textarea name='Observacao'>%s</textarea>
	</form>""" % [plate, text_value, text_value, text_value, text_value, text_value, text_value, old_client_selected, rs300_selected, moto_selected, car_selected, text_value]


func _find_button(node: Node, button_text: String) -> Button:
	if node is Button and str((node as Button).text) == button_text:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, button_text)
		if found != null:
			return found
	return null


func _find_line_edit(node: Node, placeholder: String) -> LineEdit:
	if node is LineEdit and str((node as LineEdit).placeholder_text) == placeholder:
		return node as LineEdit
	for child in node.get_children():
		var found := _find_line_edit(child, placeholder)
		if found != null:
			return found
	return null


func _has_label_fragment(node: Node, fragment: String) -> bool:
	if node is Label and str((node as Label).text).contains(fragment):
		return true
	for child in node.get_children():
		if _has_label_fragment(child, fragment):
			return true
	return false


func _fail_pair(dashboard: Node, stub: Node, message: String) -> void:
	if stub != null and is_instance_valid(stub):
		stub.queue_free()
	_fail(dashboard, message)


func _fail(dashboard: Node, message: String) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)

