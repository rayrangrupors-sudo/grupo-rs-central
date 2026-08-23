extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := load("res://src/inventory_dashboard.gd")
	if dashboard_script == null:
		push_error("Dashboard nao carregou.")
		quit(1)
		return
	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame

	var serial := OS.get_environment("CODEX_REASSIGN_TEST_SERIAL").strip_edges()
	var plate := OS.get_environment("CODEX_REASSIGN_TEST_PLATE").strip_edges()
	if plate == "" and serial != "":
		var equipment_rows: Array[Dictionary] = await dashboard.call("_fetch_modern_grupo_rs_equipment_rows", serial)
		var equipment: Dictionary = dashboard.call("_choose_grupo_rs_equipment_row", equipment_rows, serial)
		plate = str(equipment.get("plate", "")).strip_edges()
		print("EQUIPMENT_ROW=PLATE_%s|SERIAL_%s|CLIENT_%s" % [plate, str(equipment.get("serial", "")), str(equipment.get("client", ""))])
	var rows: Array[Dictionary] = await dashboard.call("_fetch_modern_grupo_rs_vehicle_rows", plate, "Ativo")
	var vehicle: Dictionary = dashboard.call("_choose_modern_grupo_rs_vehicle_row", rows, "", plate)
	if vehicle.is_empty():
		push_error("Veiculo nao localizado pela placa para inspecao somente leitura.")
		dashboard.queue_free()
		quit(1)
		return
	print("VEHICLE_ROW=PLATE_%s|SERIAL_%s|STATUS_%s" % [
		str(vehicle.get("plate", "")),
		str(vehicle.get("serial", "")),
		str(vehicle.get("status", "")),
	])

	var page: Dictionary = await dashboard.call("_modern_grupo_rs_get", str(vehicle.get("edit_href", "")))
	if not bool(page.get("ok", false)):
		push_error("Pagina de edicao do veiculo nao abriu.")
		dashboard.queue_free()
		quit(1)
		return
	var html := str(page.get("body", ""))
	var vehicle_form := _form_by_action(html, "veiculos_actions.php")
	var vehicle_fields: Dictionary = dashboard.call("_legacy_form_fields", vehicle_form)
	var snapshot: Dictionary = dashboard.call("_modern_vehicle_edit_snapshot", html)
	print("VEHICLE_SNAPSHOT=PLATE_%s|CLIENT_%s|TYPE_%s|MODEL_%s" % [
		str(snapshot.get("plate", "")),
		str(snapshot.get("client", "")),
		str(snapshot.get("vehicle_type", "")),
		str(snapshot.get("model", "")),
	])
	print("VEHICLE_SNAPSHOT_JSON=%s" % JSON.stringify(snapshot))
	print("VEHICLE_EDIT_CONTROL_VALUES=acao:%s;status:%s;pagina:%s;TipoIdentificacao:%s;TrocarEquip:%s" % [
		str(vehicle_fields.get("acao", "")),
		str(vehicle_fields.get("status", "")),
		str(vehicle_fields.get("pagina", "")),
		str(vehicle_fields.get("TipoIdentificacao", "")),
		str(vehicle_fields.get("TrocarEquip", "")),
	])
	for summary in _form_summaries(html):
		print("VEHICLE_EDIT_FORM=%s" % summary)
	print("VEHICLE_EDIT_INPUTS=%s" % ",".join(_input_names(html)))
	print("VEHICLE_EDIT_SELECTS=%s" % ",".join(_select_names(html)))
	print("VEHICLE_EDIT_BUTTONS=%s" % ",".join(_button_names(html)))
	for wanted in ["rs300", "carro"]:
		var option := _find_option(html, wanted)
		print("VEHICLE_EDIT_OPTION_%s=%s|%s|%s" % [
			wanted.to_upper(),
			str(option.get("select", "")),
			str(option.get("value", "")),
			str(option.get("label", "")),
		])
	var new_plate := OS.get_environment("CODEX_REASSIGN_TEST_NEW_PLATE").strip_edges()
	if serial != "" and new_plate != "":
		var prepared: Dictionary = await dashboard.call("_prepare_modern_vehicle_reassignment", {
			"remote_serial": serial,
			"old_plate": plate,
			"new_plate": new_plate,
		})
		print("MODERN_REASSIGN_PREFLIGHT=%s|%s" % [
			"OK" if bool(prepared.get("ok", false)) else "FALHA",
			str(prepared.get("message", "")),
		])
	if serial != "":
		var legacy: Dictionary = await dashboard.call("_preflight_legacy_grupo_rs_reassignment", serial)
		print("LEGACY_EQUIPMENT_PREFLIGHT=%s|EXISTS_%s" % [
			"OK" if bool(legacy.get("ok", false)) else "FALHA",
			"SIM" if bool(legacy.get("exists", false)) else "NAO",
		])

	dashboard.queue_free()
	await process_frame
	quit(0)


func _input_names(html: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("(?is)<input[^>]*>")
	for match_result in regex.search_all(html):
		var tag := match_result.get_string(0)
		var name := _attr(tag, "name")
		if name != "" and not result.has(name):
			result.append(name)
	return result


func _form_summaries(html: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("(?is)<form[^>]*>.*?</form>")
	for match_result in regex.search_all(html):
		var form_html := match_result.get_string(0)
		var open_tag := _first_group(form_html, "(?is)(<form[^>]*>)")
		result.append("action=%s;method=%s;inputs=%s;selects=%s;textareas=%s;buttons=%s" % [
			_attr(open_tag, "action"),
			_attr(open_tag, "method"),
			",".join(_input_names(form_html)),
			",".join(_select_names(form_html)),
			",".join(_textarea_names(form_html)),
			",".join(_button_labels(form_html)),
		])
	return result


func _form_by_action(html: String, action_fragment: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?is)<form[^>]*>.*?</form>")
	for match_result in regex.search_all(html):
		var form_html := match_result.get_string(0)
		if _attr(_first_group(form_html, "(?is)(<form[^>]*>)"), "action").contains(action_fragment):
			return form_html
	return ""


func _textarea_names(html: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("(?is)<textarea[^>]*>")
	for match_result in regex.search_all(html):
		var name := _attr(match_result.get_string(0), "name")
		if name != "" and not result.has(name):
			result.append(name)
	return result


func _button_labels(html: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("(?is)<button[^>]*>(.*?)</button>")
	for match_result in regex.search_all(html):
		var tag := match_result.get_string(0)
		var label := _clean_text(match_result.get_string(1))
		var name := _attr(tag, "name")
		result.append("%s:%s" % [name, label])
	return result


func _select_names(html: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("(?is)<select[^>]*>")
	for match_result in regex.search_all(html):
		var name := _attr(match_result.get_string(0), "name")
		if name != "" and not result.has(name):
			result.append(name)
	return result


func _button_names(html: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("(?is)<(?:button|input)[^>]*(?:type=[\"']?(?:submit|button)[\"']?)[^>]*>")
	for match_result in regex.search_all(html):
		var tag := match_result.get_string(0)
		var name := _attr(tag, "name")
		if name != "" and not result.has(name):
			result.append(name)
	return result


func _find_option(html: String, wanted: String) -> Dictionary:
	var select_regex := RegEx.new()
	select_regex.compile("(?is)<select[^>]*>.*?</select>")
	for select_match in select_regex.search_all(html):
		var select_html := select_match.get_string(0)
		var select_name := _attr(select_html, "name")
		var option_regex := RegEx.new()
		option_regex.compile("(?is)<option[^>]*>(.*?)</option>")
		for option_match in option_regex.search_all(select_html):
			var option_tag := option_match.get_string(0)
			var label := _clean_text(option_match.get_string(1))
			if label.to_lower().contains(wanted.to_lower()):
				return {"select": select_name, "value": _attr(option_tag, "value"), "label": label}
	return {}


func _button_text(html: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("(?is)<button[^>]*>(.*?)</button>")
	for match_result in regex.search_all(html):
		result.append(_clean_text(match_result.get_string(1)))
	return result


func _attr(tag: String, name: String) -> String:
	return _first_group(tag, "(?is)\\b%s\\s*=\\s*[\"']([^\"']*)[\"']" % name)


func _first_group(value: String, pattern: String) -> String:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return ""
	var matched := regex.search(value)
	return matched.get_string(1) if matched else ""


func _clean_text(value: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?is)<[^>]+>")
	return regex.sub(value, " ", true).replace("&nbsp;", " ").strip_edges()
