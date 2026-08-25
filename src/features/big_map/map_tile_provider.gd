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


static func texture_from_bytes(bytes: PackedByteArray) -> Texture2D:
	if bytes.is_empty():
		return null
	var tile_image := Image.new()
	# O provedor Esri World Imagery responde JPEG. Mantemos PNG como primeira
	# tentativa para preservar compatibilidade com caches e provedores antigos.
	var is_png := bytes.size() >= 8 \
			and bytes[0] == 0x89 \
			and bytes[1] == 0x50 \
			and bytes[2] == 0x4e \
			and bytes[3] == 0x47 \
			and bytes[4] == 0x0d \
			and bytes[5] == 0x0a \
			and bytes[6] == 0x1a \
			and bytes[7] == 0x0a
	var is_jpeg := bytes.size() >= 3 \
			and bytes[0] == 0xff \
			and bytes[1] == 0xd8 \
			and bytes[2] == 0xff
	var decode_status := ERR_FILE_UNRECOGNIZED
	if is_png:
		decode_status = tile_image.load_png_from_buffer(bytes)
	elif is_jpeg:
		tile_image = Image.new()
		decode_status = tile_image.load_jpg_from_buffer(bytes)
	if decode_status != OK:
		return null
	tile_image.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(tile_image)


static func texture_from_png(bytes: PackedByteArray) -> Texture2D:
	# Alias mantido para os chamadores existentes; a resposta pode ser PNG ou
	# JPEG dependendo do provedor configurado.
	return texture_from_bytes(bytes)
