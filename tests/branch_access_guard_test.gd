extends SceneTree

const Guard := preload("res://src/security/branch_access_guard.gd")

func _init() -> void:
	var guard := Guard.new()
	assert(not guard.can_access("imperatriz", "read"))
	assert(guard.authorize("imperatriz", "read", true, 120))
	assert(guard.can_access("imperatriz", "read"))
	assert(not guard.can_access("araguaina", "read"))
	assert(not guard.can_access("imperatriz", "write"))
	guard.clear()
	assert(not guard.can_access("imperatriz", "read"))
	print("BRANCH_ACCESS_GUARD_TEST_OK")
	quit()
