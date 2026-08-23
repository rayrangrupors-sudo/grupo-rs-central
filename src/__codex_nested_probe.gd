extends SceneTree
func _initialize() -> void:
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	var code := script.reload()
	print("RELOAD=", code)
	print("CONSTANTS=", script.get_script_constant_map())
	quit(0 if code == OK else 1)
