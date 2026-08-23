extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := load("res://src/inventory_dashboard.gd")
	var store_script := load("res://src/inventory_store.gd")
	if dashboard_script == null or store_script == null:
		push_error("Dependencias do chat IA nao carregaram.")
		quit(1)
		return

	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set("assistant_codex_auto_send_disabled_for_tests", true)

	var test_store: InventoryStore = store_script.new()
	test_store.configure("user://__codex_assistant_chat_inventory.json", "__codex_assistant_chat_inventory.json", "user://__codex_assistant_chat_backups", false)
	test_store.load_db()
	test_store.upsert_product({
		"sku": "024123456",
		"imei": "024123456",
		"plate": "TST - 1234",
		"client": "CLIENTE IA",
		"model": "V7.3.5",
		"operator": "Claro",
		"tracker_status": "Instalado",
		"chip_phone": "(99) 99999-9999",
		"apn": "hinova",
	})
	test_store.add_maintenances([{
		"client": "CLIENTE IA",
		"plate": "TST - 1234",
		"serial": "024123456",
		"source_date": "18/07/2026 09:00:00",
		"note": "Teste IA",
	}])

	dashboard.set("store", test_store)
	dashboard.set("selected_branch_name", "IMPERATRIZ")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("auto_reset_last_summary", "Monitor: teste ativo")
	dashboard.set("internal_battery_cache", {
		"024123456": {
			"ok": true,
			"status": "ok",
			"percent": 88,
			"source_at": "18/07/2026 09:10:00",
			"checked_at": int(Time.get_unix_time_from_system()),
		}
	})
	dashboard.set("location_status_cache", {
		"024123456": {
			"label": "Ligado",
			"ignition": "Ligado",
			"updated_at": "18/07/2026 09:10:00",
		}
	})
	dashboard.set("arya_status_cache", {
		"024123456": {
			"status": "online",
			"message": "Teste online",
			"checked_at": int(Time.get_unix_time_from_system()),
		}
	})

	var product_answer := str(dashboard.call("_assistant_local_answer", "como esta o aparelho 024123456"))
	if not product_answer.contains("TST - 1234") or not product_answer.contains("88%") or not product_answer.contains("Manutencao"):
		_fail(dashboard, "Resposta do aparelho nao cruzou placa, Bat. Int e manutencao: %s" % product_answer)
		return

	var sms_answer := str(dashboard.call("_assistant_local_answer", "Monitor SMS"))
	if not sms_answer.contains("Monitor SMS automatico") or not sms_answer.contains("024"):
		_fail(dashboard, "Resumo do monitor SMS nao respondeu corretamente: %s" % sms_answer)
		return

	var operator_answer := str(dashboard.call("_assistant_local_answer", "quantos claro"))
	if not operator_answer.to_lower().contains("claro") or not operator_answer.contains("1"):
		_fail(dashboard, "Resumo de operadora nao contou a Claro: %s" % operator_answer)
		return

	var empty_escalation_answer := str(dashboard.call("_assistant_local_answer", "Escalar Codex"))
	if not empty_escalation_answer.contains("Nao encontrei falha"):
		_fail(dashboard, "Escalonamento vazio deveria pedir descricao do problema: %s" % empty_escalation_answer)
		return

	var unresolved: Array = dashboard.call("_assistant_unresolved_components", {
		"components": [
			{"id": "config_info", "status": "info", "message": "Configuracao opcional."},
			{"id": "real_error", "status": "error", "message": "Falha real."},
		]
	})
	if unresolved.size() != 1 or str((unresolved[0] as Dictionary).get("id", "")) != "real_error":
		_fail(dashboard, "Componentes informativos entraram como problema nao resolvido: %s" % str(unresolved))
		return

	var escalation: Dictionary = dashboard.call("_assistant_create_codex_escalation", "Teste automatizado", "Falha simulada para Codex", {
		"password": "senha-nao-pode-vazar",
		"token": "token-nao-pode-vazar",
		"visible": "contexto permitido",
	})
	if not bool(escalation.get("ok", false)):
		_fail(dashboard, "Chamado Codex nao foi criado: %s" % str(escalation))
		return
	var escalation_path := str(escalation.get("path", ""))
	var escalation_text_path := str(escalation.get("text_path", ""))
	if not FileAccess.file_exists(escalation_path) or not FileAccess.file_exists(escalation_text_path):
		_fail(dashboard, "Arquivos do chamado Codex nao foram gravados: %s" % str(escalation))
		return
	var file := FileAccess.open(escalation_path, FileAccess.READ)
	var report_text := file.get_as_text() if file != null else ""
	if report_text.contains("senha-nao-pode-vazar") or report_text.contains("token-nao-pode-vazar"):
		_fail(dashboard, "Chamado Codex vazou segredo no JSON.")
		return
	if not report_text.contains("contexto permitido") or not report_text.contains("[removido]"):
		_fail(dashboard, "Chamado Codex nao preservou contexto seguro ou nao mascarou segredo.")
		return
	if not report_text.contains("\"delivery\"") or not report_text.contains("pending_manual"):
		_fail(dashboard, "Chamado Codex nao registrou o status de envio automatico.")
		return
	var logged := false
	for log_entry in test_store.get_system_logs(0):
		if str(log_entry.get("action", "")) == "Chamado Codex criado":
			logged = true
			break
	if not logged:
		_fail(dashboard, "Chamado Codex nao entrou no log do sistema.")
		return
	DirAccess.remove_absolute(escalation_path)
	DirAccess.remove_absolute(escalation_text_path)

	dashboard.call("_guardian_audit_event", {
		"kind": "error",
		"component": "teste_codex",
		"title": "Falha simulada",
		"details": "A IA local nao conseguiu corrigir.",
	})
	var auto_escalation_path := str(dashboard.get("assistant_last_escalation_path"))
	if auto_escalation_path == "" or not FileAccess.file_exists(auto_escalation_path):
		_fail(dashboard, "Evento automatico do Assistente nao gerou chamado Codex.")
		return
	DirAccess.remove_absolute(auto_escalation_path)
	DirAccess.remove_absolute(auto_escalation_path.replace(".json", ".txt"))

	var panel: Control = dashboard.call("_build_assistant_chat_panel")
	if panel == null:
		_fail(dashboard, "Painel do chat IA nao foi criado.")
		return
	panel.free()

	dashboard.queue_free()
	await process_frame
	_cleanup()
	print("ASSISTANT_CHAT_CHECK_OK")
	quit(0)


func _cleanup() -> void:
	for path in [
		"user://__codex_assistant_chat_inventory.json",
		"user://__codex_assistant_chat_inventory.json.bak",
		"user://__codex_assistant_chat_inventory.json.tmp",
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail(dashboard: Node, message: String) -> void:
	if is_instance_valid(dashboard):
		dashboard.queue_free()
	_cleanup()
	push_error(message)
	quit(1)
