# Asset generation prompts

These prompts are provider-neutral starting points for creating reviewable
candidate source files. They intentionally reference the schema and art style
guide instead of copying every rule into every prompt.

Use them with Codex, another coding-capable model, or a human-assisted
copy-paste workflow. Do not store API keys, provider caches, raw chat logs, or
large unreviewed payloads in this repository.

Baseline command shape:

```sh
python3 tools/asset_pipeline/validate_assets.py art/generated/examples
python3 tools/asset_pipeline/promote_asset.py art/generated/examples/ship_delta_01.json --asset-id ship_delta_01 --reviewer japurane
python3 tools/asset_pipeline/build_assets.py
python3 tools/asset_pipeline/build_assets.py --check
```

Prompts:

- [asteroid-silhouette.md](asteroid-silhouette.md)
- [ship-silhouette.md](ship-silhouette.md)
- [bullet-projectile.md](bullet-projectile.md)
- [concept-sheet.md](concept-sheet.md)
