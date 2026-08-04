from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.asset_pipeline.build_media_assets import build_outputs, check_outputs, write_outputs
from tools.asset_pipeline.validate_media_assets import MediaValidationError, validate_paths


ROOT = Path(__file__).resolve().parents[2]
APPROVED_MEDIA = ROOT / "art" / "approved" / "media"
BUILDER = ROOT / "tools" / "asset_pipeline" / "build_media_assets.py"
VALIDATOR = ROOT / "tools" / "asset_pipeline" / "validate_media_assets.py"


class MediaAssetPipelineTests(unittest.TestCase):
	def test_approved_media_assets_validate(self) -> None:
		results = validate_paths([APPROVED_MEDIA])

		self.assertEqual(
			{result.asset_id for result in results},
			{
				"background_starfield_01",
				"effect_impact_flash_01",
				"sfx_impact_thump_01",
				"sfx_shot_spark_01",
			},
		)

	def test_builder_outputs_are_byte_stable(self) -> None:
		first = build_outputs(APPROVED_MEDIA)
		second = build_outputs(APPROVED_MEDIA)

		self.assertEqual(
			{output.path: output.content for output in first},
			{output.path: output.content for output in second},
		)

	def test_cli_check_detects_stale_media_output(self) -> None:
		with tempfile.TemporaryDirectory(dir=ROOT) as temp_dir:
			temp_root = Path(temp_dir)
			source_dir = temp_root / "media"
			source_dir.mkdir()
			spec = json.loads((APPROVED_MEDIA / "sfx_shot_spark_01.json").read_text(encoding="utf-8"))
			spec["output_path"] = f"{temp_root.relative_to(ROOT).as_posix()}/sfx_shot_spark_01.wav"
			(source_dir / "sfx_shot_spark_01.json").write_text(json.dumps(spec), encoding="utf-8")

			outputs = build_outputs(source_dir)
			write_outputs(outputs)
			outputs[0].path.write_bytes(outputs[0].path.read_bytes() + b"stale")

			result = subprocess.run(
				[sys.executable, str(BUILDER), "--source-dir", str(source_dir), "--check"],
				cwd=ROOT,
				text=True,
				capture_output=True,
				check=False,
			)

			self.assertNotEqual(result.returncode, 0)
			self.assertIn("stale", result.stderr)

	def test_audio_peak_limit_is_enforced(self) -> None:
		with tempfile.TemporaryDirectory(dir=ROOT) as temp_dir:
			temp_root = Path(temp_dir)
			source_dir = temp_root / "media"
			source_dir.mkdir()
			spec = json.loads((APPROVED_MEDIA / "sfx_impact_thump_01.json").read_text(encoding="utf-8"))
			spec["audio"]["max_peak"] = 0.05
			spec["output_path"] = f"{temp_root.relative_to(ROOT).as_posix()}/sfx_impact_thump_01.wav"
			(source_dir / "sfx_impact_thump_01.json").write_text(json.dumps(spec), encoding="utf-8")
			write_outputs(build_outputs(source_dir))

			with self.assertRaisesRegex(MediaValidationError, "peak"):
				validate_paths([source_dir])

	def test_validator_cli_passes_for_approved_media(self) -> None:
		result = subprocess.run(
			[sys.executable, str(VALIDATOR), str(APPROVED_MEDIA)],
			cwd=ROOT,
			text=True,
			capture_output=True,
			check=False,
		)

		self.assertEqual(result.returncode, 0, result.stderr)
		self.assertIn("background_starfield_01", result.stdout)

	def test_check_outputs_accepts_current_outputs(self) -> None:
		self.assertEqual(check_outputs(build_outputs(APPROVED_MEDIA)), [])


if __name__ == "__main__":
	unittest.main()
