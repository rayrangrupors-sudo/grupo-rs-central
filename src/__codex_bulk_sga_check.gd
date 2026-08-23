extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := load("res://src/inventory_dashboard.gd")
	if dashboard_script == null:
		_fail("Tela principal nao carregou.")
		return
	var dashboard: Control = dashboard_script.new()

	var parsed: Dictionary = dashboard.call(
		"_parse_bulk_client_names",
		"Cliente\nJOAO DA SILVA SOARES\nMARIA TESTE\nJOAO DA SILVA SOARES"
	)
	var names: Array = parsed.get("names", [])
	if names != ["JOAO DA SILVA SOARES", "MARIA TESTE"]:
		dashboard.free()
		_fail("A lista de nomes nao preservou ordem e unicidade: %s" % str(names))
		return

	var lookup := {
		"client": "JOAO DA SILVA SOARES",
		"rastreio": {
			"ok": true,
			"state": "ok",
			"customer_name": "JOAO DA SILVA SOARES",
			"associate_status": "ATIVO",
			"vehicle_status": "",
			"financial_status": "",
		},
		"protecao": {
			"ok": false,
			"state": "not_found",
			"message": "Cliente nao localizado.",
		},
	}
	var result: Dictionary = dashboard.call(
		"_build_bulk_client_sga_result",
		"JOAO DA SILVA SOARES",
		lookup
	)
	if str(result.get("sga_rastreio_text", "")) != "Ativo" \
			or str(result.get("sga_protecao_text", "")) != "nao localizado" \
			or str(result.get("status", "")) != "Retorno parcial":
		dashboard.free()
		_fail("Resultado consolidado dos SGA ficou incorreto: %s" % str(result))
		return

	var second_result: Dictionary = dashboard.call(
		"_build_bulk_client_sga_result",
		"MARIA TESTE",
		{
			"client": "MARIA TESTE",
			"rastreio": {"ok": true, "state": "ok", "associate_status": "INADIMPLENTE"},
			"protecao": {"ok": true, "state": "ok", "associate_status": "ATIVO"},
		}
	)
	var results: Array[Dictionary] = [result, second_result]
	var sheet_text := str(dashboard.call("_bulk_client_sga_sheet_text", results))
	var sheet_lines := sheet_text.split("\n")
	if sheet_lines.size() != 2 \
			or str(sheet_lines[0]).split("\t").size() != 3 \
			or not str(sheet_lines[1]).begins_with("MARIA TESTE\tInadimplente\tAtivo"):
		dashboard.free()
		_fail("Relatorio para o Google Sheets nao possui tres colunas: %s" % sheet_text)
		return

	dashboard.set("bulk_client_lookup_report_mode", "sga")
	var report_row: Control = dashboard.call("_make_bulk_client_lookup_report_row", result)
	if not _has_label_fragment(report_row, "JOAO DA SILVA SOARES") \
			or not _has_label_fragment(report_row, "Ativo") \
			or not _has_label_fragment(report_row, "nao localizado"):
		report_row.free()
		dashboard.free()
		_fail("Linha visual dos dois SGA nao exibiu todos os dados.")
		return
	report_row.free()

	var toolbar: Control = dashboard.call("_build_bulk_command_toolbar")
	if not _has_button(toolbar, "Consultar SGA"):
		toolbar.free()
		dashboard.free()
		_fail("Botao Consultar SGA nao apareceu na tela de massa.")
		return
	toolbar.free()
	dashboard.free()
	print("BULK_SGA_CHECK_OK")
	quit(0)


func _has_label_fragment(node: Node, fragment: String) -> bool:
	if node is Label and str((node as Label).text).contains(fragment):
		return true
	for child in node.get_children():
		if _has_label_fragment(child, fragment):
			return true
	return false


func _has_button(node: Node, text_value: String) -> bool:
	if node is Button and str((node as Button).text) == text_value:
		return true
	for child in node.get_children():
		if _has_button(child, text_value):
			return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
