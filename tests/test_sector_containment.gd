extends SceneTree


const ASTEROID_SCENE := "res://scenes/entities/Asteroid.tscn"
const BULLET_SCENE := "res://scenes/entities/Bullet.tscn"
const PLAYER_SCENE := "res://scenes/entities/PlayerShip.tscn"
const GAME_SCENE := "res://scenes/game/Game.tscn"

const SECTOR_BOUNDS := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))


## Stands in for PlayerInput so a test can hold the thrust key down.
class ThrustHeld:
	extends Node

	func get_turn_axis() -> float:
		return 0.0

	func is_thrust_pressed() -> bool:
		return true

	func is_shoot_pressed() -> bool:
		return false


func _init() -> void:
	var failures: Array[String] = []

	await _test_asteroid_reflects_instead_of_wrapping(failures)
	await _test_asteroid_never_leaves_sector_over_time(failures)
	await _test_bullet_despawns_at_boundary(failures)
	await _test_ship_is_pushed_back_from_the_wall(failures)
	await _test_edge_pressure_never_exceeds_max_speed(failures)
	await _test_disabled_ship_holds_still_and_drops_the_warning(failures)
	await _test_the_shipped_game_wires_the_margin_and_the_hud(failures)
	await _test_a_ship_pinned_on_the_wall_reports_no_outward_speed(failures)
	await _test_a_rock_crushed_against_the_wall_never_points_outward(failures)
	await _test_a_rock_parented_off_the_origin_is_contained_in_world_space(failures)

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
	ship.position = Vector2(4000.0, 3000.0)
	ship.set_sector_bounds(SECTOR_BOUNDS)
	ship.set_boundary_margin(600.0)
	await physics_frame

	# Drifting outward inside the margin band, with no player input.
	ship.global_position = Vector2(80.0, 3000.0)
	ship.velocity = Vector2(-200.0, 0.0)

	var warned := [false]
	ship.boundary_warning_changed.connect(func(active: bool) -> void:
		if active:
			warned[0] = true
	)

	for _step in 90:
		await physics_frame

		if not SECTOR_BOUNDS.has_point(ship.global_position):
			failures.append("Containment: ship left the sector at %s" % str(ship.global_position))
			break

	if ship.velocity.x <= 0.0:
		failures.append("Containment: edge pressure did not reverse the ship's outward drift (vx=%f)" % ship.velocity.x)
	if not warned[0]:
		failures.append("Containment: boundary_warning_changed was never emitted inside the margin band")

	ship.queue_free()
	await physics_frame


func _test_edge_pressure_never_exceeds_max_speed(failures: Array[String]) -> void:
	var ship := (load(PLAYER_SCENE) as PackedScene).instantiate() as Area2D
	root.add_child(ship)
	ship.position = Vector2(4000.0, 3000.0)
	ship.set_sector_bounds(SECTOR_BOUNDS)
	ship.set_boundary_margin(600.0)
	await physics_frame

	# Dropped against the wall at rest: the only thing accelerating it is the
	# full 600px of edge pressure.
	ship.global_position = Vector2(0.0, 3000.0)
	ship.velocity = Vector2.ZERO

	var peak_speed := 0.0
	for _step in 200:
		await physics_frame
		peak_speed = maxf(peak_speed, ship.velocity.length())

	if peak_speed > ship.max_speed + 1.0:
		failures.append(
			"Containment: edge pressure slingshot the ship to %f past max_speed %f"
			% [peak_speed, ship.max_speed]
		)

	ship.queue_free()
	await physics_frame


func _test_disabled_ship_holds_still_and_drops_the_warning(failures: Array[String]) -> void:
	var ship := (load(PLAYER_SCENE) as PackedScene).instantiate() as Area2D
	root.add_child(ship)
	ship.position = Vector2(4000.0, 3000.0)
	ship.set_sector_bounds(SECTOR_BOUNDS)
	ship.set_boundary_margin(600.0)
	await physics_frame

	# Warned, deep inside the margin band, and then killed off there.
	ship.global_position = Vector2(200.0, 3000.0)
	ship.velocity = Vector2.ZERO

	for _step in 5:
		await physics_frame

	var warnings: Array[bool] = []
	ship.boundary_warning_changed.connect(func(active: bool) -> void: warnings.append(active))
	ship.set_controls_enabled(false)

	var resting_position: Vector2 = ship.global_position
	for _step in 120:
		await physics_frame

	if ship.global_position != resting_position:
		failures.append(
			"Containment: a ship with controls disabled coasted from %s to %s"
			% [str(resting_position), str(ship.global_position)]
		)
	if warnings.is_empty() or warnings.back() != false:
		failures.append(
			"Containment: disabling controls must clear the boundary warning, got %s"
			% str(warnings)
		)

	ship.queue_free()
	await physics_frame


func _test_the_shipped_game_wires_the_margin_and_the_hud(failures: Array[String]) -> void:
	# Every other test in this file hands the ship its margin by hand, so a
	# game.gd that forgot to push sector.get_boundary_margin(), or a HUD label
	# never connected to the signal, would leave the whole feature dead in the
	# shipped scene and the suite still green.
	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	game.auto_start = false
	root.add_child(game)
	await process_frame
	await process_frame

	var sector_margin: float = game.sector.get_boundary_margin()
	if sector_margin <= 0.0:
		failures.append("Wiring: the shipped sector must define a boundary margin, got %f" % sector_margin)

	# player_ship.gd's own default is the shipped 600 too, so comparing against
	# that proves nothing. Inject a different margin: only a game.gd that really
	# calls set_boundary_margin will report it back.
	var injected: Resource = (game.sector.definition as Resource).duplicate()
	injected.boundary_margin = 250.0
	game.sector.definition = injected
	game._apply_sector_bounds()

	if game.player_ship.boundary_margin != 250.0:
		failures.append(
			"Wiring: ship margin %f must come from the sector, not the script default"
			% game.player_ship.boundary_margin
		)

	# Inside the band the label shows, back at the centre it hides again.
	game.player_ship.global_position = game.sector.get_bounds().position
	await physics_frame
	if not game.hud.boundary_warning.visible:
		failures.append("Wiring: the HUD warning must show while the ship is against the wall")

	game.player_ship.global_position = game.sector.get_center()
	await physics_frame
	if game.hud.boundary_warning.visible:
		failures.append("Wiring: the HUD warning must clear once the ship is back inside")

	game.queue_free()
	await process_frame


func _test_a_ship_pinned_on_the_wall_reports_no_outward_speed(failures: Array[String]) -> void:
	# Edge pressure alone cannot hold a ship off the wall while thrust is held
	# into it: 1.5x acceleration only wins the last 200px, so a ship arriving at
	# speed reaches the wall and the hard clamp catches it. The clamp throws the
	# motion away, so the velocity has to go with it -- _apply_shoot_input hands
	# velocity to every bullet as inherited velocity and FollowCamera leads the
	# view with it, and both would be reading motion that is not happening.
	var ship := (load(PLAYER_SCENE) as PackedScene).instantiate() as Area2D
	root.add_child(ship)
	ship.set_sector_bounds(SECTOR_BOUNDS)
	ship.set_boundary_margin(600.0)
	await physics_frame

	var thrust := ThrustHeld.new()
	root.add_child(thrust)
	ship.input_source = thrust
	ship.global_position = Vector2(700.0, 3000.0)
	ship.rotation = -PI / 2.0
	ship.velocity = Vector2(-ship.max_speed, 0.0)

	var pinned := false
	for _step in 240:
		await physics_frame

		if ship.global_position.x > SECTOR_BOUNDS.position.x:
			continue

		pinned = true
		if ship.velocity.x < 0.0:
			failures.append(
				"Containment: a ship clamped on the wall still reports %f px/s into it"
				% ship.velocity.x
			)
			break

	if not pinned:
		failures.append("Containment: thrusting into the wall never reached it, test proves nothing")

	thrust.queue_free()
	ship.queue_free()
	await physics_frame


func _test_a_rock_crushed_against_the_wall_never_points_outward(failures: Array[String]) -> void:
	# Separating an overlap can shove a rock through a wall, so containment and
	# the elastic impulse both fire in the same resolve step. Containing first
	# lets the impulse overwrite the reflection and point the rock back out
	# while it is clamped on the wall, which earns it another impulse next frame
	# from the same unresolved overlap.
	var small := (load(ASTEROID_SCENE) as PackedScene).instantiate() as Area2D
	var large := (load(ASTEROID_SCENE) as PackedScene).instantiate() as Area2D
	root.add_child(small)
	root.add_child(large)
	small.add_to_group("asteroids")
	large.add_to_group("asteroids")
	small.set_sector_bounds(SECTOR_BOUNDS)
	large.set_sector_bounds(SECTOR_BOUNDS)
	small.setup(2, Vector2.ZERO, null, 0.0)
	large.setup(0, Vector2(-400.0, 0.0), null, 0.0)
	await physics_frame

	var wall_x: float = SECTOR_BOUNDS.position.x + small.get_collision_radius()
	small.global_position = Vector2(wall_x, 3000.0)
	small.velocity = Vector2.ZERO
	large.global_position = Vector2(wall_x + small.get_collision_radius() + large.get_collision_radius() - 6.0, 3004.0)
	large.velocity = Vector2(-400.0, 0.0)

	for _step in 60:
		await physics_frame

		if not is_instance_valid(small):
			break

		if is_equal_approx(small.global_position.x, wall_x) and small.velocity.x < 0.0:
			failures.append(
				"Containment: rock clamped on the wall at x=%f still carries %f px/s outward"
				% [small.global_position.x, small.velocity.x]
			)
			break

	small.queue_free()
	large.queue_free()
	await physics_frame


func _test_a_rock_parented_off_the_origin_is_contained_in_world_space(failures: Array[String]) -> void:
	# An asteroid seeded by an AsteroidField is parented to that field, not to
	# Entities, so its own `position` is an offset from the field centre. Sector
	# bounds are world space: containment that reads `position` clamps every
	# rock left of or above its field's centre against a wall that is not there,
	# and walls each field in at its own origin.
	var field := Node2D.new()
	field.position = Vector2(4000.0, 3000.0)
	root.add_child(field)

	var asteroid := (load(ASTEROID_SCENE) as PackedScene).instantiate() as Area2D
	field.add_child(asteroid)
	asteroid.add_to_group("asteroids")
	asteroid.set_sector_bounds(SECTOR_BOUNDS)
	asteroid.setup(0, Vector2(-60.0, -40.0), null, 0.0)
	asteroid.position = Vector2(-300.0, -200.0)
	var start := asteroid.global_position

	for _step in 20:
		await physics_frame

	if asteroid.velocity.x >= 0.0 or asteroid.velocity.y >= 0.0:
		failures.append(
			"Containment: a rock at world %s reflected as if it were on the wall, velocity %s"
			% [str(start), str(asteroid.velocity)]
		)

	var travelled: float = asteroid.global_position.distance_to(start)
	if travelled > 200.0:
		failures.append(
			"Containment: a field-parented rock jumped %f px, from %s to %s"
			% [travelled, str(start), str(asteroid.global_position)]
		)

	asteroid.queue_free()
	field.queue_free()
	await physics_frame
