# Concept Sheet Prompt

Use this prompt for raster concept sheets or visual references. Concept sheets
are not production vector assets and must not bypass schema validation or human
review.

Read first:

- `docs/art-style-guide.md`
- `docs/asset-pipeline.md`

Prompt:

Create a top-down arcade vector concept sheet for the Asteroids Android asset
pipeline. Show several ship, asteroid, projectile, thrust, and impact concepts
on a transparent or neutral dark background. Favor clear silhouettes, mobile
readability, centered pivots, canonical forward orientation for ships, and
neutral albedo without strong baked directional shadows.

Constraints:

- Do not include logos, text labels, UI chrome, or copyrighted franchise cues.
- Do not bake heavy cast shadows into rotating gameplay assets.
- Keep concepts compatible with later vector tracing or JSON polygon
  specification.
- Record provider, model, prompt revision, date, seed, source/license terms,
  and manual edits in an experiment record before promoting anything inspired
  by the sheet.
