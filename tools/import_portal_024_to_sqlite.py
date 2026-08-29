#!/usr/bin/env python3
"""Importação auditável dos rastreadores 024 previamente extraídos."""

from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import uuid
from collections import Counter
from datetime import datetime
from pathlib import Path


BRANCH = "imperatriz"
OPERATOR = "codex_importacao_autorizada"


def now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def select_rows(payload: dict) -> tuple[list[dict], dict]:
    rows = payload["selected"]
    duplicate_serials = {
        str(item["valor"])
        for item in payload["conflicts"]
        if item["tipo"] == "Número de série duplicado"
    }
    base_eligible = [
        row
        for row in rows
        if row["numero_chip"]
        and row["placa_vinculada"]
        and str(row["numero_serie"]) not in duplicate_serials
    ]
    chip_counts = Counter(str(row["numero_chip"]) for row in base_eligible)
    duplicate_chips = {chip for chip, count in chip_counts.items() if count > 1}
    accepted = [
        row
        for row in base_eligible
        if str(row["numero_chip"]) not in duplicate_chips
    ]
    report = {
        "source_rows": len(rows),
        "missing_chip_or_plate": sum(not x["numero_chip"] or not x["placa_vinculada"] for x in rows),
        "duplicate_serial_groups": len(duplicate_serials),
        "duplicate_serial_rows": sum(str(x["numero_serie"]) in duplicate_serials for x in rows),
        "duplicate_chip_groups": len(duplicate_chips),
        "duplicate_chip_rows": sum(str(x["numero_chip"]) in duplicate_chips for x in base_eligible),
        "accepted": len(accepted),
    }
    return accepted, report


def raw_device(row: dict, stamp: str) -> dict:
    serial = str(row["numero_serie"])
    chip = str(row["numero_chip"])
    plate = str(row["placa_vinculada"])
    client = str(row["cliente"])
    model = str(row["modelo"] or "RS 300")
    phone = str(row["telefone"] or "")
    return {
        "active": True,
        "category": model,
        "chip_number": chip,
        "chip_phone": phone,
        "client": client,
        "cost": 0.0,
        "created_at": stamp,
        "equipment_number": serial,
        "imei": serial,
        "installed_at": "Não informada",
        "installation_date": "Não informada",
        "last_movement_at": stamp,
        "location": "Instalado",
        "min_stock": 0,
        "model": model,
        "name": plate,
        "notes": f"Cliente Grupo RS: {client} | Importado do portal; data de instalação não informada",
        "operator": "",
        "plate": plate,
        "portal_id": str(row["portal_id"]),
        "portal_page": int(row["pagina_origem"]),
        "portal_status": str(row["status"]),
        "sku": serial,
        "status": "Instalado",
        "stock": 0,
        "tracker_status": "Instalado",
        "unit": "un",
        "updated_at": stamp,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()

    input_path = Path(args.input)
    db_path = Path(args.database)
    payload = json.loads(input_path.read_text(encoding="utf-8"))
    accepted, report = select_rows(payload)
    report.update({"branch": BRANCH, "executed": bool(args.execute), "source": str(input_path)})
    if report["accepted"] != 3185:
        raise RuntimeError(f"Contagem inesperada antes da importação: {report}")

    con = sqlite3.connect(db_path, timeout=30)
    con.execute("PRAGMA foreign_keys=ON")
    con.execute("PRAGMA busy_timeout=30000")
    integrity_before = con.execute("PRAGMA integrity_check").fetchone()[0]
    if integrity_before != "ok":
        raise RuntimeError(f"Banco não íntegro antes da importação: {integrity_before}")

    existing_serials = {
        row[0]: row[1]
        for row in con.execute("SELECT imei,id FROM devices WHERE branch_id=?", (BRANCH,))
    }
    existing_chips = {
        row[0]: row[1]
        for row in con.execute("SELECT iccid,id FROM devices WHERE branch_id=?", (BRANCH,))
        if row[0]
    }
    accepted_serials = {str(x["numero_serie"]) for x in accepted}
    for row in accepted:
        serial = str(row["numero_serie"])
        chip = str(row["numero_chip"])
        chip_owner = existing_chips.get(chip)
        expected_id = f"{BRANCH}:{serial}"
        if chip_owner and chip_owner != existing_serials.get(serial, expected_id):
            raise RuntimeError(f"Chip {chip} já pertence a outro aparelho no banco: {chip_owner}")

    report["existing_to_update"] = sum(serial in existing_serials for serial in accepted_serials)
    report["new_to_insert"] = len(accepted) - report["existing_to_update"]
    if not args.execute:
        print(json.dumps(report, ensure_ascii=False))
        con.close()
        return

    stamp = now()
    imported_ids: list[str] = []
    with con:
        con.execute("INSERT OR IGNORE INTO branches VALUES(?,?,?)", (BRANCH, "Imperatriz", stamp))
        for row in accepted:
            serial = str(row["numero_serie"])
            device_id = f"{BRANCH}:{serial}"
            raw = raw_device(row, stamp)
            raw_json = json.dumps(raw, ensure_ascii=False, separators=(",", ":"))
            con.execute(
                """
                INSERT INTO devices
                    (id,branch_id,sku,imei,iccid,plate,carrier,model,status,quantity,created_at,updated_at,raw_json)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(branch_id,sku) DO UPDATE SET
                    imei=excluded.imei,
                    iccid=excluded.iccid,
                    plate=excluded.plate,
                    model=excluded.model,
                    status=excluded.status,
                    quantity=excluded.quantity,
                    updated_at=excluded.updated_at,
                    raw_json=excluded.raw_json
                """,
                (
                    device_id,
                    BRANCH,
                    serial,
                    serial,
                    str(row["numero_chip"]),
                    str(row["placa_vinculada"]),
                    "",
                    str(row["modelo"] or "RS 300"),
                    "Instalado",
                    1.0,
                    stamp,
                    stamp,
                    raw_json,
                ),
            )
            imported_ids.append(device_id)

        details = {
            "action": "BULK_IMPORT_PORTAL_024",
            "accepted": len(accepted),
            "new": report["new_to_insert"],
            "updated": report["existing_to_update"],
            "excluded_missing_chip_or_plate": report["missing_chip_or_plate"],
            "excluded_duplicate_serial_rows": report["duplicate_serial_rows"],
            "excluded_duplicate_chip_rows": report["duplicate_chip_rows"],
            "status": "Instalado",
            "installation_date": "Não informada",
            "source_sha256": hashlib.sha256(input_path.read_bytes()).hexdigest(),
        }
        audit_id = f"{BRANCH}:audit:portal024:{uuid.uuid4()}"
        con.execute(
            "INSERT INTO audit_log VALUES(?,?,?,?,?,?,?,?,?)",
            (
                audit_id,
                BRANCH,
                "BULK_IMPORT_PORTAL_024",
                "devices",
                "portal_024_20260829",
                OPERATOR,
                stamp,
                json.dumps(details, ensure_ascii=False),
                json.dumps(details, ensure_ascii=False, separators=(",", ":")),
            ),
        )

    con.close()
    verify = sqlite3.connect(db_path)
    report["database_integrity"] = verify.execute("PRAGMA integrity_check").fetchone()[0]
    placeholders = ",".join("?" for _ in imported_ids)
    report["verified_imported_rows"] = verify.execute(
        f"SELECT COUNT(*) FROM devices WHERE id IN ({placeholders}) AND branch_id=? AND status='Instalado'",
        (*imported_ids, BRANCH),
    ).fetchone()[0]
    report["verified_not_informed_dates"] = sum(
        json.loads(row[0]).get("installed_at") == "Não informada"
        for row in verify.execute(
            f"SELECT raw_json FROM devices WHERE id IN ({placeholders}) AND branch_id=?",
            (*imported_ids, BRANCH),
        )
    )
    report["branch_devices_after"] = verify.execute(
        "SELECT COUNT(*) FROM devices WHERE branch_id=?", (BRANCH,)
    ).fetchone()[0]
    report["audit_rows"] = verify.execute(
        "SELECT COUNT(*) FROM audit_log WHERE id=?", (audit_id,)
    ).fetchone()[0]
    verify.close()
    report["executed_at"] = stamp
    Path(args.report).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
