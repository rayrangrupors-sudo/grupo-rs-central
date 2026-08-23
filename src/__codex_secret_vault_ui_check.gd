extends SceneTree

const SecretVaultScript := preload("res://src/security/secret_vault.gd")
const DashboardStubScript := preload("res://src/__codex_secret_vault_dashboard_stub.gd")
const TEST_PASSWORD := "codex-ui-vault-test"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var test_path := OS.get_environment("GRUPO_RS_VAULT_PATH").strip_edges()
	if test_path == "":
		_fail("Caminho isolado do teste nao informado.")
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
	if not bool((vault.call("initialize_unlock_password", TEST_PASSWORD) as Dictionary).get("ok", false)):
		_fail("Nao foi possivel inicializar o cofre de teste.")
		return
	vault.call("set_secret", "app", "arya_email", "conta-teste")
	vault.call("set_secret", "app", "arya_password", "senha-teste")
	vault.call("lock_view")

	var dashboard := DashboardStubScript.new()
	root.add_child(dashboard)
	for section_key in [
		"firebase",
		"arya",
		"grupo_rs",
		"sga",
		"linksolutions",
		"sms",
		"luna",
		"codex",
	]:
		dashboard.set("config_selected_section", section_key)
		var locked_view: Control = dashboard.call("_build_arya_config_view")
		root.add_child(locked_view)
		await process_frame
		if locked_view.find_child("VaultUnlockPassword", true, false) == null:
			_fail("A secao %s exibiu integracoes com o cofre bloqueado." % section_key)
			return
		locked_view.queue_free()
		await process_frame
	if bool((vault.call("unlock_view", "incorrect") as Dictionary).get("ok", false)):
		_fail("A interface aceitou uma senha incorreta.")
		return
	if not bool((vault.call("unlock_view", TEST_PASSWORD) as Dictionary).get("ok", false)):
		_fail("A interface recusou a senha correta.")
		return

	dashboard.set("config_selected_section", "arya")
	dashboard.set("config_secrets_revealed", false)
	var hidden_view: Control = dashboard.call("_build_arya_config_view")
	root.add_child(hidden_view)
	if hidden_view.find_child("VaultUnlockPassword", true, false) != null:
		_fail("A tela permaneceu bloqueada depois da autenticacao.")
		return
	var password_input: LineEdit = dashboard.get("arya_password_input")
	if password_input == null or password_input.text != "" or not password_input.secret:
		_fail("A senha apareceu sem a acao Mostrar credenciais.")
		return
	hidden_view.queue_free()

	dashboard.set("config_secrets_revealed", true)
	var revealed_view: Control = dashboard.call("_build_arya_config_view")
	root.add_child(revealed_view)
	password_input = dashboard.get("arya_password_input")
	if password_input == null or password_input.text != "senha-teste" or password_input.secret:
		_fail("A exibicao autenticada das credenciais nao funcionou.")
		return
	var email_input: LineEdit = dashboard.get("arya_email_input")
	if email_input == null or email_input.text != "conta-teste":
		_fail("O login autenticado nao foi carregado do cofre.")
		return

	dashboard.set("config_selected_section", "grupo_rs")
	var grupo_view: Control = dashboard.call("_build_arya_config_view")
	root.add_child(grupo_view)
	if not _has_text(grupo_view, "Grupo RS / Imperatriz"):
		_fail("A pagina Grupo RS / Imperatriz nao foi montada.")
		return
	if _find_button_by_text(grupo_view, "Araguaina") == null \
			or _find_button_by_text(grupo_view, "Acailandia") == null \
			or _find_button_by_text(grupo_view, "Maraba") == null:
		_fail("A navegacao das bases regionais nao foi montada.")
		return
	grupo_view.queue_free()
	await process_frame

	for branch_id in ["araguaina", "acailandia", "maraba"]:
		dashboard.set("config_selected_section", "grupo_rs_%s" % branch_id)
		var branch_view: Control = dashboard.call("_build_arya_config_view")
		root.add_child(branch_view)
		var expected_title := "Base regional / %s" % str(branch_id).capitalize()
		if not _has_text(branch_view, expected_title):
			_fail("A pagina independente de %s nao foi montada." % branch_id)
			return
		if _find_line_edit_by_placeholder(branch_view, "https://servidor/Base/") == null:
			_fail("O campo URL da base %s nao foi montado." % branch_id)
			return
		branch_view.queue_free()
		await process_frame

	vault.call("lock_view")
	revealed_view.queue_free()
	dashboard.queue_free()
	DirAccess.remove_absolute(test_path)
	print("SECRET_VAULT_UI_CHECK_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	var test_path := OS.get_environment("GRUPO_RS_VAULT_PATH").strip_edges()
	if test_path != "" and FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)
	quit(1)


func _has_text(root_node: Node, expected: String) -> bool:
	for item in root_node.find_children("*", "Label", true, false):
		if item is Label and (item as Label).text.contains(expected):
			return true
	return false


func _find_button_by_text(root_node: Node, expected: String) -> Button:
	for item in root_node.find_children("*", "Button", true, false):
		if item is Button and (item as Button).text == expected:
			return item as Button
	return null


func _find_line_edit_by_placeholder(root_node: Node, expected: String) -> LineEdit:
	for item in root_node.find_children("*", "LineEdit", true, false):
		if item is LineEdit and (item as LineEdit).placeholder_text == expected:
			return item as LineEdit
	return null
