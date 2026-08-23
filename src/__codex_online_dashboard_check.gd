extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var firebase_config := root.get_node_or_null("FirebaseSync")
	var vault := root.get_node_or_null("SecretVault")
	if firebase_config != null and vault != null:
		firebase_config.call("configure_account", {
			"database_url": "https://grupo-rs-central-165dc-default-rtdb.firebaseio.com",
			"api_key": str(vault.call("get_secret", "firebase", "api_key", "")),
			"refresh_token": str(vault.call("get_secret", "firebase", "refresh_token", "")),
		})
	var scene := load("res://scenes/estoque_profissional.tscn")
	var dashboard: Node = scene.instantiate()
	root.add_child(dashboard)
	await create_timer(3.6).timeout

	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_name", "Imperatriz")
	dashboard.set("selected_branch_db_path", "user://inventory_db.json")
	dashboard.set("selected_branch_backup_name", "inventory_db.json")
	dashboard.set("selected_branch_backup_dir", "user://backups")
	dashboard.call("_open_selected_branch")

	var deadline := Time.get_ticks_msec() + 35000
	while Time.get_ticks_msec() < deadline and not bool(dashboard.get("online_data_available")):
		await create_timer(0.1).timeout

	_check(bool(dashboard.get("online_data_available")), "Dashboard nao liberou a base online.")
	var store: Variant = dashboard.get("store")
	_check(store != null and store.is_remote_available(), "Store do dashboard nao ficou online.")
	_check(store != null and not store.get_products().is_empty(), "Dashboard abriu sem os cadastros remotos.")
	_check(bool(dashboard.get("online_services_initialized")), "Servicos automaticos nao iniciaram depois do Firebase.")
	var firebase := root.get_node_or_null("FirebaseSync")
	var firebase_status: Dictionary = firebase.call("get_status") if firebase != null else {}
	_check(bool(firebase_status.get("data_available", false)), "Topbar nao confirmou acesso aos dados.")
	_check(not _has_text(dashboard, "Sem internet"), "Tela offline permaneceu depois da reconexao.")
	_check(not _has_text(dashboard, "Backup"), "Backup local ainda apareceu na navegacao.")
	_check(not _has_text(dashboard, "Restaurar"), "Restauracao local ainda apareceu na navegacao.")
	_check(not _has_text(dashboard, "Comunicacao dos veiculos"), "Painel removido de comunicacao ainda aparece no dashboard.")
	_check(_has_text(dashboard, "Aparelhos por operadora"), "Grafico de operadoras nao apareceu no dashboard.")
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
		print("ONLINE_DASHBOARD_CHECK_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
