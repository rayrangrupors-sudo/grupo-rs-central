extends SceneTree

const MainScene := preload("res://scenes/estoque_profissional.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard: Node = MainScene.instantiate()
	root.add_child(dashboard)
	await process_frame

	var sample := "24764\tAAA - 043\t024298056\tSelecionar\tDesativar\n" \
		+ "24765\tAAA - 044\t024296621\tSelecionar\tDesativar\n" \
		+ "24769\tAAA - 052\t024297298\tSelecionar\tDesativar\n" \
		+ "23659\tAAA - 053\t024306149\tSelecionar\tDesativar\n" \
		+ "24771\tAAA - 054\t024313038\tSelecionar\tDesativar\n" \
		+ "24770\tAAA - 055\t024273216\tSelecionar\tDesativar\n" \
		+ "24772\tAAA - 056\t024317294"

	var parsed: Dictionary = dashboard.call("_parse_bulk_registration_text", sample)
	var parsed_rows: Array = parsed.get("rows", [])
	_check(parsed_rows.size() == 7, "Amostra nao produziu 7 registros.")
	_check((parsed.get("errors", []) as Array).is_empty(), "Amostra gerou erro de leitura: %s" % str(parsed.get("errors", [])))
	if parsed_rows.size() == 7:
		var first: Dictionary = parsed_rows[0]
		_check(str(first.get("plate", "")) == "AAA - 043", "Placa da primeira linha nao foi normalizada.")
		_check(str(first.get("serial", "")) == "024298056", "Serie da primeira linha nao foi preservada.")

	var analysis: Dictionary = dashboard.call("_analyze_bulk_input", sample)
	_check((analysis.get("clean_rows", []) as Array).size() == 7, "Analise nao manteve os 7 registros limpos.")
	_check(int(analysis.get("duplicate_count", -1)) == 0, "Amostra foi marcada como duplicada.")
	_check(int(analysis.get("auxiliary_fields", 0)) == 19, "Colunas auxiliares nao foram contabilizadas corretamente.")
	var cleaned := str(dashboard.call("_bulk_clean_rows_to_text", analysis.get("clean_rows", [])))
	_check(cleaned.begins_with("AAA - 043\t024298056"), "Resultado limpo nao inicia com placa e serie.")
	_check(not cleaned.contains("Selecionar") and not cleaned.contains("Desativar"), "Resultado limpo manteve colunas auxiliares.")

	var duplicate_sample := sample + "\n24764\tAAA - 043\t024298056\tSelecionar\tDesativar"
	var duplicate_analysis: Dictionary = dashboard.call("_analyze_bulk_input", duplicate_sample)
	_check(int(duplicate_analysis.get("duplicate_count", 0)) == 1, "Duplicata exata nao foi detectada.")

	var conflict_sample := sample + "\n24764\tAAA - 099\t024298056\tSelecionar\tDesativar"
	var conflict_analysis: Dictionary = dashboard.call("_analyze_bulk_input", conflict_sample)
	_check(not (conflict_analysis.get("conflicts", []) as Array).is_empty(), "Conflito de serie/placa nao foi detectado.")

	var view := dashboard.call("_build_bulk_registration_view") as Control
	root.add_child(view)
	await process_frame
	_check(_find_text(view, "Analisar dados") != null, "Botao Analisar dados nao foi criado.")
	_check(_find_text(view, "Limpar e organizar") != null, "Botao Limpar e organizar nao foi criado.")
	_check(_find_text(view, "Desfazer") != null, "Botao Desfazer nao foi criado.")
	_check(_find_text(view, "Copiar resultado") != null, "Botao Copiar resultado nao foi criado.")
	_check(_find_text(view, "Reset SMS massa") == null, "SMS em massa ainda aparece no Cadastro em massa.")
	_check(_find_text(view, "Registros brutos importados do arquivo.") != null, "Subtitulo dos dados de entrada nao segue a previa.")
	_check(_find_text(view, "Dados limpos e organizados para importação.") != null, "Subtitulo da previa inteligente nao segue a previa.")
	_check(_find_text(view, "Resultado") == null, "Coluna Resultado extra ainda aparece na previa.")

	var bulk_edit := dashboard.get("bulk_text_edit") as TextEdit
	_check(bulk_edit != null, "Campo Dados de entrada nao foi criado.")
	if bulk_edit != null:
		bulk_edit.text = sample
		dashboard.call("_preview_bulk_registration_text", sample)
		dashboard.call("_request_bulk_cleanup")
		await process_frame
		var cleaned_after_action := bulk_edit.text
		_check(cleaned_after_action == cleaned, "Botao Limpar e organizar nao aplicou o resultado esperado.")
		dashboard.call("_undo_bulk_cleanup")
		await process_frame
		_check(bulk_edit.text == sample, "Botao Desfazer nao restaurou o texto original.")

	_finish()


func _find_text(node: Node, wanted: String) -> Node:
	if node is Label and (node as Label).text == wanted:
		return node
	if node is Button and (node as Button).text == wanted:
		return node
	for child in node.get_children():
		var found := _find_text(child, wanted)
		if found != null:
			return found
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("BULK_CLEANUP_CHECK_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
