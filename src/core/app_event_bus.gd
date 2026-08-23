extends Node

signal page_changed(section: String, title: String, subtitle: String)

var current_page: Dictionary = {}


func publish_page(section: String, title: String, subtitle: String = "") -> void:
	current_page = {
		"section": section,
		"title": title,
		"subtitle": subtitle,
	}
	page_changed.emit(section, title, subtitle)


func page_snapshot() -> Dictionary:
	return current_page.duplicate(true)
