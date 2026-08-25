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
- Generated PNG/WAV media outputs may be committed when they are built from an
  approved media specification and small enough for mobile review.
- Raw model response payloads, provider caches, and unreviewed generated files
  are not production assets.

Runtime vector resources live under `assets/vector/`. These `.tres` files are
Godot-ready transforms of approved source definitions; entity scenes may assign
them through exported `visual_asset` properties.

Runtime material resources live under `assets/materials/`, with shaders under
`assets/shaders/`. `AssetMaterialDefinition` resources describe shader IDs,
lighting bands, ambient/diffuse response, emission, and deterministic
facet/noise parameters separately from polygon geometry.

Generated runtime resources live under `assets/generated/`. The checked-in
builder transforms approved source JSON into `VectorAssetDefinition` and
`AssetMaterialDefinition` `.tres` files with deterministic formatting and a
manifest that maps source paths, output paths, schema versions, material IDs,
and source checksums. Hand-authored resources under `assets/vector/` and
`assets/materials/` remain useful baselines, but generated resources should come
from the approved source specifications.

Runtime media outputs live under `assets/media/` for PNG presentation/effect
textures and `assets/audio/` for short sound effects. Approved media source
specifications live under `art/approved/media/` and use
`media-asset/v1`, separate from the vector schema. The media contract records
texture dimensions, alpha policy, file-size limits, audio format, sample rate,
channel count, duration, peak level, loop policy, prompt/provenance, and manual
cleanup notes.

Celestial and station vector outputs are generated alongside ships, asteroids,
and bullets. Approved celestial source specifications build to
`assets/generated/celestial/`, while approved station specifications build to
`assets/generated/stations/`. Gameplay integration for these categories belongs
to the consuming feature issues; this pipeline only produces reviewed resources
and gallery visibility.

## Asset IDs and file names

Use lowercase snake case for every asset ID and file stem:

- Ship family: `ship_interceptor_01`, `ship_scout_01`
- Asteroid family: `asteroid_rocky_01`, `asteroid_ice_01`
- Bullet family: `bullet_plasma_01`, `bullet_tracer_01`
- Celestial family: `celestial_planet_01`, `celestial_moon_01`
- Station family: `station_dock_01`, `station_trade_01`
- Prompt file: `ship_interceptor_vector_prompt.md`
- Approved vector spec: `ship_interceptor_01.json`

IDs should include the category, a short readable family name, and a two-digit
variant number. Do not encode provider names, model names, dates, or reviewer
names in asset IDs; keep those details in provenance metadata.

## Provenance metadata

Every approved source specification must include these fields or their schema
equivalents:

- `asset_id`: Stable lowercase snake case ID.
- `category`: `ship`, `asteroid`, `bullet`, `celestial`, `station`,
  `effect`, `presentation`, or `audio`.
- `schema_version`: Version of the schema used for validation.
- `generator`: Provider, tool, or procedural script name when known.
- `model`: Model name or version when known.
- `prompt_file`: Path to the prompt or generation note.
- `prompt_revision`: Git commit, short hash, or documented revision label.
- `created_at`: ISO 8601 date or timestamp.
- `seed`: Seed value when available.
- `manual_edits`: Human edits made after generation.
- `approval_status`: `draft`, `approved`, or `rejected`.
- `reviewer`: GitHub handle or local reviewer name for approved assets. An
  agent name is a legitimate value here, including when it matches
  `generator` — art in this repo may be self-approved by the agent that
  produced it. Record who actually signed off; never substitute a human
  handle for a review that human did not perform.
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

## Repeatable Prompt Workflow

Provider-neutral prompts live under `art/prompts/`. The baseline workflow does
not require a provider SDK or API key:

1. Read the relevant prompt, `art/schemas/vector-asset.schema.json`,
   [the art style guide](art-style-guide.md), and this contract.
2. Ask Codex or another model to return JSON-only candidate assets.
3. Save small reviewable candidates under `art/generated/examples/`, or keep
   bulk/local provider output untracked.
4. Validate candidates:

   ```sh
   python3 tools/asset_pipeline/validate_assets.py art/generated/examples
   ```

5. Build temporary review resources from the candidates:

   ```sh
   python3 tools/asset_pipeline/build_assets.py --source-dir art/generated/examples --output-dir art/generated/review_assets --allow-unapproved
   ```

6. Review candidates in the gallery with the temporary manifest:

   ```sh
   /home/japurane/.local/bin/godot --path . scenes/tools/AssetGallery.tscn -- --manifest=res://art/generated/review_assets/manifest.json
   ```

7. Record the decision in `art/experiments/`.
8. Promote one selected candidate explicitly:

   ```sh
   python3 tools/asset_pipeline/promote_asset.py art/generated/examples/ship_delta_01.json --asset-id ship_delta_01 --reviewer japurane
   ```

9. Rebuild production generated Godot resources:

   ```sh
   python3 tools/asset_pipeline/build_assets.py
   ```

Prompt revisions and model details belong in each candidate's `provenance`
object and in the experiment record. Record source/provider terms and ownership
notes, but do not make unsupported legal claims. If terms are unclear, keep the
candidate out of `art/approved/`.

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

## Adding raster and audio media

1. Add or update a provider-neutral prompt under `art/prompts/`.
2. Save the reviewed media source specification under `art/approved/media/`.
3. Keep raster and audio contracts separate from `vector-asset/v1`; media uses
   `media-asset/v1` and [the media schema](../art/schemas/media-asset.schema.json).
4. Build the runtime PNG/WAV outputs:

   ```sh
   python3 tools/asset_pipeline/build_media_assets.py
   ```

5. Validate the approved specs and generated outputs:

   ```sh
   python3 tools/asset_pipeline/validate_media_assets.py art/approved/media
   python3 tools/asset_pipeline/build_media_assets.py --check
   ```

6. Integrate small assets through existing scene boundaries. Backgrounds should
   stay behind gameplay entities, HUD icons should remain readable at mobile
   scale, and short sound/effect assets should route through `Feedback` or
   another presentation node rather than gameplay state.
7. Verify desktop and Android startup after adding runtime media. Compare APK
   size when adding large textures or longer audio.

The validator exits non-zero for malformed metadata, duplicate asset IDs,
degenerate polygons, self-intersections, unsupported categories, oversized
bounds, off-center primary polygons, invalid ship orientation, asymmetric assets
that require symmetry, and non-convex collision polygons.

## Generating Godot resources

Build all approved assets into Godot `.tres` resources:

```sh
python3 tools/asset_pipeline/build_assets.py
```

Verify the generated resources are current without writing files:

```sh
python3 tools/asset_pipeline/build_assets.py --check
```

Confirm the generated resources load in Godot:

```sh
/home/japurane/.local/bin/godot --headless --path . --script tools/asset_pipeline/check_generated_assets.gd
```

The builder validates every source asset before writing any output. It only
reads `art/approved/` by default; pass `--source-dir` with
`--allow-unapproved` when intentionally testing staging input. Generated vector
resources are written to category directories under `assets/generated/`, while
generated material definitions are written to `assets/generated/materials/`.
The manifest at `assets/generated/manifest.json` is deterministic and contains
no timestamps.

The builder creates or updates only files declared by the current build. It does
not delete unknown files automatically. In `--check` mode, it reports missing or
stale generated files and also flags files still listed by an older manifest
when those files are no longer part of the current generated set.

## Reviewing generated assets in-engine

Launch the asset gallery scene without changing the committed main scene:

```sh
/home/japurane/.local/bin/godot --path . scenes/tools/AssetGallery.tscn
```

Launch it against a temporary candidate-review manifest:

```sh
/home/japurane/.local/bin/godot --path . scenes/tools/AssetGallery.tscn -- --manifest=res://art/generated/review_assets/manifest.json
```

The gallery reads `assets/generated/manifest.json` by default, or a manifest
provided with `--manifest=...`, groups generated vector assets by category, and
shows canonical, rotating, gameplay-scale, and phone-scale previews. Use the
toolbar to switch categories, pause rotation, and toggle collision or bounds
overlays. Broken or missing generated resources are reported in the detail
panel instead of crashing the gallery.

Smoke-test the gallery without opening a desktop window:

```sh
/home/japurane/.local/bin/godot --headless --path . --script tools/asset_pipeline/check_asset_gallery.gd
```

Capture a local contact sheet for review:

```sh
/home/japurane/.local/bin/godot --path . --script tools/asset_pipeline/capture_asset_gallery.gd -- --output=res://art/generated/asset_gallery_contact_sheet.png
```

Contact-sheet capture needs a rendering display driver; use the smoke-test
command for headless automation.

For Android review, temporarily launch the same scene from the editor or a local
export override, then discard the local scene-setting change before committing.
The committed `project.godot` main scene must remain `res://scenes/game/Main.tscn`.

## Runtime Variant Selection

Gameplay uses approved generated vector resources without changing simulation
rules. `Game.tscn` owns the asteroid visual pool and `scripts/game.gd` chooses
one asteroid visual per spawn using the same seeded `RandomNumberGenerator`
that already controls positions and velocities. Split children choose their own
deterministic visuals from the same pool; scoring, speed ranges, child counts,
and collision radius tiers remain unchanged.

Entity scenes keep safe default visuals from `assets/generated/` so an empty or
invalid asteroid pool falls back to a valid baseline. Runtime code treats shared
`.tres` resources as immutable and only changes per-instance scene nodes.

Check deterministic runtime variant selection:

```sh
/home/japurane/.local/bin/godot --headless --path . --script tools/asset_pipeline/check_runtime_variants.gd
```
