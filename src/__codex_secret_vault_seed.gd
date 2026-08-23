extends SceneTree

const SecretVaultScript := preload("res://src/security/secret_vault.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var raw_json := OS.get_environment("GRUPO_RS_CREDENTIALS_JSON")
	var setup_password := OS.get_environment("GRUPO_RS_VAULT_SETUP_PASSWORD")
	if raw_json.strip_edges() == "" or setup_password.length() < SecretVaultScript.TRANSFER_MIN_PASSWORD_LENGTH:
		_fail("Dados de inicializacao ausentes.")
		return
	var parsed: Variant = JSON.parse_string(raw_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("JSON de credenciais invalido.")
		return
	var vault := root.get_node_or_null("SecretVault")
	if vault == null:
		_fail("Autoload SecretVault ausente.")
		return
	var access: Dictionary
	if bool(vault.call("has_unlock_password")):
		access = vault.call("unlock_view", setup_password)
	else:
		access = vault.call("initialize_unlock_password", setup_password)
	if not bool(access.get("ok", false)):
		_fail("Nao foi possivel preparar o cofre: %s" % str(access.get("message", "")))
		return
	var source := parsed as Dictionary
	var namespaces := {
		"app": SecretVaultScript.APP_SECRET_KEYS,
		"firebase": SecretVaultScript.FIREBASE_SECRET_KEYS,
		"luna": SecretVaultScript.LUNA_SECRET_KEYS,
	}
	var imported := 0
	for namespace_key in namespaces:
		var values: Variant = source.get(namespace_key, {})
		if typeof(values) != TYPE_DICTIONARY:
			continue
		for key in namespaces[namespace_key]:
			var value: Variant = (values as Dictionary).get(key, "")
			if str(value).strip_edges() == "":
				if (values as Dictionary).has(key) and not bool(vault.call("remove_secret", namespace_key, key)):
					_fail("Falha ao limpar uma credencial anterior do cofre.")
					return
				continue
			if not bool(vault.call("set_secret", namespace_key, key, value)):
				_fail("Falha ao gravar uma credencial no cofre.")
				return
			imported += 1
	var bundle_path := OS.get_environment("GRUPO_RS_TRANSFER_BUNDLE_PATH").strip_edges()
	if bundle_path != "":
		var transfer_password := OS.get_environment("GRUPO_RS_TRANSFER_PASSWORD")
		var exported: Dictionary = vault.call("export_transfer_bundle", bundle_path, transfer_password)
		if not bool(exported.get("ok", false)):
			_fail("Falha ao exportar o pacote portatil: %s" % str(exported.get("message", "")))
			return
	var distribution_path := OS.get_environment("GRUPO_RS_DISTRIBUTION_VAULT_PATH").strip_edges()
	if distribution_path != "" and not bool(vault.call("copy_vault_to", distribution_path)):
		_fail("Falha ao copiar o cofre para a distribuicao.")
	print("SECRET_VAULT_SEED_OK imported=%d" % imported)
	vault.call("lock_view")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
