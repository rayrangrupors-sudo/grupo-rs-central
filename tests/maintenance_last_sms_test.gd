extends SceneTree
const Sidebar=preload("res://src/features/big_map/maintenance_panel.gd")
func _initialize() -> void:
	assert(Sidebar.last_sms([],"024001").contains("Nenhum SMS"))
	assert(Sidebar.last_sms([],"").contains("pendente"))
	var events:=[{"serial":"024001","timestamp":"2026-07-01 10:00:00","status":"Enviado"},{"serial":"024002","timestamp":"2026-09-03 13:00:00","status":"Entregue"},{"serial":"024001","timestamp":"2026-09-01 11:00:00","status":"Aceito"}]
	var text:=Sidebar.last_sms(events,"024001")
	assert(text.contains("01/09/2026") and text.contains("11:00:00") and text.contains("Aceito na fila"))
	assert(not text.contains("Entregue"))
	assert(Sidebar.last_sms([events[0]],"024001").contains("01/07/2026"))
	print("LAST_SMS_TEST_PASS")
	quit()
