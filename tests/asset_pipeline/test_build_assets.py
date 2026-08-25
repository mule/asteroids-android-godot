from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.asset_pipeline.build_assets import build_outputs, check_outputs
from tools.asset_pipeline.validate_assets import format_json


ROOT = Path(__file__).resolve().parents[2]
APPROVED = ROOT / "art" / "approved"
BUILDER = ROOT / "tools" / "asset_pipeline" / "build_assets.py"


class VectorAssetBuildTests(unittest.TestCase):
    def test_build_outputs_include_vectors_materials_and_manifest(self) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT) as temp_dir:
            output_dir = Path(temp_dir) / "generated"
            outputs = build_outputs(APPROVED, output_dir)
            paths = {output.path.relative_to(output_dir).as_posix() for output in outputs}

            self.assertIn("manifest.json", paths)
            self.assertIn("ships/ship_baseline_01.tres", paths)
            self.assertIn("asteroids/asteroid_baseline_01.tres", paths)
            self.assertIn("bullets/bullet_baseline_01.tres", paths)
            self.assertIn("celestial/celestial_planet_01.tres", paths)
            self.assertIn("stations/station_dock_01.tres", paths)
            self.assertIn("materials/ship_lit_baseline.tres", paths)

    def test_cli_check_detects_stale_file(self) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT) as temp_dir:
            output_dir = Path(temp_dir) / "generated"
            first = subprocess.run(
                [sys.executable, str(BUILDER), "--output-dir", str(output_dir)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(first.returncode, 0, first.stderr)

            ship_path = output_dir / "ships" / "ship_baseline_01.tres"
            ship_path.write_text(ship_path.read_text(encoding="utf-8") + "# stale\n", encoding="utf-8")

            check = subprocess.run(
                [sys.executable, str(BUILDER), "--output-dir", str(output_dir), "--check"],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertNotEqual(check.returncode, 0)
            self.assertIn("stale", check.stderr)

    def test_generation_is_byte_stable(self) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT) as temp_dir:
            output_dir = Path(temp_dir) / "generated"
            first = build_outputs(APPROVED, output_dir)
            second = build_outputs(APPROVED, output_dir)

            self.assertEqual(
                {output.path: output.content for output in first},
                {output.path: output.content for output in second},
            )

    def test_invalid_source_leaves_existing_outputs_untouched(self) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT) as temp_dir:
            temp_root = Path(temp_dir)
            source_dir = temp_root / "approved"
            output_dir = temp_root / "generated"
            shutil.copytree(APPROVED, source_dir)
            bad_path = source_dir / "ship_baseline_01.json"
            bad_asset = json.loads(bad_path.read_text(encoding="utf-8"))
            bad_asset["primary_polygon"] = [[0, 0], [0.1, 0], [0, 1]]
            bad_path.write_text(format_json(bad_asset), encoding="utf-8")

            sentinel = output_dir / "ships" / "ship_baseline_01.tres"
            sentinel.parent.mkdir(parents=True)
            sentinel.write_text("keep me\n", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(BUILDER),
                    "--source-dir",
                    str(source_dir),
                    "--output-dir",
                    str(output_dir),
                    "--allow-unapproved",
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep me\n")

    def test_check_reports_obsolete_manifest_outputs(self) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT) as temp_dir:
            output_dir = Path(temp_dir) / "generated"
            outputs = build_outputs(APPROVED, output_dir)
            for output in outputs:
                output.path.parent.mkdir(parents=True, exist_ok=True)
                output.path.write_text(output.content, encoding="utf-8")

            obsolete = output_dir / "ships" / "old_ship.tres"
            obsolete.write_text("old\n", encoding="utf-8")
            manifest_path = output_dir / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["assets"].append(
                {
                    "asset_id": "old_ship_01",
                    "category": "ship",
                    "source_path": "art/approved/old_ship_01.json",
                    "output_path": obsolete.relative_to(ROOT).as_posix(),
                    "schema_version": "vector-asset/v1",
                    "source_sha256": "0",
                    "material_ids": [],
                }
            )
            manifest_path.write_text(format_json(manifest), encoding="utf-8")

            problems = check_outputs(build_outputs(APPROVED, output_dir), output_dir)

            self.assertTrue(any("obsolete generated file" in problem for problem in problems))


if __name__ == "__main__":
    unittest.main()
