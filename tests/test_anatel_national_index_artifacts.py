import hashlib
import json
import unittest
from collections import Counter
from pathlib import Path

from tools import build_anatel_national_index as builder


PROJECT_ROOT = Path(__file__).resolve().parents[1]
INDEX_ROOT = PROJECT_ROOT / "data" / "anatel_smp_national_index"


class NationalIndexArtifactsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest_path = INDEX_ROOT / "manifest.json"
        cls.manifest = json.loads(cls.manifest_path.read_text(encoding="utf-8"))
        cls.metadata = cls.manifest["metadata"]

    def test_manifest_provenance_hash_and_size(self) -> None:
        sidecar = (INDEX_ROOT / "manifest.sha256").read_text(encoding="ascii").split()
        self.assertEqual(len(sidecar), 3)
        self.assertEqual(sidecar[0], hashlib.sha256(self.manifest_path.read_bytes()).hexdigest().upper())
        self.assertEqual(int(sidecar[1]), self.manifest_path.stat().st_size)
        self.assertEqual(sidecar[2], "manifest.json")
        self.assertEqual(self.metadata["scope"], "Brasil")
        self.assertEqual(self.metadata["source_rows"], 3_292_893)
        self.assertEqual(self.metadata["source_zip_sha256"], "976C4BB3ABFC8F777D54D595DF1D944E12550FE653CB67EFB649ECABF8903051")
        self.assertEqual(self.metadata["source_last_modified"], "Tue, 25 Aug 2026 10:56:40 GMT")
        self.assertGreater(self.metadata["process_peak_working_set_bytes"], 0)
        self.assertEqual(self.metadata["index_zoom"], 10)
        self.assertEqual(self.metadata["cluster_zooms"], [4, 6, 8])

    def test_all_partitions_counts_bounds_and_inventory(self) -> None:
        unique_count = 0
        physical = set()
        generations: Counter[str] = Counter()
        operators: Counter[str] = Counter()
        ufs: Counter[str] = Counter()
        inventory = []
        max_station_count = 0
        max_cell_bytes = 0
        bounds = self.metadata["national_bounds"]
        for descriptor in self.manifest["cells"]:
            path = INDEX_ROOT / descriptor["path"]
            raw = path.read_bytes()
            self.assertEqual(len(raw), descriptor["bytes"])
            self.assertEqual(hashlib.sha256(raw).hexdigest().upper(), descriptor["sha256"])
            inventory.append((descriptor["path"], descriptor["sha256"], descriptor["bytes"]))
            payload = json.loads(raw)
            self.assertEqual(payload["zoom"], 10)
            self.assertEqual(payload["x"], descriptor["cell_x"])
            self.assertEqual(payload["y"], descriptor["cell_y"])
            stations = payload["stations"]
            self.assertEqual(len(stations), descriptor["cluster_count"])
            max_station_count = max(max_station_count, len(stations))
            max_cell_bytes = max(max_cell_bytes, len(raw))
            for station in stations:
                latitude = float(station["lat"])
                longitude = float(station["lng"])
                self.assertGreaterEqual(latitude, bounds["min_lat"])
                self.assertLessEqual(latitude, bounds["max_lat"])
                self.assertGreaterEqual(longitude, bounds["min_lng"])
                self.assertLessEqual(longitude, bounds["max_lng"])
                self.assertFalse(abs(latitude) < 1e-12 and abs(longitude) < 1e-12)
                self.assertEqual(builder.mercator_tile(latitude, longitude, 10), (payload["x"], payload["y"]))
                self.assertIn(station["generation"], builder.GENERATIONS)
                self.assertEqual(station["status"], "Licenciada")
                self.assertIn(station["uf"], builder.BRAZIL_UFS)
                unique_count += 1
                generations[station["generation"]] += 1
                operators[station["operator"]] += 1
                ufs[station["uf"]] += 1
                physical.add(f'{station.get("id", "")}|{station["operator"]}|{latitude:.6f}|{longitude:.6f}')
        for descriptor in self.manifest["cluster_files"].values():
            path = INDEX_ROOT / descriptor["path"]
            raw = path.read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest().upper(), descriptor["sha256"])
            inventory.append((descriptor["path"], descriptor["sha256"], descriptor["bytes"]))
            clusters = json.loads(raw)["clusters"]
            self.assertEqual(sum(int(item["cluster_count"]) for item in clusters), self.metadata["unique_station_generations"])
        inventory_hash = hashlib.sha256()
        for path, file_hash, size in sorted(inventory):
            inventory_hash.update(f"{path}|{file_hash}|{size}\n".encode("utf-8"))
        self.assertEqual(inventory_hash.hexdigest().upper(), self.metadata["index_content_sha256"])
        self.assertEqual(unique_count, self.metadata["unique_station_generations"])
        self.assertEqual(len(physical), self.metadata["unique_physical_stations"])
        self.assertEqual(dict(sorted(generations.items())), self.metadata["generation_counts"])
        self.assertEqual(dict(sorted(operators.items())), self.metadata["operator_counts"])
        self.assertEqual(dict(sorted(ufs.items())), self.metadata["uf_counts"])
        self.assertEqual(len(ufs), 27)
        for required_uf in ("AM", "MA", "DF", "SP", "RS"):
            self.assertGreater(ufs[required_uf], 0)
        self.assertEqual(max_station_count, self.metadata["max_cell_station_count"])
        self.assertEqual(max_cell_bytes, self.metadata["max_cell_bytes"])

    def test_no_build_or_backup_inside_resources(self) -> None:
        data_root = PROJECT_ROOT / "data"
        leftovers = [
            item.name for item in data_root.iterdir()
            if item.name.startswith("anatel_smp_national_index.building-")
            or item.name.startswith("anatel_smp_national_index.backup-")
        ]
        self.assertEqual(leftovers, [])


if __name__ == "__main__":
    unittest.main()
