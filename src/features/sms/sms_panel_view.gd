extends RefCounted

const NAVY := Color("#102e50")
const BLUE := Color("#0876e8")
const ORANGE := Color("#ff8000")
const MUTED := Color("#596f89")
const BORDER := Color("#dfe8f2")
const FONT := preload("res://assets/fonts/Noto_Sans/static/NotoSans-Regular.ttf")
const BOLD := preload("res://assets/fonts/Noto_Sans/static/NotoSans-SemiBold.ttf")
const PAGE_SIZE := 6

static func text(value: String, size: int = 14, color: Color = NAVY, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", BOLD if bold else FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

static func style(bg: Color = Color.WHITE, border: Color = BORDER, radius: int = 9, padding: int = 16) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box

static func card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", style())
	return panel

static func row(gap: int = 14) -> HBoxContainer:
	var result := HBoxContainer.new()
	result.add_theme_constant_override("separation", gap)
	return result

static func stack(gap: int = 8) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.add_theme_constant_override("separation", gap)
	return result

static func spacer() -> Control:
	var result := Control.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result

static func button(caption: String, action: Callable, filled: bool = false) -> Button:
	var result := Button.new()
	result.text = caption
	result.custom_minimum_size.y = 40
	result.add_theme_font_override("font", FONT)
	result.add_theme_font_size_override("font_size", 14)
	for state in ["normal", "hover", "pressed", "focus"]:
		result.add_theme_stylebox_override(state, style(BLUE if filled else Color.WHITE, BLUE if filled else BORDER, 6, 10))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		result.add_theme_color_override(state, Color.WHITE if filled else NAVY)
	result.add_theme_stylebox_override("disabled",style(Color("#fafcff"),BORDER,6,10))
	result.add_theme_color_override("font_disabled_color",Color("#a5b5c8"))
	result.pressed.connect(action)
	return result

static func pill(caption: String, color: Color, background: Color) -> PanelContainer:
	var result := PanelContainer.new()
	result.add_theme_stylebox_override("panel", style(background, background, 14, 8))
	result.add_child(text(caption, 12, color))
	return result

static func metric(title: String, value: String, detail: String, symbol: String, color: Color) -> Control:
	var panel := card()
	panel.custom_minimum_size.y = 108
	var line := row(16)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(line)
	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(48,48)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.add_theme_stylebox_override("panel", style(color,color,24,0))
	var glyph := text(symbol,25,Color.WHITE,true)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_child(glyph)
	line.add_child(icon)
	var labels := stack(4)
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(labels)
	labels.add_child(text(title,14,MUTED))
	labels.add_child(text(value,28,color,true))
	labels.add_child(text(detail,12,MUTED))
	return panel

static func bar(value: int, maximum: int, color: Color) -> ProgressBar:
	var result := ProgressBar.new()
	result.custom_minimum_size.y = 9
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.show_percentage = false
	result.max_value = maxi(1,maximum)
	result.value = value
	result.add_theme_stylebox_override("background",style(Color("#edf3fa"),Color("#edf3fa"),5,0))
	result.add_theme_stylebox_override("fill",style(color,color,5,0))
	return result

static func date_label(value: String) -> String:
	var clean := value.replace("T"," ")
	if clean.length() >= 16 and clean.substr(4,1) == "-":
		return "%s/%s/%s %s" % [clean.substr(8,2),clean.substr(5,2),clean.substr(0,4),clean.substr(11,5)]
	return clean

static func build(host) -> Control:
	if host.sms_recovery_report_open:
		return recovery_report(host)
	var root := stack(14)
	root.name = "SmsPanelView"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var heading := row(22)
	heading.custom_minimum_size.y = 64
	root.add_child(heading)
	var titles := stack(2)
	titles.add_child(text("Painel SMS",32,NAVY,true))
	titles.add_child(text("Controle de envios e consumo",15,MUTED))
	heading.add_child(titles)
	heading.add_child(spacer())
	var health_color := Color("#008c50") if host.experttexting_last_error == "" and host.experttexting_last_sync_at > 0 else Color("#aa6410")
	var health := pill(host._experttexting_status_label(),health_color,Color(health_color,0.07))
	health.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(health)
	var updated := "Ainda não atualizado"
	if host.experttexting_last_sync_at > 0:
		var local_time := Time.get_datetime_string_from_unix_time(host.experttexting_last_sync_at + int(Time.get_time_zone_from_system().bias)*60)
		updated = "Atualizado às " + local_time.substr(11,5)
	heading.add_child(text(updated,12,MUTED))
	var refresh := button("↻  Atualizar",func(): host._poll_experttexting("manual"))
	refresh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(refresh)
	var events: Array[Dictionary] = host._sms_panel_events_filtered()
	var today := Time.get_date_string_from_system()
	var today_count := 0
	var today_cost := 0.0
	var counts := {"Aceito":0,"Enviado":0,"Entregue":0,"Falho":0}
	var origins: Dictionary = {}
	for event in events:
		if str(event.get("date",str(event.get("timestamp","")).left(10))) == today:
			today_count += 1
			today_cost += float(event.get("price",0))
		var status := str(event.get("status",""))
		if counts.has(status): counts[status] += 1
		var origin := str(event.get("origin","Programa"))
		origins[origin] = int(origins.get(origin,0)) + 1
	var metrics := row()
	root.add_child(metrics)
	metrics.add_child(metric("Saldo disponível",host._format_monitor_usd(host.experttexting_last_balance).replace(".",",") if host.experttexting_last_balance >= 0 else "—",host._experttexting_status_label(),"▣",BLUE))
	metrics.add_child(metric("Solicitados hoje",str(today_count),"Programa + portal","➤",BLUE))
	metrics.add_child(metric("Aceitos pelo serviço",str(counts.Aceito),"Entrega ainda não confirmada","✓",BLUE))
	metrics.add_child(metric("Custo hoje",host._format_monitor_usd(today_cost).replace(".",","),"Estimativa","$",ORANGE))
	var summaries := row()
	summaries.custom_minimum_size.y = 150
	root.add_child(summaries)
	var status_card := card()
	summaries.add_child(status_card)
	var status_stack := stack(16)
	status_card.add_child(status_stack)
	status_stack.add_child(text("Status dos envios",17,NAVY,true))
	var segments := row(0)
	for index in range(4):
		var key: String = counts.keys()[index]
		if counts[key] > 0:
			var segment := bar(1,1,[BLUE,Color("#79b5f5"),Color("#0eaf73"),Color("#ec5265")][index])
			segment.size_flags_stretch_ratio = counts[key]
			segments.add_child(segment)
	if segments.get_child_count() == 0: segments.add_child(bar(0,1,BLUE))
	status_stack.add_child(segments)
	var stat_tiles := row(12)
	status_stack.add_child(stat_tiles)
	for index in range(4):
		var tile := card()
		tile.add_theme_stylebox_override("panel",style(Color.WHITE,BORDER,6,8))
		stat_tiles.add_child(tile)
		var labels := stack(2)
		tile.add_child(labels)
		labels.add_child(text("●  "+["Aceitos","Enviados","Entregues","Falhos"][index],12,[BLUE,Color("#79b5f5"),Color("#0eaf73"),Color("#ec5265")][index]))
		var count := text(str(counts[counts.keys()[index]]),20)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		labels.add_child(count)
	var origin_card := card()
	summaries.add_child(origin_card)
	var origin_stack := stack(18)
	origin_card.add_child(origin_stack)
	origin_stack.add_child(text("Origem dos envios",17,NAVY,true))
	var max_origin := 1
	for value in origins.values(): max_origin = maxi(max_origin,int(value))
	if origins.is_empty(): origin_stack.add_child(text("Nenhum envio registrado",14,MUTED))
	for origin in origins:
		var origin_row := row(14)
		origin_stack.add_child(origin_row)
		var caption := text(origin,13)
		caption.custom_minimum_size.x = 172
		origin_row.add_child(caption)
		origin_row.add_child(bar(origins[origin],max_origin,ORANGE if str(origin).contains("Mapa") else BLUE))
		origin_row.add_child(text(str(origins[origin]),16))
	var recovery_card := card()
	summaries.add_child(recovery_card)
	var recovery_stack := stack(8)
	recovery_card.add_child(recovery_stack)
	var recovery_title := row(8)
	recovery_stack.add_child(recovery_title)
	recovery_title.add_child(text("Funcionando após SMS",17,NAVY,true))
	recovery_title.add_child(spacer())
	var report_button := button("Ver relatório",host._open_sms_recovery_report)
	report_button.custom_minimum_size.y = 30
	recovery_title.add_child(report_button)
	var shown := 0
	for event in host.sms_panel_events:
		var recovery_status := str(event.get("recovery_status", "pending"))
		if not recovery_status in ["normalized", "observing"]:
			continue
		var compact := row(8)
		recovery_stack.add_child(compact)
		var identity := "%s · %s" % [str(event.get("plate", "Sem placa")),str(event.get("serial", ""))]
		compact.add_child(text(identity,11,NAVY,true))
		compact.add_child(spacer())
		compact.add_child(text("Normalizado" if recovery_status == "normalized" else "Em observação",11,Color("#009c66") if recovery_status == "normalized" else ORANGE,true))
		shown += 1
		if shown >= 3: break
	if shown == 0:
		recovery_stack.add_child(text("Nenhum retorno confirmado ainda.",12,MUTED))
	recovery_stack.add_child(text("ⓘ  Verificação ativa somente com este painel aberto.",10,MUTED))
	root.add_child(history(host,events))
	return root


static func recovery_report(host) -> Control:
	var root := stack(14)
	root.name = "SmsPanelView"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var heading := row(12)
	root.add_child(heading)
	heading.add_child(button("‹  Voltar",host._close_sms_recovery_report))
	var titles := stack(2)
	titles.add_child(text("Retorno após SMS",28,NAVY,true))
	titles.add_child(text("Acompanhamentos salvos; casos normalizados não são consultados novamente.",13,MUTED))
	heading.add_child(titles)
	heading.add_child(spacer())
	heading.add_child(button("↓  Exportar XLSX",host._export_sms_recovery_xlsx,true))
	var panel := card()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	var body := stack(0)
	panel.add_child(body)
	body.add_child(table_row(["Placa","Série","Origem","SMS enviado","Primeiro retorno","Última comunicação","Estado"],true))
	var count := 0
	for event in host.sms_panel_events:
		var status := str(event.get("recovery_status", "pending"))
		if status == "not_applicable": continue
		var label: String = str({"normalized":"Normalizado","observing":"Em observação","pending":"Sem retorno","unavailable":"Consulta indisponível"}.get(status,"Sem retorno"))
		body.add_child(table_row([str(event.get("plate","—")),str(event.get("serial","")),str(event.get("origin","")),date_label(str(event.get("timestamp",""))),date_label(str(event.get("recovery_first_communication",""))),date_label(str(event.get("recovery_last_communication",""))),label],false))
		count += 1
	if count == 0: body.add_child(text("Nenhum acompanhamento registrado.",14,MUTED))
	root.add_child(text("A verificação para imediatamente ao sair do Painel SMS.",12,MUTED))
	return root

static func history(host, events: Array[Dictionary]) -> Control:
	var panel := card()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := stack(10)
	panel.add_child(body)
	var heading := row()
	body.add_child(heading)
	var titles := stack(0)
	titles.add_child(text("Histórico de SMS",21,NAVY,true))
	titles.add_child(text("%d registros" % events.size(),13,MUTED))
	heading.add_child(titles)
	heading.add_child(spacer())
	heading.add_child(button("↓  Exportar XLSX",host._export_sms_panel_xlsx,true))
	var filters := row(12)
	filters.name = "SmsHistoryFilters"
	body.add_child(filters)
	var search := LineEdit.new()
	search.name = "SmsHistorySearch"
	search.placeholder_text = "Buscar série, telefone ou ID"
	search.text = host.sms_panel_search_filter
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.size_flags_stretch_ratio = 1.5
	input_style(search)
	search.text_submitted.connect(func(value): host.sms_panel_search_filter=value.strip_edges(); host.sms_panel_page=0; host._show_sms_panel())
	filters.add_child(search)
	filters.add_child(select(host,["Todos","Aceito","Enviado","Entregue","Falho"],host.sms_panel_status_filter,"Todos os status",false))
	var origins: Array[String] = ["Todos","Programa","Portal","Mapa Grande · manual"]
	for event in host.sms_panel_events:
		var origin := str(event.get("origin",""))
		if origin != "" and not origins.has(origin): origins.append(origin)
	filters.add_child(select(host,origins,host.sms_panel_origin_filter,"Todas as origens",true))
	var dates := row(4)
	var date_panel := PanelContainer.new()
	date_panel.add_theme_stylebox_override("panel",style(Color.WHITE,BORDER,6,0))
	date_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	date_panel.size_flags_stretch_ratio = 1.5
	date_panel.add_child(dates)
	filters.add_child(date_panel)
	host.sms_panel_date_input = LineEdit.new()
	host.sms_panel_end_date_input = LineEdit.new()
	for index in range(2):
		var field: LineEdit = host.sms_panel_date_input if index == 0 else host.sms_panel_end_date_input
		field.placeholder_text = "Data inicial" if index == 0 else "Data final"
		field.text = host._system_log_calendar_display_value(host.sms_panel_start_date if index == 0 else host.sms_panel_end_date)
		input_style(field)
		field.add_theme_stylebox_override("normal",style(Color.TRANSPARENT,Color.TRANSPARENT,0,8))
		field.custom_minimum_size.x = 134
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dates.add_child(host._make_system_log_date_picker(field,index == 1))
		field.text_submitted.connect(func(_value): host.sms_panel_page=0; host._refresh_sms_panel_date_filters())
		if index == 0: dates.add_child(text("—",14,MUTED))
	var apply := button("⌕",func(): host.sms_panel_search_filter=search.text.strip_edges(); host.sms_panel_page=0; host._refresh_sms_panel_date_filters())
	apply.tooltip_text = "Aplicar filtros e período (DD/MM/AAAA)"
	filters.add_child(apply)
	var clear := button("×",host._clear_sms_panel_filters)
	clear.tooltip_text = "Limpar todos os filtros"
	filters.add_child(clear)
	var columns := ["Data e hora","Série","Telefone","Origem","Status","ID","Custo"]
	body.add_child(table_row(columns,true))
	var rows := stack(0)
	rows.name = "SmsHistoryRows"
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(rows)
	host.sms_panel_page = clampi(host.sms_panel_page,0,maxi(0,ceili(float(events.size())/PAGE_SIZE)-1))
	var start: int = host.sms_panel_page*PAGE_SIZE
	for event in events.slice(start,mini(start+PAGE_SIZE,events.size())):
		rows.add_child(table_row([date_label(str(event.get("timestamp",""))),str(event.get("serial","")),str(event.get("phone","")),str(event.get("origin","")),str(event.get("status","")),str(event.get("message_id","")),host._format_monitor_usd(float(event.get("price",0))).replace(".",",")],false))
	if events.is_empty(): rows.add_child(text("Nenhum envio registrado para os filtros atuais.",14,MUTED))
	var footer := row()
	body.add_child(footer)
	footer.add_child(text("ⓘ  Aceito pelo serviço não significa entregue ao aparelho.",12,MUTED))
	footer.add_child(spacer())
	var previous := button("‹",func(): host.sms_panel_page-=1; host._show_sms_panel())
	previous.disabled = start == 0
	footer.add_child(previous)
	footer.add_child(text("%d–%d de %d" % [start+1 if not events.is_empty() else 0,mini(start+PAGE_SIZE,events.size()),events.size()],13,MUTED))
	var next := button("›",func(): host.sms_panel_page+=1; host._show_sms_panel())
	next.disabled = start+PAGE_SIZE >= events.size()
	footer.add_child(next)
	return panel

static func input_style(field: LineEdit) -> void:
	field.custom_minimum_size.y = 40
	field.add_theme_font_override("font",FONT)
	field.add_theme_font_size_override("font_size",13)
	field.add_theme_color_override("font_color",NAVY)
	field.add_theme_color_override("font_placeholder_color",MUTED)
	field.add_theme_stylebox_override("normal",style(Color.WHITE,BORDER,6,10))
	field.add_theme_stylebox_override("focus",style(Color.WHITE,BLUE,6,10))

static func select(host, options: Array, selected: String, caption: String, origin: bool) -> OptionButton:
	var result := OptionButton.new()
	result.custom_minimum_size = Vector2(165,40)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option in options: result.add_item(caption if option == "Todos" else option)
	result.select(maxi(0,options.find(selected)))
	result.add_theme_font_override("font",FONT)
	result.add_theme_font_size_override("font_size",13)
	for state in ["normal","hover","pressed","focus"]: result.add_theme_stylebox_override(state,style(Color.WHITE,BORDER,6,10))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: result.add_theme_color_override(state,NAVY)
	result.item_selected.connect(func(index):
		if origin: host.sms_panel_origin_filter=options[index]
		else: host.sms_panel_status_filter=options[index]
		host.sms_panel_page=0
		host._show_sms_panel()
	)
	return result

static func table_row(values: Array, header: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 32 if header else 38
	var box := style(Color("#f7fafe") if header else Color.WHITE,BORDER,0,5)
	box.set_border_width_all(0)
	box.border_width_bottom = 1
	panel.add_theme_stylebox_override("panel",box)
	var line := row(12)
	panel.add_child(line)
	var weights := [1.4,1.15,1.15,1.65,1.1,1.0,0.9]
	for index in range(values.size()):
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = weights[index]
		line.add_child(cell)
		if index == 4 and not header:
			var status := str(values[index])
			var color := Color("#d94459") if status == "Falho" else (Color("#009c66") if status == "Entregue" else BLUE)
			var badge := pill(status,color,Color(color,0.08))
			badge.add_theme_stylebox_override("panel",style(Color(color,0.08),Color(color,0.08),12,4))
			badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cell.add_child(badge)
		else:
			var label := text(str(values[index]),12 if header else 13,MUTED if header else NAVY)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.clip_text = true
			label.tooltip_text = str(values[index])
			cell.add_child(label)
	return panel
