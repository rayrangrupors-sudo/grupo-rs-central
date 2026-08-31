extends RefCounted

const BACKGROUND := Color("#F3F7FB")
const SURFACE := Color("#FFFFFF")
const BORDER := Color("#DCE6EF")
const TEXT := Color("#182536")
const MUTED := Color("#64748B")
const NAVY := Color("#123552")
const BLUE := Color("#087ABC")
const BLUE_SOFT := Color("#EAF5FD")
const GREEN := Color("#12A86B")
const ORANGE := Color("#F59A23")
const SIDEBAR_WIDTH := 224.0
const TOPBAR_HEIGHT := 92.0


static func surface(
	fill: Color,
	border: Color,
	border_width: int = 1,
	radius: int = 7,
	with_shadow: bool = false
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	if with_shadow:
		style.shadow_color = Color(0.04, 0.12, 0.2, 0.12)
		style.shadow_size = 8
		style.shadow_offset = Vector2(0, 3)
	return style


static func sidebar_button(active: bool, state: String) -> StyleBoxFlat:
	if active:
		var fill := BLUE
		if state == "hover":
			fill = BLUE.lightened(0.06)
		elif state == "pressed":
			fill = BLUE.darkened(0.07)
		return surface(fill, fill, 0, 9, false)

	var fill := Color.TRANSPARENT
	var border := Color.TRANSPARENT
	if state == "hover":
		fill = Color("#123d5c")
	elif state == "pressed":
		fill = Color("#174b6d")
	elif state == "focus":
		border = Color("#5e89a3")
	return surface(fill, border, 1 if border.a > 0.0 else 0, 9, false)


static func sidebar_group_button(active: bool, state: String) -> StyleBoxFlat:
	# O grupo precisa permanecer visualmente separado mesmo quando nenhum dos
	# filhos está selecionado. Isso reproduz o cartão escuro da prévia sem
	# competir com o estado azul do item ativo.
	var fill := Color("#103754")
	var border := Color("#1d4e70")
	if active:
		# O grupo continua sendo um cartão escuro quando um filho está ativo;
		# somente o filho selecionado recebe o azul forte.
		fill = Color("#103754")
		border = Color("#2d6b95")
	if state == "hover":
		fill = Color("#174a6b")
	elif state == "pressed":
		fill = Color("#0e304b")
	return surface(fill, border, 1, 10, false)


static func metric_tint(color: Color) -> Color:
	return Color(
		lerpf(color.r, 1.0, 0.88),
		lerpf(color.g, 1.0, 0.88),
		lerpf(color.b, 1.0, 0.88),
		1.0
	)
