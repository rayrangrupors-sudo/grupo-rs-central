extends SceneTree
const Radio=preload("res://src/features/big_map/maintenance_radio_context.gd")
func _initialize() -> void:
	var loc:={"operator":"VIVO","lat":-5.5,"lng":-47.5}
	var stations:=[{"operator":"VIVO","lat":-5.56,"lng":-47.5},{"operator":"TIM","lat":-5.502,"lng":-47.5}]
	assert(Radio.evaluate(loc,stations).hypothesis)
	assert(not Radio.evaluate(loc,[stations[1]]).hypothesis,"Missing own tower is not proof")
	stations.append({"operator":"VIVO","lat":-5.501,"lng":-47.5})
	assert(not Radio.evaluate(loc,stations).hypothesis)
	loc.operator="Multi Operadora"
	assert(not Radio.evaluate(loc,stations).hypothesis)
	assert(not Radio.evaluate({},stations).hypothesis)
	print("MAINTENANCE_RADIO_CONTEXT_PASS")
	quit()
