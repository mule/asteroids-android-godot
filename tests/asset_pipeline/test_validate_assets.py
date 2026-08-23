from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.asset_pipeline.validate_assets import (
    ValidationError,
    format_json,
    validate_asset,
    validate_file,
    validate_paths,
)


ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "tests" / "asset_pipeline" / "fixtures"
VALIDATOR = ROOT / "tools" / "asset_pipeline" / "validate_assets.py"


class VectorAssetValidationTests(unittest.TestCase):
    def test_valid_ship_passes_and_normalizes_deterministically(self) -> None:
        path = FIXTURES / "valid_ship.json"
        first = validate_file(path).normalized
        second = validate_asset(json.loads(format_json(first)))

        self.assertEqual(first, second)
        self.assertEqual(first["asset_id"], "ship_test_01")
        self.assertEqual(first["category"], "ship")

    def test_approved_baseline_assets_pass(self) -> None:
        results = validate_paths([ROOT / "art" / "approved"])

        self.assertEqual(
            {result.asset_id for result in results},
            {
                "asteroid_baseline_01",
                "asteroid_craggy_01",
                "asteroid_cobalt_01",
                "asteroid_ice_01",
                "asteroid_iron_01",
                "asteroid_shale_01",
                "bullet_baseline_01",
                "celestial_moon_01",
                "celestial_planet_01",
                "ship_baseline_01",
                "ship_delta_01",
                "ship_freighter_01",
                "ship_gunship_01",
                "ship_interceptor_01",
                "station_dock_01",
            },
        )

    def test_self_intersecting_polygon_fails(self) -> None:
        with self.assertRaisesRegex(ValidationError, "self-intersect"):
            validate_file(FIXTURES / "invalid_self_intersection.json")

    def test_tiny_edges_fail(self) -> None:
        with self.assertRaisesRegex(ValidationError, "shorter than"):
            validate_file(FIXTURES / "invalid_tiny_edge.json")

    def test_concave_collision_polygon_fails(self) -> None:
        with self.assertRaisesRegex(ValidationError, "must be convex"):
            validate_file(FIXTURES / "invalid_collision_concave.json")

    def test_duplicate_asset_ids_fail_across_paths(self) -> None:
        with self.assertRaisesRegex(ValidationError, "duplicate asset_id"):
            validate_paths(
                [
                    FIXTURES / "invalid_duplicate_id_a.json",
                    FIXTURES / "invalid_duplicate_id_b.json",
                ]
            )

    def test_cli_returns_non_zero_for_invalid_fixture(self) -> None:
        result = subprocess.run(
            [sys.executable, str(VALIDATOR), str(FIXTURES / "invalid_tiny_edge.json")],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("shorter than", result.stderr)

    def test_cli_writes_normalized_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            result = subprocess.run(
                [
                    sys.executable,
                    str(VALIDATOR),
                    str(ROOT / "art" / "approved"),
                    "--output-dir",
                    temp_dir,
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                sorted(path.name for path in Path(temp_dir).glob("*.json")),
                [
                    "asteroid_baseline_01.json",
                    "asteroid_cobalt_01.json",
                    "asteroid_craggy_01.json",
                    "asteroid_ice_01.json",
                    "asteroid_iron_01.json",
                    "asteroid_shale_01.json",
                    "bullet_baseline_01.json",
                    "celestial_moon_01.json",
                    "celestial_planet_01.json",
                    "ship_baseline_01.json",
                    "ship_delta_01.json",
                    "ship_freighter_01.json",
                    "ship_gunship_01.json",
                    "ship_interceptor_01.json",
                    "station_dock_01.json",
                ],
            )


if __name__ == "__main__":
    unittest.main()
