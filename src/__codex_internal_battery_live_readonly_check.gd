extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := load("res://src/inventory_dashboard.gd")
	var store_script := load("res://src/inventory_store.gd")
	if dashboard_script == null or store_script == null:
		push_error("Dependencias do teste de Bat. Int nao carregaram.")
		quit(1)
		return

	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_name", "IMPERATRIZ")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")

	var store: InventoryStore = store_script.new()
	store.configure("user://inventory_db.json", "inventory_db.json", "user://backups", false)
	store.load_db()
	dashboard.set("store", store)

	var candidates: Array[Dictionary] = []
	for product in store.get_products("", "all", false):
		if typeof(product) != TYPE_DICTIONARY:
			continue
		var item := product as Dictionary
		var serial := _digits_only(str(item.get("imei", item.get("sku", ""))))
		if serial.begins_with("024") and serial.length() == 9 and str(item.get("plate", "")).strip_edges() != "" and str(item.get("tracker_status", item.get("status", ""))).to_lower() == "instalado":
			candidates.append(item)
		if candidates.size() >= 8:
			break

	if candidates.is_empty():
		_fail(dashboard, "Nao ha aparelhos instalados 024 na base local para testar Bat. Int ao vivo.")
		return

	var checked := 0
	var endpoint_no_data := false
	var errors: Array[String] = []
	for product in candidates:
		checked += 1
		var result: Dictionary = await dashboard.call("_lookup_grupo_rs_internal_battery", product, {})
		if bool(result.get("ok", false)):
			print("INTERNAL_BATTERY_LIVE_READONLY_CHECK_OK percent=%d checked=%d" % [int(result.get("percent", -1)), checked])
			dashboard.queue_free()
			await process_frame
			quit(0)
			return
		var message := str(result.get("message", ""))
		errors.append("%s: %s" % [str(product.get("imei", product.get("sku", ""))), message])
		if message.contains("Nenhum registro recente de bateria") or message.contains("Os registros nao retornaram Bat. Int"):
			endpoint_no_data = true
			break

	if endpoint_no_data:
		print("INTERNAL_BATTERY_LIVE_READONLY_CHECK_OK no_data=true checked=%d" % checked)
		dashboard.queue_free()
		await process_frame
		quit(0)
		return

	_fail(dashboard, "Bat. Int ao vivo nao confirmou endpoint de registros. Erros: %s" % " | ".join(errors))


func _digits_only(value: String) -> String:
	var result := ""
	for i in range(value.length()):
		var code := value.unicode_at(i)
		if code >= 48 and code <= 57:
			result += value.substr(i, 1)
	return result


func _fail(dashboard: Node, message: String) -> void:
	if is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)
