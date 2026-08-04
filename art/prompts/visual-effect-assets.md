# Visual effect asset prompt

Use this prompt for small generated effect sprites or shader/particle preset
notes that augment, rather than replace, the existing procedural feedback.

Return one JSON media asset candidate using `media-asset/v1`:

- Kind: `effect`.
- Role: `impact_effect` for the first vertical slice.
- Format: PNG RGBA, transparent alpha required.
- Texture size: 64x64 or 128x128 unless a task explicitly needs more detail.
- Visual direction: short-lived flash, spark, plume, or impact bloom that reads
  over dark space but does not obscure asteroids, the player ship, or touch
  controls.
- Output path: `assets/media/effects/<asset_id>.png`.
- Include prompt, seed, cleanup, licensing/provenance, and approval metadata.

Prefer procedural Godot particles/shaders plus one small texture over large
sprite sheets.
