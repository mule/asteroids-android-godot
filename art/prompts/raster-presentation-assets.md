# Raster presentation asset prompt

Use this prompt for small generated PNG candidates such as backgrounds, title
images, and HUD icons.

Return one JSON media asset candidate using `media-asset/v1`. Keep the result
mobile-safe and gameplay-readable:

- Format: PNG RGBA, even when the asset is visually opaque.
- Background target: 1152x648, landscape 16:9, no hard horizon line, no bright
  center focal point, sparse stars, low contrast behind white/cyan gameplay
  vectors.
- HUD icon target: square, 64x64 or 128x128, transparent background, readable
  at 24px.
- Keep output paths under `assets/media/backgrounds/` or `assets/media/ui/`.
- Record `generator`, `model`, `prompt_file`, `prompt_revision`, `seed`,
  `manual_edits`, `source_license`, and concise review notes.

Do not include provider API keys, raw caches, or unapproved bulk outputs in the
candidate. If licensing or ownership is unclear, keep `approval.status` as
`draft`.
