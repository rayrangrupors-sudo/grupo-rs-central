class_name AISanitizer
extends RefCounted

const SENSITIVE_ASSIGNMENT_PATTERN := "(?i)(senha|password|passwd|token|api[_ -]?key|chave[_ -]?(da )?api|authorization)\\s*[:=]\\s*[^\\s,;]+"
const BEARER_PATTERN := "(?i)bearer\\s+[a-z0-9._~+/-]{12,}"
const PRIVATE_KEY_PATTERN := "(?i)(AIza[0-9A-Za-z_-]{20,}|sk-[0-9A-Za-z_-]{16,}|eyJ[a-zA-Z0-9_-]{12,}\\.[a-zA-Z0-9_-]+)"
const EMAIL_PATTERN := "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
const PHONE_PATTERN := "(?<!\\d)(?:\\+?55\\s*)?\\(?\\d{2}\\)?[\\s-]*\\d{4,5}[\\s-]*\\d{4}(?!\\d)"
const ICCID_PATTERN := "(?<!\\d)\\d{18,22}(?!\\d)"
const EQUIPMENT_PATTERN := "(?<!\\d)\\d{8,17}(?!\\d)"
const PLATE_PATTERN := "(?i)\\b[A-Z]{3}\\s*[- ]?\\s*[0-9][A-Z0-9][0-9A-Z]{2}\\b"
const CLIENT_PATTERN := "(?i)(cliente|titular|nome)\\s*[:=]\\s*[^|;\\n]{3,80}"


func contains_sensitive_data(text: String) -> bool:
	return (
		_has_match(text, SENSITIVE_ASSIGNMENT_PATTERN)
		or _has_match(text, BEARER_PATTERN)
		or _has_match(text, PRIVATE_KEY_PATTERN)
	)


func sanitize_text(value: String, max_chars: int = 6000) -> Dictionary:
	var result := value.strip_edges()
	var redactions := 0
	var blocked := contains_sensitive_data(result)

	var replacement := _replace_matches(result, SENSITIVE_ASSIGNMENT_PATTERN, "[CREDENCIAL REMOVIDA]")
	result = str(replacement.get("text", result))
	redactions += int(replacement.get("count", 0))
	replacement = _replace_matches(result, BEARER_PATTERN, "[TOKEN REMOVIDO]")
	result = str(replacement.get("text", result))
	redactions += int(replacement.get("count", 0))
	replacement = _replace_matches(result, PRIVATE_KEY_PATTERN, "[CHAVE REMOVIDA]")
	result = str(replacement.get("text", result))
	redactions += int(replacement.get("count", 0))
	replacement = _replace_matches(result, EMAIL_PATTERN, "[EMAIL OCULTO]")
	result = str(replacement.get("text", result))
	redactions += int(replacement.get("count", 0))
	replacement = _replace_matches(result, PHONE_PATTERN, "[TELEFONE OCULTO]")
	result = str(replacement.get("text", result))
	redactions += int(replacement.get("count", 0))
	replacement = _replace_matches(result, CLIENT_PATTERN, "Cliente [OCULTO]")
	result = str(replacement.get("text", result))
	redactions += int(replacement.get("count", 0))

	var plate_aliases: Dictionary = {}
	var plate_regex := _compile(PLATE_PATTERN)
	if plate_regex != null:
		var plate_matches := plate_regex.search_all(result)
		for match_value in plate_matches:
			var plate := str(match_value.get_string())
			if not plate_aliases.has(plate):
				plate_aliases[plate] = "Veiculo %02d" % (plate_aliases.size() + 1)
		for plate in plate_aliases:
			result = result.replace(str(plate), str(plate_aliases[plate]))
			redactions += 1

	result = _mask_long_identifiers(result, ICCID_PATTERN, "ICCID final ")
	result = _mask_long_identifiers(result, EQUIPMENT_PATTERN, "equipamento final ")
	if result.length() > max_chars:
		result = result.left(max_chars) + "\n[CONTEUDO LIMITADO]"

	return {
		"text": result,
		"redactions": redactions,
		"blocked": blocked,
		"sensitive": blocked or redactions > 0,
		"original_chars": value.length(),
		"sanitized_chars": result.length(),
	}


func sanitize_history(history: Array, max_messages: int = 20, max_chars: int = 6000) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start_index := maxi(history.size() - max_messages, 0)
	var remaining := max_chars
	for index in range(start_index, history.size()):
		if typeof(history[index]) != TYPE_DICTIONARY or remaining <= 0:
			continue
		var item := history[index] as Dictionary
		var sanitized := sanitize_text(str(item.get("text", "")), remaining)
		result.append({
			"role": "model" if str(item.get("role", "user")) in ["assistant", "model", "luna"] else "user",
			"text": str(sanitized.get("text", "")),
		})
		remaining -= str(sanitized.get("text", "")).length()
	return result


func sanitize_dictionary(value: Dictionary, max_chars: int = 6000) -> Dictionary:
	var serialized := JSON.stringify(value)
	var sanitized := sanitize_text(serialized, max_chars)
	var parsed: Variant = JSON.parse_string(str(sanitized.get("text", "{}")))
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	return {"summary": str(sanitized.get("text", ""))}


func _mask_long_identifiers(text: String, pattern: String, prefix: String) -> String:
	var regex := _compile(pattern)
	if regex == null:
		return text
	var matches := regex.search_all(text)
	var result := text
	for index in range(matches.size() - 1, -1, -1):
		var match_value: RegExMatch = matches[index]
		var raw := match_value.get_string()
		var suffix := raw.right(4)
		result = result.substr(0, match_value.get_start()) + prefix + suffix + result.substr(match_value.get_end())
	return result


func _replace_matches(text: String, pattern: String, replacement: String) -> Dictionary:
	var regex := _compile(pattern)
	if regex == null:
		return {"text": text, "count": 0}
	var matches := regex.search_all(text)
	return {"text": regex.sub(text, replacement, true), "count": matches.size()}


func _has_match(text: String, pattern: String) -> bool:
	var regex := _compile(pattern)
	return regex != null and regex.search(text) != null


func _compile(pattern: String) -> RegEx:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return null
	return regex
