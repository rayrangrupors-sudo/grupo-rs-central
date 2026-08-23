extends CanvasLayer
class_name AlertDialog

signal confirmed
signal cancelled

enum Type {
	INFO,
	SUCCESS,
	ERROR,
	WARNING,
	QUESTION,
}

const UI_FONT := preload("res://assets/fonts/Noto_Sans/static/NotoSans-SemiBold.ttf")

var panel: PanelContainer
var icon_label: Label
var title_label: Label
var message_label: Label
var note_label: Label
var confirm_button: Button
var cancel_button: Button
var accent_color := Color("#087ABC")


func _ready() -> void:
	layer = 100

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.44)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 320)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-230, -160)
	panel.pivot_offset = Vector2(230, 160)
	panel.scale = Vector2(0.82, 0.82)
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 12)
	margin.add_child(stack)

	icon_label = Label.new()
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_override("font", UI_FONT)
	icon_label.add_theme_font_size_override("font_size", 58)
	stack.add_child(icon_label)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", UI_FONT)
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color("#172334"))
	stack.add_child(title_label)

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_font_override("font", UI_FONT)
	message_label.add_theme_font_size_override("font_size", 16)
	message_label.add_theme_color_override("font_color", Color("#455465"))
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(message_label)

	note_label = Label.new()
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.add_theme_font_override("font", UI_FONT)
	note_label.add_theme_font_size_override("font_size", 13)
	note_label.add_theme_color_override("font_color", Color("#718096"))
	note_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_label.visible = false
	stack.add_child(note_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	stack.add_child(buttons)

	cancel_button = Button.new()
	cancel_button.custom_minimum_size = Vector2(126, 42)
	cancel_button.pressed.connect(_cancel)
	buttons.add_child(cancel_button)

	confirm_button = Button.new()
	confirm_button.custom_minimum_size = Vector2(126, 42)
	confirm_button.pressed.connect(_confirm)
	buttons.add_child(confirm_button)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.24)


func show_alert(
	type: Type,
	title: String,
	message: String,
	supporting_note: String = "",
	confirm_text: String = "",
	cancel_text: String = "Cancelar"
) -> void:
	title_label.text = title
	message_label.text = message
	note_label.text = supporting_note
	note_label.visible = supporting_note.strip_edges() != ""
	cancel_button.text = cancel_text if cancel_text.strip_edges() != "" else "Cancelar"
	cancel_button.visible = type == Type.QUESTION
	confirm_button.text = confirm_text if confirm_text.strip_edges() != "" else ("Confirmar" if type == Type.QUESTION else "OK")

	match type:
		Type.INFO:
			icon_label.text = "i"
			accent_color = Color("#087ABC")
		Type.SUCCESS:
			icon_label.text = "OK"
			accent_color = Color("#12A86B")
		Type.ERROR:
			icon_label.text = "X"
			accent_color = Color("#DE4141")
		Type.WARNING:
			icon_label.text = "!"
			accent_color = Color("#F59A23")
		Type.QUESTION:
			icon_label.text = "?"
			accent_color = Color("#087ABC")

	icon_label.add_theme_color_override("font_color", accent_color)
	_apply_button_styles()


func _confirm() -> void:
	confirmed.emit()
	queue_free()


func _cancel() -> void:
	cancelled.emit()
	queue_free()


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.18)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 5)
	return style


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	return style


func _apply_button_styles() -> void:
	for button in [confirm_button, cancel_button]:
		button.add_theme_font_override("font", UI_FONT)
		button.add_theme_font_size_override("font_size", 15)
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_pressed_color", Color.WHITE)

	confirm_button.add_theme_stylebox_override("normal", _button_style(accent_color, accent_color))
	confirm_button.add_theme_stylebox_override("hover", _button_style(accent_color.lightened(0.08), accent_color.lightened(0.08)))
	confirm_button.add_theme_stylebox_override("pressed", _button_style(accent_color.darkened(0.08), accent_color.darkened(0.08)))

	var secondary := Color("#6B7B8C")
	cancel_button.add_theme_stylebox_override("normal", _button_style(secondary, secondary))
	cancel_button.add_theme_stylebox_override("hover", _button_style(secondary.lightened(0.08), secondary.lightened(0.08)))
	cancel_button.add_theme_stylebox_override("pressed", _button_style(secondary.darkened(0.08), secondary.darkened(0.08)))
