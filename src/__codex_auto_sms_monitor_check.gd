extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := load("res://src/inventory_dashboard.gd")
	var store_script := load("res://src/inventory_store.gd")
	if dashboard_script == null or store_script == null:
		push_error("Scripts principais nao carregaram.")
		quit(1)
		return

	var dashboard: Node = dashboard_script.new()
	var test_store = store_script.new()
	test_store.configure("user://__codex_auto_sms_inventory.json", "__codex_auto_sms_inventory.json", "user://__codex_auto_sms_backups", false)
	test_store.load_db()
	dashboard.set("store", test_store)
	dashboard.set("selected_branch_id", "__codex_auto_sms")
	dashboard.set("selected_branch_name", "Teste")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")

	var html := """
	<table>
		<tbody>
			<tr>
				<td>CLIENTE LINK</td>
				<td>ABC - 1234</td>
				<td>024376142</td>
				<td><span>linksolutions</span></td>
				<td><button onclick="abrirSmsManualModal('(99) 98888-7777','024376142','linksolutions')">(99) 98888-7777</button></td>
				<td>17/07/2026 09:00:00</td>
			</tr>
			<tr>
				<td>CLIENTE IGNORADO</td>
				<td>XYZ - 0000</td>
				<td>17228</td>
				<td><span>hinova</span></td>
				<td><button onclick="abrirSmsManualModal('(99) 90000-0000','17228','hinova')">(99) 90000-0000</button></td>
				<td>17/07/2026 08:00:00</td>
			</tr>
			<tr>
				<td>CLIENTE HINOVA</td>
				<td>DEF - 5678</td>
				<td>024302023</td>
				<td><span>hinova</span></td>
				<td><button onclick="abrirSmsManualModal('(31) 97304-6841','024302023','hinova')">(31) 97304-6841</button></td>
				<td>17/07/2026 07:30:00</td>
			</tr>
		</tbody>
	</table>
	"""

	var rows: Array = dashboard.call("_parse_grupo_rs_maintenance_rows", html, "24 - 72 Horas")
	if rows.size() != 2:
		push_error("Parser deveria aceitar as series 024 com APN Hinova e Link Solutions. Resultado: %s" % str(rows))
		_cleanup(dashboard)
		quit(1)
		return

	var link_row := _find_row(rows, "024376142")
	var hinova_row := _find_row(rows, "024302023")
	if link_row.is_empty() or hinova_row.is_empty():
		push_error("Parser nao encontrou as series Hinova e Link Solutions esperadas.")
		_cleanup(dashboard)
		quit(1)
		return
	if str(link_row.get("sms_queue_source", "")) != "grupo_rs_manual" or str(hinova_row.get("sms_queue_source", "")) != "grupo_rs_manual":
		push_error("Linha grafica nao recebeu a marca de SMS manual.")
		_cleanup(dashboard)
		quit(1)
		return
	if str(hinova_row.get("monitor_interval", "")) != "24 - 72 Horas":
		push_error("Intervalo da lista grafica nao foi preservado.")
		_cleanup(dashboard)
		quit(1)
		return

	var now_like := int(dashboard.call("_local_now_to_unix_like"))
	var exactly_24h := _grupo_rs_datetime(now_like - 1440 * 60)
	var exactly_24h01 := _grupo_rs_datetime(now_like - 1441 * 60)
	if bool(dashboard.call("_auto_reset_location_is_stale", {"updated_at": exactly_24h})):
		push_error("Aparelho com 24h00 nao pode receber o SMS antes de completar 24h01.")
		_cleanup(dashboard)
		quit(1)
		return
	if not bool(dashboard.call("_auto_reset_location_is_stale", {"updated_at": exactly_24h01})):
		push_error("Aparelho com 24h01 deveria estar elegivel para o SMS.")
		_cleanup(dashboard)
		quit(1)
		return
	if absf(float(dashboard.call("_auto_reset_grupo_rs_sms_delay_seconds")) - 15.0) > 0.01:
		push_error("Intervalo real entre SMS deveria ser de 15 segundos.")
		_cleanup(dashboard)
		quit(1)
		return

	var link_command := str(dashboard.call("_rs300_apn_command_for_apn", "024376142", "linksolutions"))
	var hinova_command := str(dashboard.call("_rs300_apn_command_for_apn", "024302023", "hinova"))
	var time_command := str(dashboard.call("_rs300_sms_commands", "024302023").get("time", ""))
	if time_command != "ST300RPT;024302023;02;3600;60;60;1;0;300;0;0;0":
		push_error("Perfil de tempo seguro do RS300 incorreto: %s" % time_command)
		_cleanup(dashboard)
		quit(1)
		return
	if link_command != "ST300NTW;024376142;319H;0;linksolutions.br;link;link;grupors1.ddns.net;5940;grupors1.ddns.net;5941;#":
		push_error("Comando automatico Link Solutions incorreto: %s" % link_command)
		_cleanup(dashboard)
		quit(1)
		return
	if hinova_command != "ST300NTW;024302023;319H;0;hinova.br;hinova;hinova;grupors1.ddns.net;5940;grupors1.ddns.net;5941;#":
		push_error("Comando HINOVA incorreto: %s" % hinova_command)
		_cleanup(dashboard)
		quit(1)
		return

	var flow_script := load("res://src/__codex_auto_sms_dashboard_stub.gd")
	if flow_script == null:
		push_error("Stub do monitor SMS nao carregou.")
		_cleanup(dashboard)
		quit(1)
		return

	var manual_dashboard: Node = flow_script.new()
	root.add_child(manual_dashboard)
	await process_frame
	manual_dashboard.set("selected_branch_grupo_rs_mode", "modern")
	manual_dashboard.set("test_grupo_rs_equipment_rows", [{
		"serial": "02430556",
		"plate": "AAA - T250",
		"client": "CLIENTE MANUAL",
		"chip": "8955000000000000000",
		"phone": "(62) 99862-7283",
		"status": "Instalado",
		"apn": "linksolutions",
	}])
	manual_dashboard.set("test_grupo_rs_equipment_apn", "linksolutions")
	var manual_rows: Array = await manual_dashboard.call("_fetch_grupo_rs_equipment_rows", "02430556")
	if manual_rows.is_empty():
		push_error("Stub do fluxo manual nao retornou a linha de equipamento.")
		manual_dashboard.queue_free()
		_cleanup(dashboard)
		quit(1)
		return
	var manual_target: Dictionary = await manual_dashboard.call("_resolve_grupo_rs_manual_sms_target", {
		"sku": "02430556",
		"imei": "02430556",
		"plate": "AAA - T250",
		"chip_phone": "",
		"apn": "",
	})
	if not bool(manual_target.get("ok", false)):
		push_error("Fluxo manual nao resolveu telefone/APN: %s" % str(manual_target))
		manual_dashboard.queue_free()
		_cleanup(dashboard)
		quit(1)
		return
	if str(manual_target.get("phone", "")) != "(62) 99862-7283" or str(manual_target.get("apn", "")) != "linksolutions":
		push_error("Fluxo manual nao preservou telefone/APN do Grupo RS: %s" % str(manual_target))
		manual_dashboard.queue_free()
		_cleanup(dashboard)
		quit(1)
		return
	var manual_command := str(manual_dashboard.call("_rs300_apn_command_for_apn", "02430556", str(manual_target.get("apn", ""))))
	if manual_command != "ST300NTW;02430556;319H;0;linksolutions.br;link;link;grupors1.ddns.net;5940;grupors1.ddns.net;5941;#":
		push_error("Fluxo manual nao escolheu comando Link Solutions: %s" % manual_command)
		manual_dashboard.queue_free()
		_cleanup(dashboard)
		quit(1)
		return
	manual_dashboard.queue_free()
	await process_frame

	if not bool(dashboard.call("_auto_reset_can_send", "024302023")):
		push_error("Serie nova deveria estar liberada para o primeiro e unico SMS.")
		_cleanup(dashboard)
		quit(1)
		return

	dashboard.call("_auto_reset_register_attempt", "024302023")
	if bool(dashboard.call("_auto_reset_can_send", "024302023")):
		push_error("Trava nao bloqueou o segundo SMS para a mesma serie.")
		_cleanup(dashboard)
		quit(1)
		return

	var attempts: Dictionary = dashboard.get("auto_reset_attempts")
	var attempt: Dictionary = attempts.get("024302023", {})
	attempt["date"] = "2000-01-01"
	attempts["024302023"] = attempt
	dashboard.set("auto_reset_attempts", attempts)
	dashboard.set("auto_reset_due_rechecks", {
		"024302023": {
			"sku": "024302023",
			"due_at": int(Time.get_unix_time_from_system()) + 1800,
		}
	})
	dashboard.call("_save_auto_reset_state")
	if bool(dashboard.call("_auto_reset_can_send", "024302023")):
		push_error("Mudanca de dia removeu indevidamente a trava de SMS unico.")
		_cleanup(dashboard)
		quit(1)
		return

	var restarted_dashboard: Node = dashboard_script.new()
	restarted_dashboard.set("selected_branch_id", "__codex_auto_sms")
	restarted_dashboard.call("_load_auto_reset_state")
	if bool(restarted_dashboard.call("_auto_reset_can_send", "024302023")):
		push_error("Reinicio do programa removeu indevidamente a trava persistente.")
		restarted_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return
	var migrated_rechecks: Dictionary = restarted_dashboard.get("auto_reset_due_rechecks")
	var migrated_recheck: Dictionary = migrated_rechecks.get("024302023", {})
	if int(migrated_recheck.get("due_at", 0)) < int(Time.get_unix_time_from_system()) + 86300 or not bool(migrated_recheck.get("migrated_to_24h", false)):
		push_error("Prazo antigo de 30 minutos nao foi migrado com seguranca para 24 horas.")
		restarted_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return
	restarted_dashboard.free()

	var location: Dictionary = dashboard.call("_auto_reset_location_from_grupo_rs_product", hinova_row)
	dashboard.call("_schedule_auto_reset_recheck", "024302023", "024302023", hinova_row, location)
	var rechecks: Dictionary = dashboard.get("auto_reset_due_rechecks")
	var recheck_item: Dictionary = rechecks.get("024302023", {})
	if recheck_item.is_empty() or str(recheck_item.get("sms_queue_source", "")) != "grupo_rs_manual":
		push_error("Recheck de 24 horas nao foi agendado como SMS manual Grupo RS.")
		_cleanup(dashboard)
		quit(1)
		return
	if int(recheck_item.get("due_at", 0)) <= int(Time.get_unix_time_from_system()):
		push_error("Recheck foi agendado sem aguardar as 24 horas.")
		_cleanup(dashboard)
		quit(1)
		return

	attempts = dashboard.get("auto_reset_attempts")
	attempt = attempts.get("024302023", {})
	attempt["last_sent"] = int(Time.get_unix_time_from_system()) - 86401
	attempts["024302023"] = attempt
	dashboard.set("auto_reset_attempts", attempts)
	if not bool(dashboard.call("_auto_reset_attempt_recheck_due", "024302023")):
		push_error("Apos 24 horas o aparelho deveria estar pronto para o recheck.")
		_cleanup(dashboard)
		quit(1)
		return

	var hinova_maintenance_row := hinova_row.duplicate(true)
	hinova_maintenance_row["monitor_interval"] = "Manutencao"
	var added := bool(dashboard.call("_auto_reset_add_maintenance_from_grupo_rs_product", "024302023", hinova_maintenance_row))
	if not added:
		push_error("Produto pendente nao entrou na lista de manutencao.")
		_cleanup(dashboard)
		quit(1)
		return

	var maintenances: Array = test_store.get_maintenances()
	if maintenances.size() != 1:
		push_error("Quantidade inesperada de manutencoes: %d" % maintenances.size())
		_cleanup(dashboard)
		quit(1)
		return
	var maintenance := maintenances[0] as Dictionary
	if str(maintenance.get("client", "")) != "CLIENTE HINOVA":
		push_error("Cliente da manutencao incorreto.")
		_cleanup(dashboard)
		quit(1)
		return
	if str(maintenance.get("plate", "")) != "DEF - 5678":
		push_error("Placa da manutencao incorreta.")
		_cleanup(dashboard)
		quit(1)
		return
	if str(maintenance.get("serial", "")) != "024302023":
		push_error("Serie da manutencao incorreta.")
		_cleanup(dashboard)
		quit(1)
		return
	var note := str(maintenance.get("note", ""))
	if not note.contains("sem retorno apos 24 horas") or not note.contains("Intervalo: Manutencao") or not note.contains("APN: hinova"):
		push_error("Observacao automatica da manutencao incompleta: %s" % note)
		_cleanup(dashboard)
		quit(1)
		return

	test_store.add_maintenances([{
		"client": "CLIENTE PREVENTIVO ANTIGO",
		"plate": "PRV - 0001",
		"serial": "024355555",
		"note": "Entrada automatica pelo monitor: SMS unico sem retorno. | Intervalo: 24 - 72 Horas",
	}])
	if bool(dashboard.call("_auto_reset_is_in_maintenance", "024355555", "PRV - 0001")):
		push_error("Registro preventivo antigo continuou bloqueando os comandos do monitor.")
		_cleanup(dashboard)
		quit(1)
		return

	var flow_dashboard: Node = flow_script.new()
	flow_dashboard.set("store", test_store)
	flow_dashboard.set("selected_branch_id", "__codex_auto_sms_flow")
	var flow_serial := "024399999"
	var flow_updated_at := "01/01/2020 00:00:00"
	flow_dashboard.set("auto_reset_first_stale", {
		flow_serial: {
			"first_seen": int(Time.get_unix_time_from_system()) - 1801,
			"updated_at": flow_updated_at,
			"plate": "TST - 0001",
			"client": "CLIENTE TESTE FLUXO",
		},
	})
	var flow_product := {
		"sku": flow_serial,
		"imei": flow_serial,
		"equipment_number": flow_serial,
		"plate": "TST - 0001",
		"client": "CLIENTE TESTE FLUXO",
		"status": "Instalado",
	}
	var first_result: Dictionary = await flow_dashboard.call("_evaluate_auto_reset_product", flow_product, false)
	if not bool(first_result.get("sent", false)) or int(flow_dashboard.get("test_send_calls")) != 1:
		push_error("Primeira verificacao nao realizou exatamente um envio simulado: %s" % str(first_result))
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return

	var second_result: Dictionary = await flow_dashboard.call("_evaluate_auto_reset_product", flow_product, false)
	if bool(second_result.get("sent", false)) or int(flow_dashboard.get("test_send_calls")) != 1:
		push_error("Segunda verificacao repetiu o SMS: %s" % str(second_result))
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return

	var flow_attempts: Dictionary = flow_dashboard.get("auto_reset_attempts")
	var flow_attempt: Dictionary = flow_attempts.get(flow_serial, {})
	flow_attempt["last_sent"] = int(Time.get_unix_time_from_system()) - 86401
	flow_attempts[flow_serial] = flow_attempt
	flow_dashboard.set("auto_reset_attempts", flow_attempts)
	var final_result: Dictionary = await flow_dashboard.call("_evaluate_auto_reset_product", flow_product, true)
	if not bool(final_result.get("maintenance", false)) or int(flow_dashboard.get("test_send_calls")) != 1:
		push_error("Recheck nao encaminhou para manutencao ou repetiu o SMS: %s" % str(final_result))
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return
	if not bool(flow_dashboard.call("_auto_reset_is_in_maintenance", flow_serial, "TST - 0001")):
		push_error("Equipamento sem retorno nao ficou bloqueado pela lista de manutencao.")
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return

	var fail_dashboard: Node = flow_script.new()
	fail_dashboard.set("store", test_store)
	fail_dashboard.set("selected_branch_id", "__codex_auto_sms_fail")
	fail_dashboard.set("test_grupo_rs_send_ok", false)
	var failed_send_result: Dictionary = await fail_dashboard.call("_evaluate_auto_reset_grupo_rs_maintenance_product", link_row)
	if bool(failed_send_result.get("sent", false)):
		push_error("Falha de envio foi marcada como SMS enviado: %s" % str(failed_send_result))
		fail_dashboard.free()
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return
	if int(fail_dashboard.get("test_grupo_rs_send_calls")) != 1:
		push_error("Falha simulada deveria tentar exatamente um envio.")
		fail_dashboard.free()
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return
	if not bool(fail_dashboard.call("_auto_reset_can_send", "024376142")):
		push_error("Falha de envio nao pode travar a serie como SMS unico enviado.")
		fail_dashboard.free()
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return
	var fail_rechecks: Dictionary = fail_dashboard.get("auto_reset_due_rechecks")
	if fail_rechecks.has("024376142"):
		push_error("Falha de envio nao pode agendar recheck de 24 horas.")
		fail_dashboard.free()
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return
	fail_dashboard.free()

	var link_first_result: Dictionary = await flow_dashboard.call("_evaluate_auto_reset_grupo_rs_maintenance_product", link_row)
	if not bool(link_first_result.get("sent", false)) or int(flow_dashboard.get("test_grupo_rs_send_calls")) != 1:
		push_error("Monitor nao enviou o SMS Link Solutions pela fila simulada do Grupo RS: %s" % str(link_first_result))
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return

	var link_second_result: Dictionary = await flow_dashboard.call("_evaluate_auto_reset_grupo_rs_maintenance_product", link_row)
	if bool(link_second_result.get("sent", false)) or int(flow_dashboard.get("test_grupo_rs_send_calls")) != 1:
		push_error("Monitor repetiu o SMS Link Solutions: %s" % str(link_second_result))
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return

	flow_dashboard.call("_auto_reset_clear_stale_state", "024376142")
	if bool(flow_dashboard.call("_auto_reset_can_send", "024376142")):
		push_error("A recuperacao apagou indevidamente o bloqueio vitalicio do SMS.")
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return
	flow_dashboard.call(
		"_schedule_auto_reset_recheck",
		"024376142",
		"024376142",
		link_row,
		flow_dashboard.call("_auto_reset_location_from_grupo_rs_product", link_row)
	)
	var recheck_rows: Array[Dictionary] = [link_row]
	flow_dashboard.set("test_grupo_rs_maintenance_rows", recheck_rows)
	var link_rechecks: Dictionary = flow_dashboard.get("auto_reset_due_rechecks")
	var link_recheck_item: Dictionary = link_rechecks.get("024376142", {})
	var notifications_before_recheck := int(flow_dashboard.get("test_notification_calls"))
	var link_final_result: Dictionary = await flow_dashboard.call(
		"_evaluate_auto_reset_grupo_rs_sms_recheck",
		"024376142",
		link_row,
		link_recheck_item
	)
	if not bool(link_final_result.get("maintenance", false)) or int(flow_dashboard.get("test_grupo_rs_send_calls")) != 1:
		push_error("Aparelho ainda sem comunicar apos 24h nao entrou em manutencao: %s" % str(link_final_result))
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return
	if int(flow_dashboard.get("test_notification_calls")) != notifications_before_recheck + 1 or not str(flow_dashboard.get("test_notification_message")).contains("Aparelho 024376142 oscilante"):
		push_error("Alerta de oscilacao nao foi emitido corretamente.")
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return

	var non_candidate := link_row.duplicate(true)
	non_candidate["serial"] = "024477777"
	non_candidate["sku"] = "024477777"
	non_candidate["imei"] = "024477777"
	non_candidate["equipment_number"] = "024477777"
	non_candidate["monitor_interval"] = "Manutencao"
	var non_candidate_result: Dictionary = await flow_dashboard.call("_evaluate_auto_reset_grupo_rs_maintenance_product", non_candidate)
	if bool(non_candidate_result.get("sent", false)) or int(flow_dashboard.get("test_grupo_rs_send_calls")) != 1:
		push_error("A lista Manutencao foi usada indevidamente como origem de SMS.")
		flow_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return
	flow_dashboard.free()

	var arya_fail_dashboard: Node = flow_script.new()
	arya_fail_dashboard.set("store", test_store)
	arya_fail_dashboard.set("selected_branch_id", "__codex_auto_sms_arya_fail")
	arya_fail_dashboard.set("test_arya_send_ok", false)
	var arya_fail_serial := "024488888"
	arya_fail_dashboard.set("test_location", {
		"ok": true,
		"equipment_serial": arya_fail_serial,
		"plate": "ARY - 0001",
		"client": "CLIENTE ARYA FALHA",
		"updated_at": "01/01/2020 00:00:00",
	})
	var arya_fail_result: Dictionary = await arya_fail_dashboard.call("_evaluate_auto_reset_product", {
		"sku": arya_fail_serial,
		"imei": arya_fail_serial,
		"equipment_number": arya_fail_serial,
		"plate": "ARY - 0001",
		"client": "CLIENTE ARYA FALHA",
		"status": "Instalado",
	}, false)
	if bool(arya_fail_result.get("sent", false)) or not bool(arya_fail_result.get("errors", false)) or int(arya_fail_dashboard.get("test_send_calls")) != 1 or not bool(arya_fail_dashboard.call("_auto_reset_can_send", arya_fail_serial)):
		push_error("Falha Arya gravou um envio inexistente ou bloqueou a serie.")
		arya_fail_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return
	if not (arya_fail_dashboard.get("auto_reset_due_rechecks") as Dictionary).is_empty():
		push_error("Falha Arya agendou um recheck indevido.")
		arya_fail_dashboard.free()
		_cleanup(dashboard)
		quit(1)
		return
	arya_fail_dashboard.free()

	var batch_dashboard: Node = flow_script.new()
	root.add_child(batch_dashboard)
	await process_frame
	batch_dashboard.set("store", test_store)
	batch_dashboard.set("selected_branch_id", "__codex_auto_sms_batch")
	batch_dashboard.set("selected_branch_grupo_rs_mode", "modern")
	var batch_rows := _make_batch_rows(15, "024900")
	batch_dashboard.set("test_grupo_rs_maintenance_rows", batch_rows)
	await batch_dashboard.call("_run_auto_reset_monitor", "teste lote completo")
	if int(batch_dashboard.get("test_grupo_rs_send_calls")) != 15:
		push_error("Fila Grupo RS deveria enviar todos os 15 itens no mesmo ciclo, nao apenas 12. Enviados: %d" % int(batch_dashboard.get("test_grupo_rs_send_calls")))
		batch_dashboard.queue_free()
		_cleanup(dashboard)
		quit(1)
		return
	var batch_rechecks: Dictionary = batch_dashboard.get("auto_reset_due_rechecks")
	if batch_rechecks.size() != 15:
		push_error("Todos os SMS enviados em lote deveriam ter recheck agendado: %d" % batch_rechecks.size())
		batch_dashboard.queue_free()
		_cleanup(dashboard)
		quit(1)
		return
	var min_due := int(Time.get_unix_time_from_system()) + 86300
	for row in batch_rows:
		var batch_serial := str(row.get("serial", ""))
		var recheck: Dictionary = batch_rechecks.get(batch_serial, {})
		if recheck.is_empty() or int(recheck.get("due_at", 0)) < min_due or not bool(recheck.get("batch_recheck", false)):
			push_error("Recheck em lote nao foi remarcado para depois do fim da fila: %s -> %s" % [batch_serial, str(recheck)])
			batch_dashboard.queue_free()
			_cleanup(dashboard)
			quit(1)
			return
	await batch_dashboard.call("_run_auto_reset_monitor", "teste standby")
	if int(batch_dashboard.get("test_grupo_rs_send_calls")) != 15:
		push_error("Monitor enviou novos SMS durante o standby de 24 horas.")
		batch_dashboard.queue_free()
		_cleanup(dashboard)
		quit(1)
		return
	batch_dashboard.queue_free()
	await process_frame

	var batch_fail_dashboard: Node = flow_script.new()
	root.add_child(batch_fail_dashboard)
	await process_frame
	batch_fail_dashboard.set("store", test_store)
	batch_fail_dashboard.set("selected_branch_id", "__codex_auto_sms_batch_fail")
	batch_fail_dashboard.set("selected_branch_grupo_rs_mode", "modern")
	batch_fail_dashboard.set("test_grupo_rs_send_ok", false)
	batch_fail_dashboard.set("test_grupo_rs_maintenance_rows", _make_batch_rows(6, "024901"))
	await batch_fail_dashboard.call("_run_auto_reset_monitor", "teste trava falhas")
	if int(batch_fail_dashboard.get("test_grupo_rs_send_calls")) != 3:
		push_error("Trava de falhas deveria pausar apos 3 erros consecutivos. Tentativas: %d" % int(batch_fail_dashboard.get("test_grupo_rs_send_calls")))
		batch_fail_dashboard.queue_free()
		_cleanup(dashboard)
		quit(1)
		return
	if not bool(batch_fail_dashboard.call("_auto_reset_can_send", "024901000")):
		push_error("Falha em lote nao pode registrar SMS como enviado.")
		batch_fail_dashboard.queue_free()
		_cleanup(dashboard)
		quit(1)
		return
	var batch_fail_rechecks: Dictionary = batch_fail_dashboard.get("auto_reset_due_rechecks")
	if not batch_fail_rechecks.is_empty():
		push_error("Falha em lote nao pode agendar rechecks.")
		batch_fail_dashboard.queue_free()
		_cleanup(dashboard)
		quit(1)
		return
	batch_fail_dashboard.queue_free()
	await process_frame

	_cleanup(dashboard)
	print("AUTO_SMS_MONITOR_CHECK_OK")
	quit(0)


func _find_row(rows: Array, serial: String) -> Dictionary:
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var item := row as Dictionary
		if str(item.get("serial", "")) == serial:
			return item
	return {}


func _make_batch_rows(count: int, prefix: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index in range(count):
		var serial := "%s%03d" % [prefix, index]
		rows.append({
			"sku": serial,
			"imei": serial,
			"equipment_number": serial,
			"serial": serial,
			"plate": "LOT - %04d" % index,
			"client": "CLIENTE LOTE %02d" % index,
			"apn": "hinova" if index % 2 == 0 else "linksolutions",
			"chip_phone": "(99) 98888-%04d" % index,
			"phone": "(99) 98888-%04d" % index,
			"updated_at": "17/07/2026 07:%02d:00" % index,
			"monitor_interval": "24 - 72 Horas",
			"sms_queue_source": "grupo_rs_manual",
			"tracker_status": "Instalado",
			"status": "Instalado",
			"monitor_source": "grupo_rs",
		})
	return rows


func _cleanup(dashboard: Node) -> void:
	var settings: Dictionary = dashboard.call("_read_json_dictionary", "user://app_settings.json")
	var raw_states: Variant = settings.get("auto_reset_monitor_state_by_branch", {})
	if typeof(raw_states) == TYPE_DICTIONARY:
		var states := raw_states as Dictionary
		states.erase("__codex_auto_sms")
		states.erase("__codex_auto_sms_flow")
		states.erase("__codex_auto_sms_fail")
		states.erase("__codex_auto_sms_batch")
		states.erase("__codex_auto_sms_batch_fail")
		states.erase("__codex_auto_sms_arya_fail")
		settings["auto_reset_monitor_state_by_branch"] = states
		dashboard.call("_write_json_dictionary", "user://app_settings.json", settings)

	var db_path := ProjectSettings.globalize_path("user://__codex_auto_sms_inventory.json")
	var backup_path := ProjectSettings.globalize_path("user://__codex_auto_sms_inventory.json.bak")
	var temp_path := ProjectSettings.globalize_path("user://__codex_auto_sms_inventory.json.tmp")
	DirAccess.remove_absolute(db_path)
	DirAccess.remove_absolute(backup_path)
	DirAccess.remove_absolute(temp_path)
	dashboard.free()


func _grupo_rs_datetime(unix_time: int) -> String:
	var value := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%02d/%02d/%04d %02d:%02d:%02d" % [
		int(value.get("day", 0)),
		int(value.get("month", 0)),
		int(value.get("year", 0)),
		int(value.get("hour", 0)),
		int(value.get("minute", 0)),
		int(value.get("second", 0)),
	]
