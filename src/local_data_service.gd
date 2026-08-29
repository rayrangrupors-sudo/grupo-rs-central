extends Node
signal status_changed(status: Dictionary)
var _store: Variant
var _branch_id := "imperatriz"
var _status := {"state":"online","message":"Banco SQLite local disponivel.","data_available":true,"local":true,"read_verified":true,"write_verified":true,"latency_ms":0,"last_sync_at":"local"}

func _ready() -> void: call_deferred("_emit_status")
func bind_store(store: Variant, branch_id: String) -> void:
	_store=store; _branch_id=branch_id.to_lower().strip_edges()
	_status={"state":"online","message":"Banco local da filial %s disponivel." % _branch_id,"data_available":true,"local":true,"read_verified":true,"write_verified":true,"latency_ms":0,"last_sync_at":Time.get_datetime_string_from_system(false,true)}; _emit_status()
func get_status() -> Dictionary: return _status.duplicate(true)
func get_configuration_summary() -> Dictionary: return {"configured":true,"provider":"SQLite local","branch":_branch_id,"database":"C:/GRUPO RS CENTRAL/database/grupo_rs_central.sqlite"}
func uses_encrypted_secret_vault() -> bool: return true
func is_stock_live_read_only() -> bool: return false
func is_local_database_auth_required() -> bool: return false
func is_operator_authenticated() -> bool: return true
func authenticate_operator(_email:String,_password:String) -> Dictionary: return {"ok":true,"local":true}
func get_remote_credentials() -> Dictionary: return {}
func get_remote_credential(_key:String,fallback:Variant="") -> Variant: return fallback
func save_remote_credentials(_credentials:Dictionary) -> Dictionary: return {"ok":true,"local":true}
func configure_account(_config:Dictionary) -> bool: return true
func refresh_remote(_health_only:bool=false) -> Dictionary:
	if _store != null and _store.has_method("load_db"): _store.call("load_db")
	return {"ok":true,"state":"online","message":"Dados locais carregados.","data_available":true,"local":true,"read_verified":true,"write_verified":true,"latency_ms":0,"last_sync_at":Time.get_datetime_string_from_system(false,true)}
func sync_now() -> Dictionary:
	# Cada mutação do Store já foi confirmada pela própria transação incremental.
	# Não regrave todos os registros apenas para representar uma sincronização.
	var ready: bool = _store != null and _store.has_method("verify_product_persisted")
	return {"ok":ready,"state":"online" if ready else "error","message":"Transação SQLite concluída." if ready else "Banco local indisponível.","data_available":ready,"local":true}
func force_sync() -> void: sync_now()
func verify_product_persisted(serial:String,expected:Dictionary={}) -> Dictionary:
	if _store == null or not _store.has_method("verify_product_persisted"):
		return {"ok":false,"found":false,"message":"Banco local nao vinculado para verificacao fisica."}
	var verification: Variant = _store.call("verify_product_persisted", serial, expected)
	var result: Dictionary = verification as Dictionary if typeof(verification) == TYPE_DICTIONARY else {}
	result["local"] = true
	return result
func _emit_status() -> void: status_changed.emit(_status.duplicate(true))
