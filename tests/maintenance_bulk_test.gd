extends SceneTree
const Bulk := preload("res://src/features/big_map/maintenance_bulk.gd")
var failures := 0
class Host extends Node:
	var calls := 0
	var repeat := false
	var missing_meta := false
	func _grupo_rs_api_get(_path: String, _retry: bool, _force: bool) -> Dictionary:
		calls += 1
		return {"ok":true,"body":JSON.stringify({"rows":[{"serial":"same" if repeat else str(calls)}],"page":calls})}
	func _grupo_rs_api_extract_rows(payload: Dictionary) -> Array:
		return payload.rows
	func _grupo_rs_api_equipment_rows(payload: Dictionary) -> Array:
		return payload.rows
	func _grupo_rs_api_normalize_location(raw: Dictionary) -> Dictionary:
		return raw
	func _grupo_rs_api_pagination_state(payload: Dictionary, skip: int, _count: int) -> Dictionary:
		return {"pagination": {} if missing_meta else {"page":payload.page},"has_more":payload.page<2,"next_skip":skip+50}
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var host := Host.new()
	root.add_child(host)
	var progress := func(_endpoint: String, _page: int): pass
	var result := await Bulk.fetch(host,"veiculos",func():return true,progress)
	check(result.get("ok",false) and result.rows.size()==2,"all pages")
	host.calls=0
	host.repeat=true
	result=await Bulk.fetch(host,"veiculos",func():return true,progress)
	check(not result.get("ok",true),"repeated page rejected")
	host.calls=0
	host.repeat=false
	host.missing_meta=true
	result=await Bulk.fetch(host,"veiculos",func():return true,progress)
	check(not result.get("ok",true),"metadata required")
	host.calls=0
	result=await Bulk.fetch(host,"equipamentos",func():return false,progress)
	check(not result.get("ok",true) and host.calls==0,"cancel without HTTP")
	check(Bulk.index([{"serial":"1"},{"serial":"1"}],"serial")["1"].is_empty(),"ambiguous serial rejected")
	host.queue_free()
	print("MAINTENANCE_BULK_TEST failures=%d" % failures)
	quit(1 if failures else 0)
func check(value: bool, label: String) -> void:
	if not value:
		failures+=1
		push_error(label)
