extends SceneTree

const SecretVaultScript := preload("res://src/security/secret_vault.gd")
const DashboardScript := preload("res://src/inventory_dashboard.gd")
const DashboardStubScript := preload("res://src/__codex_secret_vault_dashboard_stub.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var vault := root.get_node_or_null("SecretVault")
	if vault == null:
		_fail("Autoload SecretVault ausente.")
		return
	var status: Dictionary = vault.call("status")
	if not bool(status.get("ok", false)):
		_fail("Cofre nao abriu: %s | %s" % [
			str(status.get("error", "")),
			str(status.get("path", "")),
		])
		return
	var expected := [
		["app", "arya_email"],
		["app", "arya_password"],
		["app", "grupo_rs_modern_user"],
		["app", "grupo_rs_modern_password"],
		["app", "linksolutions_email"],
		["app", "linksolutions_password"],
		["firebase", "api_key"],
		["firebase", "refresh_token"],
	]
	for entry in expected:
		if not bool(vault.call("has_secret", str(entry[0]), str(entry[1]))):
			_fail("Credencial esperada ausente: %s/%s | total=%d | %s" % [
				str(entry[0]),
				str(entry[1]),
				int(status.get("secret_count", 0)),
				str(status.get("path", "")),
			])
			return
	var configured_app: Array[String] = []
	for key in SecretVaultScript.APP_SECRET_KEYS:
		if bool(vault.call("has_secret", "app", str(key))):
			configured_app.append(str(key))
	var dashboard := DashboardStubScript.new()
	root.add_child(dashboard)
	var arya: Dictionary = dashboard.call("_arya_credentials")
	var modern: Dictionary = dashboard.call("_modern_grupo_rs_credentials")
	var link: Dictionary = dashboard.call("_linksolutions_credentials")
	if str(arya.get("email", "")).strip_edges() == "" or str(arya.get("password", "")) == "":
		_fail("Dashboard nao recebeu Arya do cofre.")
		return
	if str(modern.get("username", "")).strip_edges() == "" or str(modern.get("password", "")) == "":
		_fail("Dashboard nao recebeu Grupo RS do cofre.")
		return
	if str(link.get("username", "")).strip_edges() == "" or str(link.get("password", "")) == "":
		_fail("Dashboard nao recebeu Link Solutions do cofre.")
		return
	var live_dashboard := DashboardScript.new()
	root.add_child(live_dashboard)
	await process_frame
	var live_arya: Dictionary = live_dashboard.call("_arya_credentials")
	if str(live_arya.get("email", "")).strip_edges() == "" \
			or str(live_arya.get("password", "")) == "":
		_fail("Dashboard em execucao nao recebeu Arya do cofre.")
		return
	var firebase: Node = live_dashboard.call("_firebase_sync")
	if firebase == null \
			or not firebase.has_method("uses_encrypted_secret_vault") \
			or not bool(firebase.call("uses_encrypted_secret_vault")):
		_fail("Firebase antigo nao foi atualizado para o cofre.")
		return
	var firebase_summary: Dictionary = firebase.call("get_configuration_summary")
	if not bool(firebase_summary.get("configured", false)):
		_fail("Firebase nao recuperou a configuracao criptografada.")
		return
	var ai_manager: Node = live_dashboard.call("_ai_manager")
	if ai_manager == null \
			or not ai_manager.has_method("uses_encrypted_secret_vault") \
			or not bool(ai_manager.call("uses_encrypted_secret_vault")):
		_fail("AIManager antigo nao foi atualizado para o cofre.")
		return
	print("SECRET_VAULT_RUNTIME_CHECK_OK secrets=%d app_keys=%s" % [
		int(status.get("secret_count", 0)),
		",".join(configured_app),
	])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
