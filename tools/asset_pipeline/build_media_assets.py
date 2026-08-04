#!/usr/bin/env python3
"""Build deterministic raster and audio assets from approved media specs."""

from __future__ import annotations

import argparse
import json
import math
import random
import struct
import sys
import wave
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


ROOT = Path(__file__).resolve().parents[2]
APPROVED_MEDIA_DIR = ROOT / "art" / "approved" / "media"
MEDIA_SCHEMA_VERSION = "media-asset/v1"


class MediaBuildError(Exception):
	pass


@dataclass(frozen=True)
class MediaOutput:
	path: Path
	content: bytes


def load_media_specs(source_dir: Path) -> list[dict[str, Any]]:
	specs: list[dict[str, Any]] = []
	for path in sorted(source_dir.rglob("*.json")):
		data = json.loads(path.read_text(encoding="utf-8"))
		if data.get("schema_version") != MEDIA_SCHEMA_VERSION:
			continue
		data["_source_path"] = path
		specs.append(data)
	if not specs:
		raise MediaBuildError(f"no {MEDIA_SCHEMA_VERSION} specs found in {display_path(source_dir)}")
	return specs


def build_outputs(source_dir: Path = APPROVED_MEDIA_DIR) -> list[MediaOutput]:
	outputs: list[MediaOutput] = []
	for spec in load_media_specs(source_dir):
		output_path = ROOT / _require_string(spec, "output_path")
		kind = _require_string(spec, "kind")
		if kind in {"raster", "effect"}:
			outputs.append(MediaOutput(output_path, _render_png(spec)))
		elif kind == "audio":
			outputs.append(MediaOutput(output_path, _render_wav(spec)))
		else:
			raise MediaBuildError(f"{spec['_source_path']}: unsupported kind {kind!r}")
	return sorted(outputs, key=lambda item: display_path(item.path))


def write_outputs(outputs: Sequence[MediaOutput]) -> None:
	for output in outputs:
		output.path.parent.mkdir(parents=True, exist_ok=True)
		output.path.write_bytes(output.content)


def check_outputs(outputs: Sequence[MediaOutput]) -> list[str]:
	problems: list[str] = []
	for output in outputs:
		if not output.path.exists():
			problems.append(f"missing {display_path(output.path)}")
		elif output.path.read_bytes() != output.content:
			problems.append(f"stale {display_path(output.path)}")
	return problems


def _render_png(spec: dict[str, Any]) -> bytes:
	raster = _require_object(spec, "raster")
	width = _require_int(raster, "width")
	height = _require_int(raster, "height")
	recipe = _require_object(raster, "recipe")
	recipe_type = _require_string(recipe, "type")
	if recipe_type == "starfield_nebula":
		pixels = _starfield_nebula(width, height, recipe)
	elif recipe_type == "impact_flash":
		pixels = _impact_flash(width, height, recipe)
	else:
		raise MediaBuildError(f"{spec['_source_path']}: unsupported raster recipe {recipe_type!r}")
	return _png_rgba(width, height, pixels)


def _starfield_nebula(width: int, height: int, recipe: dict[str, Any]) -> bytes:
	rng = random.Random(_require_int(recipe, "seed"))
	pixels = bytearray(width * height * 4)
	nebula_color = _color_bytes(recipe.get("nebula_color", [38, 84, 138]))
	for y in range(height):
		for x in range(width):
			nx = (x / max(1, width - 1)) - 0.5
			ny = (y / max(1, height - 1)) - 0.48
			ridge = max(0.0, 1.0 - math.hypot(nx * 2.1, ny * 3.0))
			wisp = 0.5 + 0.5 * math.sin((nx * 12.0) + (ny * 7.0))
			index = (y * width + x) * 4
			base = 8 + int(12 * ridge * wisp)
			pixels[index] = min(255, base + int(nebula_color[0] * ridge * 0.22))
			pixels[index + 1] = min(255, base + int(nebula_color[1] * ridge * 0.20))
			pixels[index + 2] = min(255, base + 10 + int(nebula_color[2] * ridge * 0.26))
			pixels[index + 3] = 255

	for _ in range(_require_int(recipe, "star_count")):
		x = rng.randrange(width)
		y = rng.randrange(height)
		brightness = rng.randrange(135, 256)
		index = (y * width + x) * 4
		pixels[index:index + 4] = bytes((brightness, min(255, brightness + 8), 255, 255))
	return bytes(pixels)


def _impact_flash(width: int, height: int, recipe: dict[str, Any]) -> bytes:
	inner = float(recipe.get("inner_radius", 0.16))
	outer = float(recipe.get("outer_radius", 0.48))
	color = _color_bytes(recipe.get("color", [255, 202, 92]))
	pixels = bytearray(width * height * 4)
	for y in range(height):
		for x in range(width):
			nx = ((x + 0.5) / width) * 2.0 - 1.0
			ny = ((y + 0.5) / height) * 2.0 - 1.0
			dist = math.hypot(nx, ny)
			if dist > outer:
				alpha = 0
			elif dist <= inner:
				alpha = 230
			else:
				alpha = int(230 * (1.0 - ((dist - inner) / (outer - inner))) ** 1.8)
			index = (y * width + x) * 4
			pixels[index:index + 4] = bytes((color[0], color[1], color[2], alpha))
	return bytes(pixels)


def _render_wav(spec: dict[str, Any]) -> bytes:
	audio = _require_object(spec, "audio")
	recipe = _require_object(audio, "recipe")
	sample_rate = _require_int(audio, "sample_rate")
	duration = float(recipe.get("duration_seconds", audio.get("max_duration_seconds", 0.25)))
	frame_count = max(1, int(sample_rate * duration))
	recipe_type = _require_string(recipe, "type")
	rng = random.Random(_require_int(recipe, "seed"))
	samples = bytearray()
	for frame in range(frame_count):
		t = frame / sample_rate
		progress = frame / max(1, frame_count - 1)
		if recipe_type == "shot_chirp":
			frequency = 920.0 + (1.0 - progress) * 860.0
			envelope = math.exp(-progress * 10.0)
			value = math.sin(t * frequency * math.tau) * envelope * 0.62
		elif recipe_type == "impact_thump":
			frequency = 86.0 + (1.0 - progress) * 160.0
			envelope = math.exp(-progress * 5.2)
			noise = (rng.random() * 2.0 - 1.0) * 0.32
			value = ((math.sin(t * frequency * math.tau) * 0.62) + noise) * envelope
		else:
			raise MediaBuildError(f"{spec['_source_path']}: unsupported audio recipe {recipe_type!r}")
		samples.extend(struct.pack("<h", int(max(-0.98, min(0.98, value)) * 32767)))

	buffer = bytearray()
	with wave.open(_ByteWriter(buffer), "wb") as handle:
		handle.setnchannels(1)
		handle.setsampwidth(2)
		handle.setframerate(sample_rate)
		handle.writeframes(bytes(samples))
	return bytes(buffer)


class _ByteWriter:
	def __init__(self, buffer: bytearray) -> None:
		self.buffer = buffer
		self.offset = 0

	def write(self, data: bytes) -> int:
		end = self.offset + len(data)
		if end > len(self.buffer):
			self.buffer.extend(b"\0" * (end - len(self.buffer)))
		self.buffer[self.offset:end] = data
		self.offset = end
		return len(data)

	def tell(self) -> int:
		return self.offset

	def seek(self, offset: int, whence: int = 0) -> int:
		if whence == 0:
			self.offset = offset
		elif whence == 1:
			self.offset += offset
		elif whence == 2:
			self.offset = len(self.buffer) + offset
		return self.offset

	def flush(self) -> None:
		return None


def _png_rgba(width: int, height: int, pixels: bytes) -> bytes:
	def chunk(kind: bytes, payload: bytes) -> bytes:
		return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)

	raw = b"".join(b"\0" + pixels[y * width * 4:(y + 1) * width * 4] for y in range(height))
	return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def _color_bytes(value: Any) -> tuple[int, int, int]:
	if not isinstance(value, list) or len(value) != 3:
		raise MediaBuildError("color must be an RGB array")
	return tuple(max(0, min(255, int(channel))) for channel in value)


def _require_object(data: dict[str, Any], key: str) -> dict[str, Any]:
	value = data.get(key)
	if not isinstance(value, dict):
		raise MediaBuildError(f"{key}: expected object")
	return value


def _require_string(data: dict[str, Any], key: str) -> str:
	value = data.get(key)
	if not isinstance(value, str) or not value:
		raise MediaBuildError(f"{key}: expected string")
	return value


def _require_int(data: dict[str, Any], key: str) -> int:
	value = data.get(key)
	if not isinstance(value, int) or isinstance(value, bool):
		raise MediaBuildError(f"{key}: expected integer")
	return value


def display_path(path: Path) -> str:
	try:
		return path.resolve().relative_to(ROOT).as_posix()
	except ValueError:
		return path.as_posix()


def main(argv: Sequence[str] | None = None) -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--source-dir", type=Path, default=APPROVED_MEDIA_DIR)
	parser.add_argument("--check", action="store_true", help="verify outputs are current without writing")
	args = parser.parse_args(argv)
	try:
		outputs = build_outputs(args.source_dir.resolve())
		if args.check:
			problems = check_outputs(outputs)
			if problems:
				for problem in problems:
					print(problem, file=sys.stderr)
				return 1
			print("OK media assets are current")
		else:
			write_outputs(outputs)
			print(f"Wrote {len(outputs)} media assets")
	except (OSError, json.JSONDecodeError, MediaBuildError) as exc:
		print(exc, file=sys.stderr)
		return 1
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
