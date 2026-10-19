"""Reproducible native MAP composer tests: no game assets, Wine or network."""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[1] / "native_map_composer.py"
SPEC = importlib.util.spec_from_file_location("openlrr_native_map_composer", SOURCE)
composer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(composer)


class NativeMapComposerTests(unittest.TestCase):
    def example(self):
        return composer.generate("CrystalFrontier", 24, 20, 1989, 12)

    def test_binary_header_roundtrip_and_exact_native_dimensions(self):
        p = self.example()
        values = composer.tilemap(p, "terrain")
        raw = composer.encode_map(24, 20, values)
        self.assertEqual(raw[:4], b"MAP ")
        remaining, x, y = struct.unpack("<III", raw[4:16])
        self.assertEqual((x, y), (25, 21))
        self.assertEqual(remaining, len(raw) - 8)
        self.assertEqual(len(raw), 16 + 25 * 21 * 2)
        decoded = composer.decode_map(raw)
        self.assertEqual(decoded["cells"], values)
        self.assertEqual(decoded["width"], 24)
        self.assertEqual(decoded["height"], 20)

    def test_all_five_layers_have_same_geometry_and_safe_codes(self):
        p = self.example()
        for kind in composer.MAP_NAMES.values():
            with self.subTest(kind=kind):
                original = composer.tilemap(p, kind)
                raw = composer.encode_map(p["width"], p["height"], original)
                self.assertEqual(composer.decode_map(raw)["cells"], original)
                if kind == "cryore":
                    self.assertTrue(set(original).issubset({0, 1, 2}))
                    self.assertEqual(original.count(1), 12)
                if kind == "predug":
                    self.assertTrue(set(original).issubset({0, 1}))
                if kind == "surface":
                    self.assertEqual(set(original), {8})
                if kind == "terrain":
                    self.assertTrue(set(original).issubset({1, 2, 3, 4, 8, 10}))

    def test_seed_reproducible_and_different_seeds_produce_different_maps(self):
        a = self.example()
        b = composer.generate("CrystalFrontier", 24, 20, 1989, 12)
        c = composer.generate("CrystalFrontier", 24, 20, 1990, 12)
        self.assertEqual(a, b)
        self.assertNotEqual(a["rows"], c["rows"])

    def test_draft_pack_contains_valid_native_binary_and_review_only_cfg(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "CrystalFrontier"
            draft = self.example()
            with mock.patch.object(composer.os, "system",
                                   side_effect=AssertionError("no executable launch")):
                result = composer.write_pack(dest, draft)
            self.assertFalse(result["complete_playable_mission"])
            self.assertFalse(result["automatic_install_allowed"])
            self.assertTrue(result["native_map_binary_roundtrip_validated"])
            self.assertEqual(len(result["generated_files"]), 8)
            hashes = json.loads((dest / "SHA256SUMS.json").read_text())
            for key, expected in hashes.items():
                self.assertEqual(hashlib.sha256((dest / key).read_bytes()).hexdigest(),
                                 expected)
            snippet = (dest / "LEVEL-CONFIG-SNIPPET.txt").read_text()
            self.assertIn("PredugMap", snippet)
            self.assertIn("SurfaceMap", snippet)
            self.assertIn("TerrainMap", snippet)
            self.assertIn("NOT a complete Lego.cfg level", snippet)
            with self.assertRaisesRegex(ValueError, "must never be replaced"):
                composer.write_pack(dest, draft)

    def test_crystal_objective_exceeds_resources_blocked(self):
        p = self.example()
        p["crystal_goal"] = 100
        with self.assertRaisesRegex(ValueError, "exceeds"):
            composer.validate_blueprint(p)

    def test_crystals_behind_undiggable_wall_blocked(self):
        p = self.example()
        rows = [["#" for _ in range(24)] for _ in range(20)]
        rows[10][12] = "."
        rows[2][2] = "c"
        p["rows"] = ["".join(row) for row in rows]
        p["start"] = [12, 10]
        p["crystal_goal"] = 1
        with self.assertRaisesRegex(ValueError, "unreachable"):
            composer.validate_blueprint(p)

    def test_disconnected_exposed_room_rejected(self):
        p = self.example()
        rows = [list(r) for r in p["rows"]]
        rows[2][2] = "."
        p["rows"] = ["".join(row) for row in rows]
        with self.assertRaisesRegex(ValueError, "Disconnected"):
            composer.validate_blueprint(p)

    def test_unsafe_terrain_codes_or_install_request_refused(self):
        p = self.example()
        p["native_install_authorized"] = True
        with self.assertRaisesRegex(ValueError, "installation authority"):
            composer.validate_blueprint(p)
        p = self.example()
        p["rows"][0] = "0" + p["rows"][0][1:]
        with self.assertRaisesRegex(ValueError, "Invalid native map tiles"):
            composer.validate_blueprint(p)

    def test_native_map_rejects_corrupt_magic_length_and_dimensions(self):
        blob = composer.encode_map(24, 20, [0] * (25 * 21))
        for bad in (
            b"BAD!" + blob[4:],
            blob[:-2],
            blob[:4] + struct.pack("<I", 0) + blob[8:],
            blob[:8] + struct.pack("<I", 100000) + blob[12:],
        ):
            with self.subTest(blob=bad[:16]), self.assertRaisesRegex(ValueError, "MAP|dimensions"):
                composer.decode_map(bad)

    def test_cannot_write_under_installed_app_or_source_checkout(self):
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(composer.Path, "home", return_value=Path(tmp)):
                for bad in ("Applications/NormalGame", "OpenLRR-Agent/BadLevel"):
                    with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, "game or source"):
                        composer.safe_output(Path(tmp) / bad)

    def test_default_cli_is_dry_without_files_or_processes(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "CrystalFrontier"
            with mock.patch.object(composer.os, "system",
                                   side_effect=AssertionError("no execution")):
                self.assertEqual(composer.main(["--name", "CrystalFrontier",
                                                "--out", str(folder)]), 0)
            self.assertFalse(folder.exists())


if __name__ == "__main__":
    unittest.main()
