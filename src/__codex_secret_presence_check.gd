extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var vault := root.get_node_or_null("SecretVault")
	if vault == null:
		push_error("SecretVault ausente")
		quit(1)
		return
	var status: Dictionary = vault.call("status")
	print("VAULT_STATUS ok=%s count=%d password=%s" % [str(status.get("ok", false)), int(status.get("secret_count", 0)), str(status.get("password_configured", false))])
	for entry in [
		["app", "sga_rastreio_api_token"],
		["app", "sga_rastreio_user"],
		["app", "sga_rastreio_password"],
		["app", "sga_rastreio_user_token"],
		["app", "sga_protecao_api_token"],
		["app", "sga_protecao_user"],
		["app", "sga_protecao_password"],
		["app", "sga_protecao_user_token"],
	]:
		print("VAULT_KEY %s/%s=%s" % [str(entry[0]), str(entry[1]), str(vault.call("has_secret", str(entry[0]), str(entry[1])))])
	var dashboard := DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	for source in ["rastreio", "protecao"]:
		var credentials: Dictionary = dashboard.call("_sga_credentials", source)
		print("SGA_CREDENTIALS %s api=%s user=%s password=%s user_token=%s" % [source, str(str(credentials.get("api_token", "")).strip_edges() != ""), str(str(credentials.get("username", "")).strip_edges() != ""), str(str(credentials.get("password", "")) != ""), str(str(credentials.get("user_token", "")).strip_edges() != "")])
	dashboard.queue_free()
	quit(0)
