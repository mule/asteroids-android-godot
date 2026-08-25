# Ship Classes Vector Prompt

Create JSON-only candidate source files for three top-down ship class vectors:
interceptor, gunship, and freighter.

Read first:

- `art/schemas/vector-asset.schema.json`
- `docs/art-style-guide.md`
- `docs/asset-pipeline.md`

Output constraints:

- Return only JSON objects or a JSON array of objects. Do not include prose.
- Use `schema_version: "vector-asset/v1"`.
- Use `category: "ship"`.
- Use asset IDs `ship_interceptor_01`, `ship_gunship_01`, and
  `ship_freighter_01`.
- All ships face `Vector2.UP`: one clear nose near `x = 0` at the smallest
  `y` value.
- Keep the interceptor near 30x60 pixels, the gunship near 70x110 pixels, and
  the freighter near 120x190 pixels.
- Use balanced left/right geometry and set `requires_symmetry` to `true` unless
  a future prompt explicitly asks for asymmetry.
- Include a `thrust_flame` secondary polygon for each ship.
- Use a convex collision polygon that approximates each hull.
- Use `lit_vector` for hulls and `emissive` for thrust.
- Set `approval.status` to `draft` and `approval.reviewer` to `unreviewed`.
- Record provider/model/prompt details in `provenance`; use `unknown` only when
  the detail is genuinely unknown.

Review goals:

- The three classes should be distinguishable by silhouette before color.
- The forward direction must remain obvious at phone scale.
- The freighter can be large, but it should not become visually noisy.
