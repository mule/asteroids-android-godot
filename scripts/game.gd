extends Node2D


const ASTEROID_LARGE := 0
const ASTEROID_MEDIUM := 1
const ASTEROID_SMALL := 2

@export var asteroid_scene: PackedScene
@export var bullet_scene: PackedScene
@export var starting_score: int = 0
@export var starting_lives: int = 3
@export var starting_wave: int = 1
@export var initial_asteroid_count: int = 4
@export var spawn_safe_radius: float = 180.0
@export var split_child_count: int = 2
@export var random_seed: int = 1729

@onready var entities: Node2D = $Entities
@onready var player_ship: Area2D = $Entities/PlayerShip

var random := RandomNumberGenerator.new()


func _ready() -> void:
	random.seed = random_seed
	player_ship.shoot_requested.connect(_on_player_ship_shoot_requested)
	_spawn_initial_asteroids()


func _on_player_ship_shoot_requested(
	muzzle_position: Vector2,
	direction: Vector2,
	inherited_velocity: Vector2
) -> void:
	var bullet := bullet_scene.instantiate()
	entities.add_child(bullet)
	bullet.global_position = muzzle_position

	if bullet.has_method("launch"):
		bullet.launch(direction, inherited_velocity)


func _spawn_initial_asteroids() -> void:
	for index in initial_asteroid_count:
		var spawn_position := _get_safe_spawn_position(index)
		var velocity := _get_random_asteroid_velocity(ASTEROID_LARGE)
		_spawn_asteroid(ASTEROID_LARGE, spawn_position, velocity)


func _spawn_asteroid(size_tier: int, spawn_position: Vector2, velocity: Vector2) -> Area2D:
	var asteroid := asteroid_scene.instantiate() as Area2D
	entities.add_child(asteroid)
	asteroid.global_position = spawn_position

	if asteroid.has_method("setup"):
		asteroid.setup(size_tier, velocity)

	if asteroid.has_signal("destroyed"):
		asteroid.destroyed.connect(_on_asteroid_destroyed)

	return asteroid


func _on_asteroid_destroyed(
	asteroid: Area2D,
	size_tier: int,
	hit_position: Vector2,
	incoming_velocity: Vector2
) -> void:
	if size_tier >= ASTEROID_SMALL:
		return

	var next_size := size_tier + 1

	for index in split_child_count:
		var velocity := _get_split_velocity(next_size, incoming_velocity, index)
		_spawn_asteroid(next_size, hit_position, velocity)


func _get_safe_spawn_position(index: int) -> Vector2:
	var viewport_rect := get_viewport_rect()

	for attempt in 32:
		var spawn_position := Vector2(
			random.randf_range(viewport_rect.position.x, viewport_rect.end.x),
			random.randf_range(viewport_rect.position.y, viewport_rect.end.y)
		)

		if spawn_position.distance_to(player_ship.global_position) >= spawn_safe_radius:
			return spawn_position

	var fallback_angle := TAU * float(index) / maxf(1.0, float(initial_asteroid_count))
	var fallback_radius := spawn_safe_radius + 80.0
	return player_ship.global_position + Vector2.RIGHT.rotated(fallback_angle) * fallback_radius


func _get_random_asteroid_velocity(size_tier: int) -> Vector2:
	var angle := random.randf_range(0.0, TAU)
	var speed := random.randf_range(_get_min_speed(size_tier), _get_max_speed(size_tier))
	return Vector2.RIGHT.rotated(angle) * speed


func _get_split_velocity(size_tier: int, incoming_velocity: Vector2, index: int) -> Vector2:
	var base_angle := incoming_velocity.angle()

	if incoming_velocity.length_squared() <= 0.01:
		base_angle = random.randf_range(0.0, TAU)

	var spread := deg_to_rad(55.0)
	var centered_index := float(index) - (float(split_child_count - 1) / 2.0)
	var angle := base_angle + centered_index * spread + random.randf_range(-0.25, 0.25)
	var speed := random.randf_range(_get_min_speed(size_tier), _get_max_speed(size_tier))
	return Vector2.RIGHT.rotated(angle) * speed


func _get_min_speed(size_tier: int) -> float:
	match size_tier:
		ASTEROID_LARGE:
			return 45.0
		ASTEROID_MEDIUM:
			return 75.0
		_:
			return 110.0


func _get_max_speed(size_tier: int) -> float:
	match size_tier:
		ASTEROID_LARGE:
			return 105.0
		ASTEROID_MEDIUM:
			return 145.0
		_:
			return 190.0
