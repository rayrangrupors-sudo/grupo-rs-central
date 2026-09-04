extends SceneTree

class NavigationProbe extends "res://src/inventory_dashboard.gd":
	var opened := false

	func open_target() -> void:
		opened = true
		current_section = "inventory"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := NavigationProbe.new()
	root.add_child(dashboard)
	var isolated_content := MarginContainer.new()
	dashboard.add_child(isolated_content)
	dashboard.content_area = isolated_content
	isolated_content.add_child(Control.new())
	dashboard.current_section = "vehicle_location"
	dashboard.vehicle_location_query_queue.assign(["AAA-0001"])
	dashboard.vehicle_location_pending_queries.assign(["AAA-0001"])
	dashboard.vehicle_location_refreshing = true

	dashboard._request_sidebar_navigation("inventory", Callable(dashboard, "open_target"))
	assert(not dashboard.opened, "A pagina nova foi construida no mesmo passo da pagina antiga.")
	assert(isolated_content.get_child_count() == 0, "O conteudo antigo nao foi liberado antes da troca.")
	assert(dashboard.vehicle_location_query_queue.is_empty(), "A fila do mapa continuou ativa na transicao.")

	await process_frame
	assert(dashboard.opened and dashboard.current_section == "inventory", "A pagina solicitada nao abriu no quadro seguinte.")
	assert(not dashboard.sidebar_navigation_running, "A navegacao permaneceu bloqueada.")

	dashboard.free()
	await process_frame
	print("SIDEBAR_NAVIGATION_TRANSITION_TEST: OK")
	quit(0)
