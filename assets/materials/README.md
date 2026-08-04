# Runtime material resources

This directory contains `AssetMaterialDefinition` resources consumed by vector
assets and later raster assets.

The first material set is:

- `baseline_ship_lit.tres`: shared stepped lighting for the player ship.
- `baseline_asteroid_lit.tres`: faceted/noisy stepped lighting for asteroids.
- `baseline_bullet_emissive.tres`: unlit emissive bullet material.
- `baseline_thrust_emissive.tres`: unlit emissive thrust material.

Entity scripts duplicate shader materials once per instance before assigning
per-instance shader parameters. This keeps shared `.tres` resources immutable
while still allowing each rotating object to receive its own local light
direction.
