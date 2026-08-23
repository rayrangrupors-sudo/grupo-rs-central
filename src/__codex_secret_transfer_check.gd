extends SceneTree

const SecretVaultScript := preload("res://src/security/secret_vault.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var vault := root.get_node_or_null("SecretVault")
	if vault == null:
		_fail("Autoload SecretVault ausente.")
		return
	var vault_password := OS.get_environment("GRUPO_RS_VAULT_SETUP_PASSWORD")
	var transfer_password := OS.get_environment("GRUPO_RS_TRANSFER_PASSWORD")
	if vault_password.length() < SecretVaultScript.TRANSFER_MIN_PASSWORD_LENGTH \
			or transfer_password.length() < SecretVaultScript.TRANSFER_MIN_PASSWORD_LENGTH:
		_fail("Senhas de teste ausentes.")
		return
	var mode := OS.get_environment("GRUPO_RS_SECRET_TRANSFER_MODE").strip_edges().to_lower()
	if mode == "export":
		var access: Dictionary = vault.call("unlock_view", vault_password)
		if not bool(access.get("ok", false)):
			_fail("Cofre de origem nao desbloqueou.")
			return
		var bundle_path := OS.get_environment("GRUPO_RS_TRANSFER_BUNDLE_PATH")
		var exported: Dictionary = vault.call("export_transfer_bundle", bundle_path, transfer_password)
		if not bool(exported.get("ok", false)):
			_fail("Exportacao portatil falhou: %s" % str(exported.get("message", "")))
			return
		print("SECRET_TRANSFER_EXPORT_OK count=%d" % int(exported.get("secret_count", 0)))
		vault.call("lock_view")
		quit(0)
		return
	if mode == "import":
		var imported: Dictionary = vault.call(
			"import_transfer_bundle",
			OS.get_environment("GRUPO_RS_TRANSFER_BUNDLE_PATH"),
			transfer_password
		)
		if not bool(imported.get("ok", false)):
			_fail("Importacao portatil falhou: %s" % str(imported.get("message", "")))
			return
		var expected := int(OS.get_environment("GRUPO_RS_EXPECTED_SECRET_COUNT"))
		var status: Dictionary = vault.call("status")
		if expected > 0 and int(status.get("secret_count", 0)) < expected:
			_fail("Importacao portatil nao preservou a quantidade esperada.")
			return
		if not bool(vault.call("has_unlock_password")):
			var initialized: Dictionary = vault.call("initialize_unlock_password", vault_password)
			if not bool(initialized.get("ok", false)):
				_fail("Nao foi possivel proteger o cofre de destino com senha.")
				return
		for entry in [
			["app", "arya_email"],
			["app", "grupo_rs_api_user"],
			["app", "linksolutions_email"],
			["firebase", "account_email"],
			["firebase", "refresh_token"],
			["luna", "gemini_api_key"],
		]:
			if not bool(vault.call("has_secret", str(entry[0]), str(entry[1]))):
				_fail("Importacao portatil perdeu uma credencial esperada.")
				return
		print("SECRET_TRANSFER_IMPORT_OK count=%d" % int(status.get("secret_count", 0)))
		quit(0)
		return
	_fail("Modo de transferencia invalido.")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
