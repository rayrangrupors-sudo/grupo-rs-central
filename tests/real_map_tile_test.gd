## Verificação de integração do tile real usado pelo Mapa Grande.
extends SceneTree

const TileProvider := preload("res://src/features/big_map/map_tile_provider.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var request := HTTPRequest.new()
	root.add_child(request)
	var url := TileProvider.tile_url(13, 3015, 4210)
	var request_error := request.request(url)
	if request_error != OK:
		push_error("REAL_MAP_TILE_TEST: request falhou ao iniciar: %s" % request_error)
		quit(1)
		return
	var result: Array = await request.request_completed
	var response_code := int(result[1])
	var bytes: PackedByteArray = result[3]
	var texture := TileProvider.texture_from_bytes(bytes)
	print("REAL_MAP_TILE_TEST: status=%d bytes=%d texture=%s" % [response_code, bytes.size(), texture != null])
	if response_code != 200 or bytes.is_empty() or texture == null:
		push_error("REAL_MAP_TILE_TEST: tile real não foi baixado/decodificado.")
		quit(1)
		return
	print("REAL_MAP_TILE_TEST: OK")
	quit(0)
