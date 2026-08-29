## Fixture determinística do carregador incremental de tiles.
##
## Não executa _ready do dashboard, não abre HTTP e não acessa API/SGA/Banco local SQL.
extends "res://src/features/big_map/big_map_tracking_layout.gd"

var offline_http_calls := 0
var offline_png := PackedByteArray()
var offline_http_delay_msec := 0
var offline_fail_every := 0
var offline_profile_build_calls := 0


func _ready() -> void:
	pass


func _http_get_bytes(_url: String) -> Dictionary:
	offline_http_calls += 1
	if offline_http_delay_msec > 0:
		await get_tree().create_timer(float(offline_http_delay_msec) / 1000.0).timeout
	if offline_png.is_empty():
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color("#d9e8ef"))
		offline_png = image.save_png_to_buffer()
	return {"ok": true, "bytes": offline_png, "result": HTTPRequest.RESULT_SUCCESS, "response_code": 200}


func _smart_4g_tile_http_bytes(
	_url: String,
	canvas: Smart4GMapCanvas,
	load_generation: int
) -> Dictionary:
	offline_http_calls += 1
	if offline_http_delay_msec > 0:
		await get_tree().create_timer(float(offline_http_delay_msec) / 1000.0).timeout
	if canvas == null or not is_instance_valid(canvas) or not canvas.is_load_current(load_generation):
		smart_4g_tile_cancelled_http_count += 1
		return {"ok": false, "bytes": PackedByteArray(), "cancelled": true}
	if offline_fail_every > 0 and offline_http_calls % offline_fail_every == 0:
		return {"ok": false, "bytes": PackedByteArray(), "result": HTTPRequest.RESULT_CONNECTION_ERROR, "response_code": 0}
	if offline_png.is_empty():
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color("#d9e8ef"))
		offline_png = image.save_png_to_buffer()
	return {"ok": true, "bytes": offline_png, "result": HTTPRequest.RESULT_SUCCESS, "response_code": 200}


func _build_smart_4g_map_profile(
	_devices: Array[Dictionary],
	_center: Dictionary,
	_zoom: int,
	_viewport_size: Vector2i
) -> Dictionary:
	offline_profile_build_calls += 1
	return {"ok": false, "message": "Fixture sem catálogo regional."}
