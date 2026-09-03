extends SceneTree

class Probe extends "res://src/inventory_dashboard.gd":
	func _ready() -> void:
		pass
	func _sms_recovery_check_pending() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for branch in ["imperatriz", "maraba", "araguaina", "acailandia"]:
		var host := Probe.new()
		host.selected_branch_id = branch
		root.add_child(host)
		host.content_area = MarginContainer.new()
		host.add_child(host.content_area)
		var sidebar := host._build_sidebar()
		host.add_child(sidebar)
		assert(host.sidebar_buttons.has("sms_panel") == (branch == "imperatriz"))
		if branch == "imperatriz":
			host.sms_panel_events.assign([{"serial": "TEST-SMS-001", "status": "Enviado", "origin": "Programa", "timestamp": "2026-09-03 12:00:00"}])
			var button: Button = host.sidebar_buttons["sms_panel"]
			assert((button.find_child("SidebarLabel", true, false) as Label).text == "Painel SMS")
			assert(button.get_index() == (host.sidebar_buttons["monitor_4g"] as Button).get_index() + 1)
			button.pressed.emit()
			await process_frame
			assert(host.current_section == "sms_panel", "O clique voltou para o inicio.")
			assert(host.content_area.find_child("SmsPanelView", true, false) != null, "O painel real nao abriu.")
			var history_visible := false
			for label in host.content_area.find_children("*", "Label", true, false):
				if label.text == "TEST-SMS-001":
					history_visible = true
			assert(history_visible, "Historico de teste nao apareceu no painel.")
			await create_timer(0.4).timeout
			assert(host.current_section == "sms_panel", "O painel nao permaneceu aberto.")
		host.free()
	print("SMS_SIDEBAR_TEST: OK")
	quit(0)
