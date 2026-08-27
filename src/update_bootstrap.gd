extends Node

const APP_ID := "grupo-rs-central"
const STATE_PATH := "user://updates/update_state.json"
const UPDATE_LOG_PATH := "user://updates/update_log.json"
const UPDATE_REPORT_PATH := "user://updates/update_report.json"
const UPDATE_DIR := "user://updates"
const DOWNLOAD_CHUNK_SIZE := 1024 * 1024
const UPDATE_LOG_SCHEMA_VERSION := 1

var _state_path := STATE_PATH
var _update_log_path := UPDATE_LOG_PATH
var _update_report_path := UPDATE_REPORT_PATH
var _update_dir := UPDATE_DIR
var _state: Dictionary = {}
var _update_log: Array = []
var _available_manifest: Dictionary = {}
var _available_manifest_source := ""
var _boot_status: Dictionary = {
	"loaded": false,
	"version": "",
	"message": "Executavel base carregado.",
}


func _init() -> void:
	if "--update-test-mode" in OS.get_cmdline_user_args():
		_state_path = "user://codex_update_test/update_state.json"
		_update_log_path = "user://codex_update_test/update_log.json"
		_update_report_path = "user://codex_update_test/update_report.json"
		_update_dir = "user://codex_update_test/packages"
	_prepare_directories()
	_state = _read_json(_state_path)
	_update_log = _read_json_array(_update_log_path)
	_load_selected_package()


func _prepare_directories() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_update_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_state_path.get_base_dir()))


func _load_selected_package() -> void:
	var pending: Dictionary = _dictionary(_state.get("pending", {}))
	if not pending.is_empty() and bool(pending.get("boot_started", false)):
		_state["failed"] = pending
		_state.erase("pending")
		_state["last_error"] = "A atualizacao %s nao confirmou a inicializacao e foi revertida." % str(pending.get("version", ""))
		record_update_event("boot_load", "failed", str(_state["last_error"]), {
			"failed_version": str(pending.get("version", "")),
			"phase": "boot_confirmation",
		})
		# Quando a base e apenas o bootstrap, remover o pending sem reativar o
		# pacote anterior deixa a aplicacao sem a cena principal e produz uma
		# janela vazia. O ultimo pacote confirmado deve voltar a ser o ativo.
		var previous: Dictionary = _dictionary(_state.get("previous", {}))
		if not previous.is_empty():
			_state["active"] = previous
			_state.erase("previous")
		_write_state()
		pending = {}

	var selected: Dictionary = pending if not pending.is_empty() else _dictionary(_state.get("active", {}))
	var base_version := _base_version()
	# O executavel-base e a autoridade quando ja e igual ou mais novo que
	# qualquer pacote persistido. Isso evita que um estado antigo (por exemplo,
	# 4.0.85) reapareca depois de o executavel ter sido atualizado para 4.0.87.
	if not selected.is_empty():
		var selected_version := str(selected.get("version", "")).strip_edges()
		if selected_version != "" and compare_versions(selected_version, base_version) <= 0:
			if not pending.is_empty():
				_state.erase("pending")
			else:
				_state.erase("active")
			_state["last_error"] = "Pacote %s ignorado: executavel-base %s ja e igual ou mais novo." % [selected_version, base_version]
			record_update_event("boot_load", "ignored", str(_state["last_error"]), {
				"selected_version": selected_version,
				"base_version": base_version,
			})
			_write_state()
			selected = {}
			pending = {}
	if selected.is_empty():
		_boot_status["version"] = base_version
		record_update_event("boot_load", "info", "Executavel-base carregado.", {
			"base_version": base_version,
		})
		return

	var validation := _validate_local_package(selected)
	if not bool(validation.get("ok", false)):
		_handle_invalid_selected_package(selected, str(validation.get("message", "Pacote invalido.")), not pending.is_empty())
		return

	var package_path := str(selected.get("path", ""))
	if not ProjectSettings.load_resource_pack(package_path, true):
		_handle_invalid_selected_package(selected, "O Godot recusou o pacote de atualizacao.", not pending.is_empty())
		return

	_boot_status = {
		"loaded": true,
		"version": str(selected.get("version", _base_version())),
		"message": "Pacote %s carregado." % str(selected.get("version", "")),
		"path": package_path,
		"pending": not pending.is_empty(),
	}
	if not pending.is_empty():
		pending["boot_started"] = true
		pending["boot_started_at"] = Time.get_datetime_string_from_system(false, true)
		_state["pending"] = pending
		_write_state()
	record_update_event("boot_load", "loaded", str(_boot_status.get("message", "")), {
		"selected_version": str(selected.get("version", "")),
		"package_path": package_path,
		"pending": not pending.is_empty(),
	})


func _handle_invalid_selected_package(selected: Dictionary, message: String, was_pending: bool) -> void:
	_state["last_error"] = message
	_state["failed"] = selected
	if was_pending:
		_state.erase("pending")
	else:
		_state.erase("active")
	_write_state()
	record_update_event("boot_load", "failed", message, {
		"failed_version": str(selected.get("version", "")),
		"package_path": str(selected.get("path", "")),
		"was_pending": was_pending,
	})
	_boot_status = {
		"loaded": false,
		"version": _base_version(),
		"message": "%s O executavel base foi preservado." % message,
		"error": true,
	}


func mark_boot_success() -> Dictionary:
	var pending: Dictionary = _dictionary(_state.get("pending", {}))
	if pending.is_empty():
		_state["last_boot_ok_at"] = Time.get_datetime_string_from_system(false, true)
		_write_state()
		record_update_event("boot_confirm", "ok", "Inicializacao confirmada.", {
			"version": current_version(),
		})
		return {"ok": true, "message": "Inicializacao confirmada.", "version": current_version()}

	var active: Dictionary = _dictionary(_state.get("active", {}))
	if not active.is_empty():
		_state["previous"] = active
	pending.erase("boot_started")
	pending.erase("boot_started_at")
	pending["activated_at"] = Time.get_datetime_string_from_system(false, true)
	_state["active"] = pending
	_state.erase("pending")
	_state.erase("last_error")
	_state["last_boot_ok_at"] = Time.get_datetime_string_from_system(false, true)
	_write_state()
	_boot_status["pending"] = false
	record_update_event("boot_confirm", "ok", "Atualizacao confirmada.", {
		"version": str(pending.get("version", "")),
		"activated_at": str(pending.get("activated_at", "")),
	})
	return {
		"ok": true,
		"message": "Atualizacao %s confirmada." % str(pending.get("version", "")),
		"version": str(pending.get("version", "")),
	}


func boot_status() -> Dictionary:
	return _boot_status.duplicate(true)


func current_version() -> String:
	var pending: Dictionary = _dictionary(_state.get("pending", {}))
	if bool(_boot_status.get("loaded", false)) and not pending.is_empty():
		var pending_version := str(pending.get("version", _base_version()))
		return pending_version if compare_versions(pending_version, _base_version()) > 0 else _base_version()
	var active: Dictionary = _dictionary(_state.get("active", {}))
	if not active.is_empty() and bool(_boot_status.get("loaded", false)):
		var active_version := str(active.get("version", _base_version()))
		return active_version if compare_versions(active_version, _base_version()) > 0 else _base_version()
	return _base_version()


func base_version() -> String:
	return _base_version()


func default_manifest_source() -> String:
	return OS.get_executable_path().get_base_dir().path_join("updates").path_join("manifest.json")


func update_directory() -> String:
	return ProjectSettings.globalize_path(_update_dir)


func state_snapshot() -> Dictionary:
	return _state.duplicate(true)


func reset_test_state() -> bool:
	if "--update-test-mode" not in OS.get_cmdline_user_args():
		return false
	_remove_directory_contents(ProjectSettings.globalize_path("user://codex_update_test"))
	_state = {}
	_update_log = []
	_available_manifest.clear()
	_available_manifest_source = ""
	_prepare_directories()
	return true


func update_log_snapshot(limit: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(_update_log.size() - 1, -1, -1):
		var entry: Variant = _update_log[index]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		result.append((entry as Dictionary).duplicate(true))
		if limit > 0 and result.size() >= limit:
			break
	return result


func update_report_snapshot() -> Dictionary:
	var by_operation: Dictionary = {}
	var by_status: Dictionary = {}
	var actionable_failures: Array[Dictionary] = []
	for raw_event in _update_log:
		if typeof(raw_event) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = raw_event as Dictionary
		var operation := str(event.get("operation", "unknown"))
		var status := str(event.get("status", "info"))
		by_operation[operation] = int(by_operation.get(operation, 0)) + 1
		by_status[status] = int(by_status.get(status, 0)) + 1
		if status == "failed":
			actionable_failures.append(event.duplicate(true))
	return {
		"schema_version": UPDATE_LOG_SCHEMA_VERSION,
		"generated_at": Time.get_datetime_string_from_system(false, true),
		"base_version": _base_version(),
		"current_version": current_version(),
		"total_events": _update_log.size(),
		"by_operation": by_operation,
		"by_status": by_status,
		"actionable_failures": actionable_failures,
		"latest_event": update_log_snapshot(1)[0] if not _update_log.is_empty() else {},
	}


func record_update_event(operation: String, status: String = "info", message: String = "", metadata: Dictionary = {}) -> bool:
	var clean_operation := operation.strip_edges()
	if clean_operation == "":
		return false
	var clean_status := status.strip_edges()
	if clean_status == "":
		clean_status = "info"

	var event := {
		"schema_version": UPDATE_LOG_SCHEMA_VERSION,
		"id": "upd-%s-%s-%s" % [Time.get_unix_time_from_system(), Time.get_ticks_msec(), _update_log.size()],
		"timestamp": Time.get_datetime_string_from_system(false, true),
		"operation": clean_operation,
		"status": clean_status,
		"message": message.strip_edges(),
		"base_version": _base_version(),
		"current_version": current_version(),
	}
	for key in metadata.keys():
		event[str(key)] = metadata[key]

	_update_log.append(event)
	_prune_update_log()
	var log_written := _write_json(_update_log_path, {"schema_version": UPDATE_LOG_SCHEMA_VERSION, "events": _update_log})
	_write_json(_update_report_path, update_report_snapshot())
	return log_written


func available_manifest() -> Dictionary:
	return _available_manifest.duplicate(true)


func check_for_updates(manifest_source: String = "") -> Dictionary:
	var source := manifest_source.strip_edges()
	if source == "":
		source = default_manifest_source()
	var response := await _load_manifest_source(source)
	if not bool(response.get("ok", false)):
		_available_manifest.clear()
		_available_manifest_source = ""
		record_update_event("manifest_check", "failed", str(response.get("message", "Falha ao ler manifesto.")), {
			"manifest_source": source,
		})
		return response

	var manifest: Dictionary = response.get("manifest", {})
	var validation := validate_manifest(manifest)
	if not bool(validation.get("ok", false)):
		_available_manifest.clear()
		_available_manifest_source = ""
		record_update_event("manifest_check", "failed", str(validation.get("message", "Manifesto invalido.")), {
			"manifest_source": source,
		})
		return validation

	var minimum_base := str(manifest.get("minimum_base_version", "")).strip_edges()
	if minimum_base != "" and compare_versions(_base_version(), minimum_base) < 0:
		record_update_event("manifest_check", "blocked", "Manifesto exige executavel-base mais novo.", {
			"manifest_source": source,
			"minimum_base_version": minimum_base,
		})
		return {
			"ok": false,
			"requires_new_executable": true,
			"message": "Esta versao exige um novo executavel-base %s ou superior." % minimum_base,
		}

	var next_version := str(manifest.get("version", ""))
	var update_available := compare_versions(next_version, current_version()) > 0
	_available_manifest = manifest.duplicate(true)
	_available_manifest_source = source
	var manifest_message := "Atualizacao disponivel." if update_available else "O sistema ja esta atualizado."
	record_update_event("manifest_check", "ok", manifest_message, {
		"manifest_source": source,
		"available": update_available,
		"manifest_version": next_version,
		"minimum_base_version": minimum_base,
	})
	return {
		"ok": true,
		"available": update_available,
		"current_version": current_version(),
		"version": next_version,
		"notes": str(manifest.get("notes", "")),
		"size": int(manifest.get("size", 0)),
		"message": "Atualizacao %s disponivel." % next_version if update_available else "O sistema ja esta atualizado.",
	}


func install_available_update() -> Dictionary:
	if _available_manifest.is_empty():
		record_update_event("install", "failed", "Verifique as atualizacoes antes de instalar.")
		return {"ok": false, "message": "Verifique as atualizacoes antes de instalar."}

	var package_source := _resolve_package_source(_available_manifest, _available_manifest_source)
	if package_source == "":
		record_update_event("install", "failed", "O manifesto nao informou o pacote da atualizacao.", {
			"manifest_version": str(_available_manifest.get("version", "")),
		})
		return {"ok": false, "message": "O manifesto nao informou o pacote da atualizacao."}

	var version := str(_available_manifest.get("version", "")).strip_edges()
	var temp_path := _update_dir.path_join("download-%s.tmp" % _safe_version(version))
	var transfer := await _download_or_copy(package_source, temp_path)
	if not bool(transfer.get("ok", false)):
		record_update_event("install", "failed", str(transfer.get("message", "Falha no download/copia.")), {
			"manifest_version": version,
			"package_source": package_source,
		})
		return transfer

	var validation := _validate_download(temp_path, _available_manifest)
	if not bool(validation.get("ok", false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		record_update_event("install", "failed", str(validation.get("message", "Pacote invalido.")), {
			"manifest_version": version,
			"package_source": package_source,
		})
		return validation

	var staged := stage_update(temp_path, _available_manifest)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	if bool(staged.get("ok", false)):
		record_update_event("install", "staged", str(staged.get("message", "")), {
			"manifest_version": version,
			"package_source": package_source,
			"restart_required": bool(staged.get("restart_required", false)),
		})
	else:
		record_update_event("install", "failed", str(staged.get("message", "Falha ao preparar atualizacao.")), {
			"manifest_version": version,
			"package_source": package_source,
		})
	return staged


func stage_update(package_path: String, manifest: Dictionary) -> Dictionary:
	var validation := validate_manifest(manifest)
	if not bool(validation.get("ok", false)):
		record_update_event("install", "failed", str(validation.get("message", "Manifesto invalido.")), {
			"candidate_version": str(manifest.get("version", "")),
		})
		return validation
	var source_validation := _validate_download(package_path, manifest)
	if not bool(source_validation.get("ok", false)):
		record_update_event("install", "failed", str(source_validation.get("message", "Pacote invalido.")), {
			"candidate_version": str(manifest.get("version", "")),
			"package_path": package_path,
		})
		return source_validation

	var version := str(manifest.get("version", "")).strip_edges()
	if compare_versions(version, current_version()) <= 0:
		record_update_event("install", "ignored", "A versao nao e mais nova que a instalada.", {
			"candidate_version": version,
			"current_version": current_version(),
		})
		return {"ok": false, "message": "A versao %s nao e mais nova que a instalada." % version}

	var destination := _update_dir.path_join("grupo-rs-central-%s.pck" % _safe_version(version))
	var copy_result := _copy_file(package_path, destination)
	if not bool(copy_result.get("ok", false)):
		record_update_event("install", "failed", str(copy_result.get("message", "Falha ao copiar pacote.")), {
			"candidate_version": version,
			"package_path": package_path,
		})
		return copy_result

	var destination_validation := _validate_download(destination, manifest)
	if not bool(destination_validation.get("ok", false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(destination))
		record_update_event("install", "failed", str(destination_validation.get("message", "Pacote copiado invalido.")), {
			"candidate_version": version,
			"package_path": destination,
		})
		return destination_validation

	_state["pending"] = {
		"version": version,
		"path": destination,
		"sha256": str(manifest.get("sha256", "")).to_lower(),
		"size": int(manifest.get("size", 0)),
		"notes": str(manifest.get("notes", "")),
		"staged_at": Time.get_datetime_string_from_system(false, true),
		"boot_started": false,
	}
	_state.erase("last_error")
	_write_state()
	record_update_event("install", "staged", "Atualizacao instalada e aguardando reinicio.", {
		"candidate_version": version,
		"package_path": destination,
		"sha256": str(manifest.get("sha256", "")).to_lower(),
		"size": int(manifest.get("size", 0)),
	})
	return {
		"ok": true,
		"restart_required": true,
		"version": version,
		"message": "Atualizacao %s instalada. Reinicie o sistema para aplicar." % version,
	}


func rollback_available() -> bool:
	var base_version := _base_version()
	var active: Dictionary = _dictionary(_state.get("active", {}))
	var previous: Dictionary = _dictionary(_state.get("previous", {}))
	return (
		(not active.is_empty() and compare_versions(str(active.get("version", "")), base_version) > 0)
		or (not previous.is_empty() and compare_versions(str(previous.get("version", "")), base_version) > 0)
	)


func prepare_rollback() -> Dictionary:
	var active: Dictionary = _dictionary(_state.get("active", {}))
	var previous: Dictionary = _dictionary(_state.get("previous", {}))
	if active.is_empty() and previous.is_empty():
		record_update_event("rollback", "failed", "Nao existe versao anterior para restaurar.", {})
		return {"ok": false, "message": "Nao existe versao anterior para restaurar."}

	if previous.is_empty():
		_state["previous"] = active
		_state.erase("active")
		_state.erase("pending")
		_write_state()
		record_update_event("rollback", "prepared", "Retorno ao executavel base preparado.", {
			"from_version": str(active.get("version", "")),
			"to_version": _base_version(),
		})
		return {
			"ok": true,
			"restart_required": true,
			"version": _base_version(),
			"message": "Retorno ao executavel base preparado.",
		}

	_state["active"] = previous
	_state["previous"] = active
	_state.erase("pending")
	_write_state()
	record_update_event("rollback", "prepared", "Retorno para a versao %s preparado." % str(previous.get("version", "")), {
		"from_version": str(active.get("version", "")),
		"to_version": str(previous.get("version", "")),
	})
	return {
		"ok": true,
		"restart_required": true,
		"version": str(previous.get("version", _base_version())),
		"message": "Retorno para a versao %s preparado." % str(previous.get("version", "")),
	}


func restart_application() -> Dictionary:
	if OS.has_feature("editor"):
		record_update_event("restart", "blocked", "Reinicio automatico disponivel somente no executavel exportado.", {})
		return {"ok": false, "message": "Reinicio automatico disponivel somente no executavel exportado."}
	var executable := OS.get_executable_path()
	if executable.strip_edges() == "":
		record_update_event("restart", "failed", "Executavel atual nao localizado.", {})
		return {"ok": false, "message": "Executavel atual nao localizado."}
	var process_id := OS.create_process(executable, PackedStringArray(["--updated-restart"]), false)
	if process_id <= 0:
		record_update_event("restart", "failed", "O Windows nao iniciou a nova instancia do sistema.", {})
		return {"ok": false, "message": "O Windows nao iniciou a nova instancia do sistema."}
	get_tree().quit()
	record_update_event("restart", "ok", "Reiniciando o sistema.", {
		"process_id": process_id,
	})
	return {"ok": true, "message": "Reiniciando o sistema."}


func validate_manifest(manifest: Dictionary) -> Dictionary:
	if str(manifest.get("app", "")).strip_edges() != APP_ID:
		return {"ok": false, "message": "Manifesto pertence a outro aplicativo."}
	var version := str(manifest.get("version", "")).strip_edges()
	if not _version_is_valid(version):
		return {"ok": false, "message": "Versao invalida no manifesto."}
	var package_name := str(manifest.get("package", manifest.get("url", ""))).strip_edges()
	if package_name == "":
		return {"ok": false, "message": "Pacote nao informado no manifesto."}
	var sha256 := str(manifest.get("sha256", "")).strip_edges().to_lower()
	if sha256.length() != 64 or not sha256.is_valid_hex_number(false):
		return {"ok": false, "message": "SHA-256 invalido no manifesto."}
	if int(manifest.get("size", 0)) <= 0:
		return {"ok": false, "message": "Tamanho do pacote invalido no manifesto."}
	return {"ok": true}


func compare_versions(left: String, right: String) -> int:
	var left_parts := _version_parts(left)
	var right_parts := _version_parts(right)
	var count := maxi(left_parts.size(), right_parts.size())
	for index in range(count):
		var left_value := int(left_parts[index]) if index < left_parts.size() else 0
		var right_value := int(right_parts[index]) if index < right_parts.size() else 0
		if left_value < right_value:
			return -1
		if left_value > right_value:
			return 1
	return 0


func _version_parts(value: String) -> Array[int]:
	var clean := value.strip_edges().split("-", false, 1)[0]
	var result: Array[int] = []
	for part in clean.split("."):
		result.append(int(part) if str(part).is_valid_int() else 0)
	return result


func _version_is_valid(value: String) -> bool:
	var clean := value.strip_edges().split("-", false, 1)[0]
	var parts := clean.split(".")
	if parts.size() < 2 or parts.size() > 4:
		return false
	for part in parts:
		if not str(part).is_valid_int():
			return false
	return true


func _safe_version(value: String) -> String:
	var result := ""
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if character.is_valid_int() or character in [".", "-", "_"]:
			result += character
	return result if result != "" else "update"


func _base_version() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", "3.8.0")).strip_edges()
	return version if version != "" else "3.8.0"


func _load_manifest_source(source: String) -> Dictionary:
	if _is_http_source(source):
		if source.begins_with("http://") and not source.begins_with("http://127.0.0.1") and not source.begins_with("http://localhost"):
			return {"ok": false, "message": "Use HTTPS para buscar atualizacoes pela internet."}
		var request := HTTPRequest.new()
		add_child(request)
		var request_error := request.request(source)
		if request_error != OK:
			request.queue_free()
			return {"ok": false, "message": "Nao foi possivel iniciar a consulta de atualizacao."}
		var completed: Array = await request.request_completed
		request.queue_free()
		var result := int(completed[0])
		var response_code := int(completed[1])
		var body: PackedByteArray = completed[3]
		if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
			return {"ok": false, "message": "Servidor de atualizacao respondeu HTTP %d." % response_code}
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			return {"ok": false, "message": "Manifesto recebido em formato invalido."}
		return {"ok": true, "manifest": parsed as Dictionary}

	var local_path := _normalize_local_source(source)
	if not FileAccess.file_exists(local_path):
		return {"ok": false, "message": "Manifesto nao encontrado em %s." % source}
	var manifest := _read_json(local_path)
	if manifest.is_empty():
		return {"ok": false, "message": "Manifesto local vazio ou invalido."}
	return {"ok": true, "manifest": manifest}


func _resolve_package_source(manifest: Dictionary, manifest_source: String) -> String:
	var explicit_url := str(manifest.get("url", "")).strip_edges()
	if explicit_url != "":
		return explicit_url
	var package_name := str(manifest.get("package", "")).strip_edges()
	if package_name == "":
		return ""
	if _is_http_source(manifest_source):
		return manifest_source.get_base_dir().path_join(package_name)
	return _normalize_local_source(manifest_source).get_base_dir().path_join(package_name)


func _download_or_copy(source: String, destination: String) -> Dictionary:
	_prepare_directories()
	if _is_http_source(source):
		if source.begins_with("http://") and not source.begins_with("http://127.0.0.1") and not source.begins_with("http://localhost"):
			return {"ok": false, "message": "Download bloqueado: a atualizacao deve usar HTTPS."}
		var request := HTTPRequest.new()
		request.download_file = ProjectSettings.globalize_path(destination)
		add_child(request)
		var request_error := request.request(source)
		if request_error != OK:
			request.queue_free()
			return {"ok": false, "message": "Nao foi possivel iniciar o download."}
		var completed: Array = await request.request_completed
		request.queue_free()
		var result := int(completed[0])
		var response_code := int(completed[1])
		if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
			return {"ok": false, "message": "Download falhou com HTTP %d." % response_code}
		return {"ok": true}
	return _copy_file(_normalize_local_source(source), destination)


func _copy_file(source: String, destination: String) -> Dictionary:
	var source_path := ProjectSettings.globalize_path(source)
	var destination_path := ProjectSettings.globalize_path(destination)
	var input := FileAccess.open(source_path, FileAccess.READ)
	if input == null:
		return {"ok": false, "message": "Pacote de origem nao pode ser aberto."}
	DirAccess.make_dir_recursive_absolute(destination_path.get_base_dir())
	var output := FileAccess.open(destination_path, FileAccess.WRITE)
	if output == null:
		input.close()
		return {"ok": false, "message": "Pasta de atualizacoes sem permissao de escrita."}
	var remaining := input.get_length()
	while remaining > 0:
		var amount := mini(remaining, DOWNLOAD_CHUNK_SIZE)
		output.store_buffer(input.get_buffer(amount))
		remaining -= amount
	output.flush()
	input.close()
	output.close()
	return {"ok": true}


func _validate_download(path: String, manifest: Dictionary) -> Dictionary:
	var global_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(global_path):
		return {"ok": false, "message": "Pacote baixado nao foi encontrado."}
	var expected_size := int(manifest.get("size", 0))
	var file := FileAccess.open(global_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "Pacote baixado nao pode ser lido."}
	var actual_size := file.get_length()
	file.close()
	if expected_size > 0 and actual_size != expected_size:
		return {"ok": false, "message": "Tamanho do pacote divergente: esperado %d, recebido %d." % [expected_size, actual_size]}
	var expected_hash := str(manifest.get("sha256", "")).to_lower()
	var actual_hash := FileAccess.get_sha256(global_path).to_lower()
	if expected_hash != actual_hash:
		return {"ok": false, "message": "SHA-256 do pacote nao confere. A atualizacao foi bloqueada."}
	return {"ok": true, "sha256": actual_hash, "size": actual_size}


func _validate_local_package(package: Dictionary) -> Dictionary:
	var path := str(package.get("path", "")).strip_edges()
	if path == "" or not FileAccess.file_exists(path):
		return {"ok": false, "message": "Pacote ativo nao foi encontrado."}
	var expected_hash := str(package.get("sha256", "")).to_lower()
	if expected_hash == "":
		return {"ok": false, "message": "Pacote ativo sem hash de integridade."}
	var actual_hash := FileAccess.get_sha256(path).to_lower()
	if actual_hash != expected_hash:
		return {"ok": false, "message": "Pacote ativo falhou na verificacao de integridade."}
	return {"ok": true}


func _is_http_source(value: String) -> bool:
	var clean := value.strip_edges().to_lower()
	return clean.begins_with("https://") or clean.begins_with("http://")


func _normalize_local_source(value: String) -> String:
	var clean := value.strip_edges()
	if clean.begins_with("file:///"):
		clean = clean.substr(8)
	elif clean.begins_with("file://"):
		clean = clean.substr(7)
	return clean.replace("/", "\\") if OS.get_name() == "Windows" else clean


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _read_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_ARRAY:
		return parsed as Array
	if typeof(parsed) == TYPE_DICTIONARY:
		var events: Variant = (parsed as Dictionary).get("events", [])
		return events as Array if typeof(events) == TYPE_ARRAY else []
	return []


func _write_state() -> bool:
	return _write_json(_state_path, _state)


func _write_json(path: String, value: Dictionary) -> bool:
	var global_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(global_path.get_base_dir())
	var temp_path := global_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	file.close()
	if FileAccess.file_exists(global_path):
		DirAccess.remove_absolute(global_path)
	return DirAccess.rename_absolute(temp_path, global_path) == OK


func _prune_update_log() -> void:
	var max_entries := 500
	if _update_log.size() <= max_entries:
		return
	_update_log = _update_log.slice(_update_log.size() - max_entries)


func _dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


func _remove_directory_contents(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		var child_path := path.path_join(entry)
		if directory.current_is_dir():
			_remove_directory_contents(child_path)
			DirAccess.remove_absolute(child_path)
		else:
			DirAccess.remove_absolute(child_path)
		entry = directory.get_next()
	directory.list_dir_end()
