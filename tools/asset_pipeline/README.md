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
python3 -m unittest tests.asset_pipeline.test_validate_assets tests.asset_pipeline.test_build_assets
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
