extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard: Node = DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	var serial := OS.get_environment("CODEX_HIDE_TEST_SERIAL").strip_edges()
	var plate := OS.get_environment("CODEX_HIDE_TEST_PLATE").strip_edges()
	if serial == "":
		serial = "024372729"
	if plate == "":
		plate = "AAA - 008"
	var response: Dictionary = await dashboard.call("_fetch_modern_grupo_rs_vehicle_rows_all_statuses", plate, true)
	if not bool(response.get("ok", false)):
		push_error("Consulta dos estados remoto falhou: %s" % str(response.get("message", "")))
		quit(1)
		return
	var rows: Array = response.get("rows", [])
	var exact: Dictionary = dashboard.call("_choose_modern_grupo_rs_vehicle_row_exact", rows, serial, plate)
	if exact.is_empty():
		push_error("Veiculo de teste nao foi identificado de forma unica pela serie e placa.")
		quit(1)
		return
	var status := str(exact.get("status", "")).strip_edges().to_lower()
	var has_hide_action := str(exact.get("inactivate_href", "")).strip_edges() != ""
	if status == "ativo" and not has_hide_action:
		push_error("Veiculo ativo nao possui acao segura de inativacao no portal.")
		quit(1)
		return
	print("REMOTE_HIDE_READONLY_CHECK_OK status=%s hide_action=%s" % [status, has_hide_action])
	dashboard.queue_free()
	await process_frame
	quit(0)
