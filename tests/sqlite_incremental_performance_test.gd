extends SceneTree

const StoreScript := preload("res://src/inventory_store.gd")
const TEST_DB := "C:/GRUPO RS CENTRAL/test_artifacts/sqlite_incremental_performance_test.sqlite"


func _init() -> void:
	var store := StoreScript.new()
	store.configure_isolated_sqlite_for_testing(TEST_DB, "imperatriz")
	var started := Time.get_ticks_msec()
	var products := store.get_products("", "all", false)
	var load_ms := Time.get_ticks_msec() - started
	if products.size() < 3000:
		push_error("PERFORMANCE_TEST: cópia não contém massa equivalente ao banco operacional.")
		quit(1)
		return

	started = Time.get_ticks_msec()
	var full_saved := store.save_db(false)
	var full_save_ms := Time.get_ticks_msec() - started

	var fixture := {
		"sku": "PERF-SQLITE-001", "imei": "PERF-SQLITE-001", "chip_number": "89550000000000009999",
		"plate": "PRF - 0001", "operator": "TIM", "model": "RS 300", "tracker_status": "Estoque", "stock": 1,
	}
	started = Time.get_ticks_msec()
	var created := store.upsert_product(fixture)
	var upsert_ms := Time.get_ticks_msec() - started

	started = Time.get_ticks_msec()
	var installed := store.install_tracker("PERF-SQLITE-001", "PRF - 9999")
	var install_ms := Time.get_ticks_msec() - started

	started = Time.get_ticks_msec()
	var logged := store.add_system_log_event("PERFORMANCE_TEST", "Evento incremental isolado.", "PERF-SQLITE-001")
	var log_ms := Time.get_ticks_msec() - started

	started = Time.get_ticks_msec()
	var deleted := store.delete_product("PERF-SQLITE-001")
	var delete_ms := Time.get_ticks_msec() - started

	var ok := full_saved and not created.is_empty() and installed and logged and deleted
	print(JSON.stringify({
		"ok": ok, "records": products.size(), "load_ms": load_ms, "legacy_full_save_ms": full_save_ms,
		"incremental_upsert_ms": upsert_ms, "incremental_install_ms": install_ms,
		"incremental_log_ms": log_ms, "incremental_delete_ms": delete_ms,
	}))
	quit(0 if ok else 1)
