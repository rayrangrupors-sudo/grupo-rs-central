extends RefCounted


func validate(login: String, password: String, config: Dictionary) -> bool:
	var expected_user := str(config.get("user", "")).strip_edges()
	var salt := str(config.get("salt", "")).strip_edges()
	var expected_hash := str(config.get("password_hash", "")).strip_edges()
	if expected_user == "" or salt == "" or expected_hash == "":
		return false
	return login == expected_user and password_hash(password, salt) == expected_hash


func password_hash(password: String, salt: String) -> String:
	return ("%s:%s" % [salt, password]).sha256_text()
