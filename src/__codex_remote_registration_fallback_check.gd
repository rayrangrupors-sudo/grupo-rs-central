extends SceneTree


class FallbackDashboard extends "res://src/inventory_dashboard.gd":
	var posted_path := ""

	func _modern_grupo_rs_get(_path: String, _force_refresh: bool = false) -> Dictionary:
		return {"ok": true, "response_code": 200, "body": """
		<form action='equipamentos_action.php' method='post'>
		<input type='hidden' name='CodEquipamento' value='0'>
		<input name='NumeroEquipamento' value=''>
		<input name='NumeroSerie' value=''>
		<input name='Apn' value=''>
		<input name='NumeroChip' value=''>
		<input name='NumeroTelefone' value=''>
		<select name='CodModelo'><option value='2122'>RS 300</option></select>
		<select name='CodOperadora'><option value='4'>TIM</option></select>
		</form>"""}

	func _modern_grupo_rs_post_form(path: String, _fields: Dictionary, _referer_path: String = "", _retry_login: bool = true, _attempt: int = 0) -> Dictionary:
		posted_path = path
		return {"ok": true, "response_code": 200, "body": ""}

	func _wait_for_modern_equipment_row(serial: String) -> Dictionary:
		return {"ok": true, "row": {"serial": serial}}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := FallbackDashboard.new()
	root.add_child(dashboard)
	await process_frame
	var result: Dictionary = await dashboard.call("_register_modern_equipment_via_web", {
		"serial": "024399998",
		"apn": "hinova.br",
		"chip_number": "89555483000024956727",
		"phone": "37991183429",
		"operator": "Tim",
	})
	if not bool(result.get("ok", false)) or dashboard.posted_path != "equipamentos_action.php":
		push_error("Fallback web nao usou o endpoint singular real do portal: %s | %s" % [dashboard.posted_path, str(result)])
		quit(1)
		return
	print("REMOTE_REGISTRATION_FALLBACK_CHECK_OK endpoint=%s" % dashboard.posted_path)
	dashboard.queue_free()
	await process_frame
	quit(0)
