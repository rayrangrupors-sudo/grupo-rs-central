extends "res://src/inventory_dashboard.gd"

var post_calls := 0
var verify_calls := 0


func _modern_grupo_rs_post_form(_path: String, _fields: Dictionary, _referer_path: String = "", _retry_login: bool = true, _max_redirects: int = 8) -> Dictionary:
	post_calls += 1
	await get_tree().process_frame
	return {"ok": false, "message": "Conexao encerrada pelo servidor."}


func _verify_modern_grupo_rs_vehicle_reassignment(_remote_serial: String, new_plate: String, _clear_vehicle_fields: bool = false, _request: Dictionary = {}) -> Dictionary:
	verify_calls += 1
	await get_tree().process_frame
	return {
		"ok": true,
		"after": {
			"plate": new_plate,
			"client": "RS300",
			"vehicle_type": "Carro",
		},
	}
