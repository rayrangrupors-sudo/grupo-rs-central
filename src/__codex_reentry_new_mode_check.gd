extends SceneTree

class DashboardStub:
	extends "res://src/inventory_dashboard.gd"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var dashboard := DashboardStub.new()
	root.add_child(dashboard)
	await process_frame
	var page := dashboard.call("_build_form_view", "") as Control
	if page == null or dashboard.form_mode != "new":
		_fail(dashboard, "A tela de novo equipamento nao foi criada no modo correto.")
		return
	var imei := dashboard.form_fields.get("imei") as LineEdit
	var chip := dashboard.form_fields.get("chip_number") as LineEdit
	var phone := dashboard.form_fields.get("chip_phone") as LineEdit
	var plate := dashboard.form_fields.get("plate") as LineEdit
	var vehicle_model := dashboard.form_fields.get("vehicle_model") as LineEdit
	var chassis := dashboard.form_fields.get("vehicle_chassis") as LineEdit
	if imei == null or chip == null or phone == null or plate == null or vehicle_model == null or chassis == null:
		_fail(dashboard, "Campos da nova interface ausentes.")
		return
	imei.text = "990000000001"
	chip.text = "89555483000000000001"
	phone.text = "98999990001"
	dashboard.call("_set_option_value", dashboard.form_options.get("apn_source"), "hinova.br")
	dashboard.call("_set_option_value", dashboard.form_options.get("model"), "Reutilizado")
	dashboard.call("_set_option_value", dashboard.form_options.get("operator"), "Claro")
	# O fluxo novo inicia pronto para receber a placa; para validar o caminho
	# alternativo de estoque, desmarcamos explicitamente a associacao.
	dashboard.form_associate_vehicle_toggle.button_pressed = false
	var stock_request: Dictionary = dashboard.call("_equipment_registration_request_from_form")
	if not bool(stock_request.get("equipment_only", false)) or str(stock_request.get("plate", "")) != "":
		_fail(dashboard, "Novo equipamento sem associacao nao foi convertido para estoque.")
		return
	dashboard.form_associate_vehicle_toggle.button_pressed = true
	plate.text = "AAA - C99"
	vehicle_model.text = "Veiculo teste"
	chassis.text = "9BWTESTE000000001"
	var linked_request: Dictionary = dashboard.call("_equipment_registration_request_from_form")
	if bool(linked_request.get("equipment_only", true)) or str(linked_request.get("plate", "")) != "AAA - C99" \
			or str(linked_request.get("vehicle_model", "")) != "Veiculo teste" \
			or str(linked_request.get("vehicle_chassis", "")) != "9BWTESTE000000001":
		_fail(dashboard, "Novo equipamento associado nao preservou placa/modelo/chassi.")
		return
	var payload: Dictionary = dashboard.call("_grupo_rs_api_vehicle_payload", linked_request, {}, "AAA - C99", 9021)
	if str(payload.get("modelo", "")) != "Veiculo teste" or str(payload.get("chassi", "")) != "9BWTESTE000000001":
		_fail(dashboard, "Payload de novo veiculo nao carregou os dados de identificacao.")
		return
	var preserved: bool = bool(dashboard.call("_modern_vehicle_snapshot_matches_reassignment", {
		"plate": "AAA - C99", "client": "RS300", "vehicle_type": "Carro", "model": "Veiculo teste", "chassis": "9BWTESTE000000001"
	}, "AAA - C99", false, linked_request))
	if not bool(preserved):
		_fail(dashboard, "A verificacao de reentrada rejeitou dados preservados validos.")
		return
	page.queue_free()
	dashboard.queue_free()
	print("REENTRY_NEW_MODE_CHECK_OK")
	quit(0)

func _fail(dashboard: Node, message: String) -> void:
	if dashboard != null and is_instance_valid(dashboard):
		dashboard.queue_free()
	push_error(message)
	quit(1)
