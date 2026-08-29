extends Node

const MAX_CONCURRENCY := 50
const HIDE_DELAY_SECONDS := 5.0
const MAX_VISIBLE_ROWS := 4
const UI_FONT := preload("res://assets/fonts/Noto_Sans/static/NotoSans-SemiBold.ttf")
const TEXT := Color("#172638")
const MUTED := Color("#687b90")
const BLUE := Color("#0878bc")
const BLUE_DARK := Color("#123a5d")
const GREEN := Color("#10a66a")
const ORANGE := Color("#ef8a14")
const RED := Color("#df3f45")
const BORDER := Color("#d7e5f1")

var host: Node
var layer: CanvasLayer
var panel: PanelContainer
var body: VBoxContainer
var summary: Label
var collapse: Button
var hide_timer: Timer
var hide_tween: Tween
var items: Array[Dictionary] = []
var pending: Array[Dictionary] = []
var active: Dictionary = {}
var sequence := 0
var collapsed := false

func configure(owner: Node) -> void:
	host = owner
	if host != null and host.has_method("_dismiss_equipment_registration_feedback"):
		host.call("_dismiss_equipment_registration_feedback")
	_build_panel()

func has_active_or_visible() -> bool:
	return not items.is_empty() or not pending.is_empty() or not active.is_empty()

func has_serial(serial: String) -> bool:
	var target := _digits_only(serial)
	for item in items:
		if str(item.get("state", "")) in ["queued", "running", "fallback", "pending"] and _digits_only(str(item.get("serial", ""))) == target:
			return target != ""
	return false

func enqueue(kind: String, local_product: Dictionary, request: Dictionary) -> String:
	var serial := _digits_only(str(request.get("serial", request.get("remote_serial", local_product.get("imei", "")))))
	if serial == "" or has_serial(serial):
		return ""
	sequence += 1
	var id := "remote-%d-%d" % [Time.get_ticks_msec(), sequence]
	var plate := str(request.get("new_plate", request.get("plate", "")))
	var detail := "Voce pode continuar trabalhando; o aparelho permanece disponivel no estoque ate a confirmacao remota." if kind == "Cadastro" else "A operacao foi colocada na fila; a tela permanece livre para outras tarefas."
	var queued_request := request.duplicate(true)
	queued_request["serial"] = serial
	queued_request["_remote_queue_id"] = id
	items.append({"id": id, "kind": kind, "serial": serial, "plate": _format_plate(plate), "stage": "Cadastro do equipamento" if kind == "Cadastro" else "Modificando dados", "detail": detail, "state": "queued", "source": "API principal"})
	pending.append({"kind": kind, "local_product": local_product.duplicate(true), "request": queued_request, "queue_id": id})
	_show_panel()
	_rebuild()
	_drain()
	return id

func _build_panel() -> void:
	layer = CanvasLayer.new()
	layer.name = "RemoteQueueLayer"
	layer.layer = 90
	add_child(layer)
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	panel = PanelContainer.new()
	panel.name = "RemoteQueuePanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -210.0
	panel.offset_right = 210.0
	panel.offset_top = 10.0
	panel.offset_bottom = 10.0
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", _style_box(Color("#ffffff"), BORDER, 1, 14, true))
	overlay.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	stack.add_child(header)
	var title := Label.new()
	title.text = "Fila remota"
	title.add_theme_font_override("font", UI_FONT)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", BLUE_DARK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	summary = Label.new()
	summary.add_theme_font_override("font", UI_FONT)
	summary.add_theme_font_size_override("font_size", 11)
	summary.add_theme_color_override("font_color", BLUE)
	header.add_child(summary)
	collapse = Button.new()
	collapse.text = "⌃"
	collapse.tooltip_text = "Recolher fila"
	collapse.custom_minimum_size = Vector2(26, 24)
	collapse.focus_mode = Control.FOCUS_NONE
	collapse.add_theme_font_override("font", UI_FONT)
	collapse.add_theme_font_size_override("font_size", 16)
	collapse.add_theme_color_override("font_color", BLUE_DARK)
	collapse.add_theme_stylebox_override("normal", _style_box(Color("#eef6fc"), Color("#d5e6f2"), 1, 8))
	collapse.add_theme_stylebox_override("hover", _style_box(Color("#dceefb"), Color("#b6d7ec"), 1, 8))
	collapse.pressed.connect(_toggle)
	header.add_child(collapse)
	stack.add_child(HSeparator.new())
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	stack.add_child(body)
	panel.visible = false
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.97, 0.97)
	hide_timer = Timer.new()
	hide_timer.one_shot = true
	hide_timer.wait_time = HIDE_DELAY_SECONDS
	hide_timer.timeout.connect(_hide_panel)
	add_child(hide_timer)

func _toggle() -> void:
	collapsed = not collapsed
	collapse.text = "⌄" if collapsed else "⌃"
	collapse.tooltip_text = "Expandir fila" if collapsed else "Recolher fila"
	_rebuild()

func _drain() -> void:
	while not pending.is_empty() and active.size() < MAX_CONCURRENCY:
		var job: Dictionary = pending.pop_front()
		var id := str(job.get("queue_id", ""))
		active[id] = true
		# Preserve a primeira mensagem no painel até a rotina assíncrona publicar
		# a etapa técnica. Assim o aviso antigo aparece dentro da fila, sem toast.
		call_deferred("_run", job)

func _run(job: Dictionary) -> void:
	var kind := str(job.get("kind", ""))
	var request: Dictionary = job.get("request", {}) as Dictionary
	var local_product: Dictionary = job.get("local_product", {}) as Dictionary
	var id := str(job.get("queue_id", ""))
	var serial := _digits_only(str(request.get("serial", request.get("remote_serial", ""))))
	var started_at := Time.get_ticks_msec()
	var result: Dictionary
	if kind == "Cadastro":
		_update(id, "Cadastro do equipamento", "API principal consultando chip, telefone e APN")
		result = await host.call("_perform_equipment_registration", request)
		if bool(result.get("ok", false)):
			var registration_confirmation_pending := bool(result.get("confirmation_pending", false))
			if registration_confirmation_pending and typeof(result.get("request", {})) == TYPE_DICTIONARY:
				request.merge(result.get("request", {}) as Dictionary, true)
			_update(
				id,
				"Confirmacao pendente" if registration_confirmation_pending else "Confirmando placa e vinculo",
				str(result.get("message", request.get("plate", ""))) if registration_confirmation_pending else str(request.get("plate", "")),
				"pending" if registration_confirmation_pending else "running",
				"API principal"
			)
			# A API pode aceitar a solicitacao antes de confirmar a associacao.
			# Nesse estado nao podemos gravar um produto sem placa na Banco local SQL nem
			# emitir sucesso local. A finalizacao fica restrita ao retorno confirmado.
			if not registration_confirmation_pending:
				var local_result: Dictionary = await host.call("_finalize_local_equipment_registration", local_product, request)
				if not bool(local_result.get("ok", false)):
					result = {"ok": false, "message": str(local_result.get("message", "Falha ao atualizar o cadastro local."))}
				else:
					# O upsert local emite a solicitacao de sincronizacao, mas o cadastro
					# remoto so pode ser concluido depois que o Banco local SQL confirmar o
					# flush e a leitura do produto. Sem esta barreira, o fluxo de
					# Cadastro podia encerrar antes de o novo registro chegar ao Banco local SQL.
					var local_database_result: Dictionary = await host.call("_ensure_local_database_modification_saved", serial, local_result.get("product", {}) as Dictionary)
					if not bool(local_database_result.get("ok", false)):
						result = {
							"ok": false,
							"message": str(local_database_result.get("message", "O Banco local SQL nao confirmou a gravacao do cadastro.")),
							"local_database_pending": true,
						}
					else:
						result["local_database"] = local_database_result
	else:
		_update(id, "Consultando o aparelho", "API principal")
		result = await host.call("_perform_equipment_modification", request, null)
		if bool(result.get("ok", false)):
			var used_web := bool(result.get("web", false))
			_update(id, "Confirmando modificacao", "Fallback web" if used_web else "API principal", "running", "Fallback web" if used_web else "API principal")
			if host.get("store") != null:
				var local_modification: Dictionary = await host.call("_finalize_local_equipment_modification", request)
				if not bool(local_modification.get("ok", false)):
					result = {"ok": false, "message": str(local_modification.get("message", "Falha ao atualizar o cadastro local."))}
				else:
					# A persistencia ja foi confirmada. Atualize a tela/lista que o
					# operador esta vendo para nao deixar o formulario com os dados
					# antigos depois que a fila terminar.
					var local_database_result: Dictionary = await host.call("_ensure_local_database_modification_saved", serial, local_modification.get("product", {}) as Dictionary)
					if not bool(local_database_result.get("ok", false)):
						result = {"ok": false, "message": str(local_database_result.get("message", "O Banco local SQL nao confirmou a gravacao da modificacao.")), "local_database_pending": true}
					else:
						result["local_database"] = local_database_result
					if bool(result.get("ok", false)) and host.has_method("_on_remote_operation_localized"):
						host.call_deferred("_on_remote_operation_localized", kind, serial)
	if bool(result.get("ok", false)):
		var confirmation_pending := bool(result.get("confirmation_pending", false))
		_finish(
			id,
			true,
			"API aceitou; confirmacao completa pendente. Nenhum fallback foi repetido." if confirmation_pending else "Confirmado | %s" % ("cadastro e vinculo" if kind == "Cadastro" else "dados sincronizados"),
			"API principal",
			"pending" if confirmation_pending else ""
		)
		if confirmation_pending:
			_log_remote_operation_event(kind, serial, result, id, started_at, true)
		else:
			_log_remote_operation_event(kind, serial, result, id, started_at, false)
	else:
		var message := str(result.get("message", "A operacao remota nao foi confirmada."))
		_finish(
			id,
			false,
			message,
			"Fallback web" if bool(result.get("fallback_web", false)) else "API principal",
			"pending" if bool(result.get("local_database_pending", false)) else ""
		)
		_log_remote_operation_event(kind, serial, result, id, started_at, false)
	_drain()


func _log_remote_operation_event(kind: String, serial: String, result: Dictionary, correlation_id: String, started_at: int, confirmation_pending: bool) -> void:
	if host == null or not is_instance_valid(host):
		return
	var elapsed := maxi(int(Time.get_ticks_msec() - started_at), 0)
	var used_web := bool(result.get("web", false))
	var status := "progress" if confirmation_pending else ("completed" if bool(result.get("ok", false)) else "failed")
	var phase := "cadastro" if kind == "Cadastro" else "modificacao"
	var action := "Confirmacao remota pendente" if confirmation_pending else (
		"Cadastro remoto concluido" if bool(result.get("ok", false)) and kind == "Cadastro" else (
		"Modificacao remota concluida" if bool(result.get("ok", false)) else (
			"Falhou cadastro remoto" if kind == "Cadastro" else "Falhou modificacao remota")))
	var details := str(result.get("message", "")).strip_edges()
	if details == "":
		details = "%s | Serie: %s" % [kind, serial]
	else:
		details = "%s | Serie: %s" % [details, serial]
	var attempt := maxi(int(result.get("attempt", 1)), 1)
	var max_attempts := maxi(int(result.get("max_attempts", attempt)), attempt)
	var metadata := {
		"status": status,
		"phase": phase,
		"operation": phase,
		"transport": "web" if used_web else "api",
		"origin": "Portal web" if used_web else "API Grupo RS",
		"http_code": int(result.get("http_code", result.get("response_code", 0))),
		"attempt": attempt,
		"max_attempts": max_attempts,
		"latency_ms": elapsed,
		"correlation_id": correlation_id,
		"retryable": (not bool(result.get("ok", false))) and not bool(result.get("partial", false)),
		"confirmation_pending": confirmation_pending,
		"fallback_used": used_web,
		"error_code": str(result.get("error_code", "")).strip_edges(),
		"entity": "equipamento",
		"message": details,
	}
	if host.has_method("_log_system_action_event"):
		host.call("_log_system_action_event", action, details, serial, metadata)
	else:
		host.call("_log_system_action", action, details, serial)

func _update(id: String, stage: String, detail: String = "", state: String = "running", source: String = "API principal") -> void:
	for item in items:
		if str(item.get("id", "")) == id:
			item["stage"] = stage
			item["detail"] = detail if detail.strip_edges() != "" else stage
			item["state"] = state
			item["source"] = source
			_show_panel()
			_rebuild()
			return

func _finish(id: String, success: bool, detail: String, source: String, state_override: String = "") -> void:
	for item in items:
		if str(item.get("id", "")) == id:
			item["stage"] = "Concluido" if success else "Falhou"
			item["detail"] = detail
			item["state"] = state_override if state_override != "" else ("success" if success else "error")
			item["source"] = source
			active.erase(id)
			_rebuild()
			if active.is_empty() and pending.is_empty() and hide_timer != null:
				hide_timer.start(HIDE_DELAY_SECONDS)
			return

func _show_panel() -> void:
	if hide_timer != null:
		hide_timer.stop()
	if panel == null or not is_instance_valid(panel) or panel.visible:
		return
	panel.visible = true
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.97, 0.97)
	hide_tween = panel.create_tween()
	hide_tween.set_parallel(true)
	hide_tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	hide_tween.tween_property(panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hide_panel() -> void:
	if panel == null or not is_instance_valid(panel) or not active.is_empty() or not pending.is_empty():
		return
	hide_tween = panel.create_tween()
	hide_tween.tween_property(panel, "modulate:a", 0.0, 0.22)
	hide_tween.tween_property(panel, "scale", Vector2(0.98, 0.98), 0.22)
	hide_tween.finished.connect(func():
		if is_instance_valid(panel) and active.is_empty() and pending.is_empty():
			panel.visible = false
			items.clear()
			_rebuild()
	)

func _rebuild() -> void:
	if body == null or not is_instance_valid(body):
		return
	for child in body.get_children():
		child.queue_free()
	if summary != null and is_instance_valid(summary):
		summary.text = "%d operacoes  |  %d em andamento" % [items.size(), active.size()]
	body.visible = not collapsed
	if collapsed:
		return
	var shown := 0
	for item in items:
		if shown >= MAX_VISIBLE_ROWS:
			break
		body.add_child(_row(item))
		shown += 1
	if items.size() > MAX_VISIBLE_ROWS:
		var more := Label.new()
		more.text = "+ %d operacao(oes) aguardando" % (items.size() - MAX_VISIBLE_ROWS)
		more.add_theme_font_override("font", UI_FONT)
		more.add_theme_font_size_override("font_size", 11)
		more.add_theme_color_override("font_color", MUTED)
		body.add_child(more)

func _row(item: Dictionary) -> Control:
	var state := str(item.get("state", "queued"))
	var color := GREEN if state == "success" else RED if state == "error" else ORANGE if state in ["fallback", "pending"] else BLUE
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 31)
	row.add_theme_stylebox_override("panel", _style_box(Color("#fbfdff"), Color("#e4edf5"), 1, 5))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	row.add_child(margin)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 7)
	margin.add_child(line)
	var dot := Label.new()
	dot.text = "✓" if state == "success" else "!" if state == "error" else "…" if state == "pending" else "◌" if state in ["running", "fallback"] else "○"
	dot.custom_minimum_size = Vector2(17, 0)
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot.add_theme_font_override("font", UI_FONT)
	dot.add_theme_font_size_override("font_size", 13)
	dot.add_theme_color_override("font_color", color)
	line.add_child(dot)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 0)
	line.add_child(stack)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 7)
	stack.add_child(top)
	var serial := Label.new()
	serial.text = str(item.get("serial", ""))
	serial.custom_minimum_size = Vector2(88, 0)
	serial.add_theme_font_override("font", UI_FONT)
	serial.add_theme_font_size_override("font_size", 13)
	serial.add_theme_color_override("font_color", TEXT)
	top.add_child(serial)
	var stage := Label.new()
	var plate := str(item.get("plate", ""))
	stage.text = str(item.get("stage", "")) + ("  |  %s" % plate if plate != "" else "")
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.clip_text = true
	stage.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stage.add_theme_font_override("font", UI_FONT)
	stage.add_theme_font_size_override("font_size", 10)
	stage.add_theme_color_override("font_color", BLUE_DARK)
	top.add_child(stage)
	var source := Label.new()
	source.text = str(item.get("source", "API principal"))
	source.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	source.custom_minimum_size = Vector2(56, 0)
	source.add_theme_font_override("font", UI_FONT)
	source.add_theme_font_size_override("font_size", 10)
	source.add_theme_color_override("font_color", color)
	top.add_child(source)
	row.tooltip_text = str(item.get("detail", ""))
	if state in ["queued", "running", "fallback", "pending"]:
		var pulse := dot.create_tween().set_loops()
		pulse.tween_property(dot, "modulate:a", 0.45, 0.55)
		pulse.tween_property(dot, "modulate:a", 1.0, 0.55)
	return row

func _digits_only(value: String) -> String:
	var result := ""
	for character in value:
		if character >= "0" and character <= "9":
			result += character
	return result

func _format_plate(value: String) -> String:
	return str(host.call("_format_grupo_rs_vehicle_plate", value)) if host != null else value.strip_edges()

func _style_box(fill: Color, border: Color, width: int, radius: int, shadow: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	if shadow:
		box.shadow_color = Color(0, 0, 0, 0.14)
		box.shadow_size = 8
	return box
