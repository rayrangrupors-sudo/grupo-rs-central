## One-shot, paginated maintenance snapshot. No networking or automatic polling.
## The adapter supplies verified server pagination, not slices of an HTML table.
extends RefCounted

const PAGE_SIZE := 50
const MAX_PAGES := 1000
var generation := 0
var running := false
var rows: Array[Dictionary] = []
var total := -1
var next_offset := 0
var pages := 0
var error := ""
var _seen: Dictionary = {}
var _visited: Dictionary = {}


func begin() -> int:
	generation += 1
	running = true
	rows.clear()
	_seen.clear()
	_visited.clear()
	total = -1
	next_offset = 0
	pages = 0
	error = ""
	return generation


func cancel() -> void:
	generation += 1
	running = false


func accept_page(ticket: int, offset: int, page: Dictionary) -> bool:
	if ticket != generation or not running:
		return false
	if offset != next_offset or _visited.has(offset):
		return _fail("Paginação repetida ou fora de ordem.")
	if not bool(page.get("ok", false)):
		return _fail("Consulta indisponível; resultado parcial preservado.")
	var incoming: Variant = page.get("rows")
	if not incoming is Array or incoming.size() > PAGE_SIZE:
		return _fail("Resposta fora do contrato de 50 equipamentos por página.")
	if not page.get("has_more") is bool:
		return _fail("A API não informou se existem mais páginas.")
	var has_more: bool = page["has_more"]
	var next: int = int(page.get("next_offset", offset + incoming.size()))
	if has_more and (incoming.is_empty() or next <= offset):
		return _fail("A paginação não avançou.")
	var reported_total := int(page.get("total", -1))
	if reported_total >= 0 and total >= 0 and reported_total != total:
		return _fail("A lista mudou durante a consulta; atualize o levantamento.")
	if reported_total >= 0:
		total = reported_total
	var added := 0
	for value in incoming:
		if not value is Dictionary:
			return _fail("Equipamento inválido na resposta.")
		var row: Dictionary = value
		var key := str(row.get("serial", "")).strip_edges()
		if key == "":
			return _fail("Equipamento sem número de série; identidade não confirmada.")
		if _seen.has(key):
			continue
		_seen[key] = true
		rows.append(row.duplicate(true))
		added += 1
	_visited[offset] = true
	pages += 1
	next_offset = next
	if has_more and (added == 0 or pages >= MAX_PAGES):
		return _fail("Consulta interrompida para evitar repetição de páginas.")
	if total >= 0 and (rows.size() > total or (not has_more and rows.size() != total)):
		return _fail("Total informado difere dos equipamentos recebidos.")
	running = has_more
	return true


func counters() -> Dictionary:
	var result := {"processed": rows.size(), "on": 0, "off": 0, "unknown": 0,
		"awaiting": maxi(0, total - rows.size()) if total >= 0 else -1}
	for row in rows:
		var state := ignition(row.get("ignition"))
		var key := "on" if state == 1 else ("off" if state == 0 else "unknown")
		result[key] += 1
	return result


static func ignition(value: Variant) -> int:
	if value == null:
		return -1
	var numeric := str(value).strip_edges()
	if numeric.is_valid_float():
		if numeric.to_float() == 1.0:
			return 1
		if numeric.to_float() == 0.0:
			return 0
	match str(value).strip_edges().to_lower():
		"1", "true", "on", "ligado", "ligada": return 1
		"0", "false", "off", "desligado", "desligada": return 0
	return -1


static func marker_color(row: Dictionary) -> Variant:
	## Null means do not invent a green/red ignition state.
	match ignition(row.get("ignition")):
		1: return Color("#16a673")
		0: return Color("#dc3545")
	return null


func _fail(message: String) -> bool:
	error = message
	running = false
	return false
