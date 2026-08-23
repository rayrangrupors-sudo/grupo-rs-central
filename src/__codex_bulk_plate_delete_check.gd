extends SceneTree


const BULK_PLATES := """TYT - 3423
TTT - 1T11
BRA - 0001
GRS - T38
HFG - 4521
HGT - 4562
HJG - J785
RJF - 2525
ROE - 0F37
ROK - 0000
SDR - 6532
SHS - 1212
SLS - 139
SNF - 7C50
SOO - 8569
AAA - T248
AAA - T253
AAA - T254"""

const EXPECTED_PLATES := [
	"TYT - 3423",
	"TTT - 1T11",
	"BRA - 0001",
	"GRS - T38",
	"HFG - 4521",
	"HGT - 4562",
	"HJG - J785",
	"RJF - 2525",
	"ROE - 0F37",
	"ROK - 0000",
	"SDR - 6532",
	"SHS - 1212",
	"SLS - 139",
	"SNF - 7C50",
	"SOO - 8569",
	"AAA - T248",
	"AAA - T253",
	"AAA - T254",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/estoque_profissional.tscn")
	if scene == null:
		_fail("Cena principal nao carregou.")
		return

	var dashboard: Node = scene.instantiate()
	root.add_child(dashboard)
	await process_frame

	var parsed: Dictionary = dashboard.call("_parse_bulk_delete_items", BULK_PLATES)
	var items: Array = parsed.get("items", [])
	var errors: Array = parsed.get("errors", [])
	if items.size() != EXPECTED_PLATES.size():
		_fail("Esperava %d placas, mas o parser retornou %d: %s" % [EXPECTED_PLATES.size(), items.size(), errors])
		return
	if not errors.is_empty():
		_fail("O lote valido retornou erros: %s" % errors)
		return

	for index in range(items.size()):
		var item: Dictionary = items[index]
		if str(item.get("kind", "")) != "plate":
			_fail("Item %d foi classificado como aparelho: %s" % [index + 1, item])
			return
		if str(item.get("target", "")) != EXPECTED_PLATES[index]:
			_fail("Placa %d foi normalizada incorretamente: %s" % [index + 1, item])
			return
		if str(item.get("serial", "")) != "":
			_fail("Placa %s recebeu numero de serie indevido." % EXPECTED_PLATES[index])
			return

	var preview: Dictionary = dashboard.call("_parse_bulk_delete_preview_rows", BULK_PLATES)
	var preview_rows: Array = preview.get("rows", [])
	if preview_rows.size() != EXPECTED_PLATES.size() or not bool(preview.get("prefer_delete_preview", false)):
		_fail("A previa de exclusao nao reconheceu as 18 placas: %s" % preview)
		return
	if not (preview.get("errors", []) as Array).is_empty():
		_fail("A previa valida retornou erros: %s" % preview.get("errors", []))
		return

	var normalized: Dictionary = dashboard.call("_parse_bulk_delete_items", "aaa-t248\nGRS- T38\nSLS -139\nAAA - T248")
	var normalized_items: Array = normalized.get("items", [])
	if normalized_items.size() != 3:
		_fail("Normalizacao ou eliminacao de duplicatas falhou: %s" % normalized)
		return
	if str((normalized_items[0] as Dictionary).get("target", "")) != "AAA - T248" \
			or str((normalized_items[1] as Dictionary).get("target", "")) != "GRS - T38" \
			or str((normalized_items[2] as Dictionary).get("target", "")) != "SLS - 139":
		_fail("Espacos da placa nao foram normalizados: %s" % normalized_items)
		return

	var serial_result: Dictionary = dashboard.call("_parse_bulk_delete_items", "024123456")
	var serial_items: Array = serial_result.get("items", [])
	if serial_items.size() != 1 or str((serial_items[0] as Dictionary).get("kind", "")) != "equipment":
		_fail("Numero de serie deixou de ser tratado como aparelho: %s" % serial_result)
		return

	for invalid_line in ["CARLA PRISCILA DA SILVA", "AA - 1234", "AAA - 12", "17228"]:
		var invalid_result: Dictionary = dashboard.call("_parse_bulk_delete_items", invalid_line)
		if not (invalid_result.get("items", []) as Array).is_empty():
			_fail("Linha invalida foi confundida com placa: %s -> %s" % [invalid_line, invalid_result])
			return

	print("BULK_PLATE_DELETE_CHECK_OK plates=%d preview=%d safe_no_live_delete=true" % [items.size(), preview_rows.size()])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
