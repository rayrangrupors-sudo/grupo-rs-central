extends RefCounted

const TIME_PROFILE := "3600;60;60;1;0;300;0;0;0"


func commands_for(serial: String) -> Dictionary:
	var clean_serial := serial.strip_edges()
	return {
		"time": "ST300RPT;%s;02;%s" % [clean_serial, TIME_PROFILE],
		"apn": "ST300NTW;%s;319H;0;hinova.br;hinova;hinova;grupors1.ddns.net;5940;grupors1.ddns.net;5941;#" % clean_serial,
		"link": "ST300NTW;%s;319H;0;linksolutions.br;link;link;grupors1.ddns.net;5940;grupors1.ddns.net;5941;#" % clean_serial,
	}


func command_for_apn(serial: String, apn: String) -> String:
	var normalized := apn.strip_edges().to_lower()
	var commands := commands_for(serial)
	if "link" in normalized:
		return str(commands.get("link", ""))
	if "hinova" in normalized:
		return str(commands.get("apn", ""))
	return ""
