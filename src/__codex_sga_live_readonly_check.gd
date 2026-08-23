extends SceneTree

const DashboardScript := preload("res://src/inventory_dashboard.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard: Node = DashboardScript.new()
	root.add_child(dashboard)
	await process_frame
	var failed := false
	var test_plate := OS.get_environment("CODEX_SGA_TEST_PLATE").strip_edges()
	var test_client := OS.get_environment("CODEX_SGA_TEST_CLIENT").strip_edges()
	var test_source := OS.get_environment("CODEX_SGA_TEST_SOURCE").strip_edges().to_lower()
	var test_product_fallback := OS.get_environment("CODEX_SGA_TEST_PRODUCT_FALLBACK") == "1"
	if test_product_fallback and test_plate != "":
		var product_result: Dictionary = await dashboard.call("_lookup_sga_status_for_product", {
			"sku": OS.get_environment("CODEX_SGA_TEST_SERIAL").strip_edges(),
			"plate": test_plate,
			"client": "",
		})
		var resolved_client := str(product_result.get("client", "")).strip_edges()
		print("GRUPO_RS_PLACA_CLIENTE=%s" % ("LOCALIZADO" if resolved_client != "" else "FALHA"))
		print("SGA_RESOLUCAO=%s" % str(product_result.get("resolved_by", "nao_resolvido")).to_upper())
		for source in ["rastreio", "protecao"]:
			var source_result: Dictionary = product_result.get(source, {})
			if bool(source_result.get("ok", false)):
				print("SGA_%s_STATUS=%s" % [source.to_upper(), str(source_result.get("summary", "OK"))])
			else:
				failed = true
				print("SGA_%s=FALHA | %s" % [source.to_upper(), str(source_result.get("message", "Consulta recusada."))])
		if resolved_client == "" or str(product_result.get("resolved_by", "")) != "plate":
			failed = true
		dashboard.queue_free()
		await process_frame
		quit(1 if failed else 0)
		return
	for source in ["rastreio", "protecao"]:
		if test_source != "" and source != test_source:
			continue
		var credentials: Dictionary = dashboard.call("_sga_credentials", source)
		if str(credentials.get("api_token", "")).strip_edges() == "":
			print("SGA_%s=NAO_CONFIGURADO" % source.to_upper())
			continue
		var result: Dictionary = await dashboard.call("_ensure_sga_user_token", source, true)
		if bool(result.get("ok", false)):
			print("SGA_%s=AUTENTICADO" % source.to_upper())
			if test_client != "":
				var identity: Dictionary = await dashboard.call("_fetch_grupo_rs_user_cpf", test_client)
				if not bool(identity.get("ok", false)):
					failed = true
					print("GRUPO_RS_CPF=FALHA | %s" % str(identity.get("message", "CPF nao localizado.")))
				else:
					print("GRUPO_RS_CPF=LOCALIZADO")
					var cpf_lookup: Dictionary = await dashboard.call(
						"_lookup_sga_source_by_cpf",
						str(identity.get("cpf", "")),
						test_client,
						source
					)
					if bool(cpf_lookup.get("ok", false)):
						print("SGA_%s_CPF=ROTA_LIBERADA|ASSOCIADO_%s" % [
							source.to_upper(),
							"OK" if str(cpf_lookup.get("associate_status", "")) != "" else "VAZIO",
						])
					else:
						failed = true
						print("SGA_%s_CPF=FALHA | %s" % [source.to_upper(), str(cpf_lookup.get("message", "Consulta recusada."))])
			elif test_plate != "":
				var lookup: Dictionary = await dashboard.call("_lookup_sga_source_by_plate", test_plate, source)
				var lookup_state := str(lookup.get("state", "error"))
				if bool(lookup.get("ok", false)) or lookup_state == "not_found":
					print("SGA_%s_CONSULTA=ROTA_LIBERADA" % source.to_upper())
					if bool(lookup.get("ok", false)):
						print("SGA_%s_STATUS=ASSOCIADO_%s|VEICULO_%s|FINANCEIRO_%s" % [
							source.to_upper(),
							"OK" if str(lookup.get("associate_status", "")) != "" else "VAZIO",
							"OK" if str(lookup.get("vehicle_status", "")) != "" else "VAZIO",
							"OK" if str(lookup.get("financial_status", "")) != "" else "VAZIO",
						])
				else:
					failed = true
					print("SGA_%s_CONSULTA=FALHA | %s" % [source.to_upper(), str(lookup.get("message", "Consulta recusada."))])
		else:
			failed = true
			print("SGA_%s=FALHA | %s" % [source.to_upper(), str(result.get("message", "Falha sem detalhe."))])

	dashboard.queue_free()
	await process_frame
	quit(1 if failed else 0)
