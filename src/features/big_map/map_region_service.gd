## Regras de região usadas pela camada de ERBs.
##
## Mantém seleção, contagem e descoberta da região fora da interface.
extends RefCounted

const Config := preload("res://src/features/big_map/big_map_config.gd")
const GeoProjection := preload("res://src/features/big_map/map_projection.gd")


static func definition(region_id: String) -> Dictionary:
	for value in Config.REGIONS:
		var region := value as Dictionary
		if str(region.get("id", "")) == region_id:
			return region.duplicate(true)
	return {}


static func region_id_for_coordinates(latitude: float, longitude: float) -> String:
	var nearest_id := ""
	var nearest_distance := INF
	var nearest_radius := 0.0
	for value in Config.REGIONS:
		var region := value as Dictionary
		var distance := GeoProjection.distance_km(
			latitude,
			longitude,
			float(region.get("lat", 0.0)),
			float(region.get("lng", 0.0))
		)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = str(region.get("id", ""))
			nearest_radius = float(region.get("radius_km", 0.0))
	return nearest_id if nearest_id != "" and nearest_distance <= nearest_radius else "other"


static func region_id_for_device(device: Dictionary) -> String:
	if not bool(device.get("location_available", false)):
		return "without_location"
	return region_id_for_coordinates(
		float(device.get("latitude", 0.0)),
		float(device.get("longitude", 0.0))
	)


static func counts_for_devices(devices: Array[Dictionary]) -> Dictionary:
	var counts := {}
	for device in devices:
		var region_id := region_id_for_device(device)
		counts[region_id] = int(counts.get(region_id, 0)) + 1
	return counts
