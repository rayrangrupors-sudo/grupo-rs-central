extends SceneTree

const Dashboard := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := Dashboard.new()
	root.add_child(dashboard)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.one_shot = false
	dashboard.add_child(timer)
	dashboard.st310_location_poll_timer = timer

	dashboard.current_section = "dashboard"
	dashboard._update_page_scoped_timers()
	assert(timer.is_stopped(), "O ciclo do mapa ficou ativo fora da pagina.")

	dashboard.current_section = "vehicle_location"
	dashboard._update_page_scoped_timers()
	assert(not timer.is_stopped(), "O ciclo do mapa nao iniciou ao abrir a pagina.")

	dashboard.vehicle_location_query_generation = 7
	dashboard.vehicle_location_query_queue = ["ABC-1234"]
	dashboard.vehicle_location_refreshing = true
	dashboard.st310_location_polling = true
	dashboard._set_page_context("dashboard", "Dashboard")
	assert(timer.is_stopped(), "O ciclo do mapa nao parou ao trocar de pagina.")
	assert(dashboard.vehicle_location_query_generation == 8, "Consultas antigas nao foram invalidadas.")
	assert(dashboard.vehicle_location_query_queue.is_empty(), "A fila da pagina anterior foi preservada.")
	assert(not dashboard.vehicle_location_refreshing and not dashboard.st310_location_polling, "O estado de consulta ficou ativo.")

	dashboard.free()
	await process_frame
	print("PAGE_RUNTIME_LIFECYCLE_TEST: OK")
	quit(0)
