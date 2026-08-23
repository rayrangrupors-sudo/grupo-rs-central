extends RefCounted


func get_summary(store: RefCounted) -> Dictionary:
	if store == null or not store.has_method("get_tracker_stats"):
		return {}
	return store.call("get_tracker_stats")


func get_diagnostics(store: RefCounted) -> Array:
	if store == null or not store.has_method("get_diagnostics"):
		return []
	return store.call("get_diagnostics")
