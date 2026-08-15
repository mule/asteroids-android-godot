extends SceneTree


const ASTEROID_SCENE := "res://scenes/entities/Asteroid.tscn"
const BULLET_SCENE := "res://scenes/entities/Bullet.tscn"
const PLAYER_SCENE := "res://scenes/entities/PlayerShip.tscn"
const GAME_SCENE := "res://scenes/game/Game.tscn"


func _init() -> void:
	var failures: Array[String] = []

	await _test_head_on_collision(failures)
	await _test_different_size_collision(failures)
	await _test_glancing_collision(failures)
	await _test_overlap_separation(failures)
	await _test_three_asteroid_cluster(failures)
	await _test_bullet_destroys_asteroid(failures)
	await _test_player_ship_collides_with_asteroid(failures)
	await _test_multi_frame_stability(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL ASTEROID COLLISION TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


func _test_head_on_collision(failures: Array[String]) -> void:
	var packed_scene := load(ASTEROID_SCENE) as PackedScene
	var a1 := packed_scene.instantiate() as Area2D
	var a2 := packed_scene.instantiate() as Area2D

	root.add_child(a1)
	root.add_child(a2)
	a1.add_to_group("asteroids")
	a2.add_to_group("asteroids")

	a1.setup(0, Vector2(100, 0), null, 0.0) # Large, radius 44
	a2.setup(0, Vector2(-100, 0), null, 0.0) # Large, radius 44

	a1.global_position = Vector2(400, 300)
	a2.global_position = Vector2(470, 300) # distance = 70 < 88 (overlapping)

	for _step in 5:
		await physics_frame

	var vel1: Vector2 = a1.velocity
	var vel2: Vector2 = a2.velocity
	if vel1.x >= 0.0:
		failures.append("Head-on: a1 should bounce left, but velocity.x is %f" % vel1.x)
	if vel2.x <= 0.0:
		failures.append("Head-on: a2 should bounce right, but velocity.x is %f" % vel2.x)

	var final_dist: float = a1.global_position.distance_to(a2.global_position)
	if final_dist < 87.9:
		failures.append("Head-on: asteroids did not separate; distance is %f (expected >= 88)" % final_dist)

	a1.queue_free()
	a2.queue_free()
	await physics_frame


func _test_different_size_collision(failures: Array[String]) -> void:
	var packed_scene := load(ASTEROID_SCENE) as PackedScene
	var large := packed_scene.instantiate() as Area2D
	var small := packed_scene.instantiate() as Area2D

	root.add_child(large)
	root.add_child(small)
	large.add_to_group("asteroids")
	small.add_to_group("asteroids")

	large.setup(0, Vector2(100, 0), null, 0.0) # Large, m=4
	small.setup(2, Vector2(0, 0), null, 0.0)   # Small, m=1

	large.global_position = Vector2(400, 300)
	small.global_position = Vector2(450, 300) # distance 50 < 44+16=60

	for _step in 5:
		await physics_frame

	var s_vel: Vector2 = small.velocity
	var l_vel: Vector2 = large.velocity
	if s_vel.x <= 50.0:
		failures.append("Different size: small asteroid velocity should be high, got %f" % s_vel.x)
	if l_vel.x <= 0.0 or l_vel.x >= 100.0:
		failures.append("Different size: large asteroid velocity should be between 0 and 100, got %f" % l_vel.x)

	large.queue_free()
	small.queue_free()
	await physics_frame


func _test_glancing_collision(failures: Array[String]) -> void:
	var packed_scene := load(ASTEROID_SCENE) as PackedScene
	var a1 := packed_scene.instantiate() as Area2D
	var a2 := packed_scene.instantiate() as Area2D

	root.add_child(a1)
	root.add_child(a2)
	a1.add_to_group("asteroids")
	a2.add_to_group("asteroids")

	a1.setup(0, Vector2(100, 50), null, 0.0)
	a2.setup(0, Vector2(-100, -50), null, 0.0)

	a1.global_position = Vector2(400, 300)
	a2.global_position = Vector2(460, 340)

	for _step in 5:
		await physics_frame

	var vel1: Vector2 = a1.velocity
	var vel2: Vector2 = a2.velocity
	if vel1.x >= 0.0:
		failures.append("Glancing: a1 velocity.x should be deflected negative, got %f" % vel1.x)
	if vel2.x <= 0.0:
		failures.append("Glancing: a2 velocity.x should be deflected positive, got %f" % vel2.x)

	a1.queue_free()
	a2.queue_free()
	await physics_frame


func _test_overlap_separation(failures: Array[String]) -> void:
	var packed_scene := load(ASTEROID_SCENE) as PackedScene
	var a1 := packed_scene.instantiate() as Area2D
	var a2 := packed_scene.instantiate() as Area2D

	root.add_child(a1)
	root.add_child(a2)
	a1.add_to_group("asteroids")
	a2.add_to_group("asteroids")

	a1.setup(0, Vector2.ZERO, null, 0.0)
	a2.setup(0, Vector2.ZERO, null, 0.0)

	# Exactly overlapping
	a1.global_position = Vector2(500, 300)
	a2.global_position = Vector2(500, 300)

	for _step in 5:
		await physics_frame

	var dist: float = a1.global_position.distance_to(a2.global_position)
	if dist < 87.9:
		failures.append("Overlap separation: expected distance >= 88, got %f" % dist)

	a1.queue_free()
	a2.queue_free()
	await physics_frame


func _test_three_asteroid_cluster(failures: Array[String]) -> void:
	var packed_scene := load(ASTEROID_SCENE) as PackedScene
	var a1 := packed_scene.instantiate() as Area2D
	var a2 := packed_scene.instantiate() as Area2D
	var a3 := packed_scene.instantiate() as Area2D

	root.add_child(a1)
	root.add_child(a2)
	root.add_child(a3)
	a1.add_to_group("asteroids")
	a2.add_to_group("asteroids")
	a3.add_to_group("asteroids")

	a1.setup(0, Vector2(50, 0), null, 0.0)
	a2.setup(0, Vector2(-50, 0), null, 0.0)
	a3.setup(0, Vector2(0, -50), null, 0.0)

	a1.global_position = Vector2(400, 300)
	a2.global_position = Vector2(450, 300)
	a3.global_position = Vector2(425, 340)

	for _step in 10:
		await physics_frame

	var d12: float = a1.global_position.distance_to(a2.global_position)
	var d23: float = a2.global_position.distance_to(a3.global_position)
	var d13: float = a1.global_position.distance_to(a3.global_position)

	if d12 < 87.0 or d23 < 87.0 or d13 < 87.0:
		failures.append("Three asteroid cluster: asteroids did not disperse properly (d12=%f, d23=%f, d13=%f)" % [d12, d23, d13])

	a1.queue_free()
	a2.queue_free()
	a3.queue_free()
	await physics_frame


func _test_bullet_destroys_asteroid(failures: Array[String]) -> void:
	var game_packed := load(GAME_SCENE) as PackedScene
	var game := game_packed.instantiate()
	game.initial_asteroid_count = 1
	game.auto_start = false
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	# Clear initial wave asteroids
	for child in game.entities.get_children():
		if child != game.player_ship:
			child.queue_free()
	await physics_frame

	var ast: Area2D = game._spawn_asteroid(0, Vector2(600, 324), Vector2.ZERO)
	var initial_score: int = game.score

	game._on_player_ship_shoot_requested(Vector2(550, 324), Vector2.RIGHT, Vector2.ZERO)

	for _step in 15:
		await physics_frame

	if game.score <= initial_score:
		failures.append("Bullet collision: asteroid was not destroyed by bullet (score unchanged: %d)" % game.score)

	root.remove_child(game)
	game.free()
	await physics_frame


func _test_player_ship_collides_with_asteroid(failures: Array[String]) -> void:
	var game_packed := load(GAME_SCENE) as PackedScene
	var game := game_packed.instantiate()
	root.add_child(game)
	game.auto_start = false
	await physics_frame
	game._start_new_game()
	await physics_frame

	var initial_lives: int = game.lives
	var player: Area2D = game.player_ship
	player.set_invulnerable(false)

	# Spawn asteroid directly on player
	var ast: Area2D = game._spawn_asteroid(0, player.global_position, Vector2.ZERO)
	for _step in 5:
		await physics_frame

	if game.lives >= initial_lives:
		failures.append("Ship collision: player did not lose a life on asteroid collision")

	root.remove_child(game)
	game.free()
	await physics_frame


func _test_multi_frame_stability(failures: Array[String]) -> void:
	var game_packed := load(GAME_SCENE) as PackedScene
	var game := game_packed.instantiate()
	root.add_child(game)
	game.auto_start = false
	await physics_frame
	game._start_new_game()

	# Run for 120 frames with multiple asteroids moving and colliding
	for _step in 120:
		await physics_frame

	if not game.play_active:
		failures.append("Multi-frame stability: game became inactive unexpectedly")

	var ast_count: int = game._get_active_asteroid_count()
	if ast_count == 0:
		failures.append("Multi-frame stability: no active asteroids remaining")

	root.remove_child(game)
	game.free()
	await physics_frame
