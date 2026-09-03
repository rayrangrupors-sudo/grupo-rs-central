## One-shot plate snapshot. Association and chip/history are strictly on demand.
extends RefCounted
signal changed
const Snapshot=preload("res://src/features/big_map/maintenance_snapshot.gd")
const Policy=preload("res://src/features/big_map/maintenance_query_policy.gd")
var host: Node
var running:=false
var _busy:=false
var generation:=0
var total:=0
var processed:=0
var failures:=0
var request_count:=0
var message:=""
var rows: Array[Dictionary]=[]
var policy=Policy.new()
var _queue: Array[Dictionary]=[]
var _active:=0
var _workers:=0
var _deadline:=0
func cancel() -> void:
	generation+=1
	running=false
	message="Busca cancelada; pontos recebidos preservados."
	changed.emit()
func current(ticket: int) -> bool:
	return running and ticket==generation and is_instance_valid(host) and Time.get_ticks_msec()<_deadline
func start(owner: Node) -> void:
	if _busy: return
	host=owner
	_busy=true
	running=true
	generation+=1
	var ticket:=generation
	_deadline=Time.get_ticks_msec()+900000
	rows.clear()
	_queue.clear()
	total=0
	processed=0
	failures=0
	request_count=0
	policy=Policy.new()
	message="Buscando a lista completa de manutenção…"
	changed.emit()
	var response: Dictionary=await host._modern_grupo_rs_read_get("/get_veiculos_intervalo.php?intervalo=Manutencao")
	if not current(ticket): _finish(ticket); return
	if not response.get("ok",false) or not str(response.get("body","")).to_lower().contains("<tbody"):
		message="Não foi possível consultar a lista de manutenção."
		_finish(ticket)
		return
	var plates:={}
	for member in host._parse_dashboard_communication_rows(str(response.get("body","")),"Manutencao"):
		var plate: String=host._normalize_location_plate(str(member.get("plate","")))
		if plate=="": continue
		if not plates.has(plate): plates[plate]={"plate":str(member.plate),"key":plate,"members":[],"attempt":0}
		plates[plate].members.append(member.duplicate(true))
	total=plates.size()
	for plate in plates: _queue.append(plates[plate])
	_workers=5
	for index in range(5): _worker(ticket)
	while _workers>0: await host.get_tree().process_frame
	if current(ticket): message="Consulta concluída: %d/%d placas; %d pendentes. Vínculo consultado ao selecionar." % [processed,total,failures]
	_finish(ticket)
func _worker(ticket: int) -> void:
	while current(ticket) and not _queue.is_empty():
		while current(ticket) and (_active>=policy.limit or Time.get_ticks_msec()<policy.cooldown_until):
			await host.get_tree().process_frame
		if not current(ticket) or _queue.is_empty(): break
		var item: Dictionary=_queue.pop_front()
		item.attempt+=1
		_active+=1
		request_count+=1
		var response: Dictionary=await host._grupo_rs_api_get("/endpoints/localizacao.php?q=%s&skip=0&take=50" % str(item.plate).uri_encode(),true,true)
		_active-=1
		if not current(ticket): break
		var row: Dictionary={}
		if not response.get("ok",false):
			var retry: bool=policy.failure(int(response.get("response_code",0)),int(item.attempt),Time.get_ticks_msec())
			if policy.stopped:
				running=false
				message="Consulta interrompida por autorização, limite ou falhas repetidas. Pontos preservados."
				changed.emit()
				break
			if retry:
				_queue.append(item)
				message="Falha transitória: reduzindo para %d consulta(s); repetição limitada das pendentes." % policy.limit
				changed.emit()
				continue
		else:
			var json:=JSON.new()
			if json.parse(str(response.get("body","")))==OK:
				var payload: Variant=json.data
				if not (payload is Dictionary and (payload.get("success",true)==false or payload.has("erro") or payload.has("error"))):
					var raw_rows: Array=host._grupo_rs_api_extract_rows(payload)
					var matches:=[]
					for raw in raw_rows:
						var candidate: Dictionary=host._grupo_rs_api_normalize_location(raw)
						if host._normalize_location_plate(str(candidate.get("plate","")))==str(item.key): matches.append(candidate)
					if raw_rows.size()<50 and matches.size()==1:
						var candidate: Dictionary=matches[0]
						if host._vehicle_location_has_valid_coordinates(candidate) and Snapshot.ignition(candidate.get("ignition"))>=0: row=candidate.duplicate(true)
		if row.is_empty(): failures+=1
		else:
			# Never present an unverified serial/client from location as confirmed.
			for key in ["serial","client","chip","phone","apn","operator"]: row.erase(key)
			row["maintenance"]=true
			row["plate_only"]=true
			row["binding_state"]="pending"
			row["maintenance_members"]=item.members
			row["source"]="API · posição por placa; vínculo pendente"
			rows.append(row)
		processed+=1
		message="%d de %d placas · até %d consultas · vínculo sob demanda" % [processed,total,policy.limit]
		changed.emit()
		await host.get_tree().process_frame
	_workers-=1
func counts() -> Dictionary:
	var on:=0
	var off:=0
	for row in rows:
		on+=int(Snapshot.ignition(row.get("ignition"))==1)
		off+=int(Snapshot.ignition(row.get("ignition"))==0)
	return {"total":total,"processed":processed,"Processados":processed,"Ignição ligada":on,"Ignição desligada":off,"Aguardando busca":maxi(0,total-processed)}
func _finish(ticket: int) -> void:
	_busy=false
	if ticket==generation:
		if Time.get_ticks_msec()>=_deadline: message="Tempo limite; pontos recebidos preservados."
		running=false
	changed.emit()
