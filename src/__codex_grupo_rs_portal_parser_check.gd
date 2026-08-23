extends SceneTree

class DashboardStub:
	extends "res://src/inventory_dashboard.gd"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var dashboard := DashboardStub.new()
	root.add_child(dashboard)
	await process_frame
	var modern_html := """
<table><tbody><tr>
<td>997300001</td><td>RS 300</td><td>ZZP - 1234</td><td>RS300</td>
<td>89555483000000000001</td><td>98990000001</td><td><span>Ativo</span></td>
<td><a href="equipamentos_editar.php?id=19001">Editar</a></td>
</tr></tbody></table>
"""
	var legacy_html := """
<table><tbody><tr>
<td>997300002</td><td>ZZP - 1235</td><td>RS300</td>
<td>89555483000000000002</td><td>98990000002</td><td>Inativo</td>
</tr></tbody></table>
"""
	var modern_rows: Array[Dictionary] = dashboard.call("_parse_grupo_rs_equipment_rows", modern_html)
	var legacy_rows: Array[Dictionary] = dashboard.call("_parse_grupo_rs_equipment_rows", legacy_html)
	if modern_rows.size() != 1 or legacy_rows.size() != 1:
		_fail("Parser nao encontrou as duas linhas")
		return
	var modern := modern_rows[0]
	var legacy := legacy_rows[0]
	if str(modern.get("plate", "")) != "ZZP - 1234" or str(modern.get("chip", "")) != "89555483000000000001" \
			or str(modern.get("phone", "")) != "98990000001" or str(modern.get("edit_id", "")) != "19001":
		_fail("Layout moderno deslocou placa/chip/telefone/id: %s" % str(modern))
		return
	if str(legacy.get("plate", "")) != "ZZP - 1235" or str(legacy.get("chip", "")) != "89555483000000000002":
		_fail("Layout legado foi alterado incorretamente: %s" % str(legacy))
		return
	print("GRUPO_RS_PORTAL_PARSER_CHECK_OK modern_plate=%s legacy_plate=%s" % [str(modern.get("plate", "")), str(legacy.get("plate", ""))])
	dashboard.queue_free()
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
