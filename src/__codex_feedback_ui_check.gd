extends SceneTree


func _initialize() -> void:
	var source_path := "res://src/inventory_dashboard.gd"
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		push_error("Nao foi possivel ler o dashboard para validar a aba de mensagens.")
		quit(1)
		return
	var source := file.get_as_text()
	var sidebar_start := source.find("func _build_sidebar()")
	var sidebar_end := source.find("func _make_sidebar_brand()")
	var topbar_start := source.find("func _build_topbar()")
	var topbar_end := source.find("func _make_user_widget()")
	var topbar_source := source.substr(topbar_start, topbar_end - topbar_start)

	if sidebar_start < 0 or sidebar_end <= sidebar_start:
		push_error("Estrutura da sidebar nao foi encontrada.")
		quit(1)
		return
	var sidebar_source := source.substr(sidebar_start, sidebar_end - sidebar_start)
	if not sidebar_source.contains('"Logs do sistema", "log", "logs"'):
		push_error("A aba Logs do sistema nao foi registrada na sidebar.")
		quit(1)
		return
	if topbar_start < 0 or topbar_end <= topbar_start:
		push_error("Estrutura da barra superior nao foi encontrada.")
		quit(1)
		return
	if topbar_source.contains("_make_auto_reset_status_widget()"):
		push_error("A animacao do monitor ainda esta sendo adicionada ao topo.")
		quit(1)
		return
	if not source.contains('title.text = "Logs do sistema"'):
		push_error("Titulo da central de logs nao foi atualizado.")
		quit(1)
		return
	if not source.contains("_log_system_action(title_text, feedback_details)"):
		push_error("Feedback remoto nao esta sendo registrado no historico.")
		quit(1)
		return

	print("FEEDBACK_UI_CHECK_OK")
	quit(0)
