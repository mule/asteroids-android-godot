# Bullet Projectile Vector Prompt

Create JSON-only candidate source files for compact projectile vector assets.

Read first:

- `art/schemas/vector-asset.schema.json`
- `docs/art-style-guide.md`
- `docs/asset-pipeline.md`

Output constraints:

- Return only JSON objects or a JSON array of objects. Do not include prose.
- Use `schema_version: "vector-asset/v1"`.
- Use `category: "bullet"`.
- Use asset IDs like `bullet_plasma_01` or `bullet_tracer_01`.
- Keep the primary polygon within 32 pixels wide and 40 pixels tall.
- Use 3-6 vertices with a clear travel direction when appropriate.
- Avoid tiny ornamental points and self-intersections.
- Use a small circle collision shape.
- Use high-contrast fill colors and an `emissive` material.
- Set `approval.status` to `draft` and `approval.reviewer` to `unreviewed`.
- Record provider/model/prompt details in `provenance`; use `unknown` only when
  the detail is genuinely unknown.

Review goals:

- The projectile must separate clearly from stars and asteroid fragments.
- It should remain readable while moving quickly.
- Emission should help readability without becoming a large soft glow.
