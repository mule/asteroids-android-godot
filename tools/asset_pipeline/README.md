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
python3 -m unittest tests.asset_pipeline.test_validate_assets
```
