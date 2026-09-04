extends SceneTree

const Dashboard := preload("res://src/inventory_dashboard.gd")

var failures: Array[String] = []


func _init() -> void:
	var dashboard := Dashboard.new()
	root.add_child(dashboard)
	var expiry := int(Time.get_unix_time_from_system()) + 900
	var header := Marshalls.raw_to_base64('{"alg":"none"}'.to_utf8_buffer()).trim_suffix("=").replace("+", "-").replace("/", "_")
	var payload := Marshalls.raw_to_base64(JSON.stringify({"exp": expiry}).to_utf8_buffer()).trim_suffix("=").replace("+", "-").replace("/", "_")
	_check(dashboard._jwt_expiry_unix("%s.%s." % [header, payload]) == expiry, "Nao leu a validade do token JWT.")
	_check(dashboard._jwt_expiry_unix("token-invalido") == 0, "Token opaco deveria ficar sem validade conhecida.")
	dashboard.integration_session_states = {
		"grupo_rs": {"status": "connected", "checked_at": int(Time.get_unix_time_from_system())},
		"aparelhos": {"status": "connected", "checked_at": int(Time.get_unix_time_from_system())},
		"arya": {"status": "renewing", "checked_at": int(Time.get_unix_time_from_system())},
		"linksolutions": {"status": "unavailable", "checked_at": int(Time.get_unix_time_from_system())},
	}
	var stack := VBoxContainer.new()
	dashboard._build_config_connections_section(stack)
	_check(stack.find_child("ApiSessionGrid", true, false) != null, "Grade de conexoes nao foi criada.")
	_check(stack.find_children("ApiSessionCard_*", "Button", true, false).size() == 4, "A grade deve ter quatro cartoes navegaveis.")
	_check(not dashboard._config_section_requires_vault("connections"), "Status de conexao nao deve expor nem exigir credenciais.")
	dashboard.current_section = "settings"
	dashboard.config_selected_section = "connections"
	var first_card: Button = stack.find_child("ApiSessionCard_grupo_rs", true, false) as Button
	var before_id := first_card.get_instance_id()
	dashboard.integration_session_states["grupo_rs"] = {"status": "renewing", "checked_at": int(Time.get_unix_time_from_system())}
	dashboard._refresh_api_session_card("grupo_rs")
	_check(is_instance_valid(first_card) and first_card.get_instance_id() == before_id, "Atualizacao parcial recriou o cartao inteiro.")
	dashboard.queue_free()
	if failures.is_empty():
		print("INTEGRATION_SESSION_MANAGER_TEST: OK")
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
