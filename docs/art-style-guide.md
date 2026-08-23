# Art style guide

Parent epic: [#22](https://github.com/mule/asteroids-android-godot/issues/22)

The initial art direction is a top-down vector arcade presentation that can
grow beyond the current embedded `Polygon2D` shapes without making gameplay
logic depend on one visual implementation.

## Core direction

- The camera reads the playfield from directly above.
- Motion, collision, and aiming remain clear before decorative detail.
- Shapes should feel compatible with classic Asteroids, but not be limited to
  monochrome wireframes.
- Assets must work on phone and tablet screens in landscape orientation.
- The player ship faces `Vector2.UP`; generated ship geometry must use that
  orientation as its forward direction.

## Current scale anchors

Use the existing polygon scenes as the first scale reference:

- Player ship: roughly 36 pixels wide and 78 pixels tall including thrust.
- Asteroid: roughly 86 pixels across before size-tier scaling.
- Bullet: roughly 12 pixels wide and 16 pixels tall.
- Moon: roughly 260 pixels across.
- Planet: roughly 900 pixels across.
- Space station: roughly 320 pixels across, with docking approach geometry
  readable from the silhouette.
- Interceptor ship: roughly 30 pixels wide and 60 pixels tall, 78 including
  thrust.
- Gunship: roughly 70 pixels wide and 110 pixels tall, 135 including thrust.
- Freighter: roughly 120 pixels wide and 190 pixels tall, 219 including thrust.

Ship heights are quoted hull-first, then with the thrust flame, because the two
differ enough to mislead: the player ship's 78 is a with-thrust figure over a
36x50 hull, and the interceptor's hull-only 60 is also 78 once thrust is
included. Validator limits in `tools/asset_pipeline/validate_assets.py` bound
the hull polygon only, so compare hull figures when reading them.

At normal gameplay zoom, a player should recognize the ship nose, asteroid
outline, and bullet direction without pausing. At enlarged gallery scale, the
same asset may show extra contour detail, paneling, facets, or impact marks.

## Silhouettes

- Ships need a clear forward point and balanced left/right profile.
- Asteroids should have irregular outlines with no fragile needle-like spikes.
- Planets and moons should read as distant scenery: large, calm, and lower
  contrast than collision-critical entities.
- Stations should expose a clear dock approach silhouette that remains legible
  before any tutorial copy or docking UI exists.
- Bullets should be compact, high contrast, and readable while moving quickly.
- Avoid tiny interior features that only work in an enlarged preview.
- Collision geometry may stay simpler than the visible outline.

## Palette and contrast

Use a limited palette per asset family:

- Ship hulls: pale neutral fills, cool metal tints, or restrained accent colors.
- Thruster effects: warm orange, amber, or yellow with controlled transparency.
- Asteroids: neutral gray, blue gray, slate, or muted mineral colors.
- Celestial bodies: low-saturation blues, violets, grays, or muted mineral
  tones with restrained contrast so they never compete with asteroids.
- Stations: neutral albedo panels with small, purposeful accent colors around
  docking geometry.
- Bullets: bright yellow, white, cyan, or green when the gameplay state needs a
  distinct read.

Keep foreground assets visibly separated from the dark playfield and starfield.
Do not rely on subtle hue shifts alone; silhouettes and value contrast must do
most of the readability work.

## Outlines, fills, and transparency

- Vector assets may use filled polygons, outlined polygons, or both.
- Outlines should improve readability at mobile size, not create visual noise.
- Transparent fills are allowed for effects such as thrust, glow, and brief
  impact feedback.
- Core ship, asteroid, and bullet bodies should remain mostly opaque.
- Avoid broad soft glows until the raster/effects phase defines import rules.

## Lighting and rotation

The game rotates ships, bullets, and asteroids in real time, so lighting must
remain believable from every angle:

- Prefer neutral top-down lighting, simple rim accents, or stylized facets.
- Avoid strong directional shadows baked into one side of a rotating object.
- Do not paint a fixed external light source that contradicts rotation.
- Asteroid facets may imply volume, but the silhouette must still carry the
  gameplay read.
- Runtime vector assets may use shared shader-driven lighting. The authoritative
  light direction lives in the game controller and is transformed into each
  rotating object's local shader space so highlights appear stable in world
  space.
- Use 3-5 stepped lighting bands for the initial arcade look. Avoid expensive
  realistic shading until Android and Steam Deck targets have been profiled.
- Keep an unlit fallback available for debugging and readability comparison.

## Effects

Effects should clarify state:

- Thrust indicates acceleration and should sit behind the ship body.
- Bullet color should separate shots from stars and asteroid fragments.
- Bullets and thrust should use the emissive/unlit material path rather than
  diffuse lighting.
- Explosion, hit, and spawn effects may be more expressive in later issues, but
  they must not obscure collision-critical objects for long.

## Purchased raster asset contract

Purchased or generated raster assets are compatible with the shared lighting
direction only when they meet these constraints:

- Transparent top-down source with a centered pivot and canonical forward
  orientation.
- Neutral albedo or very weak baked lighting.
- No cast shadow or directional drop shadow baked into the color texture.
- Optional normal and emission maps are welcome when they match the same pivot,
  scale, and orientation as the albedo.
- Highlights and shadows must not visibly rotate against the world light when
  the object spins.

## Mobile readability checks

Review each candidate at:

- Native gameplay size.
- Half-size phone readability.
- Enlarged gallery inspection size.
- Rotating preview for ships, asteroids, and bullets.

Reject assets that only look good when enlarged, blur into the starfield, lose
their forward direction, or depend on a fixed lighting angle.
