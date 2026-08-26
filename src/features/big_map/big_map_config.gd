## Configuração central do Mapa Grande.
##
## Alterações de provedor, cidade inicial, zoom ou regiões devem ser feitas
## somente neste arquivo. Nenhuma regra de interface pertence aqui.
extends RefCounted

const DEFAULT_CITY_ID := "imperatriz"
const DEFAULT_CITY_LABEL := "Imperatriz - MA"
const DEFAULT_LATITUDE := -5.5264
const DEFAULT_LONGITUDE := -47.4919
const DEFAULT_ZOOM := 13
# Até existir uma redução nacional auditável baseada em ERBs reais, o mapa
# operacional não expõe os centroides agregados de z4/z6/z8.
const MIN_ZOOM := 10
const MAX_ZOOM := 17

# O provedor fica isolado para permitir manutenção sem alterar o canvas, a
# busca de veículos ou a camada de ERBs. A experiência final usa somente OSM.
const TILE_PROVIDER_ID := "openstreetmap"
const TILE_URL_TEMPLATE := "https://tile.openstreetmap.org/%d/%d/%d.png"
const TILE_ATTRIBUTION := "© OpenStreetMap contributors"
const TILE_SIZE := 256
const BASEMAP_NORMAL := "normal"
const DEFAULT_BASEMAP := BASEMAP_NORMAL
const BASEMAPS := {
	BASEMAP_NORMAL: {
		"id": "openstreetmap",
		"label": "OpenStreetMap",
		"url_template": "https://tile.openstreetmap.org/%d/%d/%d.png",
		"attribution": "© OpenStreetMap contributors",
	},
}

const REGIONS := [
	{"id": "imperatriz", "label": "Imperatriz - MA", "lat": -5.5264, "lng": -47.4919, "zoom": 13, "radius_km": 16.0},
	{"id": "joao_lisboa", "label": "Joao Lisboa - MA", "lat": -5.4436, "lng": -47.4064, "zoom": 12, "radius_km": 24.0},
	{"id": "davinopolis", "label": "Davinopolis - MA", "lat": -5.5464, "lng": -47.4216, "zoom": 12, "radius_km": 24.0},
	{"id": "senador_la_rocque", "label": "Senador La Rocque - MA", "lat": -5.4461, "lng": -47.2958, "zoom": 12, "radius_km": 28.0},
	{"id": "governador_edison_lobao", "label": "Governador Edison Lobao - MA", "lat": -5.7497, "lng": -47.3642, "zoom": 12, "radius_km": 30.0},
	{"id": "ribamar_fiquene", "label": "Ribamar Fiquene - MA", "lat": -5.9307, "lng": -47.3888, "zoom": 12, "radius_km": 32.0},
	{"id": "acailandia", "label": "Acailandia - MA", "lat": -4.9470, "lng": -47.5004, "zoom": 11, "radius_km": 42.0},
	{"id": "porto_franco", "label": "Porto Franco - MA", "lat": -6.3383, "lng": -47.3996, "zoom": 11, "radius_km": 42.0},
	{"id": "estreito", "label": "Estreito - MA", "lat": -6.5608, "lng": -47.4470, "zoom": 11, "radius_km": 42.0},
]


static func default_center() -> Dictionary:
	return {"lat": DEFAULT_LATITUDE, "lng": DEFAULT_LONGITUDE}


static func default_view() -> Dictionary:
	return {"center": default_center(), "zoom": DEFAULT_ZOOM, "basemap": DEFAULT_BASEMAP}


static func basemap(_value: String = DEFAULT_BASEMAP) -> Dictionary:
	# Valores antigos, inclusive "satellite", convergem para OSM. Assim um
	# estado persistido não reintroduz um provedor removido.
	return (BASEMAPS[DEFAULT_BASEMAP] as Dictionary).duplicate(true)
