extends SceneTree

class InventoryOpenProbe extends "res://src/inventory_dashboard.gd":
	var summary_calls := 0
	var refresh_calls := 0

	func _inventory_summary_stats() -> Dictionary:
		summary_calls += 1
		return {
			"total": 2500,
			"available": 600,
			"reserved": 100,
			"installed": 1700,
			"maintenance": 80,
			"inactive": 20,
		}

	func _refresh_table() -> void:
		refresh_calls += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dashboard := InventoryOpenProbe.new()
	var view := dashboard._build_list_view()
	assert(dashboard.summary_calls == 1, "A abertura recalculou o resumo completo mais de uma vez.")
	assert(dashboard.refresh_calls == 0, "A tabela foi atualizada durante a construcao pesada da pagina.")
	view.free()

	root.add_child(dashboard)
	await process_frame
	dashboard.summary_calls = 0
	dashboard.refresh_calls = 0
	dashboard._show_list()
	assert(dashboard.refresh_calls == 0, "A tabela bloqueou o mesmo quadro do clique no Estoque.")
	await process_frame
	assert(dashboard.summary_calls == 1, "A pagina aberta nao reutilizou o snapshot dos indicadores.")
	assert(dashboard.refresh_calls == 1, "A abertura nao executou exatamente uma atualizacao da tabela.")

	dashboard.free()
	await process_frame
	print("INVENTORY_OPEN_PERFORMANCE_CONTRACT_TEST: OK")
	quit(0)
