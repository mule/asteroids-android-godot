#!/usr/bin/env python3
"""Validate approved raster/effect/audio media specs and generated outputs."""

from __future__ import annotations

import argparse
import json
import struct
import sys
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


ROOT = Path(__file__).resolve().parents[2]
APPROVED_MEDIA_DIR = ROOT / "art" / "approved" / "media"
MEDIA_SCHEMA_VERSION = "media-asset/v1"
SUPPORTED_KINDS = {"raster", "effect", "audio"}
SUPPORTED_ROLES = {"background", "impact_effect", "shot_sfx", "impact_sfx"}


class MediaValidationError(Exception):
	def __init__(self, field: str, message: str) -> None:
		super().__init__(f"{field}: {message}")
		self.field = field
		self.message = message


@dataclass(frozen=True)
class MediaValidationResult:
	path: Path
	asset_id: str
	kind: str
	output_path: Path


def validate_paths(paths: Sequence[Path]) -> list[MediaValidationResult]:
	files = collect_json_files(paths)
	if not files:
		raise MediaValidationError("$", "no media JSON asset files found")
	results = [validate_file(path) for path in files]
	seen: dict[str, Path] = {}
	for result in results:
		previous = seen.get(result.asset_id)
		if previous is not None:
			raise MediaValidationError("asset_id", f"duplicate asset_id {result.asset_id!r} in {previous} and {result.path}")
		seen[result.asset_id] = result.path
	return results


def collect_json_files(paths: Sequence[Path]) -> list[Path]:
	files: list[Path] = []
	for path in paths:
		if path.is_dir():
			files.extend(sorted(child for child in path.rglob("*.json") if child.is_file() and _is_media_spec(child)))
		elif path.is_file():
			files.append(path)
		else:
			raise MediaValidationError(str(path), "path does not exist")
	return sorted(dict.fromkeys(files))


def validate_file(path: Path) -> MediaValidationResult:
	try:
		data = json.loads(path.read_text(encoding="utf-8"))
	except json.JSONDecodeError as exc:
		raise MediaValidationError("$", f"invalid JSON at line {exc.lineno}, column {exc.colno}") from exc
	if not isinstance(data, dict):
		raise MediaValidationError("$", "asset specification must be an object")

	_require_equal(data, "schema_version", MEDIA_SCHEMA_VERSION)
	asset_id = _require_string(data, "asset_id")
	kind = _require_string(data, "kind")
	if kind not in SUPPORTED_KINDS:
		raise MediaValidationError("kind", f"must be one of {sorted(SUPPORTED_KINDS)}")
	role = _require_string(data, "role")
	if role not in SUPPORTED_ROLES:
		raise MediaValidationError("role", f"must be one of {sorted(SUPPORTED_ROLES)}")
	output_path = _project_path(_require_string(data, "output_path"), "output_path")
	_validate_provenance(data.get("provenance"))
	_validate_approval(data.get("approval"))

	if kind in {"raster", "effect"}:
		_validate_raster(data, output_path)
	elif kind == "audio":
		_validate_audio(data, output_path)
	return MediaValidationResult(path=path, asset_id=asset_id, kind=kind, output_path=output_path)


def _validate_raster(data: dict[str, Any], output_path: Path) -> None:
	raster = _require_object(data, "raster")
	width = _require_int(raster, "width", minimum=1, maximum=2048)
	height = _require_int(raster, "height", minimum=1, maximum=2048)
	max_bytes = _require_int(raster, "max_bytes", minimum=1, maximum=2_000_000)
	requires_alpha = _require_bool(raster, "requires_alpha")
	if _require_string(raster, "format") != "png_rgba8":
		raise MediaValidationError("raster.format", "must be png_rgba8")
	_require_object(raster, "recipe")

	actual = _read_png_header(output_path)
	if actual["width"] != width or actual["height"] != height:
		raise MediaValidationError("output_path", f"expected {width}x{height}, got {actual['width']}x{actual['height']}")
	if actual["color_type"] != 6:
		raise MediaValidationError("output_path", "must be PNG RGBA")
	if requires_alpha and not actual["has_transparent_alpha"]:
		raise MediaValidationError("output_path", "must contain transparent alpha pixels")
	_validate_file_size(output_path, max_bytes)


def _validate_audio(data: dict[str, Any], output_path: Path) -> None:
	audio = _require_object(data, "audio")
	if _require_string(audio, "format") != "wav_pcm16":
		raise MediaValidationError("audio.format", "must be wav_pcm16")
	sample_rate = _require_int(audio, "sample_rate", minimum=8000, maximum=48000)
	channels = _require_int(audio, "channels", minimum=1, maximum=2)
	max_duration = _require_number(audio, "max_duration_seconds", minimum=0.02, maximum=2.0)
	max_peak = _require_number(audio, "max_peak", minimum=0.05, maximum=1.0)
	_require_bool(audio, "loop")
	_require_object(audio, "recipe")

	try:
		with wave.open(str(output_path), "rb") as handle:
			actual_channels = handle.getnchannels()
			actual_width = handle.getsampwidth()
			actual_rate = handle.getframerate()
			frames = handle.readframes(handle.getnframes())
			duration = handle.getnframes() / float(actual_rate)
	except (OSError, wave.Error) as exc:
		raise MediaValidationError("output_path", f"invalid WAV: {exc}") from exc

	if actual_channels != channels:
		raise MediaValidationError("output_path", f"expected {channels} channel(s), got {actual_channels}")
	if actual_width != 2:
		raise MediaValidationError("output_path", "must be 16-bit PCM")
	if actual_rate != sample_rate:
		raise MediaValidationError("output_path", f"expected {sample_rate} Hz, got {actual_rate}")
	if duration > max_duration:
		raise MediaValidationError("output_path", f"duration {duration:.3f}s exceeds {max_duration:.3f}s")
	peak = _pcm16_peak(frames)
	if peak <= 0.001:
		raise MediaValidationError("output_path", "audio is effectively silent")
	if peak > max_peak:
		raise MediaValidationError("output_path", f"peak {peak:.3f} exceeds {max_peak:.3f}")


def _read_png_header(path: Path) -> dict[str, Any]:
	data = path.read_bytes()
	if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n":
		raise MediaValidationError("output_path", "must be a PNG file")
	length = struct.unpack(">I", data[8:12])[0]
	if data[12:16] != b"IHDR" or length != 13:
		raise MediaValidationError("output_path", "missing IHDR chunk")
	width, height, bit_depth, color_type, _compression, _filter, _interlace = struct.unpack(">IIBBBBB", data[16:29])
	if bit_depth != 8:
		raise MediaValidationError("output_path", "must use 8-bit color")
	return {
		"width": width,
		"height": height,
		"color_type": color_type,
		"has_transparent_alpha": _png_has_transparent_alpha(data),
	}


def _png_has_transparent_alpha(data: bytes) -> bool:
	offset = 8
	idat = bytearray()
	width = height = color_type = 0
	while offset + 8 <= len(data):
		length = struct.unpack(">I", data[offset:offset + 4])[0]
		kind = data[offset + 4:offset + 8]
		payload = data[offset + 8:offset + 8 + length]
		offset += 12 + length
		if kind == b"IHDR":
			width, height, _bit_depth, color_type, *_ = struct.unpack(">IIBBBBB", payload)
		elif kind == b"IDAT":
			idat.extend(payload)
		elif kind == b"IEND":
			break
	if color_type != 6:
		return False
	raw = zlib_decompress(bytes(idat))
	stride = width * 4
	for y in range(height):
		row_start = y * (stride + 1)
		if raw[row_start] != 0:
			return False
		alpha = raw[row_start + 1 + 3:row_start + 1 + stride:4]
		if any(value < 255 for value in alpha):
			return True
	return False


def zlib_decompress(data: bytes) -> bytes:
	import zlib

	return zlib.decompress(data)


def _pcm16_peak(frames: bytes) -> float:
	if not frames:
		return 0.0
	count = len(frames) // 2
	values = struct.unpack("<" + ("h" * count), frames[:count * 2])
	return max(abs(value) for value in values) / 32767.0


def _validate_file_size(path: Path, max_bytes: int) -> None:
	size = path.stat().st_size
	if size > max_bytes:
		raise MediaValidationError("output_path", f"file size {size} exceeds {max_bytes}")


def _validate_provenance(value: Any) -> None:
	data = _require_object({"provenance": value}, "provenance")
	for key in ("generator", "model", "prompt_file", "prompt_revision", "created_at", "manual_edits", "source_license", "notes"):
		_require_string(data, key)
	if "seed" not in data:
		raise MediaValidationError("provenance.seed", "is required")


def _validate_approval(value: Any) -> None:
	data = _require_object({"approval": value}, "approval")
	status = _require_string(data, "status")
	if status not in {"draft", "approved", "rejected"}:
		raise MediaValidationError("approval.status", "must be draft, approved, or rejected")
	_require_string(data, "reviewer")


def _is_media_spec(path: Path) -> bool:
	try:
		data = json.loads(path.read_text(encoding="utf-8"))
	except json.JSONDecodeError:
		return True
	return isinstance(data, dict) and data.get("schema_version") == MEDIA_SCHEMA_VERSION


def _project_path(value: str, field: str) -> Path:
	if value.startswith("/") or ".." in Path(value).parts:
		raise MediaValidationError(field, "must be a relative project path")
	return ROOT / value


def _require_equal(data: dict[str, Any], key: str, expected: str) -> None:
	if data.get(key) != expected:
		raise MediaValidationError(key, f"expected {expected!r}")


def _require_object(data: dict[str, Any], key: str) -> dict[str, Any]:
	value = data.get(key)
	if not isinstance(value, dict):
		raise MediaValidationError(key, "must be an object")
	return value


def _require_string(data: dict[str, Any], key: str) -> str:
	value = data.get(key)
	if not isinstance(value, str) or not value:
		raise MediaValidationError(key, "must be a non-empty string")
	return value


def _require_bool(data: dict[str, Any], key: str) -> bool:
	value = data.get(key)
	if not isinstance(value, bool):
		raise MediaValidationError(key, "must be a boolean")
	return value


def _require_int(data: dict[str, Any], key: str, minimum: int, maximum: int) -> int:
	value = data.get(key)
	if not isinstance(value, int) or isinstance(value, bool) or value < minimum or value > maximum:
		raise MediaValidationError(key, f"must be an integer between {minimum} and {maximum}")
	return value


def _require_number(data: dict[str, Any], key: str, minimum: float, maximum: float) -> float:
	value = data.get(key)
	if not isinstance(value, (int, float)) or isinstance(value, bool) or value < minimum or value > maximum:
		raise MediaValidationError(key, f"must be a number between {minimum:g} and {maximum:g}")
	return float(value)


def display_path(path: Path) -> str:
	try:
		return path.resolve().relative_to(ROOT).as_posix()
	except ValueError:
		return path.as_posix()


def main(argv: Sequence[str] | None = None) -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("paths", nargs="*", type=Path, default=[APPROVED_MEDIA_DIR])
	args = parser.parse_args(argv)
	try:
		results = validate_paths(args.paths)
	except (OSError, MediaValidationError) as exc:
		print(exc, file=sys.stderr)
		return 1
	for result in results:
		print(f"OK {display_path(result.path)} -> {display_path(result.output_path)}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
