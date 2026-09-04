class_name InventoryStore
extends RefCounted

signal database_saved(snapshot: Dictionary, db_path: String)

const DEFAULT_DB_PATH := "C:/GRUPO RS CENTRAL/database/grupo_rs_central.sqlite"
const DEFAULT_LEGACY_PATH := "user://rastreadores.json"
const CLOUD_BACKUP_DIR_NAME := "Grupo RS Central"
const DEFAULT_CLOUD_BACKUP_FILE_NAME := "inventory_db.json"
const DEFAULT_LOCAL_BACKUP_DIR := "user://backups"
const ST310DecoderScript := preload("res://src/st310_decoder.gd")
const SCHEMA_VERSION := 3
const MAX_SYSTEM_LOGS := 1000
const SYSTEM_LOG_PRUNE_BATCH := 10
const SYSTEM_LOG_SCHEMA_VERSION := 2
const MAX_PENDING_SYNC_RECORDS := 10
const AUTOMATIC_BACKUP_RETENTION := 30
const AUTOMATIC_BACKUP_ROOT_NAME := "backups"
const INTERNAL_STOCK_PLATE_PREFIXES := ["GRS", "XRS", "AAA", "NOV"]

var _db: Dictionary = {}
var _loaded := false
var _db_path := DEFAULT_DB_PATH
var _legacy_path := DEFAULT_LEGACY_PATH
var _cloud_backup_file_name := DEFAULT_CLOUD_BACKUP_FILE_NAME
var _local_backup_dir := DEFAULT_LOCAL_BACKUP_DIR
var _migrate_legacy := true
var _online_only := true
var _remote_available := false
var _pending_sync_path := ""
var _pending_sync_queue: Array[Dictionary] = []
var _branch_id := "imperatriz"
var _sqlite := LocalSQLiteBridge.new()


func configure(db_path: String, cloud_backup_file_name: String = "", local_backup_dir: String = "", migrate_legacy: bool = false) -> void:
	_db_path = DEFAULT_DB_PATH
	_cloud_backup_file_name = cloud_backup_file_name if cloud_backup_file_name.strip_edges() != "" else _db_path.get_file()
	_local_backup_dir = local_backup_dir if local_backup_dir.strip_edges() != "" else DEFAULT_LOCAL_BACKUP_DIR
	_branch_id = _local_backup_dir.get_file().to_lower().strip_edges()
	if _branch_id == "" or _branch_id == "backups":
		_branch_id = "imperatriz"
	_migrate_legacy = migrate_legacy
	_db = _empty_db()
	_loaded = false
	_online_only = false
	_remote_available = true
	_pending_sync_path = "%s.pending.json" % _db_path
	_pending_sync_queue = _read_pending_sync_queue()


func configure_isolated_sqlite_for_testing(db_path: String, branch_id: String = "imperatriz") -> void:
	# Entrada explicita para testes: evita que qualquer cenario automatizado toque
	# no banco operacional. Nao e usada pelo fluxo normal do aplicativo.
	_db_path = db_path.strip_edges()
	_branch_id = branch_id.strip_edges().to_lower()
	if _branch_id == "":
		_branch_id = "imperatriz"
	_migrate_legacy = false
	_db = _empty_db()
	_loaded = false
	_online_only = false
	_remote_available = true
	_pending_sync_path = "%s.pending.json" % _db_path
	_pending_sync_queue.clear()


func load_db() -> Dictionary:
	if _loaded:
		return _db

	var loaded := _sqlite.execute("load", _db_path, {"branch": _branch_id})
	if bool(loaded.get("ok", false)):
		_db = _ensure_db_shape(loaded.get("snapshot", {}))
	elif _migrate_legacy and FileAccess.file_exists(_legacy_path):
		_db = _ensure_db_shape(_migrate_legacy_db(_read_legacy_array(_legacy_path)))
		_loaded = true
		save_db()
		return _db
	else:
		_db = _empty_db()

	_db = _ensure_db_shape(_db)
	_loaded = true
	return _db


func save_db(notify_remote_sync: bool = true) -> bool:
	if not _loaded and _db.is_empty():
		load_db()
	var saved := _sqlite.execute("save", _db_path, {"branch": _branch_id, "snapshot": _ensure_db_shape(_db)})
	if not bool(saved.get("ok", false)):
		return false
	if notify_remote_sync:
		database_saved.emit(_ensure_db_shape(_db.duplicate(true)), _db_path)
	return true


func verify_product_persisted(serial: String, expected_product: Dictionary = {}) -> Dictionary:
	# Leitura nova e independente do arquivo SQLite. Nunca usa apenas o cache em
	# memoria para afirmar ao operador que uma gravacao foi concluida.
	var loaded := _sqlite.execute("get_device", _db_path, {"branch": _branch_id, "sku": _normalize_sku(serial)})
	if not bool(loaded.get("ok", false)) or not bool(loaded.get("found", false)):
		return {"ok": false, "found": false, "message": "Falha ao reler o arquivo SQLite: %s" % _sqlite.last_error}
	var wanted := _normalize_sku(serial)
	if wanted == "" and not expected_product.is_empty():
		wanted = _normalize_sku(expected_product.get("sku", expected_product.get("imei", "")))
	var persisted := _normalize_product(loaded.get("product", {}) as Dictionary)
	if persisted.is_empty():
		return {"ok": false, "found": false, "matches": false, "message": "O registro nao foi encontrado ao reler o SQLite."}
	if expected_product.is_empty():
		return {"ok": true, "found": true, "matches": true, "product": persisted, "source": "sqlite_disk"}
	var expected := _normalize_product(expected_product)
	var mismatches: Array[String] = []
	for field in ["sku", "imei", "chip_number", "plate", "identification_plate", "vehicle_plate", "model", "operator", "tracker_status", "stock"]:
		if str(persisted.get(field, "")) != str(expected.get(field, "")):
			mismatches.append(str(field))
	if not mismatches.is_empty():
		return {
			"ok": false,
			"found": true,
			"matches": false,
			"mismatches": mismatches,
			"product": persisted,
			"message": "O SQLite foi relido, mas os campos nao conferem: %s." % ", ".join(mismatches),
		}
	return {"ok": true, "found": true, "matches": true, "product": persisted, "source": "sqlite_disk"}


func _persist_product_incremental(product: Dictionary, old_sku: String = "") -> bool:
	var result := _sqlite.execute("upsert_device", _db_path, {
		"branch": _branch_id,
		"product": product,
		"old_sku": _normalize_sku(old_sku),
	})
	return bool(result.get("ok", false)) and bool(result.get("found", false))


func _persist_product_with_movement_incremental(product: Dictionary, movement: Dictionary) -> bool:
	var result := _sqlite.execute("upsert_device_with_movement", _db_path, {
		"branch": _branch_id,
		"product": product,
		"movement": movement,
	})
	return bool(result.get("ok", false)) and bool(result.get("found", false))


func get_sync_snapshot() -> Dictionary:
	if not _loaded:
		load_db()
	return _ensure_db_shape(_db.duplicate(true))


func get_pending_sync_status() -> Dictionary:
	return {
		"count": _pending_sync_queue.size(),
		"limit": MAX_PENDING_SYNC_RECORDS,
		"full": _pending_sync_queue.size() >= MAX_PENDING_SYNC_RECORDS,
	}


func get_pending_sync_snapshot() -> Dictionary:
	if _pending_sync_queue.is_empty():
		return {}
	var last_entry: Dictionary = _pending_sync_queue.back()
	var snapshot: Variant = last_entry.get("snapshot", {})
	return _ensure_db_shape(snapshot as Dictionary) if typeof(snapshot) == TYPE_DICTIONARY else {}


func queue_pending_sync_snapshot(snapshot: Dictionary) -> bool:
	return _queue_pending_sync_snapshot(snapshot)


func clear_pending_sync_queue() -> void:
	_pending_sync_queue.clear()
	_remove_known_file(_pending_sync_path)


func mark_remote_available() -> void:
	_remote_available = true


func replace_from_remote(snapshot: Dictionary) -> bool:
	if not _is_valid_db_backup(snapshot):
		return false
	_db = _ensure_db_shape(snapshot.duplicate(true))
	_loaded = true
	_remote_available = true
	purge_legacy_operational_files()
	_write_automatic_remote_backup(_db)
	return true


func _write_automatic_remote_backup(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var backup_dir := _automatic_backup_dir()
	if not DirAccess.dir_exists_absolute(backup_dir):
		if DirAccess.make_dir_recursive_absolute(backup_dir) != OK:
			return
	# Um arquivo por filial e por dia evita uma pilha de cópias a cada refresh;
	# o conteúdo é sempre o último snapshot remoto confirmado daquele dia.
	var stamp := Time.get_date_string_from_system()
	var path := backup_dir.path_join("inventory_auto_%s.json" % stamp)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"schema": SCHEMA_VERSION,
		"created_at": Time.get_datetime_string_from_system(false, true),
		"source": "local_database",
		"branch_backup": _local_backup_dir.get_file(),
		"snapshot": _ensure_db_shape(snapshot),
	}, "\t"))
	file = null
	var files: Array[String] = []
	var dir := DirAccess.open(backup_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.begins_with("inventory_auto_") and name.ends_with(".json"):
			files.append(backup_dir.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	while files.size() > AUTOMATIC_BACKUP_RETENTION:
		DirAccess.remove_absolute(files.pop_front())


func get_automatic_backup_dir() -> String:
	return _automatic_backup_dir()


func get_automatic_backup_status() -> Dictionary:
	var dir := _automatic_backup_dir()
	var latest := _latest_backup_file(dir)
	return {
		"directory": dir,
		"latest": latest,
		"exists": latest != "",
		"retention_days": AUTOMATIC_BACKUP_RETENTION,
	}


func mark_remote_unavailable() -> void:
	_remote_available = false
	if not _loaded:
		_db = _empty_db()
		_loaded = true


func is_remote_available() -> bool:
	return _remote_available


func is_online_only() -> bool:
	return false


func purge_legacy_operational_files() -> void:
	for path in [
		_db_path,
		"%s.tmp" % _db_path,
		"%s.bak" % _db_path,
		_legacy_path if _migrate_legacy else "",
		"user://system_guardian_state.json",
		"user://system_guardian_state.json.tmp",
	]:
		_remove_known_file(str(path))

	_purge_json_files_in_dir(_global_path(_local_backup_dir))
	_purge_json_files_in_dir(_manual_backup_dir())

	var drive_root := _find_google_drive_root()
	if drive_root != "":
		var old_drive_dir := drive_root.path_join(CLOUD_BACKUP_DIR_NAME)
		_remove_known_file(old_drive_dir.path_join(_cloud_backup_file_name))
		_remove_known_file(old_drive_dir.path_join("%s.bak" % _cloud_backup_file_name))


func export_manual_backup() -> String:
	if not _loaded:
		load_db()
	if not save_db(false):
		return ""
	var result := _sqlite.execute("backup", _db_path, {
		"backup_dir": _automatic_backup_dir(),
		"app_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
	})
	return str(result.get("path", "")) if bool(result.get("ok", false)) else ""


func restore_backup(path: String, confirmation: String = "") -> bool:
	var clean_path := path.strip_edges()
	if clean_path == "" or not FileAccess.file_exists(clean_path):
		return false
	var result := _sqlite.execute("restore", _db_path, {
		"path": clean_path,
		"confirmation": confirmation,
		"operator": "lucasabm",
	})
	if not bool(result.get("ok", false)):
		return false
	_loaded = false
	load_db()
	return true


func inspect_backup(path: String) -> Dictionary:
	var clean_path := path.strip_edges()
	if clean_path == "" or not FileAccess.file_exists(clean_path):
		return {"valid": false, "message": "Arquivo nao encontrado."}
	var result := _sqlite.execute("inspect", _db_path, {"path": clean_path})
	result["valid"] = bool(result.get("ok", false))
	return result


func get_local_backup_dir() -> String:
	return _automatic_backup_dir()


func get_db_path() -> String:
	return _db_path


func get_global_db_path() -> String:
	return _global_path(_db_path)


func get_system_health() -> Dictionary:
	if not _loaded:
		load_db()

	return {
		"storage_mode": "SQLite local / offline-first",
		"remote_available": true,
		"products": (_db.get("products", []) as Array).size(),
		"movements": (_db.get("movements", []) as Array).size(),
		"system_logs": (_db.get("system_logs", []) as Array).size(),
		"maintenances": (_db.get("maintenances", []) as Array).size(),
	}


func get_runtime_state(key: String, fallback: Variant = null) -> Variant:
	if not _loaded:
		load_db()
	if not _remote_available:
		return fallback
	var runtime: Dictionary = _db.get("runtime", {})
	if not runtime.has(key):
		return fallback
	var value: Variant = runtime.get(key)
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY else value


func set_runtime_state(key: String, value: Variant) -> bool:
	if not _can_mutate() or key.strip_edges() == "":
		return false
	var runtime: Dictionary = _db.get("runtime", {})
	runtime[key] = value.duplicate(true) if typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY else value
	_db["runtime"] = runtime
	return save_db()


func sync_cloud_backup() -> bool:
	if _online_only:
		return false
	return _backup_db_to_cloud()


func is_cloud_backup_available() -> bool:
	if _online_only:
		return false
	return get_cloud_backup_path() != ""


func get_cloud_backup_path() -> String:
	if _online_only:
		return ""
	var drive_root := _find_google_drive_root()
	if drive_root == "":
		return ""
	return drive_root.path_join(CLOUD_BACKUP_DIR_NAME).path_join(_cloud_backup_file_name)


func _manual_backup_dir() -> String:
	var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if downloads.strip_edges() != "":
		return downloads.path_join("Grupo RS Central Backups")
	return ProjectSettings.globalize_path(_local_backup_dir)


func _automatic_backup_dir() -> String:
	var base_dir := ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")
	if not OS.has_feature("editor"):
		base_dir = OS.get_executable_path().get_base_dir()
	var branch_name := _local_backup_dir.get_file().strip_edges()
	if branch_name == "":
		branch_name = "default"
	return base_dir.path_join(AUTOMATIC_BACKUP_ROOT_NAME).path_join(branch_name)


func _backup_db_to_cloud() -> bool:
	if _online_only:
		return false
	var backup_path := get_cloud_backup_path()
	if backup_path == "":
		return false

	var backup_dir := backup_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(backup_dir):
		var make_error := DirAccess.make_dir_recursive_absolute(backup_dir)
		if make_error != OK:
			return false

	var file := FileAccess.open(backup_path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(_db, "\t"))
	file = null
	return true


func _find_google_drive_root() -> String:
	var candidates: Array[String] = []
	var user_profile := OS.get_environment("USERPROFILE")
	var home := OS.get_environment("HOME")
	var env_drive := OS.get_environment("GOOGLE_DRIVE")

	if env_drive.strip_edges() != "":
		candidates.append(env_drive)
	if user_profile.strip_edges() != "":
		candidates.append(user_profile.path_join("Google Drive"))
		candidates.append(user_profile.path_join("Meu Drive"))
		candidates.append(user_profile.path_join("My Drive"))
		candidates.append(user_profile.path_join("Drive"))
	if home.strip_edges() != "" and home != user_profile:
		candidates.append(home.path_join("Google Drive"))
		candidates.append(home.path_join("Meu Drive"))
		candidates.append(home.path_join("My Drive"))

	var alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	for i in range(alphabet.length()):
		var letter := alphabet.substr(i, 1)
		candidates.append("%s:/Meu Drive" % letter)
		candidates.append("%s:/My Drive" % letter)
		candidates.append("%s:/Google Drive" % letter)

	for candidate in candidates:
		var path := str(candidate).strip_edges()
		if path != "" and DirAccess.dir_exists_absolute(path):
			return path

	return ""


func get_products(
	query: String = "",
	category: String = "",
	low_stock_only: bool = false,
	sort_results: bool = true
) -> Array[Dictionary]:
	if not _loaded:
		load_db()

	var normalized_query := query.strip_edges().to_lower()
	var normalized_category := category.strip_edges().to_lower()
	var result: Array[Dictionary] = []

	for product in _db.get("products", []):
		if typeof(product) != TYPE_DICTIONARY:
			continue

		var item := _normalize_product(product)
		if item.is_empty():
			continue

		if normalized_category != "" and normalized_category != "all":
			if item.get("category", "").to_lower() != normalized_category:
				continue

		if low_stock_only and not _is_low_stock(item):
			continue

		if normalized_query != "" and not _matches_query(item, normalized_query):
			continue

		result.append(item)

	if sort_results:
		result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_name := str(a.get("name", "")).to_lower()
			var b_name := str(b.get("name", "")).to_lower()
			if a_name == b_name:
				return str(a.get("sku", "")).to_lower() < str(b.get("sku", "")).to_lower()
			return a_name < b_name
		)

	return result


func get_categories() -> Array[String]:
	if not _loaded:
		load_db()

	var categories: Array[String] = []
	for product in _db.get("products", []):
		if typeof(product) != TYPE_DICTIONARY:
			continue

		var category := str(product.get("category", "")).strip_edges()
		if category == "" or categories.has(category):
			continue

		categories.append(category)

	categories.sort()
	return categories


func get_status_values() -> Array[String]:
	if not _loaded:
		load_db()

	var statuses: Array[String] = ["Todos", "Estoque", "Reserva", "Instalado", "Manutencao", "Inativo"]
	for product in _db.get("products", []):
		if typeof(product) != TYPE_DICTIONARY:
			continue

		var status := str(_normalize_product(product).get("tracker_status", "")).strip_edges()
		if status != "" and not statuses.has(status):
			statuses.append(status)

	return statuses


func get_product(sku: String) -> Dictionary:
	if not _loaded:
		load_db()

	var normalized_sku := _normalize_sku(sku)
	for product in _db.get("products", []):
		if typeof(product) != TYPE_DICTIONARY:
			continue

		var item := _normalize_product(product)
		if item.get("sku", "") == normalized_sku:
			return item

	return {}


func ingest_st310_packet(raw_packet: Variant, received_at: String = "") -> Dictionary:
	## Persiste um pacote bruto ST310 sem consultar a API de localizacao.
	## A serie precisa estar associada a um produto local/Banco local SQL existente;
	## nenhum cadastro e criado automaticamente por telemetria.
	if not _can_mutate():
		return {"ok": false, "retryable": true, "message": "Armazenamento operacional indisponivel."}
	if not _loaded:
		load_db()

	var decoded: Dictionary = ST310DecoderScript.decode(raw_packet)
	if not bool(decoded.get("ok", false)):
		return {"ok": false, "retryable": false, "message": str(decoded.get("message", "Pacote ST310 invalido.")), "decoded": decoded}
	var fields: Dictionary = decoded.get("fields", {}) as Dictionary
	var serial := _st310_serial_from_fields(fields)
	if serial == "":
		return {"ok": false, "retryable": false, "message": "Pacote ST310 sem serie/ID valido.", "decoded": decoded}
	var products: Array = _db.get("products", [])
	var product_index := _find_product_index_by_st310_serial(products, serial)
	if product_index < 0:
		return {"ok": false, "retryable": true, "message": "Serie ST310 recebida sem associacao local: %s." % serial, "serial": serial, "decoded": decoded}

	var raw_text := _st310_raw_text(raw_packet)
	if raw_text == "" or raw_text.length() > 65536:
		return {"ok": false, "retryable": false, "message": "Pacote ST310 vazio ou maior que 64 KB.", "serial": serial}
	var product := _normalize_product(products[product_index])
	var packet_hash := _st310_value_hash(raw_text)
	if str(product.get("st310_packet_hash", "")).strip_edges() == packet_hash \
		and str(product.get("st310_raw_packet", "")).strip_edges() == raw_text:
		return {
			"ok": true,
			"duplicate": true,
			"serial": serial,
			"sku": str(product.get("sku", "")),
			"decoded": decoded,
			"storage": "local_database" if _remote_available else "pending_local_database",
			"message": "Pacote ST310 duplicado; nenhuma gravacao repetida foi feita.",
		}
	var previous_products := products.duplicate(true)
	var stamp := received_at.strip_edges()
	if stamp == "":
		stamp = _now_string()
	var communication_at := str(fields.get("communication_at", "")).strip_edges()
	product["st310_raw_packet"] = raw_text
	product["st310_packet_at"] = communication_at if communication_at != "" else stamp
	product["st310_packet_received_at"] = stamp
	product["st310_decoder_kind"] = str(decoded.get("kind", "communication"))
	product["st310_decoder_message"] = str(decoded.get("message", ""))
	product["st310_packet_hash"] = packet_hash
	product["updated_at"] = stamp
	products[product_index] = product
	_db["products"] = products
	if not _persist_product_incremental(product):
		_db["products"] = previous_products
		return {"ok": false, "retryable": true, "message": "Banco local SQL recusou o pacote ST310; alteracao preservada para nova tentativa.", "serial": serial}
	return {
		"ok": true,
		"serial": serial,
		"sku": str(product.get("sku", "")),
		"decoded": decoded,
		"storage": "local_database" if _remote_available else "pending_local_database",
		"message": "Pacote ST310 armazenado e pronto para o mapa.",
	}


func get_maintenances(include_completed: bool = false) -> Array[Dictionary]:
	if not _loaded:
		load_db()

	var result: Array[Dictionary] = []
	for entry in _db.get("maintenances", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item := _normalize_maintenance(entry)
		if not item.is_empty():
			if not include_completed and str(item.get("status", "")) == "concluido":
				continue
			result.append(item)

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_schedule := "%s %s" % [str(a.get("scheduled_date", "")), str(a.get("scheduled_time", ""))]
		var b_schedule := "%s %s" % [str(b.get("scheduled_date", "")), str(b.get("scheduled_time", ""))]
		if a_schedule.strip_edges() != b_schedule.strip_edges():
			return a_schedule < b_schedule
		return str(a.get("created_at", "")) < str(b.get("created_at", ""))
	)
	return result


func get_scheduled_maintenances(query: String = "") -> Array[Dictionary]:
	var normalized_query := _normalize_search_text(query)
	var result: Array[Dictionary] = []
	for item in get_maintenances(false):
		if str(item.get("scheduled_date", "")).strip_edges() == "" and str(item.get("scheduled_time", "")).strip_edges() == "":
			continue
		if normalized_query != "" and not _matches_maintenance_query(item, normalized_query):
			continue
		result.append(item)
	return result


func add_maintenances(rows: Array) -> Dictionary:
	if not _can_mutate():
		return {"created": 0, "updated": 0, "errors": ["Servidor online indisponivel."]}
	if not _loaded:
		load_db()

	var maintenances: Array = _db.get("maintenances", [])
	var created := 0
	var updated := 0
	var errors: Array[String] = []

	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var item := _normalize_maintenance(row)
		if item.is_empty():
			errors.append("Linha ignorada: dados incompletos.")
			continue

		var existing_index := _find_maintenance_index(str(item.get("serial", "")), str(item.get("plate", "")))
		if existing_index >= 0:
			var current := _normalize_maintenance(maintenances[existing_index])
			item["id"] = current.get("id", item.get("id", ""))
			item["created_at"] = current.get("created_at", _now_string())
			item["scheduled_date"] = current.get("scheduled_date", "")
			item["scheduled_time"] = current.get("scheduled_time", "")
			var existing_note := str(current.get("note", "")).strip_edges()
			if existing_note != "":
				item["note"] = existing_note
			item["updated_at"] = _now_string()
			maintenances[existing_index] = item
			updated += 1
		else:
			item["id"] = _new_maintenance_id(maintenances.size())
			item["created_at"] = _now_string()
			item["updated_at"] = _now_string()
			maintenances.append(item)
			created += 1

	_db["maintenances"] = maintenances
	save_db()
	return {
		"created": created,
		"updated": updated,
		"errors": errors,
	}


func update_maintenance_schedule(id: String, scheduled_date: String, scheduled_time: String) -> bool:
	if not _can_mutate():
		return false
	if not _loaded:
		load_db()

	var index := _find_maintenance_index_by_id(id)
	if index < 0:
		return false

	var maintenances: Array = _db.get("maintenances", [])
	var item := _normalize_maintenance(maintenances[index])
	item["scheduled_date"] = scheduled_date.strip_edges()
	item["scheduled_time"] = scheduled_time.strip_edges()
	item["status"] = "agendado"
	item["updated_at"] = _now_string()
	maintenances[index] = item
	_db["maintenances"] = maintenances
	return save_db()


func update_maintenance_note(id: String, note: String) -> bool:
	if not _can_mutate():
		return false
	if not _loaded:
		load_db()

	var index := _find_maintenance_index_by_id(id)
	if index < 0:
		return false

	var maintenances: Array = _db.get("maintenances", [])
	var item := _normalize_maintenance(maintenances[index])
	item["note"] = note.strip_edges()
	item["updated_at"] = _now_string()
	maintenances[index] = item
	_db["maintenances"] = maintenances
	return save_db()


func complete_maintenance(id: String) -> bool:
	if not _can_mutate():
		return false
	if not _loaded:
		load_db()

	var index := _find_maintenance_index_by_id(id)
	if index < 0:
		return false

	var maintenances: Array = _db.get("maintenances", [])
	var item := _normalize_maintenance(maintenances[index])
	item["status"] = "concluido"
	item["completed_at"] = _now_string()
	item["updated_at"] = _now_string()
	maintenances[index] = item
	_db["maintenances"] = maintenances
	return save_db()


func delete_maintenance(id: String) -> bool:
	if not _can_mutate():
		return false
	if not _loaded:
		load_db()

	var index := _find_maintenance_index_by_id(id)
	if index < 0:
		return false

	var maintenances: Array = _db.get("maintenances", [])
	maintenances.remove_at(index)
	_db["maintenances"] = maintenances
	return save_db()


func delete_maintenances(ids: Array[String]) -> int:
	if not _can_mutate():
		return 0
	if not _loaded:
		load_db()
	if ids.is_empty():
		return 0
	var wanted := {}
	for id in ids:
		var clean_id := str(id).strip_edges()
		if clean_id != "":
			wanted[clean_id] = true
	var maintenances: Array = _db.get("maintenances", [])
	var kept: Array = []
	var removed := 0
	for entry in maintenances:
		if typeof(entry) == TYPE_DICTIONARY and wanted.has(str((entry as Dictionary).get("id", "")).strip_edges()):
			removed += 1
			continue
		kept.append(entry)
	if removed <= 0:
		return 0
	_db["maintenances"] = kept
	return removed if save_db() else 0


func get_tracker_stats() -> Dictionary:
	if not _loaded:
		load_db()

	var stats := {
		"total": 0,
		"available": 0,
		"active": 0,
		"maintenance": 0,
		"inactive": 0,
		"linked": 0,
		"clients": 0,
		"updated": 0,
		"outdated": 0,
		"reserved": 0,
		"installed": 0,
		"operators": {},
	}
	for product in _db.get("products", []):
		if typeof(product) != TYPE_DICTIONARY:
			continue

		var item := _normalize_product(product)
		if item.is_empty():
			continue

		stats["total"] = int(stats.get("total", 0)) + 1
		var status_key := _status_key(item)
		match status_key:
			"instalado":
				stats["installed"] = int(stats.get("installed", 0)) + 1
				stats["active"] = int(stats.get("active", 0)) + 1
			"manutencao":
				stats["maintenance"] = int(stats.get("maintenance", 0)) + 1
			"inativo":
				stats["inactive"] = int(stats.get("inactive", 0)) + 1
			"reserva":
				stats["reserved"] = int(stats.get("reserved", 0)) + 1
			_:
				stats["available"] = int(stats.get("available", 0)) + 1

		if status_key == "instalado":
			stats["linked"] = int(stats.get("linked", 0)) + 1

		if status_key == "manutencao" or status_key == "inativo":
			stats["outdated"] = int(stats.get("outdated", 0)) + 1
		else:
			stats["updated"] = int(stats.get("updated", 0)) + 1

		var operator_name := str(item.get("operator", "")).strip_edges()
		if operator_name == "":
			operator_name = "Sem operadora"
		var operators: Dictionary = stats.get("operators", {})
		operators[operator_name] = int(operators.get(operator_name, 0)) + 1
		stats["operators"] = operators

	stats["clients"] = int(stats.get("reserved", 0))
	return stats


func upsert_product(product_data: Dictionary) -> Dictionary:
	return upsert_product_replacing_sku("", product_data)


func upsert_product_replacing_sku(old_sku: String, product_data: Dictionary) -> Dictionary:
	if not _can_mutate():
		return {}
	if not _loaded:
		load_db()

	var item := _normalize_product(product_data)
	if item.is_empty():
		return {}

	var products: Array = _db.get("products", [])
	var previous_products := products.duplicate(true)
	var old_index := _find_product_index(old_sku)
	var existing_index := _find_product_index(item.get("sku", ""))
	if existing_index >= 0:
		var current := _normalize_product(products[existing_index])
		item["created_at"] = current.get("created_at", _now_string())
		item["updated_at"] = _now_string()
		if not product_data.has("stock"):
			item["stock"] = current.get("stock", 0)
		for history_field in ["installed_at", "discharged_at", "last_movement_at"]:
			if not product_data.has(history_field):
				item[history_field] = current.get(history_field, "")
		products[existing_index] = item
		if old_index >= 0 and old_index != existing_index:
			products.remove_at(old_index)
	elif old_index >= 0:
		var previous := _normalize_product(products[old_index])
		item["created_at"] = previous.get("created_at", _now_string())
		item["updated_at"] = _now_string()
		if not product_data.has("stock"):
			item["stock"] = previous.get("stock", 0)
		for history_field in ["installed_at", "discharged_at", "last_movement_at"]:
			if not product_data.has(history_field):
				item[history_field] = previous.get(history_field, "")
		products[old_index] = item
	else:
		var now := _now_string()
		item["created_at"] = now
		item["updated_at"] = now
		products.append(item)

	# Manutencao nao possui uma data de instalacao vigente.
	# As baixas anteriores continuam preservadas nos movimentos e no historico.
	if _status_key(item) == "manutencao":
		item["installed_at"] = ""
		item["discharged_at"] = ""

	_db["products"] = products
	if not _persist_product_incremental(item, old_sku):
		_db["products"] = previous_products
		return {}
	return item


func commit_appliance_replacement_local(source_sku: String, target_sku: String, target_patch: Dictionary, source_patch: Dictionary, maintenance_row: Dictionary) -> Dictionary:
	# Aplica as duas mudancas locais e a manutencao em uma unica gravacao.
	# A troca remota pode ser confirmada antes do Banco local SQL. Por isso a parte
	# local precisa ser atomica: nenhum aparelho fica parcialmente atualizado.
	if not _can_mutate():
		return {"ok": false, "message": "Servidor online indisponivel para confirmar a troca local."}
	if not _loaded:
		load_db()

	var clean_source := _normalize_sku(source_sku)
	var clean_target := _normalize_sku(target_sku)
	if clean_source == "" or clean_target == "" or clean_source == clean_target:
		return {"ok": false, "message": "Os aparelhos de origem e destino precisam ser diferentes."}

	var products: Array = _db.get("products", [])
	var source_index := _find_product_index(clean_source)
	var target_index := _find_product_index(clean_target)
	if source_index < 0 or target_index < 0:
		return {"ok": false, "message": "Os dois aparelhos precisam existir no estoque local para confirmar a troca."}

	var previous_products := products.duplicate(true)
	var previous_maintenances: Array = (_db.get("maintenances", []) as Array).duplicate(true)
	var source := _normalize_product(products[source_index])
	var target := _normalize_product(products[target_index])
	for key in target_patch.keys():
		target[str(key)] = target_patch.get(key)
	for key in source_patch.keys():
		source[str(key)] = source_patch.get(key)
	target["updated_at"] = _now_string()
	source["updated_at"] = _now_string()
	products[target_index] = target
	products[source_index] = source

	var maintenance := _normalize_maintenance(maintenance_row)
	if maintenance.is_empty():
		return {"ok": false, "message": "O registro de manutencao da troca esta incompleto."}
	var maintenances: Array = previous_maintenances.duplicate(true)
	var maintenance_index := _find_maintenance_index(str(maintenance.get("serial", "")), str(maintenance.get("plate", "")))
	if maintenance_index >= 0:
		var current_maintenance := _normalize_maintenance(maintenances[maintenance_index])
		maintenance["id"] = current_maintenance.get("id", maintenance.get("id", ""))
		maintenance["created_at"] = current_maintenance.get("created_at", _now_string())
		maintenance["updated_at"] = _now_string()
		maintenances[maintenance_index] = maintenance
	else:
		maintenance["id"] = _new_maintenance_id(maintenances.size())
		maintenance["created_at"] = _now_string()
		maintenance["updated_at"] = _now_string()
		maintenances.append(maintenance)

	_db["products"] = products
	_db["maintenances"] = maintenances
	if save_db():
		return {"ok": true, "source": source, "target": target, "maintenance": maintenance}

	_db["products"] = previous_products
	_db["maintenances"] = previous_maintenances
	return {"ok": false, "message": "O Banco local SQL recusou a gravacao atomica da troca local; os dois aparelhos foram preservados."}


func find_duplicate_product(product_data: Dictionary, ignore_sku: String = "") -> Dictionary:
	if not _loaded:
		load_db()

	var normalized := _normalize_product(product_data)
	if normalized.is_empty():
		return {}

	var ignored := _normalize_sku(ignore_sku)
	var sku := _normalize_sku(normalized.get("sku", ""))
	var imei := str(normalized.get("imei", "")).strip_edges().to_upper()
	var plate := str(normalized.get("plate", "")).strip_edges().to_upper()
	var chip := str(normalized.get("chip_number", "")).strip_edges().to_upper()

	for product in _db.get("products", []):
		if typeof(product) != TYPE_DICTIONARY:
			continue
		var current := _normalize_product(product)
		var current_sku := _normalize_sku(current.get("sku", ""))
		if ignored != "" and current_sku == ignored:
			continue
		if sku != "" and current_sku == sku:
			return {"field": "IMEI", "product": current}
		if imei != "" and str(current.get("imei", "")).strip_edges().to_upper() == imei:
			return {"field": "IMEI", "product": current}
		if plate != "" and str(current.get("plate", "")).strip_edges().to_upper() == plate:
			return {"field": "placa", "product": current}
		if chip != "" and str(current.get("chip_number", "")).strip_edges().to_upper() == chip:
			return {"field": "chip", "product": current}

	return {}


func upsert_historical_installed_product(product_data: Dictionary, installed_at: String) -> Dictionary:
	if not _can_mutate():
		return {}
	if not _loaded:
		load_db()

	var item := _normalize_product(product_data)
	if item.is_empty():
		return {}

	var clean_date := installed_at.strip_edges()
	if clean_date == "":
		clean_date = _now_string()

	item["tracker_status"] = "Instalado"
	item["status"] = "Instalado"
	item["location"] = "Instalado"
	item["stock"] = 0
	item["active"] = true
	item["installed_at"] = clean_date
	item["discharged_at"] = clean_date
	item["last_movement_at"] = clean_date

	var products: Array = _db.get("products", [])
	var existing_index := _find_product_index(item.get("sku", ""))
	if existing_index >= 0:
		var current := _normalize_product(products[existing_index])
		item["created_at"] = current.get("created_at", clean_date)
		item["updated_at"] = _now_string()
		products[existing_index] = item
	else:
		item["created_at"] = clean_date
		item["updated_at"] = _now_string()
		products.append(item)

	_db["products"] = products
	save_db()
	return item


func set_tracker_status(sku: String, status: String) -> bool:
	if not _can_mutate():
		return false
	if not _loaded:
		load_db()

	var index := _find_product_index(sku)
	if index < 0:
		return false

	var products: Array = _db.get("products", [])
	var previous_products := products.duplicate(true)
	var product := _normalize_product(products[index])
	var previous_status_key := _status_key(product)
	var clean_status := status.strip_edges()
	if clean_status == "":
		clean_status = "Estoque"
	var next_status_key := _status_key_from_text(clean_status)

	product["tracker_status"] = clean_status
	product["status"] = clean_status
	product["location"] = clean_status
	product["active"] = next_status_key != "inativo"
	product["stock"] = 1 if next_status_key == "estoque" else 0
	if next_status_key == "estoque" and previous_status_key == "instalado":
		product["vehicle_plate"] = ""
		product["plate"] = str(product.get("identification_plate", ""))
		product["installed_at"] = ""
		product["discharged_at"] = ""
	if next_status_key == "manutencao":
		product["installed_at"] = ""
		product["discharged_at"] = ""
	product["updated_at"] = _now_string()

	products[index] = product
	_db["products"] = products
	if not _persist_product_incremental(product):
		_db["products"] = previous_products
		return false
	return true


func add_system_log(action: String, details: String = "", sku: String = "") -> bool:
	return add_system_log_event(action, details, sku, {})


func add_system_log_event(action: String, details: String = "", sku: String = "", metadata: Dictionary = {}) -> bool:
	if not _can_mutate():
		return false
	if not _loaded:
		load_db()

	var clean_action := action.strip_edges()
	if clean_action == "":
		clean_action = "Acao do sistema"

	var logs: Array = _db.get("system_logs", [])
	var event_id := "log-%s-%s-%s" % [Time.get_unix_time_from_system(), Time.get_ticks_msec(), logs.size()]
	var clean_details := details.strip_edges()
	var event := {
		"schema_version": SYSTEM_LOG_SCHEMA_VERSION,
		"id": event_id,
		"timestamp": _now_string(),
		"action": clean_action,
		"details": clean_details,
		"sku": _normalize_sku(sku),
	}
	var enriched := _infer_system_log_metadata(clean_action, clean_details, _normalize_sku(sku), metadata, event_id)
	for key in enriched.keys():
		event[str(key)] = enriched[key]
	logs.append(event)

	logs = _prune_system_logs(logs)

	_db["system_logs"] = logs
	var persisted := _sqlite.execute("append_audit", _db_path, {"branch": _branch_id, "event": event})
	if not bool(persisted.get("ok", false)):
		logs.erase(event)
		_db["system_logs"] = logs
		return false
	return true


func get_system_logs(limit: int = 300) -> Array[Dictionary]:
	if not _loaded:
		load_db()

	var logs: Array = _db.get("system_logs", [])
	var result: Array[Dictionary] = []
	for i in range(logs.size() - 1, -1, -1):
		var entry = logs[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		result.append(_normalize_system_log(entry))
		if limit > 0 and result.size() >= limit:
			break

	return result


func get_remote_operation_metrics(limit: int = 0) -> Dictionary:
	"""Resume saude, risco e observabilidade das operacoes remotas."""
	var metrics := {
		"total": 0,
		"completed": 0,
		"progress": 0,
		"failed": 0,
		"fallback": 0,
		"pending_confirmation": 0,
		"http_5xx": 0,
		"http_4xx": 0,
		"no_http_observability": 0,
		"retryable_failures": 0,
		"association_conflicts": 0,
		"confirmation_mismatches": 0,
		"risk_high": 0,
		"risk_medium": 0,
		"risk_low": 0,
		"average_latency_ms": 0,
		"p50_latency_ms": 0,
		"p95_latency_ms": 0,
		"success_rate": 0.0,
		"fallback_rate": 0.0,
		"observability_rate": 0.0,
	}
	var latencies: Array[int] = []
	var total_latency := 0
	var observable_count := 0
	for entry in get_system_logs(limit):
		var phase := str(entry.get("phase", "")).to_lower()
		var transport := str(entry.get("transport", "")).to_lower()
		var action := str(entry.get("action", "")).to_lower()
		var is_remote := phase in ["cadastro", "modificacao", "vinculacao"] or transport in ["api", "web"] or action.contains("remot") or action.contains("grupo rs")
		if not is_remote:
			continue
		metrics["total"] = int(metrics["total"]) + 1
		var status := str(entry.get("status", "info")).to_lower()
		if status == "completed":
			metrics["completed"] = int(metrics["completed"]) + 1
		elif status == "progress":
			metrics["progress"] = int(metrics["progress"]) + 1
		elif status == "failed":
			metrics["failed"] = int(metrics["failed"]) + 1
		if bool(entry.get("fallback_used", false)) or transport == "web":
			metrics["fallback"] = int(metrics["fallback"]) + 1
		if bool(entry.get("confirmation_pending", false)) or status == "progress":
			metrics["pending_confirmation"] = int(metrics["pending_confirmation"]) + 1
		var http_code := int(entry.get("http_code", 0))
		if http_code >= 500:
			metrics["http_5xx"] = int(metrics["http_5xx"]) + 1
		elif http_code >= 400:
			metrics["http_4xx"] = int(metrics["http_4xx"]) + 1
		if transport in ["api", "web"]:
			if http_code > 0:
				observable_count += 1
			elif phase != "sincronizacao":
				metrics["no_http_observability"] = int(metrics["no_http_observability"]) + 1
		if bool(entry.get("retryable", false)) and status == "failed":
			metrics["retryable_failures"] = int(metrics["retryable_failures"]) + 1
		var text := (str(entry.get("action", "")) + " " + str(entry.get("details", ""))).to_lower()
		if text.contains("associad") or text.contains("duplic") or text.contains("conflit"):
			metrics["association_conflicts"] = int(metrics["association_conflicts"]) + 1
		if text.contains("nao confirmou") or text.contains("diverg") or text.contains("mismatch") or bool(entry.get("confirmation_pending", false)):
			metrics["confirmation_mismatches"] = int(metrics["confirmation_mismatches"]) + 1
		var risk_level := str(entry.get("risk_level", "low")).to_lower()
		if risk_level == "high":
			metrics["risk_high"] = int(metrics["risk_high"]) + 1
		elif risk_level == "medium":
			metrics["risk_medium"] = int(metrics["risk_medium"]) + 1
		else:
			metrics["risk_low"] = int(metrics["risk_low"]) + 1
		var latency_ms := int(entry.get("latency_ms", 0))
		if latency_ms > 0:
			latencies.append(latency_ms)
			total_latency += latency_ms
	if latencies.size() > 0:
		latencies.sort()
		metrics["average_latency_ms"] = int(round(float(total_latency) / float(latencies.size())))
		metrics["p50_latency_ms"] = latencies[int(float(latencies.size() - 1) * 0.50)]
		metrics["p95_latency_ms"] = latencies[int(float(latencies.size() - 1) * 0.95)]
	var total := int(metrics["total"])
	if total > 0:
		metrics["success_rate"] = float(metrics["completed"]) / float(total)
		metrics["fallback_rate"] = float(metrics["fallback"]) / float(total)
		metrics["observability_rate"] = float(observable_count) / float(total)
	return metrics


func get_product_history(sku: String, limit: int = 120) -> Array[Dictionary]:
	if not _loaded:
		load_db()

	var normalized_sku := _normalize_sku(sku)
	var events: Array[Dictionary] = []
	var product := get_product(normalized_sku)
	if product.is_empty():
		return events

	_add_history_event(events, str(product.get("created_at", "")), "Cadastro", "Produto criado", normalized_sku)
	_add_history_event(events, str(product.get("updated_at", "")), "Atualizacao", "Ultima alteracao do cadastro", normalized_sku)
	var identification_plate := str(product.get("identification_plate", "")).strip_edges()
	var vehicle_plate := str(product.get("vehicle_plate", product.get("plate", ""))).strip_edges()
	var installation_details := "Instalado no veiculo %s" % vehicle_plate
	if identification_plate != "":
		installation_details = "Identificacao %s instalada no veiculo %s" % [identification_plate, vehicle_plate]
	_add_history_event(events, str(product.get("installed_at", "")), "Instalacao", installation_details, normalized_sku)
	_add_history_event(events, str(product.get("discharged_at", "")), "Baixa", "Baixa registrada", normalized_sku)

	for movement in _db.get("movements", []):
		if typeof(movement) != TYPE_DICTIONARY:
			continue
		if _normalize_sku(movement.get("sku", "")) != normalized_sku:
			continue
		_add_history_event(events, str(movement.get("timestamp", "")), str(movement.get("type", "Movimento")).capitalize(), str(movement.get("reason", "")), normalized_sku)

	for log_entry in _db.get("system_logs", []):
		if typeof(log_entry) != TYPE_DICTIONARY:
			continue
		if _normalize_sku(log_entry.get("sku", "")) != normalized_sku:
			continue
		_add_history_event(events, str(log_entry.get("timestamp", "")), str(log_entry.get("action", "Acao")), str(log_entry.get("details", "")), normalized_sku)

	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("timestamp", "")) > str(b.get("timestamp", ""))
	)
	if limit > 0 and events.size() > limit:
		events = events.slice(0, limit)
	return events


func get_diagnostics() -> Array[Dictionary]:
	if not _loaded:
		load_db()

	var result: Array[Dictionary] = []
	var seen_skus := {}
	var seen_imeis := {}

	for product in _db.get("products", []):
		if typeof(product) != TYPE_DICTIONARY:
			continue

		var item := _normalize_product(product)
		var sku := str(item.get("sku", ""))
		var imei := str(item.get("imei", ""))
		var status_key := _status_key(item)
		var plate := str(item.get("plate", "")).strip_edges()
		var operator_name := str(item.get("operator", "")).strip_edges()
		var model := str(item.get("model", item.get("category", ""))).strip_edges()

		if seen_skus.has(sku):
			_add_diagnostic(result, "Duplicado", sku, "SKU repetido no banco.", "Alto")
		seen_skus[sku] = true

		if imei != "":
			if seen_imeis.has(imei):
				_add_diagnostic(result, "Duplicado", sku, "IMEI repetido: %s" % imei, "Alto")
			seen_imeis[imei] = true

		if status_key == "instalado" and plate == "":
			_add_diagnostic(result, "Instalado sem placa", sku, "Equipamento instalado precisa ter placa.", "Alto")
		if status_key == "estoque" and plate != "" and not _plate_is_internal_stock_marker(plate):
			_add_diagnostic(result, "Estoque com placa", sku, "Equipamento em estoque ainda tem placa preenchida.", "Medio")
		if status_key == "reserva" and sku == "":
			_add_diagnostic(result, "Reserva incompleta", sku, "Reserva sem identificacao.", "Alto")
		if operator_name == "":
			_add_diagnostic(result, "Operadora vazia", sku, "Informe a operadora.", "Medio")
		if model == "" or model == "Geral":
			_add_diagnostic(result, "Tipo vazio", sku, "Informe o tipo/modelo.", "Medio")
		if status_key == "desconhecido":
			_add_diagnostic(result, "Status estranho", sku, "Status nao reconhecido: %s" % str(item.get("tracker_status", "")), "Alto")

	return result


func get_report_rows(report_type: String, date_query: String = "") -> Array[Dictionary]:
	if not _loaded:
		load_db()

	var key := report_type.strip_edges().to_lower()
	var rows: Array[Dictionary] = []
	match key:
		"baixas":
			for movement in _db.get("movements", []):
				if typeof(movement) != TYPE_DICTIONARY:
					continue
				var type_key := str(movement.get("type", "")).to_lower()
				if type_key != "baixa" and type_key != "saida":
					continue
				if date_query != "" and not str(movement.get("timestamp", "")).begins_with(date_query):
					continue
				rows.append({
					"data": str(movement.get("timestamp", "")),
					"numero": str(movement.get("sku", "")),
					"placa": _plate_from_reason(str(movement.get("reason", ""))),
					"tipo": str(movement.get("type", "")),
					"operadora": "",
					"status": "Baixa",
				})
		_:
			for product in get_products("", "all", false):
				if key == "estoque" and _status_key(product) != "estoque":
					continue
				if key == "operadora" and str(product.get("operator", "")).strip_edges() == "":
					continue
				if key == "mensal" and date_query != "" and not _product_matches_date(product, date_query):
					continue
				rows.append({
					"data": str(product.get("updated_at", product.get("created_at", ""))),
					"numero": str(product.get("imei", product.get("sku", ""))),
					"placa": str(product.get("plate", "")),
					"tipo": str(product.get("model", product.get("category", ""))),
					"operadora": str(product.get("operator", "")),
					"status": str(product.get("tracker_status", "")),
				})

	return rows


func install_tracker(sku: String, plate: String) -> bool:
	if not _can_mutate():
		return false
	if not _loaded:
		load_db()

	var index := _find_product_index(sku)
	if index < 0:
		return false

	var clean_plate := plate.strip_edges().to_upper()
	if clean_plate == "":
		return false

	var products: Array = _db.get("products", [])
	var previous_products := products.duplicate(true)
	var product := _normalize_product(products[index])
	if _status_key(product) == "instalado" and str(product.get("vehicle_plate", product.get("plate", ""))).strip_edges().to_upper() == clean_plate:
		return true
	var now := _now_string()
	var identification_plate := str(product.get("identification_plate", "")).strip_edges().to_upper()
	if identification_plate == "" and _status_key(product) != "instalado":
		identification_plate = str(product.get("plate", "")).strip_edges().to_upper()

	product["identification_plate"] = identification_plate
	product["vehicle_plate"] = clean_plate
	product["plate"] = clean_plate
	product["tracker_status"] = "Instalado"
	product["status"] = "Instalado"
	product["location"] = "Instalado"
	product["stock"] = 0
	product["active"] = true
	product["remote_registration_status"] = "local_database_pending"
	product["installed_at"] = now
	product["discharged_at"] = now
	product["updated_at"] = now
	product["last_movement_at"] = now

	products[index] = product
	_db["products"] = products

	var movement := {
		"id": "%s-baixa-%s" % [product.get("sku", ""), Time.get_unix_time_from_system()],
		"sku": product.get("sku", ""),
		"product_name": product.get("name", ""),
		"type": "baixa",
		"quantity": 1.0,
		"delta": -1.0,
		"reason": ("Baixa da identificacao %s para instalacao no veiculo %s" % [identification_plate, clean_plate]) if identification_plate != "" else ("Baixa para instalacao no veiculo %s" % clean_plate),
		"identification_plate": identification_plate,
		"vehicle_plate": clean_plate,
		"timestamp": now,
		"stock_after": 0,
	}
	var movements: Array = _db.get("movements", [])
	var previous_movements := movements.duplicate(true)
	movements.append(movement)
	_db["movements"] = movements

	if not _persist_product_with_movement_incremental(product, movement):
		_db["products"] = previous_products
		_db["movements"] = previous_movements
		return false
	return true


func delete_product(sku: String) -> bool:
	if not _can_mutate():
		return false
	if not _loaded:
		load_db()

	var index := _find_product_index(sku)
	if index < 0:
		return false

	var products: Array = _db.get("products", [])
	var previous_products := products.duplicate(true)
	products.remove_at(index)
	_db["products"] = products
	var deleted := _sqlite.execute("delete_device", _db_path, {"branch": _branch_id, "sku": _normalize_sku(sku)})
	if not bool(deleted.get("ok", false)) or int(deleted.get("deleted", 0)) != 1:
		_db["products"] = previous_products
		return false
	return true


func apply_movement(sku: String, quantity: float, movement_type: String, reason: String) -> Dictionary:
	if not _can_mutate():
		return {}
	if not _loaded:
		load_db()

	var index := _find_product_index(sku)
	if index < 0:
		return {}

	var products: Array = _db.get("products", [])
	var product := _normalize_product(products[index])
	if product.is_empty():
		return {}

	var normalized_type := movement_type.strip_edges().to_lower()
	var delta := quantity
	if normalized_type == "saida" or normalized_type == "baixa":
		delta = -absf(quantity)
	elif normalized_type == "entrada":
		delta = absf(quantity)

	var next_stock := int(round(float(product.get("stock", 0)) + delta))
	product["stock"] = maxi(next_stock, 0)
	product["updated_at"] = _now_string()
	product["last_movement_at"] = _now_string()
	products[index] = product
	_db["products"] = products

	var movement := {
		"id": "%s-%s" % [product.get("sku", ""), Time.get_unix_time_from_system()],
		"sku": product.get("sku", ""),
		"product_name": product.get("name", ""),
		"type": normalized_type,
		"quantity": quantity,
		"delta": delta,
		"reason": reason.strip_edges(),
		"timestamp": _now_string(),
		"stock_after": product.get("stock", 0)
	}

	var movements: Array = _db.get("movements", [])
	movements.append(movement)
	_db["movements"] = movements
	save_db()
	return movement


func get_recent_movements(limit: int = 8) -> Array[Dictionary]:
	if not _loaded:
		load_db()

	var movements: Array = _db.get("movements", [])
	var result: Array[Dictionary] = []

	for i in range(movements.size() - 1, -1, -1):
		var movement = movements[i]
		if typeof(movement) != TYPE_DICTIONARY:
			continue
		result.append(movement)
		if result.size() >= limit:
			break

	return result


func get_stats() -> Dictionary:
	if not _loaded:
		load_db()

	var products: Array = _db.get("products", [])
	var movements: Array = _db.get("movements", [])
	var total_units := 0
	var low_stock := 0
	var stock_value := 0.0

	for product in products:
		if typeof(product) != TYPE_DICTIONARY:
			continue

		var item := _normalize_product(product)
		total_units += int(item.get("stock", 0))
		if _is_low_stock(item):
			low_stock += 1
		stock_value += float(item.get("stock", 0)) * float(item.get("cost", 0.0))

	return {
		"total_skus": products.size(),
		"total_units": total_units,
		"low_stock": low_stock,
		"movements": movements.size(),
		"today_movements": _count_today_movements(movements),
		"stock_value": stock_value,
	}


func _count_today_movements(movements: Array) -> int:
	var today := _today_string()
	var total := 0

	for movement in movements:
		if typeof(movement) != TYPE_DICTIONARY:
			continue
		if str(movement.get("timestamp", "")).begins_with(today):
			total += 1

	return total


func _empty_db() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"products": [],
		"movements": [],
		"system_logs": [],
		"maintenances": [],
		"runtime": {},
	}


func _ensure_db_shape(value: Dictionary) -> Dictionary:
	var db := _empty_db()
	if typeof(value) != TYPE_DICTIONARY:
		return db

	db["schema"] = int(value.get("schema", SCHEMA_VERSION))
	db["products"] = _normalize_product_array(value.get("products", []))
	db["movements"] = _normalize_movement_array(value.get("movements", []))
	db["system_logs"] = _normalize_system_log_array(value.get("system_logs", []))
	db["maintenances"] = _normalize_maintenance_array(value.get("maintenances", []))
	db["runtime"] = (value.get("runtime", {}) as Dictionary).duplicate(true) \
		if typeof(value.get("runtime", {})) == TYPE_DICTIONARY else {}
	return db


func _normalize_product_array(value) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result

	for entry in value:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var product := _normalize_product(entry)
		if not product.is_empty():
			result.append(product)

	return result


func _normalize_maintenance_array(value) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result

	for entry in value:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item := _normalize_maintenance(entry)
		if not item.is_empty():
			result.append(item)

	return result


func _normalize_maintenance(value: Dictionary) -> Dictionary:
	var client := str(value.get("client", value.get("name", ""))).strip_edges()
	var plate := str(value.get("plate", "")).strip_edges().to_upper()
	var serial := str(value.get("serial", value.get("sku", ""))).strip_edges()
	if client == "" or plate == "" or serial == "":
		return {}

	return {
		"id": str(value.get("id", "")).strip_edges(),
		"client": client,
		"plate": plate,
		"serial": serial,
		"provider": str(value.get("provider", "")).strip_edges(),
		"phone": str(value.get("phone", "")).strip_edges(),
		"source_date": str(value.get("source_date", "")).strip_edges(),
		"scheduled_date": str(value.get("scheduled_date", "")).strip_edges(),
		"scheduled_time": str(value.get("scheduled_time", "")).strip_edges(),
		"note": str(value.get("note", value.get("notes", ""))).strip_edges(),
		"status": str(value.get("status", "pendente")).strip_edges().to_lower(),
		"completed_at": str(value.get("completed_at", "")).strip_edges(),
		"created_at": str(value.get("created_at", "")).strip_edges(),
		"updated_at": str(value.get("updated_at", "")).strip_edges(),
	}


func _normalize_movement_array(value) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result

	for entry in value:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		result.append({
			"id": str(entry.get("id", "")),
			"sku": str(entry.get("sku", "")),
			"product_name": str(entry.get("product_name", "")),
			"type": str(entry.get("type", "")),
			"quantity": float(entry.get("quantity", 0)),
			"delta": float(entry.get("delta", 0)),
			"reason": str(entry.get("reason", "")),
			"identification_plate": str(entry.get("identification_plate", "")),
			"vehicle_plate": str(entry.get("vehicle_plate", "")),
			"timestamp": str(entry.get("timestamp", "")),
			"stock_after": int(entry.get("stock_after", 0)),
		})

	return result


func _normalize_system_log_array(value) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result

	for entry in value:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		result.append(_normalize_system_log(entry))

	return _prune_system_logs(result)


func _prune_system_logs(logs: Array) -> Array:
	if logs.size() < MAX_SYSTEM_LOGS:
		return logs
	var overflow := logs.size() - MAX_SYSTEM_LOGS
	var batches := int(floor(float(overflow) / float(SYSTEM_LOG_PRUNE_BATCH))) + 1
	var remove_count := mini(batches * SYSTEM_LOG_PRUNE_BATCH, logs.size())
	return logs.slice(remove_count)


func _normalize_system_log(value: Dictionary) -> Dictionary:
	var event_id := str(value.get("id", "")).strip_edges()
	if event_id == "":
		event_id = "legacy-%s-%s" % [str(value.get("timestamp", "")), str(value.get("action", ""))]
	var action := str(value.get("action", "")).strip_edges()
	var details := str(value.get("details", "")).strip_edges()
	var sku := _normalize_sku(value.get("sku", ""))
	var normalized := value.duplicate(true)
	normalized["schema_version"] = int(value.get("schema_version", SYSTEM_LOG_SCHEMA_VERSION))
	normalized["id"] = event_id
	normalized["timestamp"] = str(value.get("timestamp", ""))
	normalized["action"] = action
	normalized["details"] = details
	normalized["sku"] = sku
	var metadata := _infer_system_log_metadata(action, details, sku, value, event_id)
	for key in metadata.keys():
		normalized[str(key)] = metadata[key]
	return normalized


func _infer_system_log_metadata(action: String, details: String, sku: String, provided: Dictionary, event_id: String) -> Dictionary:
	var combined := "%s %s" % [action, details]
	var joined := combined.to_lower()
	var nested: Dictionary = provided.get("metadata", {}) if typeof(provided.get("metadata", {})) == TYPE_DICTIONARY else {}
	var metadata := nested.duplicate(true)
	for key in [
		"status", "phase", "transport", "origin", "http_code", "attempt", "max_attempts",
		"latency_ms", "correlation_id", "plate", "operation", "retryable", "error_code",
		"entity", "operator", "message", "fallback_used", "confirmation_pending",
		"error_count", "checked", "stock_like", "installed", "updated", "risk_level", "risk_reasons",
		# Evento completo e mascarado do Painel SMS, usado para reconstruir o
		# historico apos reiniciar o aplicativo.
		"sms_event"
	]:
		if provided.has(key):
			metadata[str(key)] = provided.get(key)

	var status := str(metadata.get("status", "")).strip_edges().to_lower()
	if status == "":
		# Registros antigos da sincronizacao usavam "erros: 0" no texto. A
		# palavra "erro" nao pode transformar uma sincronizacao saudavel em
		# falha apenas por causa do nome do contador.
		var sync_without_errors := false
		if joined.contains("sincron"):
			var sync_error_regex := RegEx.new()
			if sync_error_regex.compile("(?i)erros?\\s*[:=]\\s*0") == OK:
				sync_without_errors = sync_error_regex.search(combined) != null
		if sync_without_errors or int(metadata.get("error_count", -1)) == 0:
			status = "completed"
		var success_signal := joined.contains("conclu") or joined.contains("sucesso") or joined.contains("confirmado") or joined.contains("salvo") or joined.contains("sincronizou") or joined.contains("recuperado") or joined.contains("atualizou")
		var failure_signal := joined.contains("falhou") or joined.contains("erro") or joined.contains("timeout") or joined.contains("nao confirmado")
		var progress_signal := joined.contains("andamento") or joined.contains("pendente") or joined.contains("consultando") or joined.contains("iniciado") or joined.contains("interrompido") or joined.contains("abrindo") or joined.contains("aguardando") or joined.contains("preparando")
		if status != "" :
			pass
		elif failure_signal or joined.contains("indisponivel"):
			status = "failed"
		elif progress_signal:
			status = "progress"
		elif success_signal:
			status = "completed"
		else:
			status = "info"
	metadata["status"] = status

	var transport := str(metadata.get("transport", "")).strip_edges().to_lower()
	var fallback_used := bool(metadata.get("fallback_used", false))
	if joined.contains("fallback") or joined.contains("portal web") or joined.contains("web como"):
		transport = "web"
		fallback_used = true
	elif transport == "":
		if joined.contains("api"):
			transport = "api"
		elif joined.contains("local_database"):
			transport = "local_database"
		else:
			transport = "local"
	metadata["transport"] = transport
	metadata["fallback_used"] = fallback_used

	var origin := str(metadata.get("origin", "")).strip_edges()
	if origin == "":
		match transport:
			"api": origin = "API Grupo RS"
			"web": origin = "Portal web"
			"local_database": origin = "Banco local SQL"
			_: origin = "Sistema local"
	metadata["origin"] = origin

	var phase := str(metadata.get("phase", "")).strip_edges().to_lower()
	if phase == "":
		if joined.contains("vincul") or joined.contains("associ"):
			phase = "vinculacao"
		elif joined.contains("modific") or joined.contains("edit") or joined.contains("alter") or joined.contains("troca"):
			phase = "modificacao"
		elif joined.contains("cadastro") or joined.contains("registr"):
			phase = "cadastro"
		elif joined.contains("localiza") or joined.contains("posicao"):
			phase = "localizacao"
		elif joined.contains("sincron"):
			phase = "sincronizacao"
		elif joined.contains("sms") or joined.contains("reset"):
			phase = "comunicacao"
		elif joined.contains("manut"):
			phase = "manutencao"
		else:
			phase = "operacao"
	metadata["phase"] = phase

	var operation := str(metadata.get("operation", "")).strip_edges().to_lower()
	if operation == "":
		operation = phase
	metadata["operation"] = operation

	var plate := str(metadata.get("plate", "")).strip_edges()
	if plate == "":
		plate = _extract_system_log_value(details, "placa")
	metadata["plate"] = plate

	var http_code := int(metadata.get("http_code", 0))
	if http_code <= 0:
		http_code = _extract_system_log_int(details, "http")
	metadata["http_code"] = http_code

	var attempt := int(metadata.get("attempt", 0))
	var max_attempts := int(metadata.get("max_attempts", 0))
	var attempt_pair := _extract_system_log_attempt(details)
	if attempt <= 0 and attempt_pair.size() > 0:
		attempt = int(attempt_pair[0])
	if max_attempts <= 0 and attempt_pair.size() > 1:
		max_attempts = int(attempt_pair[1])
	metadata["attempt"] = attempt
	metadata["max_attempts"] = max_attempts

	var latency_ms := int(metadata.get("latency_ms", 0))
	if latency_ms <= 0:
		latency_ms = _extract_system_log_latency_ms(details)
	metadata["latency_ms"] = latency_ms

	var correlation_id := str(metadata.get("correlation_id", "")).strip_edges()
	if correlation_id == "":
		correlation_id = event_id.replace("log-", "evt-")
	metadata["correlation_id"] = correlation_id
	metadata["entity"] = str(metadata.get("entity", "equipamento")).strip_edges()
	metadata["operator"] = str(metadata.get("operator", "")).strip_edges()
	metadata["error_code"] = str(metadata.get("error_code", "")).strip_edges()
	metadata["retryable"] = bool(metadata.get("retryable", status == "failed" and (http_code == 0 or http_code >= 500)))
	metadata["message"] = str(metadata.get("message", details)).strip_edges()

	# Classifica automaticamente o risco de cada operacao remota para que
	# confirmacao pendente, fallback e conflitos nao fiquem escondidos no log.
	var remote_context := transport in ["api", "web"] or phase in ["cadastro", "modificacao", "vinculacao"]
	var risk_level := str(metadata.get("risk_level", "")).strip_edges().to_lower()
	var risk_reasons: Array[String] = []
	var provided_reasons = metadata.get("risk_reasons", [])
	if typeof(provided_reasons) == TYPE_ARRAY:
		for reason in provided_reasons:
			var clean_reason := str(reason).strip_edges()
			if clean_reason != "" and not risk_reasons.has(clean_reason):
				risk_reasons.append(clean_reason)
	var risk_text := "%s %s" % [action, details]
	var risk_text_lower := risk_text.to_lower()
	if remote_context:
		if status == "failed":
			risk_reasons.append("operacao falhou")
		if http_code >= 500:
			risk_reasons.append("erro HTTP 5xx")
		if http_code >= 400 and http_code < 500:
			risk_reasons.append("erro HTTP 4xx")
		if fallback_used or transport == "web":
			risk_reasons.append("fallback web utilizado")
		if bool(metadata.get("confirmation_pending", false)) or status == "progress":
			risk_reasons.append("confirmacao pendente")
		if risk_text_lower.contains("associad") or risk_text_lower.contains("duplic") or risk_text_lower.contains("conflit"):
			risk_reasons.append("conflito ou duplicidade de associacao")
		if risk_text_lower.contains("nao confirmou") or risk_text_lower.contains("diverg") or risk_text_lower.contains("mismatch"):
			risk_reasons.append("dados remotos divergentes")
		if phase != "sincronizacao" and http_code <= 0:
			risk_reasons.append("HTTP nao informado")
	if risk_level not in ["low", "medium", "high"]:
		if status == "failed" or http_code >= 500 or risk_text_lower.contains("associad") or risk_text_lower.contains("duplic") or risk_text_lower.contains("conflit"):
			risk_level = "high"
		elif fallback_used or bool(metadata.get("confirmation_pending", false)) or status == "progress" or (http_code >= 400 and http_code < 500) or (remote_context and phase != "sincronizacao" and http_code <= 0):
			risk_level = "medium"
		else:
			risk_level = "low"
	metadata["risk_level"] = risk_level
	metadata["risk_reasons"] = risk_reasons
	metadata["metadata"] = metadata.duplicate(true)
	return metadata


func _extract_system_log_value(details: String, key: String) -> String:
	var regex := RegEx.new()
	if regex.compile("(?i)%s\\s*[:=]\\s*([^|]+)" % key) != OK:
		return ""
	var match = regex.search(details)
	return match.get_string(1).strip_edges() if match != null else ""


func _extract_system_log_int(details: String, key: String) -> int:
	var regex := RegEx.new()
	if regex.compile("(?i)%s\\s*(?:status)?\\s*[:=]?\\s*(\\d{3})" % key) != OK:
		return 0
	var match = regex.search(details)
	return int(match.get_string(1)) if match != null else 0


func _extract_system_log_attempt(details: String) -> Array[int]:
	var regex := RegEx.new()
	if regex.compile("(?i)(?:tentativa|retry|tentativas)\\s*(\\d+)\\s*/\\s*(\\d+)") != OK:
		return []
	var match = regex.search(details)
	if match == null:
		return []
	return [int(match.get_string(1)), int(match.get_string(2))]


func _extract_system_log_latency_ms(details: String) -> int:
	var regex := RegEx.new()
	if regex.compile("(?i)(\\d+(?:[.,]\\d+)?)\\s*ms") != OK:
		return 0
	var match = regex.search(details)
	if match == null:
		return 0
	var raw := match.get_string(1).strip_edges()
	var normalized := raw.replace(",", ".")
	var dot_index := normalized.find(".")
	if dot_index > 0 and normalized.length() - dot_index - 1 == 3:
		return int(normalized.substr(0, dot_index)) * 1000 + int(normalized.substr(dot_index + 1))
	return int(round(float(normalized)))


func _normalize_product(value: Dictionary) -> Dictionary:
	var imei := _first_text(value, ["imei", "numero_serie", "iccid"])
	if imei == "":
		imei = str(value.get("sku", "")).strip_edges()

	var sku := _normalize_sku(value.get("sku", ""))
	if sku == "" or sku.begins_with("PRD-"):
		sku = _normalize_sku(imei)
	if sku == "":
		sku = "PRD-%s" % Time.get_unix_time_from_system()
	if imei == "":
		imei = sku

	var equipment_number := _first_text(value, ["equipment_number", "numero_equipamento", "numero"])
	var apn := _first_text(value, ["apn", "APN"])
	var chip_number := _first_text(value, ["chip_number", "numero_chip", "chip", "iccid"])
	var chip_phone := _first_text(value, ["chip_phone", "telefone_chip", "phone", "telefone"])
	var model := _first_text(value, ["model", "modelo", "tipo"])
	var operator_name := _first_text(value, ["operator", "operadora"])
	var plate := _first_text(value, ["plate", "placa", "placa_instalacao"])
	if model == "" and _plate_is_special_v735(plate):
		model = "V7.3.5"
	var client := _first_text(value, ["client", "cliente"])
	var tracker_status := _first_text(value, ["tracker_status", "status", "location"])
	if tracker_status == "":
		tracker_status = "Estoque"
	var tracker_status_key := _status_key_from_text(tracker_status)
	var identification_plate := _first_text(value, ["identification_plate", "original_plate", "tracker_plate", "placa_identificacao"])
	var vehicle_plate := _first_text(value, ["vehicle_plate", "installed_vehicle_plate", "placa_veiculo"])
	# Compatibilidade: uma placa de item ainda nao instalado era a identificacao
	# usada no estoque. Para itens legados ja instalados, a placa existente e
	# considerada apenas a placa do veiculo, sem inventar uma identificacao.
	if identification_plate == "" and tracker_status_key != "instalado":
		identification_plate = plate
	if vehicle_plate == "" and tracker_status_key == "instalado":
		vehicle_plate = plate
	if tracker_status_key == "instalado" and vehicle_plate != "":
		plate = vehicle_plate
	elif identification_plate != "":
		plate = identification_plate
	var remote_registration_status := str(value.get("remote_registration_status", "")).strip_edges()
	# Pacotes ST310 podem ser recebidos por uma ponte local/Banco local SQL. Eles são
	# mantidos no cadastro para que o mapa possa decodificar a telemetria sem
	# consultar a API de localização. Nenhuma coordenada é criada aqui.
	var st310_raw_packet: Variant = value.get("st310_raw_packet", value.get("st310_packet", value.get("raw_packet", "")))
	var st310_packet_at := str(value.get("st310_packet_at", value.get("packet_at", ""))).strip_edges()
	var st310_packet_received_at := str(value.get("st310_packet_received_at", "")).strip_edges()
	var st310_decoder_kind := str(value.get("st310_decoder_kind", "")).strip_edges()
	var st310_decoder_message := str(value.get("st310_decoder_message", "")).strip_edges()
	var st310_packet_hash := str(value.get("st310_packet_hash", "")).strip_edges()

	var name := str(value.get("name", "")).strip_edges()
	if name == "":
		name = equipment_number
	if name == "":
		name = plate
	if name == "":
		name = "Rastreador %s" % imei
	if equipment_number == "" and name != "" and not name.begins_with("Rastreador "):
		equipment_number = name

	var category := str(value.get("category", "")).strip_edges()
	if category == "" and model != "":
		category = model
	if category == "" and operator_name != "":
		category = operator_name
	if category == "":
		category = "Geral"
	if model == "" and category != "Geral":
		model = category
	if model == "" and _plate_is_special_v735(plate):
		model = "V7.3.5"
	if category == "Geral" and model == "V7.3.5":
		category = model

	var location := str(value.get("location", "")).strip_edges()
	if location == "":
		location = tracker_status

	var unit := str(value.get("unit", "un")).strip_edges()
	if unit == "":
		unit = "un"

	var notes := str(value.get("notes", "")).strip_edges()
	if notes == "":
		var legacy_notes := str(value.get("tipo", "")).strip_edges()
		if legacy_notes != "" and legacy_notes != model:
			notes = "Migrado do cadastro legado: %s" % legacy_notes

	var stock := int(value.get("stock", 0))
	if value.has("quantity") and not value.has("stock"):
		stock = int(value.get("quantity", 0))
	elif value.has("status") and not value.has("stock"):
		var legacy_status := _status_key_from_text(tracker_status)
		stock = 0 if ["reserva", "instalado", "inativo"].has(legacy_status) else 1

	var min_stock := int(value.get("min_stock", 0))
	var cost := float(value.get("cost", 0.0))
	var active := bool(value.get("active", _status_key_from_text(tracker_status) != "inativo"))

	return {
		"sku": sku,
		"name": name,
		"category": category,
		"location": location,
		"unit": unit,
		"stock": maxi(stock, 0),
		"min_stock": maxi(min_stock, 0),
		"cost": maxf(cost, 0.0),
		"notes": notes,
		"active": active,
		"equipment_number": equipment_number,
		"imei": imei,
		"apn": apn,
		"chip_number": chip_number,
		"chip_phone": chip_phone,
		"model": model,
		"operator": operator_name,
		"plate": plate,
		"identification_plate": identification_plate,
		"vehicle_plate": vehicle_plate,
		"client": client,
		"tracker_status": tracker_status,
		"status": tracker_status,
		"remote_registration_status": remote_registration_status,
		"st310_raw_packet": st310_raw_packet,
		"st310_packet_at": st310_packet_at,
		"st310_packet_received_at": st310_packet_received_at,
		"st310_decoder_kind": st310_decoder_kind,
		"st310_decoder_message": st310_decoder_message,
		"st310_packet_hash": st310_packet_hash,
		"created_at": str(value.get("created_at", "")),
		"updated_at": str(value.get("updated_at", "")),
		"last_movement_at": str(value.get("last_movement_at", "")),
		"installed_at": str(value.get("installed_at", "")),
		"discharged_at": str(value.get("discharged_at", "")),
	}


func _migrate_legacy_db(legacy: Array) -> Dictionary:
	var db := _empty_db()
	var now := _now_string()

	for entry in legacy:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var item := _normalize_product({
			"sku": str(entry.get("iccid", "")),
			"imei": str(entry.get("iccid", "")),
			"chip_number": str(entry.get("iccid", "")),
			"name": str(entry.get("placa", "")).strip_edges(),
			"plate": str(entry.get("placa", "")).strip_edges(),
			"model": str(entry.get("tipo", "")).strip_edges(),
			"operator": str(entry.get("operadora", "")).strip_edges(),
			"tracker_status": str(entry.get("status", "")).strip_edges(),
			"category": str(entry.get("operadora", "")).strip_edges(),
			"location": str(entry.get("status", "")).strip_edges(),
			"unit": "un",
			"stock": 0 if str(entry.get("status", "")).strip_edges().to_lower() == "instalado" else 1,
			"min_stock": 0,
			"cost": 0,
			"notes": "Migrado do cadastro legado",
			"created_at": str(entry.get("data", now)),
			"updated_at": now,
			"last_movement_at": str(entry.get("data", now)),
		})

		if not item.is_empty():
			db["products"].append(item)
			db["movements"].append({
				"id": "%s-%s" % [item.get("sku", ""), Time.get_unix_time_from_system()],
				"sku": item.get("sku", ""),
				"product_name": item.get("name", ""),
				"type": "migracao",
				"quantity": float(item.get("stock", 0)),
				"delta": float(item.get("stock", 0)),
				"reason": "Importado do cadastro legado",
				"timestamp": now,
				"stock_after": item.get("stock", 0),
			})

	return db


func _read_db_file(path: String) -> Dictionary:
	var parsed := _read_json_dictionary(path)
	if parsed.is_empty():
		return _empty_db()

	return parsed


func _read_json_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}

	return parsed


func _is_valid_db_backup(value: Dictionary) -> bool:
	if value.is_empty():
		return false
	return value.has("products") or value.has("movements") or value.has("system_logs") \
		or value.has("maintenances") or value.has("runtime")


func _replace_file_atomically(temp_path: String, target_path: String, backup_path: String) -> bool:
	var temp_global := _global_path(temp_path)
	var target_global := _global_path(target_path)
	var backup_global := _global_path(backup_path)

	if FileAccess.file_exists(backup_global):
		DirAccess.remove_absolute(backup_global)

	if FileAccess.file_exists(target_global):
		var backup_error := DirAccess.rename_absolute(target_global, backup_global)
		if backup_error != OK:
			DirAccess.remove_absolute(temp_global)
			return false

	var replace_error := DirAccess.rename_absolute(temp_global, target_global)
	if replace_error != OK:
		if FileAccess.file_exists(backup_global):
			DirAccess.rename_absolute(backup_global, target_global)
		DirAccess.remove_absolute(temp_global)
		return false

	if FileAccess.file_exists(backup_global):
		DirAccess.remove_absolute(backup_global)
	return true


func _global_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


func _queue_pending_sync_snapshot(raw_snapshot: Dictionary) -> bool:
	if _pending_sync_path.strip_edges() == "":
		return false

	var snapshot := _ensure_db_shape(raw_snapshot.duplicate(true))
	var snapshot_hash := JSON.stringify(snapshot).sha256_text()
	if not _pending_sync_queue.is_empty():
		var last_entry: Dictionary = _pending_sync_queue.back()
		if str(last_entry.get("hash", "")) == snapshot_hash:
			return true

	if _pending_sync_queue.size() >= MAX_PENDING_SYNC_RECORDS:
		return false

	var previous_queue := _pending_sync_queue.duplicate(true)
	_pending_sync_queue.append({
		"id": "pending-%s" % Time.get_ticks_msec(),
		"created_at": Time.get_datetime_string_from_system(false, true),
		"hash": snapshot_hash,
		"snapshot": snapshot,
	})
	if _write_pending_sync_queue():
		return true
	_pending_sync_queue = previous_queue
	return false


func _read_pending_sync_queue() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _pending_sync_path.strip_edges() == "" or not FileAccess.file_exists(_pending_sync_path):
		return result

	var raw := _read_json_dictionary(_pending_sync_path)
	var entries: Variant = raw.get("entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return result

	for entry_value in entries:
		if result.size() >= MAX_PENDING_SYNC_RECORDS:
			break
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry := entry_value as Dictionary
		var snapshot: Variant = entry.get("snapshot", {})
		if typeof(snapshot) != TYPE_DICTIONARY:
			continue
		result.append({
			"id": str(entry.get("id", "pending-%d" % result.size())),
			"created_at": str(entry.get("created_at", "")),
			"hash": str(entry.get("hash", JSON.stringify(snapshot).sha256_text())),
			"snapshot": _ensure_db_shape(snapshot as Dictionary),
		})
	return result


func _write_pending_sync_queue() -> bool:
	var temp_path := "%s.tmp" % _pending_sync_path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"schema": 1,
		"entries": _pending_sync_queue,
	}, "\t"))
	file = null
	return _replace_file_atomically(temp_path, _pending_sync_path, "%s.bak" % _pending_sync_path)


func _can_mutate() -> bool:
	return true


func _find_product_index_by_st310_serial(products: Array, serial: String) -> int:
	var target := _st310_digits_only(serial)
	if target == "":
		return -1
	for index in range(products.size()):
		var raw_product: Variant = products[index]
		if typeof(raw_product) != TYPE_DICTIONARY:
			continue
		var product := _normalize_product(raw_product as Dictionary)
		for key in ["imei", "equipment_number", "sku"]:
			if _st310_digits_only(str(product.get(key, ""))) == target:
				return index
	return -1


func _st310_serial_from_fields(fields: Dictionary) -> String:
	for key in ["serial", "id", "ID", "imei", "IMEI", "numeroSerie", "numero_serie"]:
		var candidate := _st310_digits_only(str(fields.get(key, "")))
		if candidate.length() >= 6 and candidate.length() <= 20:
			return candidate
	return ""


func _st310_digits_only(value: String) -> String:
	var result := ""
	for index in range(value.length()):
		var char := value.substr(index, 1)
		if char >= "0" and char <= "9":
			result += char
	return result


func _st310_raw_text(value: Variant) -> String:
	if typeof(value) == TYPE_STRING:
		return str(value).strip_edges()
	if typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
		return JSON.stringify(value)
	return ""


func _st310_value_hash(value: String) -> String:
	var hash_value := 2166136261
	for index in range(value.length()):
		hash_value = int((hash_value ^ value.unicode_at(index)) * 16777619) & 0x7fffffff
	return "%08x" % hash_value


func _remove_known_file(path: String) -> void:
	var clean_path := path.strip_edges()
	if clean_path == "":
		return
	var absolute_path := _global_path(clean_path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


func _purge_json_files_in_dir(dir_path: String) -> void:
	var clean_dir := dir_path.strip_edges()
	if clean_dir == "" or not DirAccess.dir_exists_absolute(clean_dir):
		return
	var dir := DirAccess.open(clean_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "json":
			_remove_known_file(clean_dir.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


func _latest_backup_file(dir_path: String) -> String:
	var clean_dir := dir_path.strip_edges()
	if clean_dir == "" or not DirAccess.dir_exists_absolute(clean_dir):
		return ""

	var dir := DirAccess.open(clean_dir)
	if dir == null:
		return ""

	var latest_path := ""
	var latest_modified := 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "json":
			var candidate := clean_dir.path_join(file_name)
			var modified := FileAccess.get_modified_time(candidate)
			if modified > latest_modified:
				latest_modified = modified
				latest_path = candidate
		file_name = dir.get_next()
	dir.list_dir_end()
	return latest_path


func _read_legacy_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		return []

	return parsed


func _find_product_index(sku: String) -> int:
	var normalized_sku := _normalize_sku(sku)
	if normalized_sku == "":
		return -1

	var products: Array = _db.get("products", [])
	for index in range(products.size()):
		var product = products[index]
		if typeof(product) != TYPE_DICTIONARY:
			continue
		var item := _normalize_product(product)
		if item.get("sku", "") == normalized_sku:
			return index

	return -1


func _find_maintenance_index(serial: String, plate: String) -> int:
	var clean_serial := serial.strip_edges()
	var clean_plate := plate.strip_edges().to_upper()
	var maintenances: Array = _db.get("maintenances", [])
	for index in range(maintenances.size()):
		var item := _normalize_maintenance(maintenances[index])
		if item.is_empty():
			continue
		if str(item.get("serial", "")).strip_edges() == clean_serial and str(item.get("plate", "")).strip_edges().to_upper() == clean_plate:
			return index

	return -1


func _find_maintenance_index_by_id(id: String) -> int:
	var clean_id := id.strip_edges()
	if clean_id == "":
		return -1

	var maintenances: Array = _db.get("maintenances", [])
	for index in range(maintenances.size()):
		var item := _normalize_maintenance(maintenances[index])
		if str(item.get("id", "")).strip_edges() == clean_id:
			return index

	return -1


func _new_maintenance_id(index: int) -> String:
	return "mnt-%s-%s" % [Time.get_unix_time_from_system(), index]


func _normalize_datetime(value: String) -> String:
	if value == "":
		return ""

	var v := value.to_lower().strip_edges()

	# ISO fix
	v = v.replace("t", " ")

	# remove separadores
	v = v.replace("-", "")
	v = v.replace(":", "")
	v = v.replace(" ", "")

	return v


func _matches_query(product: Dictionary, query: String) -> bool:
	var q := _normalize_search_text(query)
	if q == "":
		return true

	var q_without_zeroes := _trim_leading_zeroes(q)
	var fields := [
		product.get("sku", ""),
		product.get("name", ""),
		product.get("category", ""),
		product.get("location", ""),
		product.get("unit", ""),
		product.get("notes", ""),
		product.get("equipment_number", ""),
		product.get("imei", ""),
		product.get("chip_number", ""),
		product.get("chip_phone", ""),
		product.get("plate", ""),
		product.get("identification_plate", ""),
		product.get("vehicle_plate", ""),
		product.get("client", ""),
		product.get("model", ""),
		product.get("operator", ""),
		product.get("tracker_status", ""),
		product.get("status", ""),
		_normalize_datetime(str(product.get("created_at", ""))),
		_normalize_datetime(str(product.get("updated_at", ""))),
		_normalize_datetime(str(product.get("installed_at", ""))),
		_normalize_datetime(str(product.get("discharged_at", ""))),
		_normalize_datetime(str(product.get("last_movement_at", ""))),
	]

	for field in fields:
		var normalized_field := _normalize_search_text(str(field))
		if normalized_field.contains(q):
			return true
		if q_without_zeroes != q and _trim_leading_zeroes(normalized_field).contains(q_without_zeroes):
			return true

	return false


func _matches_maintenance_query(item: Dictionary, query: String) -> bool:
	var q := _normalize_search_text(query)
	if q == "":
		return true

	var fields := [
		item.get("client", ""),
		item.get("plate", ""),
		item.get("serial", ""),
		item.get("scheduled_date", ""),
		item.get("scheduled_time", ""),
		item.get("note", ""),
	]
	for field in fields:
		var text := _normalize_search_text(str(field))
		if text.contains(q):
			return true

	return false


func _normalize_search_text(value) -> String:
	return str(value).strip_edges().to_lower() \
		.replace(" ", "") \
		.replace("/", "") \
		.replace("-", "") \
		.replace("_", "") \
		.replace(".", "") \
		.replace(":", "") \
		.replace("(", "") \
		.replace(")", "") \
		.replace("\n", "") \
		.replace("\t", "") \
		.replace("á", "a") \
		.replace("à", "a") \
		.replace("ã", "a") \
		.replace("â", "a") \
		.replace("é", "e") \
		.replace("ê", "e") \
		.replace("í", "i") \
		.replace("ó", "o") \
		.replace("õ", "o") \
		.replace("ô", "o") \
		.replace("ú", "u") \
		.replace("ç", "c") \
		.replace("á", "a") \
		.replace("à", "a") \
		.replace("ã", "a") \
		.replace("â", "a") \
		.replace("é", "e") \
		.replace("ê", "e") \
		.replace("í", "i") \
		.replace("ó", "o") \
		.replace("õ", "o") \
		.replace("ô", "o") \
		.replace("ú", "u") \
		.replace("ç", "c") \
		.replace("ã¡", "a") \
		.replace("ã ", "a") \
		.replace("ã£", "a") \
		.replace("ã¢", "a") \
		.replace("ã©", "e") \
		.replace("ãª", "e") \
		.replace("ã­", "i") \
		.replace("ã³", "o") \
		.replace("ãµ", "o") \
		.replace("ã´", "o") \
		.replace("ãº", "u") \
		.replace("ã§", "c")


func _trim_leading_zeroes(value: String) -> String:
	var index := 0
	while index < value.length() - 1 and value.substr(index, 1) == "0":
		index += 1
	return value.substr(index)


func _plate_is_special_v735(plate: String) -> bool:
	return _normalize_search_text(plate).begins_with("xrs")


func _is_low_stock(product: Dictionary) -> bool:
	var min_stock := int(product.get("min_stock", 0))
	if min_stock <= 0:
		return false
	return int(product.get("stock", 0)) <= min_stock


func _normalize_sku(value) -> String:
	return str(value).strip_edges().to_upper()


func _first_text(value: Dictionary, keys: Array) -> String:
	for key in keys:
		var text := str(value.get(str(key), "")).strip_edges()
		if text != "":
			return text
	return ""


func _status_key(product: Dictionary) -> String:
	return _status_key_from_text(str(product.get("tracker_status", product.get("status", ""))))


func _status_key_from_text(value: String) -> String:
	var text := value.strip_edges().to_lower()
	text = text.replace("ç", "c") \
		.replace("ã", "a") \
		.replace("á", "a") \
		.replace("à", "a") \
		.replace("â", "a") \
		.replace("é", "e") \
		.replace("ê", "e") \
		.replace("í", "i") \
		.replace("ó", "o") \
		.replace("õ", "o") \
		.replace("ô", "o") \
		.replace("ú", "u")

	text = text.replace("ç", "c") \
		.replace("ã", "a") \
		.replace("á", "a") \
		.replace("â", "a") \
		.replace("é", "e") \
		.replace("í", "i") \
		.replace("ó", "o") \
		.replace("õ", "o")

	if text == "em estoque" or text == "estoque":
		return "estoque"
	if text == "em reserva" or text == "reserva":
		return "reserva"
	if text == "instalado":
		return "instalado"
	if text == "manutencao" or text == "manutenção":
		return "manutencao"
	if text == "inativo":
		return "inativo"

	return "desconhecido"


func _is_linked(product: Dictionary) -> bool:
	return str(product.get("plate", "")).strip_edges() != "" \
		or str(product.get("client", "")).strip_edges() != ""


func _add_history_event(events: Array[Dictionary], timestamp: String, action: String, details: String, sku: String) -> void:
	var clean_timestamp := timestamp.strip_edges()
	if clean_timestamp == "":
		return
	events.append({
		"timestamp": clean_timestamp,
		"action": action.strip_edges(),
		"details": details.strip_edges(),
		"sku": _normalize_sku(sku),
	})


func _add_diagnostic(result: Array[Dictionary], kind: String, sku: String, details: String, severity: String) -> void:
	result.append({
		"type": kind,
		"sku": _normalize_sku(sku),
		"details": details,
		"severity": severity,
	})


func _plate_is_internal_stock_marker(value: String) -> bool:
	var key := _normalize_search_text(value).to_upper()
	if key == "":
		return false
	for prefix in INTERNAL_STOCK_PLATE_PREFIXES:
		if key.begins_with(str(prefix)):
			return true
	return false


func _product_matches_date(product: Dictionary, date_query: String) -> bool:
	var query := date_query.strip_edges()
	if query == "":
		return true
	return str(product.get("created_at", "")).begins_with(query) \
		or str(product.get("updated_at", "")).begins_with(query) \
		or str(product.get("installed_at", "")).begins_with(query) \
		or str(product.get("discharged_at", "")).begins_with(query) \
		or str(product.get("last_movement_at", "")).begins_with(query)


func _plate_from_reason(reason: String) -> String:
	var regex := RegEx.new()
	if regex.compile("placa\\s+([A-Z0-9\\- ]+)") != OK:
		return ""
	var match := regex.search(reason.to_upper())
	if match == null:
		return ""
	return match.get_string(1).strip_edges()


func _today_string() -> String:
	return Time.get_date_string_from_system()


func _now_string() -> String:
	return Time.get_datetime_string_from_system()


func _file_stamp() -> String:
	return _now_string().replace(":", "").replace("-", "").replace("T", "_")
