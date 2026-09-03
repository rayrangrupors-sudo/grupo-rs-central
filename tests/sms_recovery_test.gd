extends SceneTree

class Probe extends "res://src/inventory_dashboard.gd":
	var calls := 0
	func _ready() -> void: pass
	func _grupo_rs_api_find_location(_serial: String, _plate: String, _vehicle_id: String = "", _allow_full_scan: bool = true, _take_size: int = 50) -> Dictionary:
		calls += 1
		return {"ok":true,"location":{"updated_at":"2026-09-03 12:%s:00" % ("10" if calls == 1 else "20"),"ignition":"ligado"}}

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var host := Probe.new()
	root.add_child(host)
	host.content_area = MarginContainer.new()
	host.add_child(host.content_area)
	host.current_section = "sms_panel"
	host.sms_panel_events.append({"id":"sms-1","serial":"024000101","plate":"ABC1D23","origin":"Mapa Grande · manual","timestamp":"2026-09-03 12:00:00","recovery_status":"pending","recovery_checked_at":0})
	await host._sms_recovery_check_pending()
	assert(host.sms_panel_events[0].recovery_status == "observing")
	host.sms_panel_events[0].recovery_checked_at = 0
	await host._sms_recovery_check_pending()
	assert(host.sms_panel_events[0].recovery_status == "normalized")
	host.sms_panel_events[0].recovery_checked_at = 0
	await host._sms_recovery_check_pending()
	assert(host.calls == 2, "Caso normalizado foi consultado novamente.")
	host._open_sms_recovery_report()
	await process_frame
	assert(host.sms_recovery_report_open)
	assert(host.content_area.find_child("SmsPanelView",true,false) != null)
	host.current_section = "inventory"
	host.sms_panel_events.append({"id":"sms-2","serial":"024000102","plate":"DEF4G56","timestamp":"2026-09-03 12:00:00","recovery_status":"pending","recovery_checked_at":0})
	await host._sms_recovery_check_pending()
	assert(host.calls == 2, "Consulta rodou fora do Painel SMS.")
	host.free()
	print("SMS_RECOVERY_TEST: OK")
	quit()
