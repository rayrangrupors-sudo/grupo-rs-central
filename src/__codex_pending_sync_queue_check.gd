extends SceneTree

const StoreScript := preload("res://src/inventory_store.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := "user://__codex_pending_sync_queue_check.json"
	var store: InventoryStore = StoreScript.new()
	store.configure(path, "__codex_pending_sync_queue_check.json", "user://__codex_pending_sync_queue_backups", false)
	store.clear_pending_sync_queue()
	store.load_db()

	for index in range(10):
		var sku := "024900%03d" % index
		_check(not store.upsert_product({
			"sku": sku,
			"name": "Fila %d" % index,
		}).is_empty(), "Registro %d nao entrou na fila." % index)

	_check(int(store.get_pending_sync_status().get("count", 0)) == 10, "A fila nao chegou ao limite de 10 registros.")
	_check(store.upsert_product({"sku": "024999999", "name": "Limite"}).is_empty(), "A fila aceitou o 11o registro.")

	var reopened: InventoryStore = StoreScript.new()
	reopened.configure(path, "__codex_pending_sync_queue_check.json", "user://__codex_pending_sync_queue_backups", false)
	_check(int(reopened.get_pending_sync_status().get("count", 0)) == 10, "A fila nao foi preservada no disco.")
	reopened.clear_pending_sync_queue()
	_check(int(reopened.get_pending_sync_status().get("count", 0)) == 0, "A fila nao foi limpa depois da confirmacao.")

	if failures.is_empty():
		print("PENDING_SYNC_QUEUE_CHECK_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
