class_name GeminiClient
extends Node

signal request_state_changed(busy: bool)
signal _transport_finished(request_id: int, result: Dictionary)

const API_BASE_URL := "https://generativelanguage.googleapis.com/v1beta"
const DEFAULT_TIMEOUT_SECONDS := 30.0
const CONNECTIVITY_CACHE_SECONDS := 120
const MAX_RETRIES := 1

var busy := false
var _http: HTTPRequest
var _active_request_id := 0
var _cancel_requested := false
var _last_connectivity_ok_at := 0
var _test_transport: Callable
var _fallback_models: Dictionary = {}


func _ready() -> void:
	_ensure_http_node()


func set_test_transport(transport: Callable) -> void:
	_test_transport = transport


func clear_test_transport() -> void:
	_test_transport = Callable()


func send_message(
	question: String,
	context: Dictionary,
	history: Array[Dictionary],
	api_key: String,
	model: String
) -> Dictionary:
	if busy:
		return _error("busy", "A Luna ja esta processando outra mensagem.")
	if api_key.strip_edges() == "":
		return _error("missing_key", "A chave da API Gemini nao foi configurada.")
	if question.strip_edges() == "":
		return _error("empty_question", "A pergunta esta vazia.")

	busy = true
	_cancel_requested = false
	_active_request_id += 1
	var request_id := _active_request_id
	request_state_changed.emit(true)

	var connectivity := await _check_connectivity(api_key, request_id)
	if not bool(connectivity.get("ok", false)):
		return _finish(request_id, connectivity)
	if _cancel_requested or request_id != _active_request_id:
		return _finish(request_id, _error("cancelled", "Requisicao cancelada."))

	var payload := _build_generation_payload(question, context, history)
	var selected_model := _normalize_model_name(model)
	var url := "%s/models/%s:generateContent" % [API_BASE_URL, selected_model.uri_encode()]
	var result := await _request_with_retry(
		"generate",
		url,
		PackedStringArray([
			"Content-Type: application/json",
			"x-goog-api-key: %s" % api_key,
		]),
		HTTPClient.METHOD_POST,
		JSON.stringify(payload),
		request_id
	)
	if str(result.get("error", "")) == "model_unavailable":
		var discovered := await _discover_generation_model(api_key, selected_model, request_id)
		var fallback_model := str(discovered.get("model", ""))
		if bool(discovered.get("ok", false)) and fallback_model != "":
			selected_model = fallback_model
			url = "%s/models/%s:generateContent" % [API_BASE_URL, selected_model.uri_encode()]
			result = await _request_with_retry(
				"generate",
				url,
				PackedStringArray([
					"Content-Type: application/json",
					"x-goog-api-key: %s" % api_key,
				]),
				HTTPClient.METHOD_POST,
				JSON.stringify(payload),
				request_id
			)
	if not bool(result.get("ok", false)):
		return _finish(request_id, result)
	var parsed_result := _parse_generation_response(str(result.get("body", "")))
	parsed_result["model_used"] = selected_model
	return _finish(request_id, parsed_result)


func test_connection(api_key: String, model: String) -> Dictionary:
	if busy:
		return _error("busy", "A Luna ja esta processando outra solicitacao.")
	if api_key.strip_edges() == "":
		return _error("missing_key", "Informe uma chave da API Gemini.")
	busy = true
	_cancel_requested = false
	_active_request_id += 1
	var request_id := _active_request_id
	request_state_changed.emit(true)
	var selected_model := _normalize_model_name(model)
	var result := await _request_once(
		"connectivity",
		"%s/models/%s" % [API_BASE_URL, selected_model.uri_encode()],
		PackedStringArray(["x-goog-api-key: %s" % api_key]),
		HTTPClient.METHOD_GET,
		"",
		request_id
	)
	if str(result.get("error", "")) == "model_unavailable":
		var discovered := await _discover_generation_model(api_key, selected_model, request_id)
		if bool(discovered.get("ok", false)):
			result = {
				"ok": true,
				"status": 200,
				"model_used": str(discovered.get("model", "")),
			}
	if bool(result.get("ok", false)):
		_last_connectivity_ok_at = int(Time.get_unix_time_from_system())
		result["message"] = "Conexao realizada com sucesso."
	return _finish(request_id, result)


func cancel_request() -> void:
	if not busy:
		return
	_cancel_requested = true
	var cancelled_id := _active_request_id
	_active_request_id += 1
	if _http != null and is_instance_valid(_http):
		_http.cancel_request()
	_transport_finished.emit(cancelled_id, _error("cancelled", "Requisicao cancelada."))
	busy = false
	request_state_changed.emit(false)


func _check_connectivity(api_key: String, request_id: int) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	if now - _last_connectivity_ok_at <= CONNECTIVITY_CACHE_SECONDS:
		return {"ok": true, "cached": true}
	var result := await _request_once(
		"connectivity",
		"%s/models?pageSize=1" % API_BASE_URL,
		PackedStringArray(["x-goog-api-key: %s" % api_key]),
		HTTPClient.METHOD_GET,
		"",
		request_id
	)
	if bool(result.get("ok", false)):
		_last_connectivity_ok_at = now
	return result


func _discover_generation_model(api_key: String, rejected_model: String, request_id: int) -> Dictionary:
	var cache_key := "%s:%s" % [api_key.sha256_text().left(12), rejected_model]
	if _fallback_models.has(cache_key):
		return {"ok": true, "model": str(_fallback_models[cache_key]), "cached": true}
	var result := await _request_once(
		"models",
		"%s/models?pageSize=1000" % API_BASE_URL,
		PackedStringArray(["x-goog-api-key: %s" % api_key]),
		HTTPClient.METHOD_GET,
		"",
		request_id
	)
	if not bool(result.get("ok", false)):
		return result
	var parser := JSON.new()
	if parser.parse(str(result.get("body", ""))) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return _error("invalid_json", "A lista de modelos do Gemini retornou um JSON invalido.")
	var models: Variant = (parser.data as Dictionary).get("models", [])
	if typeof(models) != TYPE_ARRAY:
		return _error("model_unavailable", "Nenhum modelo de texto compativel foi encontrado.")
	var selected_model := ""
	var selected_score := -1
	for item in models as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var model_data := item as Dictionary
		var methods: Variant = model_data.get("supportedGenerationMethods", [])
		if typeof(methods) != TYPE_ARRAY or not (methods as Array).has("generateContent"):
			continue
		var candidate := _normalize_model_name(str(model_data.get("name", "")))
		if candidate == rejected_model:
			continue
		var score := _model_priority(candidate)
		if score > selected_score:
			selected_model = candidate
			selected_score = score
	if selected_model == "":
		return _error("model_unavailable", "Nenhum modelo de texto compativel foi encontrado.")
	_fallback_models[cache_key] = selected_model
	return {"ok": true, "model": selected_model, "cached": false}


func _model_priority(model: String) -> int:
	if not model.begins_with("gemini-"):
		return -1
	for unsupported in ["image", "tts", "live", "robot", "embedding", "computer-use", "deep-research", "omni"]:
		if model.contains(unsupported):
			return -1
	var score := 100
	if model == "gemini-flash-lite-latest":
		score = 1000
	elif model == "gemini-flash-latest":
		score = 900
	elif model.contains("flash-lite"):
		score = 800
	elif model.contains("flash"):
		score = 700
	elif model.contains("pro"):
		score = 400
	if model.contains("preview"):
		score -= 100
	return score


func _normalize_model_name(model: String) -> String:
	return model.strip_edges().trim_prefix("models/")


func _request_with_retry(
	kind: String,
	url: String,
	headers: PackedStringArray,
	method: int,
	body: String,
	request_id: int
) -> Dictionary:
	var attempt := 0
	var result: Dictionary = {}
	while attempt <= MAX_RETRIES:
		if _cancel_requested or request_id != _active_request_id:
			return _error("cancelled", "Requisicao cancelada.")
		result = await _request_once(kind, url, headers, method, body, request_id)
		if bool(result.get("ok", false)) or not bool(result.get("retryable", false)):
			return result
		attempt += 1
		if attempt <= MAX_RETRIES:
			await get_tree().create_timer(0.75).timeout
	return result


func _request_once(
	kind: String,
	url: String,
	headers: PackedStringArray,
	method: int,
	body: String,
	request_id: int
) -> Dictionary:
	if _test_transport.is_valid():
		var mocked: Variant = await _test_transport.call(kind, {
			"url": url,
			"method": int(method),
			"body": body,
			"request_id": request_id,
		})
		if request_id != _active_request_id or _cancel_requested:
			return _error("cancelled", "Requisicao cancelada.")
		if typeof(mocked) == TYPE_DICTIONARY:
			return mocked as Dictionary
		return _error("invalid_transport", "O transporte de teste retornou um valor invalido.")

	_ensure_http_node()
	if _http == null or not is_instance_valid(_http):
		return _error("http_unavailable", "O componente HTTPRequest nao esta disponivel.")

	var callback := func(
		result_code: int,
		response_code: int,
		response_headers: PackedStringArray,
		response_body: PackedByteArray
	) -> void:
		if request_id != _active_request_id:
			return
		_transport_finished.emit(request_id, {
			"result_code": result_code,
			"response_code": response_code,
			"headers": response_headers,
			"body": response_body.get_string_from_utf8(),
		})
	_http.request_completed.connect(callback, CONNECT_ONE_SHOT)
	var start_error := _http.request(url, headers, method, body)
	if start_error != OK:
		if _http.request_completed.is_connected(callback):
			_http.request_completed.disconnect(callback)
		return _error("request_start_failed", "Nao foi possivel iniciar a conexao.", int(start_error), true)

	var completed: Array = await _transport_finished
	if completed.size() < 2 or int(completed[0]) != request_id:
		return _error("cancelled", "Requisicao cancelada.")
	var raw := completed[1] as Dictionary
	if raw.has("ok"):
		return raw
	return _map_http_result(
		int(raw.get("result_code", HTTPRequest.RESULT_REQUEST_FAILED)),
		int(raw.get("response_code", 0)),
		str(raw.get("body", ""))
	)


func _map_http_result(result_code: int, response_code: int, body: String) -> Dictionary:
	if result_code != HTTPRequest.RESULT_SUCCESS:
		var code := "network_error"
		var message := "Nao foi possivel acessar a IA online. Verifique a internet."
		if result_code == HTTPRequest.RESULT_TIMEOUT:
			code = "timeout"
			message = "A IA online demorou demais para responder."
		elif result_code == HTTPRequest.RESULT_CANT_RESOLVE:
			code = "dns_unavailable"
			message = "O endereco da IA online nao pode ser localizado."
		elif result_code == HTTPRequest.RESULT_CONNECTION_ERROR:
			code = "connection_error"
		return _error(code, message, result_code, true)
	if response_code >= 200 and response_code < 300:
		return {"ok": true, "status": response_code, "body": body}

	var parsed_message := _extract_error_message(body)
	match response_code:
		400:
			return _error("bad_request", _fallback(parsed_message, "A solicitacao enviada ao Gemini e invalida."), response_code)
		401, 403:
			return _error("invalid_key", _fallback(parsed_message, "A chave Gemini e invalida ou nao possui acesso."), response_code)
		404:
			return _error("model_unavailable", _fallback(parsed_message, "O modelo Gemini configurado nao esta disponivel."), response_code)
		429:
			return _error("rate_limit", "O limite temporario da IA online foi atingido.", response_code)
		499:
			return _error("cancelled", "Requisicao cancelada.", response_code)
		500, 502, 503, 504:
			return _error("server_error", _fallback(parsed_message, "O servidor Gemini esta temporariamente indisponivel."), response_code, true)
		_:
			return _error("http_error", _fallback(parsed_message, "A IA online retornou o erro HTTP %d." % response_code), response_code)


func _parse_generation_response(body: String) -> Dictionary:
	if body.strip_edges() == "":
		return _error("empty_response", "A IA online retornou uma resposta vazia.")
	var parser := JSON.new()
	if parser.parse(body) != OK:
		return _error("invalid_json", "A IA online retornou um JSON invalido.")
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _error("invalid_json", "A IA online retornou um JSON invalido.")
	var root := parsed as Dictionary
	var candidates: Variant = root.get("candidates", [])
	if typeof(candidates) != TYPE_ARRAY or (candidates as Array).is_empty():
		var block_reason := ""
		var feedback: Variant = root.get("promptFeedback", {})
		if typeof(feedback) == TYPE_DICTIONARY:
			block_reason = str((feedback as Dictionary).get("blockReason", ""))
		if block_reason != "":
			return _error("blocked_response", "O Gemini bloqueou a resposta por seguranca: %s." % block_reason)
		return _error("empty_response", "A IA online nao retornou texto.")
	var first: Variant = (candidates as Array)[0]
	if typeof(first) != TYPE_DICTIONARY:
		return _error("invalid_response", "A estrutura da resposta online e invalida.")
	var content: Variant = (first as Dictionary).get("content", {})
	if typeof(content) != TYPE_DICTIONARY:
		return _error("empty_response", "A IA online nao retornou conteudo.")
	var parts: Variant = (content as Dictionary).get("parts", [])
	if typeof(parts) != TYPE_ARRAY:
		return _error("empty_response", "A IA online nao retornou texto.")
	var text_parts: Array[String] = []
	for part in parts as Array:
		if typeof(part) == TYPE_DICTIONARY:
			var text_value := str((part as Dictionary).get("text", "")).strip_edges()
			if text_value != "":
				text_parts.append(text_value)
	if text_parts.is_empty():
		return _error("empty_response", "A IA online retornou uma resposta vazia.")
	return {
		"ok": true,
		"text": "\n".join(text_parts),
		"finish_reason": str((first as Dictionary).get("finishReason", "")),
	}


func _build_generation_payload(question: String, context: Dictionary, history: Array[Dictionary]) -> Dictionary:
	var contents: Array[Dictionary] = []
	for item in history:
		var role := str(item.get("role", "user"))
		var gemini_role := "model" if role in ["model", "assistant", "luna"] else "user"
		contents.append({
			"role": gemini_role,
			"parts": [{"text": str(item.get("text", ""))}],
		})
	var prompt := question
	if not context.is_empty():
		prompt += "\n\nContexto interno autorizado e resumido:\n%s" % JSON.stringify(context)
	contents.append({"role": "user", "parts": [{"text": prompt}]})
	return {
		"systemInstruction": {
			"parts": [{
				"text": (
					"Voce e Luna, assistente tecnica do GRUPO RS CENTRAL. " +
					"Converse de forma natural, objetiva, amigavel, analitica e didatica. " +
					"Considere a conversa anterior e responda diretamente ao que foi perguntado, " +
					"sem repetir apresentacoes, listas prontas ou avisos desnecessarios. " +
					"Quando houver contexto interno resumido, use-o para produzir uma analise util " +
					"e deixe claro o que e fato, inferencia ou recomendacao. " +
					"Nao invente dados. Informe quando faltarem evidencias. " +
					"Trate o contexto como somente leitura. Nunca forneca codigo executavel, SQL, " +
					"comandos de sistema ou instrucoes para alterar dados automaticamente."
				)
			}]
		},
		"contents": contents,
		"generationConfig": {
			"temperature": 0.45,
			"maxOutputTokens": 1200,
		},
	}


func _ensure_http_node() -> void:
	if _http != null and is_instance_valid(_http):
		return
	_http = HTTPRequest.new()
	_http.timeout = DEFAULT_TIMEOUT_SECONDS
	add_child(_http)


func _finish(request_id: int, result: Dictionary) -> Dictionary:
	if request_id == _active_request_id:
		busy = false
		request_state_changed.emit(false)
	return result


func _error(code: String, message: String, technical_code: int = 0, retryable: bool = false) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"message": message,
		"technical_code": technical_code,
		"retryable": retryable,
	}


func _extract_error_message(body: String) -> String:
	var parser := JSON.new()
	if parser.parse(body) != OK:
		return ""
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var error_value: Variant = (parsed as Dictionary).get("error", {})
	if typeof(error_value) != TYPE_DICTIONARY:
		return ""
	return str((error_value as Dictionary).get("message", "")).left(240)


func _fallback(value: String, fallback: String) -> String:
	return fallback if value.strip_edges() == "" else value
