extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard_script := GDScript.new()
	dashboard_script.source_code = FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if dashboard_script.reload() != OK:
		_fail("Dashboard nao compilou.")
		return
	var dashboard: Node = dashboard_script.new()

	var now := int(Time.get_unix_time_from_system())
	dashboard.set("location_status_cache", {
		"stale": {"label": "Ligado", "checked_at": now - 2000},
		"fresh": {"label": "Ligado", "checked_at": now},
	})
	dashboard.call("_prune_operational_caches")
	var pruned: Dictionary = dashboard.get("location_status_cache")
	if pruned.has("stale") or not pruned.has("fresh"):
		_fail("Limpeza de cache nao removeu somente a entrada expirada.")
		return

	dashboard.call("_cache_location_failure", "024300001", {
		"message": "API Grupo RS indisponivel (HTTP 503)",
	}, {
		"label": "Ligado",
		"color": Color("#13a56a"),
		"plate": "AAA - 0001",
	})
	var transient_status: Dictionary = dashboard.get("location_status_cache").get("024300001", {})
	if str(transient_status.get("label", "")) != "Revalidando":
		_fail("Falha transitoria nao preservou a ultima leitura.")
		return

	dashboard.call("_cache_location_failure", "024300002", {
		"message": "API Grupo RS nao localizou o veiculo consultado.",
	})
	var real_missing: Dictionary = dashboard.get("location_status_cache").get("024300002", {})
	if str(real_missing.get("label", "")) != "Nao localizado":
		_fail("Ausencia real nao foi marcada como Nao localizado.")
		return

	if int(dashboard.call("_grupo_rs_api_backoff_seconds")) != 5:
		_fail("Backoff inicial da API deveria ser 5 segundos.")
		return
	dashboard.set("grupo_rs_api_reconnect_attempt", 4)
	if int(dashboard.call("_grupo_rs_api_backoff_seconds")) != 120:
		_fail("Backoff progressivo da API nao foi calculado corretamente.")
		return

	dashboard.queue_free()
	print("API_RESILIENCE_CHECK_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
