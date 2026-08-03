#!/usr/bin/env python3
"""Validate and normalize vector asset source specifications."""

from __future__ import annotations

import argparse
import copy
import json
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence


SCHEMA_VERSION = "vector-asset/v1"
SUPPORTED_CATEGORIES = {"ship", "asteroid", "bullet"}
ASSET_ID_RE = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*_[0-9]{2}$")
TOKEN_RE = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$")
EDGE_TOLERANCE = 0.25
CENTROID_LIMIT = 12.0
SYMMETRY_TOLERANCE = 0.75
CATEGORY_LIMITS = {
    "ship": {"max_width": 96.0, "max_height": 128.0, "min_height": 16.0},
    "asteroid": {"max_width": 128.0, "max_height": 128.0, "min_height": 16.0},
    "bullet": {"max_width": 32.0, "max_height": 40.0, "min_height": 4.0},
}


class ValidationError(Exception):
    def __init__(self, field: str, message: str) -> None:
        super().__init__(f"{field}: {message}")
        self.field = field
        self.message = message


@dataclass(frozen=True)
class ValidationResult:
    path: Path
    asset_id: str
    normalized: dict[str, Any]


Point = tuple[float, float]


def load_json(path: Path) -> Any:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:
        raise ValidationError("$", f"invalid JSON at line {exc.lineno}, column {exc.colno}") from exc


def validate_file(path: Path) -> ValidationResult:
    data = load_json(path)
    normalized = validate_asset(data)
    return ValidationResult(path=path, asset_id=normalized["asset_id"], normalized=normalized)


def validate_asset(data: Any) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise ValidationError("$", "asset specification must be an object")

    normalized = copy.deepcopy(data)
    _require_string(normalized, "schema_version")
    if normalized["schema_version"] != SCHEMA_VERSION:
        raise ValidationError("schema_version", f"expected {SCHEMA_VERSION!r}")

    asset_id = _require_string(normalized, "asset_id")
    if not ASSET_ID_RE.fullmatch(asset_id):
        raise ValidationError("asset_id", "must be lowercase snake_case with a two-digit variant suffix")

    category = _require_string(normalized, "category")
    if category not in SUPPORTED_CATEGORIES:
        raise ValidationError("category", f"must be one of {sorted(SUPPORTED_CATEGORIES)}")

    polygon = _normalize_polygon(normalized.get("primary_polygon"), "primary_polygon")
    normalized["primary_polygon"] = polygon
    _validate_visual_polygon(polygon, category, "primary_polygon")
    _validate_category_shape(polygon, category)

    normalized["fill_color"] = _normalize_color(normalized.get("fill_color"), "fill_color")
    if "outline" in normalized:
        _validate_outline(normalized["outline"])

    secondary_polygons = normalized.get("secondary_polygons", [])
    if not isinstance(secondary_polygons, list):
        raise ValidationError("secondary_polygons", "must be an array")
    normalized["secondary_polygons"] = [
        _normalize_secondary_polygon(item, f"secondary_polygons[{index}]")
        for index, item in enumerate(secondary_polygons)
    ]

    if "collision" in normalized:
        normalized["collision"] = _normalize_collision(normalized["collision"])

    requires_symmetry = normalized.get("requires_symmetry", False)
    if not isinstance(requires_symmetry, bool):
        raise ValidationError("requires_symmetry", "must be a boolean")
    normalized["requires_symmetry"] = requires_symmetry
    if requires_symmetry:
        _validate_x_axis_symmetry(polygon, "primary_polygon")

    normalized["tags"] = _normalize_tags(normalized.get("tags", []))
    normalized["provenance"] = _normalize_provenance(normalized.get("provenance"))
    normalized["approval"] = _normalize_approval(normalized.get("approval"))

    return _deterministic_asset(normalized)


def collect_json_files(paths: Sequence[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_dir():
            files.extend(sorted(child for child in path.rglob("*.json") if child.is_file()))
        elif path.is_file():
            files.append(path)
        else:
            raise ValidationError(str(path), "path does not exist")
    return sorted(dict.fromkeys(files))


def validate_paths(paths: Sequence[Path]) -> list[ValidationResult]:
    files = collect_json_files(paths)
    if not files:
        raise ValidationError("$", "no JSON asset files found")

    results = [validate_file(path) for path in files]
    seen: dict[str, Path] = {}
    for result in results:
        previous_path = seen.get(result.asset_id)
        if previous_path is not None:
            raise ValidationError(
                "asset_id",
                f"duplicate asset_id {result.asset_id!r} in {previous_path} and {result.path}",
            )
        seen[result.asset_id] = result.path

    return results


def write_normalized(results: Sequence[ValidationResult], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for result in results:
        output_path = output_dir / result.path.name
        output_path.write_text(format_json(result.normalized), encoding="utf-8")


def format_json(data: Any) -> str:
    return json.dumps(data, indent=2, sort_keys=True, ensure_ascii=True) + "\n"


def _deterministic_asset(asset: dict[str, Any]) -> dict[str, Any]:
    ordered_keys = [
        "schema_version",
        "asset_id",
        "category",
        "primary_polygon",
        "fill_color",
        "outline",
        "secondary_polygons",
        "collision",
        "requires_symmetry",
        "tags",
        "provenance",
        "approval",
    ]
    return {key: asset[key] for key in ordered_keys if key in asset}


def _normalize_secondary_polygon(data: Any, field: str) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise ValidationError(field, "must be an object")

    polygon_id = _require_string(data, f"{field}.polygon_id")
    if not TOKEN_RE.fullmatch(polygon_id):
        raise ValidationError(f"{field}.polygon_id", "must be lowercase snake_case")

    polygon = _normalize_polygon(data.get("polygon"), f"{field}.polygon")
    _validate_visual_polygon(polygon, "secondary", f"{field}.polygon")
    normalized = {
        "polygon_id": polygon_id,
        "polygon": polygon,
        "fill_color": _normalize_color(data.get("fill_color"), f"{field}.fill_color"),
        "visible_by_default": data.get("visible_by_default", True),
    }
    if not isinstance(normalized["visible_by_default"], bool):
        raise ValidationError(f"{field}.visible_by_default", "must be a boolean")
    return normalized


def _normalize_collision(data: Any) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise ValidationError("collision", "must be an object")
    collision_type = _require_string(data, "collision.type")

    if collision_type == "circle":
        radius = _number(data.get("radius"), "collision.radius")
        if radius <= 0:
            raise ValidationError("collision.radius", "must be greater than zero")
        if radius > 80:
            raise ValidationError("collision.radius", "must be 80 pixels or less")
        return {"type": "circle", "radius": _stable_number(radius)}

    if collision_type == "convex_polygon":
        polygon = _normalize_polygon(data.get("polygon"), "collision.polygon")
        _validate_visual_polygon(polygon, "collision", "collision.polygon")
        if not _is_convex(polygon):
            raise ValidationError("collision.polygon", "must be convex for ConvexPolygonShape2D")
        return {"type": "convex_polygon", "polygon": polygon}

    raise ValidationError("collision.type", "must be 'circle' or 'convex_polygon'")


def _validate_visual_polygon(polygon: list[list[float | int]], category: str, field: str) -> None:
    points = _as_points(polygon)
    if len(points) < 3:
        raise ValidationError(field, "must contain at least three points")

    for index, (a, b) in enumerate(zip(points, points[1:] + points[:1])):
        if _distance(a, b) < EDGE_TOLERANCE:
            raise ValidationError(f"{field}[{index}]", f"edge is shorter than {EDGE_TOLERANCE} pixels")

    if _has_self_intersections(points):
        raise ValidationError(field, "polygon must not self-intersect")

    area = _signed_area(points)
    if abs(area) < 1.0:
        raise ValidationError(field, "polygon area must be non-zero")

    centroid = _centroid(points)
    if category != "secondary" and math.hypot(centroid[0], centroid[1]) > CENTROID_LIMIT:
        raise ValidationError(field, f"centroid must be within {CENTROID_LIMIT} pixels of origin")

    if area < 0:
        polygon.reverse()


def _validate_category_shape(polygon: list[list[float | int]], category: str) -> None:
    points = _as_points(polygon)
    min_x, max_x, min_y, max_y = _bounds(points)
    width = max_x - min_x
    height = max_y - min_y
    limits = CATEGORY_LIMITS[category]
    if width > limits["max_width"]:
        raise ValidationError("primary_polygon", f"{category} width {width:g} exceeds {limits['max_width']:g}")
    if height > limits["max_height"]:
        raise ValidationError("primary_polygon", f"{category} height {height:g} exceeds {limits['max_height']:g}")
    if height < limits["min_height"]:
        raise ValidationError("primary_polygon", f"{category} height {height:g} is below {limits['min_height']:g}")

    if category == "ship":
        top_y = min(point[1] for point in points)
        nose_points = [point for point in points if math.isclose(point[1], top_y, abs_tol=0.001)]
        if len(nose_points) != 1 or abs(nose_points[0][0]) > 4.0:
            raise ValidationError("primary_polygon", "ship must have one forward nose near x=0 facing Vector2.UP")


def _validate_x_axis_symmetry(polygon: list[list[float | int]], field: str) -> None:
    points = _as_points(polygon)
    remaining = list(points)
    for x, y in points:
        match_index = next(
            (
                index
                for index, candidate in enumerate(remaining)
                if abs(candidate[0] + x) <= SYMMETRY_TOLERANCE and abs(candidate[1] - y) <= SYMMETRY_TOLERANCE
            ),
            None,
        )
        if match_index is None:
            raise ValidationError(field, "requires_symmetry is true but x-axis mirror points are missing")
        remaining.pop(match_index)


def _normalize_polygon(data: Any, field: str) -> list[list[float | int]]:
    if not isinstance(data, list):
        raise ValidationError(field, "must be an array")

    points: list[list[float | int]] = []
    previous: Point | None = None
    for index, point in enumerate(data):
        if not isinstance(point, list) or len(point) != 2:
            raise ValidationError(f"{field}[{index}]", "must be a two-number array")
        normalized_point = [_stable_number(_number(point[0], f"{field}[{index}][0]")), _stable_number(_number(point[1], f"{field}[{index}][1]"))]
        current = (float(normalized_point[0]), float(normalized_point[1]))
        if previous is not None and current == previous:
            raise ValidationError(f"{field}[{index}]", "duplicate consecutive point")
        previous = current
        points.append(normalized_point)

    if len(points) >= 2 and points[0] == points[-1]:
        raise ValidationError(field, "do not repeat the first point at the end")
    if len(points) < 3:
        raise ValidationError(field, "must contain at least three points")
    return points


def _normalize_color(data: Any, field: str) -> list[float | int]:
    if not isinstance(data, list) or len(data) != 4:
        raise ValidationError(field, "must be an RGBA array with four numbers")
    color = [_stable_number(_number(channel, f"{field}[{index}]")) for index, channel in enumerate(data)]
    for index, channel in enumerate(color):
        if float(channel) < 0.0 or float(channel) > 1.0:
            raise ValidationError(f"{field}[{index}]", "must be between 0 and 1")
    return color


def _validate_outline(data: Any) -> None:
    if not isinstance(data, dict):
        raise ValidationError("outline", "must be an object")
    _normalize_color(data.get("color"), "outline.color")
    width = _number(data.get("width"), "outline.width")
    if width < 0 or width > 16:
        raise ValidationError("outline.width", "must be between 0 and 16")


def _normalize_tags(data: Any) -> list[str]:
    if not isinstance(data, list):
        raise ValidationError("tags", "must be an array")
    tags: list[str] = []
    for index, tag in enumerate(data):
        if not isinstance(tag, str) or not TOKEN_RE.fullmatch(tag):
            raise ValidationError(f"tags[{index}]", "must be lowercase snake_case")
        if tag in tags:
            raise ValidationError(f"tags[{index}]", f"duplicate tag {tag!r}")
        tags.append(tag)
    return sorted(tags)


def _normalize_provenance(data: Any) -> dict[str, Any]:
    required = [
        "generator",
        "model",
        "prompt_file",
        "prompt_revision",
        "created_at",
        "seed",
        "manual_edits",
        "source_license",
        "notes",
    ]
    if not isinstance(data, dict):
        raise ValidationError("provenance", "must be an object")
    for key in required:
        if key not in data:
            raise ValidationError(f"provenance.{key}", "is required")
    for key in required:
        if key != "seed" and not isinstance(data[key], str):
            raise ValidationError(f"provenance.{key}", "must be a string")
    return {key: data[key] for key in required}


def _normalize_approval(data: Any) -> dict[str, str]:
    if not isinstance(data, dict):
        raise ValidationError("approval", "must be an object")
    status = _require_string(data, "approval.status")
    if status not in {"draft", "approved", "rejected"}:
        raise ValidationError("approval.status", "must be draft, approved, or rejected")
    reviewer = _require_string(data, "approval.reviewer")
    return {"status": status, "reviewer": reviewer}


def _require_string(data: dict[str, Any], field: str) -> str:
    key = field.rsplit(".", 1)[-1]
    value = data.get(key)
    if not isinstance(value, str) or value == "":
        raise ValidationError(field, "must be a non-empty string")
    return value


def _number(value: Any, field: str) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value):
        raise ValidationError(field, "must be a finite number")
    return float(value)


def _stable_number(value: float) -> float | int:
    if math.isclose(value, round(value), abs_tol=0.000000001):
        return int(round(value))
    return round(value, 6)


def _as_points(polygon: Sequence[Sequence[float | int]]) -> list[Point]:
    return [(float(point[0]), float(point[1])) for point in polygon]


def _signed_area(points: Sequence[Point]) -> float:
    return sum((a[0] * b[1]) - (b[0] * a[1]) for a, b in zip(points, points[1:] + points[:1])) / 2.0


def _centroid(points: Sequence[Point]) -> Point:
    area_factor = 0.0
    cx = 0.0
    cy = 0.0
    for a, b in zip(points, points[1:] + points[:1]):
        cross = (a[0] * b[1]) - (b[0] * a[1])
        area_factor += cross
        cx += (a[0] + b[0]) * cross
        cy += (a[1] + b[1]) * cross
    if math.isclose(area_factor, 0.0):
        return (0.0, 0.0)
    return (cx / (3.0 * area_factor), cy / (3.0 * area_factor))


def _bounds(points: Sequence[Point]) -> tuple[float, float, float, float]:
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return min(xs), max(xs), min(ys), max(ys)


def _distance(a: Point, b: Point) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def _has_self_intersections(points: Sequence[Point]) -> bool:
    edges = list(zip(points, points[1:] + points[:1]))
    for first_index, first in enumerate(edges):
        for second_index, second in enumerate(edges):
            if second_index <= first_index:
                continue
            if abs(first_index - second_index) == 1:
                continue
            if first_index == 0 and second_index == len(edges) - 1:
                continue
            if _segments_intersect(first[0], first[1], second[0], second[1]):
                return True
    return False


def _segments_intersect(a: Point, b: Point, c: Point, d: Point) -> bool:
    o1 = _orientation(a, b, c)
    o2 = _orientation(a, b, d)
    o3 = _orientation(c, d, a)
    o4 = _orientation(c, d, b)
    return o1 * o2 < 0 and o3 * o4 < 0


def _orientation(a: Point, b: Point, c: Point) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _is_convex(points: Sequence[Sequence[float | int]]) -> bool:
    typed_points = _as_points(points)
    signs: list[float] = []
    count = len(typed_points)
    for index in range(count):
        a = typed_points[index]
        b = typed_points[(index + 1) % count]
        c = typed_points[(index + 2) % count]
        cross = _orientation(a, b, c)
        if not math.isclose(cross, 0.0, abs_tol=0.000001):
            signs.append(math.copysign(1.0, cross))
    return bool(signs) and all(sign == signs[0] for sign in signs)


def _print_errors(errors: Iterable[tuple[Path | None, ValidationError]]) -> None:
    for path, error in errors:
        prefix = f"{path}: " if path is not None else ""
        print(f"{prefix}{error}", file=sys.stderr)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path, help="JSON asset files or directories to validate")
    parser.add_argument("--normalize", action="store_true", help="emit normalized JSON to stdout")
    parser.add_argument("--output-dir", type=Path, help="write normalized JSON files to this directory")
    args = parser.parse_args(argv)

    results: list[ValidationResult] = []
    errors: list[tuple[Path | None, ValidationError]] = []
    try:
        files = collect_json_files(args.paths)
    except ValidationError as exc:
        _print_errors([(None, exc)])
        return 1

    for path in files:
        try:
            results.append(validate_file(path))
        except ValidationError as exc:
            errors.append((path, exc))

    seen: dict[str, Path] = {}
    for result in results:
        previous_path = seen.get(result.asset_id)
        if previous_path is not None:
            errors.append(
                (
                    result.path,
                    ValidationError(
                        "asset_id",
                        f"duplicate asset_id {result.asset_id!r} in {previous_path} and {result.path}",
                    ),
                )
            )
        seen[result.asset_id] = result.path

    if errors:
        _print_errors(errors)
        return 1

    if args.output_dir is not None:
        write_normalized(results, args.output_dir)
    elif args.normalize:
        payload: Any = results[0].normalized if len(results) == 1 else [result.normalized for result in results]
        print(format_json(payload), end="")
    else:
        for result in results:
            print(f"OK {result.path} ({result.asset_id})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
