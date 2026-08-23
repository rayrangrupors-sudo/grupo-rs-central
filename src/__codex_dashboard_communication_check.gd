extends SceneTree


class CommunicationDashboardStub:
	extends "res://src/inventory_dashboard.gd"

	var request_count := 0
	var fail_requests := false
	var fail_interval := ""


	func _ready() -> void:
		pass


	func _http_get_text(url: String, timeout_seconds: float = 20.0) -> Dictionary:
		request_count += 1
		if fail_requests or (fail_interval != "" and url.contains(fail_interval.uri_encode())):
			return {"ok": false, "message": "falha simulada"}
		var amounts := {
			"0 - 1 Hora": 3,
			"1 - 6 Horas": 2,
			"6 - 24 Horas": 4,
			"24 - 72 Horas": 1,
			"Manutencao": 5,
		}
		for interval_name in amounts.keys():
			if url.contains(str(interval_name).uri_encode()):
				return {"ok": true, "body": _fixture_html(int(amounts[interval_name]))}
		return {"ok": false, "message": "intervalo desconhecido"}


	func _fixture_html(amount: int) -> String:
		var rows: Array[String] = ["<tr class='dcm-apn-row'><td colspan='6'>APN</td></tr>"]
		for index in range(amount):
			var serial := "080%06d" % index if index == 0 else "024%06d" % index
			rows.append("<tr><td>CLIENTE %02d</td><td>AAA - %04d</td><td>%s</td><td>hinova</td><td>(99) 99999-0000</td><td>22/07/2026 10:00</td></tr>" % [index, index, serial])
		return "<table><tbody>%s</tbody></table>" % "".join(rows)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := CommunicationDashboardStub.new()
	dashboard.selected_branch_grupo_rs_mode = "modern"
	dashboard.selected_branch_name = "IMPERATRIZ"
	root.add_child(dashboard)
	await process_frame

	var parsed: Array = dashboard.call("_parse_dashboard_communication_rows", dashboard._fixture_html(3), "0 - 1 Hora")
	_expect(parsed.size() == 3, "Parser contou linha de agrupamento APN.")
	_expect(str((parsed[0] as Dictionary).get("serial", "")).begins_with("080"), "Grafico descartou aparelho que nao comeca com 024.")

	var snapshot: Dictionary = await dashboard.call("_fetch_dashboard_communication_snapshot")
	_expect(bool(snapshot.get("ok", false)), "Snapshot simulado falhou: %s" % str(snapshot))
	_expect(dashboard.request_count == 5, "Atualizacao deveria consultar exatamente cinco faixas.")
	_expect(int(snapshot.get("total", 0)) == 15, "Total das faixas ficou incorreto.")
	_expect(bool(snapshot.get("complete", false)), "Snapshot completo nao foi marcado como completo.")
	var counts: Dictionary = snapshot.get("counts", {})
	_expect(int(counts.get("Manutencao", 0)) == 5, "Contagem de Manutencao incorreta.")

	dashboard.dashboard_communication_snapshot = snapshot
	dashboard.fail_interval = "6 - 24 Horas"
	var incomplete_snapshot: Dictionary = await dashboard.call("_fetch_dashboard_communication_snapshot")
	_expect(not bool(incomplete_snapshot.get("ok", false)), "Falha de uma faixa nao deveria publicar snapshot parcial.")
	_expect(not bool(incomplete_snapshot.get("complete", false)), "Snapshot parcial foi marcado como completo.")
	_expect(int(incomplete_snapshot.get("successful_intervals", 0)) < 5, "Falha simulada nao foi contabilizada.")
	dashboard.fail_interval = ""

	dashboard.dashboard_communication_snapshot = snapshot
	var panel: Control = dashboard.call("_build_communication_panel", {"total": 10, "operators": {"Claro": 10}})
	root.add_child(panel)
	await process_frame
	await create_timer(0.55).timeout
	_expect(_has_text(panel, "Comunicacao dos veiculos"), "Titulo do novo grafico nao apareceu.")
	_expect(_has_button(panel, "Operadoras"), "Acesso ao grafico antigo nao foi preservado.")
	_expect(_has_text_fragment(panel, "automatico a cada 1 min"), "Frequencia automatica nao esta visivel.")
	_expect(dashboard.dashboard_communication_bar_nodes.size() == 5, "Grafico nao criou as cinco barras.")
	var first_bar: ProgressBar = dashboard.dashboard_communication_bar_nodes.get("0 - 1 Hora")
	_expect(first_bar != null and int(first_bar.value) == 3 and int(first_bar.max_value) == 15, "Barra animada nao recebeu os valores do snapshot.")

	dashboard.call("_open_dashboard_communication_interval", "Manutencao")
	await process_frame
	_expect(dashboard.dashboard_communication_detail_layer != null, "Clique da barra nao abriu a lista.")
	_expect(dashboard.dashboard_communication_detail_body.get_child_count() == 5, "Lista da faixa nao mostrou os registros esperados.")

	var many_rows: Array[Dictionary] = []
	for index in range(23):
		many_rows.append({"client": "CLIENTE %02d" % index, "plate": "AAA - %04d" % index, "serial": "024%06d" % index, "apn": "hinova", "updated_at": "agora"})
	dashboard.dashboard_communication_detail_rows = many_rows
	dashboard.dashboard_communication_detail_page = 0
	dashboard.call("_render_dashboard_communication_detail_page")
	_expect(dashboard.dashboard_communication_detail_body.get_child_count() == 10, "Detalhes deveriam renderizar dez veiculos por pagina.")
	dashboard.call("_change_dashboard_communication_detail_page", 1)
	dashboard.call("_change_dashboard_communication_detail_page", 1)
	_expect(dashboard.dashboard_communication_detail_body.get_child_count() == 3, "Ultima pagina dos detalhes deveria ter tres veiculos.")

	dashboard.dashboard_communication_last_error = "falha simulada"
	dashboard.call("_apply_dashboard_communication_snapshot", false)
	_expect(_has_text_fragment(panel, "nova tentativa em 1 min"), "Falha nao preservou nem identificou a ultima leitura valida.")

	dashboard.call("_setup_dashboard_communication_monitor")
	_expect(dashboard.dashboard_communication_timer != null and int(dashboard.dashboard_communication_timer.wait_time) == 60, "Temporizador nao foi configurado para um minuto.")
	dashboard.dashboard_communication_timer.stop()

	print("DASHBOARD_COMMUNICATION_CHECK_OK")
	dashboard.call("_close_dashboard_communication_detail")
	panel.queue_free()
	dashboard.queue_free()
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)


func _has_text(node: Node, value: String) -> bool:
	if node is Label and str((node as Label).text) == value:
		return true
	for child in node.get_children():
		if _has_text(child, value):
			return true
	return false


func _has_text_fragment(node: Node, value: String) -> bool:
	if node is Label and str((node as Label).text).contains(value):
		return true
	for child in node.get_children():
		if _has_text_fragment(child, value):
			return true
	return false


func _has_button(node: Node, value: String) -> bool:
	if node is Button and str((node as Button).text) == value:
		return true
	for child in node.get_children():
		if _has_button(child, value):
			return true
	return false
