## Verificação de integração do tile real usado pelo Mapa Grande.
extends SceneTree

const TileProvider := preload("res://src/features/big_map/map_tile_provider.gd")
const Config := preload("res://src/features/big_map/big_map_config.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var result: Dictionary = await _download_basemap(Config.BASEMAP_NORMAL)
	print("REAL_MAP_TILE_TEST: basemap=osm status=%d bytes=%d texture=%s" % [int(result.get("status", 0)), int(result.get("bytes", 0)), bool(result.get("texture", false))])
	if not bool(result.get("ok", false)):
		push_error("REAL_MAP_TILE_TEST: falha no OpenStreetMap")
		quit(1)
		return
	print("REAL_MAP_TILE_TEST: OK OSM_ONLY")
	quit(0)


func _download_basemap(basemap: String) -> Dictionary:
	var request := HTTPRequest.new()
	root.add_child(request)
	var url := TileProvider.tile_url(13, 3015, 4210, basemap)
	var request_error := request.request(url)
	if request_error != OK:
		request.queue_free()
		return {"ok": false, "status": 0, "bytes": 0, "texture": false}
	var result: Array = await request.request_completed
	var response_code := int(result[1])
	var bytes: PackedByteArray = result[3]
	var texture := TileProvider.texture_from_bytes(bytes)
	request.queue_free()
	return {
		"ok": response_code == 200 and not bytes.is_empty() and texture != null,
		"status": response_code,
		"bytes": bytes.size(),
		"texture": texture != null,
	}
