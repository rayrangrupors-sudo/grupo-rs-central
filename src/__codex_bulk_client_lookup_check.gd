extends SceneTree


class BulkClientLookupStub:
	extends "res://src/inventory_dashboard.gd"

	var queries: Array[String] = []
	var logged_actions: Array[Dictionary] = []


	func _fetch_grupo_rs_equipment_rows(query: String) -> Array[Dictionary]:
		queries.append(query)
		match query:
			"CARLA PRISCILA DA SILVA":
				return [{"client": "CARLA PRISCILA DA SILVA", "serial": "024111111", "plate": "AAA - 1A11"}]
			"ARIMATEIA JULIO VIEIRA SALES":
				return [
					{"client": "ARIMATEIA JULIO VIEIRA SALES", "serial": "024222222", "plate": "AAA - 2A22"},
					{"client": "ARIMATEIA JULIO VIEIRA SALES", "serial": "024333333", "plate": "AAA - 3A33"},
					{"client": "OUTRO CLIENTE", "serial": "024999999", "plate": "AAA - 9A99"},
				]
			"JAIRO GUIMARAES RICARTE DA SILVA":
				return [
					{"client": "JAIRO GUIMARAES RICARTE DA SILVA JUNIOR", "serial": "024444444"},
					{"client": "JAIRO GUIMARAES RICARTE DA SILVA FILHO", "serial": "024555555"},
				]
			"CLAUDIO HENRIQUE PATRICIO DE SOUSA":
				return [{"client": "CLÁUDIO HENRIQUE PATRÍCIO DE SOUSA", "serial": "024666666"}]
		return []


	func _fetch_grupo_rs_maintenance_rows_with_status(_require_supported_apn: bool = true) -> Dictionary:
		return {
			"ok": true,
			"complete": true,
			"succeeded_intervals": ["24 - 72 Horas", "Manutencao"],
			"rows": [
				{"client": "CARLA PRISCILA DA SILVA", "serial": "024111111", "plate": "ABC - 1D23", "monitor_interval": "Manutencao"},
				{"client": "CARLA PRISCILA DA SILVA", "serial": "024111111", "plate": "ABC - 1D23", "monitor_interval": "Manutencao"},
				{"client": "ARIMATEIA JULIO VIEIRA SALES", "serial": "024222222", "plate": "DEF - 4G56", "monitor_interval": "24 - 72 Horas"},
				{"client": "FERNANDA DE ALMEIDA VIEGAS MONTEIRO", "serial": "024777777", "plate": "GHI - 7J89", "monitor_interval": "Manutencao"},
				{"client": "CLÁUDIO HENRIQUE PATRÍCIO DE SOUSA", "serial": "024666666", "plate": "JKL - 0M12", "monitor_interval": "Manutencao"},
				{"client": "CLIENTE FORA DA LISTA", "serial": "024888888", "plate": "MNO - 3P45", "monitor_interval": "Manutencao"},
			],
		}


	func _log_system_action(action: String, details: String = "", sku: String = "") -> void:
		logged_actions.append({"action": action, "details": details, "sku": sku})


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := BulkClientLookupStub.new()
	root.add_child(dashboard)
	await process_frame

	var raw_names := "Cliente\nCARLA PRISCILA DA SILVA \r\nARIMATEIA JULIO VIEIRA SALES\nFERNANDA DE ALMEIDA VIEGAS MONTEIRO\nJAIRO GUIMARAES RICARTE DA SILVA\nCLAUDIO HENRIQUE PATRICIO DE SOUSA\nCARLA PRISCILA DA SILVA\n024376142"
	var parsed: Dictionary = dashboard.call("_parse_bulk_client_names", raw_names)
	var names: Array = parsed.get("names", [])
	_expect(names.size() == 5, "Parser nao preservou cinco clientes unicos: %s" % str(parsed))
	_expect(str(names[0]) == "CARLA PRISCILA DA SILVA", "Parser alterou o primeiro nome.")
	_expect(int((parsed.get("invalid", []) as Array).size()) == 1, "Linha numerica deveria ser ignorada.")

	await dashboard.call("_run_bulk_client_tracker_lookup", _as_string_array(names), 1)
	var results: Array = dashboard.bulk_client_lookup_results
	_expect(results.size() == 5, "Consulta nao retornou um resultado por cliente.")
	_expect(str((results[0] as Dictionary).get("serial_text", "")) == "024111111", "Rastreador unico incorreto.")
	_expect(str((results[1] as Dictionary).get("serial_text", "")) == "024222222, 024333333", "Multiplos rastreadores nao ficaram na mesma celula.")
	_expect(str((results[2] as Dictionary).get("status", "")) == "Nao encontrado", "Cliente ausente deveria permanecer no relatorio.")
	_expect(str((results[3] as Dictionary).get("status", "")) == "Nome ambiguo", "Homônimos aproximados nao foram bloqueados.")
	_expect(str((results[4] as Dictionary).get("serial_text", "")) == "024666666", "Normalizacao de acentos falhou.")
	_expect(dashboard.queries.size() == 5, "Quantidade de consultas ao Grupo RS incorreta.")
	_expect(dashboard.logged_actions.size() == 1, "Resumo da consulta nao foi registrado no log.")

	var sheet_text := str(dashboard.call("_bulk_client_lookup_sheet_text", _as_dictionary_array(results)))
	var sheet_lines := sheet_text.split("\n", true)
	_expect(sheet_lines.size() == 5, "Copia nao preservou uma linha por cliente.")
	_expect(str(sheet_lines[0]) == "CARLA PRISCILA DA SILVA\t024111111", "Primeira linha nao esta em duas colunas.")
	_expect(str(sheet_lines[1]) == "ARIMATEIA JULIO VIEIRA SALES\t024222222, 024333333", "Celula com multiplos aparelhos ficou incorreta.")
	_expect(str(sheet_lines[2]) == "FERNANDA DE ALMEIDA VIEGAS MONTEIRO\t", "Cliente sem resultado nao preservou a segunda celula vazia.")

	var mass_view: Control = dashboard.call("_build_bulk_registration_view")
	_expect(_has_button_text(mass_view, "Consultar clientes"), "Botao Consultar clientes nao apareceu na pagina Massa.")
	_expect(_has_button_text(mass_view, "Checar manutencao"), "Botao Checar manutencao nao apareceu na pagina Massa.")
	_expect(_has_text_fragment(mass_view, "Consulta por cliente"), "Exemplo de nomes nao apareceu na entrada em massa.")
	mass_view.free()

	_expect(dashboard.bulk_client_lookup_report_layer != null, "Relatorio visual nao foi aberto ao finalizar.")
	_expect(_has_button_text(dashboard.bulk_client_lookup_report_layer, "Copiar para Sheets"), "Relatorio nao oferece copia para Google Sheets.")
	_expect(dashboard.bulk_client_lookup_report_body.get_child_count() == 5, "Relatorio nao renderizou os cinco resultados.")

	await dashboard.call("_run_bulk_client_maintenance_lookup", _as_string_array(names), 0)
	var maintenance_results: Array = dashboard.bulk_client_lookup_results
	_expect(maintenance_results.size() == 3, "Consulta deveria retornar somente tres veiculos em Manutencao: %s" % str(maintenance_results))
	_expect(str((maintenance_results[0] as Dictionary).get("input_name", "")) == "CARLA PRISCILA DA SILVA", "Cliente em manutencao incorreto.")
	_expect(str((maintenance_results[0] as Dictionary).get("plate_text", "")) == "ABC - 1D23", "Placa em manutencao incorreta.")
	_expect(not str(maintenance_results).contains("DEF - 4G56"), "Aparelho da faixa 24 - 72 Horas vazou para o relatorio de manutencao.")
	_expect(not str(maintenance_results).contains("CLIENTE FORA DA LISTA"), "Cliente nao solicitado vazou para o relatorio.")
	var maintenance_sheet := str(dashboard.call("_bulk_client_lookup_sheet_text", _as_dictionary_array(maintenance_results), "plate_text"))
	_expect(maintenance_sheet.contains("CARLA PRISCILA DA SILVA\tABC - 1D23"), "Copia Cliente/Placa nao esta tabulada.")
	_expect(not maintenance_sheet.contains("024111111"), "Copia de manutencao incluiu o rastreador em vez da placa.")
	_expect(str(dashboard.bulk_client_lookup_report_mode) == "maintenance", "Relatorio nao entrou no modo manutencao.")
	_expect(_has_text_fragment(dashboard.bulk_client_lookup_report_layer, "Somente aparelhos presentes na faixa Manutencao"), "Relatorio nao identifica a fonte Manutencao.")

	var paged_results: Array[Dictionary] = []
	for index in range(23):
		paged_results.append({"input_name": "CLIENTE %02d" % index, "plate_text": "AAA - %04d" % index, "status": "Em manutencao", "ok": true})
	dashboard.bulk_client_lookup_results = paged_results
	dashboard.bulk_client_lookup_current_page = 0
	dashboard.call("_render_bulk_client_lookup_report_page")
	_expect(dashboard.bulk_client_lookup_report_body.get_child_count() == 10, "Primeira pagina deveria conter dez registros.")
	dashboard.call("_change_bulk_client_lookup_page", 1)
	_expect(dashboard.bulk_client_lookup_report_body.get_child_count() == 10, "Segunda pagina deveria conter dez registros.")
	dashboard.call("_change_bulk_client_lookup_page", 1)
	_expect(dashboard.bulk_client_lookup_report_body.get_child_count() == 3, "Ultima pagina deveria conter tres registros.")

	dashboard.call("_close_bulk_client_lookup_report")
	print("BULK_CLIENT_LOOKUP_CHECK_OK")
	dashboard.queue_free()
	quit(0)


func _as_string_array(values: Array) -> Array[String]:
	var typed: Array[String] = []
	for value in values:
		typed.append(str(value))
	return typed


func _as_dictionary_array(values: Array) -> Array[Dictionary]:
	var typed: Array[Dictionary] = []
	for value in values:
		if typeof(value) == TYPE_DICTIONARY:
			typed.append(value as Dictionary)
	return typed


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)


func _has_button_text(node: Node, value: String) -> bool:
	if node is Button and str((node as Button).text) == value:
		return true
	for child in node.get_children():
		if _has_button_text(child, value):
			return true
	return false


func _has_text_fragment(node: Node, value: String) -> bool:
	if node is Label and str((node as Label).text).contains(value):
		return true
	if node is TextEdit and str((node as TextEdit).placeholder_text).contains(value):
		return true
	for child in node.get_children():
		if _has_text_fragment(child, value):
			return true
	return false
