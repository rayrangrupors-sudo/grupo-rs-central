extends SceneTree

const Dashboard := preload("res://tests/fixtures/offline_branch_inventory_dashboard.gd")
const StoreScript := preload("res://src/inventory_store.gd")

var failures: Array[String] = []


class FakeBancoLocalSQLSync extends Node:
	var bound_store: Variant
	var bound_branch := ""
	var snapshots: Dictionary = {}
	var bind_calls: Array[String] = []
	var refresh_calls: Array[String] = []

	func bind_store(next_store: Variant, branch_id: String) -> void:
		bound_store = next_store
		bound_branch = branch_id
		bind_calls.append(branch_id)

	func refresh_remote(_health_only: bool = false) -> Dictionary:
		refresh_calls.append(bound_branch)
		var snapshot: Dictionary = snapshots.get(bound_branch, {})
		if bound_store != null:
			bound_store.replace_from_remote(snapshot)
		return {
			"state": "synced",
			"branch": bound_branch,
			"data_available": true,
			"record_count": (snapshot.get("products", []) as Array).size(),
		}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := Dashboard.new()
	var sync := FakeBancoLocalSQLSync.new()
	root.add_child(sync)
	root.add_child(dashboard)
	dashboard.offline_local_database_sync = sync
	await process_frame

	var first_store := StoreScript.new()
	var second_store := StoreScript.new()
	sync.snapshots = {
		"imperatriz": _snapshot("IMP-ONLY"),
		"araguaina": _snapshot("ARA-ONLY"),
	}

	dashboard.store = first_store
	dashboard.selected_branch_id = "imperatriz"
	dashboard.current_section = "dashboard"
	sync.bind_store(first_store, "imperatriz")
	await dashboard._refresh_open_branch_from_remote(sync, "imperatriz", first_store)
	_check(sync.bound_branch == "imperatriz", "Primeira filial não permaneceu vinculada.")
	var first_products: Array[Dictionary] = first_store.get_products()
	_check(first_products.size() == 1 and str(first_products[0].get("sku", "")) == "IMP-ONLY", "Snapshot da primeira filial não foi aplicado.")
	_check(dashboard.offline_dashboard_refreshes == 1, "Contadores do dashboard não foram recompostos após sincronização.")

	dashboard.store = second_store
	dashboard.selected_branch_id = "araguaina"
	dashboard.current_section = "inventory"
	sync.bind_store(second_store, "araguaina")
	await dashboard._refresh_open_branch_from_remote(sync, "araguaina", second_store)
	_check(sync.bound_branch == "araguaina", "Troca de filial não atualizou bind_store.")
	var second_products: Array[Dictionary] = second_store.get_products()
	first_products = first_store.get_products()
	_check(second_products.size() == 1 and str(second_products[0].get("sku", "")) == "ARA-ONLY", "Snapshot da filial selecionada não foi aplicado.")
	_check(first_products.size() == 1 and str(first_products[0].get("sku", "")) == "IMP-ONLY", "Dados de filiais foram misturados.")
	_check(dashboard.offline_table_refreshes == 1, "Tabela da filial não foi atualizada após sincronização.")
	_check(sync.refresh_calls == ["imperatriz", "araguaina"], "refresh_remote não respeitou a ordem das filiais.")

	var synthetic_products: Array[Dictionary] = [{"sku": "OFFLINE-ONLY"}]
	for regional_branch in ["araguaina", "acailandia", "maraba"]:
		dashboard.selected_branch_id = regional_branch
		_check(not dashboard._branch_supports_operational_apis(), "Filial regional habilitou APIs operacionais.")
		_check(not dashboard._grupo_rs_api_reads_enabled(), "Filial regional habilitou API Grupo RS.")
		_check(not dashboard._grupo_rs_platform_reads_enabled(), "Filial regional habilitou leitura de portal legado.")
		_check(not dashboard._branch_supports_stock_sync(), "Filial regional habilitou sincronização operacional de placas.")
		dashboard.schedule_visible_inventory_device_cycle(synthetic_products, 0, 1, 1)
		dashboard._setup_st310_location_poll_timer()
		_check(dashboard.st310_location_poll_timer == null, "Filial regional criou polling ST310.")
	_check(dashboard.offline_operational_cycle_starts == 0, "Filial regional iniciou consulta de telemetria/status.")
	_check(sync.refresh_calls.has("araguaina"), "Banco local SQL não permaneceu ativo para a filial regional.")

	dashboard.selected_branch_id = "imperatriz"
	_check(dashboard._branch_supports_operational_apis(), "Imperatriz perdeu o fluxo operacional autorizado.")
	dashboard.schedule_visible_inventory_device_cycle(synthetic_products, 0, 1, 1)
	_check(dashboard.offline_operational_cycle_starts == 1, "Imperatriz não preservou o ciclo operacional.")

	dashboard.queue_free()
	sync.queue_free()
	await process_frame
	if failures.is_empty():
		print("INVENTORY_BRANCH_BANCO_LOCAL_SQL_REFRESH_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _snapshot(sku: String) -> Dictionary:
	return {
		"products": [{"sku": sku, "status": "estoque"}],
		"movements": [],
		"maintenance": [],
		"logs": [],
		"sms_logs": [],
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
