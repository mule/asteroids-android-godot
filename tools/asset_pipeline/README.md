# Asset pipeline tools

## Validate vector source assets

```sh
python3 tools/asset_pipeline/validate_assets.py art/approved
```

The validator checks JSON structure, provenance metadata, category limits,
polygon geometry, collision-shape constraints, duplicate asset IDs, and
deterministic normalization. It has no dependency on the Godot editor.

Run the automated tests with:

```sh
python3 -m unittest tests.asset_pipeline.test_validate_assets tests.asset_pipeline.test_build_assets tests.asset_pipeline.test_promote_asset tests.asset_pipeline.test_media_assets
```

## Build generated Godot resources

```sh
python3 tools/asset_pipeline/build_assets.py
```

The builder reads `art/approved/`, validates every JSON file, then writes
Godot-ready resources under `assets/generated/`:

- `assets/generated/ships/`
- `assets/generated/asteroids/`
- `assets/generated/bullets/`
- `assets/generated/materials/`
- `assets/generated/manifest.json`

Use `--check` in CI or review workflows to fail when generated files are
missing, stale, or when a previously-manifested generated output is still
present after its source asset was removed:

```sh
python3 tools/asset_pipeline/build_assets.py --check
```

Confirm Godot can load every manifest entry:

```sh
/home/japurane/.local/bin/godot --headless --path . --script tools/asset_pipeline/check_generated_assets.gd
```

The builder only reads approved specs by default. To build from a staging
directory, pass both `--source-dir` and `--allow-unapproved` so the nonproduction
input is explicit.

## Promote one reviewed candidate

```sh
python3 tools/asset_pipeline/promote_asset.py art/generated/examples/ship_delta_01.json --asset-id ship_delta_01 --reviewer japurane
```

Promotion validates one explicit candidate file, normalizes it, sets approval
metadata, writes it to `art/approved/`, and refuses to overwrite an existing
approved file unless `--allow-overwrite` is passed.

Build temporary candidate-review resources without touching production generated
assets:

```sh
python3 tools/asset_pipeline/build_assets.py --source-dir art/generated/examples --output-dir art/generated/review_assets --allow-unapproved
```

## Review generated assets

```sh
/home/japurane/.local/bin/godot --path . scenes/tools/AssetGallery.tscn
```

Review a temporary candidate manifest:

```sh
/home/japurane/.local/bin/godot --path . scenes/tools/AssetGallery.tscn -- --manifest=res://art/generated/review_assets/manifest.json
```

The gallery loads `assets/generated/manifest.json`, groups generated vector
assets by category, and provides rotating, canonical, gameplay-scale,
phone-scale, collision, and bounds previews without changing the gameplay main
scene.

Smoke-test the gallery UI tree:

```sh
/home/japurane/.local/bin/godot --headless --path . --script tools/asset_pipeline/check_asset_gallery.gd
```

Capture an ignored local contact sheet:

```sh
/home/japurane/.local/bin/godot --path . --script tools/asset_pipeline/capture_asset_gallery.gd -- --output=res://art/generated/asset_gallery_contact_sheet.png
```

## Check runtime variants

```sh
/home/japurane/.local/bin/godot --headless --path . --script tools/asset_pipeline/check_runtime_variants.gd
```

The runtime smoke check verifies that the same seed produces the same asteroid
spawn and visual sequence, that the initial wave contains multiple generated
asteroid visuals, and that split children retain the expected size tier.

## Build and validate media assets

```sh
python3 tools/asset_pipeline/build_media_assets.py
python3 tools/asset_pipeline/validate_media_assets.py art/approved/media
python3 tools/asset_pipeline/build_media_assets.py --check
```

Media specs under `art/approved/media/` use `media-asset/v1`. The builder
creates deterministic PNG/WAV outputs under `assets/media/` and `assets/audio/`;
the validator checks dimensions, alpha requirements, file-size limits, WAV
sample rate, channel count, duration, and normalized peak level.
