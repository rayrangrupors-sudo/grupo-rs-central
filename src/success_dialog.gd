extends CanvasLayer
class_name SuccessDialog

var panel: PanelContainer
var icon: Label
var title_label: Label
var message_label: Label
var ok_button: Button

func _ready():
	layer = 100

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 300)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -210
	panel.offset_top = -150
	panel.offset_right = 210
	panel.offset_bottom = 150
	panel.pivot_offset = Vector2(210, 150)
	panel.scale = Vector2(0.6, 0.6)
	add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.corner_radius_top_left = 15
	style.corner_radius_top_right = 15
	style.corner_radius_bottom_left = 15
	style.corner_radius_bottom_right = 15
	panel.add_theme_stylebox_override("panel", style)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)

	icon = Label.new()
	icon.text = "OK"
	icon.text = "✔"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.text = "OK"
	icon.add_theme_font_size_override("font_size", 72)
	icon.add_theme_color_override("font_color", Color("42c767"))
	vb.add_child(icon)

	title_label = Label.new()
	title_label.text = "Sucesso"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	vb.add_child(title_label)

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(message_label)

	ok_button = Button.new()
	ok_button.text = "OK"
	ok_button.custom_minimum_size = Vector2(120, 44)
	ok_button.pressed.connect(queue_free)
	vb.add_child(ok_button)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.35)

func show_success(title_text: String, msg: String):
	title_label.text = title_text
	message_label.text = msg
