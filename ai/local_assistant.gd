class_name LocalAssistant
extends RefCounted

var _context: AIContextProvider
var _intents: Array[Dictionary] = []
var _handlers: Dictionary = {}


func setup(context_provider: AIContextProvider) -> void:
	_context = context_provider
	_handlers = {
		"saudacao": Callable(self, "_answer_greeting"),
		"consultar_estoque": Callable(self, "_answer_inventory"),
		"consultar_manutencao": Callable(self, "_answer_maintenance"),
		"consultar_iccid_duplicado": Callable(self, "_answer_duplicate_iccid"),
		"consultar_inconsistencias": Callable(self, "_answer_inconsistencies"),
		"consultar_sincronizacao": Callable(self, "_answer_sync"),
		"ajuda_baixa": Callable(self, "_answer_discharge_help"),
		"ajuda_cadastro": Callable(self, "_answer_registration_help"),
		"ajuda_pagina": Callable(self, "_answer_page_help"),
		"ajuda_monitor_4g": Callable(self, "_answer_monitor_help"),
		"capacidades": Callable(self, "_answer_capabilities"),
	}
	_intents = [
		{"id": "consultar_iccid_duplicado", "phrases": ["iccid duplicado", "iccids duplicados", "chip duplicado"]},
		{"id": "consultar_inconsistencias", "phrases": ["inconsistencia", "campos vazios", "dados incompletos", "formato invalido"]},
		{"id": "consultar_manutencao", "phrases": ["em manutencao", "manutencoes", "equipamentos com problema", "quantos em manutencao"]},
		{"id": "consultar_estoque", "phrases": ["resumo do estoque", "quantos aparelhos", "aparelhos disponiveis", "estoque baixo", "disponiveis"]},
		{"id": "consultar_sincronizacao", "phrases": ["sistema sincronizado", "status da sincronizacao", "local_database", "servidor conectado"]},
		{"id": "ajuda_baixa", "phrases": ["como dar baixa", "dar baixa em um aparelho", "baixa no estoque"]},
		{"id": "ajuda_cadastro", "phrases": ["como cadastrar", "novo rastreador", "adicionar equipamento", "cadastrar aparelho"]},
		{"id": "ajuda_monitor_4g", "phrases": ["explique o monitor 4g", "como funciona o monitor 4g", "tela monitor 4g"]},
		{"id": "ajuda_pagina", "phrases": ["como usar esta tela", "o que significa esta tela", "explique esta tela", "o que posso fazer"]},
		{"id": "capacidades", "phrases": ["o que voce faz", "como pode ajudar", "suas funcoes", "quem e luna"]},
		{"id": "saudacao", "phrases": ["ola", "bom dia", "boa tarde", "boa noite", "oi luna"]},
	]


func answer(question: String) -> Dictionary:
	if _context == null:
		return _result(false, "", "A Luna local ainda nao recebeu o contexto do sistema.")
	var normalized := _normalize(question)
	if normalized == "":
		return _result(true, "entrada_vazia", "Escreva uma pergunta para eu ajudar.")
	var best_id := ""
	var best_score := 0
	for intent in _intents:
		var score := _score_intent(normalized, intent.get("phrases", []))
		if score > best_score:
			best_score = score
			best_id = str(intent.get("id", ""))
	if best_id == "" or best_score < 2 or not _handlers.has(best_id):
		return _result(false, "", "Nao encontrei uma resposta local segura para essa pergunta.")
	var response: Dictionary = (_handlers[best_id] as Callable).call()
	response["handled"] = true
	response["intent"] = best_id
	response["mode"] = "local"
	response["confidence"] = minf(1.0, float(best_score) / 3.0)
	response["actions"] = _safe_actions(response.get("actions", []))
	return response


func should_use_online(question: String, local_result: Dictionary) -> bool:
	if not bool(local_result.get("handled", false)):
		return true
	var normalized := _normalize(question)
	if float(local_result.get("confidence", 0.0)) < 0.95:
		return true
	return _contains_any(normalized, [
		"relatorio detalhado",
		"gere um relatorio",
		"analise avancada",
		"analise esta situacao",
		"compare",
		"elabore",
		"me ajude a entender",
		"melhor forma",
		"o que voce acha",
		"por que",
		"possiveis causas",
		"recomende",
		"sugira",
		"sugira melhorias",
		"situacao incomum",
		"explique melhor",
		"explique detalhadamente",
	])


func _answer_greeting() -> Dictionary:
	return _result(true, "saudacao", "Ola. Sou a Luna. Posso consultar resumos do estoque, manutencoes, sincronizacao, inconsistencias e explicar as telas do sistema.")


func _answer_inventory() -> Dictionary:
	var summary := _context.get_inventory_summary()
	if summary.is_empty():
		return _result(true, "consultar_estoque", "Nao encontrei dados de estoque carregados nesta filial.")
	var text := "Resumo do estoque: %d equipamento(s) no total, %d disponivel(is), %d instalado(s), %d em manutencao, %d reservado(s) e %d inativo(s)." % [
		int(summary.get("total", 0)),
		int(summary.get("disponiveis", 0)),
		int(summary.get("instalados", 0)),
		int(summary.get("manutencao", 0)),
		int(summary.get("reservados", 0)),
		int(summary.get("inativos", 0)),
	]
	var low_stock := int(summary.get("estoque_baixo", 0))
	if low_stock > 0:
		text += " Ha %d item(ns) sinalizado(s) com estoque baixo." % low_stock
	return _result(true, "consultar_estoque", text, [{"id": "open_inventory", "label": "Abrir estoque"}])


func _answer_maintenance() -> Dictionary:
	var summary := _context.get_maintenance_summary()
	return _result(
		true,
		"consultar_manutencao",
		"Existem %d manutencao(oes) aberta(s) e %d concluida(s) no resumo atual." % [
			int(summary.get("abertas", 0)),
			int(summary.get("concluidas", 0)),
		],
		[{"id": "open_maintenance", "label": "Ver manutencoes"}]
	)


func _answer_duplicate_iccid() -> Dictionary:
	var summary := _context.get_duplicate_iccid_summary()
	var groups := int(summary.get("groups", 0))
	if groups == 0:
		return _result(true, "consultar_iccid_duplicado", "Nao encontrei ICCIDs duplicados nos dados carregados.")
	return _result(
		true,
		"consultar_iccid_duplicado",
		"Foram encontrados %d grupo(s) de ICCID duplicado, envolvendo %d registro(s). Os numeros reais nao sao exibidos pela Luna." % [
			groups,
			int(summary.get("records", 0)),
		],
		[{"id": "open_inventory", "label": "Abrir registros"}]
	)


func _answer_inconsistencies() -> Dictionary:
	var issues := _context.find_data_inconsistencies()
	if issues.is_empty():
		return _result(true, "consultar_inconsistencias", "Nao encontrei inconsistencias nos diagnosticos atuais.")
	var parts: Array[String] = []
	var total := 0
	for issue in issues:
		var count := int(issue.get("count", 0))
		total += count
		parts.append("%s: %d" % [str(issue.get("type", "outro")).replace("_", " "), count])
	return _result(
		true,
		"consultar_inconsistencias",
		"Foram encontradas %d ocorrencia(s): %s." % [total, ", ".join(parts)],
		[{"id": "open_inventory", "label": "Ver registros"}]
	)


func _answer_sync() -> Dictionary:
	var status := _context.get_sync_status()
	if not bool(status.get("available", false)):
		return _result(true, "consultar_sincronizacao", str(status.get("message", "Sincronizacao indisponivel.")))
	var message := "Sincronizacao: estado %s, %d pendencia(s), %d falha(s)" % [
		str(status.get("state", "desconhecido")),
		int(status.get("pending", 0)),
		int(status.get("failures", 0)),
	]
	var last_sync := str(status.get("last_sync_at", ""))
	if last_sync != "":
		message += ", ultima atividade em %s" % last_sync
	message += "."
	return _result(true, "consultar_sincronizacao", message, [{"id": "open_settings", "label": "Abrir configuracoes"}])


func _answer_discharge_help() -> Dictionary:
	return _result(
		true,
		"ajuda_baixa",
		"Abra Estoque, pesquise o numero de serie, escolha Dar baixa, informe a placa e revise os dados antes de confirmar. A Luna nao executa a baixa automaticamente.",
		[{"id": "open_inventory", "label": "Abrir estoque"}]
	)


func _answer_registration_help() -> Dictionary:
	return _result(
		true,
		"ajuda_cadastro",
		"Abra Cadastros ou Estoque e selecione Novo. Informe numero de serie, tipo, operadora, placa e status. Revise os campos obrigatorios antes de Salvar.",
		[{"id": "open_inventory", "label": "Abrir cadastro"}]
	)


func _answer_page_help() -> Dictionary:
	var page := str(_context.page_context().get("current_page", ""))
	return _result(true, "ajuda_pagina", _context.get_system_help(page))


func _answer_monitor_help() -> Dictionary:
	return _result(
		true,
		"ajuda_monitor_4g",
		_context.get_system_help("monitor_4g"),
		[{"id": "open_monitor_4g", "label": "Abrir Monitor 4G"}]
	)


func _answer_capabilities() -> Dictionary:
	return _result(
		true,
		"capacidades",
		"Eu funciono localmente para consultas e diagnosticos do GRUPO RS CENTRAL. Quando autorizado e necessario, posso usar o Gemini para elaborar uma explicacao ou relatorio mais avancado. Nunca executo alteracoes a partir de uma resposta online."
	)


func _result(handled: bool, intent: String, text: String, actions: Array = []) -> Dictionary:
	return {
		"handled": handled,
		"intent": intent,
		"text": text,
		"actions": actions,
		"mode": "local",
		"confidence": 1.0 if handled else 0.0,
	}


func _score_intent(question: String, phrases: Variant) -> int:
	if typeof(phrases) != TYPE_ARRAY:
		return 0
	var score := 0
	for phrase_value in phrases as Array:
		var phrase := _normalize(str(phrase_value))
		if question == phrase:
			score = maxi(score, 4)
		elif question.contains(phrase):
			score = maxi(score, 3)
		else:
			var matched_words := 0
			for word in phrase.split(" ", false):
				if word.length() >= 3 and question.contains(word):
					matched_words += 1
			score = maxi(score, matched_words)
	return score


func _safe_actions(actions: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(actions) != TYPE_ARRAY:
		return result
	var allowed := ["open_inventory", "open_maintenance", "open_logs", "open_settings", "open_monitor_4g"]
	for item in actions as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var action := item as Dictionary
		if allowed.has(str(action.get("id", ""))):
			result.append(action.duplicate(true))
	return result


func _normalize(text: String) -> String:
	var result := text.to_lower().strip_edges()
	var replacements := {
		"a": ["á", "à", "ã", "â"],
		"e": ["é", "ê"],
		"i": ["í"],
		"o": ["ó", "ô", "õ"],
		"u": ["ú"],
		"c": ["ç"],
	}
	for replacement in replacements:
		for character in replacements[replacement]:
			result = result.replace(str(character), str(replacement))
	for symbol in ["?", "!", ".", ",", ";", ":"]:
		result = result.replace(symbol, " ")
	return " ".join(result.split(" ", false))


func _contains_any(text: String, values: Array) -> bool:
	for value in values:
		if text.contains(str(value)):
			return true
	return false
