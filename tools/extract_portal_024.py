#!/usr/bin/env python3
"""Extrai, em modo somente leitura, equipamentos 024 do portal Grupo RS."""

from __future__ import annotations

import argparse
import html
import json
import re
import time
import unicodedata
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path


class TableParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.in_tr = False
        self.in_cell = False
        self.cell_parts: list[str] = []
        self.row: list[str] = []
        self.rows: list[list[str]] = []
        self.current_id = ""
        self.row_id = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_dict = dict(attrs)
        if tag == "tr":
            self.in_tr = True
            self.row = []
            self.row_id = ""
        elif tag in {"td", "th"} and self.in_tr:
            self.in_cell = True
            self.cell_parts = []
        elif tag == "a" and self.in_tr:
            href = attrs_dict.get("href") or ""
            match = re.search(r"equipamentos_editar\.php\?id=(\d+)", href)
            if match:
                self.row_id = match.group(1)

    def handle_data(self, data: str) -> None:
        if self.in_cell:
            self.cell_parts.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag in {"td", "th"} and self.in_cell:
            value = " ".join("".join(self.cell_parts).split())
            self.row.append(html.unescape(value))
            self.in_cell = False
        elif tag == "tr" and self.in_tr:
            if self.row:
                self.rows.append(self.row + [self.row_id])
            self.in_tr = False


def normalize_client(value: str) -> str:
    plain = unicodedata.normalize("NFKD", value)
    plain = "".join(c for c in plain if not unicodedata.combining(c))
    return re.sub(r"[^A-Z0-9]", "", plain.upper())


def clean(value: str) -> str:
    value = " ".join(value.replace("\xa0", " ").split()).strip()
    return "" if value in {"-", "--"} else value


def fetch(url: str, attempts: int = 4) -> str:
    last_error: Exception | None = None
    for attempt in range(attempts):
        try:
            request = urllib.request.Request(
                url,
                headers={"User-Agent": "Mozilla/5.0 (compatible; GrupoRS-Auditoria/1.0)"},
            )
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.read().decode("utf-8", errors="replace")
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"Falha ao consultar {url}: {last_error}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--pages", type=int, default=257)
    args = parser.parse_args()

    base_url = "https://novogrupors.ddns.net/cadastro/equipamentos_listar.php"
    selected: list[dict[str, str | int]] = []
    excluded: list[dict[str, str | int]] = []
    scanned_rows = 0

    for page in range(1, args.pages + 1):
        url = f"{base_url}?{urllib.parse.urlencode({'pagina': page})}"
        document = fetch(url)
        table = TableParser()
        table.feed(document)
        data_rows = [row for row in table.rows if len(row) >= 9 and row[0] != "Numero Serie"]
        scanned_rows += len(data_rows)
        for row in data_rows:
            serial, model, plate, client, chip, phone, status = map(clean, row[:7])
            portal_id = clean(row[-1])
            if not serial.startswith("024"):
                continue
            item: dict[str, str | int] = {
                "portal_id": portal_id,
                "numero_serie": serial,
                "numero_chip": chip,
                "placa_vinculada": plate,
                "cliente": client,
                "modelo": model,
                "telefone": phone,
                "status": status,
                "pagina_origem": page,
                "url_origem": url,
            }
            normalized = normalize_client(client)
            if normalized in {"RS300", "MANUTENCOES"}:
                item["motivo_exclusao"] = "RS300" if normalized == "RS300" else "MANUTENÇÕES"
                excluded.append(item)
            else:
                selected.append(item)
        if page % 25 == 0 or page == args.pages:
            print(f"paginas={page}/{args.pages} linhas={scanned_rows} selecionados={len(selected)}")

    serial_groups: dict[str, list[int]] = {}
    chip_groups: dict[str, list[int]] = {}
    for index, item in enumerate(selected):
        serial_groups.setdefault(str(item["numero_serie"]), []).append(index)
        if item["numero_chip"]:
            chip_groups.setdefault(str(item["numero_chip"]), []).append(index)

    conflicts: list[dict[str, object]] = []
    for value, indexes in serial_groups.items():
        if len(indexes) > 1:
            conflicts.append({"tipo": "Número de série duplicado", "valor": value, "indices": indexes})
    for value, indexes in chip_groups.items():
        if len(indexes) > 1:
            conflicts.append({"tipo": "Chip duplicado", "valor": value, "indices": indexes})

    for index, item in enumerate(selected):
        notes: list[str] = []
        if not item["numero_chip"]:
            notes.append("chip ausente")
        if not item["placa_vinculada"]:
            notes.append("placa ausente")
        if len(serial_groups[str(item["numero_serie"])]) > 1:
            notes.append("série duplicada")
        if item["numero_chip"] and len(chip_groups[str(item["numero_chip"])]) > 1:
            notes.append("chip duplicado")
        item["situacao_importacao"] = "REVISAR" if notes else "PRONTO"
        item["observacao"] = "; ".join(notes)
        item["indice_extracao"] = index + 1

    payload = {
        "metadata": {
            "source": base_url,
            "extracted_at_utc": datetime.now(timezone.utc).isoformat(),
            "pages_scanned": args.pages,
            "rows_scanned": scanned_rows,
            "matched_024_before_exclusion": len(selected) + len(excluded),
            "selected_rows": len(selected),
            "excluded_rows": len(excluded),
            "excluded_rs300": sum(1 for x in excluded if x["motivo_exclusao"] == "RS300"),
            "excluded_manutencoes": sum(1 for x in excluded if x["motivo_exclusao"] == "MANUTENÇÕES"),
            "missing_chip": sum(1 for x in selected if not x["numero_chip"]),
            "missing_plate": sum(1 for x in selected if not x["placa_vinculada"]),
            "duplicate_serial_groups": sum(1 for x in conflicts if x["tipo"] == "Número de série duplicado"),
            "duplicate_chip_groups": sum(1 for x in conflicts if x["tipo"] == "Chip duplicado"),
        },
        "selected": selected,
        "excluded": excluded,
        "conflicts": conflicts,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(payload["metadata"], ensure_ascii=False))


if __name__ == "__main__":
    main()
