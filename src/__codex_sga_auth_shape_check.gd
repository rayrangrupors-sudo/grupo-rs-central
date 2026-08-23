extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")
const SGA_API_BASE_URL := "https://api.hinova.com.br/api/sga/v2"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	for source in ["rastreio", "protecao"]:
		var credentials: Dictionary = dashboard.call("_sga_credentials", source)
		var response: Dictionary = await dashboard.call(
			"_http_post_json_with_headers",
			"%s/usuario/autenticar" % SGA_API_BASE_URL,
			{
				"usuario": str(credentials.get("username", "")),
				"senha": str(credentials.get("password", "")),
			},
			PackedStringArray([
				"User-Agent: GrupoRSCentral/1.0",
				"Accept: application/json",
				"Content-Type: application/json",
				"Authorization: Bearer %s" % str(credentials.get("api_token", "")),
			])
		)
		var parsed: Variant = JSON.parse_string(str(response.get("body", "")))
		var api_error := {}
		if typeof(parsed) == TYPE_DICTIONARY and typeof((parsed as Dictionary).get("error", null)) == TYPE_DICTIONARY:
			api_error = (parsed as Dictionary).get("error", {})
		print("SGA_AUTH_SHAPE_%s ok=%s response_code=%d shape=%s" % [
			source.to_upper(),
			str(response.get("ok", false)),
			int(response.get("response_code", 0)),
			JSON.stringify(_shape(parsed)),
		])
		if not api_error.is_empty():
			print("SGA_AUTH_ERROR_%s code=%s message=%s" % [
				source.to_upper(),
				str(api_error.get("codigo_erro", "")),
				str(api_error.get("mensagem", "")),
			])
	dashboard.queue_free()
	await process_frame
	quit(0)


func _shape(value: Variant, depth: int = 0) -> Variant:
	if depth >= 5:
		return "depth-limit"
	if typeof(value) == TYPE_DICTIONARY:
		var result := {}
		for key in value:
			result[str(key)] = _shape((value as Dictionary).get(key), depth + 1)
		return result
	if typeof(value) == TYPE_ARRAY:
		var array := value as Array
		return {
			"type": "array",
			"size": array.size(),
			"first": _shape(array[0], depth + 1) if not array.is_empty() else null,
		}
	if typeof(value) == TYPE_STRING:
		return "string(%d)" % str(value).length()
	return type_string(typeof(value))
