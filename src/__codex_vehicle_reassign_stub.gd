extends "res://src/inventory_dashboard.gd"

var test_events: Array[String] = []
var test_fail_stage := ""


func _grupo_rs_api_reads_enabled() -> bool:
	# Este stub valida o fluxo web sem depender das credenciais/API locais.
	return false


func _prepare_modern_vehicle_reassignment(request: Dictionary) -> Dictionary:
	test_events.append("prepare_modern")
	await get_tree().process_frame
	if test_fail_stage == "prepare_modern":
		return {"ok": false, "message": "Falha simulada na preparacao."}
	var prepared := request.duplicate(true)
	prepared["ok"] = true
	return prepared


func _preflight_legacy_grupo_rs_reassignment(_serial: String) -> Dictionary:
	test_events.append("prepare_legacy")
	await get_tree().process_frame
	if test_fail_stage == "prepare_legacy":
		return {"ok": false, "message": "Falha simulada no sistema antigo."}
	return {"ok": true, "exists": true}


func _update_modern_grupo_rs_vehicle_reassignment(_prepared: Dictionary) -> Dictionary:
	test_events.append("update_modern")
	await get_tree().process_frame
	if test_fail_stage == "update_modern":
		return {"ok": false, "message": "Falha simulada na atualizacao moderna."}
	return {"ok": true}


func _rollback_modern_grupo_rs_vehicle_reassignment(_prepared: Dictionary) -> Dictionary:
	test_events.append("rollback_modern")
	await get_tree().process_frame
	if test_fail_stage == "rollback_modern":
		return {"ok": false, "message": "Falha simulada na restauracao moderna."}
	return {"ok": true, "message": "Restauracao simulada concluida."}


func _clear_legacy_grupo_rs_equipment_events(_serial: String, _stage_callback: Callable = Callable()) -> Dictionary:
	test_events.append("clear_legacy_events")
	await get_tree().process_frame
	if test_fail_stage == "clear_legacy_events":
		return {"ok": false, "message": "Falha simulada na limpeza de eventos."}
	return {"ok": true}


func _finalize_local_vehicle_reassignment(_request: Dictionary) -> Dictionary:
	test_events.append("finalize_local")
	if test_fail_stage == "finalize_local":
		return {"ok": false, "message": "Falha simulada no cadastro local."}
	return {"ok": true}


func _log_system_action(_action: String, _details: String = "", _sku: String = "") -> void:
	pass
