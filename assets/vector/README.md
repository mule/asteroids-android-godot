# Runtime vector resources

This directory contains Godot-ready `VectorAssetDefinition` resources consumed
by entity scenes through their exported `visual_asset` properties.

The baseline resources reproduce the original embedded `Polygon2D` visuals:

- `baseline_ship.tres`
- `baseline_asteroid.tres`
- `baseline_bullet.tres`

Outlines are currently stored as resource metadata only. Rendering them can be
added later when the asset gallery defines the preview and review controls.
