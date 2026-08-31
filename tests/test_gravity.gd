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


func _init() -> void:
	var failures: Array[String] = []

	await _test_gravity_free_ship_motion_stays_unchanged(failures)
	await _test_player_ship_accumulates_gravity(failures)
	await _test_asteroid_accumulates_gravity(failures)
	await _test_full_thrust_escapes_every_committed_body(failures)
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

	for body in bodies:
		body.remove_from_group("gravity_sources")
	root.remove_child(sector)
	sector.queue_free()
	await process_frame


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
