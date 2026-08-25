# Space Station Vector Prompt

Create one JSON-only candidate source file for a top-down vector space station.

Read first:

- `art/schemas/vector-asset.schema.json`
- `docs/art-style-guide.md`
- `docs/asset-pipeline.md`

Output constraints:

- Return exactly one JSON object and no prose.
- Use `schema_version: "vector-asset/v1"`.
- Use `category: "station"`.
- Use an asset ID like `station_dock_01`.
- Keep the main station roughly 320 pixels across and centered near the origin.
- Include a visually obvious dock approach using a secondary polygon with a
  purposeful accent color.
- Keep the silhouette broad and mechanically readable, with no fragile antenna
  spikes.
- Use a neutral `lit_vector` material for the hull and an `emissive` material
  only for small docking accents.
- Use simple collision metadata for gallery review; gameplay docking behavior
  belongs to the consuming issue.
- Set `approval.status` to `draft` and `approval.reviewer` to `unreviewed`.
- Record provider/model/prompt details in `provenance`; use `unknown` only when
  the detail is genuinely unknown.

Review goals:

- The dock approach should be discoverable from silhouette and color alone.
- The station should look like scenery/infrastructure, not a ship or asteroid.
- Rotation should not imply a fixed baked light source.
