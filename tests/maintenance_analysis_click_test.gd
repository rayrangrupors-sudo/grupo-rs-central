extends SceneTree
class Controller extends "res://tests/fixtures/offline_big_map_controller.gd":
	var hang_chip := false
	func _maintenance_analysis_timeout_seconds() -> float:
		return 0.1
	func _maintenance_history_task(_location: Dictionary, state: Dictionary) -> void:
		await get_tree().create_timer(0.02).timeout
		state.records = [{"battery_voltage":"5","ignition":1}]
		state.note = "Histórico de teste."
		state.history_done = true
	func _maintenance_chip_task(_location: Dictionary, state: Dictionary) -> void:
		if not hang_chip:
			state.chip = {"status":"online"}
			state.chip_done = true
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var controller := Controller.new()
	controller.vehicle_location_integration = preload("res://src/features/location/vehicle_location_integration.gd").new()
	var view: Control = controller._build_vehicle_location_view()
	root.add_child(controller)
	controller.add_child(view)
	await process_frame
	controller.maintenance_mode = true
	var row := {"maintenance":true,"serial":"test","plate":"TEST","ignition":1}
	controller.vehicle_location_selected = row
	controller._render_vehicle_location_details(row)
	var button: Button=controller.vehicle_location_details_body.find_child("MaintenanceAnalyze",true,false)
	check(button != null,"button exists")
	button.pressed.emit()
	await create_timer(0.2).timeout
	check(not controller.maintenance_analysis_busy,"click finished")
	check(str(controller.maintenance_reports.get("test","")).contains("abaixo de 9 V"),"diagnosis from click")
	var visible_report := false
	for child in controller.vehicle_location_details_body.find_children("*","Label",true,false):
		if child is Label and child.text.contains("abaixo de 9 V"):
			visible_report = visible_report or (child.visible and child.text.length() < 400)
	check(visible_report,"compact visible report")
	check(controller.vehicle_location_details_body.find_child("MaintenanceSms", true, false) != null,"online exposes SMS icon")
	check(controller._tracking_row_matches_filter({"ignition":1},"Última ignição ligada"),"on filter")
	check(not controller._tracking_row_matches_filter({"ignition":0},"Última ignição ligada"),"on filter excludes off")
	check(not controller._tracking_row_matches_filter({},"Última ignição desligada"),"unknown is not off")
	controller.hang_chip = true
	await controller._analyze_maintenance(row)
	check(not controller.maintenance_analysis_busy,"timeout releases button")
	check(controller.maintenance_reports.test.contains("chip não concluiu"),"partial result on chip timeout")
	check(controller.vehicle_location_details_body.find_child("MaintenanceSms", true, false) == null,"unavailable hides SMS")
	controller.queue_free()
	await process_frame
	print("MAINTENANCE_ANALYSIS_CLICK_TEST failures=%d" % failures)
	quit(1 if failures else 0)
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
