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
