#!/usr/bin/env python3
"""Build Godot vector resources from approved vector asset specifications."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.asset_pipeline.validate_assets import (  # noqa: E402
    ValidationError,
    ValidationResult,
    format_json,
    validate_paths,
)


APPROVED_SOURCE_DIR = ROOT / "art" / "approved"
DEFAULT_OUTPUT_DIR = ROOT / "assets" / "generated"
MANIFEST_NAME = "manifest.json"
BUILD_SCHEMA_VERSION = "vector-asset-build/v1"
CATEGORY_ENUM = {"ship": 0, "asteroid": 1, "bullet": 2}
CATEGORY_DIR = {"ship": "ships", "asteroid": "asteroids", "bullet": "bullets"}
SHADER_MODE_ENUM = {"unlit": 0, "lit_vector": 1, "asteroid_faceted": 2, "emissive": 3}
SHADER_PATH = {
    "unlit": "assets/shaders/emissive_unlit.gdshader",
    "lit_vector": "assets/shaders/vector_lit.gdshader",
    "asteroid_faceted": "assets/shaders/asteroid_faceted.gdshader",
    "emissive": "assets/shaders/emissive_unlit.gdshader",
}


@dataclass(frozen=True)
class GeneratedFile:
    path: Path
    content: str


@dataclass(frozen=True)
class MaterialSource:
    material_id: str
    definition: dict[str, Any]
    owner_asset_id: str


def build_outputs(source_dir: Path, output_dir: Path) -> list[GeneratedFile]:
    results = validate_paths([source_dir])
    materials = _collect_materials(results)
    generated: list[GeneratedFile] = []

    for material in materials:
        generated.append(
            GeneratedFile(
                path=output_dir / "materials" / f"{material.material_id}.tres",
                content=_render_material_resource(material.definition),
            )
        )

    for result in results:
        generated.append(
            GeneratedFile(
                path=_asset_output_path(output_dir, result.normalized),
                content=_render_vector_resource(result, output_dir),
            )
        )

    generated.append(
        GeneratedFile(
            path=output_dir / MANIFEST_NAME,
            content=format_json(_build_manifest(results, materials, generated, source_dir, output_dir)),
        )
    )
    return sorted(generated, key=lambda item: _project_path(item.path))


def write_outputs(outputs: Sequence[GeneratedFile]) -> None:
    for output in outputs:
        output.path.parent.mkdir(parents=True, exist_ok=True)
        output.path.write_text(output.content, encoding="utf-8")


def check_outputs(outputs: Sequence[GeneratedFile], output_dir: Path) -> list[str]:
    problems: list[str] = []
    expected = {output.path.resolve(): output for output in outputs}
    for output in outputs:
        if not output.path.exists():
            problems.append(f"missing {display_path(output.path)}")
            continue
        actual = output.path.read_text(encoding="utf-8")
        if actual != output.content:
            problems.append(f"stale {display_path(output.path)}")

    manifest_path = output_dir / MANIFEST_NAME
    if manifest_path.exists():
        try:
            existing = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            problems.append(f"invalid existing manifest {display_path(manifest_path)}: {exc}")
        else:
            for path_text in _manifest_output_paths(existing):
                path = (ROOT / path_text).resolve()
                if path not in expected and path.exists():
                    problems.append(f"obsolete generated file still present {display_path(path)}")

    return problems


def display_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def _collect_materials(results: Sequence[ValidationResult]) -> list[MaterialSource]:
    materials: dict[str, MaterialSource] = {}
    for result in results:
        for definition in _asset_materials(result.normalized):
            material_id = definition["material_id"]
            existing = materials.get(material_id)
            candidate = MaterialSource(material_id=material_id, definition=definition, owner_asset_id=result.asset_id)
            if existing is not None and existing.definition != definition:
                raise ValidationError(
                    "material.material_id",
                    f"conflicting material_id {material_id!r} in {existing.owner_asset_id} and {result.asset_id}",
                )
            materials[material_id] = candidate
    return [materials[key] for key in sorted(materials)]


def _asset_materials(asset: dict[str, Any]) -> list[dict[str, Any]]:
    materials: list[dict[str, Any]] = []
    if "material" in asset:
        materials.append(asset["material"])
    for secondary in asset.get("secondary_polygons", []):
        if "material" in secondary:
            materials.append(secondary["material"])
    return materials


def _render_material_resource(material: dict[str, Any]) -> str:
    shader_mode = material["shader_mode"]
    lines = [
        '[gd_resource type="Resource" script_class="AssetMaterialDefinition" load_steps=3 format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/resources/asset_material_definition.gd" id="1_material_definition"]',
        f'[ext_resource type="Shader" path="res://{SHADER_PATH[shader_mode]}" id="2_shader"]',
        "",
        "[resource]",
        'script = ExtResource("1_material_definition")',
        f'material_id = &"{material["material_id"]}"',
        f"shader_mode = {SHADER_MODE_ENUM[shader_mode]}",
        'shader = ExtResource("2_shader")',
    ]
    for key in [
        "base_tint",
        "ambient",
        "diffuse_strength",
        "light_band_count",
        "highlight_strength",
        "emission_color",
        "emission_intensity",
        "noise_seed",
        "noise_scale",
        "noise_strength",
        "facet_strength",
    ]:
        if key not in material:
            continue
        value = material[key]
        if key in {"base_tint", "emission_color"}:
            lines.append(f"{key} = {_color(value)}")
        else:
            lines.append(f"{key} = {_number(value)}")
    return "\n".join(lines) + "\n"


def _render_vector_resource(result: ValidationResult, output_dir: Path) -> str:
    asset = result.normalized
    secondary_polygons = asset.get("secondary_polygons", [])
    ext_resources = [
        '[ext_resource type="Script" path="res://scripts/resources/vector_asset_definition.gd" id="1_vector_definition"]'
    ]
    if secondary_polygons:
        ext_resources.append(
            '[ext_resource type="Script" path="res://scripts/resources/vector_asset_polygon.gd" id="2_vector_polygon"]'
        )

    material_ids = _ordered_asset_material_ids(asset)
    material_ext_ids: dict[str, str] = {}
    for material_id in material_ids:
        ext_id = f"{len(ext_resources) + 1}_{material_id}"
        material_ext_ids[material_id] = ext_id
        material_path = output_dir / "materials" / f"{material_id}.tres"
        ext_resources.append(f'[ext_resource type="Resource" path="{_res_path(material_path)}" id="{ext_id}"]')

    subresources = [_render_secondary_polygon(secondary, material_ext_ids) for secondary in secondary_polygons]
    load_steps = len(ext_resources) + len(subresources) + 1
    lines = [
        f'[gd_resource type="Resource" script_class="VectorAssetDefinition" load_steps={load_steps} format=3]',
        "",
        *ext_resources,
    ]
    if subresources:
        lines.append("")
        lines.append("\n\n".join(subresources))

    lines.extend(
        [
            "",
            "[resource]",
            'script = ExtResource("1_vector_definition")',
            f'asset_id = &"{asset["asset_id"]}"',
            f"category = {CATEGORY_ENUM[asset['category']]}",
            f"primary_polygon = {_packed_vector2(asset['primary_polygon'])}",
            f"fill_color = {_color(asset['fill_color'])}",
        ]
    )
    if "outline" in asset:
        lines.append(f"outline_color = {_color(asset['outline']['color'])}")
        lines.append(f"outline_width = {_number(asset['outline']['width'])}")
    if "material" in asset:
        lines.append(f'material_definition = ExtResource("{material_ext_ids[asset["material"]["material_id"]]}")')
    if secondary_polygons:
        subresource_refs = ", ".join(f'SubResource("Resource_{item["polygon_id"]}")' for item in secondary_polygons)
        lines.append(f"secondary_polygons = Array[Resource]([{subresource_refs}])")
    if "collision" in asset:
        collision = asset["collision"]
        if collision["type"] == "convex_polygon":
            lines.append("use_collision_polygon = true")
            lines.append(f"collision_polygon = {_packed_vector2(collision['polygon'])}")
        elif collision["type"] == "circle":
            lines.append(f"collision_radius = {_number(collision['radius'])}")
    if asset.get("tags"):
        lines.append(f"tags = {_packed_string_array(asset['tags'])}")
    lines.append(f'provenance_reference = "{display_path(result.path)}"')
    return "\n".join(lines) + "\n"


def _render_secondary_polygon(secondary: dict[str, Any], material_ext_ids: dict[str, str]) -> str:
    lines = [
        f'[sub_resource type="Resource" id="Resource_{secondary["polygon_id"]}"]',
        'script = ExtResource("2_vector_polygon")',
        f'polygon_id = &"{secondary["polygon_id"]}"',
        f"polygon = {_packed_vector2(secondary['polygon'])}",
        f"fill_color = {_color(secondary['fill_color'])}",
    ]
    if "material" in secondary:
        lines.append(f'material_definition = ExtResource("{material_ext_ids[secondary["material"]["material_id"]]}")')
    if secondary.get("visible_by_default") is False:
        lines.append("visible_by_default = false")
    return "\n".join(lines)


def _ordered_asset_material_ids(asset: dict[str, Any]) -> list[str]:
    material_ids: list[str] = []
    if "material" in asset:
        material_ids.append(asset["material"]["material_id"])
    for secondary in asset.get("secondary_polygons", []):
        if "material" in secondary:
            material_ids.append(secondary["material"]["material_id"])
    return list(dict.fromkeys(material_ids))


def _build_manifest(
    results: Sequence[ValidationResult],
    materials: Sequence[MaterialSource],
    outputs: Sequence[GeneratedFile],
    source_dir: Path,
    output_dir: Path,
) -> dict[str, Any]:
    output_by_stem = {output.path.stem: output.path for output in outputs}
    material_by_id = {material.material_id: material for material in materials}
    asset_entries = []
    for result in sorted(results, key=lambda item: item.asset_id):
        asset = result.normalized
        asset_entries.append(
            {
                "asset_id": result.asset_id,
                "category": asset["category"],
                "source_path": display_path(result.path),
                "output_path": display_path(_asset_output_path(output_dir, asset)),
                "schema_version": asset["schema_version"],
                "source_sha256": _sha256(result.path),
                "material_ids": _ordered_asset_material_ids(asset),
            }
        )

    material_entries = []
    for material_id in sorted(material_by_id):
        material_entries.append(
            {
                "material_id": material_id,
                "owner_asset_id": material_by_id[material_id].owner_asset_id,
                "output_path": display_path(output_by_stem[material_id]),
                "shader_mode": material_by_id[material_id].definition["shader_mode"],
            }
        )

    return {
        "schema_version": BUILD_SCHEMA_VERSION,
        "source_dir": display_path(source_dir),
        "output_dir": display_path(output_dir),
        "assets": asset_entries,
        "materials": material_entries,
    }


def _manifest_output_paths(manifest: Any) -> list[str]:
    if not isinstance(manifest, dict):
        return []
    paths: list[str] = []
    for section in ("assets", "materials"):
        entries = manifest.get(section, [])
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if isinstance(entry, dict) and isinstance(entry.get("output_path"), str):
                paths.append(entry["output_path"])
    return paths


def _asset_output_path(output_dir: Path, asset: dict[str, Any]) -> Path:
    return output_dir / CATEGORY_DIR[asset["category"]] / f"{asset['asset_id']}.tres"


def _res_path(path: Path) -> str:
    return "res://" + path.resolve().relative_to(ROOT).as_posix()


def _project_path(path: Path) -> str:
    return path.resolve().relative_to(ROOT).as_posix()


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _packed_vector2(points: Sequence[Sequence[float | int]]) -> str:
    flattened = [coordinate for point in points for coordinate in point]
    return "PackedVector2Array(" + ", ".join(_number(value) for value in flattened) + ")"


def _packed_string_array(values: Sequence[str]) -> str:
    return "PackedStringArray(" + ", ".join(json.dumps(value) for value in values) + ")"


def _color(value: Sequence[float | int]) -> str:
    return "Color(" + ", ".join(_number(channel) for channel in value) + ")"


def _number(value: float | int) -> str:
    if isinstance(value, int):
        return str(value)
    text = f"{value:.6f}".rstrip("0").rstrip(".")
    return text if text else "0"


def _is_approved_source(source_dir: Path) -> bool:
    try:
        return source_dir.resolve().is_relative_to(APPROVED_SOURCE_DIR.resolve())
    except AttributeError:
        try:
            source_dir.resolve().relative_to(APPROVED_SOURCE_DIR.resolve())
            return True
        except ValueError:
            return False


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=APPROVED_SOURCE_DIR, help="source JSON directory")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR, help="generated resource directory")
    parser.add_argument("--allow-unapproved", action="store_true", help="allow reading outside art/approved")
    parser.add_argument("--check", action="store_true", help="verify generated files are current without writing")
    args = parser.parse_args(argv)

    source_dir = args.source_dir.resolve()
    output_dir = args.output_dir.resolve()
    if not args.allow_unapproved and not _is_approved_source(source_dir):
        print(
            f"{display_path(source_dir)} is outside art/approved; pass --allow-unapproved for staging sources",
            file=sys.stderr,
        )
        return 1

    try:
        outputs = build_outputs(source_dir, output_dir)
        if args.check:
            problems = check_outputs(outputs, output_dir)
            if problems:
                for problem in problems:
                    print(problem, file=sys.stderr)
                return 1
            print(f"OK {display_path(output_dir)} is current")
        else:
            write_outputs(outputs)
            print(f"Wrote {len(outputs)} generated files to {display_path(output_dir)}")
    except (OSError, ValidationError, ValueError) as exc:
        print(exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
