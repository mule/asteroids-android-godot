#!/usr/bin/env python3
"""Promote one validated vector asset candidate into art/approved."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Sequence


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.asset_pipeline.validate_assets import ValidationError, ValidationResult, format_json, validate_file  # noqa: E402


APPROVED_DIR = ROOT / "art" / "approved"


def promote_asset(
    candidate_path: Path,
    asset_id: str,
    reviewer: str,
    output_dir: Path = APPROVED_DIR,
    allow_overwrite: bool = False,
) -> Path:
    result = validate_file(candidate_path)
    if result.asset_id != asset_id:
        raise ValidationError("asset_id", f"expected {asset_id!r}, found {result.asset_id!r}")

    normalized = _approved_copy(result, reviewer)
    output_path = output_dir / f"{asset_id}.json"
    if output_path.exists() and not allow_overwrite:
        raise ValidationError(str(output_path), "already exists; pass --allow-overwrite to replace it")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(format_json(normalized), encoding="utf-8")
    return output_path


def _approved_copy(result: ValidationResult, reviewer: str) -> dict:
    normalized = dict(result.normalized)
    normalized["approval"] = {
        "status": "approved",
        "reviewer": reviewer,
    }
    return normalized


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path, help="single candidate JSON file to promote")
    parser.add_argument("--asset-id", required=True, help="asset_id expected in the selected candidate")
    parser.add_argument("--reviewer", required=True, help="reviewer name recorded in approval metadata")
    parser.add_argument("--output-dir", type=Path, default=APPROVED_DIR, help="approved asset directory")
    parser.add_argument("--allow-overwrite", action="store_true", help="replace an existing approved file")
    args = parser.parse_args(argv)

    if args.candidate.is_dir():
        print("candidate must be one explicit JSON file, not a directory", file=sys.stderr)
        return 1

    try:
        output_path = promote_asset(
            candidate_path=args.candidate,
            asset_id=args.asset_id,
            reviewer=args.reviewer,
            output_dir=args.output_dir,
            allow_overwrite=args.allow_overwrite,
        )
    except (OSError, ValidationError) as exc:
        print(exc, file=sys.stderr)
        return 1

    print(f"Promoted {args.asset_id} to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
