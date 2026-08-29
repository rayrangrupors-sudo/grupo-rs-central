extends SceneTree
const VaultScript:=preload("res://src/security/secret_vault.gd")
func _init() -> void:
	var vault:=VaultScript.new(); root.add_child(vault)
	var status:Dictionary=vault.status()
	print(JSON.stringify({"ok":status.get("ok",false),"encrypted":status.get("encrypted",false),"password_configured":status.get("password_configured",false),"secret_count":status.get("secret_count",0)}))
	quit(0 if bool(status.get("ok",false)) and int(status.get("secret_count",0))>0 else 1)
