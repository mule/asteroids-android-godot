# Shader resources

Shaders are written for Godot 4.7 CanvasItem rendering and the Mobile renderer.

- `vector_lit.gdshader`: clean stepped lighting for vector ships and similar
  readable hard-surface shapes.
- `asteroid_faceted.gdshader`: stepped lighting with deterministic facet/noise
  variation for rocky silhouettes.
- `emissive_unlit.gdshader`: unlit emission for bullets, thrust, muzzle flashes,
  impacts, and similar effects.

Keep shader loops and texture samples out of the first runtime path. The current
shaders use only per-fragment arithmetic and per-instance uniforms.
