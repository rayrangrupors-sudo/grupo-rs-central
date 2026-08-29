class_name SecretVaultStore
extends Node

signal view_lock_changed(unlocked: bool)
signal secrets_changed

const VAULT_VERSION := 1
const VAULT_DIRECTORY := ".secrets"
const VAULT_FILE := "integrations.vault"
const VIEW_SESSION_SECONDS := 600
const PASSWORD_HASH_ROUNDS := 12000
const TRANSFER_FORMAT := "grupo-rs-central-secret-transfer"
const TRANSFER_VERSION := 1
const TRANSFER_MIN_PASSWORD_LENGTH := 8

const APP_SECRET_KEYS := [
	"arya_email",
	"arya_password",
	"arya_token",
	"grupo_rs_modern_user",
	"grupo_rs_modern_password",
	"grupo_rs_api_user",
	"grupo_rs_api_password",
	"grupo_rs_legacy_user",
	"grupo_rs_legacy_password",
	"grupo_rs_legacy_araguaina_user",
	"grupo_rs_legacy_araguaina_password",
	"grupo_rs_legacy_acailandia_user",
	"grupo_rs_legacy_acailandia_password",
	"grupo_rs_legacy_maraba_user",
	"grupo_rs_legacy_maraba_password",
	"linksolutions_email",
	"linksolutions_password",
	"linksolutions_token",
	"experttexting_username",
	"experttexting_api_key",
	"experttexting_api_secret",
	"openai_api_key",
]

const BANCO_LOCAL_SQL_SECRET_KEYS := [
	"account_email",
	"api_key",
	"refresh_token",
	"user_id",
]

const LUNA_SECRET_KEYS := [
	"gemini_api_key",
]

var _data: Dictionary = {}
var _loaded := false
var _load_error := ""
var _view_unlocked_until := 0


func _ready() -> void:
	_ensure_loaded()
	if OS.get_environment("GRUPO_RS_TRANSFER_MODE").strip_edges() != "":
		call_deferred("_run_transfer_cli")


func _run_transfer_cli() -> void:
	var mode := OS.get_environment("GRUPO_RS_TRANSFER_MODE").strip_edges().to_lower()
	var bundle_path := OS.get_environment("GRUPO_RS_TRANSFER_BUNDLE_PATH").strip_edges()
	var transfer_password := OS.get_environment("GRUPO_RS_TRANSFER_PASSWORD")
	var vault_password := OS.get_environment("GRUPO_RS_VAULT_PASSWORD")
	if vault_password == "":
		vault_password = transfer_password
	if mode not in ["import", "export"]:
		_print_transfer_cli_error("invalid_mode")
		return
	if bundle_path == "" or transfer_password.length() < TRANSFER_MIN_PASSWORD_LENGTH:
		_print_transfer_cli_error("missing_bundle_or_password")
		return

	if mode == "export":
		if vault_password.length() < TRANSFER_MIN_PASSWORD_LENGTH:
			_print_transfer_cli_error("missing_vault_password")
			return
		var access: Dictionary = unlock_view(vault_password)
		if not bool(access.get("ok", false)):
			_print_transfer_cli_error("vault_unlock_failed")
			return
		var exported: Dictionary = export_transfer_bundle(bundle_path, transfer_password)
		lock_view()
		if not bool(exported.get("ok", false)):
			_print_transfer_cli_error("export_failed")
			return
		print("SECRET_TRANSFER_CLI_OK mode=export count=%d" % int(exported.get("secret_count", 0)))
		get_tree().quit(0)
		return

	var imported: Dictionary = import_transfer_bundle(bundle_path, transfer_password)
	if not bool(imported.get("ok", false)):
		_print_transfer_cli_error("import_failed")
		return
	if not has_unlock_password():
		if vault_password.length() < TRANSFER_MIN_PASSWORD_LENGTH:
			_print_transfer_cli_error("missing_vault_password")
			return
		var initialized: Dictionary = initialize_unlock_password(vault_password)
		if not bool(initialized.get("ok", false)):
			_print_transfer_cli_error("vault_setup_failed")
			return
	print("SECRET_TRANSFER_CLI_OK mode=import count=%d" % int(imported.get("secret_count", 0)))
	get_tree().quit(0)


func _print_transfer_cli_error(code: String) -> void:
	push_error("SECRET_TRANSFER_CLI_ERROR %s" % code)
	get_tree().quit(1)


func vault_path() -> String:
	# O caminho sobrescrito e reservado para o editor e para os scripts de
	# transferencia. Em um executavel exportado, uma variavel de ambiente antiga
	# nao pode redirecionar o programa para um cofre de outro perfil/instalacao.
	# O modo de transferencia continua podendo apontar explicitamente para um
	# cofre, e o override manual permanece disponivel para diagnosticos locais.
	var transfer_mode := OS.get_environment("GRUPO_RS_TRANSFER_MODE").strip_edges()
	var allow_override := OS.get_environment("GRUPO_RS_VAULT_OVERRIDE").strip_edges().to_lower() in ["1", "true", "yes"]
	if OS.has_feature("editor") or transfer_mode != "" or allow_override:
		var override_path := OS.get_environment("GRUPO_RS_VAULT_PATH").strip_edges()
		if override_path != "":
			return override_path
	var base_dir := ""
	if OS.has_feature("editor"):
		base_dir = ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")
	else:
		base_dir = OS.get_executable_path().get_base_dir()
	return base_dir.path_join(VAULT_DIRECTORY).path_join(VAULT_FILE)


func status() -> Dictionary:
	_ensure_loaded()
	return {
		"ok": _load_error == "",
		"error": _load_error,
		"path": vault_path(),
		"encrypted": true,
		"password_configured": has_unlock_password(),
		"view_unlocked": is_view_unlocked(),
		"view_seconds_remaining": view_seconds_remaining(),
		"secret_count": _secret_count(),
	}


func has_unlock_password() -> bool:
	_ensure_loaded()
	var unlock: Dictionary = _data.get("unlock", {})
	return str(unlock.get("salt", "")).strip_edges() != "" \
		and str(unlock.get("hash", "")).strip_edges() != ""


func initialize_unlock_password(password: String) -> Dictionary:
	_ensure_loaded()
	if _load_error != "":
		return {"ok": false, "message": _load_error}
	if password.length() < 8:
		return {"ok": false, "message": "A senha do cofre precisa ter pelo menos 8 caracteres."}
	if has_unlock_password() and not is_view_unlocked():
		return {"ok": false, "message": "O cofre ja possui senha. Desbloqueie antes de altera-la."}
	var salt := _random_hex(24)
	_data["unlock"] = {
		"salt": salt,
		"hash": _password_hash(password, salt),
	}
	_view_unlocked_until = int(Time.get_unix_time_from_system()) + VIEW_SESSION_SECONDS
	if not _save():
		return {"ok": false, "message": _load_error}
	view_lock_changed.emit(true)
	return {"ok": true, "message": "Senha do cofre configurada."}


func unlock_view(password: String) -> Dictionary:
	_ensure_loaded()
	if _load_error != "":
		return {"ok": false, "message": _load_error}
	if not has_unlock_password():
		return {"ok": false, "message": "O cofre ainda nao possui senha de visualizacao."}
	var unlock: Dictionary = _data.get("unlock", {})
	var expected := str(unlock.get("hash", ""))
	var actual := _password_hash(password, str(unlock.get("salt", "")))
	if not _constant_time_equals(actual, expected):
		lock_view()
		return {"ok": false, "message": "Senha incorreta."}
	_view_unlocked_until = int(Time.get_unix_time_from_system()) + VIEW_SESSION_SECONDS
	view_lock_changed.emit(true)
	return {
		"ok": true,
		"message": "Cofre desbloqueado.",
		"expires_in": VIEW_SESSION_SECONDS,
	}


func lock_view() -> void:
	var was_unlocked := _view_unlocked_until > 0
	_view_unlocked_until = 0
	if was_unlocked:
		view_lock_changed.emit(false)


func is_view_unlocked() -> bool:
	if _view_unlocked_until <= 0:
		return false
	if int(Time.get_unix_time_from_system()) >= _view_unlocked_until:
		lock_view()
		return false
	return true


func view_seconds_remaining() -> int:
	if not is_view_unlocked():
		return 0
	return maxi(_view_unlocked_until - int(Time.get_unix_time_from_system()), 0)


func get_secret(namespace_key: String, key: String, fallback: Variant = "") -> Variant:
	_ensure_loaded()
	if _load_error != "":
		return fallback
	var namespaces: Dictionary = _data.get("secrets", {})
	var values: Dictionary = namespaces.get(_safe_namespace(namespace_key), {})
	return values.get(key, fallback)


func has_secret(namespace_key: String, key: String) -> bool:
	_ensure_loaded()
	var namespaces: Dictionary = _data.get("secrets", {})
	var values: Dictionary = namespaces.get(_safe_namespace(namespace_key), {})
	return values.has(key) and str(values.get(key, "")).strip_edges() != ""


func set_secret(namespace_key: String, key: String, value: Variant) -> bool:
	_ensure_loaded()
	if _load_error != "":
		return false
	var clean_namespace := _safe_namespace(namespace_key)
	var namespaces: Dictionary = _data.get("secrets", {})
	var values: Dictionary = namespaces.get(clean_namespace, {})
	if str(value).strip_edges() == "":
		values.erase(key)
	else:
		values[key] = value
	namespaces[clean_namespace] = values
	_data["secrets"] = namespaces
	return _save()


func remove_secret(namespace_key: String, key: String) -> bool:
	_ensure_loaded()
	if _load_error != "":
		return false
	var clean_namespace := _safe_namespace(namespace_key)
	var namespaces: Dictionary = _data.get("secrets", {})
	var values: Dictionary = namespaces.get(clean_namespace, {})
	values.erase(key)
	namespaces[clean_namespace] = values
	_data["secrets"] = namespaces
	return _save()


func remove_secrets(namespace_key: String, keys) -> bool:
	_ensure_loaded()
	if _load_error != "":
		return false
	var clean_namespace := _safe_namespace(namespace_key)
	var namespaces: Dictionary = _data.get("secrets", {})
	var values: Dictionary = namespaces.get(clean_namespace, {})
	for key in keys:
		values.erase(key)
	namespaces[clean_namespace] = values
	_data["secrets"] = namespaces
	return _save()


func extract_secrets(namespace_key: String, source: Dictionary, keys) -> Dictionary:
	_ensure_loaded()
	var clean := source.duplicate(true)
	if _load_error != "":
		return clean
	var clean_namespace := _safe_namespace(namespace_key)
	var namespaces: Dictionary = _data.get("secrets", {})
	var values: Dictionary = namespaces.get(clean_namespace, {})
	var changed := false
	for key in keys:
		if not clean.has(key):
			continue
		var value: Variant = clean.get(key)
		if str(value).strip_edges() == "":
			# Campos vazios em configuracoes antigas sao apenas preferencias
			# ausentes; nao devem apagar um segredo ja importado no cofre.
			# A remocao explicita usa remove_secret/remove_secrets.
			clean.erase(key)
			continue
		else:
			values[key] = value
		clean.erase(key)
		changed = true
	if changed:
		namespaces[clean_namespace] = values
		_data["secrets"] = namespaces
		_save()
	return clean


func merge_secrets(namespace_key: String, source: Dictionary, keys) -> Dictionary:
	_ensure_loaded()
	var merged := source.duplicate(true)
	if _load_error != "":
		return merged
	var namespaces: Dictionary = _data.get("secrets", {})
	var values: Dictionary = namespaces.get(_safe_namespace(namespace_key), {})
	for key in keys:
		if values.has(key):
			merged[key] = values[key]
	return merged


func copy_vault_to(destination_path: String) -> bool:
	_ensure_loaded()
	if _load_error != "" or not FileAccess.file_exists(vault_path()):
		return false
	DirAccess.make_dir_recursive_absolute(destination_path.get_base_dir())
	if FileAccess.file_exists(destination_path):
		DirAccess.remove_absolute(destination_path)
	return DirAccess.copy_absolute(vault_path(), destination_path) == OK


func export_transfer_bundle(destination_path: String, transfer_password: String) -> Dictionary:
	_ensure_loaded()
	if _load_error != "":
		return {"ok": false, "message": _load_error}
	if not is_view_unlocked():
		return {"ok": false, "message": "Desbloqueie o cofre antes de exportar uma transferencia."}
	if transfer_password.length() < TRANSFER_MIN_PASSWORD_LENGTH:
		return {"ok": false, "message": "A senha de transferencia precisa ter pelo menos 8 caracteres."}
	var clean_path := destination_path.strip_edges()
	if clean_path == "":
		return {"ok": false, "message": "Destino do pacote de transferencia nao informado."}
	var payload := {
		"format": TRANSFER_FORMAT,
		"version": TRANSFER_VERSION,
		"created_at": Time.get_datetime_string_from_system(false, true),
		"secrets": _transfer_secrets_snapshot(),
	}
	var write_result := _write_encrypted_transfer_file(clean_path, payload, transfer_password)
	if not bool(write_result.get("ok", false)):
		return write_result
	return {
		"ok": true,
		"path": clean_path,
		"secret_count": int(write_result.get("secret_count", 0)),
		"message": "Pacote de transferencia criptografado criado.",
	}


func import_transfer_bundle(source_path: String, transfer_password: String) -> Dictionary:
	_ensure_loaded()
	if _load_error != "":
		return {"ok": false, "message": _load_error}
	if transfer_password.length() < TRANSFER_MIN_PASSWORD_LENGTH:
		return {"ok": false, "message": "A senha de transferencia precisa ter pelo menos 8 caracteres."}
	var clean_path := source_path.strip_edges()
	if clean_path == "" or not FileAccess.file_exists(clean_path):
		return {"ok": false, "message": "Pacote de transferencia nao encontrado."}
	var file := FileAccess.open_encrypted_with_pass(clean_path, FileAccess.READ, transfer_password)
	if file == null:
		return {"ok": false, "message": "Nao foi possivel abrir o pacote de transferencia. Verifique a senha."}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file = null
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "message": "Pacote de transferencia invalido."}
	var payload := parsed as Dictionary
	if str(payload.get("format", "")) != TRANSFER_FORMAT \
			or int(payload.get("version", 0)) != TRANSFER_VERSION:
		return {"ok": false, "message": "Formato do pacote de transferencia nao suportado."}
	var incoming: Variant = payload.get("secrets", {})
	if typeof(incoming) != TYPE_DICTIONARY:
		return {"ok": false, "message": "Pacote de transferencia sem credenciais validas."}
	var filtered := _filter_transfer_secrets(incoming as Dictionary)
	var imported_count := _count_transfer_secrets(filtered)
	if imported_count <= 0:
		return {"ok": false, "message": "Pacote de transferencia sem credenciais reconhecidas."}
	var namespaces: Dictionary = _data.get("secrets", {})
	for namespace_key in filtered:
		var current_values: Dictionary = namespaces.get(namespace_key, {})
		var incoming_values: Dictionary = filtered.get(namespace_key, {})
		for key in incoming_values:
			current_values[str(key)] = incoming_values.get(key)
		namespaces[namespace_key] = current_values
	_data["secrets"] = namespaces
	if not _save():
		return {"ok": false, "message": _load_error}
	return {
		"ok": true,
		"secret_count": imported_count,
		"message": "Credenciais importadas para o cofre local.",
	}


func _write_encrypted_transfer_file(path: String, payload: Dictionary, password: String) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(path)
	var temp_path := "%s.tmp" % absolute_path
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)
	var file := FileAccess.open_encrypted_with_pass(temp_path, FileAccess.WRITE, password)
	if file == null:
		return {"ok": false, "message": "Nao foi possivel criar o pacote de transferencia."}
	file.store_string(JSON.stringify(payload))
	file.flush()
	file = null
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
	var rename_error := DirAccess.rename_absolute(temp_path, absolute_path)
	if rename_error != OK:
		DirAccess.remove_absolute(temp_path)
		return {"ok": false, "message": "Nao foi possivel finalizar o pacote de transferencia."}
	return {
		"ok": true,
		"secret_count": _count_transfer_secrets(payload.get("secrets", {})),
	}


func _transfer_secrets_snapshot() -> Dictionary:
	return _filter_transfer_secrets(_data.get("secrets", {}))


func _filter_transfer_secrets(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var namespaces := {
		"app": APP_SECRET_KEYS,
		"local_database": BANCO_LOCAL_SQL_SECRET_KEYS,
		"luna": LUNA_SECRET_KEYS,
	}
	for namespace_key in namespaces:
		var source_values: Variant = source.get(namespace_key, {})
		if typeof(source_values) != TYPE_DICTIONARY:
			continue
		var clean_values: Dictionary = {}
		for key in namespaces[namespace_key]:
			var value: Variant = (source_values as Dictionary).get(key, "")
			if str(value).strip_edges() != "":
				clean_values[key] = value
		if not clean_values.is_empty():
			result[namespace_key] = clean_values
	return result


func _count_transfer_secrets(source: Variant) -> int:
	if typeof(source) != TYPE_DICTIONARY:
		return 0
	var total := 0
	for namespace_key in source:
		var values: Variant = (source as Dictionary).get(namespace_key, {})
		if typeof(values) == TYPE_DICTIONARY:
			total += (values as Dictionary).size()
	return total


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_data = _default_data()
	var path := vault_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if not FileAccess.file_exists(path):
		if not _save():
			_load_error = "Nao foi possivel criar o cofre criptografado."
		return
	var file := FileAccess.open_encrypted_with_pass(path, FileAccess.READ, _machine_passphrase())
	if file == null:
		_load_error = "O cofre nao pode ser aberto neste usuario do Windows."
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file = null
	if typeof(parsed) != TYPE_DICTIONARY:
		_load_error = "O cofre criptografado esta corrompido."
		return
	var loaded_data := parsed as Dictionary
	if int(loaded_data.get("version", 0)) != VAULT_VERSION:
		_load_error = "Versao do cofre nao suportada."
		return
	_data = loaded_data
	if typeof(_data.get("secrets", {})) != TYPE_DICTIONARY:
		_data["secrets"] = {}
	if typeof(_data.get("unlock", {})) != TYPE_DICTIONARY:
		_data["unlock"] = {}


func _save() -> bool:
	if _load_error != "":
		return false
	var path := vault_path()
	var temp_path := "%s.tmp" % path
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_data["version"] = VAULT_VERSION
	_data["updated_at"] = Time.get_datetime_string_from_system(false, true)
	var file := FileAccess.open_encrypted_with_pass(
		temp_path,
		FileAccess.WRITE,
		_machine_passphrase()
	)
	if file == null:
		_load_error = "Nao foi possivel gravar o cofre criptografado."
		return false
	file.store_string(JSON.stringify(_data))
	file.flush()
	file = null
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var rename_error := DirAccess.rename_absolute(temp_path, path)
	if rename_error != OK:
		_load_error = "Nao foi possivel finalizar o arquivo criptografado."
		DirAccess.remove_absolute(temp_path)
		return false
	secrets_changed.emit()
	return true


func _default_data() -> Dictionary:
	return {
		"version": VAULT_VERSION,
		"unlock": {},
		"secrets": {},
		"updated_at": "",
	}


func _machine_passphrase() -> String:
	var identity := "%s|%s|%s|%s" % [
		"grupo-rs-central",
		OS.get_unique_id(),
		OS.get_environment("USERNAME").strip_edges().to_lower(),
		"vault-aes-256-v1",
	]
	return identity.sha256_text()


func _password_hash(password: String, salt: String) -> String:
	var digest := ("%s|%s" % [salt, password]).sha256_text()
	for index in range(PASSWORD_HASH_ROUNDS):
		digest = ("%s|%s|%d" % [salt, digest, index]).sha256_text()
	return digest


func _constant_time_equals(left: String, right: String) -> bool:
	if left.length() != right.length():
		return false
	var difference := 0
	for index in range(left.length()):
		difference |= left.unicode_at(index) ^ right.unicode_at(index)
	return difference == 0


func _random_hex(byte_count: int) -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(byte_count).hex_encode()


func _safe_namespace(value: String) -> String:
	var clean := value.strip_edges().to_lower()
	return clean if clean != "" else "app"


func _secret_count() -> int:
	var total := 0
	var namespaces: Dictionary = _data.get("secrets", {})
	for namespace_key in namespaces:
		var values: Variant = namespaces.get(namespace_key)
		if typeof(values) == TYPE_DICTIONARY:
			total += (values as Dictionary).size()
	return total
