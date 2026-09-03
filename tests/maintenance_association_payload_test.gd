extends SceneTree
class Fake extends "res://tests/fixtures/offline_big_map_controller.gd":
	var body:="not-json"
	func _grupo_rs_api_get(_path: String,_retry: bool=true,_force: bool=false) -> Dictionary:
		return {"ok":true,"response_code":200,"body":body}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host:=Fake.new()
	for body in ["not-json","null","{\"success\":false}"]:
		host.body=body
		var result: Dictionary=await host._grupo_rs_api_find_vehicle("TEST123","",true,false)
		assert(not result.ok and not result.get("not_found",false))
	host.body="{\"data\":[]}"
	var empty: Dictionary=await host._grupo_rs_api_find_vehicle("TEST123","",true,false)
	assert(empty.not_found)
	host.free()
	print("ASSOCIATION_PAYLOAD_TEST_PASS")
	quit()
