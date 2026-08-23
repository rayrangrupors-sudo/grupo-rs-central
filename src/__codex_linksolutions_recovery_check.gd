extends "res://src/inventory_dashboard.gd"

var get_calls := 0
var login_calls := 0


func _ready() -> void:
	var result := await _lookup_linksolutions_sim_data("25854947")
	assert(bool(result.get("ok", false)), "a consulta deveria se recuperar do timeout")
	assert(login_calls == 1, "a sessao deveria ser renovada uma unica vez")
	assert(get_calls == 2, "a consulta deveria repetir somente apos renovar a sessao")
	print("LINKSOLUTIONS_RECOVERY_OK")
	get_tree().quit()


func _http_get_text_with_headers(_url: String, _headers: PackedStringArray, _timeout_seconds: float = 15.0) -> Dictionary:
	get_calls += 1
	if get_calls == 1:
		return {"ok": false, "response_code": 0, "message": "Tempo de conexao esgotado."}
	return {
		"ok": true,
		"response_code": 200,
		"body": JSON.stringify({"iccid": "89555483000025854947", "status__name": "Connected"}),
	}


func _request_linksolutions_login() -> Dictionary:
	login_calls += 1
	return {"ok": true}


func _http_post_json_with_headers(_url: String, _value: Variant, _headers: PackedStringArray, _timeout_seconds: float = 15.0) -> Dictionary:
	return {"ok": false, "response_code": 0, "message": "Tempo de conexao esgotado."}


func _scan_linksolutions_sim_by_iccid_suffix(_suffix: String) -> Dictionary:
	return {"ok": false, "status": "transient", "message": "Tempo de conexao esgotado."}
