extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		_fail("Dashboard atual nao compilou.")
		return
	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_name", "IMPERATRIZ")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")
	# Exercita o mesmo fallback da aplicacao: leitura publica primeiro e login
	# somente quando o endpoint exigir sessao.
	dashboard.set("modern_grupo_rs_logged_in", false)

	var serials := ["02437314", "02437350", "02437503", "02437294", "02437432", "02437509", "02437328", "02437761"]
	var equipment_rows: Array[Dictionary] = []
	var chosen_serial := ""
	var equipment: Dictionary = {}
	var details: Dictionary = {}
	var client := ""
	var plate := ""
	var client_id := ""
	var location: Dictionary = {}
	for candidate in serials:
		equipment_rows = await dashboard.call("_fetch_grupo_rs_equipment_rows", candidate)
		if equipment_rows.is_empty():
			continue
		equipment = equipment_rows[0]
		client = str(equipment.get("client", "")).strip_edges()
		plate = str(equipment.get("plate", "")).strip_edges()
		if client == "" or plate == "":
			continue
		client_id = await dashboard.call("_fetch_grupo_rs_client_id", client)
		if client_id == "":
			continue
		var vehicle: Dictionary = await dashboard.call("_fetch_grupo_rs_vehicle_location", client_id, plate, candidate)
		var candidate_location := {
			"lat": vehicle.get("lat", vehicle.get("Latitude", vehicle.get("latitude", 0))),
			"lng": vehicle.get("lng", vehicle.get("Longitude", vehicle.get("longitude", 0))),
		}
		if vehicle.is_empty() or not _valid_coordinates(candidate_location):
			continue
		chosen_serial = candidate
		details = await dashboard.call("_fetch_grupo_rs_equipment_details", equipment)
		location = {
			"ok": true,
			"serial": chosen_serial,
			"client": client,
			"client_id": client_id,
			"plate": plate,
			"vehicle_id": dashboard.call("_grupo_rs_vehicle_id_from_value", vehicle),
			"lat": candidate_location.get("lat", 0),
			"lng": candidate_location.get("lng", 0),
			"updated_at": vehicle.get("UltimaComunicacao", vehicle.get("DataEvento", vehicle.get("data_comunicacao", ""))),
			"ignition": vehicle.get("ignicao", vehicle.get("Ignicao", "")),
			"speed": vehicle.get("velocidade", vehicle.get("Velocidade", 0)),
		}
		break

	if chosen_serial == "":
		_fail("Equipamentos responderam, mas os candidatos testados nao tinham coordenadas validas.")
		return

	print("IMPERATRIZ_CHAIN equipment=%s client=%s plate=%s apn=%s iccid=%s row_chip=%s edit_link=%s" % [
		"OK" if not equipment_rows.is_empty() else "FAIL",
		"OK" if client != "" else "FAIL",
		"OK" if plate != "" else "FAIL",
		"OK" if str(details.get("apn", "")).strip_edges() != "" else "MISSING",
		"OK" if str(details.get("chip", "")).strip_edges().length() >= 18 else "MISSING",
		"OK" if str(equipment.get("chip", "")).strip_edges() != "" else "MISSING",
		"OK" if str(equipment.get("edit_href", "")).strip_edges() != "" else "MISSING",
	])
	print("IMPERATRIZ_CHAIN location=%s client_id=%s coordinates=%s ignition=%s" % [
		"OK" if bool(location.get("ok", false)) else "FAIL",
		"OK" if client_id != "" else "FAIL",
		"OK" if _valid_coordinates(location) else "FAIL",
		"OK" if str(location.get("ignition", "")).strip_edges() != "" else "MISSING",
	])

	if not bool(location.get("ok", false)) or not _valid_coordinates(location):
		_fail("A cadeia de localizacao nao retornou coordenadas validas.")
		return

	var battery: Dictionary = await dashboard.call("_lookup_grupo_rs_internal_battery_from_location", location, {})
	print("IMPERATRIZ_CHAIN battery=%s value=%s message=%s" % [
		"OK" if bool(battery.get("ok", false)) else "NO_DATA",
		str(battery.get("percent", "--")),
		str(battery.get("message", "")),
	])

	var iccid := str(details.get("chip", equipment.get("chip", ""))).strip_edges()
	if iccid.length() >= 18:
		var chip: Dictionary = await dashboard.call("_lookup_arya_chip_status", iccid)
		print("IMPERATRIZ_CHAIN chip_arya=%s" % ("OK" if str(chip.get("status", "")).strip_edges() not in ["", "erro", "login"] else "FAIL"))
	else:
		print("IMPERATRIZ_CHAIN chip_arya=SKIPPED_NO_ICCID")

	dashboard.queue_free()
	quit(0)


func _valid_coordinates(location: Dictionary) -> bool:
	var lat := str(location.get("lat", 0)).replace(",", ".").to_float()
	var lng := str(location.get("lng", 0)).replace(",", ".").to_float()
	return is_finite(lat) and is_finite(lng) and lat != 0.0 and lng != 0.0


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
