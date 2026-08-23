class_name AISettings
extends RefCounted

const SecretVaultScript := preload("res://src/security/secret_vault.gd")
const CONFIG_PATH := "user://ai_config.json"
const TEST_CONFIG_PATH := "user://ai_config.codex_test.json"
const DEFAULT_MODEL := "gemini-flash-lite-latest"
const RETIRED_DEFAULT_MODELS := ["gemini-2.5-flash-lite"]
const MIN_API_KEY_LENGTH := 20

const DEFAULTS := {
	"gemini_api_key": "",
	"gemini_enabled": false,
	"local_ai_enabled": true,
	"model": DEFAULT_MODEL,
	"save_history_local": false,
	"context_inventory": true,
	"context_maintenance": true,
	"allow_online_analysis": false,
	"daily_request_limit": 20,
	"minimum_interval_seconds": 10,
	"max_history_messages": 20,
	"max_prompt_chars": 6000,
	"cache_ttl_seconds": 1800,
	"monitor_enabled": true,
	"monitor_interval_seconds": 300,
	"low_stock_threshold": 5,
}

var _values: Dictionary = DEFAULTS.duplicate(true)
var _config_path := CONFIG_PATH
var _test_mode := false


func _init() -> void:
	_test_mode = _is_test_runtime()
	if _test_mode:
		_config_path = TEST_CONFIG_PATH


func load_settings() -> Dictionary:
	_values = DEFAULTS.duplicate(true)
	var found_plaintext_key := false
	if FileAccess.file_exists(_config_path):
		var file := FileAccess.open(_config_path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				found_plaintext_key = (parsed as Dictionary).has("gemini_api_key") \
					and str((parsed as Dictionary).get("gemini_api_key", "")).strip_edges() != ""
				for key in (parsed as Dictionary):
					if _values.has(key):
						_values[key] = (parsed as Dictionary)[key]
	if not _test_mode:
		var vault := _secret_vault()
		if vault != null:
			var migrated := _values.duplicate(true)
			if found_plaintext_key:
				migrated = vault.call(
					"extract_secrets",
					"luna",
					migrated,
					SecretVaultScript.LUNA_SECRET_KEYS
				)
			else:
				for secret_key in SecretVaultScript.LUNA_SECRET_KEYS:
					migrated.erase(secret_key)
			_values = vault.call(
				"merge_secrets",
				"luna",
				migrated,
				SecretVaultScript.LUNA_SECRET_KEYS
			)
	var repaired := _normalize()
	if repaired or found_plaintext_key:
		_write_values()
	return get_all()


func save_settings(changes: Dictionary = {}) -> bool:
	for key in changes:
		if _values.has(key):
			_values[key] = changes[key]
	_normalize()
	return _write_values()


func _write_values() -> bool:
	var stored_values := _values.duplicate(true)
	if not _test_mode:
		var vault := _secret_vault()
		if vault != null:
			stored_values = vault.call(
				"extract_secrets",
				"luna",
				stored_values,
				SecretVaultScript.LUNA_SECRET_KEYS
			)
			if not bool(vault.call("status").get("ok", false)):
				return false
	var file := FileAccess.open(_config_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(stored_values, "\t"))
	return true


func get_value(key: String, fallback: Variant = null) -> Variant:
	if key == "gemini_api_key":
		var environment_key := OS.get_environment("GEMINI_API_KEY").strip_edges()
		if environment_key != "":
			return environment_key
	return _values.get(key, fallback)


func set_value(key: String, value: Variant) -> void:
	if _values.has(key):
		_values[key] = value
		_normalize()


func get_all(include_secret: bool = true) -> Dictionary:
	var result := _values.duplicate(true)
	if include_secret:
		var environment_key := OS.get_environment("GEMINI_API_KEY").strip_edges()
		if environment_key != "":
			result["gemini_api_key"] = environment_key
	else:
		result.erase("gemini_api_key")
		result["api_key_configured"] = str(get_value("gemini_api_key", "")) != ""
	return result


func clear_api_key() -> bool:
	_values["gemini_api_key"] = ""
	if not _test_mode:
		var vault := _secret_vault()
		if vault != null:
			vault.call("remove_secret", "luna", "gemini_api_key")
	return save_settings()


func api_key_source() -> String:
	if OS.get_environment("GEMINI_API_KEY").strip_edges() != "":
		return "environment"
	if str(_values.get("gemini_api_key", "")).strip_edges() != "":
		return "encrypted_vault" if not _test_mode else "test_file"
	return "none"


func active_config_path() -> String:
	return _config_path


func is_test_mode() -> bool:
	return _test_mode


func _normalize() -> bool:
	var repaired := false
	_values["gemini_api_key"] = str(_values.get("gemini_api_key", "")).strip_edges()
	if not _test_mode \
			and str(_values["gemini_api_key"]) != "" \
			and str(_values["gemini_api_key"]).length() < MIN_API_KEY_LENGTH:
		_values["gemini_api_key"] = ""
		_values["gemini_enabled"] = false
		_values["allow_online_analysis"] = false
		repaired = true
	_values["model"] = str(_values.get("model", DEFAULT_MODEL)).strip_edges()
	if str(_values["model"]) == "" or RETIRED_DEFAULT_MODELS.has(str(_values["model"])):
		_values["model"] = DEFAULT_MODEL
		repaired = true
	for key in [
		"gemini_enabled",
		"local_ai_enabled",
		"save_history_local",
		"context_inventory",
		"context_maintenance",
		"allow_online_analysis",
		"monitor_enabled",
	]:
		_values[key] = bool(_values.get(key, DEFAULTS[key]))
	_values["daily_request_limit"] = clampi(int(_values.get("daily_request_limit", 20)), 1, 100)
	_values["minimum_interval_seconds"] = clampi(int(_values.get("minimum_interval_seconds", 10)), 2, 300)
	_values["max_history_messages"] = clampi(int(_values.get("max_history_messages", 20)), 4, 20)
	_values["max_prompt_chars"] = clampi(int(_values.get("max_prompt_chars", 6000)), 1000, 12000)
	_values["cache_ttl_seconds"] = clampi(int(_values.get("cache_ttl_seconds", 1800)), 60, 86400)
	_values["monitor_interval_seconds"] = clampi(int(_values.get("monitor_interval_seconds", 300)), 60, 3600)
	_values["low_stock_threshold"] = clampi(int(_values.get("low_stock_threshold", 5)), 0, 10000)
	return repaired


func _is_test_runtime() -> bool:
	if OS.get_environment("GRUPO_RS_AI_TEST_MODE").strip_edges() == "1":
		return true
	var arguments := OS.get_cmdline_args()
	arguments.append_array(OS.get_cmdline_user_args())
	for argument in arguments:
		if str(argument).contains("__codex_luna_ai_check"):
			return true
	return false


func _secret_vault() -> Node:
	var main_loop := Engine.get_main_loop()
	if not main_loop is SceneTree:
		return null
	var tree := main_loop as SceneTree
	var vault := tree.root.get_node_or_null("SecretVault")
	if vault != null:
		return vault
	vault = SecretVaultScript.new()
	vault.name = "SecretVault"
	tree.root.add_child(vault)
	return vault
