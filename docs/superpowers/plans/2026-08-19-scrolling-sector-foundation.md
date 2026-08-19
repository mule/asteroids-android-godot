# Scrolling Sector: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the scrolling foundation — a large bounded sector, a follow camera, soft edges that contain every entity, and parallax depth — so the game visibly scrolls with the ship.

**Scope:** This plan covers child issues #44, #45, #46, and #47 of epic #43. The
epic's remaining twelve issues are independent subsystems that build on this
foundation and get their own plans once it lands:

- `2026-08-19-scrolling-sector-content.md` — issues #48-#52: asteroid fields, activation, asset families, planets and moons, gravity.
- `2026-08-19-scrolling-sector-loop.md` — issues #53-#57: hull/fuel/credits, stations and docking, AI ships, threat escalation.
- `2026-08-19-scrolling-sector-navigation.md` — issues #58-#59: sector map, Android performance verification and docs.

Each plan produces working, testable software on its own.

**Architecture (whole epic):** A `SectorDefinition` resource plus a seeded `Sector` node become the single authority for world extent, replacing every `get_viewport_rect()` call. A `Camera2D` with engine-provided limits decouples simulation extent from visible extent. Shared behavior (bounds, gravity, activation) lives in static-method helper scripts preloaded as constants, following the existing `scripts/material_runtime.gd` idiom rather than a class hierarchy. Responsibilities are extracted out of `scripts/game.gd` as the epic proceeds so it ends smaller than it started.

**Tech Stack:** Godot 4.7 (Mobile renderer), GDScript, Android export target. Tests are `SceneTree` scripts run headless.

**Spec:** `docs/superpowers/specs/2026-08-19-scrolling-sector-design.md`

## Global Constraints

- Godot 4.7.x. `project.godot` declares `config/features=PackedStringArray("4.7", "Mobile")`. Do not use nodes or APIs added after 4.7.
- Godot binary is at `/home/japurane/.local/bin/godot`. Every verification command in this plan uses that absolute path.
- Target platform is Android, landscape (`window/handheld/orientation=0`), package `com.japurane.asteroids`.
- All randomness must go through a seeded `RandomNumberGenerator`. Never call the global `randf()`/`randi()` in gameplay code. The existing seed discipline is `random_seed = 1729`.
- Tests are `extends SceneTree` scripts that collect failures into an `Array[String]`, print `FAIL: ` lines via `printerr`, and end with `quit(0)` on success or `quit(1)` on failure. Match `tests/test_asteroid_collisions.gd` exactly.
- Run any test with: `/home/japurane/.local/bin/godot --headless --path . --script tests/<file>.gd`
- `tests/test_asteroid_collisions.gd` must pass after every single task. It is the regression gate for the whole epic.
- Shared behavior uses static functions on a script preloaded as a `const`, e.g. `const WORLD_BOUNDS := preload("res://scripts/world/world_bounds.gd")`. Do not introduce entity base classes.
- GDScript style in this repo: tabs for indentation, typed variables (`var x: float`), typed function signatures, two blank lines between top-level functions, `snake_case` members, leading underscore for private members.
- Commit after every task. Never commit generated APKs or `.godot/`.
- Godot generates a `.uid` file next to every new `.gd` script on first import.
  These are project source metadata and must be committed alongside the script.
  Run the editor or a headless import (`godot --headless --path . --quit`) after
  creating a script so its `.uid` exists before you stage the commit.

## File Structure

**Created**

| Path | Responsibility |
|---|---|
| `scripts/resources/sector_definition.gd` | Declarative sector: size, seed, content counts, margins, threat curve |
| `scripts/resources/ship_class_definition.gd` | Per-ship-class stats and visual asset |
| `scripts/resources/celestial_body_definition.gd` | Planet/moon radius, mass, gravity, orbit |
| `scripts/world/world_bounds.gd` | Static bounds math: clamp, reflect, edge pressure |
| `scripts/world/sector.gd` | Owns bounds; seeded placement of all sector content |
| `scripts/world/gravity_field.gd` | Static gravity accumulation from `gravity_sources` group |
| `scripts/world/activation.gd` | Static distance-based simulation enable/disable |
| `scripts/world/threat_director.gd` | Time-driven threat level and hostile scheduling |
| `scripts/entities/ship_systems.gd` | Hull, fuel, credits component with signals |
| `scripts/entities/celestial_body.gd` | Planet/moon behavior and orbiting |
| `scripts/entities/space_station.gd` | Station hull, dock zone, docking state |
| `scripts/entities/ai_ship.gd` | AI ship steering and state machine |
| `scripts/world/asteroid_field.gd` | One field's budget, seeding, and cleared state |
| `scripts/ui/sector_map.gd` | Minimap rendering and off-screen markers |
| `scripts/ui/dock_panel.gd` | Station service UI |
| `scenes/world/AsteroidField.tscn` | Field region node |
| `scenes/entities/CelestialBody.tscn` | Planet/moon scene |
| `scenes/entities/SpaceStation.tscn` | Station scene with dock area |
| `scenes/entities/AiShip.tscn` | AI ship scene |
| `scenes/ui/SectorMap.tscn` | Minimap CanvasLayer |
| `scenes/ui/DockPanel.tscn` | Dock services CanvasLayer |
| `assets/sectors/sector_default.tres` | The default sector definition |

**Modified**

| Path | Change |
|---|---|
| `scripts/player_ship.gd` | Wrap replaced by bounds clamp + edge pressure; gravity; fuel-gated thrust |
| `scripts/asteroid.gd` | Wrap replaced by edge reflection; gravity |
| `scripts/bullet.gd` | Wrap replaced by despawn at bounds |
| `scripts/game.gd` | Sheds spawning, ship state, and wave logic; coordinates only |
| `scripts/starfield.gd` | Replaced by seeded parallax layers in sector space |
| `scripts/hud.gd` | Hull/fuel bars, credits, sector label, boundary warning |
| `scenes/game/Game.tscn` | Camera, Sector, parallax layers; `PlayArea` and fixed backgrounds removed |
| `tests/test_asteroid_collisions.gd` | Runs in a gravity-free sector so existing assertions hold |
| `README.md`, `docs/` | Controls, sector concept, verification commands |

**Deleted**

- `scenes/game/Game.tscn` nodes `Background`, `BackgroundTexture`, `PlayArea`, `PlayArea/PlayAreaBounds`.

---

### Task 1 (#44): Sector definition and world-bounds authority

Pure refactor. Behavior after this task is byte-for-byte identical to before: the
default sector is exactly viewport-sized and entities still wrap. Only the
*source* of the bounds changes, from `get_viewport_rect()` to the sector.

**Files:**
- Create: `scripts/resources/sector_definition.gd`
- Create: `scripts/world/world_bounds.gd`
- Create: `scripts/world/sector.gd`
- Create: `assets/sectors/sector_default.tres`
- Modify: `scripts/player_ship.gd` (replace `_wrap_to_visible_viewport`, lines 105-119)
- Modify: `scripts/asteroid.gd` (replace `_wrap_to_visible_viewport`, lines 228-241)
- Modify: `scripts/bullet.gd` (replace `_wrap_to_visible_viewport`, lines 57-70)
- Modify: `scripts/game.gd` (`_get_safe_spawn_position`, `_respawn_player`)
- Modify: `scenes/game/Game.tscn` (add `Sector` node)
- Test: `tests/test_world_bounds.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `SectorDefinition` resource with `world_size: Vector2`, `sector_seed: int`, `boundary_margin: float`, `asteroid_field_count: int`, `planet_count: int`, `moon_count: int`, `station_count: int`, `min_landmark_separation: float`, `threat_curve: Curve`, and `func get_bounds() -> Rect2`.
  - `WorldBounds` static class with `wrap_to_bounds(position: Vector2, bounds: Rect2, margin: float) -> Vector2`, `clamp_to_sector(position: Vector2, bounds: Rect2, radius: float) -> Vector2`, `is_outside(position: Vector2, bounds: Rect2, radius: float) -> bool`, `reflect_velocity_at_edge(position: Vector2, velocity: Vector2, bounds: Rect2, radius: float) -> Vector2`, `edge_pressure(position: Vector2, bounds: Rect2, margin: float) -> Vector2`.
  - `Sector` node with `func get_bounds() -> Rect2`, `func get_center() -> Vector2`, `func get_random_position(rng: RandomNumberGenerator) -> Vector2`, and an exported `definition: Resource`.
  - Every entity gains `var sector_bounds: Rect2` and `func set_sector_bounds(bounds: Rect2) -> void`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_world_bounds.gd`:

```gdscript
extends SceneTree


const WORLD_BOUNDS := preload("res://scripts/world/world_bounds.gd")


func _init() -> void:
	var failures: Array[String] = []

	_test_wrap_matches_legacy_behavior(failures)
	_test_clamp_keeps_position_inside(failures)
	_test_is_outside_respects_radius(failures)
	_test_reflect_only_when_moving_outward(failures)
	_test_edge_pressure_ramps_inward(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL WORLD BOUNDS TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


func _test_wrap_matches_legacy_behavior(failures: Array[String]) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(1152.0, 648.0))
	var margin := 32.0

	# Exiting the left edge reappears at the right, exactly as the old
	# _wrap_to_visible_viewport did.
	var wrapped := WORLD_BOUNDS.wrap_to_bounds(Vector2(-40.0, 300.0), bounds, margin)
	if not is_equal_approx(wrapped.x, 1184.0):
		failures.append("Wrap: expected x 1184.0 crossing left edge, got %f" % wrapped.x)

	wrapped = WORLD_BOUNDS.wrap_to_bounds(Vector2(1200.0, 300.0), bounds, margin)
	if not is_equal_approx(wrapped.x, -32.0):
		failures.append("Wrap: expected x -32.0 crossing right edge, got %f" % wrapped.x)

	# A position well inside is untouched.
	var inside := Vector2(500.0, 300.0)
	if WORLD_BOUNDS.wrap_to_bounds(inside, bounds, margin) != inside:
		failures.append("Wrap: interior position must not move")


func _test_clamp_keeps_position_inside(failures: Array[String]) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))
	var clamped := WORLD_BOUNDS.clamp_to_sector(Vector2(-500.0, 9999.0), bounds, 40.0)

	if not is_equal_approx(clamped.x, 40.0):
		failures.append("Clamp: expected x 40.0, got %f" % clamped.x)
	if not is_equal_approx(clamped.y, 5960.0):
		failures.append("Clamp: expected y 5960.0, got %f" % clamped.y)


func _test_is_outside_respects_radius(failures: Array[String]) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))

	if WORLD_BOUNDS.is_outside(Vector2(4000.0, 3000.0), bounds, 40.0):
		failures.append("is_outside: sector centre reported outside")
	if not WORLD_BOUNDS.is_outside(Vector2(10.0, 3000.0), bounds, 40.0):
		failures.append("is_outside: position within radius of the wall must count as outside")


func _test_reflect_only_when_moving_outward(failures: Array[String]) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))

	# At the left wall, moving left: reflect.
	var reflected := WORLD_BOUNDS.reflect_velocity_at_edge(
		Vector2(0.0, 3000.0), Vector2(-120.0, 40.0), bounds, 0.0
	)
	if reflected.x <= 0.0:
		failures.append("Reflect: outward x velocity must flip, got %f" % reflected.x)
	if not is_equal_approx(reflected.y, 40.0):
		failures.append("Reflect: tangential y velocity must be preserved, got %f" % reflected.y)

	# At the left wall, already moving right: leave alone. Without this guard an
	# entity resting on the wall flips every frame and jitters in place.
	reflected = WORLD_BOUNDS.reflect_velocity_at_edge(
		Vector2(0.0, 3000.0), Vector2(120.0, 0.0), bounds, 0.0
	)
	if not is_equal_approx(reflected.x, 120.0):
		failures.append("Reflect: inward velocity must not flip, got %f" % reflected.x)


func _test_edge_pressure_ramps_inward(failures: Array[String]) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))
	var margin := 600.0

	if WORLD_BOUNDS.edge_pressure(Vector2(4000.0, 3000.0), bounds, margin) != Vector2.ZERO:
		failures.append("Edge pressure: sector interior must be zero")

	var at_inner_edge := WORLD_BOUNDS.edge_pressure(Vector2(600.0, 3000.0), bounds, margin)
	if absf(at_inner_edge.x) > 0.001:
		failures.append("Edge pressure: must be zero at the inner edge of the band, got %f" % at_inner_edge.x)

	var at_wall := WORLD_BOUNDS.edge_pressure(Vector2(0.0, 3000.0), bounds, margin)
	if not is_equal_approx(at_wall.x, 1.0):
		failures.append("Edge pressure: must be 1.0 pointing inward at the wall, got %f" % at_wall.x)

	var half_way := WORLD_BOUNDS.edge_pressure(Vector2(300.0, 3000.0), bounds, margin)
	if absf(half_way.x - 0.5) > 0.01:
		failures.append("Edge pressure: must ramp linearly, expected 0.5, got %f" % half_way.x)

	var right_wall := WORLD_BOUNDS.edge_pressure(Vector2(8000.0, 3000.0), bounds, margin)
	if not is_equal_approx(right_wall.x, -1.0):
		failures.append("Edge pressure: right wall must push left, got %f" % right_wall.x)
```

- [ ] **Step 2: Run the test to verify it fails**

```sh
/home/japurane/.local/bin/godot --headless --path . --script tests/test_world_bounds.gd
```

Expected: failure loading `res://scripts/world/world_bounds.gd` because the file does not exist yet.

- [ ] **Step 3: Implement `WorldBounds`**

Create `scripts/world/world_bounds.gd`:

```gdscript
extends RefCounted
class_name WorldBounds

## Static bounds math for sector space. Preload as a const, following the
## scripts/material_runtime.gd idiom:
##   const WORLD_BOUNDS := preload("res://scripts/world/world_bounds.gd")


static func wrap_to_bounds(position: Vector2, bounds: Rect2, margin: float) -> Vector2:
	var minimum := bounds.position - Vector2.ONE * margin
	var maximum := bounds.end + Vector2.ONE * margin
	var wrapped := position

	if wrapped.x < minimum.x:
		wrapped.x = maximum.x
	elif wrapped.x > maximum.x:
		wrapped.x = minimum.x

	if wrapped.y < minimum.y:
		wrapped.y = maximum.y
	elif wrapped.y > maximum.y:
		wrapped.y = minimum.y

	return wrapped


static func clamp_to_sector(position: Vector2, bounds: Rect2, radius: float = 0.0) -> Vector2:
	return Vector2(
		clampf(position.x, bounds.position.x + radius, bounds.end.x - radius),
		clampf(position.y, bounds.position.y + radius, bounds.end.y - radius)
	)


static func is_outside(position: Vector2, bounds: Rect2, radius: float = 0.0) -> bool:
	return (
		position.x < bounds.position.x + radius
		or position.x > bounds.end.x - radius
		or position.y < bounds.position.y + radius
		or position.y > bounds.end.y - radius
	)


static func reflect_velocity_at_edge(
	position: Vector2,
	velocity: Vector2,
	bounds: Rect2,
	radius: float = 0.0
) -> Vector2:
	var reflected := velocity

	# Only flip when the entity is actually moving further out. Flipping
	# unconditionally makes an entity resting on the wall jitter every frame.
	if position.x <= bounds.position.x + radius and reflected.x < 0.0:
		reflected.x = -reflected.x
	elif position.x >= bounds.end.x - radius and reflected.x > 0.0:
		reflected.x = -reflected.x

	if position.y <= bounds.position.y + radius and reflected.y < 0.0:
		reflected.y = -reflected.y
	elif position.y >= bounds.end.y - radius and reflected.y > 0.0:
		reflected.y = -reflected.y

	return reflected


static func edge_pressure(position: Vector2, bounds: Rect2, margin: float) -> Vector2:
	## Inward push in the range 0.0 at the inner edge of the margin band to 1.0
	## at the wall. Exactly zero outside the band.
	if margin <= 0.0:
		return Vector2.ZERO

	var pressure := Vector2.ZERO

	var left_depth := (bounds.position.x + margin) - position.x
	if left_depth > 0.0:
		pressure.x += clampf(left_depth / margin, 0.0, 1.0)

	var right_depth := position.x - (bounds.end.x - margin)
	if right_depth > 0.0:
		pressure.x -= clampf(right_depth / margin, 0.0, 1.0)

	var top_depth := (bounds.position.y + margin) - position.y
	if top_depth > 0.0:
		pressure.y += clampf(top_depth / margin, 0.0, 1.0)

	var bottom_depth := position.y - (bounds.end.y - margin)
	if bottom_depth > 0.0:
		pressure.y -= clampf(bottom_depth / margin, 0.0, 1.0)

	return pressure
```

- [ ] **Step 4: Run the test to verify it passes**

```sh
/home/japurane/.local/bin/godot --headless --path . --script tests/test_world_bounds.gd
```

Expected: `ALL WORLD BOUNDS TESTS PASSED SUCCESSFULLY!` and exit code 0.

- [ ] **Step 5: Add the `SectorDefinition` resource**

Create `scripts/resources/sector_definition.gd`:

```gdscript
extends Resource
class_name SectorDefinition


@export var sector_name: StringName = &"vega_7"
@export var world_size: Vector2 = Vector2(1152.0, 648.0)
@export var sector_seed: int = 1729
@export var boundary_margin: float = 600.0
@export var asteroid_field_count: int = 5
@export var planet_count: int = 2
@export var moon_count: int = 3
@export var station_count: int = 1
@export var min_landmark_separation: float = 900.0
@export var threat_curve: Curve


func get_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, world_size)
```

`world_size` starts at the current viewport size on purpose. Task 2 grows it, so
this task changes nothing a player can see.

- [ ] **Step 6: Add the `Sector` node**

Create `scripts/world/sector.gd`:

```gdscript
extends Node2D


@export var definition: Resource


func get_bounds() -> Rect2:
	if definition != null and definition.has_method("get_bounds"):
		return definition.get_bounds()

	return get_viewport_rect()


func get_center() -> Vector2:
	return get_bounds().get_center()


func get_boundary_margin() -> float:
	if definition != null and "boundary_margin" in definition:
		return definition.boundary_margin

	return 0.0


func get_random_position(rng: RandomNumberGenerator, inset: float = 0.0) -> Vector2:
	var bounds := get_bounds()
	return Vector2(
		rng.randf_range(bounds.position.x + inset, bounds.end.x - inset),
		rng.randf_range(bounds.position.y + inset, bounds.end.y - inset)
	)
```

- [ ] **Step 7: Create the default sector resource**

Create `assets/sectors/sector_default.tres`:

```
[gd_resource type="Resource" script_class="SectorDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/sector_definition.gd" id="1_sector"]

[resource]
script = ExtResource("1_sector")
sector_name = &"vega_7"
world_size = Vector2(1152, 648)
sector_seed = 1729
boundary_margin = 600.0
asteroid_field_count = 5
planet_count = 2
moon_count = 3
station_count = 1
min_landmark_separation = 900.0
```

- [ ] **Step 8: Wire the `Sector` node into `Game.tscn`**

Add a `Sector` node as the first child of `Game`, before `Entities`, with its
script set to `res://scripts/world/sector.gd` and `definition` set to
`res://assets/sectors/sector_default.tres`. Leave `PlayArea` in place for now;
Task 2 removes it.

- [ ] **Step 9: Replace the three wrap implementations**

In `scripts/player_ship.gd`, `scripts/asteroid.gd`, and `scripts/bullet.gd`,
add near the top of each file:

```gdscript
const WORLD_BOUNDS := preload("res://scripts/world/world_bounds.gd")
```

Add to each of the three scripts:

```gdscript
var sector_bounds: Rect2 = Rect2()


func set_sector_bounds(bounds: Rect2) -> void:
	sector_bounds = bounds


func _get_sector_bounds() -> Rect2:
	if sector_bounds.size.x > 0.0 and sector_bounds.size.y > 0.0:
		return sector_bounds

	return get_viewport_rect()
```

Then replace each `_wrap_to_visible_viewport()` body with:

```gdscript
func _wrap_to_visible_viewport() -> void:
	position = WORLD_BOUNDS.wrap_to_bounds(position, _get_sector_bounds(), wrap_margin)
```

Keep the function name for this task. `scripts/asteroid.gd` calls
`other._wrap_to_visible_viewport()` from `_resolve_asteroid_collision`, and
`tests/test_asteroid_collisions.gd` exercises that path, so renaming now would
break the regression gate for no gain. Task 3 renames it.

- [ ] **Step 10: Point `game.gd` at the sector**

In `scripts/game.gd`, add `@onready var sector: Node2D = $Sector` alongside the
other `@onready` declarations, then replace the body of
`_get_safe_spawn_position` so it samples the sector rather than the viewport:

```gdscript
func _get_safe_spawn_position(index: int, asteroid_count: int) -> Vector2:
	for attempt in 32:
		var spawn_position := sector.get_random_position(random)

		if spawn_position.distance_to(player_ship.global_position) >= spawn_safe_radius:
			return spawn_position

	var fallback_angle := TAU * float(index) / maxf(1.0, float(asteroid_count))
	var fallback_radius := spawn_safe_radius + 80.0
	return player_ship.global_position + Vector2.RIGHT.rotated(fallback_angle) * fallback_radius
```

Replace `get_viewport_rect().get_center()` in `_respawn_player` with
`sector.get_center()`.

Add a helper that pushes bounds to every entity, and call it from
`_apply_lighting_to_entity` so newly spawned entities are covered by the same
hook that already exists:

```gdscript
func _apply_sector_bounds_to_entity(entity: Node) -> void:
	if entity != null and entity.has_method("set_sector_bounds"):
		entity.set_sector_bounds(sector.get_bounds())
```

Call `_apply_sector_bounds_to_entity(entity)` from inside
`_apply_lighting_to_entity`. That function is already invoked for the player
ship, every spawned asteroid, and every spawned bullet, so this single call site
covers all three without touching each spawn path.

- [ ] **Step 11: Run the full test suite**

```sh
/home/japurane/.local/bin/godot --headless --path . --script tests/test_world_bounds.gd
/home/japurane/.local/bin/godot --headless --path . --script tests/test_asteroid_collisions.gd
/home/japurane/.local/bin/godot --headless --path . --quit
```

Expected: both test scripts print their success banner and exit 0, and the
project boots headless with no script errors.

- [ ] **Step 12: Verify on desktop**

```sh
/home/japurane/.local/bin/godot --path .
```

Expected: the game looks and plays exactly as before this task. Asteroids and
bullets still wrap at the screen edges, the ship still wraps, waves still clear.
If anything differs, the refactor is wrong.

- [ ] **Step 13: Commit**

```sh
git add scripts/resources/sector_definition.gd scripts/resources/sector_definition.gd.uid \
        scripts/world/world_bounds.gd scripts/world/world_bounds.gd.uid \
        scripts/world/sector.gd scripts/world/sector.gd.uid \
        assets/sectors/sector_default.tres \
        scripts/player_ship.gd scripts/asteroid.gd scripts/bullet.gd \
        scripts/game.gd scenes/game/Game.tscn tests/test_world_bounds.gd
git commit -m "Add sector definition and world-bounds authority"
```

---

### Task 2 (#45): Follow camera with sector limits and look-ahead

This is the task where scrolling becomes visible. The sector grows to 8000x6000
and a camera follows the ship.

**Files:**
- Create: `scripts/world/follow_camera.gd`
- Modify: `assets/sectors/sector_default.tres` (world_size)
- Modify: `scenes/game/Game.tscn` (add `FollowCamera`; delete `PlayArea`)
- Modify: `scripts/game.gd` (wire camera to the player ship and sector)
- Test: `tests/test_follow_camera.gd`

**Interfaces:**
- Consumes: `Sector.get_bounds()` and `SectorDefinition.world_size` from Task 1.
- Produces: `FollowCamera` node with `func set_target(node: Node2D) -> void`, `func apply_sector_limits(bounds: Rect2) -> void`, and exported `look_ahead_seconds: float`, `max_look_ahead: float`, `smoothing_speed: float`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_follow_camera.gd`:

```gdscript
extends SceneTree


const CAMERA_SCRIPT := preload("res://scripts/world/follow_camera.gd")


func _init() -> void:
	var failures: Array[String] = []

	await _test_limits_come_from_sector_bounds(failures)
	await _test_camera_tracks_target(failures)
	await _test_look_ahead_leads_the_velocity(failures)
	await _test_look_ahead_is_capped(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL FOLLOW CAMERA TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


func _make_camera() -> Camera2D:
	var camera := Camera2D.new()
	camera.set_script(CAMERA_SCRIPT)
	return camera


func _test_limits_come_from_sector_bounds(failures: Array[String]) -> void:
	var camera := _make_camera()
	root.add_child(camera)
	await physics_frame

	camera.apply_sector_limits(Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0)))

	if camera.limit_left != 0:
		failures.append("Camera limits: expected limit_left 0, got %d" % camera.limit_left)
	if camera.limit_right != 8000:
		failures.append("Camera limits: expected limit_right 8000, got %d" % camera.limit_right)
	if camera.limit_bottom != 6000:
		failures.append("Camera limits: expected limit_bottom 6000, got %d" % camera.limit_bottom)

	camera.queue_free()
	await physics_frame


func _test_camera_tracks_target(failures: Array[String]) -> void:
	var camera := _make_camera()
	var target := Node2D.new()
	root.add_child(camera)
	root.add_child(target)
	await physics_frame

	camera.set_target(target)
	target.global_position = Vector2(4000.0, 3000.0)

	for _step in 10:
		await physics_frame

	var distance := camera.global_position.distance_to(target.global_position)
	if distance > 400.0:
		failures.append("Camera tracking: camera did not converge on target, distance %f" % distance)

	camera.queue_free()
	target.queue_free()
	await physics_frame


func _test_look_ahead_leads_the_velocity(failures: Array[String]) -> void:
	var camera := _make_camera()
	root.add_child(camera)
	await physics_frame

	var lead := camera.compute_look_ahead(Vector2(500.0, 0.0))
	if lead.x <= 0.0:
		failures.append("Look-ahead: rightward velocity must lead right, got %f" % lead.x)
	if absf(lead.y) > 0.001:
		failures.append("Look-ahead: zero y velocity must not lead vertically, got %f" % lead.y)

	var still := camera.compute_look_ahead(Vector2.ZERO)
	if still != Vector2.ZERO:
		failures.append("Look-ahead: a stationary ship must have no lead")

	camera.queue_free()
	await physics_frame


func _test_look_ahead_is_capped(failures: Array[String]) -> void:
	var camera := _make_camera()
	root.add_child(camera)
	await physics_frame

	# A very fast ship must not push the camera arbitrarily far ahead, or the
	# ship leaves the screen entirely.
	var lead := camera.compute_look_ahead(Vector2(100000.0, 0.0))
	if lead.length() > camera.max_look_ahead + 0.001:
		failures.append("Look-ahead: must be capped at max_look_ahead, got %f" % lead.length())

	camera.queue_free()
	await physics_frame
```

- [ ] **Step 2: Run the test to verify it fails**

```sh
/home/japurane/.local/bin/godot --headless --path . --script tests/test_follow_camera.gd
```

Expected: failure loading `res://scripts/world/follow_camera.gd`.

- [ ] **Step 3: Implement the camera**

Create `scripts/world/follow_camera.gd`:

```gdscript
extends Camera2D


@export var look_ahead_seconds: float = 0.45
@export var max_look_ahead: float = 260.0
@export var smoothing_speed: float = 5.0
@export var look_ahead_smoothing: float = 3.0

var target: Node2D
var current_look_ahead: Vector2 = Vector2.ZERO


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = smoothing_speed
	# Drag margins keep small corrections from shaking the whole view.
	drag_horizontal_enabled = true
	drag_vertical_enabled = true
	drag_left_margin = 0.15
	drag_right_margin = 0.15
	drag_top_margin = 0.15
	drag_bottom_margin = 0.15
	make_current()


func set_target(node: Node2D) -> void:
	target = node

	if target != null:
		global_position = target.global_position
		reset_smoothing()


func apply_sector_limits(bounds: Rect2) -> void:
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)


func compute_look_ahead(velocity: Vector2) -> Vector2:
	return (velocity * look_ahead_seconds).limit_length(max_look_ahead)


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	var target_velocity: Vector2 = Vector2.ZERO
	if "velocity" in target:
		target_velocity = target.velocity

	var desired_look_ahead := compute_look_ahead(target_velocity)
	current_look_ahead = current_look_ahead.lerp(
		desired_look_ahead,
		clampf(look_ahead_smoothing * delta, 0.0, 1.0)
	)

	global_position = target.global_position + current_look_ahead
```

Note: `position_smoothing_enabled` means the camera's rendered position lags its
node position, which is what produces the follow feel. The look-ahead is
smoothed separately so that tapping thrust does not snap the view.

- [ ] **Step 4: Run the test to verify it passes**

```sh
/home/japurane/.local/bin/godot --headless --path . --script tests/test_follow_camera.gd
```

Expected: `ALL FOLLOW CAMERA TESTS PASSED SUCCESSFULLY!` and exit code 0.

- [ ] **Step 5: Grow the sector**

Edit `assets/sectors/sector_default.tres` and change:

```
world_size = Vector2(8000, 6000)
```

- [ ] **Step 6: Add the camera to `Game.tscn` and delete `PlayArea`**

Add a `FollowCamera` node of type `Camera2D` as a child of `Game`, with script
`res://scripts/world/follow_camera.gd`.

Delete the `PlayArea` node and its `PlayAreaBounds` child. Nothing reads them,
and `SectorDefinition` is now the single source of world extent. Leaving a stale
1152x648 box in the scene invites a future task to wire it up by mistake.

- [ ] **Step 7: Wire the camera in `game.gd`**

Add to the `@onready` block:

```gdscript
@onready var follow_camera: Camera2D = $FollowCamera
```

At the end of `_ready()`, before the `auto_start` check:

```gdscript
	follow_camera.apply_sector_limits(sector.get_bounds())
	follow_camera.set_target(player_ship)
```

In `_respawn_player`, after repositioning the ship, re-centre the camera so a
respawn does not produce a long slide across the sector:

```gdscript
	follow_camera.set_target(player_ship)
```

- [ ] **Step 8: Run the full test suite**

```sh
/home/japurane/.local/bin/godot --headless --path . --script tests/test_world_bounds.gd
/home/japurane/.local/bin/godot --headless --path . --script tests/test_follow_camera.gd
/home/japurane/.local/bin/godot --headless --path . --script tests/test_asteroid_collisions.gd
```

Expected: all three print their success banner and exit 0.

- [ ] **Step 9: Verify on desktop**

```sh
/home/japurane/.local/bin/godot --path .
```

Expected: the view now scrolls with the ship. The HUD stays fixed on screen
because it is a `CanvasLayer`. Two things will look broken, and both are
expected and fixed by Tasks 3 and 4: the background is a small rectangle in the
top-left corner with void around it, and asteroids wrap against sector edges
thousands of pixels away so the sector feels almost empty. Do not fix them here.

- [ ] **Step 10: Commit**

```sh
git add scripts/world/follow_camera.gd scripts/world/follow_camera.gd.uid \
        tests/test_follow_camera.gd \
        assets/sectors/sector_default.tres scenes/game/Game.tscn scripts/game.gd
git commit -m "Add follow camera with sector limits and look-ahead"
```

---

### Task 3 (#46): Soft sector boundary and containment

Replace wrapping with containment. The ship is pushed back, asteroids and AI
ships reflect, bullets despawn.

**Files:**
- Modify: `scripts/player_ship.gd` (edge pressure, clamp, warning signal)
- Modify: `scripts/asteroid.gd` (reflection; rename `_wrap_to_visible_viewport`)
- Modify: `scripts/bullet.gd` (despawn at bounds)
- Modify: `scripts/hud.gd` (boundary warning label)
- Modify: `scenes/ui/Hud.tscn` (warning label node)
- Modify: `scripts/game.gd` (connect the warning signal)
- Test: `tests/test_sector_containment.gd`

**Interfaces:**
- Consumes: `WorldBounds.edge_pressure`, `WorldBounds.clamp_to_sector`, `WorldBounds.reflect_velocity_at_edge`, `WorldBounds.is_outside` from Task 1; `set_sector_bounds` on all three entities.
- Produces:
  - `player_ship.gd` signal `boundary_warning_changed(active: bool)` and exported `boundary_push_multiplier: float`.
  - `asteroid.gd` renames `_wrap_to_visible_viewport()` to `_contain_in_sector()`; the call in `_resolve_asteroid_collision` is renamed with it.
  - `hud.gd` gains `func set_boundary_warning(active: bool) -> void`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_sector_containment.gd`:

```gdscript
extends SceneTree


const ASTEROID_SCENE := "res://scenes/entities/Asteroid.tscn"
const BULLET_SCENE := "res://scenes/entities/Bullet.tscn"
const PLAYER_SCENE := "res://scenes/entities/PlayerShip.tscn"

const SECTOR_BOUNDS := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))


func _init() -> void:
	var failures: Array[String] = []

	await _test_asteroid_reflects_instead_of_wrapping(failures)
	await _test_asteroid_never_leaves_sector_over_time(failures)
	await _test_bullet_despawns_at_boundary(failures)
	await _test_ship_is_pushed_back_from_the_wall(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL SECTOR CONTAINMENT TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


func _test_asteroid_reflects_instead_of_wrapping(failures: Array[String]) -> void:
	var asteroid := (load(ASTEROID_SCENE) as PackedScene).instantiate() as Area2D
	root.add_child(asteroid)
	asteroid.add_to_group("asteroids")
	asteroid.set_sector_bounds(SECTOR_BOUNDS)
	asteroid.setup(0, Vector2(-400.0, 0.0), null, 0.0)
	asteroid.global_position = Vector2(60.0, 3000.0)

	for _step in 20:
		await physics_frame

	# Old behavior teleported it to the far right edge. New behavior bounces it.
	if asteroid.global_position.x > 4000.0:
		failures.append("Containment: asteroid wrapped to the far side instead of reflecting (x=%f)" % asteroid.global_position.x)
	if asteroid.velocity.x <= 0.0:
		failures.append("Containment: asteroid velocity should have reflected inward, got %f" % asteroid.velocity.x)

	asteroid.queue_free()
	await physics_frame


func _test_asteroid_never_leaves_sector_over_time(failures: Array[String]) -> void:
	var asteroid := (load(ASTEROID_SCENE) as PackedScene).instantiate() as Area2D
	root.add_child(asteroid)
	asteroid.add_to_group("asteroids")
	asteroid.set_sector_bounds(SECTOR_BOUNDS)
	asteroid.setup(2, Vector2(600.0, 430.0), null, 0.0)
	asteroid.global_position = Vector2(4000.0, 3000.0)

	for _step in 300:
		await physics_frame

		if not SECTOR_BOUNDS.has_point(asteroid.global_position):
			failures.append("Containment: asteroid escaped the sector at %s" % str(asteroid.global_position))
			break

	asteroid.queue_free()
	await physics_frame


func _test_bullet_despawns_at_boundary(failures: Array[String]) -> void:
	var bullet := (load(BULLET_SCENE) as PackedScene).instantiate() as Area2D
	root.add_child(bullet)
	bullet.set_sector_bounds(SECTOR_BOUNDS)
	bullet.global_position = Vector2(120.0, 3000.0)
	bullet.launch(Vector2.LEFT, Vector2.ZERO)

	for _step in 30:
		await physics_frame

		if not is_instance_valid(bullet) or bullet.is_queued_for_deletion():
			break

	if is_instance_valid(bullet) and not bullet.is_queued_for_deletion():
		failures.append("Containment: bullet did not despawn at the sector boundary")
		bullet.queue_free()

	await physics_frame


func _test_ship_is_pushed_back_from_the_wall(failures: Array[String]) -> void:
	var ship := (load(PLAYER_SCENE) as PackedScene).instantiate() as Area2D
	root.add_child(ship)
	ship.set_sector_bounds(SECTOR_BOUNDS)
	ship.set_boundary_margin(600.0)
	await physics_frame

	# Drifting outward inside the margin band, with no player input.
	ship.global_position = Vector2(80.0, 3000.0)
	ship.velocity = Vector2(-200.0, 0.0)

	var warned := false
	ship.boundary_warning_changed.connect(func(active: bool) -> void:
		if active:
			warned = true
	)

	for _step in 90:
		await physics_frame

		if not SECTOR_BOUNDS.has_point(ship.global_position):
			failures.append("Containment: ship left the sector at %s" % str(ship.global_position))
			break

	if ship.velocity.x <= 0.0:
		failures.append("Containment: edge pressure did not reverse the ship's outward drift (vx=%f)" % ship.velocity.x)
	if not warned:
		failures.append("Containment: boundary_warning_changed was never emitted inside the margin band")

	ship.queue_free()
	await physics_frame
```

- [ ] **Step 2: Run the test to verify it fails**

```sh
/home/japurane/.local/bin/godot --headless --path . --script tests/test_sector_containment.gd
```

Expected: multiple failures — the asteroid wraps, the bullet survives, and the
ship has no `set_boundary_margin` method.

- [ ] **Step 3: Contain the asteroid**

In `scripts/asteroid.gd`, replace `_wrap_to_visible_viewport()` with:

```gdscript
func _contain_in_sector() -> void:
	var bounds := _get_sector_bounds()
	var radius := get_collision_radius()
	velocity = WORLD_BOUNDS.reflect_velocity_at_edge(position, velocity, bounds, radius)
	position = WORLD_BOUNDS.clamp_to_sector(position, bounds, radius)
```

Update the call in `_physics_process` and the two calls in
`_resolve_asteroid_collision` (`_wrap_to_visible_viewport()` and
`other._wrap_to_visible_viewport()`) to use `_contain_in_sector`. Update the
`has_method` guard to `other.has_method("_contain_in_sector")`.

- [ ] **Step 4: Despawn the bullet**

In `scripts/bullet.gd`, replace `_wrap_to_visible_viewport()` with:

```gdscript
func _despawn_outside_sector() -> void:
	if WORLD_BOUNDS.is_outside(position, _get_sector_bounds(), 0.0):
		queue_free()
```

Update the call in `_physics_process`, which becomes:

```gdscript
	position += velocity * delta
	_despawn_outside_sector()
```

- [ ] **Step 5: Contain the ship**

In `scripts/player_ship.gd`, add the signal and exports near the existing ones:

```gdscript
signal boundary_warning_changed(active: bool)

@export var boundary_push_multiplier: float = 1.5

var boundary_margin: float = 600.0
var boundary_warning_active: bool = false


func set_boundary_margin(value: float) -> void:
	boundary_margin = value
```

Replace `_wrap_to_visible_viewport()` with:

```gdscript
func _contain_in_sector(delta: float) -> void:
	var bounds := _get_sector_bounds()
	var pressure := WORLD_BOUNDS.edge_pressure(position, bounds, boundary_margin)

	if pressure != Vector2.ZERO:
		velocity += pressure * acceleration * boundary_push_multiplier * delta

	position = WORLD_BOUNDS.clamp_to_sector(position, bounds, 0.0)

	var warning := pressure != Vector2.ZERO
	if warning != boundary_warning_active:
		boundary_warning_active = warning
		boundary_warning_changed.emit(warning)
```

In `_physics_process`, replace the `_wrap_to_visible_viewport()` call with
`_contain_in_sector(delta)`.

Move that call so it runs even when controls are disabled. `_physics_process`
currently returns early on `not controls_enabled`, which would let a drifting
respawning ship leave the sector:

```gdscript
func _physics_process(delta: float) -> void:
	if not controls_enabled:
		_apply_drift(delta)
		_move(delta)
		_contain_in_sector(delta)
		return

	_update_fire_cooldown(delta)
	_apply_rotation_input(delta)
	_apply_thrust_input(delta)
	_apply_shoot_input()
	_apply_drift(delta)
	_move(delta)
	_contain_in_sector(delta)
	_update_shader_light_direction()
```

- [ ] **Step 6: Delete the now-unused `wrap_margin` exports**

Nothing reads `wrap_margin` any more. Remove the `@export var wrap_margin` line
from `scripts/player_ship.gd`, `scripts/asteroid.gd`, and `scripts/bullet.gd`.
Leaving a dead export visible in the inspector invites someone to tune it and
wonder why nothing happens.

- [ ] **Step 7: Add the HUD warning**

In `scenes/ui/Hud.tscn`, add a `Label` node named `BoundaryWarning`, centred
horizontally near the top of the screen, text `LEAVING SECTOR`, in a warning
colour, `visible = false`.

In `scripts/hud.gd`, add:

```gdscript
@onready var boundary_warning: Label = $BoundaryWarning


func set_boundary_warning(active: bool) -> void:
	boundary_warning.visible = active
```

- [ ] **Step 8: Wire it up in `game.gd`**

In `_ready()`, alongside the other `player_ship` signal connections:

```gdscript
	player_ship.boundary_warning_changed.connect(hud.set_boundary_warning)
```

Extend `_apply_sector_bounds_to_entity` so the ship also learns the margin:

```gdscript
func _apply_sector_bounds_to_entity(entity: Node) -> void:
	if entity == null:
		return

	if entity.has_method("set_sector_bounds"):
		entity.set_sector_bounds(sector.get_bounds())

	if entity.has_method("set_boundary_margin"):
		entity.set_boundary_margin(sector.get_boundary_margin())
```

- [ ] **Step 9: Run the full test suite**

```sh
/home/japurane/.local/bin/godot --headless --path . --script tests/test_sector_containment.gd
/home/japurane/.local/bin/godot --headless --path . --script tests/test_world_bounds.gd
/home/japurane/.local/bin/godot --headless --path . --script tests/test_follow_camera.gd
/home/japurane/.local/bin/godot --headless --path . --script tests/test_asteroid_collisions.gd
```

Expected: all four print their success banner and exit 0. `test_asteroid_collisions.gd`
matters most here: it places asteroids around (400-550, 300), well inside an
8000x6000 sector, so containment must not perturb it.

- [ ] **Step 10: Verify on desktop**

```sh
/home/japurane/.local/bin/godot --path .
```

Expected: flying toward a sector edge shows `LEAVING SECTOR` and the ship is
pushed back before reaching the wall. Nothing wraps any more.

- [ ] **Step 11: Commit**

```sh
git add scripts/player_ship.gd scripts/asteroid.gd scripts/bullet.gd \
        scripts/hud.gd scenes/ui/Hud.tscn scripts/game.gd \
        tests/test_sector_containment.gd
git commit -m "Replace screen wrapping with soft sector boundary containment"
```

---

### Task 4 (#47): Parallax star layers and deep-space background

Removes the fixed-size background left broken by Task 2 and gives the sector
visible depth so scrolling reads as motion.

**Files:**
- Create: `scripts/world/star_layer.gd`
- Modify: `scenes/game/Game.tscn` (delete `Background`, `BackgroundTexture`, `Starfield`; add parallax layers)
- Delete: `scripts/starfield.gd`, `scripts/starfield.gd.uid`
- Test: `tests/test_star_layer.gd`

**Interfaces:**
- Consumes: `Sector.get_bounds()` and `SectorDefinition.sector_seed` from Task 1.
- Produces: `StarLayer` node with exports `star_count: int`, `layer_seed: int`, `min_radius: float`, `max_radius: float`, `star_color: Color`, and `func build_stars(bounds: Rect2, seed_value: int) -> void`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_star_layer.gd`:

```gdscript
extends SceneTree


const STAR_LAYER := preload("res://scripts/world/star_layer.gd")
const BOUNDS := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))


func _init() -> void:
	var failures: Array[String] = []

	await _test_stars_fill_sector_not_viewport(failures)
	await _test_same_seed_produces_same_layout(failures)
	await _test_different_seed_produces_different_layout(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL STAR LAYER TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


func _make_layer(count: int) -> Node2D:
	var layer := Node2D.new()
	layer.set_script(STAR_LAYER)
	layer.star_count = count
	return layer


func _positions(layer: Node2D) -> PackedVector2Array:
	var result := PackedVector2Array()
	for child in layer.get_children():
		result.append((child as Node2D).position)
	return result


func _test_stars_fill_sector_not_viewport(failures: Array[String]) -> void:
	var layer := _make_layer(300)
	root.add_child(layer)
	await physics_frame

	layer.build_stars(BOUNDS, 1729)

	if layer.get_child_count() != 300:
		failures.append("Star layer: expected 300 stars, got %d" % layer.get_child_count())

	var max_x := 0.0
	for position in _positions(layer):
		if not BOUNDS.has_point(position):
			failures.append("Star layer: star placed outside sector at %s" % str(position))
			break
		max_x = maxf(max_x, position.x)

	# With 300 stars across 8000px, the furthest should be far beyond the old
	# 1152px viewport width. This is what proves stars moved to sector space.
	if max_x < 4000.0:
		failures.append("Star layer: stars are clustered near the origin, max x %f" % max_x)

	layer.queue_free()
	await physics_frame


func _test_same_seed_produces_same_layout(failures: Array[String]) -> void:
	var first := _make_layer(50)
	var second := _make_layer(50)
	root.add_child(first)
	root.add_child(second)
	await physics_frame

	first.build_stars(BOUNDS, 4242)
	second.build_stars(BOUNDS, 4242)

	if _positions(first) != _positions(second):
		failures.append("Star layer: the same seed must produce an identical layout")

	first.queue_free()
	second.queue_free()
	await physics_frame


func _test_different_seed_produces_different_layout(failures: Array[String]) -> void:
	var first := _make_layer(50)
	var second := _make_layer(50)
	root.add_child(first)
	root.add_child(second)
	await physics_frame

	first.build_stars(BOUNDS, 1)
	second.build_stars(BOUNDS, 2)

	if _positions(first) == _positions(second):
		failures.append("Star layer: different seeds must produce different layouts")

	first.queue_free()
	second.queue_free()
	await physics_frame
```

- [ ] **Step 2: Run the test to verify it fails**

```sh
/home/japurane/.local/bin/godot --headless --path . --script tests/test_star_layer.gd
```

Expected: failure loading `res://scripts/world/star_layer.gd`.

- [ ] **Step 3: Implement `StarLayer`**

Create `scripts/world/star_layer.gd`:

```gdscript
extends Node2D


@export var star_count: int = 90
@export var layer_seed: int = 404
@export var min_radius: float = 1.0
@export var max_radius: float = 2.4
@export var star_color: Color = Color(0.65, 0.82, 1.0)
@export var min_alpha: float = 0.28
@export var max_alpha: float = 0.7

var random := RandomNumberGenerator.new()


func build_stars(bounds: Rect2, seed_value: int) -> void:
	for child in get_children():
		child.queue_free()

	random.seed = seed_value

	for index in star_count:
		var star := Polygon2D.new()
		var radius := random.randf_range(min_radius, max_radius)
		star.polygon = PackedVector2Array([
			Vector2(0.0, -radius),
			Vector2(radius, 0.0),
			Vector2(0.0, radius),
			Vector2(-radius, 0.0)
		])
		star.position = Vector2(
			random.randf_range(bounds.position.x, bounds.end.x),
			random.randf_range(bounds.position.y, bounds.end.y)
		)
		star.color = Color(
			star_color.r,
			star_color.g,
			star_color.b,
			random.randf_range(min_alpha, max_alpha)
		)
		add_child(star)
```

The old `starfield.gd` built stars in `_ready()` from the viewport rect. Building
them on demand from an explicit `bounds` argument is what makes the layout
testable and seed-reproducible.

- [ ] **Step 4: Run the test to verify it passes**

```sh
/home/japurane/.local/bin/godot --headless --path . --script tests/test_star_layer.gd
```

Expected: `ALL STAR LAYER TESTS PASSED SUCCESSFULLY!` and exit code 0.

- [ ] **Step 5: Rebuild the background in `Game.tscn`**

Delete the `Background` `ColorRect`, the `BackgroundTexture` `TextureRect`, and
the `Starfield` node. All three are viewport-sized and scroll away from the ship.

Add, as the first children of `Game` so they render behind everything:

1. `DeepSpace` — a `CanvasLayer` with `layer = -100` and `follow_viewport_enabled = false`,
   containing a `ColorRect` with `anchors_preset = 15` (full rect) and colour
   `Color(0.0352941, 0.0392157, 0.0588235, 1)`. A non-following `CanvasLayer`
   pins the void colour to the screen at zero cost regardless of camera position.
2. `StarsFar` — a `Parallax2D` node with `scroll_scale = Vector2(0.15, 0.15)`,
   containing a `Node2D` named `Layer` with script `res://scripts/world/star_layer.gd`,
   `star_count = 420`, `layer_seed = 404`, `max_radius = 1.6`, `min_alpha = 0.15`, `max_alpha = 0.4`.
3. `StarsMid` — a `Parallax2D` node with `scroll_scale = Vector2(0.4, 0.4)`,
   containing a `Node2D` named `Layer` with the same script,
   `star_count = 260`, `layer_seed = 405`, `min_alpha = 0.3`, `max_alpha = 0.7`.

`Parallax2D` is the Godot 4 node for this; do not use the deprecated
`ParallaxBackground`/`ParallaxLayer` pair.

- [ ] **Step 6: Build the layers from the sector seed**

In `scripts/game.gd`, add to the `@onready` block:

```gdscript
@onready var stars_far: Node2D = $StarsFar/Layer
@onready var stars_mid: Node2D = $StarsMid/Layer
```

And in `_ready()`, after the camera wiring:

```gdscript
	_build_star_layers()
```

With:

```gdscript
func _build_star_layers() -> void:
	var bounds := sector.get_bounds()
	var sector_seed := random_seed

	if sector.definition != null and "sector_seed" in sector.definition:
		sector_seed = sector.definition.sector_seed

	stars_far.build_stars(bounds, sector_seed + stars_far.layer_seed)
	stars_mid.build_stars(bounds, sector_seed + stars_mid.layer_seed)
```

Offsetting each layer's build seed by its own `layer_seed` keeps the two layers
from producing identical star patterns on top of each other.

- [ ] **Step 7: Delete the old starfield**

```sh
git rm scripts/starfield.gd scripts/starfield.gd.uid
```

- [ ] **Step 8: Run the full test suite**

```sh
/home/japurane/.local/bin/godot --headless --path . --script tests/test_star_layer.gd
/home/japurane/.local/bin/godot --headless --path . --script tests/test_sector_containment.gd
/home/japurane/.local/bin/godot --headless --path . --script tests/test_world_bounds.gd
/home/japurane/.local/bin/godot --headless --path . --script tests/test_follow_camera.gd
/home/japurane/.local/bin/godot --headless --path . --script tests/test_asteroid_collisions.gd
/home/japurane/.local/bin/godot --headless --path . --quit
```

Expected: five success banners, all exit 0, and a clean headless boot with no
errors about the removed `Starfield` node.

- [ ] **Step 9: Verify on desktop and on device**

```sh
/home/japurane/.local/bin/godot --path .
```

Expected: no void or misplaced rectangle anywhere. Flying produces visible
parallax, with far stars drifting slower than near stars.

Then verify the foundation on Android, since this is the last task in the plan:

```sh
mkdir -p builds/android
/home/japurane/.local/bin/godot --headless --path . --export-debug Android builds/android/asteroids-debug.apk
/home/japurane/Android/Sdk/platform-tools/adb install -r builds/android/asteroids-debug.apk
/home/japurane/Android/Sdk/platform-tools/adb shell monkey -p com.japurane.asteroids -c android.intent.category.LAUNCHER 1
```

Expected: the game launches in landscape, touch controls still work, the view
scrolls, and the star layers render without visible seams or stutter.

- [ ] **Step 10: Commit**

```sh
# The starfield deletion was already staged by the git rm in Step 7.
git add scripts/world/star_layer.gd scripts/world/star_layer.gd.uid \
        tests/test_star_layer.gd scenes/game/Game.tscn scripts/game.gd
git commit -m "Replace fixed starfield with seeded parallax star layers"
```

---

## Completion criteria for this plan

- The camera scrolls with the ship across an 8000x6000 sector.
- No entity of any type can leave the sector, verified by a 300-frame test.
- The ship is pushed back from sector edges with a visible HUD warning.
- Star layers are seed-reproducible and fill sector space, with parallax depth.
- `tests/test_asteroid_collisions.gd` still passes unchanged in substance.
- The Android debug APK builds, installs, and runs.
- `scripts/starfield.gd`, `Background`, `BackgroundTexture`, and `PlayArea` are gone.

Once these hold, write `2026-08-19-scrolling-sector-content.md` for issues #48-#52.
