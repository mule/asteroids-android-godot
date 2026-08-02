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
@export var respawn_delay_seconds: float = 1.2
@export var respawn_invulnerability_seconds: float = 2.0
@export var random_seed: int = 1729

@onready var entities: Node2D = $Entities
@onready var player_ship: Area2D = $Entities/PlayerShip
@onready var hud: CanvasLayer = $Hud

var random := RandomNumberGenerator.new()
var score: int = 0
var lives: int = 0
var wave: int = 0
var play_active: bool = false
var respawning: bool = false


func _ready() -> void:
	random.seed = random_seed
	player_ship.shoot_requested.connect(_on_player_ship_shoot_requested)
	player_ship.area_entered.connect(_on_player_ship_area_entered)
	_start_new_game()


func _unhandled_input(event: InputEvent) -> void:
	if not play_active and event.is_action_pressed("restart"):
		_start_new_game()


func _start_new_game() -> void:
	_clear_dynamic_entities()
	score = starting_score
	lives = starting_lives
	wave = starting_wave
	play_active = true
	respawning = false
	hud.hide_status()
	_update_hud()
	_respawn_player(false)
	_spawn_wave()


func _on_player_ship_shoot_requested(
	muzzle_position: Vector2,
	direction: Vector2,
	inherited_velocity: Vector2
) -> void:
	if not play_active or respawning:
		return

	var bullet := bullet_scene.instantiate()
	entities.add_child(bullet)
	bullet.add_to_group("bullets")
	bullet.global_position = muzzle_position

	if bullet.has_method("launch"):
		bullet.launch(direction, inherited_velocity)


func _on_player_ship_area_entered(area: Area2D) -> void:
	if not play_active or respawning or not area.is_in_group("asteroids"):
		return

	lives = max(0, lives - 1)
	_update_hud()
	_clear_bullets()

	if lives <= 0:
		_end_game()
		return

	_begin_respawn()


func _spawn_wave() -> void:
	var asteroid_count: int = initial_asteroid_count + maxi(0, wave - starting_wave)

	for index in asteroid_count:
		var spawn_position := _get_safe_spawn_position(index, asteroid_count)
		var velocity := _get_random_asteroid_velocity(ASTEROID_LARGE)
		_spawn_asteroid(ASTEROID_LARGE, spawn_position, velocity)


func _spawn_asteroid(size_tier: int, spawn_position: Vector2, velocity: Vector2) -> Area2D:
	var asteroid := asteroid_scene.instantiate() as Area2D
	entities.add_child(asteroid)
	asteroid.add_to_group("asteroids")
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
	if not play_active:
		return

	score += _get_score_value(size_tier)
	_update_hud()

	if size_tier < ASTEROID_SMALL:
		var next_size := size_tier + 1

		for index in split_child_count:
			var velocity := _get_split_velocity(next_size, incoming_velocity, index)
			_spawn_asteroid(next_size, hit_position, velocity)

	call_deferred("_check_wave_cleared")


func _begin_respawn() -> void:
	respawning = true
	player_ship.set_controls_enabled(false)
	player_ship.set_invulnerable(true)
	await get_tree().create_timer(respawn_delay_seconds).timeout

	if not play_active:
		return

	_respawn_player(true)


func _respawn_player(use_invulnerability_timer: bool) -> void:
	player_ship.reset_for_respawn(get_viewport_rect().get_center())
	player_ship.set_controls_enabled(true)
	player_ship.set_invulnerable(use_invulnerability_timer)
	respawning = false

	if use_invulnerability_timer:
		_end_invulnerability_after_delay()


func _end_invulnerability_after_delay() -> void:
	await get_tree().create_timer(respawn_invulnerability_seconds).timeout

	if play_active and not respawning:
		player_ship.set_invulnerable(false)


func _end_game() -> void:
	play_active = false
	respawning = false
	player_ship.set_controls_enabled(false)
	player_ship.set_invulnerable(true)
	hud.show_game_over(score, wave)


func _check_wave_cleared() -> void:
	if not play_active or _get_active_asteroid_count() > 0:
		return

	wave += 1
	_update_hud()
	_clear_bullets()
	_spawn_wave()


func _clear_dynamic_entities() -> void:
	for child in entities.get_children():
		if child != player_ship:
			child.queue_free()


func _clear_bullets() -> void:
	for bullet in get_tree().get_nodes_in_group("bullets"):
		bullet.queue_free()


func _get_active_asteroid_count() -> int:
	var count := 0

	for asteroid in get_tree().get_nodes_in_group("asteroids"):
		if is_instance_valid(asteroid) and not asteroid.is_queued_for_deletion():
			count += 1

	return count


func _update_hud() -> void:
	hud.set_score(score)
	hud.set_lives(lives)
	hud.set_wave(wave)


func _get_safe_spawn_position(index: int, asteroid_count: int) -> Vector2:
	var viewport_rect := get_viewport_rect()

	for attempt in 32:
		var spawn_position := Vector2(
			random.randf_range(viewport_rect.position.x, viewport_rect.end.x),
			random.randf_range(viewport_rect.position.y, viewport_rect.end.y)
		)

		if spawn_position.distance_to(player_ship.global_position) >= spawn_safe_radius:
			return spawn_position

	var fallback_angle := TAU * float(index) / maxf(1.0, float(asteroid_count))
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
	var wave_bonus: float = maxf(0.0, float(wave - starting_wave)) * 6.0

	match size_tier:
		ASTEROID_LARGE:
			return 45.0 + wave_bonus
		ASTEROID_MEDIUM:
			return 75.0 + wave_bonus
		_:
			return 110.0 + wave_bonus


func _get_max_speed(size_tier: int) -> float:
	var wave_bonus: float = maxf(0.0, float(wave - starting_wave)) * 8.0

	match size_tier:
		ASTEROID_LARGE:
			return 105.0 + wave_bonus
		ASTEROID_MEDIUM:
			return 145.0 + wave_bonus
		_:
			return 190.0 + wave_bonus


func _get_score_value(size_tier: int) -> int:
	match size_tier:
		ASTEROID_LARGE:
			return 20
		ASTEROID_MEDIUM:
			return 50
		_:
			return 100
