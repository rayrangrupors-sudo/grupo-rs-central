class_name StockOperationGuard
extends RefCounted

## Barreiras comuns para impedir perda silenciosa ou sucesso falso.
const MAX_OPERATION_AGE_SECONDS := 900

func accept_remote_snapshot(snapshot: Variant) -> bool:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return false
	var data := snapshot as Dictionary
	if data.is_empty():
		return false
	var records: Variant = data.get("records", {})
	return typeof(records) == TYPE_DICTIONARY and not (records as Dictionary).is_empty()

func can_report_success(local_database_confirmed: bool, operation_id: String, expected_operation_id: String) -> bool:
	return local_database_confirmed and operation_id.strip_edges() != "" and operation_id == expected_operation_id

func is_safe_branch(branch_id: String) -> bool:
	return branch_id.strip_edges().to_lower() in ["imperatriz", "araguaina", "acailandia", "maraba"]
