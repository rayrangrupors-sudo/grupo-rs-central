import hashlib
import importlib.util
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
BUILDER_PATH = PROJECT_ROOT / "tools" / "build_anatel_national_index.py"
SPEC = importlib.util.spec_from_file_location("anatel_national_builder", BUILDER_PATH)
BUILDER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(BUILDER)


def station_tuple(
    key: str,
    station_id: str,
    operator: str,
    generation: str,
    latitude: float,
    longitude: float,
    city: str,
    uf: str,
    provider: str = "",
    infrastructure: str = "",
) -> tuple:
    cell_x, cell_y = BUILDER.mercator_tile(latitude, longitude, BUILDER.INDEX_ZOOM)
    return (
        key, station_id, operator, provider, "", generation, latitude, longitude,
        city, uf, "", "", "", "", "Licenciada", infrastructure,
        "", "", "", "", "", "", "", "", cell_x, cell_y,
    )


class NationalIndexBuilderTest(unittest.TestCase):
    def test_upsert_arity_and_missing_field_merge(self) -> None:
        connection = sqlite3.connect(":memory:")
        BUILDER.configure_database(connection)
        first = station_tuple("station-key", "station-id", "TIM", "4G", -5.5, -47.5, "", "MA")
        second = station_tuple(
            "station-key", "station-id", "TIM", "4G", -5.5, -47.5,
            "Cidade sintética - MA", "MA", provider="TIM", infrastructure="Greenfield",
        )
        self.assertEqual(len(first), 26)
        connection.execute(BUILDER.UPSERT_STATION, first)
        connection.execute(BUILDER.UPSERT_STATION, second)
        row = connection.execute(
            "SELECT COUNT(*), provider_name, city, infrastructure_class FROM stations"
        ).fetchone()
        self.assertEqual(row[0], 1)
        self.assertEqual(row[1:], ("TIM", "Cidade sintética - MA", "Greenfield"))
        connection.close()

    def test_small_partitioned_index_and_manifest(self) -> None:
        with tempfile.TemporaryDirectory(prefix="anatel-index-test-") as temporary:
            root = Path(temporary)
            database = root / "index.sqlite"
            output = root / "national-index-building"
            output.mkdir()
            connection = sqlite3.connect(database)
            BUILDER.configure_database(connection)
            rows = [
                station_tuple("ma-key", "ma-id", "TIM", "4G", -5.5, -47.5, "Cidade sintética - MA", "MA", "TIM"),
                station_tuple("sp-key", "sp-id", "CLARO", "5G", -23.5, -46.6, "Cidade sintética - SP", "SP", "CLARO"),
            ]
            connection.executemany(BUILDER.UPSERT_STATION, rows)
            connection.execute("INSERT INTO station_bands VALUES (?,?)", ("ma-key", "700"))
            connection.execute("INSERT INTO station_technologies VALUES (?,?)", ("sp-key", "NR"))
            connection.commit()
            connection.close()
            source = {
                "source_last_modified": "Tue, 25 Aug 2026 10:56:40 GMT",
                "source_collected_at": "2026-08-25T15:16:28Z",
                "source_zip_sha256": "A" * 64,
                "source_zip_bytes": 123,
                "source_entry": "Estacoes_SMP.csv",
                "source_rows": 2,
                "selected_rows": 2,
                "malformed_rows": 0,
                "invalid_or_outside_coordinates": 0,
                "source_generation_counts": {"4G": 1, "5G": 1},
                "unique_station_generations": 2,
            }
            result = BUILDER.build_index(database, output, source)
            manifest_path = output / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            metadata = manifest["metadata"]
            self.assertEqual(metadata["source_last_modified"], source["source_last_modified"])
            self.assertEqual(metadata["scope"], "Brasil")
            self.assertEqual(metadata["unique_station_generations"], 2)
            self.assertEqual(metadata["cell_count"], 2)
            self.assertGreaterEqual(metadata["index_file_count"], 4)
            self.assertEqual(len(metadata["index_content_sha256"]), 64)
            sidecar = (output / "manifest.sha256").read_text(encoding="ascii").split()
            self.assertEqual(sidecar[0], hashlib.sha256(manifest_path.read_bytes()).hexdigest().upper())
            self.assertEqual(int(sidecar[1]), manifest_path.stat().st_size)
            self.assertEqual(result["manifest_sha256"], sidecar[0])


if __name__ == "__main__":
    unittest.main()
