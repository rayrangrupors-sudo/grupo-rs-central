extends SceneTree

class Probe extends "res://src/features/big_map/big_map_tracking_layout.gd":
	var calls := 0
	func _ready() -> void:
		pass
	func _fetch_vehicle_location_api_rows_smart(_query: String = "") -> Dictionary:
		calls += 1
		await get_tree().create_timer(0.05).timeout
		return {"ok": true, "rows": []}
	func _apply_vehicle_location_filters() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var host := Probe.new()
	host.vehicle_location_integration = preload("res://src/features/location/vehicle_location_integration.gd").new()
	root.add_child(host)
	host.current_section = "vehicle_location"
	host.vehicle_location_pending_queries.assign(["ABC-1234", "DEF-5678"])
	host._refresh_vehicle_location_view()
	assert(host.calls == 1)
	host._set_page_context("inventory", "Estoque")
	await create_timer(0.2).timeout
	assert(host.calls == 1, "Resposta atrasada iniciou outra consulta fora do mapa.")
	assert(host.vehicle_location_pending_queries.is_empty())
	await host._refresh_vehicle_location_view()
	assert(host.calls == 1, "Consulta direta foi aceita fora do mapa.")
	host.current_section = "vehicle_location"
	host.vehicle_location_pending_queries.assign(["ABC-1234"])
	await host._refresh_vehicle_location_view()
	assert(host.calls == 2, "Consulta nao voltou a funcionar ao reabrir o mapa.")
	host.free()
	print("MAP_PAGE_STOP_REGRESSION_TEST: OK")
	quit(0)
