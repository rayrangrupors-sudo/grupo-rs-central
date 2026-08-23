extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("ONLINE_ONLY_UI_START")
	var scene := load("res://scenes/estoque_profissional.tscn")
	var dashboard: Node = scene.instantiate()
	root.add_child(dashboard)
	await create_timer(3.6).timeout
	print("ONLINE_ONLY_UI_OPEN")

	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_name", "Imperatriz")
	dashboard.set("selected_branch_db_path", "user://__codex_online_ui.json")
	dashboard.set("selected_branch_backup_name", "__codex_online_ui.json")
	dashboard.set("selected_branch_backup_dir", "user://__codex_online_ui_backups")
	dashboard.call("_open_selected_branch")
	await create_timer(0.8).timeout
	# O teste visual precisa ser deterministico: a credencial real pode estar
	# online durante a execucao. Simulamos somente a transicao de estado que
	# ocorre quando a sonda ativa detecta a queda, sem tocar no Firebase.
	dashboard.set("online_data_available", false)
	dashboard.call("_on_firebase_status_changed", {
		"state": "offline",
		"message": "Teste controlado: sem internet.",
		"data_available": false,
		"read_ok": false,
		"write_ok": false,
		"pending": false,
		"pending_count": 0,
		"latency_ms": -1,
		"last_sync_at": "",
	})
	# A montagem do painel de saude agenda uma leitura inicial; chamamos a
	# mesma tela de bloqueio explicitamente para isolar a assercao visual.
	dashboard.set("current_content_allows_offline", false)
	dashboard.call("_show_online_unavailable_view", "offline", "Teste controlado: sem internet.")
	await process_frame
	print("ONLINE_ONLY_UI_ASSERT")

	_check(
		_has_text(dashboard, "Dados online indisponiveis") or _has_text(dashboard, "Sem internet"),
		"Tela de bloqueio online nao apareceu."
	)
	_check(_has_text(dashboard, "Configurar servidor"), "Acao de configuracao nao apareceu na queda.")
	_check(not _has_text(dashboard, "Backup"), "Botao Backup ainda esta visivel.")
	_check(not _has_text(dashboard, "Restaurar"), "Botao Restaurar ainda esta visivel.")
	_check(
		_has_text(dashboard, "Sem dados")
			or _has_text(dashboard, "Sem internet")
			or _has_text(dashboard, "Aguardando")
			or _has_text(dashboard, "Conectando")
			or _has_text(dashboard, "Sincronizando")
			or _has_text(dashboard, "Atencao"),
		"Topbar nao mostrou o estado de indisponibilidade do Firebase."
	)

	dashboard.call("_show_firebase_config")
	await process_frame
	_check(_has_text(dashboard, "Configuracoes"), "Configuracoes nao abriu sem internet.")
	_check(_has_text(dashboard, "Firebase"), "Secao Firebase nao esta acessivel sem internet.")

	print("ONLINE_ONLY_UI_FINISH")
	_finish()


func _has_text(node: Node, wanted: String) -> bool:
	if node is Label and wanted.to_lower() in (node as Label).text.to_lower():
		return true
	if node is Button and wanted.to_lower() in (node as Button).text.to_lower():
		return true
	for child in node.get_children():
		if _has_text(child, wanted):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("ONLINE_ONLY_UI_CHECK_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
