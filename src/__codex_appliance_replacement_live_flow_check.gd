extends SceneTree


const SOURCE_SERIAL := "024393169"
const SOURCE_PLATE := "TST - 3169"
const TARGET_SERIAL := "024379377"
const TARGET_PLATE := "BAX - 4089"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		_fail("Dashboard nao compilou.")
		return
	var dashboard: Node = dashboard_script.new()
	root.add_child(dashboard)
	await process_frame
	dashboard.set("selected_branch_id", "imperatriz")
	dashboard.set("selected_branch_grupo_rs_mode", "modern")
	dashboard.set("selected_branch_grupo_rs_base_url", "https://novogrupors.ddns.net/cadastro/")
	var login: Dictionary = await dashboard.call("_grupo_rs_api_login")
	if not bool(login.get("ok", false)):
		_fail("Login API falhou: %s" % str(login.get("message", "")))
		return

	var source_lookup: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", SOURCE_PLATE, SOURCE_SERIAL, true, true)
	var target_lookup: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", TARGET_PLATE, TARGET_SERIAL, true, true)
	if not bool(source_lookup.get("ok", false)) or not bool(target_lookup.get("ok", false)):
		_fail("Os dois aparelhos de teste nao foram encontrados antes da troca.")
		return
	var source_before: Dictionary = await dashboard.call("_appliance_replacement_enrich_api_vehicle_row", source_lookup.get("row", {}) as Dictionary)
	var target_before: Dictionary = await dashboard.call("_appliance_replacement_enrich_api_vehicle_row", target_lookup.get("row", {}) as Dictionary)
	print("LIVE_SWAP_BEFORE source=%s/%s client=%s target=%s/%s client=%s" % [SOURCE_SERIAL, str(source_before.get("plate", "")), str(source_before.get("client", "")), TARGET_SERIAL, str(target_before.get("plate", "")), str(target_before.get("client", ""))])
	if str(source_before.get("client", "")).strip_edges() == "" or str(source_before.get("client_id", "")).strip_edges() == "":
		_fail("O titular da origem nao foi enriquecido pela leitura web; nenhuma alteracao foi feita.")
		return

	var store_script := load("res://src/inventory_store.gd")
	var store = store_script.new()
	store.configure("user://__codex_appliance_replacement_live.json", "__codex_appliance_replacement_live.json", "user://__codex_appliance_replacement_live_backups", false)
	store.load_db()
	store.mark_remote_available()
	store.upsert_product({"sku": SOURCE_SERIAL, "imei": SOURCE_SERIAL, "equipment_number": SOURCE_SERIAL, "model": "RS 300", "operator": "Tim", "plate": SOURCE_PLATE, "client": str(source_before.get("client", "")), "tracker_status": "Instalado", "status": "Instalado", "location": "Instalado", "stock": 0})
	store.upsert_product({"sku": TARGET_SERIAL, "imei": TARGET_SERIAL, "equipment_number": TARGET_SERIAL, "model": "RS 300", "operator": "Vivo", "plate": TARGET_PLATE, "client": str(target_before.get("client", "")), "tracker_status": "Instalado", "status": "Instalado", "location": "Instalado", "stock": 0})
	dashboard.set("store", store)

	# Chama somente o executor API para impedir que este teste real escreva pelo
	# portal caso a API nao esteja apta a preparar o plano.
	var result: Dictionary = await dashboard.call("_perform_api_appliance_replacement", {"client_plate": SOURCE_PLATE, "swap_plate": TARGET_PLATE, "operation_id": "live-swap-20260818"})
	print("LIVE_SWAP_RESULT=%s" % JSON.stringify({"handled": result.get("handled", false), "ok": result.get("ok", false), "api": result.get("api", false), "message": result.get("message", ""), "local": result.get("local", {})}))
	if not bool(result.get("handled", false)):
		_fail("A API nao preparou o fluxo; o teste foi interrompido sem fallback de escrita.")
		return

	var restore_messages: Array[String] = []
	var target_after_lookup: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", "", TARGET_SERIAL, true, true)
	var target_after: Dictionary = target_after_lookup.get("row", {}) as Dictionary
	if not target_after.is_empty():
		var target_restore_request: Dictionary = await dashboard.call("_appliance_replacement_api_request_for_row", target_before, str(target_before.get("client_id", "")), TARGET_PLATE, false, dashboard.call("_appliance_replacement_copy_fields", target_before))
		var target_restore: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", target_restore_request, target_after, TARGET_PLATE)
		restore_messages.append("target=%s" % ("OK" if bool(target_restore.get("ok", false)) else str(target_restore.get("message", "falhou"))))
	var source_after_lookup: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", "", SOURCE_SERIAL, true, true)
	var source_after: Dictionary = source_after_lookup.get("row", {}) as Dictionary
	if not source_after.is_empty():
		var source_restore_request: Dictionary = await dashboard.call("_appliance_replacement_api_request_for_row", source_before, str(source_before.get("client_id", "")), SOURCE_PLATE, false, dashboard.call("_appliance_replacement_copy_fields", source_before))
		var source_restore: Dictionary = await dashboard.call("_grupo_rs_api_update_vehicle", source_restore_request, source_after, SOURCE_PLATE)
		restore_messages.append("source=%s" % ("OK" if bool(source_restore.get("ok", false)) else str(source_restore.get("message", "falhou"))))
	print("LIVE_SWAP_RESTORE %s" % " | ".join(restore_messages))

	var source_final: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", SOURCE_PLATE, SOURCE_SERIAL, true, true)
	var target_final: Dictionary = await dashboard.call("_grupo_rs_api_find_vehicle", TARGET_PLATE, TARGET_SERIAL, true, true)
	if not bool(source_final.get("ok", false)) or not bool(target_final.get("ok", false)):
		_fail("A restauracao real nao confirmou as duas associacoes originais.")
		return
	print("LIVE_SWAP_CHECK_OK api_primary=true hybrid_read=true swap=%s restore=OK" % ("OK" if bool(result.get("ok", false)) else "PARTIAL"))
	dashboard.queue_free()
	_cleanup()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	_cleanup()
	quit(1)


func _cleanup() -> void:
	for path in [
		"user://__codex_appliance_replacement_live.json",
		"user://__codex_appliance_replacement_live.json.tmp",
		"user://__codex_appliance_replacement_live.json.bak",
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
