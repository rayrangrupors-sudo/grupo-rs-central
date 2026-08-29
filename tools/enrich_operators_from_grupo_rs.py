#!/usr/bin/env python3
"""Consulta a operadora oficial no Grupo RS e atualiza o SQLite local com auditoria."""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import hashlib
import html
import json
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.request
import uuid
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


DETAIL_URL = "https://novogrupors.ddns.net/cadastro/equipamentos_editar.php?id={}"
SELECT_RE = re.compile(r"<select\b[^>]*\bname=[\"']CodOperadora[\"'][^>]*>(.*?)</select>", re.I | re.S)
OPTION_RE = re.compile(r"<option\b([^>]*)>(.*?)</option>", re.I | re.S)
TAG_RE = re.compile(r"<[^>]+>")


def clean(value: object) -> str:
    return " ".join(str(value or "").strip().split())


def parse_operator(page: str) -> str:
    select = SELECT_RE.search(page)
    if not select:
        return ""
    for attrs, label in OPTION_RE.findall(select.group(1)):
        if re.search(r"\bselected(?:\s*=\s*[\"']?selected[\"']?)?", attrs, re.I):
            return clean(html.unescape(TAG_RE.sub("", label)))
    return ""


def fetch_one(item: dict, retries: int = 4) -> dict:
    portal_id = clean(item["portal_id"])
    serial = clean(item["serial"])
    url = DETAIL_URL.format(portal_id)
    last_error = ""
    for attempt in range(retries):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "Grupo-RS-Local-Migration/1.0"})
            with urllib.request.urlopen(request, timeout=25) as response:
                body = response.read().decode("utf-8", errors="replace")
            operator = parse_operator(body)
            if not operator:
                raise ValueError("operadora selecionada não encontrada")
            return {"serial": serial, "portal_id": portal_id, "url": url, "operator": operator, "status": "ok"}
        except (urllib.error.URLError, TimeoutError, ValueError, OSError) as exc:
            last_error = f"{type(exc).__name__}: {exc}"
            if attempt + 1 < retries:
                time.sleep(0.8 * (attempt + 1))
    return {"serial": serial, "portal_id": portal_id, "url": url, "operator": "", "status": "error", "error": last_error}


def atomic_json(path: Path, payload: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


def build_portal_map(extraction_path: Path) -> tuple[dict[str, str], list[str]]:
    data = json.loads(extraction_path.read_text(encoding="utf-8"))
    selected: dict[str, set[str]] = {}
    excluded: dict[str, set[str]] = {}
    for group, destination in (("selected", selected), ("excluded", excluded)):
        for row in data.get(group, []):
            serial = clean(row.get("numero_serie"))
            portal_id = clean(row.get("portal_id"))
            if serial and portal_id:
                destination.setdefault(serial, set()).add(portal_id)
    # O banco foi criado a partir do conjunto `selected`; portanto ele tem
    # precedência sobre cópias antigas que ficaram em `excluded` (por exemplo,
    # uma unidade de manutenção com o mesmo número de série).
    mapping = {serial: next(iter(ids)) for serial, ids in selected.items() if len(ids) == 1}
    for serial, ids in excluded.items():
        if serial not in selected and len(ids) == 1:
            mapping[serial] = next(iter(ids))
    conflicts = sorted(serial for serial, ids in selected.items() if len(ids) != 1)
    return mapping, conflicts


def lookup(args: argparse.Namespace) -> int:
    args.output.mkdir(parents=True, exist_ok=True)
    portal_map, extraction_conflicts = build_portal_map(args.extraction)
    with sqlite3.connect(f"file:{args.database.as_posix()}?mode=ro", uri=True) as db:
        db_rows = db.execute(
            "SELECT id, sku, imei, carrier FROM devices WHERE branch_id = ? ORDER BY sku", (args.branch,)
        ).fetchall()
        integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
    if integrity != "ok":
        raise RuntimeError(f"banco não íntegro: {integrity}")
    if len(db_rows) != args.expected_count:
        raise RuntimeError(f"quantidade inesperada: {len(db_rows)} (esperado {args.expected_count})")

    targets = []
    missing = []
    for device_id, sku, imei, old_carrier in db_rows:
        serial = clean(imei) or clean(sku)
        portal_id = portal_map.get(serial)
        if not portal_id:
            missing.append(serial)
            continue
        targets.append({"device_id": device_id, "serial": serial, "portal_id": portal_id, "old_carrier": clean(old_carrier)})
    active_conflicts = sorted(serial for serial in extraction_conflicts if serial in {target["serial"] for target in targets} or serial in missing)
    if missing or active_conflicts:
        raise RuntimeError(f"mapeamento não exato: ausentes={len(missing)}, conflitos_ativos={len(active_conflicts)}")

    checkpoint_path = args.output / "operator_lookup_checkpoint.json"
    completed: dict[str, dict] = {}
    if checkpoint_path.exists():
        checkpoint = json.loads(checkpoint_path.read_text(encoding="utf-8"))
        completed = {row["serial"]: row for row in checkpoint.get("results", []) if row.get("status") == "ok"}
    pending = [target for target in targets if target["serial"] not in completed]
    print(json.dumps({"phase": "lookup", "targets": len(targets), "resumed": len(completed), "pending": len(pending)}), flush=True)

    processed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        future_map = {pool.submit(fetch_one, target): target for target in pending}
        for future in concurrent.futures.as_completed(future_map):
            result = future.result()
            completed[result["serial"]] = result
            processed += 1
            if processed % 100 == 0 or processed == len(pending):
                rows = [completed[key] for key in sorted(completed)]
                atomic_json(checkpoint_path, {"updated_at": datetime.now(timezone.utc).isoformat(), "results": rows})
                print(json.dumps({"completed": len(completed), "total": len(targets), "errors": sum(r["status"] != "ok" for r in rows)}), flush=True)

    results = [completed.get(target["serial"], {**target, "operator": "", "status": "missing"}) for target in targets]
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "database": str(args.database),
        "target_count": len(targets),
        "success_count": sum(row["status"] == "ok" for row in results),
        "failure_count": sum(row["status"] != "ok" for row in results),
        "operator_counts": dict(sorted(Counter(row["operator"] for row in results if row["status"] == "ok").items())),
        "results": results,
    }
    atomic_json(args.output / "operator_lookup_report.json", report)
    with (args.output / "operator_lookup_report.csv").open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=["serial", "portal_id", "operator", "status", "url", "error"])
        writer.writeheader()
        for row in results:
            writer.writerow({key: row.get(key, "") for key in writer.fieldnames})
    print(json.dumps({key: report[key] for key in ("success_count", "failure_count", "operator_counts")}, ensure_ascii=False), flush=True)
    return 0 if report["failure_count"] == 0 else 3


def apply_results(args: argparse.Namespace) -> int:
    report_path = args.output / "operator_lookup_report.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report["target_count"] != args.expected_count or report["failure_count"] != 0:
        raise RuntimeError("relatório incompleto; gravação recusada")
    lookup = {row["serial"]: clean(row["operator"]) for row in report["results"] if row["status"] == "ok"}
    now = datetime.now(timezone.utc).isoformat()
    with sqlite3.connect(args.database, timeout=30) as db:
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("BEGIN IMMEDIATE")
        rows = db.execute("SELECT id, sku, imei, raw_json FROM devices WHERE branch_id = ?", (args.branch,)).fetchall()
        if len(rows) != args.expected_count:
            raise RuntimeError(f"quantidade mudou antes da gravação: {len(rows)}")
        changed = 0
        for device_id, sku, imei, raw_text in rows:
            serial = clean(imei) or clean(sku)
            operator = lookup.get(serial)
            if not operator:
                raise RuntimeError(f"resultado ausente para {serial}")
            try:
                raw = json.loads(raw_text or "{}")
            except json.JSONDecodeError:
                raw = {}
            raw["operator"] = operator
            raw["operator_source"] = "Grupo RS / equipamentos_editar.php"
            raw["operator_verified_at"] = now
            db.execute(
                "UPDATE devices SET carrier = ?, updated_at = ?, raw_json = ? WHERE id = ?",
                (operator, now, json.dumps(raw, ensure_ascii=False, separators=(",", ":")), device_id),
            )
            changed += 1
        details = {"updated_devices": changed, "source": "Grupo RS", "report": str(report_path), "operator_counts": report["operator_counts"]}
        audit_id = str(uuid.uuid4())
        db.execute(
            "INSERT INTO audit_log (id, branch_id, action, entity_type, entity_id, operator, occurred_at, details, raw_json) VALUES (?,?,?,?,?,?,?,?,?)",
            (audit_id, args.branch, "operator_enrichment", "devices", "batch", "codex_migration", now,
             json.dumps(details, ensure_ascii=False), json.dumps(details, ensure_ascii=False, separators=(",", ":"))),
        )
        db.commit()
        integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
        blank = db.execute("SELECT COUNT(*) FROM devices WHERE branch_id=? AND TRIM(COALESCE(carrier,''))=''", (args.branch,)).fetchone()[0]
        counts = db.execute("SELECT carrier, COUNT(*) FROM devices WHERE branch_id=? GROUP BY carrier ORDER BY COUNT(*) DESC", (args.branch,)).fetchall()
    verification = {"applied_at": now, "updated": changed, "integrity": integrity, "blank_carriers": blank, "operator_counts": dict(counts)}
    atomic_json(args.output / "operator_apply_verification.json", verification)
    print(json.dumps(verification, ensure_ascii=False), flush=True)
    return 0 if integrity == "ok" and blank == 0 else 4


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("lookup", "apply"))
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--extraction", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--branch", default="imperatriz")
    parser.add_argument("--expected-count", type=int, default=3181)
    parser.add_argument("--workers", type=int, default=12)
    args = parser.parse_args()
    return lookup(args) if args.mode == "lookup" else apply_results(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(json.dumps({"ok": False, "error": f"{type(exc).__name__}: {exc}"}, ensure_ascii=False), file=sys.stderr, flush=True)
        raise
