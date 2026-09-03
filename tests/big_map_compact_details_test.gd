extends SceneTree

const Layout := preload("res://src/features/big_map/big_map_tracking_layout.gd")
const TrackingView := preload("res://src/features/big_map/big_map_tracking_view.gd")
const LocationIntegration := preload("res://src/features/location/vehicle_location_integration.gd")

class Probe extends Layout:
	func _ready() -> void: pass

func _initialize() -> void: call_deferred("run")

func labels_in(root: Node) -> Array[String]:
	var values: Array[String] = []
	for label in root.find_children("*","Label",true,false):
		if label.is_visible_in_tree(): values.append(str(label.text))
	return values

func run() -> void:
	var host := Probe.new()
	root.add_child(host)
	var view := TrackingView.new()
	host.add_child(view)
	host.tracking_view = view
	host.vehicle_location_details_body = view.details_body
	host.vehicle_location_map_canvas = view.map_canvas
	host.vehicle_location_integration = LocationIntegration.new()
	var vehicle := {"plate":"ABC1D23","serial":"024000001","client":"CLIENTE TESTE","speed":0,"updated_at":"2026-09-03 14:00:00","lat":-5.49,"lng":-47.46,"ignition":1,"nearby_tower_count":11,"source":"API oficial"}
	host._render_vehicle_location_details(vehicle)
	var visible := labels_in(view.details_body)
	assert(visible.has("Série") and visible.has("Cliente") and visible.has("Última comunicação"))
	assert(not visible.has("Coordenadas"),"Coordenadas deveriam iniciar recolhidas.")
	var vehicle_toggle: CheckButton
	for toggle in view.details_body.find_children("*","CheckButton",true,false): vehicle_toggle=toggle
	assert(vehicle_toggle != null and vehicle_toggle.text == "Ver detalhes técnicos")
	vehicle_toggle.button_pressed = true
	assert(labels_in(view.details_body).has("Coordenadas"))
	host.tracking_reference_vehicle = vehicle
	var station := {"id":"1012586321","city":"Imperatriz - MA","uf":"MA","provider_name":"TIM","technologies":["LTE"],"generation":"4G","status":"Licenciada","lat":-5.50,"lng":-47.47,"bands":["1800"],"entity":"TIM S A"}
	host._render_tracking_station_details(station)
	visible = labels_in(view.details_body)
	assert(visible.has("Operadora") and visible.has("TIM") and visible.has("LTE") and visible.has("Tecnologia · 4G"))
	assert(visible.has("●  Licenciada"))
	assert(visible.has("Imperatriz - MA · MA"))
	assert(not visible.has("Entidade"),"Detalhes cadastrais deveriam iniciar recolhidos.")
	var station_toggle: CheckButton
	for toggle in view.details_body.find_children("*","CheckButton",true,false): station_toggle=toggle
	assert(station_toggle != null and station_toggle.text == "Ver detalhes técnicos")
	station_toggle.button_pressed = true
	assert(labels_in(view.details_body).has("Entidade"))
	host.free()
	print("BIG_MAP_COMPACT_DETAILS_TEST: OK")
	quit()
