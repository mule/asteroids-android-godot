# Experiment: Issue 29 Vector Candidate Workflow

## Goal

Demonstrate the repeatable prompt, validation, gallery review, and explicit
promotion workflow for one alternate ship and a small asteroid candidate set.

## Generation

- Prompt files: `art/prompts/ship-silhouette.md`,
  `art/prompts/asteroid-silhouette.md`
- Prompt revision: `issue-29`
- Provider/tool: Codex
- Model: GPT-5 Codex
- Date: 2026-08-04
- Seed: manual deterministic examples
- Candidate files: `art/generated/examples/ship_delta_01.json`,
  `art/generated/examples/asteroid_shale_01.json`,
  `art/generated/examples/asteroid_cobalt_01.json`,
  `art/generated/examples/asteroid_lattice_01.json`,
  `art/generated/examples/asteroid_slate_01.json`,
  `art/generated/examples/asteroid_ember_01.json`,
  `art/generated/examples/bullet_spark_01.json`

## Review

- Validator command:
  `python3 tools/asset_pipeline/validate_assets.py art/generated/examples`
- Gallery command:
  `/home/japurane/.local/bin/godot --path . scenes/tools/AssetGallery.tscn`
- Contact sheet or screenshot: local captures belong under `art/generated/`
  and are not committed by default.
- Mobile/readability notes: promoted assets use compact silhouettes and avoid
  thin spikes.
- Collision/bounds notes: asteroid candidates use circular collisions; the ship
  uses a convex hull collision polygon.
- Material/lighting notes: asteroids use `asteroid_faceted`; ship hull uses
  `lit_vector` and thrust uses `emissive`.

## Decision

- Promoted: `ship_delta_01`, `asteroid_shale_01`, `asteroid_cobalt_01`
- Rejected: `asteroid_lattice_01`, `asteroid_slate_01`,
  `asteroid_ember_01`
- Staged for later review: `bullet_spark_01`
- Manual cleanup: normalized through `tools/asset_pipeline/promote_asset.py`.
- Follow-up: issue #28 can choose whether any approved variants enter runtime
  asteroid spawning.

## Provenance And Terms

Examples are project-owned, hand-authored/Codex-assisted JSON specifications
created for this repository. No external API credentials, provider caches, or
third-party source assets are stored here.
