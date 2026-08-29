extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _init() -> void:
	var dashboard = DashboardScript.new()
	var rows: Array[Dictionary] = [
		{"sku": "SEM-1", "installed_at": ""},
		{"sku": "ANTIGO", "installed_at": "2025-01-10T08:00:00"},
		{"sku": "RECENTE", "installed_at": "2026-08-29T11:30:00"},
		{"sku": "SEM-2", "installed_at": "Não informada"},
		{"sku": "INTERMEDIARIO", "installed_at": "2026-07-15T18:45:12"},
	]
	rows.sort_custom(dashboard._inventory_installation_is_newer)
	var order: Array[String] = []
	for row in rows:
		order.append(str(row.get("sku", "")))
	var expected: Array[String] = ["RECENTE", "INTERMEDIARIO", "ANTIGO", "SEM-1", "SEM-2"]
	if order != expected:
		push_error("Ordem incorreta: %s" % str(order))
		quit(1)
		return
	print("PASS: recentes primeiro e registros sem data no final: %s" % str(order))
	quit(0)
