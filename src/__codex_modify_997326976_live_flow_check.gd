extends SceneTree

const SERIAL := "997326976"
const OLD_PLATE := "AAA - TEST"
const NEW_PLATE := "AAA - TFS"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		_fail("Dashboard nao compilou.")
		return
	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")
	var login: Dictionary = await dashboard.call("_grupo_rs_api_login")
	if not bool(login.get("ok", false)):
		_fail("Login recusado: %s" % str(login.get("message", "")))
		return
	var equipment: Dictionary = await dashboard.call("_grupo_rs_api_find_equipment", SERIAL, true)
	if not bool(equipment.get("ok", false)):
		_fail("Equipamento nao encontrado: %s" % str(equipment.get("message", "")))
		return
	# A consulta por placa pode falhar em algumas respostas do portal mesmo
	# quando a associação existe. Localizamos primeiro pelo serial e usamos a
	# placa devolvida pela própria API como origem da alteração.
	var current: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", "", SERIAL, true, true)
	if not bool(current.get("ok", false)):
		_fail("Associacao original nao encontrada: %s" % str(current.get("message", "")))
		return
	var current_row := current.get("row", {}) as Dictionary
	var old_plate := str(current_row.get("plate", OLD_PLATE)).strip_edges()
	var request := {
		"serial": SERIAL,
		"remote_serial": SERIAL,
		"old_plate": old_plate,
		"new_plate": NEW_PLATE,
		"vehicle_target_plate": NEW_PLATE,
		"apply_vehicle_policy": true,
		"vehicle_association_requested": true,
		"clear_vehicle_association": false,
		"clear_vehicle_fields": false,
		"vehicle_type": "Carro",
		"client": "RS300",
		"model": "RS 300",
		"operator": "Tim",
		"chip_number": str((equipment.get("row", {}) as Dictionary).get("numeroChip", "")),
		"phone": str((equipment.get("row", {}) as Dictionary).get("numeroTelefone", "")),
		"apn": str((equipment.get("row", {}) as Dictionary).get("apn", "")),
		"equipment_fields_changed": false,
	}
	print("LIVE_MODIFY_START serial=%s old=%s new=%s" % [SERIAL, old_plate, NEW_PLATE])
	var result: Dictionary = await dashboard.call("_perform_equipment_modification", request, null)
	print("LIVE_MODIFY_RESULT ok=%s api=%s fallback=%s message=%s" % [str(result.get("ok", false)), str(result.get("api", false)), str(result.get("web", false)), str(result.get("message", ""))])
	if not bool(result.get("ok", false)):
		_fail("A modificacao real nao foi confirmada: %s" % str(result.get("message", result)))
		return
	var confirmed: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", "", SERIAL, true, true)
	if not bool(confirmed.get("ok", false)):
		_fail("A consulta final nao confirmou a nova placa: %s" % str(confirmed.get("message", "")))
		return
	var confirmed_row := confirmed.get("row", {}) as Dictionary
	var confirmed_plate := str(confirmed_row.get("plate", "")).strip_edges().to_upper()
	if confirmed_plate != NEW_PLATE.to_upper():
		_fail("A consulta final retornou placa inesperada: %s" % confirmed_plate)
		return
	print("LIVE_MODIFY_CONFIRMED_OK serial=%s plate=%s vehicle=%s" % [SERIAL, NEW_PLATE, str(confirmed.get("row", {}))])
	dashboard.queue_free()
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
