extends SceneTree


class ModifyStub:
	extends "res://src/inventory_dashboard.gd"
	var patch_calls := 0
	var api_vehicle_calls := 0
	var post_calls := 0
	var web_post_calls := 0
	var last_json_payload: Dictionary = {}

	func _grupo_rs_api_find_equipment(serial: String, _force_read: bool = true) -> Dictionary:
		return {"ok": true, "row": {"id": 9021, "numeroSerie": serial, "numeroChip": "89555483000000000000", "numeroTelefone": "11999999999", "apn": "hinova.br"}}

	func _grupo_rs_api_patch_equipment(_request: Dictionary, _existing: Dictionary) -> Dictionary:
		patch_calls += 1
		return {"ok": true, "row": {"id": 9021}}

	func _perform_api_vehicle_modification(_request: Dictionary) -> Dictionary:
		api_vehicle_calls += 1
		return {"handled": true, "ok": true, "skipped": true}

	func _grupo_rs_api_find_vehicle(_plate: String = "", _serial: String = "", _force_read: bool = true, _allow_full_scan: bool = true) -> Dictionary:
		return {"ok": false, "not_found": true, "response_code": 200, "message": "A placa ainda nao existe no teste."}

	func _grupo_rs_api_resolve_rs300_client_id() -> Dictionary:
		return {"ok": true, "client_id": "12824", "source": "test"}

	func _grupo_rs_api_json_request(_path: String, _method: int, payload: Dictionary, _retry_login: bool = true) -> Dictionary:
		post_calls += 1
		last_json_payload = payload.duplicate(true)
		return {"ok": true, "response_code": 200, "body": "{\"ok\":true}"}

	func _grupo_rs_api_wait_for_equipment(_serial: String) -> Dictionary:
		return {"ok": false, "not_found": true, "message": "A API ainda nao publicou a alteracao."}

	func run_base_patch(request: Dictionary, existing: Dictionary) -> Dictionary:
		return await super._grupo_rs_api_patch_equipment(request, existing)

	func _modern_grupo_rs_get(_path: String, _retry_login: bool = true) -> Dictionary:
		return {"ok": true, "body": """
		<form action='veiculos_actions.php' method='post'>
		<input type='hidden' name='acao' value='cadastrar'>
		<select name='CodCliente'><option value='12824'>RS300</option></select>
		<select name='CodTipoVeiculo'><option value='1'>Carro</option></select>
		<select name='TrocarEquip'><option value=''>Selecione</option><option value='024399999'>024399999</option></select>
		<input name='Placa' value=''>
		</form>
		"""}

	func _modern_grupo_rs_post_form(_action: String, _fields: Dictionary, _referer: String = "", _follow_redirect: bool = true, _redirects: int = 0) -> Dictionary:
		web_post_calls += 1
		return {"ok": true, "body": "ok"}

	func _verify_modern_vehicle_registration(_serial: String, _plate: String) -> Dictionary:
		return {"ok": true, "row": {"serial": _serial, "plate": _plate}}

	func run_base_vehicle_modification(request: Dictionary) -> Dictionary:
		return await super._perform_modern_vehicle_modification(request)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := ModifyStub.new()
	root.add_child(dashboard)
	await process_frame

	var edit_form := """
	<form action='equipamentos_action.php' method='post'>
	<input type='hidden' name='CodEquipamento' value=''>
	<input name='NumeroEquipamento' value='024399999'>
	<input name='NumeroSerie' value='024399999'>
	<input name='Apn' value='hinova.br'>
	<input name='NumeroChip' value='89555483000000000000'>
	<input name='NumeroTelefone' value='11999999999'>
	<select name='CodModelo'><option value='2122' selected>RS 300</option></select>
	<select name='CodOperadora'><option value='4' selected>TIM</option></select>
	</form>
	"""
	var fields_result: Dictionary = dashboard.call("_build_modern_equipment_modification_fields", edit_form, {
		"serial": "024399999",
		"chip_number": "",
		"phone": "",
		"apn": "",
	}, {"edit_id": "9021", "chip": "89555483000000000000", "phone": "11999999999", "apn": "hinova.br"})
	_expect(bool(fields_result.get("ok", false)), "A edicao web nao preservou campos omitidos.")
	var fields: Dictionary = fields_result.get("fields", {}) as Dictionary
	_expect(str(fields.get("CodEquipamento", "")) == "9021", "A edicao web nao recuperou o ID quando o hidden veio vazio.")
	_expect(str(fields.get("NumeroChip", "")) == "89555483000000000000", "O ICCID preservado nao foi enviado.")
	_expect(str(fields.get("NumeroTelefone", "")) == "11999999999", "O telefone preservado nao foi enviado.")
	_expect(str(fields.get("Apn", "")) == "hinova.br", "A APN preservada nao foi enviada.")

	var plate_only := {
		"serial": "024399999",
		"remote_serial": "024399999",
		"old_plate": "AAA - 0001",
		"new_plate": "AAA - 0002",
		"equipment_fields_changed": false,
	}
	var plate_result: Dictionary = await dashboard.call("_perform_equipment_modification", plate_only, null)
	_expect(bool(plate_result.get("ok", false)), "A modificacao somente de placa falhou.")
	_expect(int(dashboard.patch_calls) == 0, "A modificacao somente de placa fez PATCH desnecessario no equipamento.")
	_expect(int(dashboard.api_vehicle_calls) == 1, "A modificacao de placa nao chamou a etapa de veiculo.")

	var equipment_change := plate_only.duplicate(true)
	equipment_change["new_plate"] = "AAA - 0001"
	equipment_change["equipment_fields_changed"] = true
	equipment_change["chip_number"] = "89555483000012345678"
	equipment_change["phone"] = "11988887777"
	equipment_change["apn"] = "hinova.br"
	var equipment_result: Dictionary = await dashboard.call("_perform_equipment_modification", equipment_change, null)
	_expect(bool(equipment_result.get("ok", false)), "A modificacao de chip/telefone/APN falhou no stub.")
	_expect(int(dashboard.patch_calls) == 1, "A modificacao de campos do equipamento nao fez exatamente um PATCH.")

	var new_association: Dictionary = await dashboard.call("run_base_vehicle_modification", {
		"remote_serial": "024399999",
		"old_plate": "",
		"new_plate": "AAA - 0003",
	})
	_expect(not bool(new_association.get("ok", false)), "Modificar aceitou criar associacao sem veiculo existente.")
	_expect(bool(new_association.get("no_existing_vehicle", false)), "A ausencia de veiculo existente nao foi sinalizada.")
	_expect(int(dashboard.web_post_calls) == 0, "Modificar abriu POST de cadastro para aparelho sem veiculo existente.")

	var payload: Dictionary = dashboard.call("_grupo_rs_api_equipment_payload", {
		"serial": "024399999",
		"chip_number": "89555483000012345678",
		"phone": "11988887777",
		"apn": "hinova.br",
	}, {"codModelo": 2122, "codOperadora": 4}, true)
	_expect(str(payload.get("numeroSerie", "")) == "024399999", "O payload parcial perdeu a serie.")
	_expect(str(payload.get("numeroChip", "")) == "89555483000012345678", "O payload parcial perdeu o ICCID.")
	_expect(str(payload.get("numeroTelefone", "")) == "11988887777", "O payload parcial perdeu o telefone.")
	_expect(str(payload.get("apn", "")) == "hinova.br", "O payload parcial perdeu a APN.")

	dashboard.post_calls = 0
	var vehicle_registration: Dictionary = await dashboard.call("_grupo_rs_api_register_vehicle", {
		"plate": "AAA - 0004",
		"serial": "024399999",
		"api_vehicle_status": "Ativo",
	}, {"codEquipamento": 9021})
	_expect(bool(vehicle_registration.get("ok", false)), "A associacao API sem tipo de veiculo nao foi aceita no teste.")
	_expect(int(dashboard.last_json_payload.get("codCliente", 0)) == 12824, "A associacao API nao preservou o titular RS300.")
	_expect(int(dashboard.last_json_payload.get("codTipoVeiculo", 0)) == 1, "A associacao API sem tipo nao enviou Carro.")

	dashboard.post_calls = 0
	var patch_result: Dictionary = await dashboard.call("run_base_patch", {
		"serial": "024399999",
		"chip_number": "89555483000012345678",
		"phone": "11988887777",
		"apn": "hinova.br",
	}, {"id": 9021})
	_expect(not bool(patch_result.get("ok", false)), "PATCH sem confirmacao foi tratado como sucesso.")
	_expect(bool(patch_result.get("partial", false)) and bool(patch_result.get("confirmation_pending", false)), "PATCH sem confirmacao nao ficou pendente com seguranca.")
	_expect(int(dashboard.post_calls) == 1, "PATCH sem confirmacao foi repetido.")

	var store_script := load("res://src/inventory_store.gd")
	var local_store = store_script.new()
	local_store.configure("user://codex_modify_local_persistence.json")
	local_store.load_db()
	# O teste de persistencia local deve representar a condicao normal do app:
	# Firebase disponivel. Sem isso o store online-only apenas enfileira um
	# snapshot e um teste repetido pode atingir o limite da fila pendente.
	local_store.mark_remote_available()
	dashboard.set("store", local_store)
	local_store.upsert_product_replacing_sku("024399999", {
		"sku": "024399999", "imei": "024399999", "model": "RS Novo",
		"operator": "Tim", "tracker_status": "Estoque", "status": "Estoque",
		"location": "Estoque", "stock": 1,
	})
	var local_modification: Dictionary = await dashboard.call("_finalize_local_equipment_modification", {
		"serial": "024399999", "local_sku": "024399999", "new_plate": "AAA - 0101",
		"chip_number": "89555483000012345678", "phone": "11988887777", "apn": "hinova.br",
		"model": "Reutilizado", "operator": "Claro", "tracker_status": "Manutencao",
	})
	_expect(bool(local_modification.get("ok", false)), "A persistencia local da modificacao falhou.")
	var local_saved: Dictionary = local_store.get_product("024399999")
	_expect(str(local_saved.get("model", "")) == "Reutilizado", "O tipo/modelo nao foi preservado no registro local.")
	_expect(str(local_saved.get("operator", "")) == "Claro", "A operadora nao foi preservada no registro local.")
	_expect(str(local_saved.get("tracker_status", "")) == "Manutencao", "O status nao foi preservado no registro local.")
	_expect(str(local_saved.get("status", "")) == "Manutencao" and str(local_saved.get("location", "")) == "Manutencao", "Os campos derivados do status nao foram atualizados.")

	# Um aparelho que ja existia no Grupo RS antes do Firebase deve ser criado
	# no espelho local depois da modificacao remota confirmada.
	var imported_modification: Dictionary = await dashboard.call("_finalize_local_equipment_modification", {
		"serial": "997326352", "local_sku": "997326352", "new_plate": "QWE - TSD",
		"chip_number": "89555483000100000413", "phone": "98980000413", "apn": "hinova.br",
		"model": "Reutilizado", "operator": "Tim", "tracker_status": "Manutencao",
	})
	_expect(bool(imported_modification.get("ok", false)), "Um aparelho preexistente nao foi criado no espelho Firebase local.")
	var imported_saved: Dictionary = local_store.get_product("997326352")
	_expect(str(imported_saved.get("plate", "")) == "QWE - TSD", "A placa do registro importado nao foi gravada.")
	_expect(str(imported_saved.get("tracker_status", "")) == "Manutencao", "O status do registro importado nao foi gravado.")

	var form_view: Control = dashboard.call("_build_form_view", "")
	var status_option: OptionButton = (dashboard.get("form_options") as Dictionary).get("tracker_status") as OptionButton
	_expect(status_option != null and status_option.item_count == 5, "As opcoes de status nao estao acessiveis no formulario.")
	_expect(status_option.get_item_text(3) == "Manutencao" and status_option.get_item_text(0) == "Estoque", "As opcoes de status foram alteradas ou ocultadas.")
	form_view.free()

	dashboard.queue_free()
	print("MODIFY_FUNCTION_CHECK_OK")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
