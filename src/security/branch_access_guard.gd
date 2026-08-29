class_name BranchAccessGuard
extends RefCounted

## Guarda local de autorização por filial. A decisão final deve ser reforçada
## pelas regras do Banco local SQL; nenhuma credencial é armazenada neste arquivo.
const SESSION_TTL_SECONDS := 900

var _authorized_branch := ""
var _authorized_until := 0
var _permission := ""

func authorize(branch_id: String, permission: String, granted: bool, ttl_seconds: int = SESSION_TTL_SECONDS) -> bool:
	_authorized_branch = branch_id.strip_edges().to_lower() if granted else ""
	_permission = permission.strip_edges().to_lower() if granted else ""
	_authorized_until = Time.get_unix_time_from_system() + maxi(60, ttl_seconds) if granted else 0
	return granted and _authorized_branch != "" and _permission != ""

func clear() -> void:
	_authorized_branch = ""
	_permission = ""
	_authorized_until = 0

func can_access(branch_id: String, permission: String) -> bool:
	if _authorized_branch == "" or Time.get_unix_time_from_system() >= _authorized_until:
		clear()
		return false
	return _authorized_branch == branch_id.strip_edges().to_lower() and _permission == permission.strip_edges().to_lower()

func authorized_branch() -> String:
	return _authorized_branch if Time.get_unix_time_from_system() < _authorized_until else ""
