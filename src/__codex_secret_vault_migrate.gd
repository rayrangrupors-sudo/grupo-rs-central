extends SceneTree

const SecretVaultScript := preload("res://src/security/secret_vault.gd")

const CONFIGS := [
	{
		"path": "user://app_settings.json",
		"namespace": "app",
		"keys": SecretVaultScript.APP_SECRET_KEYS,
	},
	{
		"path": "user://firebase_sync_config.json",
		"namespace": "firebase",
		"keys": SecretVaultScript.FIREBASE_SECRET_KEYS,
	},
	{
		"path": "user://ai_config.json",
		"namespace": "luna",
		"keys": SecretVaultScript.LUNA_SECRET_KEYS,
	},
]

const OPTIONAL_SEEDS := [
	{
		"environment": "GRUPO_RS_SEED_LINK_EMAIL",
		"namespace": "app",
		"key": "linksolutions_email",
	},
	{
		"environment": "GRUPO_RS_SEED_LINK_PASSWORD",
		"namespace": "app",
		"key": "linksolutions_password",
	},
]

const LEGACY_APP_BACKUP_PATH := "user://app_settings.json.experttexting.bak"
const LEGACY_RECOVERY_KEYS := [
	"sga_rastreio_password",
	"sga_rastreio_user_token",
	"sga_protecao_password",
	"sga_protecao_user_token",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var password := OS.get_environment("GRUPO_RS_VAULT_SETUP_PASSWORD")
	if password.length() < 8:
		_fail("Senha de migracao ausente ou invalida.")
		return
	var vault := root.get_node_or_null("SecretVault")
	if vault == null:
		vault = SecretVaultScript.new()
		vault.name = "SecretVault"
		root.add_child(vault)
	var access: Dictionary
	if bool(vault.call("has_unlock_password")):
		access = vault.call("unlock_view", password)
	else:
		access = vault.call("initialize_unlock_password", password)
	if not bool(access.get("ok", false)):
		_fail("Nao foi possivel preparar o cofre: %s" % str(access.get("message", "")))
		return
	for seed in OPTIONAL_SEEDS:
		var value := OS.get_environment(str(seed.get("environment", "")))
		if value == "":
			continue
		if not bool(vault.call(
			"set_secret",
			str(seed.get("namespace", "")),
			str(seed.get("key", "")),
			value
		)):
			_fail("Nao foi possivel gravar uma credencial adicional no cofre.")
			return
	if FileAccess.file_exists(LEGACY_APP_BACKUP_PATH):
		var legacy_backup := _read_dictionary(LEGACY_APP_BACKUP_PATH)
		for key in LEGACY_RECOVERY_KEYS:
			var value: Variant = legacy_backup.get(key, "")
			if str(value).strip_edges() == "":
				continue
			if not bool(vault.call("set_secret", "app", key, value)):
				_fail("Nao foi possivel recuperar uma credencial SGA do backup legado.")
				return
		var sanitized_backup := legacy_backup.duplicate(true)
		for key in SecretVaultScript.APP_SECRET_KEYS:
			sanitized_backup.erase(key)
		if sanitized_backup != legacy_backup \
				and not _write_dictionary(LEGACY_APP_BACKUP_PATH, sanitized_backup):
			_fail("Nao foi possivel higienizar o backup antigo de configuracoes.")
			return

	var migrated_counts := {}
	for config in CONFIGS:
		var path := str(config.get("path", ""))
		var namespace_key := str(config.get("namespace", ""))
		var keys: Array = config.get("keys", [])
		var original := _read_dictionary(path)
		var sanitized: Dictionary = vault.call("extract_secrets", namespace_key, original, keys)
		for key in keys:
			var original_value: Variant = original.get(key, "")
			if str(original_value).strip_edges() == "":
				continue
			if vault.call("get_secret", namespace_key, str(key), null) != original_value:
				_fail("A verificacao criptografada falhou em %s." % namespace_key)
				return
		if sanitized != original and not _write_dictionary(path, sanitized):
			_fail("Nao foi possivel remover os campos sensiveis de %s." % path)
			return
		var count := 0
		for key in keys:
			if bool(vault.call("has_secret", namespace_key, str(key))):
				count += 1
		migrated_counts[namespace_key] = count

	var destination := ProjectSettings.globalize_path(
		"res://dist/GRUPO RS CENTRAL/.secrets/integrations.vault"
	)
	if not bool(vault.call("copy_vault_to", destination)):
		_fail("Nao foi possivel copiar o cofre para a pasta do executavel.")
		return
	vault.call("lock_view")
	print(
		"SECRET_VAULT_MIGRATION_OK app=%d firebase=%d luna=%d" % [
			int(migrated_counts.get("app", 0)),
			int(migrated_counts.get("firebase", 0)),
			int(migrated_counts.get("luna", 0)),
		]
	)
	quit(0)


func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file = null
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _write_dictionary(path: String, value: Dictionary) -> bool:
	var temp_path := "%s.vault_migration.tmp" % path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	file = null
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute_path)
	if DirAccess.rename_absolute(absolute_temp, absolute_path) == OK:
		return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
