extends SceneTree
const Policy=preload("res://tests/fixtures/adaptive_query_policy.gd")
func _initialize() -> void:
	var p:=Policy.new()
	assert(p.limit==5)
	assert(p.failure(0,1,1000) and p.limit==2 and p.cooldown_until==3000)
	assert(p.failure(503,2,2000) and p.limit==1 and p.cooldown_until==6000)
	assert(not p.failure(0,3,3000) and p.retries==2)
	for code in [401,403,429]:
		var auth:=Policy.new()
		assert(not auth.failure(code,1,0) and auth.stopped)
	var absent:=Policy.new()
	assert(not absent.failure(404,1,0) and absent.limit==5)
	print("ADAPTIVE_POLICY_TEST_PASS")
	quit()
