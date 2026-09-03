## Native controls matching the approved maintenance sidebar concept.
extends RefCounted
const NAVY=Color("#103f60")
const MUTED=Color("#526780")
const BLUE=Color("#007db8")
static func label(text: String,size: int=13,color: Color=NAVY) -> Label:
	var node:=Label.new()
	node.text=text
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	return node
static func box(parent: Node,fill: Color=Color.WHITE,accent: Color=Color("#d9e2eb")) -> VBoxContainer:
	var panel:=PanelContainer.new()
	var style:=StyleBoxFlat.new()
	style.bg_color=fill
	style.border_color=accent
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left=9
	style.content_margin_right=9
	style.content_margin_top=7
	style.content_margin_bottom=7
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	var body:=VBoxContainer.new()
	body.add_theme_constant_override("separation",5)
	panel.add_child(body)
	return body
static func line(parent: Node,caption: String,value: String) -> void:
	var row:=HBoxContainer.new()
	parent.add_child(row)
	var key:=label(caption,12,MUTED)
	key.autowrap_mode=TextServer.AUTOWRAP_OFF
	key.custom_minimum_size.x=65
	row.add_child(key)
	var val:=label(value,12)
	val.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(val)
static func last_sms(events: Array, serial: String) -> String:
	if serial == "": return "Último SMS: vínculo pendente"
	var latest: Dictionary = {}
	for event in events:
		if not event is Dictionary or str(event.get("serial", "")) != serial: continue
		if latest.is_empty() or str(event.get("timestamp", "")) > str(latest.get("timestamp", "")):
			latest = event
	if latest.is_empty(): return "Nenhum SMS registrado neste sistema"
	var stamp := str(latest.get("timestamp", "")).replace("T", " ")
	if stamp == "": stamp = str(latest.get("date", "")) + " " + str(latest.get("time", ""))
	var parts := stamp.split(" ")
	if parts.size() >= 2:
		var day := parts[0].split("-")
		if day.size() == 3: stamp = "%s/%s/%s · %s" % [day[2], day[1], day[0], parts[1].left(8)]
	var status := str(latest.get("status", "Estado não informado"))
	if status == "Aceito": status = "Aceito na fila"
	return "Último SMS: %s\n%s" % [status, stamp.strip_edges() if stamp.strip_edges() != "" else "Data não registrada"]

static func render(host: Node,location: Dictionary) -> void:
	var body: VBoxContainer=host.vehicle_location_details_body
	body.add_theme_constant_override("separation",6)
	host.tracking_view.details_title.hide()
	body.add_child(label("VEÍCULO SELECIONADO",10,MUTED))
	body.add_child(label(str(location.get("plate","—")).replace(" - "," · "),23))
	var ignition: int=host.MaintenanceSnapshot.ignition(location.get("ignition"))
	body.add_child(label("●  Última ignição " + ("ligada" if ignition==1 else ("desligada" if ignition==0 else "não informada")),12,Color("#00884a") if ignition==1 else MUTED))
	line(body,"Série",host._blank(str(location.get("serial",""))))
	line(body,"Cliente",host._blank(str(location.get("client",""))))
	var date:=str(location.get("updated_at",""))
	var parts:=date.replace("T"," ").split(" ")
	if parts.size()>=2:
		var day:=parts[0].split("-")
		if day.size()==3: date="%s/%s/%s · %s"%[day[2],day[1],day[0],parts[1].left(8)]
	line(body,"Última com.",host._blank(date))
	var binding_ok: bool=not location.get("plate_only",false) or location.get("binding_state","")=="confirmed"
	if not binding_ok:
		var state:=str(location.get("binding_state","pending"))
		var messages:={"pending":"Vínculo pendente.","loading":"Consultando associação…","not_found":"Não foi encontrada uma associação para esta placa.","error":"Não foi possível consultar a associação.","ambiguous":"Mais de uma associação encontrada.","conflict":"Associação divergente da lista de manutenção."}
		body.add_child(label(str(messages.get(state,messages.error))+" Análise e SMS bloqueados.",12))
		if state!="loading":
			var retry: Button=host.tracking_view._button("Consultar associação",BLUE,Color.WHITE,0)
			retry.pressed.connect(Callable(host,"_request_maintenance_binding").bind(location.duplicate(true),true),CONNECT_DEFERRED)
			body.add_child(retry)
	var serial:=str(location.get("serial",""))
	var apn:=str(location.get("apn",""))
	var carrier:=str(location.get("operator",""))
	if carrier.to_upper()=="VIVO": carrier="Vivo"
	elif carrier.to_upper()=="CLARO": carrier="Claro"
	var color:=Color("#790ab0") if carrier.to_upper()=="VIVO" else (Color("#d52d40") if carrier.to_upper()=="CLARO" else BLUE)
	var card:=box(body,Color("#fbfdff"))
	var card_style: StyleBoxFlat=card.get_parent().get_theme_stylebox("panel").duplicate()
	card_style.border_color=color
	card_style.border_width_left=3
	card_style.border_width_top=0
	card_style.border_width_right=0
	card_style.border_width_bottom=0
	card.get_parent().add_theme_stylebox_override("panel",card_style)
	var row:=HBoxContainer.new()
	card.add_child(row)
	var provider:="Innova" if host._apn_is_hinova(apn) else ("Link" if host._apn_is_linksolutions(apn) else "—")
	var identity:=label((carrier if carrier!="" else "Operadora —")+" · "+provider,13,color)
	identity.tooltip_text="Operadora móvel · Provedor do chip"
	identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(identity)
	var chip: Dictionary=host.maintenance_chip_results.get(serial,{})
	var status:=str(chip.get("status",""))
	var status_text:="Online" if status=="online" else ("Offline" if status=="offline" else ("Indisponível" if host.maintenance_reports.has(serial) else "Não consultado"))
	if host.maintenance_analysis_busy and host.maintenance_reports.has(serial) and not host.maintenance_summaries.has(serial): status_text="Consultando…"
	var status_label:=label(status_text,11,Color("#00884a") if status=="online" else MUTED)
	status_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	row.add_child(status_label)
	var apn_row:=HBoxContainer.new()
	card.add_child(apn_row)
	var apn_label:=label("APN: "+host._blank(apn),12)
	apn_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	apn_row.add_child(apn_label)
	if binding_ok and status=="online" and not host.maintenance_analysis_busy:
		var sms: Button=host._make_icon_action_button(host.ICON_DIR+"mensagem.svg",BLUE,BLUE,Vector2(36,32),Callable(host,"_review_maintenance_sms").bind(location.duplicate(true)))
		sms.name="MaintenanceSms"
		var reason: String=host._maintenance_sms_unavailable_reason(location)
		sms.disabled=reason!=""
		sms.tooltip_text="Enviar SMS" if reason=="" else reason
		apn_row.add_child(sms)
	var sms_history := label(last_sms(host.sms_panel_events, serial if binding_ok else ""),11,MUTED)
	sms_history.name = "MaintenanceLastSms"
	card.add_child(sms_history)
	var analysis:=VBoxContainer.new()
	analysis.add_theme_constant_override("separation",5)
	body.add_child(analysis)
	analysis.add_child(label("ANÁLISE",10,MUTED))
	var summary: String=host.maintenance_summaries.get(serial,"")
	if summary!="":
		var lines:=summary.split("\n")
		analysis.add_child(label(lines[0].replace("Análise inconclusiva.","Causa não determinada").replace("Possível causa: ","Possível "),15))
		if lines.size()>1: analysis.add_child(label(lines[1].trim_prefix("Evidência: ").replace("1 registros ","1 registro "),12,MUTED))
		if lines.size()>2:
			analysis.add_child(label("Próxima ação: "+lines[2].trim_prefix("Próxima ação: "),12))
	else:
		analysis.add_child(label("Consultando registros e chip…" if host.maintenance_analysis_busy else "Consulte os registros para avaliar possíveis causas.",12,MUTED))
	var analyze: Button=host.tracking_view._button("Analisar novamente" if summary!="" else "Analisar 20 registros",BLUE,Color.WHITE,0)
	analyze.custom_minimum_size.y=34
	analyze.name="MaintenanceAnalyze"
	analyze.icon=load(host.ICON_DIR+"atualizar.svg")
	analyze.expand_icon=true
	analyze.add_theme_constant_override("icon_max_width",18)
	analyze.add_theme_font_size_override("font_size",13)
	analyze.pressed.connect(Callable(host,"_analyze_maintenance").bind(location.duplicate(true)),CONNECT_DEFERRED)
	analyze.disabled=host.maintenance_analysis_busy or host.maintenance_loader.running or not binding_ok
	analysis.add_child(analyze)
	if host.maintenance_reports.has(serial):
		var evidence:=label(str(host.maintenance_reports[serial]),12)
		var evidence_scroll:=ScrollContainer.new()
		evidence_scroll.custom_minimum_size.y=160
		evidence_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		evidence.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		evidence_scroll.add_child(evidence)
		evidence_scroll.hide()
		var expand:=Button.new()
		expand.text="Ver 20 registros   ⌄"
		expand.flat=true
		expand.add_theme_font_size_override("font_size",12)
		expand.alignment=HORIZONTAL_ALIGNMENT_LEFT
		expand.add_theme_color_override("font_color",NAVY)
		expand.pressed.connect(func(): evidence_scroll.visible=not evidence_scroll.visible; expand.text="Ocultar registros   ⌃" if evidence_scroll.visible else "Ver 20 registros   ⌄")
		analysis.add_child(expand)
		analysis.add_child(evidence_scroll)
	analysis.add_child(label("Análise experimental · não confirma defeito",10,MUTED))
