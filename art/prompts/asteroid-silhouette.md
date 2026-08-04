# Asteroid Vector Silhouette Prompt

Create JSON-only candidate source files for top-down Asteroids-style asteroid
vector assets.

Read first:

- `art/schemas/vector-asset.schema.json`
- `docs/art-style-guide.md`
- `docs/asset-pipeline.md`

Output constraints:

- Return only JSON objects or a JSON array of objects. Do not include prose.
- Use `schema_version: "vector-asset/v1"`.
- Use `category: "asteroid"`.
- Use asset IDs like `asteroid_shale_01` or `asteroid_cobalt_01`.
- Keep the primary polygon centered near the origin.
- Use 7-10 vertices.
- Keep width and height at or below 112 pixels.
- Avoid self-intersections, repeated points, and needle-like spikes.
- Use a circular collision shape with a radius that encloses the readable body.
- Use muted mineral fills with an `asteroid_faceted` material.
- Keep material IDs lowercase snake case and unique per visual family.
- Set `approval.status` to `draft` and `approval.reviewer` to `unreviewed`.
- Record provider/model/prompt details in `provenance`; use `unknown` only when
  the detail is genuinely unknown.

Review goals:

- The silhouette must remain readable at gameplay and phone scale.
- Rotation must not make the asset look directional or ship-like.
- Facet/noise settings should help surface texture without hiding the outline.
