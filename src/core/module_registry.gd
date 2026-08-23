extends Node

const AuthModule := preload("res://src/modules/auth_module.gd")
const StockModule := preload("res://src/modules/stock_module.gd")
const Monitor4GModule := preload("res://src/modules/monitor_4g_module.gd")
const SmsModule := preload("res://src/modules/sms_module.gd")

var _modules: Dictionary = {}


func _ready() -> void:
	register_module("auth", AuthModule.new())
	register_module("stock", StockModule.new())
	register_module("monitor_4g", Monitor4GModule.new())
	register_module("sms", SmsModule.new())


func register_module(module_id: String, module: RefCounted) -> void:
	var clean_id := module_id.strip_edges().to_lower()
	if clean_id == "" or module == null:
		return
	_modules[clean_id] = module


func get_module(module_id: String) -> RefCounted:
	return _modules.get(module_id.strip_edges().to_lower()) as RefCounted


func module_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for module_id in _modules:
		result.append(str(module_id))
	result.sort()
	return result
