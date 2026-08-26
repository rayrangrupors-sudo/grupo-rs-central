extends SceneTree

const FirebaseSync := preload("res://src/firebase_sync.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sync := FirebaseSync.new()
	root.add_child(sync)
	await process_frame
	var expected_from_args := "--stock-live-read-only" in OS.get_cmdline_user_args()
	_check(bool(sync.call("is_stock_live_read_only")) == expected_from_args, "A flag read-only não foi interpretada conforme os argumentos do processo.")

	sync.set("_stock_live_read_only", true)
	_check(bool(sync.call("is_stock_live_read_only")), "O modo read-only não pôde ser habilitado para o teste.")

	var patch_result: Dictionary = await sync.call("_database_request", HTTPClient.METHOD_PATCH, "health/ping", {"probe": true})
	var put_result: Dictionary = await sync.call("_database_request", HTTPClient.METHOD_PUT, "health/ping", {"probe": true})
	var delete_result: Dictionary = await sync.call("_database_request", HTTPClient.METHOD_DELETE, "health/ping")
	_check(bool(patch_result.get("blocked", false)), "PATCH não foi bloqueado antes da rede.")
	_check(bool(put_result.get("blocked", false)), "PUT não foi bloqueado antes da rede.")
	_check(bool(delete_result.get("blocked", false)), "DELETE não foi bloqueado antes da rede.")
	var metrics: Dictionary = sync.call("get_read_only_metrics")
	_check(int(metrics.get("blocked_mutations", 0)) == 3, "Contagem sanitizada de mutações bloqueadas incorreta.")

	var probe: Dictionary = await sync.call("_verify_connection_read_write")
	_check(bool(probe.get("read_only", false)) and not bool(probe.get("write_ok", true)), "A sonda não foi desabilitada no modo read-only.")
	var heartbeat: Dictionary = await sync.call("_write_health_heartbeat")
	_check(bool(heartbeat.get("blocked", false)), "Heartbeat não foi bloqueado no modo read-only.")
	metrics = sync.call("get_read_only_metrics")
	_check(int(metrics.get("blocked_mutations", 0)) == 6, "Sonda/heartbeat não foram contabilizados de forma sanitizada.")

	var sync_result: Dictionary = await sync.call("sync_now")
	_check(sync_result.get("state") == "read_only", "sync_now não foi desabilitado no modo read-only.")
	sync.force_sync()
	await process_frame
	metrics = sync.call("get_read_only_metrics")
	_check(int(metrics.get("blocked_mutations", 0)) == 6, "force_sync tentou mutação no modo read-only.")

	sync.queue_free()
	await process_frame
	if failures.is_empty():
		print("FIREBASE_SYNC_READ_ONLY_TEST: OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
