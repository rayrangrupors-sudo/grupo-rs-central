extends SceneTree
const Loader=preload("res://src/features/big_map/maintenance_loader.gd")
class Fake extends "res://tests/maintenance_web_location_test.gd".Fake:
	func _parse_dashboard_communication_rows(_html: String,_status: String) -> Array[Dictionary]:
		return [{"serial":"024123","client":"Cliente teste"}]
	func _legacy_select_options(_html: String,_name: String) -> Array[Dictionary]: return []
	func _modern_grupo_rs_read_get(path: String) -> Dictionary:
		if path.contains("intervalo") or path.contains("equipamentos_editar"):
			return {"ok":true,"body":"<tbody></tbody>"}
		return await super._modern_grupo_rs_read_get(path)
	func _grupo_rs_api_find_vehicle(_plate: String="",_serial: String="",_force: bool=true,_scan: bool=true) -> Dictionary:
		return {"ok":true,"row":{"serial":"024123","vehicle_id":"7","plate":"AAA1234"}}
	func _grupo_rs_api_find_equipment(_serial: String,_force: bool=true) -> Dictionary:
		return {"ok":true,"row":{"serial":"024123"}}
	func _grupo_rs_api_find_location(_serial: String,_plate: String,_id: String="",_scan: bool=true,_take: int=50) -> Dictionary:
		return {"ok":false,"location":{}}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host:=Fake.new()
	host.selected_branch_grupo_rs_mode="modern"
	host.selected_branch_grupo_rs_base_url="https://novogrupors.ddns.net/cadastro/"
	host.vehicle_location_integration=preload("res://src/features/location/vehicle_location_integration.gd").new()
	root.add_child(host)
	var loader:=Loader.new()
	await loader.start(host)
	assert(loader.processed==1 and loader.failures==0)
	assert(loader.rows[0].has("location_source"))
	assert(host._vehicle_location_has_valid_coordinates(loader.rows[0]))
	assert(loader.counts()["Ignição ligada"]==1)
	assert(host.calls==2)
	host.mode="wrong"
	await loader.start(host)
	assert(loader.failures==1 and not host._vehicle_location_has_valid_coordinates(loader.rows[0]))
	loader.host=null
	host.queue_free()
	await process_frame
	print("HYBRID_LOADER_TEST_PASS")
	quit()
