extends SceneTree
const Loader=preload("res://src/features/big_map/maintenance_plate_loader.gd")
const Binding=preload("res://src/features/big_map/maintenance_binding.gd")
class Fake extends "res://tests/fixtures/offline_big_map_controller.gd":
	var attempts:={}
	var active:=0
	var peak:=0
	var fail_once:=true
	var bind_calls:=0
	var bind_mode:="ok"
	func _modern_grupo_rs_read_get(_path: String) -> Dictionary:
		return {"ok":true,"body":"<tbody></tbody>"}
	func _parse_dashboard_communication_rows(_html: String,_interval: String) -> Array[Dictionary]:
		var rows: Array[Dictionary]=[]
		for i in range(12): rows.append({"plate":"TEST-%03d"%i,"serial":"024%03d"%i,"client":"Cliente teste"})
		return rows
	func _grupo_rs_api_get(path: String,_retry: bool=true,_force: bool=false) -> Dictionary:
		assert(path.contains("localizacao.php"))
		var plate:=path.split("q=")[1].split("&")[0].uri_decode()
		attempts[plate]=int(attempts.get(plate,0))+1
		active+=1
		peak=maxi(peak,active)
		await get_tree().create_timer(0.01).timeout
		active-=1
		if fail_once and plate=="TEST-000" and attempts[plate]==1: return {"ok":false,"response_code":0}
		var index:=int(plate.right(3))
		return {"ok":true,"body":JSON.stringify({"data":[{"CodVeiculo":index+1,"Placa":plate,"Latitude":-5.5,"Longitude":-47.5,"StatusIgnicao":index%2,"DataEvento":"2026-09-03 12:00:00"}]})}
	func _grupo_rs_api_find_vehicle(plate: String="",_serial: String="",_force: bool=true,_scan: bool=true) -> Dictionary:
		bind_calls+=1
		await get_tree().create_timer(0.04).timeout
		if bind_mode=="missing": return {"ok":false,"not_found":true}
		if bind_mode=="error": return {"ok":false,"response_code":0}
		var index:=int(plate.right(3))
		return {"ok":true,"row":{"vehicle_id":str(index+1),"plate":plate,"serial":"WRONG" if bind_mode=="conflict" else "024%03d"%index}}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host:=Fake.new()
	host.vehicle_location_integration=preload("res://src/features/location/vehicle_location_integration.gd").new()
	root.add_child(host)
	var loader:=Loader.new()
	await loader.start(host)
	assert(loader.processed==12 and loader.rows.size()==12 and loader.failures==0)
	assert(host.peak<=5 and loader.policy.limit==2 and loader.policy.retries==1)
	assert(host.bind_calls==0 and loader.request_count==13)
	var seen:={}
	for row in loader.rows:
		assert(not seen.has(row.plate))
		seen[row.plate]=true
		assert(not row.has("serial") and row.binding_state=="pending")
	var snapshot: Dictionary=loader.rows[0]
	var bound: Dictionary=await Binding.resolve(host,snapshot)
	assert(bound.binding_state=="confirmed" and bound.client=="Cliente teste")
	assert(bound.lat==snapshot.lat and bound.updated_at==snapshot.updated_at)
	for mode in ["missing","error","conflict"]:
		host.bind_mode=mode
		bound=await Binding.resolve(host,snapshot)
		assert(bound.binding_state==("not_found" if mode=="missing" else mode))
	# Delayed first selection must not replace the newer selection.
	host.bind_mode="ok"
	var view: Control=host._build_vehicle_location_view()
	host.add_child(view)
	host.maintenance_mode=true
	host.vehicle_location_selected=loader.rows[0]
	host._request_maintenance_binding(loader.rows[0])
	await create_timer(0.17).timeout
	host.vehicle_location_selected=loader.rows[1]
	host._request_maintenance_binding(loader.rows[1])
	await create_timer(0.4).timeout
	assert(host.vehicle_location_selected.plate==loader.rows[1].plate)
	assert(host.vehicle_location_selected.binding_state=="confirmed")
	# Analysis and SMS cannot start with an unconfirmed association.
	host._analyze_maintenance(snapshot)
	assert(not host.maintenance_analysis_busy)
	host._review_maintenance_sms(snapshot)
	loader.start(host)
	loader.cancel()
	await create_timer(0.1).timeout
	assert(not loader.running)
	loader.host=null
	host.queue_free()
	await process_frame
	print("MAINTENANCE_LAZY_FLOW_TEST_PASS")
	quit()
