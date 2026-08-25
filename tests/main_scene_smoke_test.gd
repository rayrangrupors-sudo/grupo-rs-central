## Confirma que a cena principal ainda instancia após a modularização.
extends SceneTree


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
	root.add_child(instance)
	print("MAIN_SCENE_SMOKE_TEST: OK")
	root.remove_child(instance)
	instance.free()
	quit(0)
