extends SceneTree


class LiveDashboard:
	extends "res://src/inventory_dashboard.gd"

	func _ready() -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := LiveDashboard.new()
	dashboard.selected_branch_id = "imperatriz"
	dashboard.selected_branch_name = "IMPERATRIZ"
	dashboard.selected_branch_grupo_rs_mode = "modern"
	dashboard.selected_branch_grupo_rs_base_url = "https://novogrupors.ddns.net/cadastro/"
	root.add_child(dashboard)
	await process_frame

	var snapshot: Dictionary = await dashboard.call("_fetch_dashboard_communication_snapshot")
	if not bool(snapshot.get("ok", false)):
		push_error("Leitura real do grafico falhou: %s" % str(snapshot.get("message", snapshot)))
		dashboard.queue_free()
		quit(1)
		return
	var counts: Dictionary = snapshot.get("counts", {})
	for interval_name in dashboard.DASHBOARD_COMMUNICATION_INTERVALS:
		if not counts.has(str(interval_name)):
			push_error("Faixa ausente na leitura real: %s" % str(interval_name))
			dashboard.queue_free()
			quit(1)
			return
	if int(snapshot.get("total", 0)) <= 0:
		push_error("Leitura real retornou total vazio.")
		dashboard.queue_free()
		quit(1)
		return

	print("DASHBOARD_COMMUNICATION_LIVE_READONLY_CHECK_OK total=%d counts=%s" % [int(snapshot.get("total", 0)), str(counts)])
	dashboard.queue_free()
	quit(0)
