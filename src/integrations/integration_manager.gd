extends Node

signal status_changed(integration_id: String, status: Dictionary)

var _statuses: Dictionary = {}


func update_status(integration_id: String, status: Dictionary) -> void:
	var clean_id := integration_id.strip_edges().to_lower()
	if clean_id == "":
		return
	_statuses[clean_id] = status.duplicate(true)
	status_changed.emit(clean_id, status.duplicate(true))


func get_status(integration_id: String) -> Dictionary:
	var value: Variant = _statuses.get(integration_id.strip_edges().to_lower(), {})
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


func status_snapshot() -> Dictionary:
	return _statuses.duplicate(true)
