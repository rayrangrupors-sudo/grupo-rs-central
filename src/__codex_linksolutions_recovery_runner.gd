extends SceneTree


func _init() -> void:
	var probe: Node = load("res://src/__codex_linksolutions_recovery_check.gd").new()
	root.add_child(probe)
