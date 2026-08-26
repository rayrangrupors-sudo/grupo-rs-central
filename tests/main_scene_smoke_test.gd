## Confirma offline que a cena principal instancia e aponta para o controller.
extends SceneTree

const ActiveController := preload("res://src/features/big_map/big_map_tracking_layout.gd")


func _init() -> void:
	var packed := load("res://scenes/estoque_profissional.tscn") as PackedScene
	if packed == null:
		push_error("MAIN_SCENE_SMOKE_TEST: cena principal não carregou.")
		quit(1)
		return
	var instance := packed.instantiate()
	if instance == null:
		push_error("MAIN_SCENE_SMOKE_TEST: cena principal não instanciou.")
		quit(1)
		return
	if instance.get_script() != ActiveController:
		push_error("MAIN_SCENE_SMOKE_TEST: cena principal não usa o controller do Mapa Grande.")
		instance.free()
		quit(1)
		return
	print("MAIN_SCENE_SMOKE_TEST: OK")
	instance.free()
	quit(0)
