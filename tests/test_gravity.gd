extends SceneTree


const GRAVITY_FIELD := preload("res://scripts/world/gravity_field.gd")
const PLAYER_SCENE := "res://scenes/entities/PlayerShip.tscn"
const BULLET_SCENE := "res://scenes/entities/Bullet.tscn"
const SECTOR_SCRIPT := "res://scripts/world/sector.gd"
const SHIPPED_SECTOR := "res://assets/sectors/sector_default.tres"


class GravitySource:
	extends Node2D

	var body_radius: float = 100.0
	var influence_radius: float = 400.0
	## Optional, mirroring CelestialBody: when a source carries a definition,
	## its gravity_strength is what fills the cap.
	var definition: Resource = null

	func get_body_radius() -> float:
		return body_radius

	func get_influence_radius() -> float:
		return influence_radius


class ThrustHeld:
	extends Node

	func is_thrust_pressed() -> bool:
		return true

	func is_shoot_pressed() -> bool:
		return false

	func get_turn_axis() -> float:
		return 0.0


class NoInput:
	extends Node

	func is_thrust_pressed() -> bool:
		return false

	func is_shoot_pressed() -> bool:
		return false

	func get_turn_axis() -> float:
		return 0.0


## Holds thrust down. The ship reads input through `input_source`, so a test
## can fly it for real rather than re-implementing _apply_thrust_input().
class ThrustInput:
	extends Node

	func get_turn_axis() -> float:
		return 0.0

	func is_thrust_pressed() -> bool:
		return true

	func is_shoot_pressed() -> bool:
		return false


func _init() -> void:
	var failures: Array[String] = []

	await _test_gravity_free_ship_motion_stays_unchanged(failures)
	await _test_player_ship_accumulates_gravity(failures)
	await _test_asteroid_accumulates_gravity(failures)
	_test_the_cap_tracks_the_ship_it_protects(failures)
	await _test_full_thrust_escapes_every_committed_body(failures)
	await _test_a_dry_tank_still_escapes_every_committed_body(failures)
	await _test_gravity_strength_scales_the_surface_pull(failures)
	_test_acceleration_is_exactly_zero_outside_influence(failures)
	_test_acceleration_increases_toward_surface(failures)
	_test_overlapping_influences_sum(failures)
	await _test_bullets_ignore_gravity_sources(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL GRAVITY TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


## The cap is a promise about one specific ship: surface gravity is
## SURFACE_ACCELERATION_CAP_RATIO of what the player can push back with, so
## full thrust escapes by construction rather than by tuning. GravityField
## cannot read that number off player_ship.gd -- player_ship.gd preloads
## GravityField, and GDScript rejects the cycle -- so the ship's acceleration
## is duplicated there as a constant, and this is the only thing holding the
## two together. The escapability test below cannot do it: it reads the
## scene's own acceleration, so it keeps passing while the real ratio drifts,
## right up until a weakened ship stops escaping at all.
func _test_the_cap_tracks_the_ship_it_protects(failures: Array[String]) -> void:
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Area2D
	var ship_acceleration: float = player.acceleration
	player.free()

	if ship_acceleration <= 0.0:
		failures.append("Cap drift: PlayerShip.acceleration is %.1f, so the cap protects nothing" % ship_acceleration)
		return

	if is_equal_approx(GRAVITY_FIELD.PLAYER_MAX_THRUST_ACCELERATION, ship_acceleration):
		return

	var actual_ratio: float = GRAVITY_FIELD.max_surface_acceleration(
		GRAVITY_FIELD.PLAYER_MAX_THRUST_ACCELERATION
	) / ship_acceleration
	failures.append(
		"Cap drift: GravityField assumes a %.1f thrust ship but PlayerShip.acceleration is %.1f, putting surface gravity at %.2f of thrust instead of %.2f"
		% [
			GRAVITY_FIELD.PLAYER_MAX_THRUST_ACCELERATION,
			ship_acceleration,
			actual_ratio,
			GRAVITY_FIELD.SURFACE_ACCELERATION_CAP_RATIO,
		]
	)


func _test_full_thrust_escapes_every_committed_body(failures: Array[String]) -> void:
	var sector_script := load(SECTOR_SCRIPT) as Script
	var definition := load(SHIPPED_SECTOR) as Resource
	var player_scene := load(PLAYER_SCENE) as PackedScene
	if sector_script == null or definition == null or player_scene == null:
		failures.append("Escapability: could not load shipped sector or player scene")
		return

	var player := player_scene.instantiate() as Area2D
	var player_acceleration: float = player.acceleration
	var max_speed: float = player.max_speed
	player.free()

	var sector := sector_script.new() as Node2D
	sector.definition = definition
	root.add_child(sector)
	await process_frame

	var rng := RandomNumberGenerator.new()
	rng.seed = definition.sector_seed
	sector.place_content(rng)
	await process_frame

	var bodies: Array = sector.get_celestial_bodies()
	if bodies.is_empty():
		failures.append("Escapability: shipped sector placed no gravity bodies")

	for body in bodies:
		var radius: float = body.get_body_radius()
		var influence_radius: float = body.get_influence_radius()
		var position: Vector2 = body.global_position + Vector2.RIGHT * radius
		var velocity := Vector2.ZERO
		var escaped := false
		var delta := 1.0 / 60.0

		for _frame in 720:
			var thrust := Vector2.RIGHT * player_acceleration
			var gravity: Vector2 = GRAVITY_FIELD.acceleration_from(position, body)
			velocity += (thrust + gravity) * delta
			velocity = velocity.limit_length(max_speed)
			position += velocity * delta

			if position.distance_to(body.global_position) > influence_radius:
				escaped = true
				break

		if not escaped:
			failures.append(
				"Escapability: full thrust did not escape %s from surface radius %.1f within %.1fs"
				% [body.name, radius, 720.0 * delta]
			)

	# Per body is what #52 asks for, but it is not what a ship flies through.
	# Every moon in the shipped sector orbits INSIDE its planet's influence
	# radius, so the field fought near a moon is the moon's plus the planet's.
	# On the shipped sector that sums to 0.82 of thrust where the cap alone
	# reads 0.70, and the margin narrows with every moon a sector adds -- so
	# the escape is asserted against the sum, and outward in every direction
	# rather than only along +X, because the summed field is not radial.
	var sources: Array[Node] = get_nodes_in_group("gravity_sources")
	for body in bodies:
		var radius: float = body.get_body_radius()
		var influence_radius: float = body.get_influence_radius()

		for step in 24:
			var angle := TAU * float(step) / 24.0
			var away := Vector2.RIGHT.rotated(angle)
			var position: Vector2 = body.global_position + away * radius
			var velocity := Vector2.ZERO
			var delta := 1.0 / 60.0
			var escaped := false

			for _frame in 900:
				var gravity: Vector2 = GRAVITY_FIELD.accumulate(position, sources)
				velocity += (away * player_acceleration + gravity) * delta
				velocity = velocity.limit_length(max_speed)
				position += velocity * delta

				if position.distance_to(body.global_position) > influence_radius:
					escaped = true
					break

			if not escaped:
				failures.append(
					"Escapability: full thrust did not escape %s through the summed field, thrusting %.0f degrees outward"
					% [body.name, rad_to_deg(angle)]
				)
				break

	for body in bodies:
		body.remove_from_group("gravity_sources")
	root.remove_child(sector)
	sector.queue_free()
	await process_frame


## A ship that has run its tank dry must still be able to leave a gravity well.
##
## `ship_systems.gd` states the contract this protects: "a hard fuel-out in an
## 8000x6000 sector strands the player with no way to reach a station and no
## way to die, which is an unwinnable soft-lock no amount of tuning removes.
## Reserve thrust turns it into a slow, costly, survivable limp home." #52 says
## the same in its own words -- "without ever creating a trap the player cannot
## escape".
##
## Surface gravity capped against the ship's FULL thrust is 0.7 x 360 = 252,
## while reserve thrust is 0.25 x 360 = 90, so gravity wins everywhere inside
## 1.673 x body_radius -- 18% of every influence disc. And the player cannot die
## out of it: PlayerShip.collision_mask excludes CelestialBody's layer and
## nothing connects area_entered, so the run can be neither continued nor ended.
##
## Flown with the real ship rather than a re-implementation of it, because the
## thing under test is what the player's own _physics_process does.
func _test_a_dry_tank_still_escapes_every_committed_body(failures: Array[String]) -> void:
	_clear_gravity_sources()
	var sector_script := load(SECTOR_SCRIPT) as Script
	var definition := load(SHIPPED_SECTOR) as Resource
	if sector_script == null or definition == null:
		failures.append("Dry escape: could not load the shipped sector")
		return

	var sector := sector_script.new() as Node2D
	sector.definition = definition
	root.add_child(sector)
	await process_frame

	var rng := RandomNumberGenerator.new()
	rng.seed = definition.sector_seed
	sector.place_content(rng)
	await process_frame

	var bodies: Array = sector.get_celestial_bodies()
	if bodies.is_empty():
		failures.append("Dry escape: shipped sector placed no gravity bodies")

	var input := ThrustInput.new()
	root.add_child(input)
	var ship := (load(PLAYER_SCENE) as PackedScene).instantiate() as Area2D
	root.add_child(ship)
	await process_frame
	ship.input_source = input
	ship.set_sector_bounds(definition.get_bounds())

	var delta := 1.0 / float(Engine.physics_ticks_per_second)

	for body in bodies:
		var radius: float = body.get_body_radius()
		var influence_radius: float = body.get_influence_radius()
		var away := Vector2.RIGHT

		ship.global_position = body.global_position + away * radius
		ship.velocity = Vector2.ZERO
		# Vector2.UP.rotated(rotation) is the thrust direction.
		ship.rotation = away.angle() + PI * 0.5
		ship.ship_systems.reset_systems()
		# Empty the tank for real, through the same path the game uses.
		for _drain in 400:
			ship.ship_systems.consume_fuel(1.0)

		if ship.ship_systems.fuel > 0.0:
			failures.append("Dry escape: the tank did not empty, holds %f" % ship.ship_systems.fuel)
			break
		if is_equal_approx(ship.ship_systems.get_thrust_factor(), 1.0):
			failures.append("Dry escape: an empty tank still reports full thrust")
			break

		var escaped := false
		var best := 0.0
		for _frame in 3600:
			ship._physics_process(delta)
			var travelled: float = ship.global_position.distance_to(body.global_position)
			best = maxf(best, travelled)
			if travelled > influence_radius:
				escaped = true
				break

		if not escaped:
			failures.append(
				"Dry escape: a fuel-dry ship never left %s -- reached %.0f of the %.0f influence radius in 60s"
				% [body.name, best, influence_radius]
			)

	ship.queue_free()
	input.queue_free()
	for body in bodies:
		body.remove_from_group("gravity_sources")
	root.remove_child(sector)
	sector.queue_free()
	await process_frame
	_clear_gravity_sources()


## #51 committed gravity_strength 1400 for planets and 350 for moons -- a
## deliberate 4:1 -- and nothing read it, so a 76px moon pulled exactly as hard
## as a 220px planet and a body authored with no gravity still pulled at the
## full cap. #52's safety rule says gravity is "capped at" 0.7x thrust, which is
## a ceiling; the authored strength is what fills it.
func _test_gravity_strength_scales_the_surface_pull(failures: Array[String]) -> void:
	_clear_gravity_sources()
	var definition_script := load("res://scripts/resources/celestial_body_definition.gd") as Script

	var full := _make_strength_source(Vector2.ZERO, 100.0, 400.0, 1400.0, definition_script)
	var quarter := _make_strength_source(Vector2(4000.0, 0.0), 100.0, 400.0, 350.0, definition_script)
	var none := _make_strength_source(Vector2(8000.0, 0.0), 100.0, 400.0, 0.0, definition_script)
	await process_frame

	var full_pull: float = GRAVITY_FIELD.acceleration_from(full.global_position + Vector2.RIGHT * 100.0, full).length()
	var quarter_pull: float = GRAVITY_FIELD.acceleration_from(quarter.global_position + Vector2.RIGHT * 100.0, quarter).length()
	var none_pull: float = GRAVITY_FIELD.acceleration_from(none.global_position + Vector2.RIGHT * 100.0, none).length()

	var cap: float = GRAVITY_FIELD.max_surface_acceleration(GRAVITY_FIELD.PLAYER_MAX_THRUST_ACCELERATION)
	if not is_equal_approx(full_pull, cap):
		failures.append("Strength scaling: a 1400 body should pull at the cap %.2f, pulled %.2f" % [cap, full_pull])
	if not is_equal_approx(quarter_pull, cap * 0.25):
		failures.append(
			"Strength scaling: a 350 body should pull at a quarter of the cap (%.2f), pulled %.2f"
			% [cap * 0.25, quarter_pull]
		)
	if not is_zero_approx(none_pull):
		failures.append("Strength scaling: a body authored with no gravity pulled %.2f" % none_pull)

	for source in [full, quarter, none]:
		source.remove_from_group("gravity_sources")
		source.queue_free()
	await process_frame
	_clear_gravity_sources()


func _make_strength_source(
	position: Vector2,
	radius: float,
	influence_radius: float,
	strength: float,
	definition_script: Script
) -> Node2D:
	var source := _make_source(position, radius, influence_radius)
	var body_definition: Resource = definition_script.new()
	body_definition.body_radius = radius
	body_definition.gravity_strength = strength
	body_definition.influence_multiplier = influence_radius / radius
	source.set("definition", body_definition)
	source.add_to_group("gravity_sources")
	return source


func _test_acceleration_is_exactly_zero_outside_influence(failures: Array[String]) -> void:
	var source := _make_source(Vector2.ZERO, 100.0, 400.0)
	var acceleration: Vector2 = GRAVITY_FIELD.acceleration_from(Vector2(401.0, 0.0), source)

	if acceleration != Vector2.ZERO:
		failures.append("Zero influence: acceleration outside radius must be exactly ZERO, got %s" % acceleration)

	source.free()


func _test_acceleration_increases_toward_surface(failures: Array[String]) -> void:
	var source := _make_source(Vector2.ZERO, 100.0, 400.0)
	var surface: float = GRAVITY_FIELD.acceleration_from(Vector2(100.0, 0.0), source).length()
	var middle: float = GRAVITY_FIELD.acceleration_from(Vector2(200.0, 0.0), source).length()
	var edge: float = GRAVITY_FIELD.acceleration_from(Vector2(350.0, 0.0), source).length()
	var cap: float = GRAVITY_FIELD.max_surface_acceleration(360.0)

	if not is_equal_approx(surface, cap):
		failures.append("Monotonic: surface acceleration %.4f must equal cap %.4f" % [surface, cap])
	if not (surface > middle and middle > edge and edge > 0.0):
		failures.append("Monotonic: expected surface %.4f > middle %.4f > edge %.4f > 0" % [surface, middle, edge])

	source.free()


func _test_overlapping_influences_sum(failures: Array[String]) -> void:
	var left := _make_source(Vector2.ZERO, 100.0, 400.0)
	var right := _make_source(Vector2(300.0, 0.0), 100.0, 400.0)
	var sources: Array[Node] = [left, right]
	var position := Vector2(100.0, 0.0)
	var expected: Vector2 = (
		GRAVITY_FIELD.acceleration_from(position, left)
		+ GRAVITY_FIELD.acceleration_from(position, right)
	)
	var actual: Vector2 = GRAVITY_FIELD.accumulate(position, sources)

	if not actual.is_equal_approx(expected):
		failures.append("Summing: overlapping gravity expected %s, got %s" % [expected, actual])

	left.free()
	right.free()


func _test_gravity_free_ship_motion_stays_unchanged(failures: Array[String]) -> void:
	_clear_gravity_sources()
	var ship := (load(PLAYER_SCENE) as PackedScene).instantiate() as Area2D
	var input := ThrustHeld.new()
	root.add_child(input)
	root.add_child(ship)
	await process_frame
	_clear_gravity_sources()

	ship.input_source = input
	ship.set_sector_bounds(Rect2(Vector2.ZERO, Vector2(3000.0, 3000.0)))
	ship.global_position = Vector2(1000.0, 1000.0)
	ship.rotation = PI / 2.0
	ship.velocity = Vector2.ZERO

	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var expected_velocity: Vector2 = Vector2.RIGHT * ship.acceleration * delta
	expected_velocity = expected_velocity.limit_length(ship.max_speed)
	expected_velocity = expected_velocity.move_toward(Vector2.ZERO, ship.linear_drag * delta)
	var expected_position: Vector2 = ship.global_position + expected_velocity * delta

	ship._physics_process(delta)

	if not ship.velocity.is_equal_approx(expected_velocity):
		failures.append("Gravity-free ship: velocity changed from expected %s to %s" % [expected_velocity, ship.velocity])
	if ship.global_position.distance_to(expected_position) > 0.01:
		failures.append("Gravity-free ship: position expected %s, got %s" % [expected_position, ship.global_position])

	ship.queue_free()
	input.queue_free()
	await process_frame
	_clear_gravity_sources()


func _test_player_ship_accumulates_gravity(failures: Array[String]) -> void:
	_clear_gravity_sources()
	var ship := (load(PLAYER_SCENE) as PackedScene).instantiate() as Area2D
	var input := NoInput.new()
	root.add_child(input)
	root.add_child(ship)
	await process_frame
	_clear_gravity_sources()

	var source := _make_source(Vector2.ZERO, 100.0, 400.0)
	source.add_to_group("gravity_sources")
	root.add_child(source)

	ship.input_source = input
	ship.set_sector_bounds(Rect2(Vector2(-1000.0, -1000.0), Vector2(3000.0, 3000.0)))
	ship.global_position = Vector2(200.0, 0.0)
	ship.velocity = Vector2.ZERO

	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var expected_gravity: Vector2 = GRAVITY_FIELD.acceleration_from(ship.global_position, source)
	var expected_velocity: Vector2 = (expected_gravity * delta).limit_length(ship.max_speed)
	expected_velocity = expected_velocity.move_toward(Vector2.ZERO, ship.linear_drag * delta)

	ship._physics_process(delta)

	if not ship.velocity.is_equal_approx(expected_velocity):
		failures.append("Player gravity: velocity expected %s, got %s" % [expected_velocity, ship.velocity])

	ship.queue_free()
	input.queue_free()
	source.remove_from_group("gravity_sources")
	source.queue_free()
	await process_frame
	_clear_gravity_sources()


func _test_asteroid_accumulates_gravity(failures: Array[String]) -> void:
	_clear_gravity_sources()
	var asteroid := (load("res://scenes/entities/Asteroid.tscn") as PackedScene).instantiate() as Area2D
	root.add_child(asteroid)
	await process_frame
	_clear_gravity_sources()

	var source := _make_source(Vector2.ZERO, 100.0, 400.0)
	source.add_to_group("gravity_sources")
	root.add_child(source)

	asteroid.set_sector_bounds(Rect2(Vector2(-1000.0, -1000.0), Vector2(3000.0, 3000.0)))
	asteroid.global_position = Vector2(200.0, 0.0)
	asteroid.velocity = Vector2.ZERO

	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var expected_velocity: Vector2 = GRAVITY_FIELD.acceleration_from(asteroid.global_position, source) * delta
	expected_velocity = expected_velocity.limit_length(asteroid.get_collision_radius() / delta)

	asteroid._physics_process(delta)

	if not asteroid.velocity.is_equal_approx(expected_velocity):
		failures.append("Asteroid gravity: velocity expected %s, got %s" % [expected_velocity, asteroid.velocity])

	asteroid.queue_free()
	source.remove_from_group("gravity_sources")
	source.queue_free()
	await process_frame
	_clear_gravity_sources()


func _test_bullets_ignore_gravity_sources(failures: Array[String]) -> void:
	_clear_gravity_sources()
	var source := _make_source(Vector2(500.0, 500.0), 100.0, 1000.0)
	source.add_to_group("gravity_sources")
	root.add_child(source)

	var bullet := (load(BULLET_SCENE) as PackedScene).instantiate() as Area2D
	root.add_child(bullet)
	await process_frame

	bullet.set_sector_bounds(Rect2(Vector2.ZERO, Vector2(3000.0, 3000.0)))
	bullet.global_position = Vector2(600.0, 500.0)
	bullet.launch(Vector2.RIGHT, Vector2.ZERO)

	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var expected_velocity: Vector2 = Vector2.RIGHT * bullet.speed
	var expected_position: Vector2 = bullet.global_position + expected_velocity * delta

	bullet._physics_process(delta)

	if not bullet.velocity.is_equal_approx(expected_velocity):
		failures.append("Bullet gravity: velocity changed to %s" % bullet.velocity)
	if bullet.global_position.distance_to(expected_position) > 0.01:
		failures.append("Bullet gravity: position expected %s, got %s" % [expected_position, bullet.global_position])

	bullet.queue_free()
	source.remove_from_group("gravity_sources")
	source.queue_free()
	await process_frame
	_clear_gravity_sources()


func _make_source(position: Vector2, radius: float, influence_radius: float) -> GravitySource:
	var source := GravitySource.new()
	source.global_position = position
	source.body_radius = radius
	source.influence_radius = influence_radius
	return source


func _clear_gravity_sources() -> void:
	for source in get_nodes_in_group("gravity_sources"):
		source.remove_from_group("gravity_sources")
