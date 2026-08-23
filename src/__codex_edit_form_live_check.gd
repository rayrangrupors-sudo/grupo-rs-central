extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard: Node = DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	var serial := OS.get_environment("CODEX_EDIT_TEST_SERIAL").strip_edges()
	if serial == "":
		serial = "024372729"
	var rows: Array = await dashboard.call("_fetch_grupo_rs_equipment_rows", serial)
	if rows.is_empty():
		push_error("Equipamento de teste nao foi localizado.")
		quit(1)
		return
	var row: Dictionary = rows[0] as Dictionary
	var plate := str(row.get("plate", "")).strip_edges()
	var client := str(row.get("client", "")).strip_edges()
	if plate == "" or client == "":
		push_error("Associacao nao foi enriquecida: placa='%s' cliente='%s'." % [plate, client])
		quit(1)
		return
	var form_data: Dictionary = row.duplicate(true)
	var details: Dictionary = await dashboard.call("_fetch_grupo_rs_equipment_details", form_data)
	for key in details.keys():
		form_data[key] = details[key]
	var available := str(form_data.get("serial", "")).strip_edges() != "" and str(form_data.get("plate", "")).strip_edges() != ""
	if not available:
		push_error("Botao Alterar placa RS continuaria desabilitado.")
		quit(1)
		return
	print("EDIT_FORM_LIVE_CHECK_OK plate=%s client_present=%s reassignment_ready=%s" % [plate, str(client != ""), available])
	dashboard.queue_free()
	await process_frame
	quit(0)
