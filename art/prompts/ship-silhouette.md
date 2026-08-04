# Ship Vector Silhouette Prompt

Create one JSON-only candidate source file for a top-down player ship vector
asset.

Read first:

- `art/schemas/vector-asset.schema.json`
- `docs/art-style-guide.md`
- `docs/asset-pipeline.md`

Output constraints:

- Return exactly one JSON object and no prose.
- Use `schema_version: "vector-asset/v1"`.
- Use `category: "ship"`.
- Use an asset ID like `ship_delta_01`.
- The ship faces `Vector2.UP`: one clear nose near `x = 0` at the smallest
  `y` value.
- Keep the main hull within 96 pixels wide and 128 pixels tall.
- Use balanced left/right geometry and set `requires_symmetry` to `true` unless
  the prompt explicitly asks for an asymmetric ship.
- Include a `thrust_flame` secondary polygon when the design needs thrust
  feedback.
- Use a convex collision polygon that approximates the hull.
- Use `lit_vector` for the hull and `emissive` for thrust.
- Set `approval.status` to `draft` and `approval.reviewer` to `unreviewed`.
- Record provider/model/prompt details in `provenance`; use `unknown` only when
  the detail is genuinely unknown.

Review goals:

- The forward direction must be obvious at gameplay scale.
- The hull should not depend on small internal details.
- Thruster geometry must sit behind the hull and avoid covering collision-
  critical space.
