class_name LocalSQLiteBridge
extends RefCounted

const SERVICE_PATH := "res://tools/local_sqlite_service.py"
var last_error := ""

func execute(operation: String, database_path: String, request: Dictionary = {}) -> Dictionary:
	last_error = ""
	var python := _find_python()
	if python == "": return _failure("Runtime Python com SQLite nao encontrado.")
	var token := "%s_%s" % [Time.get_ticks_msec(), randi()]
	var request_path := ProjectSettings.globalize_path("user://sqlite_request_%s.json" % token)
	var response_path := ProjectSettings.globalize_path("user://sqlite_response_%s.json" % token)
	var file := FileAccess.open(request_path, FileAccess.WRITE)
	if file == null: return _failure("Nao foi possivel preparar a transacao SQLite.")
	file.store_string(JSON.stringify(request)); file = null
	var output: Array = []
	var args := PackedStringArray([ProjectSettings.globalize_path(SERVICE_PATH), operation, ProjectSettings.globalize_path(database_path), request_path, response_path])
	var exit_code := OS.execute(python, args, output, true, false)
	var result: Dictionary = {}
	if FileAccess.file_exists(response_path):
		var response := FileAccess.open(response_path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(response.get_as_text()) if response != null else null
		if typeof(parsed) == TYPE_DICTIONARY: result = parsed
	DirAccess.remove_absolute(request_path); DirAccess.remove_absolute(response_path)
	if result.is_empty(): return _failure("Falha SQLite (codigo %s): %s" % [exit_code, " ".join(output)])
	if not bool(result.get("ok", false)): last_error = str(result.get("error", "Falha SQLite."))
	return result

func _failure(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "error": message}

func _find_python() -> String:
	var configured := OS.get_environment("GRUPO_RS_PYTHON").strip_edges()
	var bundled := "C:/GRUPO RS CENTRAL/runtime/python/python.exe"
	if not OS.has_feature("editor"):
		bundled = OS.get_executable_path().get_base_dir().path_join("runtime/python/python.exe")
	for candidate in PackedStringArray([configured, bundled, "C:/GRUPO RS CENTRAL/runtime/python/python.exe", "python.exe", "python"]):
		if candidate == "": continue
		if candidate.contains("/") or candidate.contains("\\"):
			if FileAccess.file_exists(candidate): return candidate
		else:
			var output: Array = []
			if OS.execute("where.exe", PackedStringArray([candidate]), output, true, false) == 0: return candidate
	return ""
