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

	var base_version := str(bootstrap.call("base_version"))
	var update_version := _next_patch_version(base_version)
	var later_version := _next_patch_version(update_version)
	if int(bootstrap.call("compare_versions", update_version, base_version)) != 1:
		_fail("Comparacao de versao nova falhou.")
		return
	if int(bootstrap.call("compare_versions", base_version, base_version)) != 0:
		_fail("Comparacao de versoes iguais falhou.")
		return
	if int(bootstrap.call("compare_versions", "0.0.1", base_version)) != -1:
		_fail("Comparacao de versao antiga falhou.")
		return

	var source_dir := "user://codex_update_test/source"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source_dir))
	var package_path := source_dir.path_join("grupo-rs-central-%s.pck" % update_version)
	var package := FileAccess.open(package_path, FileAccess.WRITE)
	if package == null:
		_fail("Pacote simulado nao pode ser criado.")
		return
	package.store_buffer(("PACOTE-DE-TESTE-GRUPO-RS-" + update_version).to_utf8_buffer())
	package.close()

	var global_package := ProjectSettings.globalize_path(package_path)
	var package_reader := FileAccess.open(global_package, FileAccess.READ)
	var package_size := package_reader.get_length()
	package_reader.close()
	var manifest := {
		"app": "grupo-rs-central",
		"channel": "stable",
		"version": update_version,
		"minimum_base_version": base_version,
		"package": package_path.get_file(),
		"sha256": FileAccess.get_sha256(global_package),
		"size": package_size,
		"notes": "Teste automatico do atualizador.",
	}
	var manifest_path := source_dir.path_join("manifest.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	manifest_file.close()

	var check: Dictionary = await bootstrap.call("check_for_updates", ProjectSettings.globalize_path(manifest_path))
	if not bool(check.get("ok", false)) or not bool(check.get("available", false)):
		_fail("Manifesto local nao anunciou a versao nova: %s" % str(check))
		return

	var installed: Dictionary = await bootstrap.call("install_available_update")
	if not bool(installed.get("ok", false)) or not bool(installed.get("restart_required", false)):
		_fail("Pacote valido nao foi preparado: %s" % str(installed))
		return
	var state: Dictionary = bootstrap.call("state_snapshot")
	var pending: Dictionary = state.get("pending", {})
	if str(pending.get("version", "")) != update_version:
		_fail("Estado pendente nao preservou a versao.")
		return
	var staged_path := str(pending.get("path", ""))
	if not FileAccess.file_exists(staged_path):
		_fail("Pacote validado nao foi copiado para a pasta segura.")
		return

	var corrupt_manifest := manifest.duplicate(true)
	corrupt_manifest["version"] = later_version
	corrupt_manifest["sha256"] = "0".repeat(64)
	var corrupt: Dictionary = bootstrap.call("stage_update", package_path, corrupt_manifest)
	if bool(corrupt.get("ok", false)) or not str(corrupt.get("message", "")).contains("SHA-256"):
		_fail("Pacote adulterado nao foi bloqueado pelo SHA-256.")
		return

	bootstrap.call("reset_test_state")
	print("UPDATE_SYSTEM_CHECK_OK")
	quit(0)


func _next_patch_version(version: String) -> String:
	var parts := version.split(".")
	while parts.size() < 3:
		parts.append("0")
	return "%d.%d.%d" % [int(parts[0]), int(parts[1]), int(parts[2]) + 1]


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
