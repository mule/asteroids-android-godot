# Celestial Body Vector Prompt

Create JSON-only candidate source files for distant top-down celestial vector
assets: one planet and one moon.

Read first:

- `art/schemas/vector-asset.schema.json`
- `docs/art-style-guide.md`
- `docs/asset-pipeline.md`

Output constraints:

- Return only JSON objects or a JSON array of objects. Do not include prose.
- Use `schema_version: "vector-asset/v1"`.
- Use `category: "celestial"`.
- Use asset IDs like `celestial_planet_01` and `celestial_moon_01`.
- Keep the primary polygon centered near the origin.
- Keep the moon near 260 pixels across and the planet near 400 pixels across.
- Use broad, simple rounded silhouettes with 10-18 vertices.
- Avoid high-contrast outlines, baked directional shadows, and obstacle-like
  crags.
- Use low-saturation fills with a `lit_vector` material and restrained diffuse
  response.
- Use circular collision metadata only as review/debug bounds; gameplay wiring
  belongs to the consuming issue.
- Set `approval.status` to `draft` and `approval.reviewer` to `unreviewed`.
- Record provider/model/prompt details in `provenance`; use `unknown` only when
  the detail is genuinely unknown.

Review goals:

- The asset should read as background scenery at phone scale.
- It must not compete with asteroids, bullets, or the player ship.
- Shader-driven lighting should carry the volume impression without baked
  shadows.
