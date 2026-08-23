extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var settings_script := load("res://ai/ai_settings.gd")
	var client_script := load("res://ai/gemini_client.gd")
	var vault_script := load("res://src/security/secret_vault.gd")
	if settings_script == null or client_script == null or vault_script == null:
		_fail("Componentes da Luna nao carregaram.")
		return
	var initial_vault = vault_script.new()
	initial_vault.name = "SecretVault"
	root.add_child(initial_vault)
	var vault_had_key_before_load := bool(initial_vault.call(
		"has_secret",
		"luna",
		"gemini_api_key"
	))
	var settings = settings_script.new()
	var values: Dictionary = settings.load_settings()
	var api_key := str(settings.get_value("gemini_api_key", "")).strip_edges()
	var vault = settings._secret_vault()
	var vault_status: Dictionary = vault.status() if vault != null else {}
	var status := {
		"configured": api_key != "",
		"source": settings.api_key_source(),
		"enabled": bool(values.get("gemini_enabled", false)),
		"online_analysis": bool(values.get("allow_online_analysis", false)),
		"model": str(values.get("model", "")),
		"test_mode": bool(settings.is_test_mode()),
		"config_path": str(settings.active_config_path()),
		"vault_ok": bool(vault_status.get("ok", false)),
		"vault_error": str(vault_status.get("error", "")),
		"vault_path": str(vault_status.get("path", "")),
		"vault_had_key_before_load": vault_had_key_before_load,
		"vault_has_key": bool(vault.call("has_secret", "luna", "gemini_api_key")) if vault != null else false,
	}
	print("GEMINI_STATUS=", JSON.stringify(status))
	if api_key == "":
		quit(2)
		return
	var client = client_script.new()
	root.add_child(client)
	var result: Dictionary = await client.test_connection(
		api_key,
		str(values.get("model", "gemini-flash-lite-latest"))
	)
	print("GEMINI_CONNECTION=", JSON.stringify({
		"ok": bool(result.get("ok", false)),
		"error": str(result.get("error", "")),
		"message": str(result.get("message", "")),
		"model": str(result.get("model", values.get("model", ""))),
	}))
	quit(0 if bool(result.get("ok", false)) else 1)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
