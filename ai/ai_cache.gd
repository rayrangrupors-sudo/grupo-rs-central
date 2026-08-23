class_name AICache
extends RefCounted

const MAX_ENTRIES := 50

var _entries: Dictionary = {}
var _ttl_seconds := 1800


func configure(ttl_seconds: int) -> void:
	_ttl_seconds = clampi(ttl_seconds, 60, 86400)
	_prune()


func make_key(question: String, context: Dictionary, model: String) -> String:
	return ("%s|%s|%s" % [question.strip_edges().to_lower(), JSON.stringify(context), model]).sha256_text()


func get_value(key: String) -> Dictionary:
	_prune()
	if not _entries.has(key):
		return {"hit": false}
	var entry := _entries[key] as Dictionary
	return {
		"hit": true,
		"value": entry.get("value"),
		"created_at": int(entry.get("created_at", 0)),
	}


func put(key: String, value: Variant) -> void:
	_prune()
	if _entries.size() >= MAX_ENTRIES and not _entries.has(key):
		var oldest_key := ""
		var oldest_time := Time.get_unix_time_from_system()
		for candidate in _entries:
			var candidate_time := int((_entries[candidate] as Dictionary).get("created_at", 0))
			if candidate_time <= oldest_time:
				oldest_time = candidate_time
				oldest_key = str(candidate)
		if oldest_key != "":
			_entries.erase(oldest_key)
	_entries[key] = {
		"value": value,
		"created_at": int(Time.get_unix_time_from_system()),
	}


func clear() -> void:
	_entries.clear()


func size() -> int:
	_prune()
	return _entries.size()


func _prune() -> void:
	var now := int(Time.get_unix_time_from_system())
	var expired: Array[String] = []
	for key in _entries:
		var created_at := int((_entries[key] as Dictionary).get("created_at", 0))
		if now - created_at > _ttl_seconds:
			expired.append(str(key))
	for key in expired:
		_entries.erase(key)
