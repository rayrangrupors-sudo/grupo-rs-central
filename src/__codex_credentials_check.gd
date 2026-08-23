extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var vault := root.get_node_or_null("SecretVault")
	if vault == null or not bool((vault.call("status") as Dictionary).get("ok", false)):
		push_error("Cofre criptografado indisponivel para o teste de integracoes.")
		quit(1)
		return
	var dashboard: Node = DashboardScript.new()
	root.add_child(dashboard)
	await process_frame

	var arya_credentials: Dictionary = dashboard.call("_arya_credentials")
	if str(arya_credentials.get("email", "")).strip_edges() == "" or str(arya_credentials.get("password", "")) == "":
		var merged_settings: Dictionary = dashboard.call("_read_json_dictionary", "user://app_settings.json")
		_fail(
			dashboard,
			"Credenciais da Arya nao foram encontradas nas configuracoes. vault_email=%s vault_password=%s merged_email=%s merged_password=%s" % [
				str(vault.call("has_secret", "app", "arya_email")),
				str(vault.call("has_secret", "app", "arya_password")),
				str(merged_settings.has("arya_email")),
				str(merged_settings.has("arya_password")),
			]
		)
		return

	var arya_token := str(dashboard.call("_arya_token")).strip_edges()
	if arya_token == "":
		var arya_login: Dictionary = await dashboard.call("_ensure_arya_token", true)
		if not bool(arya_login.get("ok", false)):
			_fail(dashboard, "Login/token da Arya nao foi confirmado: %s" % str(arya_login.get("message", "falha sem detalhe")))
			return

	var link_credentials: Dictionary = dashboard.call("_linksolutions_credentials")
	if str(link_credentials.get("username", "")).strip_edges() == "" or str(link_credentials.get("password", "")) == "":
		_fail(dashboard, "Credenciais da Link Solutions nao foram encontradas nas configuracoes.")
		return

	var legacy_credentials: Dictionary = dashboard.call("_legacy_grupo_rs_credentials")
	if str(legacy_credentials.get("username", "")).strip_edges() == "" or str(legacy_credentials.get("password", "")) == "":
		_fail(dashboard, "Credenciais do Grupo RS antigo nao foram resolvidas.")
		return
	var delete_url := str(dashboard.call("_legacy_grupo_rs_delete_base_url")).strip_edges()
	if not delete_url.contains("sis.sosrastrear.com.br"):
		_fail(dashboard, "URL de exclusao do sistema antigo nao foi resolvida corretamente.")
		return

	var link_token := str(dashboard.call("_linksolutions_token")).strip_edges()
	if link_token == "":
		var link_login: Dictionary = await dashboard.call("_request_linksolutions_login")
		if not bool(link_login.get("ok", false)):
			_fail(dashboard, "Login/token da Link Solutions nao foi confirmado: %s" % str(link_login.get("message", "falha sem detalhe")))
			return

	var settings: Dictionary = dashboard.call("_read_json_dictionary", "user://app_settings.json")
	if str(settings.get("arya_password", "")) == "" or str(settings.get("linksolutions_password", "")) == "":
		_fail(dashboard, "Senhas nao ficaram persistidas no app_settings.json.")
		return

	dashboard.queue_free()
	await process_frame
	_cleanup()
	print("CREDENTIALS_CHECK_OK")
	quit(0)


func _cleanup() -> void:
	for path in [
		"user://__codex_credentials_inventory.json",
		"user://__codex_credentials_inventory.json.bak",
		"user://__codex_credentials_inventory.json.tmp",
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail(dashboard: Node, message: String) -> void:
	if is_instance_valid(dashboard):
		dashboard.queue_free()
	_cleanup()
	push_error(message)
	quit(1)
