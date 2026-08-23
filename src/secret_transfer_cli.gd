extends SceneTree

const SecretVaultScript := preload("res://src/security/secret_vault.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var vault := root.get_node_or_null("SecretVault")
	if vault == null:
		_finish("SECRET_TRANSFER_CLI_ERROR vault_unavailable")
		return

	var mode := OS.get_environment("GRUPO_RS_TRANSFER_MODE").strip_edges().to_lower()
	var bundle_path := OS.get_environment("GRUPO_RS_TRANSFER_BUNDLE_PATH").strip_edges()
	var transfer_password := OS.get_environment("GRUPO_RS_TRANSFER_PASSWORD")
	var vault_password := OS.get_environment("GRUPO_RS_VAULT_PASSWORD")
	if vault_password == "":
		vault_password = transfer_password
	if mode not in ["import", "export"]:
		_finish("SECRET_TRANSFER_CLI_ERROR invalid_mode")
		return
	if bundle_path == "" or transfer_password.length() < SecretVaultScript.TRANSFER_MIN_PASSWORD_LENGTH:
		_finish("SECRET_TRANSFER_CLI_ERROR missing_bundle_or_password")
		return

	if mode == "export":
		if vault_password.length() < SecretVaultScript.TRANSFER_MIN_PASSWORD_LENGTH:
			_finish("SECRET_TRANSFER_CLI_ERROR missing_vault_password")
			return
		var access: Dictionary = vault.call("unlock_view", vault_password)
		if not bool(access.get("ok", false)):
			_finish("SECRET_TRANSFER_CLI_ERROR vault_unlock_failed")
			return
		var exported: Dictionary = vault.call("export_transfer_bundle", bundle_path, transfer_password)
		vault.call("lock_view")
		if not bool(exported.get("ok", false)):
			_finish("SECRET_TRANSFER_CLI_ERROR export_failed")
			return
		print("SECRET_TRANSFER_CLI_OK mode=export count=%d" % int(exported.get("secret_count", 0)))
		quit(0)
		return

	var imported: Dictionary = vault.call("import_transfer_bundle", bundle_path, transfer_password)
	if not bool(imported.get("ok", false)):
		_finish("SECRET_TRANSFER_CLI_ERROR import_failed")
		return
	if not bool(vault.call("has_unlock_password")):
		if vault_password.length() < SecretVaultScript.TRANSFER_MIN_PASSWORD_LENGTH:
			_finish("SECRET_TRANSFER_CLI_ERROR missing_vault_password")
			return
		var initialized: Dictionary = vault.call("initialize_unlock_password", vault_password)
		if not bool(initialized.get("ok", false)):
			_finish("SECRET_TRANSFER_CLI_ERROR vault_setup_failed")
			return
	print("SECRET_TRANSFER_CLI_OK mode=import count=%d" % int(imported.get("secret_count", 0)))
	quit(0)


func _finish(message: String) -> void:
	push_error(message)
	quit(1)
