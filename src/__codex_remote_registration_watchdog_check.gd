extends SceneTree


class DashboardStub:
	extends "res://src/inventory_dashboard.gd"
	var feedback: Array[Dictionary] = []
	var logs: Array[Dictionary] = []

	func _equipment_registration_timeout_seconds() -> float:
		return 0.05

	func _show_equipment_registration_feedback(title_text: String, status_text: String, detail_text: String, _color: Color) -> void:
		feedback.append({
			"title": title_text,
			"status": status_text,
			"detail": detail_text,
		})

	func _log_system_action(action: String, details: String = "", serial: String = "") -> void:
		logs.append({"action": action, "details": details, "serial": serial})

	func _perform_equipment_registration(_request: Dictionary) -> Dictionary:
		# Simula uma requisição que não encerra dentro do limite do cadastro.
		await get_tree().create_timer(1.0).timeout
		return {"ok": true, "equipment_only": true}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := DashboardStub.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.equipment_registration_running = true
	dashboard.call_deferred(
		"_start_equipment_registration_job",
		{},
		{"serial": "024399996", "equipment_only": true}
	)
	await root.get_tree().create_timer(0.1).timeout
	# Forca o prazo curto tambem se a chamada virtual for otimizada pelo runtime.
	dashboard.equipment_registration_deadline_msec = Time.get_ticks_msec() + 50
	await root.get_tree().create_timer(0.45).timeout
	if dashboard.equipment_registration_running:
		_fail(dashboard, "Watchdog nao liberou o cadastro remoto apos timeout.")
		return
	if dashboard.equipment_registration_active_generation != -1:
		_fail(dashboard, "Geracao do cadastro remoto permaneceu ativa apos timeout.")
		return
	if dashboard.equipment_registration_deadline_msec != 0:
		_fail(dashboard, "Prazo do cadastro remoto permaneceu definido apos timeout.")
		return
	if dashboard.logs.is_empty() or str(dashboard.logs[0].get("action", "")) != "Cadastro remoto expirou":
		_fail(dashboard, "Timeout do cadastro remoto nao foi registrado corretamente: %s" % str(dashboard.logs))
		return

	# Aguarda a resposta atrasada simulada e confirma que ela nao reativa o job.
	await root.get_tree().create_timer(0.7).timeout
	if dashboard.equipment_registration_running or dashboard.equipment_registration_active_generation != -1:
		_fail(dashboard, "Resposta atrasada reativou o cadastro remoto.")
		return

	dashboard.queue_free()
	print("REMOTE_REGISTRATION_WATCHDOG_CHECK_OK")
	quit(0)


func _fail(dashboard: Node, message: String) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)
