extends SceneTree

class Probe extends "res://src/inventory_dashboard.gd":
	func _ready() -> void:
		pass
	func _sms_recovery_check_pending() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var host := Probe.new()
	host.selected_branch_id = "imperatriz"
	root.add_child(host)
	host.content_area = MarginContainer.new()
	host.add_child(host.content_area)
	host.experttexting_last_sync_at = int(Time.get_unix_time_from_system())
	for index in range(8):
		host.sms_panel_events.append({"serial":"02400010%d" % index,"status":"Aceito" if index < 7 else "Falho","origin":"Programa" if index < 7 else "Mapa Grande · manual","timestamp":"2026-09-03 12:00:00","message_id":"TEST-%d" % index,"price":0.02})
	host._show_sms_panel()
	await process_frame
	assert(host.content_area.find_child("SmsHistoryRows",true,false).get_child_count() == 6)
	var next: Button
	for control in host.content_area.find_children("*","Button",true,false):
		if control.text == "›": next=control
	assert(next != null and not next.disabled)
	next.pressed.emit()
	await process_frame
	assert(host.sms_panel_page == 1)
	assert(host.content_area.find_child("SmsHistoryRows",true,false).get_child_count() == 2)
	host.sms_panel_status_filter = "Falho"
	host.sms_panel_origin_filter = "Mapa Grande · manual"
	host._show_sms_panel()
	await process_frame
	assert(host.sms_panel_page == 0)
	assert(host._sms_panel_events_filtered().size() == 1)
	host.sms_panel_search_filter = "missing"
	host._show_sms_panel()
	await process_frame
	assert(host._sms_panel_events_filtered().is_empty())
	host._clear_sms_panel_filters()
	await process_frame
	assert(host._sms_panel_events_filtered().size() == 8)
	var search: LineEdit = host.content_area.find_child("SmsHistorySearch",true,false)
	search.text_submitted.emit("TEST-7")
	await process_frame
	assert(host._sms_panel_events_filtered().size() == 1)
	host.free()
	print("SMS_PANEL_LAYOUT_TEST: OK")
	quit()
