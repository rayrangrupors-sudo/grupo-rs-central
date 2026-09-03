extends SceneTree
const Fallback=preload("res://src/features/big_map/maintenance_web_location.gd")
class Fake extends "res://tests/fixtures/offline_big_map_controller.gd":
	var mode:="ok"
	var calls:=0
	func _modern_grupo_rs_read_get(_path: String) -> Dictionary:
		calls+=1
		if _path.contains("clientes_select2"):
			var items:=[{"id":123.0,"text":"Cliente teste"}]
			if mode=="ambiguous": items.append({"id":124,"text":"Cliente teste"})
			return {"ok":true,"body":JSON.stringify({"items":items})}
		assert(_path.contains("cliente=123&"))
		if mode=="sql": return {"ok":true,"body":"{\"erro\":\"sql\"}"}
		var row:={"CodVeiculo":7,"placa":"AAA1234","lat":-5.5,"lng":-47.5,"ignicao":1}
		if mode=="wrong": row.CodVeiculo=8
		if mode=="coordinate": row.lat=999
		var rows:=[row]
		if mode=="duplicate": rows.append(row)
		return {"ok":true,"body":JSON.stringify(rows)}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host:=Fake.new()
	host.selected_branch_grupo_rs_mode="modern"
	host.selected_branch_grupo_rs_base_url="https://novogrupors.ddns.net/cadastro/"
	host.vehicle_location_integration=preload("res://src/features/location/vehicle_location_integration.gd").new()
	var identity:={"client":"Cliente teste","vehicle_id":"7","serial":"024123","plate":"AAA1234"}
	var result: Dictionary=await Fallback.fetch(host,identity,func():return true)
	assert(result.ok)
	for mode in ["ambiguous","wrong","coordinate","duplicate","sql"]:
		host.mode=mode
		result=await Fallback.fetch(host,identity,func():return true)
		assert(not result.ok)
	var calls:=host.calls
	result=await Fallback.fetch(host,identity,func():return false)
	assert(not result.ok and host.calls==calls)
	host.mode="ok"
	result=await Fallback.fetch(host,identity,func():return host.calls==calls)
	assert(not result.ok and host.calls==calls+1)
	host.free()
	print("WEB_LOCATION_TEST_PASS")
	quit()
