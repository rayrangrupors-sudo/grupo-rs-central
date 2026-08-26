## Garante que a subclasse ativa do Mapa Grande não quebrou Estoque nem Sair.
extends SceneTree

const AlertDialog := preload("res://src/ErrorDialog.gd")
const OfflineDashboard := preload("res://tests/fixtures/offline_main_dashboard.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var instance := OfflineDashboard.new()
	root.add_child(instance)
	await process_frame
	await process_frame
	instance.call("_show_list")
	await process_frame
	_check(str(instance.get("current_section")) == "inventory", "Botão/rota Estoque não selecionou a seção inventory.")
	var topbar_title: Variant = instance.get("topbar_title_label")
	_check(topbar_title is Label and (topbar_title as Label).text == "Estoque de equipamentos", "Título do Estoque não foi renderizado.")
	_check(int(instance.get("offline_external_calls")) == 0, "Estoque tentou alcançar Firebase/HTTP/SGA/ciclo remoto.")
	instance.call("_request_exit")
	await process_frame
	var exit_dialog: CanvasLayer
	for child in instance.get_children():
		if child is AlertDialog:
			exit_dialog = child as CanvasLayer
			break
	_check(exit_dialog != null, "Sair não abriu confirmação segura.")
	if exit_dialog != null:
		var title_label: Variant = exit_dialog.get("title_label")
		_check(title_label is Label and (title_label as Label).text == "Sair do sistema?", "Confirmação de Sair tem título incorreto.")
		exit_dialog.call("_cancel")
	await process_frame
	_check(int(instance.get("offline_external_calls")) == 0, "Sair acionou integração externa.")
	root.remove_child(instance)
	instance.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("MAIN_SCENE_STOCK_EXIT_SMOKE_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
