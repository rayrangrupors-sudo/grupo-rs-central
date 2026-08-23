class_name AIContextProvider
extends RefCounted

const SUMMARY_CACHE_SECONDS := 30

var _store: Object
var _sync_provider: Object
var _branch_id := ""
var _page_context: Dictionary = {}
var _runtime_context: Dictionary = {}
var _settings: AISettings
var _summary_cache: Dictionary = {}
var _summary_cache_at := 0


func setup(settings: AISettings) -> void:
	_settings = settings


func bind_store(store: Object, branch_id: String, sync_provider: Object = null) -> void:
	_store = store
	_branch_id = branch_id
	_sync_provider = sync_provider
	invalidate()


func unbind_store() -> void:
	_store = null
	_sync_provider = null
	_branch_id = ""
	_runtime_context.clear()
	invalidate()


func update_page_context(context: Dictionary) -> void:
	_page_context = {
		"current_page": str(context.get("current_page", "")),
		"title": str(context.get("title", "")),
		"subtitle": str(context.get("subtitle", "")),
		"selected_branch_id": str(context.get("selected_branch_id", _branch_id)),
		"current_filters": _sanitize_filter_context(context.get("current_filters", {})),
	}


func update_runtime_context(context: Dictionary) -> void:
	for key in context:
		_runtime_context[key] = context[key]


func invalidate() -> void:
	_summary_cache.clear()
	_summary_cache_at = 0


func is_ready() -> bool:
	return _store != null and is_instance_valid(_store)


func get_inventory_summary() -> Dictionary:
	_refresh_summary_cache()
	return (_summary_cache.get("inventory", {}) as Dictionary).duplicate(true)


func get_maintenance_summary() -> Dictionary:
	_refresh_summary_cache()
	return (_summary_cache.get("maintenance", {}) as Dictionary).duplicate(true)


func get_sync_status() -> Dictionary:
	if _sync_provider == null or not is_instance_valid(_sync_provider) or not _sync_provider.has_method("get_status"):
		return {"available": false, "message": "Sincronizacao indisponivel."}
	var status: Variant = _sync_provider.call("get_status")
	if typeof(status) != TYPE_DICTIONARY:
		return {"available": false, "message": "Estado de sincronizacao invalido."}
	var source := status as Dictionary
	return {
		"available": true,
		"configured": bool(source.get("configured", false)),
		"state": str(source.get("state", "unknown")),
		"message": str(source.get("message", "")),
		"last_sync_at": str(source.get("last_sync_at", "")),
		"pending": int(source.get("pending", source.get("pending_count", 0))),
		"failures": int(source.get("failure_count", 0)),
		"latency_ms": int(source.get("latency_ms", -1)),
	}


func get_system_help(page_name: String) -> String:
	var help_by_page := {
		"dashboard": "A pagina inicial resume estoque, comunicacoes, manutencoes e integracoes. Use os indicadores para abrir o detalhe correspondente.",
		"inventory": "Em Estoque voce pesquisa, filtra, cadastra, edita e da baixa em rastreadores. Alteracoes sempre exigem uma acao explicita do usuario.",
		"maintenance": "A area de Manutencao reune equipamentos que precisam de atendimento. Use OK quando o servico for concluido ou Excluir para retirar apenas o agendamento.",
		"monitor_4g": "O Monitor 4G analisa rastreadores ligados e compara o horario do GPS com o servidor para estimar a qualidade regional da comunicacao.",
		"logs": "A Central de eventos mostra sincronizacoes, comandos, recuperacoes e falhas tecnicas. Os filtros nao alteram os registros.",
		"settings": "Configuracoes centraliza credenciais, conexoes, seguranca, atualizacoes e a Luna. Senhas ficam no armazenamento local do computador.",
		"guardian": "A Assistente Luna responde localmente sobre o sistema e pode usar o Gemini, quando autorizado, para analises textuais mais avancadas.",
		"bulk": "Cadastro em massa valida uma lista antes de salvar. Revise a previa e os campos detectados antes de confirmar.",
		"reports": "Relatorios permite consultar e exportar resumos operacionais sem alterar os dados do estoque.",
	}
	var key := page_name.strip_edges().to_lower()
	return str(help_by_page.get(key, "Esta tela ainda nao possui uma explicacao local detalhada."))


func find_data_inconsistencies() -> Array[Dictionary]:
	if not is_ready() or not _store.has_method("get_diagnostics"):
		return []
	var raw: Variant = _store.call("get_diagnostics")
	if typeof(raw) != TYPE_ARRAY:
		return []
	var grouped: Dictionary = {}
	for item in raw as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var diagnostic := item as Dictionary
		var kind := str(diagnostic.get("type", diagnostic.get("kind", "outro")))
		if kind == "":
			kind = "outro"
		if not grouped.has(kind):
			grouped[kind] = {
				"type": kind,
				"count": 0,
				"severity": str(diagnostic.get("severity", "warning")),
				"message": str(diagnostic.get("message", "Dados inconsistentes encontrados.")),
			}
		grouped[kind]["count"] = int(grouped[kind].get("count", 0)) + 1
	var result: Array[Dictionary] = []
	for kind in grouped:
		result.append((grouped[kind] as Dictionary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("count", 0)) > int(b.get("count", 0)))
	return result


func get_duplicate_iccid_summary() -> Dictionary:
	if not is_ready() or not _store.has_method("get_products"):
		return {"groups": 0, "records": 0}
	var products: Variant = _store.call("get_products")
	if typeof(products) != TYPE_ARRAY:
		return {"groups": 0, "records": 0}
	var counts: Dictionary = {}
	for item in products as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var product := item as Dictionary
		var iccid := str(product.get("chip_number", product.get("iccid", ""))).strip_edges()
		if iccid == "":
			continue
		counts[iccid] = int(counts.get(iccid, 0)) + 1
	var groups := 0
	var records := 0
	for iccid in counts:
		var count := int(counts[iccid])
		if count > 1:
			groups += 1
			records += count
	return {"groups": groups, "records": records}


func get_system_health_summary() -> Dictionary:
	if not is_ready() or not _store.has_method("get_system_health"):
		return {"available": false}
	var raw: Variant = _store.call("get_system_health")
	if typeof(raw) != TYPE_DICTIONARY:
		return {"available": false}
	var health := raw as Dictionary
	return {
		"available": true,
		"storage_mode": str(health.get("storage_mode", "")),
		"remote_available": bool(health.get("remote_available", false)),
		"loaded": bool(health.get("loaded", true)),
	}


func get_controlled_context(question: String) -> Dictionary:
	var context := {
		"branch": _branch_id,
		"page": _page_context.duplicate(true),
	}
	var normalized := question.to_lower()
	if _settings == null or bool(_settings.get_value("context_inventory", true)):
		if _contains_any(normalized, ["estoque", "aparelho", "equipamento", "operadora", "tipo", "dispon"]):
			context["inventory"] = get_inventory_summary()
			context["inconsistencies"] = find_data_inconsistencies()
	if _settings == null or bool(_settings.get_value("context_maintenance", true)):
		if _contains_any(normalized, ["manuten", "parado", "problema", "falha", "equipamento"]):
			context["maintenance"] = get_maintenance_summary()
	if _contains_any(normalized, ["sincron", "conexao", "servidor", "firebase"]):
		context["sync"] = get_sync_status()
	if _runtime_context.has("selected_equipment"):
		context["selected_equipment"] = _summarize_selected_equipment(_runtime_context["selected_equipment"])
	return context


func page_context() -> Dictionary:
	return _page_context.duplicate(true)


func monitoring_context() -> Dictionary:
	var result: Dictionary = {}
	for key in ["stopped_over_limit", "consecutive_failures", "last_backup_at", "monitor_summary"]:
		if _runtime_context.has(key):
			result[key] = _runtime_context[key]
	return result


func _refresh_summary_cache() -> void:
	var now := int(Time.get_unix_time_from_system())
	if not _summary_cache.is_empty() and now - _summary_cache_at <= SUMMARY_CACHE_SECONDS:
		return
	var inventory := {
		"total": 0,
		"disponiveis": 0,
		"instalados": 0,
		"manutencao": 0,
		"inativos": 0,
		"reservados": 0,
		"estoque_baixo": 0,
	}
	var maintenance := {"abertas": 0, "concluidas": 0}
	if is_ready():
		if _store.has_method("get_tracker_stats"):
			var tracker_raw: Variant = _store.call("get_tracker_stats")
			if typeof(tracker_raw) == TYPE_DICTIONARY:
				var tracker := tracker_raw as Dictionary
				inventory["total"] = int(tracker.get("total", 0))
				inventory["disponiveis"] = int(tracker.get("available", tracker.get("stock", 0)))
				inventory["instalados"] = int(tracker.get("installed", tracker.get("active", 0)))
				inventory["manutencao"] = int(tracker.get("maintenance", 0))
				inventory["inativos"] = int(tracker.get("inactive", 0))
				inventory["reservados"] = int(tracker.get("reserved", 0))
		if _store.has_method("get_stats"):
			var stats_raw: Variant = _store.call("get_stats")
			if typeof(stats_raw) == TYPE_DICTIONARY:
				inventory["estoque_baixo"] = int((stats_raw as Dictionary).get("low_stock", 0))
		if _store.has_method("get_maintenances"):
			var open_raw: Variant = _store.call("get_maintenances", false)
			var all_raw: Variant = _store.call("get_maintenances", true)
			var open_count := (open_raw as Array).size() if typeof(open_raw) == TYPE_ARRAY else 0
			var all_count := (all_raw as Array).size() if typeof(all_raw) == TYPE_ARRAY else open_count
			maintenance["abertas"] = open_count
			maintenance["concluidas"] = maxi(all_count - open_count, 0)
	_summary_cache = {"inventory": inventory, "maintenance": maintenance}
	_summary_cache_at = now


func _summarize_selected_equipment(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var item := value as Dictionary
	return {
		"status": str(item.get("status", "")),
		"operator": str(item.get("operator", "")),
		"type": str(item.get("type", item.get("model", ""))),
		"has_plate": str(item.get("plate", "")).strip_edges() != "",
		"has_iccid": str(item.get("chip_number", item.get("iccid", ""))).strip_edges() != "",
	}


func _sanitize_filter_context(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var source := value as Dictionary
	var result: Dictionary = {}
	for key in source:
		if ["status", "category", "operator", "page", "sort"].has(str(key)):
			result[str(key)] = source[key]
	return result


func _contains_any(text: String, values: Array) -> bool:
	for value in values:
		if text.contains(str(value)):
			return true
	return false
