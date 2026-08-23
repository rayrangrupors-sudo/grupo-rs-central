extends SceneTree


func _initialize() -> void:
	call_deferred("_configure")


func _configure() -> void:
	var api_key := DisplayServer.clipboard_get().strip_edges()
	if api_key.length() < 30:
		push_error("GEMINI_CONFIG_FAILED: clipboard does not contain a valid API key")
		quit(1)
		return

	var settings = load("res://ai/ai_settings.gd").new()
	settings.load_settings()
	var saved: bool = settings.save_settings({
		"gemini_api_key": api_key,
		"gemini_enabled": true,
		"allow_online_analysis": true,
		"local_ai_enabled": true,
		"model": "gemini-flash-lite-latest",
	})
	var vault = settings._secret_vault()
	var vault_has_key := bool(vault.call("has_secret", "luna", "gemini_api_key")) \
		if vault != null else false
	var vault_error := str(vault.status().get("error", "")) if vault != null else "unavailable"
	var reopened_vault = load("res://src/security/secret_vault.gd").new()
	reopened_vault.name = "GeminiVaultVerification"
	root.add_child(reopened_vault)
	var persisted_key := bool(reopened_vault.call(
		"has_secret",
		"luna",
		"gemini_api_key"
	))
	api_key = ""
	DisplayServer.clipboard_set("")

	if not saved or not vault_has_key or not persisted_key or vault_error != "":
		push_error("GEMINI_CONFIG_FAILED: encrypted vault write failed: %s" % vault_error)
		quit(2)
		return

	print("GEMINI_CONFIG_SAVED=", JSON.stringify({
		"vault_path": str(vault.status().get("path", "")),
		"vault_ok": bool(vault.status().get("ok", false)),
		"vault_has_key": vault_has_key,
		"persisted_key": persisted_key,
	}))
	quit(0)
