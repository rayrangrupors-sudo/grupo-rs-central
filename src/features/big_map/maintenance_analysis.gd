## Evidence summary, not a confirmed hardware diagnosis.
extends RefCounted
const Dates := preload("res://src/inventory_communication_status.gd")
const Snapshot := preload("res://src/features/big_map/maintenance_snapshot.gd")

static func compact(records: Array, chip: Dictionary) -> String:
	var evidence := summarize(records, chip)
	for line in evidence.split("\n\n"):
		if line.contains("abaixo de 9 V com ignição ligada"):
			return "Possível causa: alimentação ou instalação.\nEvidência: " + line.split(":")[0] + ".\nPróxima ação: verificar alimentação e instalação."
		if line.contains("atraso GPS"):
			return "Possível causa: atraso de transmissão ou horário/GPS.\nEvidência: " + line.split(". Pode")[0] + ".\nPróxima ação: conferir os horários e a conectividade."
		if line.contains("abaixo de 9 V com ignição desligada"):
			return "Possível causa: alimentação ou dormência.\nEvidência: " + line.split(":")[0] + ".\nPróxima ação: verificar tempo parado e alimentação."
	return "Análise inconclusiva.\nEvidência: %d registros, sem causa determinada.\nPróxima ação: conferir o equipamento e os detalhes disponíveis." % records.size()


static func summarize(records: Array, chip: Dictionary) -> String:
	var voltage_count := 0
	var low_on := 0
	var low_off := 0
	var lag_count := 0
	var comparable_dates := 0
	for row in records:
		var value := str(row.get("battery_voltage", "")).replace(",", ".").strip_edges()
		if value.is_valid_float():
			voltage_count += 1
			if value.to_float() < 9.0:
				var state := Snapshot.ignition(row.get("ignition"))
				low_on += int(state == 1)
				low_off += int(state == 0)
		var server := Dates.parse_datetime(str(row.get("server_at", "")))
		var gps := Dates.parse_datetime(str(row.get("gps_at", "")))
		if server > 0 and gps > 0:
			comparable_dates += 1
			lag_count += int(server - gps > 7200)
	var lines: Array[String] = ["Análise experimental · %d registros recebidos." % records.size()]
	if records.is_empty():
		lines.append("Sem histórico disponível: causa não determinada.")
	if lag_count > 0:
		lines.append("%d/%d registros com atraso GPS → servidor superior a 2 h. Pode envolver transmissão represada ou horário/GPS; não confirma defeito." % [lag_count, comparable_dates])
	if low_on > 0:
		lines.append("%d registros abaixo de 9 V com ignição ligada: verificar alimentação, instalação e interpretação da tensão pelo equipamento." % low_on)
	if low_off > 0:
		lines.append("%d registros abaixo de 9 V com ignição desligada: verificar alimentação e eventual dormência. A leitura isolada não confirma a causa." % low_off)
	if voltage_count == 0:
		lines.append("Tensão externa indisponível nos registros.")
	if comparable_dates == 0:
		lines.append("Não há pares de horários GPS/servidor válidos para avaliar atraso.")
	if not records.is_empty() and lag_count == 0 and low_on == 0 and low_off == 0:
		lines.append("Nenhuma dessas anomalias foi identificada na amostra. Isso não exclui falha interna, instalação ou perda de configuração APN/porta.")
	var chip_status := str(chip.get("status", "indisponível")).to_lower()
	if chip_status not in ["online", "offline"]:
		chip_status = "indisponível"
	lines.append("Chip agora: %s. Esse estado não descreve o momento da última comunicação." % chip_status)
	lines.append("ERBs próximas não comprovam cobertura nem intensidade de sinal. Travamento, curto e perda de APN não são confirmáveis apenas por ausência de comunicação.")
	lines.append("O prefixo 024 não identifica a versão do RS300. Comandos exigem revisão manual; nenhum SMS é enviado pela análise.")
	return "\n\n".join(lines)
