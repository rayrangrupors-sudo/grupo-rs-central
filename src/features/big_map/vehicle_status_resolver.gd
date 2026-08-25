## Classificação visual de comunicação do veículo no Mapa Grande.
##
## A mesma resposta deve alimentar agulha, lista e painel de detalhes.
extends RefCounted


static func resolve(
	location: Dictionary,
	coordinates_valid: bool,
	hours_since_update: float,
	ignition_state: int,
	colors: Dictionary
) -> Dictionary:
	if bool(location.get("position_preserved", false)):
		return apply_state(location, "Desatualizado", colors.get("stale", Color("#f2b233")))
	if not coordinates_valid:
		return apply_state(location, "Sem posição", colors.get("unknown", Color("#8b98a6")))
	if str(location.get("updated_at", "")).strip_edges() == "" or hours_since_update < 0.0:
		return apply_state(location, "Sem comunicação", colors.get("unknown", Color("#8b98a6")))
	var stale_limit_hours := (5.0 / 60.0) if ignition_state == 1 else 2.0
	if hours_since_update >= stale_limit_hours:
		return apply_state(location, "Desatualizado", colors.get("stale", Color("#f2b233")))
	if ignition_state == 1:
		return apply_state(location, "Ligado", colors.get("on", Color("#16a673")))
	if ignition_state == 0:
		return apply_state(location, "Desligado", colors.get("off", Color("#dc3545")))
	var speed_text := str(location.get("speed", "0")).replace(",", ".").strip_edges()
	if speed_text.is_valid_float() and speed_text.to_float() > 0.0:
		return apply_state(location, "Ligado", colors.get("on", Color("#16a673")))
	return apply_state(location, "Sem status", colors.get("unknown", Color("#8b98a6")))


static func apply_state(location: Dictionary, label: String, color: Color) -> Dictionary:
	location["communication_state"] = label
	location["communication_color"] = color
	return {"label": label, "color": color}


static func color_for_state(location: Dictionary) -> Color:
	match str(location.get("communication_state", "")).strip_edges().to_lower():
		"ligado":
			return Color("#16a673")
		"desligado":
			return Color("#dc3545")
		"desatualizado":
			return Color("#f2b233")
	return Color("#8b98a6")
