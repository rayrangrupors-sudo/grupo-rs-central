extends SceneTree


class DashboardProbe:
	extends "res://src/inventory_dashboard.gd"
	var probe_status := "Instalado"

	func _local_product_for_serial(_serial: String) -> Dictionary:
		return {
			"serial": "024381076",
			"sku": "024381076",
			"plate": "ROR - 9H20",
			"client": "ADRIANA CONCEICAO DOS REIS",
			"tracker_status": probe_status,
		}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := DashboardProbe.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")
	var login: Dictionary = await dashboard.call("_grupo_rs_api_login")
	if not bool(login.get("ok", false)):
		_fail(dashboard, "Login API recusado: %s" % str(login.get("message", "")))
		return
	for status in ["Instalado", "Inativo", "Manutencao", "Reserva", "Estoque"]:
		dashboard.probe_status = status
		var source := str(dashboard.call("_grupo_rs_location_source_mode_for_serial", "024381076"))
		var location: Dictionary = await dashboard.call("_lookup_grupo_rs_location", "024381076")
		print("LOCATION_STATUS_REAL status=%s source=%s ok=%s location_source=%s message=%s" % [status, source, str(location.get("ok", false)), str(location.get("source", "")), str(location.get("message", ""))])
		if source != "api" or not bool(location.get("ok", false)):
			_fail(dashboard, "Localizacao falhou para status %s." % status)
			return
	dashboard.queue_free()
	print("LOCATION_STATUS_REAL_CHECK_OK statuses=5 api_primary=true")
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)
