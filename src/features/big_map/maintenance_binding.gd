## Resolve one selected plate. Preserve snapshot coordinates and timestamp.
extends RefCounted
static func resolve(host: Node, snapshot: Dictionary) -> Dictionary:
	var result:=snapshot.duplicate(true)
	var response: Dictionary=await host._grupo_rs_api_find_vehicle(str(snapshot.get("plate","")),"",true,false)
	if not response.get("ok",false):
		result.binding_state="not_found" if response.get("not_found",false) else ("ambiguous" if response.has("rows") else "error")
		return result
	var vehicle: Dictionary=response.get("row",{})
	var serial:=str(vehicle.get("serial",""))
	var members: Array=snapshot.get("maintenance_members",[])
	var expected:={}
	for member in members:
		var value:=str(member.get("serial",""))
		if value!="": expected[value]=member
	if host._normalize_location_plate(str(vehicle.get("plate","")))!=host._normalize_location_plate(str(snapshot.get("plate",""))) or str(vehicle.get("vehicle_id",""))!=str(snapshot.get("vehicle_id","")):
		result.binding_state="conflict"
		return result
	if serial=="": result.binding_state="not_found"; return result
	if expected.size()!=1 or not expected.has(serial): result.binding_state="conflict"; return result
	result.serial=serial
	result.client=str(vehicle.get("client",""))
	if result.client=="":
		result.client=str(expected[serial].get("client",""))
		result.client_source="Lista web · série e veículo confirmados"
	result.binding_state="confirmed"
	return result
