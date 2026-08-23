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

	var config: Dictionary = dashboard.call("_branch_config", "imperatriz")
	dashboard.set("selected_branch_id", str(config.get("id", "imperatriz")))
	dashboard.set("selected_branch_name", str(config.get("name", "IMPERATRIZ")))
	dashboard.set("selected_branch_grupo_rs_mode", str(config.get("grupo_rs_mode", "modern")))
	dashboard.set("selected_branch_grupo_rs_base_url", str(config.get("grupo_rs_base_url", "")))
	dashboard.set("selected_branch_grupo_rs_platform_url", str(config.get("grupo_rs_platform_url", "")))

	var results: Array[Dictionary] = []
	results.append(await dashboard.call("_guardian_probe_grupo_rs"))
	results.append(await dashboard.call("_guardian_probe_arya"))
	results.append(await dashboard.call("_guardian_probe_linksolutions"))

	var has_error := false
	for result in results:
		var status := str(result.get("status", "error"))
		if status == "error":
			has_error = true
		print("GUARDIAN_LIVE | %s | %s | %s" % [
			str(result.get("label", "Componente")),
			status,
			str(result.get("message", "")),
		])
	print("GUARDIAN_LIVE_CHECK_%s" % ("ATTENTION" if has_error else "OK"))
	quit(0)
