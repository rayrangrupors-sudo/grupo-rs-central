extends "res://src/inventory_dashboard.gd"

var test_send_calls := 0
var test_arya_send_ok := true
var test_grupo_rs_send_calls := 0
var test_grupo_rs_send_ok := true
var test_grupo_rs_maintenance_rows: Array[Dictionary] = []
var test_grupo_rs_maintenance_fetch_complete := true
var test_equipment_presence_by_serial: Dictionary = {}
var test_grupo_rs_equipment_rows: Array = []
var test_grupo_rs_equipment_apn := ""
var test_location_button_calls := 0
var test_sms_dialog_calls := 0
var test_notification_calls := 0
var test_notification_message := ""
var test_last_action_serial := ""
var test_location := {
	"ok": true,
	"equipment_serial": "024399999",
	"plate": "TST - 0001",
	"client": "CLIENTE TESTE FLUXO",
	"updated_at": "01/01/2020 00:00:00",
}


func _lookup_grupo_rs_location(_serial: String, _progress_callback: Callable = Callable(), _source_mode: String = "", _fallback_plate: String = "", _fallback_client: String = "") -> Dictionary:
	return test_location.duplicate(true)


func _show_location_lookup(serial: String, _fallback_plate: String = "", _fallback_client: String = "") -> void:
	test_location_button_calls += 1
	test_last_action_serial = serial


func _show_arya_sms_dialog(product: Dictionary) -> void:
	test_sms_dialog_calls += 1
	test_last_action_serial = str(product.get("imei", product.get("serial", "")))


func _resolve_arya_iccid_for_product_cached(_product: Dictionary) -> Dictionary:
	return {"ok": true, "iccid": "8955000000000000000", "apn": "hinova.br"}


func _lookup_arya_inventory_data(_iccid: String) -> Dictionary:
	return {"ok": true, "parsed": {"status": "online", "phone": "5531999999999"}}


func _send_arya_sms(_number: String, _message: String) -> Dictionary:
	test_send_calls += 1
	if not test_arya_send_ok:
		return {"ok": false, "message": "Falha simulada no envio Arya."}
	return {"ok": true}


func _send_grupo_rs_sms_manual_queue(_phone: String, _serial: String, _apn: String, _command: String) -> Dictionary:
	test_grupo_rs_send_calls += 1
	if not test_grupo_rs_send_ok:
		return {"ok": false, "message": "Falha simulada no envio Grupo RS."}
	return {"ok": true}


func _fetch_grupo_rs_equipment_rows(_serial: String) -> Array[Dictionary]:
	await get_tree().process_frame
	var rows: Array[Dictionary] = []
	for row in test_grupo_rs_equipment_rows:
		rows.append(row.duplicate(true))
	return rows


func _fetch_grupo_rs_equipment_apn(equipment: Dictionary) -> String:
	await get_tree().process_frame
	if test_grupo_rs_equipment_apn != "":
		return test_grupo_rs_equipment_apn
	return str(equipment.get("apn", ""))


func _fetch_grupo_rs_maintenance_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in test_grupo_rs_maintenance_rows:
		rows.append(row.duplicate(true))
	return rows


func _fetch_grupo_rs_maintenance_rows_with_status(_require_supported_apn: bool = true) -> Dictionary:
	return {"ok": true, "complete": test_grupo_rs_maintenance_fetch_complete, "rows": _fetch_grupo_rs_maintenance_rows(), "errors": [], "message": ""}


func _fetch_grupo_rs_equipment_presence(serial: String) -> Dictionary:
	var value: Variant = test_equipment_presence_by_serial.get(serial, {"ok": true, "found": false})
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {"ok": false, "found": false}


func _auto_reset_grupo_rs_sms_delay_seconds() -> float:
	return 0.0


func _send_auto_reset_desktop_notification(_title: String, message: String) -> bool:
	test_notification_calls += 1
	test_notification_message = message
	return true


func _log_system_action(_action: String, _details: String = "", _sku: String = "") -> void:
	pass


func _update_auto_reset_feedback(_message: String, _color: Color = Color.TRANSPARENT) -> void:
	pass
