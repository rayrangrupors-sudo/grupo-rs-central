extends SceneTree

const GuardianScript := preload("res://src/system_guardian.gd")
const TEST_STATE_PATH := "user://__codex_system_guardian_state.json"

var repair_calls: Array[String] = []
var audit_events: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var guardian: Node = GuardianScript.new()
	root.add_child(guardian)
	guardian.call(
		"configure",
		"test_branch",
		Callable(self, "_probe_health"),
		Callable(self, "_repair"),
		Callable(self, "_audit"),
		TEST_STATE_PATH,
		10
	)

	var snapshot: Dictionary = await guardian.call("run_now", "test")
	if repair_calls != ["restart_timers"]:
		_fail("O assistente nao limitou a execucao a correcao segura esperada: %s" % str(repair_calls))
		return

	var routines := _component(snapshot, "routines")
	if str(routines.get("status", "")) != "recovered" or str(routines.get("automation", "")) != "repaired":
		_fail("A rotina permitida nao foi recuperada.")
		return

	var unsafe := _component(snapshot, "unsafe_sms")
	if str(unsafe.get("automation", "")) != "blocked":
		_fail("Uma acao fora da lista segura nao foi bloqueada.")
		return
	var delayed := _component(snapshot, "delayed_session")
	if str(delayed.get("automation", "")) != "observing":
		_fail("A anomalia remota nao aguardou confirmacao antes de agir.")
		return
	if repair_calls.has("send_sms"):
		_fail("O teste tentou enviar SMS por meio do assistente.")
		return
	if not _has_audit_kind("blocked") or not _has_audit_kind("repair"):
		_fail("Os eventos de bloqueio e correcao nao foram auditados.")
		return
	var second_snapshot: Dictionary = await guardian.call("run_now", "test")
	if repair_calls != ["restart_timers", "renew_linksolutions_session"]:
		_fail("A correcao confirmada em dois ciclos nao respeitou a sequencia segura: %s" % str(repair_calls))
		return
	var delayed_repaired := _component(second_snapshot, "delayed_session")
	if str(delayed_repaired.get("status", "")) != "recovered":
		_fail("A sessao simulada nao foi recuperada depois da confirmacao.")
		return
	if int(second_snapshot.get("cycle_count", 0)) != 2:
		_fail("A contagem de ciclos nao foi atualizada.")
		return
	if not FileAccess.file_exists(TEST_STATE_PATH):
		_fail("O estado persistente nao foi criado.")
		return

	guardian.call("shutdown")
	guardian.queue_free()
	await process_frame

	var restored: Node = GuardianScript.new()
	root.add_child(restored)
	restored.call(
		"configure",
		"test_branch",
		Callable(self, "_probe_health"),
		Callable(self, "_repair"),
		Callable(self, "_audit"),
		TEST_STATE_PATH,
		10
	)
	var restored_snapshot: Dictionary = restored.call("get_snapshot")
	if int(restored_snapshot.get("cycle_count", 0)) != 2:
		_fail("O ciclo salvo nao foi restaurado.")
		return
	var restored_events: Array = restored_snapshot.get("events", [])
	if restored_events.is_empty():
		_fail("O historico local do assistente nao foi restaurado.")
		return

	var other_branch: Node = GuardianScript.new()
	root.add_child(other_branch)
	other_branch.call(
		"configure",
		"other_branch",
		Callable(self, "_probe_health"),
		Callable(self, "_repair"),
		Callable(self, "_audit"),
		TEST_STATE_PATH,
		10
	)
	if int((other_branch.call("get_snapshot") as Dictionary).get("cycle_count", 0)) != 0:
		_fail("O estado de uma filial vazou para outra filial.")
		return

	restored.call("set_enabled", false)
	if bool(restored.call("is_enabled")):
		_fail("A pausa do assistente nao foi persistida em memoria.")
		return
	var paused_snapshot: Dictionary = restored.call("get_snapshot")
	if str(paused_snapshot.get("status", "")) != "paused":
		_fail("O estado pausado nao foi publicado para a interface.")
		return

	restored.call("shutdown")
	other_branch.call("shutdown")
	_cleanup()
	print("SYSTEM_GUARDIAN_CHECK_OK")
	quit(0)


func _probe_health() -> Dictionary:
	return {
		"components": [
			{
				"id": "local_data",
				"label": "Banco local",
				"status": "ok",
				"message": "Estrutura valida.",
			},
			{
				"id": "routines",
				"label": "Rotinas autonomas",
				"status": "error",
				"message": "Temporizador parado.",
				"fix_action": "restart_timers",
				"repair_after": 1,
			},
			{
				"id": "unsafe_sms",
				"label": "Acao perigosa simulada",
				"status": "error",
				"message": "Teste de bloqueio.",
				"fix_action": "send_sms",
				"repair_after": 1,
			},
			{
				"id": "delayed_session",
				"label": "Sessao simulada",
				"status": "error",
				"message": "Sessao expirada no teste.",
				"fix_action": "renew_linksolutions_session",
				"repair_after": 2,
			},
		]
	}


func _repair(action: String, _component_data: Dictionary) -> Dictionary:
	repair_calls.append(action)
	return {"ok": true, "message": "Temporizador reiniciado no teste."}


func _audit(event: Dictionary) -> void:
	audit_events.append(event.duplicate(true))


func _component(snapshot: Dictionary, component_id: String) -> Dictionary:
	for raw_component in snapshot.get("components", []):
		if typeof(raw_component) == TYPE_DICTIONARY and str((raw_component as Dictionary).get("id", "")) == component_id:
			return raw_component as Dictionary
	return {}


func _has_audit_kind(kind: String) -> bool:
	for event in audit_events:
		if str(event.get("kind", "")) == kind:
			return true
	return false


func _cleanup() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_STATE_PATH)
	if FileAccess.file_exists(TEST_STATE_PATH):
		DirAccess.remove_absolute(absolute_path)
	if FileAccess.file_exists(TEST_STATE_PATH + ".tmp"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_STATE_PATH + ".tmp"))


func _fail(message: String) -> void:
	push_error(message)
	_cleanup()
	quit(1)
