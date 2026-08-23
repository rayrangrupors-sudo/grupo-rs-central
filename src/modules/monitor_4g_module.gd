extends RefCounted

const MonitorScript := preload("res://src/smart_4g_monitor.gd")


func create_analyzer() -> RefCounted:
	return MonitorScript.new()
