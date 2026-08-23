extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var password := OS.get_environment("CODEX_AUTH_TEST_PASSWORD")
	if password.is_empty():
		_fail("Senha de teste nao informada pelo ambiente.")
		return

	var config_path := ProjectSettings.globalize_path("user://auth_config.json")
	var config := _read_json(config_path)
	if config.is_empty():
		_fail("Configuracao de login nao encontrada em %s." % config_path)
		return

	var auth_script := load("res://src/modules/auth_module.gd")
	if auth_script == null:
		_fail("Modulo de autenticacao nao pode ser carregado.")
		return
	var auth_module = auth_script.new()
	if not bool(auth_module.call("validate", "Lucas", password, config)):
		_fail("O runtime recusou Lucas com a senha configurada.")
		return
	if bool(auth_module.call("validate", "Lucas", password + "-incorreta", config)):
		_fail("O runtime aceitou uma senha incorreta.")
		return

	var scene := load("res://scenes/estoque_profissional.tscn")
	if scene == null:
		_fail("Cena principal nao pode ser carregada.")
		return
	var dashboard: Node = scene.instantiate()
	root.add_child(dashboard)
	await process_frame
	if not bool(dashboard.call("_validate_login", "Lucas", password)):
		_fail("A tela de login recusou a credencial aceita pelo modulo.")
		return
	if bool(dashboard.call("_validate_login", "Lucas", password + "-incorreta")):
		_fail("A tela de login aceitou uma senha incorreta.")
		return

	var version := "base"
	var bootstrap := root.get_node_or_null("UpdateBootstrap")
	if bootstrap != null:
		version = str(bootstrap.call("current_version"))
	print("AUTH_LOGIN_CHECK_OK version=%s" % version)
	quit(0)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
