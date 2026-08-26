## Adaptador do provedor de tiles do Mapa Grande.
##
## Centraliza URL, chave de cache, atribuição e decodificação da imagem.
## A comunicação HTTP continua assíncrona no controlador do dashboard.
extends RefCounted

const Config := preload("res://src/features/big_map/big_map_config.gd")


static func cache_key(zoom: int, tile_x: int, tile_y: int, basemap_id: String = Config.BASEMAP_NORMAL) -> String:
	var provider := Config.basemap(basemap_id)
	return "%s/%d/%d/%d" % [str(provider.get("id", Config.TILE_PROVIDER_ID)), zoom, tile_x, tile_y]


static func tile_url(zoom: int, tile_x: int, tile_y: int, basemap_id: String = Config.BASEMAP_NORMAL) -> String:
	var provider := Config.basemap(basemap_id)
	var template := str(provider.get("url_template", Config.TILE_URL_TEMPLATE))
	return template % [zoom, tile_x, tile_y]


static func attribution(basemap_id: String = Config.BASEMAP_NORMAL) -> String:
	return str(Config.basemap(basemap_id).get("attribution", Config.TILE_ATTRIBUTION))


static func image_from_bytes(bytes: PackedByteArray) -> Image:
	if bytes.is_empty():
		return null
	var tile_image := Image.new()
	# O endpoint de tiles padrão do OpenStreetMap responde PNG. JPEG permanece
	# aceito apenas como tolerância de decodificação, não como segundo provedor.
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
	return tile_image


static func texture_from_image(tile_image: Image) -> Texture2D:
	return ImageTexture.create_from_image(tile_image) if tile_image != null and not tile_image.is_empty() else null


static func texture_from_bytes(bytes: PackedByteArray) -> Texture2D:
	return texture_from_image(image_from_bytes(bytes))


static func texture_from_png(bytes: PackedByteArray) -> Texture2D:
	# Alias mantido para os chamadores existentes; a resposta pode ser PNG ou
	# JPEG dependendo do provedor configurado.
	return texture_from_bytes(bytes)
