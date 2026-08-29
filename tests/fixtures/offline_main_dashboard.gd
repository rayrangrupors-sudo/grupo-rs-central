## Shell principal determinístico: constrói Estoque/Sair sem qualquer integração.
extends "res://src/features/big_map/big_map_tracking_layout.gd"

const Integration := preload("res://src/features/location/vehicle_location_integration.gd")

var offline_external_calls := 0


func _ready() -> void:
	vehicle_location_integration = Integration.new()
	selected_branch_id = "imperatriz"
	selected_branch_name = "Imperatriz"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var app_theme := Theme.new()
	app_theme.default_font = UI_FONT
	app_theme.default_font_size = 18
	theme = app_theme
	_build_ui()


func _load_auth_config() -> Dictionary:
	return {"user": "Operador offline", "salt": "offline", "password_hash": "offline", "version": 1}


func _register_runtime_integrations() -> void:
	pass


func _local_database_sync() -> Node:
	offline_external_calls += 1
	return null


func _inventory_summary_stats() -> Dictionary:
	return {"total": 0, "estoque": 0, "reserva": 0, "instalado": 0, "manutencao": 0, "inativo": 0}


func _filtered_products() -> Array[Dictionary]:
	return []


func _sync_inventory_visible_scope(_products: Array[Dictionary]) -> void:
	pass


func _schedule_sga_status_for_products(_products: Array[Dictionary]) -> void:
	offline_external_calls += 1


func schedule_visible_inventory_device_cycle(_products: Array[Dictionary], _start_index: int, _end_index: int, _total_count: int) -> void:
	offline_external_calls += 1


func _http_get_text(_url: String, _timeout_seconds: float = 15.0) -> Dictionary:
	offline_external_calls += 1
	return {"ok": false, "error": "Rede bloqueada pela fixture offline"}


func _http_get_text_with_headers(_url: String, _headers: PackedStringArray, _timeout_seconds: float = 15.0) -> Dictionary:
	offline_external_calls += 1
	return {"ok": false, "error": "Rede bloqueada pela fixture offline"}


func _http_get_bytes(_url: String) -> Dictionary:
	offline_external_calls += 1
	return {"ok": false, "error": "Rede bloqueada pela fixture offline"}
