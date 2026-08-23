extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/estoque_profissional.tscn")
	if scene == null:
		push_error("Cena principal nao carregou.")
		quit(1)
		return
	var dashboard: Node = scene.instantiate()
	root.add_child(dashboard)
	await process_frame
	var response: Dictionary = await dashboard.call("_grupo_rs_api_get", "/endpoints/localizacao.php", true, true)
	var body := str(response.get("body", ""))
	var payload: Variant = JSON.parse_string(body)
	var rows: Array = await dashboard.call("_grupo_rs_api_extract_rows", payload)
	print("LOCATION_KEYS=", str((payload as Dictionary).keys()) if typeof(payload) == TYPE_DICTIONARY else "not-dict")
	print("LOCATION_ROWS=", str(rows.size()))
	for raw in rows.slice(0, min(rows.size(), 3)):
		print("LOCATION_RAW=", str(raw))
		print("LOCATION_NORMALIZED=", str(await dashboard.call("_grupo_rs_api_normalize_location", raw)))
	print("LOCATION_RESPONSE=", body.substr(0, 6000))
	quit(0)
