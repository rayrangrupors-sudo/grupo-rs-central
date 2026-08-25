## Adaptador do provedor de tiles do Mapa Grande.
##
## Centraliza URL, chave de cache, atribuição e decodificação da imagem.
## A comunicação HTTP continua assíncrona no controlador do dashboard.
extends RefCounted

const Config := preload("res://src/features/big_map/big_map_config.gd")


static func cache_key(zoom: int, tile_x: int, tile_y: int) -> String:
	return "%s/%d/%d/%d" % [Config.TILE_PROVIDER_ID, zoom, tile_x, tile_y]


static func tile_url(zoom: int, tile_x: int, tile_y: int) -> String:
	# O endpoint World_Imagery usa a ordem z/y/x, enquanto o canvas trabalha
	# internamente com coordenadas x/y.
	return Config.TILE_URL_TEMPLATE % [zoom, tile_y, tile_x]


static func attribution() -> String:
	return Config.TILE_ATTRIBUTION


static func texture_from_png(bytes: PackedByteArray) -> Texture2D:
	if bytes.is_empty():
		return null
	var tile_image := Image.new()
	if tile_image.load_png_from_buffer(bytes) != OK:
		return null
	tile_image.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(tile_image)
