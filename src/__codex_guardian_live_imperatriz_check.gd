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

	dashboard.call("_select_branch", "imperatriz")
	await process_frame
	dashboard.call("_open_selected_branch")
	await process_frame
	await process_frame

	var guardian: Variant = dashboard.get("system_guardian")
	if guardian == null or not is_instance_valid(guardian):
		push_error("Assistente autonomo nao iniciou.")
		dashboard.queue_free()
		await process_frame
		quit(1)
		return

	var snapshot: Dictionary = await guardian.call("run_now", "test")
	var bad_components: Array[String] = []
	for raw_component in snapshot.get("components", []):
		if typeof(raw_component) != TYPE_DICTIONARY:
			continue
		var component := raw_component as Dictionary
		var status := str(component.get("status", ""))
		if status == "error" or status == "warning":
			bad_components.append("%s=%s:%s" % [
				str(component.get("id", "")),
				status,
				str(component.get("message", "")),
			])

	if not bad_components.is_empty():
		push_error("Assistente ainda encontrou alerta/falha: %s" % " | ".join(bad_components))
		dashboard.queue_free()
		await process_frame
		quit(1)
		return

	dashboard.queue_free()
	await process_frame
	print("GUARDIAN_LIVE_IMPERATRIZ_CHECK_OK")
	quit(0)
