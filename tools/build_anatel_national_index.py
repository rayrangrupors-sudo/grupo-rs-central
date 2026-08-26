#!/usr/bin/env python3
"""Gera um índice nacional particionado das ERBs SMP licenciadas da Anatel.

O CSV é lido diretamente do ZIP em streaming. Uma base SQLite temporária faz a
deduplicação em disco; nenhuma lista com as mais de três milhões de linhas é
mantida em memória. A saída final é particionada por tiles Web Mercator z8.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import shutil
import sqlite3
import sys
import tempfile
import time
import unicodedata
import zipfile
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


INDEX_ZOOM = 10
CLUSTER_ZOOMS = (4, 6, 8)
GENERATIONS = {"2G", "3G", "4G", "5G"}
BRAZIL_UFS = {
    "AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA",
    "MT", "MS", "MG", "PA", "PB", "PR", "PE", "PI", "RJ", "RN",
    "RS", "RO", "RR", "SC", "SP", "SE", "TO",
}
BRAZIL_BOUNDS = {"min_lat": -34.0, "max_lat": 6.0, "min_lng": -74.5, "max_lng": -28.0}
SOURCE_URL = "https://www.anatel.gov.br/dadosabertos/paineis_de_dados/outorga_e_licenciamento/estacoes_smp.zip"


def normalized_header(value: str) -> str:
    decomposed = unicodedata.normalize("NFD", (value or "").strip())
    return "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn")


def normalized_operator(value: str) -> str:
    upper = (value or "").strip().upper()
    if "CLARO" in upper:
        return "CLARO"
    if "TIM" in upper:
        return "TIM"
    if "VIVO" in upper or "TELEFONICA" in upper:
        return "VIVO"
    return "OUTRAS"


def clean(value: object) -> str:
    return str(value or "").strip()


def parse_float(value: str) -> float | None:
    try:
        result = float(clean(value).replace(",", "."))
    except ValueError:
        return None
    return result if math.isfinite(result) else None


def valid_national_coordinate(latitude: float, longitude: float, uf: str) -> bool:
    return (
        uf in BRAZIL_UFS
        and BRAZIL_BOUNDS["min_lat"] <= latitude <= BRAZIL_BOUNDS["max_lat"]
        and BRAZIL_BOUNDS["min_lng"] <= longitude <= BRAZIL_BOUNDS["max_lng"]
        and not (abs(latitude) < 1e-12 and abs(longitude) < 1e-12)
    )


def mercator_tile(latitude: float, longitude: float, zoom: int) -> tuple[int, int]:
    safe_lat = max(-85.05112878, min(85.05112878, latitude))
    count = 1 << zoom
    x = int(math.floor((longitude + 180.0) / 360.0 * count))
    lat_rad = math.radians(safe_lat)
    y = int(math.floor((1.0 - math.log(math.tan(lat_rad) + 1.0 / math.cos(lat_rad)) / math.pi) / 2.0 * count))
    return max(0, min(count - 1, x)), max(0, min(count - 1, y))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def process_memory_metrics() -> dict[str, int]:
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes

        class ProcessMemoryCounters(ctypes.Structure):
            _fields_ = [
                ("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t),
            ]

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        psapi = ctypes.WinDLL("psapi", use_last_error=True)
        kernel32.GetCurrentProcess.restype = wintypes.HANDLE
        psapi.GetProcessMemoryInfo.argtypes = [
            wintypes.HANDLE,
            ctypes.POINTER(ProcessMemoryCounters),
            wintypes.DWORD,
        ]
        psapi.GetProcessMemoryInfo.restype = wintypes.BOOL
        counters = ProcessMemoryCounters()
        counters.cb = ctypes.sizeof(counters)
        handle = kernel32.GetCurrentProcess()
        if psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
            return {
                "process_peak_working_set_bytes": int(counters.PeakWorkingSetSize),
                "process_working_set_bytes_at_manifest": int(counters.WorkingSetSize),
            }
    return {"process_peak_working_set_bytes": -1, "process_working_set_bytes_at_manifest": -1}


def configure_database(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        PRAGMA temp_store=FILE;
        PRAGMA locking_mode=EXCLUSIVE;
        PRAGMA cache_size=-65536;
        CREATE TABLE stations (
            station_key TEXT PRIMARY KEY,
            station_id TEXT NOT NULL,
            operator TEXT NOT NULL,
            provider_name TEXT NOT NULL,
            entity TEXT NOT NULL,
            generation TEXT NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            city TEXT NOT NULL,
            uf TEXT NOT NULL,
            district TEXT NOT NULL,
            address TEXT NOT NULL,
            address_number TEXT NOT NULL,
            address_complement TEXT NOT NULL,
            status TEXT NOT NULL,
            infrastructure_class TEXT NOT NULL,
            first_license_date TEXT NOT NULL,
            license_date TEXT NOT NULL,
            license_valid_until TEXT NOT NULL,
            frequency_mhz TEXT NOT NULL,
            frequency_initial_mhz TEXT NOT NULL,
            frequency_final_mhz TEXT NOT NULL,
            frequency_tx_mhz TEXT NOT NULL,
            frequency_rx_mhz TEXT NOT NULL,
            cell_x INTEGER NOT NULL,
            cell_y INTEGER NOT NULL
        );
        CREATE TABLE station_bands (
            station_key TEXT NOT NULL,
            value TEXT NOT NULL,
            PRIMARY KEY (station_key, value)
        ) WITHOUT ROWID;
        CREATE TABLE station_technologies (
            station_key TEXT NOT NULL,
            value TEXT NOT NULL,
            PRIMARY KEY (station_key, value)
        ) WITHOUT ROWID;
        """
    )


UPSERT_STATION = """
INSERT INTO stations VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(station_key) DO UPDATE SET
    provider_name=CASE WHEN stations.provider_name='' THEN excluded.provider_name ELSE stations.provider_name END,
    entity=CASE WHEN stations.entity='' THEN excluded.entity ELSE stations.entity END,
    city=CASE WHEN stations.city='' THEN excluded.city ELSE stations.city END,
    uf=CASE WHEN stations.uf='' THEN excluded.uf ELSE stations.uf END,
    district=CASE WHEN stations.district='' THEN excluded.district ELSE stations.district END,
    address=CASE WHEN stations.address='' THEN excluded.address ELSE stations.address END,
    address_number=CASE WHEN stations.address_number='' THEN excluded.address_number ELSE stations.address_number END,
    address_complement=CASE WHEN stations.address_complement='' THEN excluded.address_complement ELSE stations.address_complement END,
    infrastructure_class=CASE WHEN stations.infrastructure_class='' THEN excluded.infrastructure_class ELSE stations.infrastructure_class END,
    first_license_date=CASE WHEN stations.first_license_date='' THEN excluded.first_license_date ELSE stations.first_license_date END,
    license_date=CASE WHEN stations.license_date='' THEN excluded.license_date ELSE stations.license_date END,
    license_valid_until=CASE WHEN stations.license_valid_until='' THEN excluded.license_valid_until ELSE stations.license_valid_until END,
    frequency_mhz=CASE WHEN stations.frequency_mhz='' THEN excluded.frequency_mhz ELSE stations.frequency_mhz END,
    frequency_initial_mhz=CASE WHEN stations.frequency_initial_mhz='' THEN excluded.frequency_initial_mhz ELSE stations.frequency_initial_mhz END,
    frequency_final_mhz=CASE WHEN stations.frequency_final_mhz='' THEN excluded.frequency_final_mhz ELSE stations.frequency_final_mhz END,
    frequency_tx_mhz=CASE WHEN stations.frequency_tx_mhz='' THEN excluded.frequency_tx_mhz ELSE stations.frequency_tx_mhz END,
    frequency_rx_mhz=CASE WHEN stations.frequency_rx_mhz='' THEN excluded.frequency_rx_mhz ELSE stations.frequency_rx_mhz END
"""


def required_columns(headers: list[str]) -> dict[str, str]:
    normalized = {normalized_header(header): header for header in headers}
    required = [
        "Numero Estacao", "Frequencia (MHz)", "Banda_MHZ", "Frequencia Inicial",
        "Frequencia Final", "FreqTxMHz", "FreqRxMHz", "Data Validade", "Entidade",
        "Tecnologia", "Tipo de Tecnologia 5G", "Latitude decimal", "Longitude decimal",
        "EnderecoEstacao", "EndBairro", "EndNumero", "EndComplemento", "ClassInfraFisica",
        "Data Primeiro Licenciamento", "Data Licenciamento", "Situacao", "Empresa Estacao",
        "Faixa Estacao", "Subfaixa Estacao", "Geracao", "Municipio-UF", "UF",
    ]
    missing = [name for name in required if name not in normalized]
    if missing:
        raise RuntimeError("Formato oficial alterado; colunas ausentes: " + ", ".join(missing))
    return {name: normalized[name] for name in required}


def row_value(row: dict[str, str], columns: dict[str, str], name: str) -> str:
    return clean(row.get(columns[name], ""))


def flush_batches(
    connection: sqlite3.Connection,
    stations: list[tuple],
    bands: list[tuple[str, str]],
    technologies: list[tuple[str, str]],
) -> None:
    with connection:
        connection.executemany(UPSERT_STATION, stations)
        connection.executemany("INSERT OR IGNORE INTO station_bands VALUES (?,?)", bands)
        connection.executemany("INSERT OR IGNORE INTO station_technologies VALUES (?,?)", technologies)
    stations.clear()
    bands.clear()
    technologies.clear()


def ingest_csv(zip_path: Path, database_path: Path) -> dict:
    connection = sqlite3.connect(database_path)
    configure_database(connection)
    source_rows = selected_rows = malformed_rows = invalid_coordinates = 0
    source_generation_counts: Counter[str] = Counter()
    station_batch: list[tuple] = []
    band_batch: list[tuple[str, str]] = []
    technology_batch: list[tuple[str, str]] = []
    started = time.monotonic()

    with zipfile.ZipFile(zip_path) as archive:
        entries = [item for item in archive.infolist() if item.filename.lower().endswith(".csv")]
        if not entries:
            raise RuntimeError("O ZIP oficial não contém CSV.")
        entry = entries[0]
        with archive.open(entry, "r") as binary, __import__("io").TextIOWrapper(binary, encoding="utf-8-sig", newline="") as text:
            reader = csv.DictReader(text, delimiter=";", quotechar='"')
            if reader.fieldnames is None:
                raise RuntimeError("CSV oficial sem cabeçalho.")
            columns = required_columns(reader.fieldnames)
            for row in reader:
                source_rows += 1
                try:
                    generation = row_value(row, columns, "Geracao").upper()
                    status = row_value(row, columns, "Situacao").upper()
                    if generation not in GENERATIONS or status != "LICENCIADA":
                        continue
                    latitude = parse_float(row_value(row, columns, "Latitude decimal"))
                    longitude = parse_float(row_value(row, columns, "Longitude decimal"))
                    uf = row_value(row, columns, "UF").upper()
                    if latitude is None or longitude is None or not valid_national_coordinate(latitude, longitude, uf):
                        invalid_coordinates += 1
                        continue
                    selected_rows += 1
                    source_generation_counts[generation] += 1
                    provider_name = row_value(row, columns, "Empresa Estacao")
                    operator = normalized_operator(provider_name)
                    station_id = row_value(row, columns, "Numero Estacao")
                    latitude = round(latitude, 6)
                    longitude = round(longitude, 6)
                    cell_x, cell_y = mercator_tile(latitude, longitude, INDEX_ZOOM)
                    station_key = f"{station_id}|{operator}|{generation}|{latitude:.6f}|{longitude:.6f}"
                    station_batch.append((
                        station_key, station_id, operator, provider_name,
                        row_value(row, columns, "Entidade"), generation, latitude, longitude,
                        row_value(row, columns, "Municipio-UF"), uf,
                        row_value(row, columns, "EndBairro"), row_value(row, columns, "EnderecoEstacao"),
                        row_value(row, columns, "EndNumero"), row_value(row, columns, "EndComplemento"),
                        "Licenciada", row_value(row, columns, "ClassInfraFisica"),
                        row_value(row, columns, "Data Primeiro Licenciamento"),
                        row_value(row, columns, "Data Licenciamento"), row_value(row, columns, "Data Validade"),
                        row_value(row, columns, "Frequencia (MHz)"), row_value(row, columns, "Frequencia Inicial"),
                        row_value(row, columns, "Frequencia Final"), row_value(row, columns, "FreqTxMHz"),
                        row_value(row, columns, "FreqRxMHz"), cell_x, cell_y,
                    ))
                    for band in (
                        row_value(row, columns, "Faixa Estacao"),
                        row_value(row, columns, "Subfaixa Estacao"),
                        row_value(row, columns, "Banda_MHZ"),
                    ):
                        if band:
                            band_batch.append((station_key, band))
                    for technology in (
                        row_value(row, columns, "Tecnologia"),
                        row_value(row, columns, "Tipo de Tecnologia 5G"),
                    ):
                        if technology:
                            technology_batch.append((station_key, technology))
                except (KeyError, TypeError, ValueError):
                    malformed_rows += 1
                if len(station_batch) >= 5000:
                    flush_batches(connection, station_batch, band_batch, technology_batch)
                if source_rows % 250000 == 0:
                    elapsed = max(time.monotonic() - started, 0.001)
                    print(f"PROGRESS rows={source_rows} selected={selected_rows} rows_per_second={source_rows / elapsed:.0f}", flush=True)
            if station_batch:
                flush_batches(connection, station_batch, band_batch, technology_batch)

    connection.executescript(
        """
        CREATE INDEX stations_cell_idx ON stations(cell_x, cell_y);
        CREATE INDEX stations_city_idx ON stations(city);
        CREATE INDEX stations_filter_idx ON stations(operator, generation, status);
        ANALYZE;
        """
    )
    unique_station_generations = connection.execute("SELECT COUNT(*) FROM stations").fetchone()[0]
    connection.close()
    return {
        "source_entry": entry.filename,
        "source_rows": source_rows,
        "selected_rows": selected_rows,
        "malformed_rows": malformed_rows,
        "invalid_or_outside_coordinates": invalid_coordinates,
        "source_generation_counts": dict(sorted(source_generation_counts.items())),
        "unique_station_generations": unique_station_generations,
    }


def load_values(connection: sqlite3.Connection, table: str, station_keys: list[str]) -> dict[str, list[str]]:
    result: dict[str, list[str]] = defaultdict(list)
    for offset in range(0, len(station_keys), 800):
        keys = station_keys[offset:offset + 800]
        placeholders = ",".join("?" for _ in keys)
        for station_key, value in connection.execute(
            f"SELECT station_key, value FROM {table} WHERE station_key IN ({placeholders}) ORDER BY value",
            keys,
        ):
            result[station_key].append(value)
    return result


def station_payload(row: sqlite3.Row, bands: list[str], technologies: list[str]) -> dict:
    payload = {
        "id": row["station_id"], "operator": row["operator"], "provider_name": row["provider_name"],
        "entity": row["entity"], "generation": row["generation"], "lat": row["lat"], "lng": row["lng"],
        "city": row["city"], "uf": row["uf"], "district": row["district"], "address": row["address"],
        "address_number": row["address_number"], "address_complement": row["address_complement"],
        "status": row["status"], "infrastructure_class": row["infrastructure_class"],
        "first_license_date": row["first_license_date"], "license_date": row["license_date"],
        "license_valid_until": row["license_valid_until"], "frequency_mhz": row["frequency_mhz"],
        "frequency_initial_mhz": row["frequency_initial_mhz"], "frequency_final_mhz": row["frequency_final_mhz"],
        "frequency_tx_mhz": row["frequency_tx_mhz"], "frequency_rx_mhz": row["frequency_rx_mhz"],
        "bands": bands, "technologies": technologies,
    }
    # JSON esparso: valores ausentes continuam semanticamente ausentes e não
    # ocupam bytes repetidos em centenas de milhares de registros.
    required = {"id", "operator", "generation", "lat", "lng", "status", "city", "uf"}
    return {
        key: value for key, value in payload.items()
        if key in required or value not in ("", [], None)
    }


def new_aggregate(zoom: int, x: int, y: int) -> dict:
    return {
        "zoom": zoom, "x": x, "y": y, "count": 0, "lat_sum": 0.0, "lng_sum": 0.0,
        "min_lat": 90.0, "max_lat": -90.0, "min_lng": 180.0, "max_lng": -180.0,
        "operators": set(), "generations": set(), "statuses": set(), "cities": set(), "ufs": set(),
        "facets": Counter(), "physical": set(),
    }


def add_to_aggregate(aggregate: dict, row: sqlite3.Row) -> None:
    aggregate["count"] += 1
    aggregate["lat_sum"] += row["lat"]
    aggregate["lng_sum"] += row["lng"]
    aggregate["min_lat"] = min(aggregate["min_lat"], row["lat"])
    aggregate["max_lat"] = max(aggregate["max_lat"], row["lat"])
    aggregate["min_lng"] = min(aggregate["min_lng"], row["lng"])
    aggregate["max_lng"] = max(aggregate["max_lng"], row["lng"])
    aggregate["operators"].add(row["operator"])
    aggregate["generations"].add(row["generation"])
    aggregate["statuses"].add(row["status"])
    if row["city"]:
        aggregate["cities"].add(row["city"])
    if row["uf"]:
        aggregate["ufs"].add(row["uf"])
    aggregate["facets"][f'{row["operator"]}|{row["generation"]}|{row["status"]}'] += 1
    aggregate["physical"].add(f'{row["station_id"]}|{row["operator"]}|{row["lat"]:.6f}|{row["lng"]:.6f}')


def aggregate_payload(aggregate: dict, *, cluster: bool) -> dict:
    count = aggregate["count"]
    payload = {
        "id": f'cluster-z{aggregate["zoom"]}-{aggregate["x"]}-{aggregate["y"]}',
        "is_index_cluster": cluster,
        "cluster_count": count,
        "physical_count": len(aggregate["physical"]),
        "cell_zoom": aggregate["zoom"], "cell_x": aggregate["x"], "cell_y": aggregate["y"],
        "lat": round(aggregate["lat_sum"] / max(count, 1), 6),
        "lng": round(aggregate["lng_sum"] / max(count, 1), 6),
        "bbox": {
            "min_lat": aggregate["min_lat"], "max_lat": aggregate["max_lat"],
            "min_lng": aggregate["min_lng"], "max_lng": aggregate["max_lng"],
        },
        "operators": sorted(aggregate["operators"]), "generations": sorted(aggregate["generations"]),
        "statuses": sorted(aggregate["statuses"]), "cities": sorted(aggregate["cities"]),
        "ufs": sorted(aggregate["ufs"]), "facets": dict(sorted(aggregate["facets"].items())),
    }
    return payload


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(payload, stream, ensure_ascii=False, separators=(",", ":"))


def build_index(database_path: Path, output_building: Path, source_metadata: dict) -> dict:
    connection = sqlite3.connect(database_path)
    connection.row_factory = sqlite3.Row
    cells = connection.execute("SELECT DISTINCT cell_x, cell_y FROM stations ORDER BY cell_x, cell_y").fetchall()
    cell_summaries: list[dict] = []
    cluster_aggregates: dict[int, dict[tuple[int, int], dict]] = {zoom: {} for zoom in CLUSTER_ZOOMS}
    generation_counts: Counter[str] = Counter()
    operator_counts: Counter[str] = Counter()
    status_counts: Counter[str] = Counter()
    uf_counts: Counter[str] = Counter()
    unique_physical_stations = 0
    file_inventory: list[tuple[str, str, int]] = []
    max_cell_station_count = 0
    max_cell_bytes = 0
    started = time.monotonic()

    for cell_index, (cell_x, cell_y) in enumerate(cells, start=1):
        rows = connection.execute(
            "SELECT * FROM stations WHERE cell_x=? AND cell_y=? ORDER BY station_key",
            (cell_x, cell_y),
        ).fetchall()
        keys = [row["station_key"] for row in rows]
        bands = load_values(connection, "station_bands", keys)
        technologies = load_values(connection, "station_technologies", keys)
        stations = [station_payload(row, bands.get(row["station_key"], []), technologies.get(row["station_key"], [])) for row in rows]
        relative_path = f"cells/z{INDEX_ZOOM}/{cell_x}/{cell_y}.json"
        cell_path = output_building / relative_path
        write_json(cell_path, {"schema_version": 1, "zoom": INDEX_ZOOM, "x": cell_x, "y": cell_y, "stations": stations})
        cell_hash = sha256_file(cell_path)
        file_inventory.append((relative_path, cell_hash, cell_path.stat().st_size))
        max_cell_station_count = max(max_cell_station_count, len(rows))
        max_cell_bytes = max(max_cell_bytes, cell_path.stat().st_size)

        cell_aggregate = new_aggregate(INDEX_ZOOM, cell_x, cell_y)
        for row in rows:
            add_to_aggregate(cell_aggregate, row)
            generation_counts[row["generation"]] += 1
            operator_counts[row["operator"]] += 1
            status_counts[row["status"]] += 1
            uf_counts[row["uf"]] += 1
            for zoom in CLUSTER_ZOOMS:
                cluster_x, cluster_y = mercator_tile(row["lat"], row["lng"], zoom)
                aggregate = cluster_aggregates[zoom].setdefault((cluster_x, cluster_y), new_aggregate(zoom, cluster_x, cluster_y))
                add_to_aggregate(aggregate, row)
        unique_physical_stations += len(cell_aggregate["physical"])
        summary = aggregate_payload(cell_aggregate, cluster=True)
        summary["path"] = relative_path
        summary["sha256"] = cell_hash
        summary["bytes"] = cell_path.stat().st_size
        cell_summaries.append(summary)
        if cell_index % 100 == 0 or cell_index == len(cells):
            print(f"INDEX_PROGRESS cells={cell_index}/{len(cells)} elapsed_seconds={time.monotonic() - started:.1f}", flush=True)

    cluster_files: dict[str, dict] = {}
    for zoom, aggregates in cluster_aggregates.items():
        entries = [aggregate_payload(aggregates[key], cluster=True) for key in sorted(aggregates)]
        relative_path = f"clusters/z{zoom}.json"
        cluster_path = output_building / relative_path
        write_json(cluster_path, {"schema_version": 1, "zoom": zoom, "clusters": entries})
        cluster_hash = sha256_file(cluster_path)
        file_inventory.append((relative_path, cluster_hash, cluster_path.stat().st_size))
        cluster_files[str(zoom)] = {
            "path": relative_path, "sha256": cluster_hash, "bytes": cluster_path.stat().st_size,
            "clusters": len(entries),
        }

    inventory_digest = hashlib.sha256()
    for relative_path, file_hash, size in sorted(file_inventory):
        inventory_digest.update(f"{relative_path}|{file_hash}|{size}\n".encode("utf-8"))
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    memory_metrics = process_memory_metrics()
    metadata = {
        "provider": "Agência Nacional de Telecomunicações - Anatel",
        "dataset": "Estações do Serviço Móvel Pessoal - SMP",
        "source_url": SOURCE_URL,
        "source_last_modified": source_metadata["source_last_modified"],
        "source_collected_at": source_metadata["source_collected_at"],
        "source_zip_sha256": source_metadata["source_zip_sha256"],
        "source_zip_bytes": source_metadata["source_zip_bytes"],
        "source_entry": source_metadata["source_entry"],
        "generated_at": generated_at,
        "schema_version": 3,
        "index_version": "anatel-smp-national-webmercator-z10-v2",
        "index_content_sha256": inventory_digest.hexdigest().upper(),
        "scope": "Brasil",
        "coverage": "Território brasileiro por UF e limites geográficos documentados",
        "selection_rule": "UF oficial brasileira; situação LICENCIADA; gerações 2G/3G/4G/5G; coordenadas decimais válidas dentro dos limites nacionais documentados",
        "source_rows": source_metadata["source_rows"],
        "selected_rows": source_metadata["selected_rows"],
        "malformed_rows": source_metadata["malformed_rows"],
        "invalid_or_outside_coordinates": source_metadata["invalid_or_outside_coordinates"],
        "unique_station_generations": source_metadata["unique_station_generations"],
        "unique_physical_stations": unique_physical_stations,
        "source_generation_counts": source_metadata["source_generation_counts"],
        "generation_counts": dict(sorted(generation_counts.items())),
        "operator_counts": dict(sorted(operator_counts.items())),
        "status_counts": dict(sorted(status_counts.items())),
        "uf_counts": dict(sorted(uf_counts.items())),
        "generations": sorted(GENERATIONS),
        "status": "Licenciada",
        "national_bounds": BRAZIL_BOUNDS,
        "index_zoom": INDEX_ZOOM,
        "cluster_zooms": list(CLUSTER_ZOOMS),
        "cell_count": len(cell_summaries),
        "index_file_count": len(file_inventory),
        "index_bytes": sum(item[2] for item in file_inventory),
        "max_cell_station_count": max_cell_station_count,
        "max_cell_bytes": max_cell_bytes,
        "memory_policy": "SQLite temporário em disco; cache de páginas SQLite configurado para 64 MiB; lotes de 5.000 linhas; runtime carrega somente células visíveis/vizinhas com LRU limitado",
        **memory_metrics,
    }
    manifest = {
        "schema_version": 3,
        "metadata": metadata,
        "cells": cell_summaries,
        "cluster_files": cluster_files,
    }
    manifest_path = output_building / "manifest.json"
    write_json(manifest_path, manifest)
    manifest_hash = sha256_file(manifest_path)
    (output_building / "manifest.sha256").write_text(
        f"{manifest_hash} {manifest_path.stat().st_size} manifest.json\n",
        encoding="ascii",
        newline="\n",
    )
    connection.close()
    return {"metadata": metadata, "manifest_sha256": manifest_hash}


def safe_replace_directory(building: Path, output: Path, work_root: Path) -> Path | None:
    work_root = work_root.resolve()
    building = building.resolve()
    output = output.resolve()
    if building.parent != work_root or building.name != "national-index-building":
        raise RuntimeError("Diretório temporário fora do destino seguro.")
    backup = None
    if output.exists():
        backup_root = Path(tempfile.gettempdir()).resolve() / "grupo-rs-anatel-national-backups"
        backup_root.mkdir(parents=True, exist_ok=True)
        backup = backup_root / (output.name + ".backup-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
        shutil.move(str(output), str(backup))
    shutil.move(str(building), str(output))
    return backup


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zip", required=True, type=Path, help="ZIP oficial estacoes_smp.zip já preservado")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "data" / "anatel_smp_national_index")
    parser.add_argument("--audit-json", type=Path, default=Path(__file__).resolve().parents[1] / "docs" / "anatel_smp_audit_2026-08-25.json")
    parser.add_argument("--keep-sqlite", action="store_true")
    args = parser.parse_args()
    zip_path = args.zip.resolve()
    output = args.output.resolve()
    if not zip_path.is_file():
        raise FileNotFoundError(zip_path)
    if output == output.parent or output.name in {"", ".", ".."}:
        raise RuntimeError("Destino nacional inseguro.")
    output.parent.mkdir(parents=True, exist_ok=True)
    work_dir = Path(tempfile.mkdtemp(prefix="grupo-rs-anatel-national-"))
    building = work_dir / "national-index-building"
    building.mkdir(parents=True)
    database_path = work_dir / "anatel_smp_index.sqlite"
    try:
        source_zip_hash = sha256_file(zip_path)
        audited: dict = {}
        if args.audit_json.is_file():
            audited = json.loads(args.audit_json.read_text(encoding="utf-8"))
            if clean(audited.get("source_zip_sha256")).upper() != source_zip_hash:
                raise RuntimeError("O hash do ZIP diverge da auditoria informada.")
        source_info = {
            "source_zip_sha256": source_zip_hash,
            "source_zip_bytes": zip_path.stat().st_size,
            "source_last_modified": clean(audited.get("source_last_modified")),
            "source_collected_at": datetime.fromtimestamp(zip_path.stat().st_mtime, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        if not source_info["source_last_modified"]:
            raise RuntimeError("Data Last-Modified oficial ausente; informe um arquivo de auditoria válido.")
        ingestion = ingest_csv(zip_path, database_path)
        source_info.update(ingestion)
        result = build_index(database_path, building, source_info)
        backup = safe_replace_directory(building, output, work_dir)
        summary = {
            "ok": True,
            "output": str(output),
            "backup": str(backup) if backup else "",
            "manifest_sha256": result["manifest_sha256"],
            **result["metadata"],
        }
        print("RESULT " + json.dumps(summary, ensure_ascii=False, separators=(",", ":")), flush=True)
        return 0
    finally:
        if not args.keep_sqlite and database_path.exists():
            database_path.unlink()
        try:
            work_dir.rmdir()
        except OSError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
