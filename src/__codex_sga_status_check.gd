extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := load("res://src/inventory_dashboard.gd")
	if dashboard_script == null:
		_fail(null, "Dashboard nao carregou.")
		return

	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame

	if str(dashboard.call("_sga_source_label", "rastreio")) != "Rastreio":
		_fail(dashboard, "Rotulo do SGA Rastreio incorreto.")
		return
	if str(dashboard.call("_sga_source_label", "protecao")) != "Protecao":
		_fail(dashboard, "Rotulo do SGA Protecao incorreto.")
		return
	if str(dashboard.call("_sga_api_token_validation_message", "https://sga.hinova.com.br/portal/")) == "":
		_fail(dashboard, "URL do portal foi aceita incorretamente como token API.")
		return
	if str(dashboard.call("_sga_api_token_validation_message", "4831")) == "":
		_fail(dashboard, "Codigo do cliente foi aceito incorretamente como token API.")
		return

	var active_overdue := {
		"state": "ok",
		"associate_status": "ATIVO",
		"vehicle_status": "ATIVO",
		"financial_status": "INADIMPLENTE",
	}
	if str(dashboard.call("_sga_status_summary", active_overdue)) != "Ativo / Inadimplente":
		_fail(dashboard, "Resumo cadastral/financeiro nao removeu duplicidade corretamente.")
		return
	if str(dashboard.call("_sga_result_text", "protecao", active_overdue)) != "Protecao: Ativo / Inadimplente":
		_fail(dashboard, "Texto do resultado SGA Protecao incorreto.")
		return

	var cancelled := {
		"state": "ok",
		"associate_status": "CANCELADO",
		"vehicle_status": "INATIVO",
		"financial_status": "",
	}
	if str(dashboard.call("_sga_status_summary", cancelled)) != "Cancelado / Inativo":
		_fail(dashboard, "Situacoes cancelado/inativo nao foram preservadas.")
		return

	var nested: Dictionary = dashboard.call("_sga_response_dictionary", {
		"data": {
			"descricao_situacao_veiculo": "ATIVO",
			"situacao_financeira": "ADIMPLENTE",
		}
	})
	if str(nested.get("situacao_financeira", "")) != "ADIMPLENTE":
		_fail(dashboard, "Resposta envelopada da API SGA nao foi interpretada.")
		return

	if str(dashboard.call("_sga_result_state_from_body", "Cliente nao encontrado", 200)) != "not_found":
		_fail(dashboard, "Mensagem de cliente nao encontrado deveria ser nao localizado.")
		return
	if str(dashboard.call("_sga_result_state_from_body", "Acesso negado", 401)) != "login":
		_fail(dashboard, "Resposta 401 do SGA deveria pedir acesso.")
		return

	var users_html := "<table><tbody><tr><td>CLIENTE TESTE</td><td>cliente.teste</td><td></td><td><a href='usuarios_editar.php?id=42'>Editar</a></td></tr></tbody></table>"
	var user_rows: Array[Dictionary] = dashboard.call("_parse_grupo_rs_user_rows", users_html)
	if user_rows.size() != 1 or str(user_rows[0].get("edit_href", "")) != "usuarios_editar.php?id=42":
		_fail(dashboard, "Lista de Usuarios do Grupo RS nao foi interpretada.")
		return
	var selected_user: Dictionary = dashboard.call("_select_grupo_rs_user_row", user_rows, "cliente teste")
	if str(selected_user.get("client", "")) != "CLIENTE TESTE":
		_fail(dashboard, "Cliente exato nao foi selecionado em Usuarios.")
		return
	var equipment_html := "<table><tbody><tr><td>024288081</td><td>PSO - 8628</td><td>JOAO DA SILVA SOARES</td><td>89551180157006044933</td><td>(83) 9876-05894</td><td>Ativo</td></tr></tbody></table>"
	var equipment_rows: Array[Dictionary] = dashboard.call("_parse_grupo_rs_equipment_rows", equipment_html)
	var plate_equipment: Dictionary = dashboard.call("_select_grupo_rs_equipment_row_by_plate", equipment_rows, "pso8628")
	if str(plate_equipment.get("client", "")) != "JOAO DA SILVA SOARES":
		_fail(dashboard, "Associado nao foi resolvido pela correspondencia exata da placa.")
		return
	var local_without_client := {"sku": "02428808", "plate": "PSO - 8628", "client": ""}
	if str(dashboard.call("_sga_product_cache_key", local_without_client)) != "plate:PSO8628":
		_fail(dashboard, "Cadastro local sem cliente nao recebeu uma chave SGA pela placa.")
		return
	var latin_name := PackedByteArray([0x4A, 0x4F, 0xC3, 0x4F])
	var expected_latin_name := "JO%sO" % String.chr(0x00C3)
	if str(dashboard.call("_decode_http_body_bytes", latin_name)) != expected_latin_name:
		_fail(dashboard, "Nome em Latin-1 do Sistema RS nao foi decodificado corretamente.")
		return
	var invalid_cpf: Dictionary = await dashboard.call("_lookup_sga_source_by_cpf", "123", "CLIENTE TESTE", "rastreio")
	if str(invalid_cpf.get("state", "")) != "cpf_invalid":
		_fail(dashboard, "CPF invalido deveria ser bloqueado antes da consulta SGA.")
		return

	dashboard.set("sga_status_cache", {
		"clienteteste": {
			"checked_at": int(Time.get_unix_time_from_system()),
			"rastreio": active_overdue,
			"protecao": cancelled,
		}
	})
	var cell: Control = dashboard.call("_make_sga_status_cell", {"client": "CLIENTE TESTE"}, 292.0)
	var labels := _collect_label_text(cell)
	if not labels.has("Rastreio: Ativo / Inadimplente"):
		_fail(dashboard, "Celula visual nao mostrou o SGA Rastreio.")
		return
	if not labels.has("Protecao: Cancelado / Inativo"):
		_fail(dashboard, "Celula visual nao mostrou o SGA Protecao.")
		return
	var strip: Control = dashboard.call("_make_sga_status_strip", {"client": "CLIENTE TESTE"})
	var strip_labels := _collect_label_text(strip)
	if not strip_labels.has("Situacao SGA") or not strip_labels.has("Rastreio: Ativo / Inadimplente") or not strip_labels.has("Protecao: Cancelado / Inativo"):
		_fail(dashboard, "Faixa visual nao exibiu as duas situacoes SGA.")
		return
	dashboard.set("sga_status_cache", {
		"plate:PSO8628": {
			"checked_at": int(Time.get_unix_time_from_system()),
			"rastreio": active_overdue,
			"protecao": cancelled,
		}
	})
	var fallback_strip: Control = dashboard.call("_make_sga_status_strip", local_without_client)
	var fallback_labels := _collect_label_text(fallback_strip)
	if not fallback_labels.has("Rastreio: Ativo / Inadimplente") or not fallback_labels.has("Protecao: Cancelado / Inativo"):
		_fail(dashboard, "Cadastro local sem cliente nao exibiu o resultado SGA armazenado pela placa.")
		return
	dashboard.set("config_selected_section", "sga")
	var config_view: Control = dashboard.call("_build_arya_config_view")
	var config_labels := _collect_label_text(config_view)
	if not config_labels.has("SGA Hinova") or not config_labels.has("SGA de Rastreio") or not config_labels.has("SGA de Protecao"):
		_fail(dashboard, "Configuracoes nao exibiram os dois acessos SGA.")
		return

	cell.free()
	strip.free()
	fallback_strip.free()
	config_view.free()
	dashboard.queue_free()
	await process_frame
	print("SGA_STATUS_CHECK_OK")
	quit(0)


func _collect_label_text(node: Node) -> Array[String]:
	var result: Array[String] = []
	if node is Label:
		result.append(str((node as Label).text))
	for child in node.get_children():
		result.append_array(_collect_label_text(child))
	return result


func _fail(dashboard: Node, message: String) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)
