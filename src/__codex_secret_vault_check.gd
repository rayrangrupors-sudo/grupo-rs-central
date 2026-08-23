extends SceneTree

const SecretVaultScript := preload("res://src/security/secret_vault.gd")
const TEST_PASSWORD := "codex-vault-test-only"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var test_path := OS.get_environment("GRUPO_RS_VAULT_PATH").strip_edges()
	if test_path == "":
		_fail("Caminho isolado do teste nao foi informado.")
		return
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)
	var existing := root.get_node_or_null("SecretVault")
	if existing != null:
		root.remove_child(existing)
		existing.free()
	var vault := SecretVaultScript.new()
	vault.name = "SecretVault"
	root.add_child(vault)

	var initialized: Dictionary = vault.call("initialize_unlock_password", TEST_PASSWORD)
	if not bool(initialized.get("ok", false)):
		_fail("Inicializacao do cofre falhou.")
		return
	if not bool(vault.call("set_secret", "app", "sample_password", "never-plain-text")):
		_fail("Gravacao criptografada falhou.")
		return
	vault.call("lock_view")
	if bool(vault.call("is_view_unlocked")):
		_fail("Bloqueio de visualizacao falhou.")
		return
	if bool((vault.call("unlock_view", "wrong-password") as Dictionary).get("ok", false)):
		_fail("Senha incorreta foi aceita.")
		return
	if not bool((vault.call("unlock_view", TEST_PASSWORD) as Dictionary).get("ok", false)):
		_fail("Senha correta foi recusada.")
		return
	if str(vault.call("get_secret", "app", "sample_password", "")) != "never-plain-text":
		_fail("Leitura do segredo falhou.")
		return
	var raw := FileAccess.get_file_as_bytes(test_path)
	if _bytes_contains(raw, "never-plain-text".to_utf8_buffer()) \
			or _bytes_contains(raw, TEST_PASSWORD.to_utf8_buffer()):
		_fail("O arquivo do cofre contem texto sensivel legivel.")
		return
	var source := {
		"plain_setting": true,
		"arya_password": "migrated-value",
	}
	var clean: Dictionary = vault.call(
		"extract_secrets",
		"app",
		source,
		SecretVaultScript.APP_SECRET_KEYS
	)
	if clean.has("arya_password") \
			or str(vault.call("get_secret", "app", "arya_password", "")) != "migrated-value":
		_fail("Extracao de credencial falhou.")
		return
	var merged: Dictionary = vault.call(
		"merge_secrets",
		"app",
		clean,
		SecretVaultScript.APP_SECRET_KEYS
	)
	if str(merged.get("arya_password", "")) != "migrated-value":
		_fail("Leitura transparente do cofre falhou.")
		return
	vault.call("lock_view")
	print("SECRET_VAULT_CHECK_OK")
	DirAccess.remove_absolute(test_path)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	var test_path := OS.get_environment("GRUPO_RS_VAULT_PATH").strip_edges()
	if test_path != "" and FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)
	quit(1)


func _bytes_contains(haystack: PackedByteArray, needle: PackedByteArray) -> bool:
	if needle.is_empty() or needle.size() > haystack.size():
		return false
	for start in range(haystack.size() - needle.size() + 1):
		var matched := true
		for offset in range(needle.size()):
			if haystack[start + offset] != needle[offset]:
				matched = false
				break
		if matched:
			return true
	return false
