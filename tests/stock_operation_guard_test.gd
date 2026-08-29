extends SceneTree

const Guard := preload("res://src/security/stock_operation_guard.gd")

func _init() -> void:
	var guard := Guard.new()
	assert(not guard.accept_remote_snapshot({}))
	assert(not guard.accept_remote_snapshot({"records": {}}))
	assert(guard.accept_remote_snapshot({"records": {"products": {}}}))
	assert(guard.can_report_success(true, "op-1", "op-1"))
	assert(not guard.can_report_success(false, "op-1", "op-1"))
	assert(not guard.can_report_success(true, "op-1", "op-2"))
	assert(guard.is_safe_branch("imperatriz"))
	assert(not guard.is_safe_branch("outra"))
	print("STOCK_OPERATION_GUARD_TEST_OK")
	quit()
