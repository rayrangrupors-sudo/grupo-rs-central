import hashlib
import struct
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = PROJECT_ROOT / "assets" / "maps" / "erb_markers_v3"
PRODUCTION_ROOT = ASSET_ROOT / "production"
COMPACT_EXPECTED = {
    "compact/erb-marker-claro-v3.png": (6421, "7865CD2E7E8B4B0B7074E0E3921BF551742D6F8F1216BF21E09AAF12568AF784"),
    "compact/erb-marker-neutro-v3.png": (6419, "54C8C574E9DE5AB52A1B781CDA3E024F5D022246665A082A839C4D780AADD777"),
    "compact/erb-marker-tim-v3.png": (6423, "E3E124E7F971A379BF7992121A99C9D8B1ED69710A0716F20B160D7A06E68BCA"),
    "compact/erb-marker-vivo-v3.png": (6408, "AC738939A76BCE1D87BF34A796DF58D805A99D032B18774689FB10241C3B9FA9"),
}
SELECTED_EXPECTED = {
    "selected/erb-marker-claro-v3-selected.png": (7352, "08C86110A072F0C3FE274E05C3CE2A64503CEB61964EAECF6CB2C1D167983A8C"),
    "selected/erb-marker-neutro-v3-selected.png": (7336, "35AE03E6F4F873B44190EC14574352DB0D6DA04B13F685EC37D3948FFE8552C2"),
    "selected/erb-marker-tim-v3-selected.png": (7209, "B7B86E7FCA35667586BB56D6FC3329B1C9BCDDC718801B97299E9E28868042A1"),
    "selected/erb-marker-vivo-v3-selected.png": (7257, "12574E32F8E2564AC6DF8F7EA8061624A2ECB5808786AEF5CC79F5B1B39BEB5B"),
}


class ErbMarkerAssetsTest(unittest.TestCase):
    def test_only_production_assets_are_referenced_and_valid(self) -> None:
        canvas = (PROJECT_ROOT / "src" / "features" / "big_map" / "big_map_canvas.gd").read_text(encoding="utf-8")
        for name, (expected_size, expected_hash) in (COMPACT_EXPECTED | SELECTED_EXPECTED).items():
            path = PRODUCTION_ROOT / name
            raw = path.read_bytes()
            self.assertEqual(len(raw), expected_size)
            self.assertEqual(hashlib.sha256(raw).hexdigest().upper(), expected_hash)
            self.assertEqual(raw[:8], b"\x89PNG\r\n\x1a\n")
            width, height, bit_depth, color_type = struct.unpack(">IIBB", raw[16:26])
            self.assertEqual((width, height, bit_depth, color_type), (256, 256, 8, 6))
            sidecar = path.with_suffix(path.suffix + ".import")
            self.assertTrue(sidecar.is_file())
            self.assertIn(
                f'source_file="res://assets/maps/erb_markers_v3/production/{name}"',
                sidecar.read_text(encoding="utf-8"),
            )
        for name in COMPACT_EXPECTED:
            self.assertIn(f"res://assets/maps/erb_markers_v3/production/{name}", canvas)
        self.assertEqual(canvas.count("res://assets/maps/erb_markers_v3/production/compact/"), 4)
        self.assertNotIn("erb_markers_v1", canvas)
        self.assertNotIn("erb_markers_v2/", canvas)
        self.assertNotIn("erb_markers_v2r1", canvas)
        self.assertNotIn("erb_markers_v3/review", canvas)
        self.assertNotIn("erb_markers_v3/production/selected", canvas)
        self.assertNotIn("debug-alpha", canvas)
        self.assertNotIn("test-alpha", canvas)

    def test_export_excludes_non_production_candidates(self) -> None:
        preset = (PROJECT_ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        for pattern in (
            "assets/maps/erb_markers_v1/**",
            "assets/maps/erb_markers_v2/**",
            "assets/maps/erb_markers_v2r1/**",
            "assets/maps/erb_markers_v3/production/selected/**",
            "assets/maps/erb_markers_v3/review/**",
            "data/anatel_smp_national_index.backup-*/**",
            "data/anatel_smp_national_index.building-*/**",
            "**/__pycache__/**",
            "tools/__pycache__/**",
            "**/*.pyc",
            "*.pyc",
        ):
            self.assertIn(pattern, preset)


if __name__ == "__main__":
    unittest.main()
