extends SceneTree


func _initialize() -> void:
	var dashboard_script := load("res://src/inventory_dashboard.gd")
	if dashboard_script == null:
		_fail("Dashboard nao carregou.")
		return

	var dashboard: Node = dashboard_script.new()
	var imei := LineEdit.new()
	var plate := LineEdit.new()
	var chip := LineEdit.new()
	var phone := LineEdit.new()
	imei.text = "024000000"
	plate.text = "OLD - 0000"
	chip.text = "89555483000024958749"
	phone.text = "31999999999"
	dashboard.set("form_fields", {
		"imei": imei,
		"plate": plate,
		"chip_number": chip,
		"chip_phone": phone,
	})

	var apn := _option(["Selecione", "hinova.br", "linksolutions.br"], 2)
	var model := _option(["Selecione", "Reutilizado", "RS300"], 1)
	var operator_name := _option(["Selecione", "Tim", "Claro"], 2)
	var tracker_status := _option(["Estoque", "Manutencao"], 0)
	dashboard.set("form_options", {
		"apn_source": apn,
		"model": model,
		"operator": operator_name,
		"tracker_status": tracker_status,
	})
	dashboard.call("_apply_grupo_rs_data_to_form", {
		"serial": "024290459",
		"plate": "AAA - T293",
		"chip": "89555483000025855019",
		"phone": "5532988094790",
		"apn": "hinova.br",
		"operator": "Tim",
		"client": "RS300",
	})

	if imei.text != "024290459" or plate.text != "AAA - T293":
		_fail("Serie ou placa nao foram atualizadas pela busca.")
		return
	if chip.text != "89555483000025855019":
		_fail("ICCID remoto nao substituiu o ICCID antigo.")
		return
	if phone.text != "32988094790":
		_fail("Telefone remoto nao foi atualizado no formato local.")
		return
	if str(dashboard.call("_selected_option_text", apn, true)) != "hinova.br":
		_fail("APN remota nao atualizou a origem do formulario.")
		return
	if str(dashboard.call("_selected_option_text", operator_name, true)) != "Tim":
		_fail("Operadora remota nao atualizou o formulario.")
		return

	dashboard.free()
	print("GRUPO_RS_FORM_LOOKUP_CHECK_OK")
	quit(0)


func _option(values: Array[String], selected: int) -> OptionButton:
	var option := OptionButton.new()
	for value in values:
		option.add_item(value)
	option.select(selected)
	return option


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
