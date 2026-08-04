# Asset pipeline contract

Parent epic: [#22](https://github.com/mule/asteroids-android-godot/issues/22)

This project uses Asteroids as a small, reviewable testbed for AI-assisted game
asset production. The pipeline is intentionally lightweight: versioned prompts
and approved source specifications are the production contract; generated model
payloads are temporary source material until reviewed and promoted.

No gameplay behavior changes are part of this contract. The current entity
integration points remain:

- `scenes/entities/PlayerShip.tscn` for the player ship, thrust flame, and
  convex collision shape.
- `scenes/entities/Asteroid.tscn` for the asteroid polygon and circular
  collision shape.
- `scenes/entities/Bullet.tscn` for the projectile polygon and circular
  collision shape.
- `scripts/player_ship.gd`, which expects a stable `ThrustFlame` node.
- `scripts/asteroid.gd`, which expects a stable `RockShape` node and applies
  size scaling.

## Lifecycle

Every promoted asset moves through the same lifecycle:

1. Generate candidate material from a versioned prompt or procedural script.
2. Validate the candidate against the relevant schema and geometry rules.
3. Review the asset visually at gameplay scale and at enlarged inspection size.
4. Approve one source specification as the production input.
5. Transform or import the approved source into Godot-ready resources.
6. Verify the desktop project still starts and, for runtime integration changes,
   verify the Android debug APK.

The lifecycle is designed to keep model output inspectable. A provider response
is never considered a production asset by itself.

## Repository layout

```text
art/
  README.md
  prompts/       Provider-neutral prompts and prompt notes.
  generated/     Temporary generated candidates and local scratch exports.
  approved/      Reviewed source specifications used by production transforms.
  rejected/      Optional notes for rejected candidates, not bulk payloads.
  schemas/       JSON schemas and validation documentation.
  experiments/   Local exploration that is not part of production.
docs/
  asset-pipeline.md
  art-style-guide.md
```

`art/generated/`, `art/rejected/`, and `art/experiments/` are ignored except for
their `.gitkeep` files. Commit only small, useful examples there when a later
issue explicitly asks for them.

## Authoritative files

- Approved JSON or another reviewed source specification under `art/approved/`
  is the source of truth for vector assets.
- Schemas under `art/schemas/` define the structure validators must enforce.
- Prompt files under `art/prompts/` explain how candidates were produced, but
  prompts do not override approved source specifications.
- Generated `.tres` files may be committed later when predictable Godot imports
  are useful for review or Android builds.
- Raw model response payloads, provider caches, and unreviewed generated files
  are not production assets.

Runtime vector resources live under `assets/vector/`. These `.tres` files are
Godot-ready transforms of approved source definitions; entity scenes may assign
them through exported `visual_asset` properties.

Runtime material resources live under `assets/materials/`, with shaders under
`assets/shaders/`. `AssetMaterialDefinition` resources describe shader IDs,
lighting bands, ambient/diffuse response, emission, and deterministic
facet/noise parameters separately from polygon geometry.

## Asset IDs and file names

Use lowercase snake case for every asset ID and file stem:

- Ship family: `ship_interceptor_01`, `ship_scout_01`
- Asteroid family: `asteroid_rocky_01`, `asteroid_ice_01`
- Bullet family: `bullet_plasma_01`, `bullet_tracer_01`
- Prompt file: `ship_interceptor_vector_prompt.md`
- Approved vector spec: `ship_interceptor_01.json`

IDs should include the category, a short readable family name, and a two-digit
variant number. Do not encode provider names, model names, dates, or reviewer
names in asset IDs; keep those details in provenance metadata.

## Provenance metadata

Every approved source specification must include these fields or their schema
equivalents:

- `asset_id`: Stable lowercase snake case ID.
- `category`: `ship`, `asteroid`, `bullet`, `effect`, `presentation`, or
  `audio`.
- `schema_version`: Version of the schema used for validation.
- `generator`: Provider, tool, or procedural script name when known.
- `model`: Model name or version when known.
- `prompt_file`: Path to the prompt or generation note.
- `prompt_revision`: Git commit, short hash, or documented revision label.
- `created_at`: ISO 8601 date or timestamp.
- `seed`: Seed value when available.
- `manual_edits`: Human edits made after generation.
- `approval_status`: `draft`, `approved`, or `rejected`.
- `reviewer`: GitHub handle or local reviewer name for approved assets.
- `source_license`: License, ownership note, or source restriction.
- `notes`: Short review notes that explain meaningful decisions.

Unknown provider details should be recorded as `unknown`, not omitted. This
makes gaps visible during review.

## Review and promotion

Generated candidates start outside the production path. To promote one:

1. Save or update the prompt under `art/prompts/`.
2. Place the candidate source in `art/generated/` only if it is small and worth
   reviewing in Git; otherwise keep it local and document the relevant summary.
3. Validate the candidate against the schema in `art/schemas/`.
4. Review the silhouette, color, readability, and rotation behavior using the
   rules in [the art style guide](art-style-guide.md).
5. Copy the approved source specification into `art/approved/`.
6. Record provenance metadata and reviewer approval in the approved file.
7. Generate or update Godot resources only from the approved source.

Rejected output should usually stay untracked. Use `art/rejected/` for short
notes or small review fixtures only when they help future contributors avoid
the same failed direction.

## Verification

Documentation-only changes should be verified by checking paths, links, and a
Godot startup run:

```sh
/home/japurane/.local/bin/godot --headless --path . --quit
```

Runtime asset integration work must also use the Android export guide:

- [Android export guide](android-export.md)

## Adding a vector gameplay variant

1. Add or update the approved source specification under `art/approved/`.
2. Generate a Godot `VectorAssetDefinition` resource under `assets/vector/`.
3. Confirm the resource has an `asset_id`, category, primary polygon, fill
   color, and provenance reference.
4. For ships, include a `thrust_flame` secondary polygon if the variant needs
   thrust feedback, and include a convex collision polygon when collision data
   differs from the scene fallback.
5. Assign the `.tres` resource to the entity scene's exported `visual_asset`
   property or to a scene instance used for review.
6. Run the desktop and Android verification expected by the task that changes
   runtime assets.

## Adding a material variant

1. Add or update an `AssetMaterialDefinition` under `assets/materials/`.
2. Reference a shader from `assets/shaders/`.
3. Keep the material parameters deterministic: no runtime random mutation of
   shared resources.
4. Assign the material resource from a vector asset's `material_definition` or a
   secondary polygon's `material_definition`.
5. Use the `toggle_shader_lighting` input action, bound to `L`, to compare the
   shader-lit result with the unlit baseline at gameplay scale.

`Game.gd` owns the authoritative `world_light_direction`. Entity scripts receive
that direction and rotate it into local shader space before updating their
per-instance material. Shared material resources are never mutated per frame.

## Validating vector source assets

Vector source specifications use the schema at
`art/schemas/vector-asset.schema.json`. The validator is intentionally
editor-independent and uses the Python standard library.

Validate all approved source assets:

```sh
python3 tools/asset_pipeline/validate_assets.py art/approved
```

Validate one candidate file:

```sh
python3 tools/asset_pipeline/validate_assets.py art/generated/ship_candidate_01.json
```

Emit deterministic normalized JSON to stdout:

```sh
python3 tools/asset_pipeline/validate_assets.py art/approved/ship_baseline_01.json --normalize
```

Write normalized JSON files into a staging directory:

```sh
python3 tools/asset_pipeline/validate_assets.py art/approved --output-dir /tmp/asteroids-normalized-assets
```

The validator exits non-zero for malformed metadata, duplicate asset IDs,
degenerate polygons, self-intersections, unsupported categories, oversized
bounds, off-center primary polygons, invalid ship orientation, asymmetric assets
that require symmetry, and non-convex collision polygons.
