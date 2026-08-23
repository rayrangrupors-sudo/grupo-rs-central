extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var bootstrap := root.get_node_or_null("UpdateBootstrap")
	if bootstrap == null:
		_fail("Autoload UpdateBootstrap nao foi carregado.")
		return
	if not bool(bootstrap.call("reset_test_state")):
		_fail("Teste nao iniciou em modo isolado.")
		return

	# Simula exatamente o executavel fixo distribuido, sem alterar o projeto em disco.
	ProjectSettings.set_setting("application/config/version", "3.9.40")
	var manifest_path := ProjectSettings.globalize_path("dist/GRUPO RS CENTRAL/updates/manifest.json")
	var manifest_data = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (manifest_data is Dictionary) or str(manifest_data.get("version", "")).is_empty():
		_fail("Manifesto publicado invalido ou sem versao: %s" % manifest_path)
		return
	var expected_version := str(manifest_data.get("version", ""))
	var check: Dictionary = await bootstrap.call("check_for_updates", manifest_path)
	if not bool(check.get("ok", false)) or bool(check.get("requires_new_executable", false)):
		_fail("O manifesto publicado ainda bloqueia a base 3.9.40: %s" % str(check))
		return
	if str(check.get("version", "")) != expected_version:
		_fail("Versao publicada inesperada: %s (esperada %s)" % [str(check), expected_version])
		return

	var installed: Dictionary = await bootstrap.call("install_available_update")
	if not bool(installed.get("ok", false)) or not bool(installed.get("restart_required", false)):
		_fail("Pacote publicado nao foi preparado: %s" % str(installed))
		return

	bootstrap.call("reset_test_state")
	print("PUBLISHED_MANIFEST_COMPATIBILITY_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
