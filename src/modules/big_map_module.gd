## Fachada pública do módulo Mapa Grande.
##
## O restante da aplicação acessa configuração e serviços por esta classe,
## sem conhecer arquivos internos da feature.
extends RefCounted

const Config := preload("res://src/features/big_map/big_map_config.gd")
const RegionService := preload("res://src/features/big_map/map_region_service.gd")
const TileProvider := preload("res://src/features/big_map/map_tile_provider.gd")
const VehicleStatus := preload("res://src/features/big_map/vehicle_status_resolver.gd")


func default_view() -> Dictionary:
	return Config.default_view()


func region_catalog() -> Array:
	return Config.REGIONS.duplicate(true)


func region_definition(region_id: String) -> Dictionary:
	return RegionService.definition(region_id)


func tile_url(zoom: int, tile_x: int, tile_y: int) -> String:
	return TileProvider.tile_url(zoom, tile_x, tile_y)


func tile_attribution() -> String:
	return TileProvider.attribution()


func resolve_vehicle_status(
	location: Dictionary,
	coordinates_valid: bool,
	hours_since_update: float,
	ignition_state: int,
	colors: Dictionary
) -> Dictionary:
	return VehicleStatus.resolve(location, coordinates_valid, hours_since_update, ignition_state, colors)
