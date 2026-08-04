from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.asset_pipeline.promote_asset import promote_asset
from tools.asset_pipeline.validate_assets import ValidationError, format_json


ROOT = Path(__file__).resolve().parents[2]
PROMOTER = ROOT / "tools" / "asset_pipeline" / "promote_asset.py"
CANDIDATE = ROOT / "art" / "generated" / "examples" / "ship_delta_01.json"


class PromoteAssetTests(unittest.TestCase):
    def test_promote_single_candidate_normalizes_and_approves(self) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT) as temp_dir:
            output_path = promote_asset(
                CANDIDATE,
                asset_id="ship_delta_01",
                reviewer="test_reviewer",
                output_dir=Path(temp_dir),
            )

            promoted = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(promoted["asset_id"], "ship_delta_01")
            self.assertEqual(promoted["approval"], {"status": "approved", "reviewer": "test_reviewer"})
            self.assertEqual(output_path.read_text(encoding="utf-8"), format_json(promoted))

    def test_promote_refuses_asset_id_mismatch(self) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT) as temp_dir:
            with self.assertRaisesRegex(ValidationError, "expected 'ship_wrong_01'"):
                promote_asset(
                    CANDIDATE,
                    asset_id="ship_wrong_01",
                    reviewer="test_reviewer",
                    output_dir=Path(temp_dir),
                )

    def test_cli_refuses_directory_input(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(PROMOTER),
                str(ROOT / "art" / "generated" / "examples"),
                "--asset-id",
                "ship_delta_01",
                "--reviewer",
                "test_reviewer",
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a directory", result.stderr)

    def test_cli_refuses_overwrite_without_flag(self) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT) as temp_dir:
            output_dir = Path(temp_dir)
            first = subprocess.run(
                [
                    sys.executable,
                    str(PROMOTER),
                    str(CANDIDATE),
                    "--asset-id",
                    "ship_delta_01",
                    "--reviewer",
                    "test_reviewer",
                    "--output-dir",
                    str(output_dir),
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(first.returncode, 0, first.stderr)

            second = subprocess.run(
                [
                    sys.executable,
                    str(PROMOTER),
                    str(CANDIDATE),
                    "--asset-id",
                    "ship_delta_01",
                    "--reviewer",
                    "test_reviewer",
                    "--output-dir",
                    str(output_dir),
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertNotEqual(second.returncode, 0)
            self.assertIn("already exists", second.stderr)


if __name__ == "__main__":
    unittest.main()
