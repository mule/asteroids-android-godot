# Design: A scrolling sector — from one screen to an explorable space

Date: 2026-08-19
Status: Approved for planning
Epic: [#43](https://github.com/mule/asteroids-android-godot/issues/43)

## Goal

Replace the single fixed screen with a large bounded sector that the camera
scrolls through as the ship flies. The sector contains asteroid fields,
planets, moons, space stations, and other ships of several sizes. The game's
theme shifts from pure arcade Asteroids toward a Space Rangers style open
sector: the player survives, earns credits, and docks at stations to repair
and refuel.

This epic delivers the sector layer and enough of the new loop to prove the
theme. Trading, factions, quests, ship upgrades, and multiple star systems are
explicitly out of scope and become later epics.

## Why now

The asset pipeline epic (#22) stated that its results should "provide reusable
lessons and tooling for a later Space Rangers-inspired game". The vector asset,
material, and media pipeline is complete, so new entity families (planets,
moons, stations, ship classes) can now be produced through an established
process instead of hand-authored polygons. The remaining blocker to a larger
game is that the world is literally the size of the viewport.

## Current state

The world is the viewport. Six places encode that assumption:

- `scripts/player_ship.gd` `_wrap_to_visible_viewport()` uses `get_viewport_rect()`.
- `scripts/asteroid.gd` `_wrap_to_visible_viewport()` — a second copy.
- `scripts/bullet.gd` `_wrap_to_visible_viewport()` — a third copy.
- `scripts/game.gd` `_get_safe_spawn_position()` samples the viewport rect.
- `scripts/game.gd` `_respawn_player()` spawns at `get_viewport_rect().get_center()`.
- `scripts/starfield.gd` `_build_stars()` scatters stars inside the viewport rect.

Additionally `scenes/game/Game.tscn` holds a `Background` `ColorRect` and a
`BackgroundTexture` `TextureRect` fixed at 1152x648, and a `PlayArea` collision
box of the same size that nothing currently reads.

`scripts/game.gd` is 412 lines and already owns deterministic RNG, spawning,
splitting, scoring, waves, lighting propagation, HUD updates, pause, and
respawn. It must shed responsibilities during this epic rather than absorb
more.

`tests/test_asteroid_collisions.gd` covers asteroid-asteroid collision response
and must continue to pass.

## Design principles

- One authority for world bounds. No script asks the viewport where the world ends.
- The sector is reproducible from a definition plus a seed, matching the
  existing deterministic RNG discipline (`random_seed = 1729`).
- Simulation extent is independent of visible extent.
- No unwinnable states. Every failure mode must be recoverable or must end the run.
- Shared behavior uses static-method helper scripts preloaded as constants, the
  idiom already established by `scripts/material_runtime.gd`. No new base-class
  hierarchy for entities.
- Gameplay logic stays separate from visual asset definitions, per the asset
  pipeline contract.
- Each child issue is independently shippable and independently verifiable.

## Architecture

### Coordinate and bounds model

The sector is an axis-aligned rectangle in world space with its origin at
`Vector2.ZERO` and size taken from a `SectorDefinition`. Default 8000x6000.

Entities live in world coordinates. The camera maps world to screen. Nothing
wraps.

### New resources — `scripts/resources/`

`sector_definition.gd` (extends `Resource`)

    world_size            Vector2   default (8000, 6000)
    sector_seed           int       default 1729
    boundary_margin       float     default 600.0
    asteroid_field_count  int
    planet_count          int
    moon_count            int
    station_count         int
    min_landmark_separation float
    threat_curve          Curve     threat level over elapsed time

`ship_class_definition.gd` (extends `Resource`)

    class_id              StringName
    max_hull              float
    acceleration          float
    max_speed             float
    turn_speed_degrees    float
    collision_radius      float
    weapon_cooldown       float
    weapon_damage         float
    visual_asset          Resource
    ai_profile            StringName   hostile | freighter | defender

`celestial_body_definition.gd` (extends `Resource`)

    body_id               StringName
    body_radius           float
    gravity_strength      float
    influence_multiplier  float   default 4.0
    visual_asset          Resource
    orbit_radius          float   0 for planets, > 0 for moons
    orbit_period_seconds  float

### New runtime scripts — `scripts/world/`

`world_bounds.gd` — static helpers, no state:

    static func clamp_to_sector(position, bounds) -> Vector2
    static func reflect_velocity_at_edge(position, velocity, bounds, radius) -> Vector2
    static func edge_pressure(position, bounds, margin) -> Vector2
    static func is_outside(position, bounds) -> bool

Replaces all three copies of `_wrap_to_visible_viewport()`.

`sector.gd` — a `Node2D` that owns the active `SectorDefinition`, exposes
`get_bounds()`, and performs seeded placement of fields, planets, moons, and
stations with a minimum-separation constraint.

`gravity_field.gd` — static. Accumulates acceleration at a world position from
all nodes in the `gravity_sources` group, contributing zero outside each
body's influence radius.

`activation.gd` — static. Given a camera position and an activation radius,
enables or disables simulation on registered groups.

`threat_director.gd` — a `Node` that raises threat level over elapsed run time
and schedules hostile patrol spawns. Replaces the wave rule.

`ship_systems.gd` — a `Node` component holding hull, fuel, and credits, with
signals for damage, depletion, and destruction. Attached to the player ship.

### New scenes

- `scenes/world/AsteroidField.tscn` — a region node owning an asteroid budget.
- `scenes/entities/CelestialBody.tscn` — planet or moon.
- `scenes/entities/SpaceStation.tscn` — hull plus a dock zone `Area2D`.
- `scenes/entities/AiShip.tscn` — driven by a `ShipClassDefinition`.
- `scenes/ui/SectorMap.tscn` — minimap and off-screen markers.
- `scenes/ui/DockPanel.tscn` — station services.

### Camera

A `Camera2D` child of `Game`, following the player ship, configured with:

- `position_smoothing_enabled = true`, speed tuned for readability.
- Drag margins so small movements do not shake the view.
- Look-ahead: camera offset proportional to ship velocity, clamped, so the
  player sees where they are heading rather than where they have been.
- `limit_left/top/right/bottom` set from sector bounds, so the camera never
  shows outside the sector. This is engine-provided and requires no clamping code.

`Hud` is already a `CanvasLayer` and stays screen-fixed with no change.

### Nodes removed or replaced

- `Game.tscn` `Background` and `BackgroundTexture` fixed-size `Control` nodes are
  replaced by `Parallax2D` layers that follow the camera.
- `Game.tscn` `PlayArea` and its 1152x648 `PlayAreaBounds` collision box are
  removed. Nothing reads them today, and `SectorDefinition` becomes the single
  source of world extent.
- `scripts/starfield.gd` is replaced by seeded parallax star layers. Star
  placement moves from the viewport rect to sector space and is driven by
  `sector_seed`.

### Responsibility extraction from `game.gd`

- Spawning and placement move to `sector.gd` and `AsteroidField`.
- Player hull, fuel, and credits move to `ship_systems.gd`.
- Wave progression is deleted and replaced by `threat_director.gd`.
- `game.gd` retains coordination: wiring signals, starting and ending runs,
  pause, and lighting propagation.

## Behavior rules

### Soft sector boundary

A margin band of `boundary_margin` pixels inside each sector edge.

- Player ship: a restoring acceleration ramping from zero at the band's inner
  edge to `1.5 x ship acceleration` at the wall, plus a `LEAVING SECTOR` HUD
  warning while inside the band. Position is hard-clamped at the wall so the
  ship can never exit.
- Asteroids and AI ships: velocity reflects at the wall, preserving speed.
- Bullets: despawn at the wall.

### Gravity

Only inside `influence_radius = influence_multiplier x body_radius`, default
4x. Force falls off as inverse square of distance, normalized so that
acceleration at the body surface is at most `0.7 x player max thrust
acceleration`. Full thrust therefore always escapes, by construction rather
than by tuning. Outside the influence radius the contribution is exactly zero.

Applies to the player ship, asteroids, and AI ships. Bullets are unaffected,
keeping aiming predictable.

### Hull, fuel, credits

- Hull depletes from asteroid collisions, enemy fire, and station or body impact.
- Fuel drains while thrusting.
- At zero fuel the ship drops to 25 percent reserve thrust rather than losing
  thrust entirely. A hard fuel-out in an 8000x6000 sector is an unwinnable
  soft-lock that no balancing removes; reserve thrust makes it a costly setback
  instead.
- The run ends when hull reaches zero. Restart generates a new sector seed.
- Credits are earned from destroying asteroids and hostile ships, and from
  clearing an asteroid field.

### Docking

Entering a station's dock zone below a speed threshold docks the ship. Docking
opens a service panel offering repair and refuel priced in credits. Undocking
releases the ship at a fixed offset with zero velocity.

### Progression

There are no waves. Threat level rises with elapsed run time along
`threat_curve`, increasing hostile patrol frequency and ship class. Asteroid
fields have budgets; clearing one pays a credit bonus and seeds a replacement
field elsewhere in the sector. The run ends at hull zero with a summary showing
credits earned, fields cleared, ships destroyed, and time survived.

## Child issues

Sequenced so that dependencies flow downward. Issues 1 through 4 are the
foundation and deliver scrolling. Issues 5 through 9 fill the sector. Issues 10
through 14 deliver the Space Rangers loop. Issues 15 and 16 make it playable
and shippable.

1. #44 Sector definition and world-bounds authority — `enhancement` `godot`
2. #45 Follow camera with sector limits and look-ahead — `enhancement` `godot`
3. #46 Soft sector boundary and containment — `enhancement` `godot`
4. #47 Parallax star layers and deep-space background — `enhancement` `godot`
5. #48 Asteroid fields with seeded placement — `enhancement` `godot`
6. #49 Entity activation and simulation budget — `enhancement` `godot` `android`
7. #50 Asset families for celestial bodies, stations, and ship classes — `enhancement` `documentation`
8. #51 Planets and moons — `enhancement` `godot`
9. #52 Local gravity wells — `enhancement` `godot`
10. #53 Ship systems: hull, fuel, and credits — `enhancement` `godot`
11. #54 Space stations with docking, repair, and refuel — `enhancement` `godot`
12. #55 AI ship framework and hostile interceptors — `enhancement` `godot`
13. #56 Neutral freighters and station defenders — `enhancement` `godot`
14. #57 Threat escalation and run summary — `enhancement` `godot`
15. #58 Sector map, minimap, and off-screen markers — `enhancement` `godot` `android`
16. #59 Android performance verification and documentation — `android` `documentation`

## Testing strategy

Existing coverage that must keep passing:

- `tests/test_asteroid_collisions.gd`. Gravity changes asteroid motion, so this
  test runs in a sector containing no gravity sources.
- The asset pipeline Python tests under `tests/asset_pipeline/`.

New coverage:

- Sector placement determinism: the same `SectorDefinition` and seed produce an
  identical layout, asserted on a sorted snapshot in the style of
  `get_active_asteroid_debug_snapshot()`.
- Boundary containment: no entity of any type ever reports a position outside
  sector bounds across a long simulated run.
- Gravity escapability: from rest at each body's surface, full thrust away from
  the body leaves the influence radius within a bounded time.
- Activation correctness: every entity deactivated by distance is reactivated
  when the camera returns, and no entity is permanently frozen.
- Fuel floor: at zero fuel the ship still accelerates at the reserve rate.
- Frame budget: physics frame time on an Android device stays within budget at
  the target entity count.

## Risks and mitigations

- Gravity destabilizing asteroid collision response. Mitigated by capping
  gravity acceleration well below collision separation impulse and by keeping
  the existing collision test gravity-free.
- Performance on Android at sector scale. Mitigated by issue 6 landing before
  the content-heavy issues, and by a frame budget test on device.
- `game.gd` growing further. Mitigated by extracting spawning, ship state, and
  progression into separate scripts as part of the epic.
- The sector feeling empty or unreadable. Mitigated by issue 15 delivering the
  minimap and off-screen markers, and by parallax depth in issue 4.
- Scope creep toward full Space Rangers systems. Mitigated by naming trading,
  factions, quests, upgrades, and multiple systems as out of scope here.

## Out of scope

Trade goods and market prices. Factions and reputation. Quests. Ship and weapon
upgrades. Multiple star systems and hyperjump. Persistent save between sessions.
Mining and cargo. Each is a candidate for a later epic that builds on this one.
