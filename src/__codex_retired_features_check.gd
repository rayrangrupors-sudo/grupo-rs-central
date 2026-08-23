extends SceneTree

const RETIRED_LABELS := [
	"Monitor automatico",
	"Guardian",
	"Assistente IA",
	"Luna",
	"Relatorios",
	"Manutencao",
	"Excluir em massa",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/estoque_profissional.tscn")
	if scene == null:
		_fail("Cena principal nao carregou.")
		return
	var dashboard: Node = scene.instantiate()
	root.add_child(dashboard)
	await process_frame

	if bool(dashboard.call("_branch_supports_auto_monitor")):
		_fail("Monitor automatico ainda esta habilitado.")
		return
	var project_config := FileAccess.get_file_as_string("res://project.godot")
	if project_config.contains("AIManager="):
		_fail("AIManager ainda esta registrado como autoload.")
		return
	var dashboard_source := FileAccess.get_file_as_string("res://src/inventory_dashboard.gd")
	if not dashboard_source.contains('func(): _request_delete(sku)'):
		_fail("Botao de exclusao individual nao esta ligado ao cadastro.")
		return
	if not dashboard_source.contains('btn_deletar.tooltip_text = "Excluir equipamento"'):
		_fail("Botao de exclusao individual nao foi restaurado.")
		return

	var view_names := ["sidebar", "topbar", "system_menu", "bulk"]
	var views := [
		dashboard.call("_build_sidebar"),
		dashboard.call("_build_topbar"),
		dashboard.call("_make_system_menu_button"),
		dashboard.call("_build_bulk_registration_view"),
	]
	for index in range(views.size()):
		var view: Node = views[index]
		var found := _find_retired_text(view)
		if found != "":
			_fail("Recurso aposentado ainda visivel em %s: %s" % [view_names[index], found])
			return

	print("RETIRED_FEATURES_CHECK_OK")
	quit(0)


func _find_retired_text(node: Node) -> String:
	if node is Button:
		var button_text := str((node as Button).text).strip_edges()
		if RETIRED_LABELS.has(button_text):
			return button_text
	if node is Label:
		var label_text := str((node as Label).text).strip_edges()
		if RETIRED_LABELS.has(label_text):
			return label_text
	for child in node.get_children():
		var found := _find_retired_text(child)
		if found != "":
			return found
	return ""


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
