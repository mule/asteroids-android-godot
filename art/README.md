# Art pipeline workspace

This directory contains the version-controlled inputs and review structure for
the AI-assisted asset pipeline described in:

- [Asset pipeline contract](../docs/asset-pipeline.md)
- [Art style guide](../docs/art-style-guide.md)

## Directories

- `prompts/`: Provider-neutral prompts and prompt notes.
- `generated/`: Temporary candidates and small review fixtures.
- `approved/`: Reviewed source specifications that production transforms may
  consume.
- `rejected/`: Optional rejection notes or tiny fixtures; bulk rejected output
  should stay untracked.
- `schemas/`: Schemas and validation documentation.
- `experiments/`: Local exploration that is not part of the production path.

Approved source specifications are authoritative. Raw model payloads and local
provider caches are not production assets.

Raster, effect, and audio media specs live under `approved/media/` and use the
separate `media-asset/v1` contract. Build them with
`python3 tools/asset_pipeline/build_media_assets.py` before validating with
`python3 tools/asset_pipeline/validate_media_assets.py art/approved/media`.
