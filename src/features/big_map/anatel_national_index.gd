## Índice espacial nacional das ERBs licenciadas da Anatel.
##
## Lê apenas o manifesto no início. Em zoom distante usa arquivos de clusters;
## em zoom intermediário usa resumos z8; em zoom próximo abre somente células
## visíveis/vizinhas e as mantém em cache LRU limitado. Não acessa rede.
class_name AnatelNationalIndex
extends RefCounted

const GeoProjection := preload("res://src/features/big_map/map_projection.gd")

const MANIFEST_PATH := "res://data/anatel_smp_national_index/manifest.json"
const MANIFEST_HASH_PATH := "res://data/anatel_smp_national_index/manifest.sha256"
const INDEX_ROOT := "res://data/anatel_smp_national_index"
const DEFAULT_MAX_CACHE_CELLS := 32
const DEFAULT_MAX_CACHE_STATIONS := 20000
const DEFAULT_MAX_CACHE_SOURCE_BYTES := 16 * 1024 * 1024
const INDIVIDUAL_MIN_ZOOM := 10
const SUMMARY_MIN_ZOOM := 7

var metadata: Dictionary = {}
var manifest_sha256 := ""
var load_error := ""
var index_zoom := 8
var cells_by_key: Dictionary = {}
var cell_summaries: Array[Dictionary] = []
var cluster_files: Dictionary = {}
var cluster_cache: Dictionary = {}
var cell_cache: Dictionary = {}
var cell_cache_order: Array[String] = []
var cell_cache_station_count := 0
var cell_cache_source_bytes := 0
var verified_files: Dictionary = {}
var max_cache_cells := DEFAULT_MAX_CACHE_CELLS
var max_cache_stations := DEFAULT_MAX_CACHE_STATIONS
var max_cache_source_bytes := DEFAULT_MAX_CACHE_SOURCE_BYTES
var query_mutex := Mutex.new()


func load_manifest(path: String = MANIFEST_PATH) -> Dictionary:
	clear_cache()
	metadata.clear()
	cells_by_key.clear()
	cell_summaries.clear()
	cluster_files.clear()
	cluster_cache.clear()
	verified_files.clear()
	manifest_sha256 = ""
	if not FileAccess.file_exists(path):
		load_error = "Índice nacional particionado da Anatel não encontrado."
		return {"ok": false, "message": load_error}
	var parsed := _read_json_dictionary(path)
	if not bool(parsed.get("ok", false)):
		load_error = str(parsed.get("message", "Manifesto nacional inválido."))
		return {"ok": false, "message": load_error}
	var payload: Dictionary = parsed.get("value", {})
	metadata = (payload.get("metadata", {}) as Dictionary).duplicate(true)
	if str(metadata.get("scope", "")) != "Brasil" \
			or str(metadata.get("source_zip_sha256", "")).length() != 64 \
			or str(metadata.get("index_content_sha256", "")).length() != 64:
		load_error = "Manifesto nacional sem proveniência verificável."
		metadata.clear()
		return {"ok": false, "message": load_error}
	index_zoom = int(metadata.get("index_zoom", 10))
	for value in payload.get("cells", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var summary := (value as Dictionary).duplicate(true)
		var key := _cell_key(int(summary.get("cell_x", -1)), int(summary.get("cell_y", -1)))
		if key == "-1:-1":
			continue
		cells_by_key[key] = summary
		cell_summaries.append(summary)
	cluster_files = (payload.get("cluster_files", {}) as Dictionary).duplicate(true)
	if cells_by_key.is_empty() or cluster_files.is_empty():
		load_error = "Manifesto nacional sem células ou clusters."
		return {"ok": false, "message": load_error}
	if not FileAccess.file_exists(MANIFEST_HASH_PATH):
		load_error = "Sidecar SHA-256 do manifesto nacional ausente."
		return {"ok": false, "message": load_error}
	manifest_sha256 = FileAccess.get_sha256(path).to_upper()
	var hash_file := FileAccess.open(MANIFEST_HASH_PATH, FileAccess.READ)
	var hash_parts := hash_file.get_as_text().strip_edges().split(" ", false) if hash_file != null else PackedStringArray()
	var expected := str(hash_parts[0]).to_upper() if hash_parts.size() >= 1 else ""
	var expected_bytes := int(hash_parts[1]) if hash_parts.size() >= 2 and str(hash_parts[1]).is_valid_int() else -1
	var manifest_file := FileAccess.open(path, FileAccess.READ)
	var manifest_bytes := manifest_file.get_length() if manifest_file != null else -1
	if expected.length() != 64 or expected != manifest_sha256 or expected_bytes <= 0 or expected_bytes != manifest_bytes:
		load_error = "Hash do manifesto nacional não confere."
		return {"ok": false, "message": load_error}
	metadata["manifest_bytes"] = manifest_bytes
	load_error = ""
	return {
		"ok": true,
		"metadata": metadata.duplicate(true),
		"manifest_sha256": manifest_sha256,
		"cells": cells_by_key.size(),
	}


func query_viewport(bounds: Dictionary, zoom: int, filters: Dictionary = {}) -> Dictionary:
	if metadata.is_empty():
		return {"ok": false, "message": load_error if load_error != "" else "Índice nacional não carregado."}
	var safe_bounds := _normalized_bounds(bounds)
	if safe_bounds.is_empty():
		return {"ok": false, "message": "Viewport geográfico inválido."}
	var source: Array[Dictionary] = []
	var mode := "individual"
	var loaded_cells: Array[String] = []
	var city_filter := str(filters.get("city", ""))
	if zoom < SUMMARY_MIN_ZOOM and city_filter == "":
		mode = "national_clusters"
		var cluster_zoom := 4 if zoom <= 4 else 6
		source = _clusters_for_zoom(cluster_zoom, safe_bounds)
	elif zoom < INDIVIDUAL_MIN_ZOOM and city_filter == "":
		mode = "regional_clusters"
		source = _clusters_for_zoom(8, safe_bounds)
	else:
		var keys := _visible_cell_keys(safe_bounds, true)
		for key in keys:
			var rows: Variant = _load_cell(key)
			if rows == null:
				continue
			loaded_cells.append(key)
			for station in rows as Array:
				if typeof(station) != TYPE_DICTIONARY:
					continue
				var row := station as Dictionary
				if _point_in_bounds(float(row.get("lat", 0.0)), float(row.get("lng", 0.0)), safe_bounds):
					source.append(row)
	var filtered := filter_entries(source, filters)
	return {
		"ok": true,
		"mode": mode,
		"stations": filtered,
		"station_count": _entry_count(filtered),
		"visible_entries": filtered.size(),
		"loaded_cells": loaded_cells,
		"cache_cells": cell_cache.size(),
		"cache_stations": cell_cache_station_count,
		"metadata": metadata.duplicate(true),
	}


func query_viewport_threadsafe(bounds: Dictionary, zoom: int, filters: Dictionary = {}) -> Dictionary:
	# FileAccess/JSON são síncronos, por isso o controller chama este método em
	# WorkerThreadPool. O mutex protege o cache LRU quando gestos sucessivos
	# deixam uma consulta obsoleta ainda terminando em background.
	query_mutex.lock()
	var result := query_viewport(bounds, zoom, filters)
	query_mutex.unlock()
	return result


func query_viewport_threadsafe_to(
	bounds: Dictionary,
	zoom: int,
	filters: Dictionary,
	result_target: Dictionary
) -> void:
	result_target["result"] = query_viewport_threadsafe(bounds, zoom, filters)


func filter_entries(source: Array, filters: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in source:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry := value as Dictionary
		if bool(entry.get("is_index_cluster", false)):
			var filtered_cluster := _filtered_cluster(entry, filters)
			if not filtered_cluster.is_empty():
				result.append(filtered_cluster)
			continue
		if _station_matches(entry, filters):
			result.append(entry.duplicate(true))
	return result


func clear_cache() -> void:
	cell_cache.clear()
	cell_cache_order.clear()
	cell_cache_station_count = 0
	cell_cache_source_bytes = 0


func cache_state() -> Dictionary:
	return {
		"cells": cell_cache.size(),
		"stations": cell_cache_station_count,
		"source_bytes": cell_cache_source_bytes,
		"cache_bytes": cell_cache_source_bytes,
		"estimated_runtime_bytes": cell_cache_source_bytes + cell_cache_station_count * 256,
		"max_cells": max_cache_cells,
		"max_stations": max_cache_stations,
		"max_source_bytes": max_cache_source_bytes,
		"max_cache_bytes": max_cache_source_bytes,
		"single_oversized_cell_allowed": cell_cache.size() == 1 and (
			cell_cache_station_count > max_cache_stations or cell_cache_source_bytes > max_cache_source_bytes
		),
		"keys": cell_cache_order.duplicate(),
	}


func _clusters_for_zoom(zoom: int, bounds: Dictionary) -> Array[Dictionary]:
	var cache_key := str(zoom)
	if not cluster_cache.has(cache_key):
		var descriptor: Dictionary = cluster_files.get(cache_key, {})
		var rows: Variant = _load_index_file(str(descriptor.get("path", "")), str(descriptor.get("sha256", "")), "clusters")
		cluster_cache[cache_key] = rows
	var result: Array[Dictionary] = []
	for cluster in cluster_cache.get(cache_key, []) as Array:
		if typeof(cluster) == TYPE_DICTIONARY and _bbox_intersects((cluster as Dictionary).get("bbox", {}) as Dictionary, bounds):
			result.append((cluster as Dictionary).duplicate(true))
	return result


func _visible_cell_keys(bounds: Dictionary, include_neighbors: bool) -> Array[String]:
	var north_west: Dictionary = GeoProjection.lat_lng_to_tile(float(bounds.get("max_lat", 0.0)), float(bounds.get("min_lng", 0.0)), index_zoom)
	var south_east: Dictionary = GeoProjection.lat_lng_to_tile(float(bounds.get("min_lat", 0.0)), float(bounds.get("max_lng", 0.0)), index_zoom)
	var margin := 1 if include_neighbors else 0
	var min_x := maxi(0, mini(int(north_west.get("x", 0)), int(south_east.get("x", 0))) - margin)
	var max_x := maxi(int(north_west.get("x", 0)), int(south_east.get("x", 0))) + margin
	var min_y := maxi(0, mini(int(north_west.get("y", 0)), int(south_east.get("y", 0))) - margin)
	var max_y := maxi(int(north_west.get("y", 0)), int(south_east.get("y", 0))) + margin
	var result: Array[String] = []
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var key := _cell_key(x, y)
			if cells_by_key.has(key):
				result.append(key)
	return result


func _load_cell(key: String) -> Variant:
	if cell_cache.has(key):
		_touch_cache_key(key)
		return cell_cache[key]
	var descriptor: Dictionary = cells_by_key.get(key, {})
	if descriptor.is_empty():
		return null
	var rows: Variant = _load_index_file(str(descriptor.get("path", "")), str(descriptor.get("sha256", "")), "stations")
	if rows == null:
		return null
	cell_cache[key] = rows
	cell_cache_order.append(key)
	cell_cache_station_count += (rows as Array).size()
	cell_cache_source_bytes += int(descriptor.get("bytes", 0))
	_enforce_cache_limits()
	return cell_cache.get(key, null)


func _load_index_file(relative_path: String, expected_hash: String, array_field: String) -> Variant:
	if relative_path == "" or relative_path.contains("..") or expected_hash.length() != 64:
		return null
	var path := "%s/%s" % [INDEX_ROOT, relative_path]
	if not FileAccess.file_exists(path):
		return null
	if not verified_files.has(relative_path):
		if expected_hash != "" and FileAccess.get_sha256(path).to_upper() != expected_hash.to_upper():
			return null
		verified_files[relative_path] = true
	var parsed := _read_json_dictionary(path)
	if not bool(parsed.get("ok", false)):
		return null
	var payload: Dictionary = parsed.get("value", {})
	var rows: Variant = payload.get(array_field, [])
	return rows if typeof(rows) == TYPE_ARRAY else null


func _touch_cache_key(key: String) -> void:
	cell_cache_order.erase(key)
	cell_cache_order.append(key)


func _enforce_cache_limits() -> void:
	while cell_cache.size() > max_cache_cells \
			or cell_cache_station_count > max_cache_stations \
			or cell_cache_source_bytes > max_cache_source_bytes:
		# Uma única célula oficial nunca é descartada logo após a leitura. O
		# manifesto registra o maior shard para que esse excesso seja auditável.
		if cell_cache_order.size() <= 1:
			break
		var oldest: String = str(cell_cache_order.pop_front())
		var rows: Array = cell_cache.get(oldest, [])
		var descriptor: Dictionary = cells_by_key.get(oldest, {})
		cell_cache_station_count = maxi(0, cell_cache_station_count - rows.size())
		cell_cache_source_bytes = maxi(0, cell_cache_source_bytes - int(descriptor.get("bytes", 0)))
		cell_cache.erase(oldest)


func _filtered_cluster(entry: Dictionary, filters: Dictionary) -> Dictionary:
	var operator_filter := str(filters.get("operator", ""))
	var generation_filter := str(filters.get("generation", ""))
	var status_filter := str(filters.get("status", ""))
	var city_filter := str(filters.get("city", ""))
	if city_filter != "" and not _array_matches(entry.get("cities", []), city_filter):
		return {}
	var count := 0
	var facets: Dictionary = entry.get("facets", {})
	for facet_key in facets:
		var parts := str(facet_key).split("|")
		if parts.size() < 3:
			continue
		if not _value_matches(str(parts[0]), operator_filter):
			continue
		if not _value_matches(str(parts[1]), generation_filter):
			continue
		if not _value_matches(str(parts[2]), status_filter):
			continue
		count += int(facets[facet_key])
	if count <= 0:
		return {}
	var filtered := entry.duplicate(true)
	filtered["cluster_count"] = count
	filtered["operator"] = operator_filter if operator_filter not in ["", "__missing__"] else ""
	filtered["generation"] = generation_filter if generation_filter not in ["", "__missing__"] else ""
	filtered["status"] = status_filter if status_filter not in ["", "__missing__"] else "Licenciada"
	return filtered


func _station_matches(station: Dictionary, filters: Dictionary) -> bool:
	return _value_matches(str(station.get("operator", "")), str(filters.get("operator", ""))) \
			and _value_matches(str(station.get("generation", "")), str(filters.get("generation", ""))) \
			and _value_matches(str(station.get("city", "")), str(filters.get("city", ""))) \
			and _value_matches(str(station.get("status", "")), str(filters.get("status", "")))


func _value_matches(actual: String, expected: String) -> bool:
	if expected == "":
		return true
	if expected == "__missing__":
		return actual.strip_edges() == ""
	return actual.strip_edges().casecmp_to(expected.strip_edges()) == 0


func _array_matches(values: Variant, expected: String) -> bool:
	if expected == "":
		return true
	if typeof(values) != TYPE_ARRAY:
		return expected == "__missing__"
	for value in values as Array:
		if _value_matches(str(value), expected):
			return true
	return expected == "__missing__" and (values as Array).is_empty()


func _entry_count(entries: Array[Dictionary]) -> int:
	var total := 0
	for entry in entries:
		total += int(entry.get("cluster_count", 1)) if bool(entry.get("is_index_cluster", false)) else 1
	return total


func _normalized_bounds(bounds: Dictionary) -> Dictionary:
	var min_lat := float(bounds.get("min_lat", -91.0))
	var max_lat := float(bounds.get("max_lat", 91.0))
	var min_lng := float(bounds.get("min_lng", -181.0))
	var max_lng := float(bounds.get("max_lng", 181.0))
	if min_lat > max_lat or min_lng > max_lng \
			or min_lat < -90.0 or max_lat > 90.0 or min_lng < -180.0 or max_lng > 180.0:
		return {}
	return {"min_lat": min_lat, "max_lat": max_lat, "min_lng": min_lng, "max_lng": max_lng}


func _bbox_intersects(first: Dictionary, second: Dictionary) -> bool:
	return float(first.get("max_lat", -91.0)) >= float(second.get("min_lat", 91.0)) \
			and float(first.get("min_lat", 91.0)) <= float(second.get("max_lat", -91.0)) \
			and float(first.get("max_lng", -181.0)) >= float(second.get("min_lng", 181.0)) \
			and float(first.get("min_lng", 181.0)) <= float(second.get("max_lng", -181.0))


func _point_in_bounds(latitude: float, longitude: float, bounds: Dictionary) -> bool:
	return latitude >= float(bounds.get("min_lat", -90.0)) \
			and latitude <= float(bounds.get("max_lat", 90.0)) \
			and longitude >= float(bounds.get("min_lng", -180.0)) \
			and longitude <= float(bounds.get("max_lng", 180.0))


func _cell_key(x: int, y: int) -> String:
	return "%d:%d" % [x, y]


func _read_json_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "Arquivo não pôde ser aberto: %s" % path}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "message": "JSON inválido: %s" % path}
	return {"ok": true, "value": parsed as Dictionary}
