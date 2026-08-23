extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store_script := load("res://src/inventory_store.gd")
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		_fail("Dashboard nao compilou.")
		return
	if store_script == null or dashboard_script == null:
		_fail("Dependencias do teste de log nao carregaram.")
		return

	var store: InventoryStore = store_script.new()
	store.configure("user://__codex_system_log_inventory.json", "__codex_system_log_inventory.json", "user://__codex_system_log_backups", false)
	store.load_db()
	store.mark_remote_available()
	for index in range(1005):
		store.add_system_log("Teste log", "evento %04d" % index)

	var stored_logs := store.get_system_logs(0)
	if stored_logs.size() != 995:
		_fail("A poda em lotes de 10 nao manteve a janela esperada: %d" % stored_logs.size())
		return
	if str(stored_logs[stored_logs.size() - 1].get("details", "")) != "evento 0010" or str(stored_logs[0].get("details", "")) != "evento 1004":
		_fail("A poda nao removeu somente os 10 registros mais antigos.")
		return

	var dashboard: Node = dashboard_script.new()
	var sample_logs: Array[Dictionary] = []
	for index in range(350):
		sample_logs.append({
			"timestamp": "2026-07-20T10:%02d:%02d" % [int(index / 60), index % 60],
			"action": "Evento",
			"details": str(index),
			"sku": "",
		})
	var filtered: Array = dashboard.call("_filter_logs_by_date", sample_logs, "2026-07-20", 0)
	if filtered.size() != 350:
		dashboard.free()
		_fail("Filtro da tela ainda limitou os registros do dia: %d" % filtered.size())
		return

	var typed_filtered: Array[Dictionary] = []
	for entry in filtered:
		typed_filtered.append(entry as Dictionary)
	var first_page: Dictionary = dashboard.call("_system_log_page_data", typed_filtered, 0)
	if int(first_page.get("page_count", 0)) != 18 or int(first_page.get("total", 0)) != 350 or (first_page.get("entries", []) as Array).size() != 20:
		dashboard.free()
		_fail("Primeira pagina do log ficou incorreta: %s" % str(first_page))
		return
	var last_page: Dictionary = dashboard.call("_system_log_page_data", typed_filtered, 999)
	if int(last_page.get("page", -1)) != 17 or (last_page.get("entries", []) as Array).size() != 10:
		dashboard.free()
		_fail("Ultima pagina do log nao foi limitada corretamente: %s" % str(last_page))
		return

	dashboard.set("store", store)
	var persisted_timestamp := str(stored_logs[0].get("timestamp", ""))
	var persisted_date := persisted_timestamp.replace("T", " ").split(" ")[0]
	dashboard.set("system_log_selected_date", "%s 00:00" % persisted_date)
	dashboard.set("system_log_end_date", "%s 23:59" % persisted_date)
	dashboard.set("system_log_current_page", 0)
	var log_view: Control = dashboard.call("_build_system_log_view")
	var rendered_rows := _count_system_log_rows(log_view)
	if rendered_rows != 5:
		log_view.free()
		dashboard.free()
		_fail("Tela do log nao respeitou a lista compacta de 5 linhas na primeira pagina: %d." % rendered_rows)
		return
	if not _has_label_fragment(log_view, "Mostrando 1-5 de 995 registros"):
		log_view.free()
		dashboard.free()
		_fail("Resumo da paginacao nao apareceu na tela.")
		return
	var initial_view_id := log_view.get_instance_id()
	var initial_detail := dashboard.get("system_log_detail_panel") as Control
	var initial_detail_id := initial_detail.get_instance_id() if initial_detail != null else -1
	var selection_id := str(dashboard.call("_system_log_entry_id", stored_logs[1]))
	var visible_logs: Array = dashboard.call("_filter_system_log_records", store.get_system_logs(0))
	var found_entry: Dictionary = dashboard.call("_find_system_log_entry", visible_logs, selection_id)
	dashboard.call("_select_system_log_entry", selection_id)
	var refreshed_detail := dashboard.get("system_log_detail_panel") as Control
	var detail_replaced_when_available := initial_detail == null or (refreshed_detail != null and refreshed_detail.get_instance_id() != initial_detail_id)
	if log_view.get_instance_id() != initial_view_id or not detail_replaced_when_available or _count_system_log_rows(log_view) != 5:
		log_view.free()
		dashboard.free()
		_fail("Selecao do evento recriou a tela inteira ou alterou a pagina de eventos.")
		return
	log_view.free()
	dashboard.free()

	_cleanup()
	print("SYSTEM_LOG_CHECK_OK")
	quit(0)


func _cleanup() -> void:
	for path in [
		"user://__codex_system_log_inventory.json",
		"user://__codex_system_log_inventory.json.tmp",
		"user://__codex_system_log_inventory.json.bak",
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail(message: String) -> void:
	push_error(message)
	_cleanup()
	quit(1)


func _count_labels_with_prefix(node: Node, prefix: String) -> int:
	var count := 0
	if node is Label and str((node as Label).text).begins_with(prefix):
		count += 1
	for child in node.get_children():
		count += _count_labels_with_prefix(child, prefix)
	return count


func _count_system_log_rows(node: Node) -> int:
	var count := 1 if node is Button and (node as Button).has_meta("system_log_event_row") else 0
	for child in node.get_children():
		count += _count_system_log_rows(child)
	return count


func _has_label_fragment(node: Node, fragment: String) -> bool:
	if node is Label and str((node as Label).text).contains(fragment):
		return true
	for child in node.get_children():
		if _has_label_fragment(child, fragment):
			return true
	return false
