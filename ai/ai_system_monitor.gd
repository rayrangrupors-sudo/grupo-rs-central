class_name AISystemMonitor
extends Node

signal alert_created(alert: Dictionary)
signal alerts_changed(alerts: Array)

const STATE_PATH := "user://luna_monitor_state.json"
const ALERT_COOLDOWN_SECONDS := 21600
const MAX_ALERTS := 30

var _provider: AIContextProvider
var _settings: AISettings
var _timer: Timer
var _alerts: Array[Dictionary] = []
var _shown_at_by_fingerprint: Dictionary = {}
var _last_available_count := -1


func setup(provider: AIContextProvider, settings: AISettings) -> void:
	_provider = provider
	_settings = settings
	_load_state()
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.timeout.connect(run_now)
	add_child(_timer)
	apply_settings()


func apply_settings() -> void:
	if _timer == null or _settings == null:
		return
	_timer.wait_time = float(_settings.get_value("monitor_interval_seconds", 300))
	if bool(_settings.get_value("monitor_enabled", true)):
		_timer.start()
	else:
		_timer.stop()


func run_now() -> Array[Dictionary]:
	if _provider == null or not _provider.is_ready():
		return get_alerts()
	_provider.invalidate()
	var candidates: Array[Dictionary] = []
	_check_low_stock(candidates)
	_check_maintenance(candidates)
	_check_inconsistencies(candidates)
	_check_sync(candidates)
	_check_storage(candidates)
	_check_stock_change(candidates)
	_check_runtime_rules(candidates)
	for alert in candidates:
		_publish_if_new(alert)
	_save_state()
	alerts_changed.emit(get_alerts())
	return get_alerts()


func get_alerts() -> Array[Dictionary]:
	return _alerts.duplicate(true)


func dismiss_alert(alert_id: String) -> void:
	for index in range(_alerts.size() - 1, -1, -1):
		if str(_alerts[index].get("id", "")) == alert_id:
			_alerts.remove_at(index)
	_save_state()
	alerts_changed.emit(get_alerts())


func clear_alerts() -> void:
	_alerts.clear()
	_save_state()
	alerts_changed.emit([])


func _check_low_stock(result: Array[Dictionary]) -> void:
	var inventory := _provider.get_inventory_summary()
	var threshold := int(_settings.get_value("low_stock_threshold", 5))
	var available := int(inventory.get("disponiveis", 0))
	var low_stock := int(inventory.get("estoque_baixo", 0))
	if available <= threshold or low_stock > 0:
		result.append(_alert(
			"low_stock",
			"warning",
			"Estoque requer atencao",
			"Ha %d equipamento(s) disponivel(is) e %d item(ns) com estoque baixo." % [available, low_stock],
			[{"id": "open_inventory", "label": "Ver estoque"}]
		))


func _check_maintenance(result: Array[Dictionary]) -> void:
	var inventory := _provider.get_inventory_summary()
	var maintenance := _provider.get_maintenance_summary()
	var total := maxi(int(inventory.get("total", 0)), 1)
	var open_count := int(maintenance.get("abertas", 0))
	if open_count >= 5 and float(open_count) / float(total) >= 0.12:
		result.append(_alert(
			"maintenance_high",
			"warning",
			"Volume incomum em manutencao",
			"%d equipamento(s) estao na lista de manutencao." % open_count,
			[{"id": "open_maintenance", "label": "Ver manutencoes"}]
		))


func _check_inconsistencies(result: Array[Dictionary]) -> void:
	var issues := _provider.find_data_inconsistencies()
	var total := 0
	for issue in issues:
		total += int(issue.get("count", 0))
	var duplicate_iccid := _provider.get_duplicate_iccid_summary()
	total += int(duplicate_iccid.get("records", 0))
	if total > 0:
		result.append(_alert(
			"data_inconsistencies",
			"warning",
			"Dados incompletos ou inconsistentes",
			"Foram encontradas %d ocorrencia(s) que precisam de revisao." % total,
			[{"id": "open_inventory", "label": "Ver registros"}, {"id": "ask_luna", "label": "Pedir analise da Luna"}]
		))


func _check_sync(result: Array[Dictionary]) -> void:
	var sync := _provider.get_sync_status()
	if not bool(sync.get("available", false)):
		return
	var failures := int(sync.get("failures", 0))
	if not bool(sync.get("configured", false)) or failures >= 2:
		result.append(_alert(
			"sync_failure",
			"error",
			"Falha de sincronizacao",
			"A sincronizacao apresenta %d falha(s) consecutiva(s)." % failures,
			[{"id": "open_settings", "label": "Abrir configuracoes"}]
		))


func _check_storage(result: Array[Dictionary]) -> void:
	var health := _provider.get_system_health_summary()
	if bool(health.get("available", false)) and not bool(health.get("remote_available", true)):
		result.append(_alert(
			"remote_storage_unavailable",
			"error",
			"Banco remoto indisponivel",
			"O sistema permanece em modo local, mas o armazenamento remoto nao esta acessivel.",
			[{"id": "open_settings", "label": "Ver conexao"}]
		))


func _check_stock_change(result: Array[Dictionary]) -> void:
	var inventory := _provider.get_inventory_summary()
	var available := int(inventory.get("disponiveis", 0))
	if _last_available_count >= 0:
		var delta := available - _last_available_count
		var threshold := maxi(5, int(ceil(float(maxi(_last_available_count, 1)) * 0.20)))
		if absi(delta) >= threshold:
			result.append(_alert(
				"stock_change",
				"warning",
				"Alteracao importante no estoque",
				"A quantidade disponivel mudou de %d para %d desde a ultima verificacao." % [_last_available_count, available],
				[{"id": "open_inventory", "label": "Revisar estoque"}]
			))
	_last_available_count = available


func _check_runtime_rules(result: Array[Dictionary]) -> void:
	var runtime := _provider.monitoring_context()
	var stopped := int(runtime.get("stopped_over_limit", 0))
	if stopped > 0:
		result.append(_alert(
			"stopped_equipment",
			"warning",
			"Equipamentos parados por muito tempo",
			"%d equipamento(s) ultrapassaram o periodo de comunicacao esperado." % stopped,
			[{"id": "open_logs", "label": "Ver eventos"}]
		))
	var consecutive_failures := int(runtime.get("consecutive_failures", 0))
	if consecutive_failures >= 3:
		result.append(_alert(
			"consecutive_failures",
			"error",
			"Falhas consecutivas",
			"Foram registradas %d falhas consecutivas no ciclo operacional." % consecutive_failures,
			[{"id": "open_logs", "label": "Ver falhas"}]
		))
	var last_backup_at := str(runtime.get("last_backup_at", "")).strip_edges()
	if last_backup_at != "":
		var backup_unix := int(Time.get_unix_time_from_datetime_string(last_backup_at))
		var now := int(Time.get_unix_time_from_system())
		if backup_unix > 0 and now - backup_unix > 604800:
			result.append(_alert(
				"backup_late",
				"warning",
				"Backup atrasado",
				"O ultimo backup registrado tem mais de 7 dias.",
				[{"id": "open_settings", "label": "Ver backup"}]
			))


func _alert(id: String, severity: String, title: String, message: String, actions: Array) -> Dictionary:
	return {
		"id": id,
		"severity": severity,
		"title": title,
		"message": message,
		"actions": actions,
		"created_at": Time.get_datetime_string_from_system(false, true),
	}


func _publish_if_new(alert: Dictionary) -> void:
	var fingerprint := ("%s|%s" % [str(alert.get("id", "")), str(alert.get("message", ""))]).sha256_text()
	var now := int(Time.get_unix_time_from_system())
	var last_shown := int(_shown_at_by_fingerprint.get(fingerprint, 0))
	if last_shown > 0 and now - last_shown < ALERT_COOLDOWN_SECONDS:
		return
	_shown_at_by_fingerprint[fingerprint] = now
	_alerts.push_front(alert.duplicate(true))
	if _alerts.size() > MAX_ALERTS:
		_alerts.resize(MAX_ALERTS)
	alert_created.emit(alert.duplicate(true))


func _load_state() -> void:
	if not FileAccess.file_exists(STATE_PATH):
		return
	var file := FileAccess.open(STATE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var state := parsed as Dictionary
	if typeof(state.get("alerts", [])) == TYPE_ARRAY:
		for item in state.get("alerts", []):
			if typeof(item) == TYPE_DICTIONARY:
				_alerts.append((item as Dictionary).duplicate(true))
	if typeof(state.get("shown_at", {})) == TYPE_DICTIONARY:
		_shown_at_by_fingerprint = (state.get("shown_at", {}) as Dictionary).duplicate(true)
	_last_available_count = int(state.get("last_available_count", -1))


func _save_state() -> void:
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"alerts": _alerts,
		"shown_at": _shown_at_by_fingerprint,
		"last_available_count": _last_available_count,
	}, "\t"))
