extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


class ExpertTextingStub:
	extends "res://src/inventory_dashboard.gd"

	var fake_settings := {
		"experttexting_username": "conta-teste",
		"experttexting_api_key": "api-key-teste",
		"experttexting_api_secret": "api-secret-teste",
		"experttexting_sender": "DEFAULT",
		"experttexting_enabled": true,
		"experttexting_inbox_enabled": true,
		"experttexting_daily_limit_usd": 10.0,
		"experttexting_monthly_limit_usd": 100.0,
		"experttexting_minimum_balance_usd": 0.0,
	}
	var post_calls := 0
	var get_calls := 0
	var last_post_fields: Dictionary = {}
	var logged_actions: Array[Dictionary] = []


	func _read_json_dictionary(_path: String) -> Dictionary:
		return fake_settings.duplicate(true)


	func _write_json_dictionary(_path: String, value: Dictionary) -> bool:
		fake_settings = value.duplicate(true)
		return true


	func _http_post_form_with_headers(_url: String, fields: Dictionary, _headers: PackedStringArray, _max_redirects: int = 8) -> Dictionary:
		post_calls += 1
		last_post_fields = fields.duplicate(true)
		return {
			"ok": true,
			"body": JSON.stringify({
				"Response": {"message_id": "671729375", "message_count": 1, "price": 0.023},
				"ErrorMessage": "",
				"Status": 0,
			}),
		}


	func _http_get_text_with_headers(url: String, _headers: PackedStringArray, _timeout_seconds: float = 15.0) -> Dictionary:
		get_calls += 1
		if url.contains("Account/Balance"):
			return {"ok": true, "body": JSON.stringify({"Response": {"Balance": 12.50}, "ErrorMessage": "", "Status": 0})}
		if url.contains("Message/Status"):
			return {"ok": true, "body": JSON.stringify({"Response": {"Status": "SENT"}, "ErrorMessage": "", "Status": 0})}
		if url.contains("Message/UnreadInbox"):
			return {
				"ok": true,
				"body": JSON.stringify({
					"Response": [{"Sender": "5562998627283", "Text": "ST300 ACK", "Date": "2026-07-22T12:00:00"}],
					"ErrorMessage": "",
					"Status": 0,
				}),
			}
		return {"ok": false, "message": "Endpoint simulado desconhecido."}


	func _log_system_action(action: String, details: String = "", sku: String = "") -> void:
		logged_actions.append({"action": action, "details": details, "sku": sku})


	func _refresh_auto_reset_dashboard_if_visible() -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := ExpertTextingStub.new()
	root.add_child(dashboard)
	dashboard.call("_setup_experttexting_poll")
	_expect(dashboard.experttexting_poll_timer != null and is_instance_valid(dashboard.experttexting_poll_timer), "Timer automatico do ExpertTexting nao foi criado.")
	_expect(not dashboard.experttexting_poll_timer.is_stopped(), "Timer automatico do ExpertTexting nao foi iniciado.")
	dashboard.experttexting_poll_timer.stop()

	_expect(dashboard.call("_experttexting_is_configured"), "Credenciais simuladas nao foram reconhecidas.")
	_expect(str(dashboard.call("_experttexting_e164_number", "(62) 99862-7283")) == "5562998627283", "Telefone brasileiro nao foi convertido para E164.")
	_expect(str(dashboard.call("_experttexting_e164_number", "+55 62 99862-7283")) == "5562998627283", "Telefone com DDI foi alterado incorretamente.")

	var balance: Dictionary = await dashboard.call("_experttexting_refresh_balance", false)
	_expect(bool(balance.get("ok", false)), "Consulta simulada de saldo falhou: %s" % str(balance))
	_expect(absf(float(balance.get("balance", 0.0)) - 12.50) < 0.001, "Saldo retornado esta incorreto.")

	var sent: Dictionary = await dashboard.call("_experttexting_send_sms", "(62) 99862-7283", "COMANDO TESTE")
	_expect(bool(sent.get("ok", false)), "Envio simulado falhou: %s" % str(sent))
	_expect(str(sent.get("message_id", "")) == "671729375", "message_id nao foi preservado.")
	_expect(absf(float(sent.get("price", 0.0)) - 0.023) < 0.0001, "Custo real do provedor nao foi registrado.")
	_expect(str(dashboard.last_post_fields.get("to", "")) == "5562998627283", "Envio nao usou telefone E164.")
	_expect(not dashboard.last_post_fields.has("password"), "Payload incluiu campo de senha indevido.")

	dashboard.call("_auto_reset_register_attempt", "024376142", sent)
	var status_result: Dictionary = await dashboard.call("_experttexting_poll_pending_statuses")
	_expect(bool(status_result.get("ok", false)), "Consulta simulada de status falhou.")
	var attempt: Dictionary = dashboard.auto_reset_attempts.get("024376142", {})
	_expect(str(attempt.get("provider_status", "")) == "SENT", "Status SENT nao foi persistido.")

	var inbox_result: Dictionary = await dashboard.call("_experttexting_pull_inbox")
	_expect(bool(inbox_result.get("ok", false)) and int(inbox_result.get("added", 0)) == 1, "SMS recebido nao foi importado.")
	_expect(dashboard.experttexting_inbox_events.size() == 1, "Historico local da caixa de entrada nao foi atualizado.")
	attempt = dashboard.auto_reset_attempts.get("024376142", {})
	_expect(str(attempt.get("provider_status", "")) == "REPLIED", "Resposta nao foi relacionada ao aparelho pelo telefone.")
	var duplicate_result: Dictionary = await dashboard.call("_experttexting_pull_inbox")
	_expect(int(duplicate_result.get("added", -1)) == 0, "Mensagem recebida foi duplicada.")

	dashboard.fake_settings["experttexting_minimum_balance_usd"] = 20.0
	dashboard.experttexting_last_balance = 12.50
	dashboard.experttexting_last_balance_at = int(Time.get_unix_time_from_system())
	var blocked: Dictionary = await dashboard.call("_experttexting_budget_guard")
	_expect(not bool(blocked.get("ok", true)) and str(blocked.get("message", "")).contains("Saldo protegido"), "Trava de saldo minimo nao bloqueou o envio.")

	var usage: Dictionary = dashboard.call("_experttexting_usage_for_prefix", Time.get_date_string_from_system())
	_expect(int(usage.get("count", 0)) == 1 and absf(float(usage.get("cost", 0.0)) - 0.023) < 0.0001, "Ledger de custo ficou incorreto.")

	dashboard.auto_reset_view_section = "sms"
	var monitor_view: Control = dashboard.call("_build_auto_reset_dashboard_view")
	_expect(_has_text(monitor_view, "SMS / API") and _has_text(monitor_view, "SMS recebidos") and _has_text(monitor_view, "Entregas recentes"), "Pagina SMS/API do monitor nao montou os paineis esperados.")
	monitor_view.free()
	dashboard.config_selected_section = "sms"
	var config_view: Control = dashboard.call("_build_arya_config_view")
	_expect(
		config_view.find_child("VaultUnlockPassword", true, false) != null,
		"Configuracao ExpertTexting nao foi protegida pelo cofre."
	)
	config_view.free()

	print("EXPERTTEXTING_INTEGRATION_CHECK_OK")
	dashboard.queue_free()
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)


func _has_text(node: Node, value: String) -> bool:
	if node is Label and str((node as Label).text).contains(value):
		return true
	if node is Button and str((node as Button).text).contains(value):
		return true
	for child in node.get_children():
		if _has_text(child, value):
			return true
	return false
