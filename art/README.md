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

