extends SceneTree

const SecretVaultScript := preload("res://src/security/secret_vault.gd")
const BACKUP_PATH := "user://app_settings.json.experttexting.bak"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var vault := root.get_node_or_null("SecretVault")
	if vault == null or not FileAccess.file_exists(BACKUP_PATH):
		push_error("Cofre ou backup legado indisponivel.")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BACKUP_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Backup legado invalido.")
		quit(1)
		return
	var backup := parsed as Dictionary
	for key in SecretVaultScript.APP_SECRET_KEYS:
		if not backup.has(key) or str(backup.get(key, "")).strip_edges() == "":
			continue
		var backup_value: Variant = backup.get(key)
		var vault_value: Variant = vault.call("get_secret", "app", str(key), "")
		print("LEGACY_SECRET key=%s backup_len=%d vault_len=%d equal=%s" % [
			str(key),
			str(backup_value).length(),
			str(vault_value).length(),
			str(backup_value == vault_value),
		])
	quit(0)
