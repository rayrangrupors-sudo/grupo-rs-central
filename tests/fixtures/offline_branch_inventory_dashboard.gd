extends "res://src/inventory_dashboard.gd"

var offline_firebase_sync: Node
var offline_dashboard_refreshes := 0
var offline_table_refreshes := 0
var offline_operational_cycle_starts := 0


func _ready() -> void:
	pass


func _firebase_sync() -> Node:
	return offline_firebase_sync


func _show_dashboard() -> void:
	current_section = "dashboard"
	offline_dashboard_refreshes += 1


func _refresh_table() -> void:
	offline_table_refreshes += 1


func _on_firebase_status_changed(status: Dictionary) -> void:
	online_data_available = bool(status.get("data_available", false))


func _start_visible_inventory_device_cycle(_products: Array[Dictionary], _signature: String, _generation: int) -> void:
	offline_operational_cycle_starts += 1
