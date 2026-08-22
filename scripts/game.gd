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
@export var world_light_direction: Vector2 = Vector2(-0.55, -0.83)
@export var shader_lighting_enabled: bool = true
@export var asteroid_visual_assets: Array[Resource] = []
@export var auto_start: bool = true

@onready var entities: Node2D = $Entities
@onready var player_ship: Area2D = $Entities/PlayerShip
@onready var sector: Sector = $Sector
@onready var follow_camera: Camera2D = $FollowCamera
@onready var stars_far: Node2D = $StarsFar/Layer
@onready var stars_mid: Node2D = $StarsMid/Layer
@onready var player_input: Node = $PlayerInput
@onready var feedback: Node = $Feedback
@onready var hud: CanvasLayer = $Hud

var random := RandomNumberGenerator.new()
var score: int = 0
var lives: int = 0
var wave: int = 0
var play_active: bool = false
var paused: bool = false
var respawning: bool = false


func _ready() -> void:
	random.seed = random_seed
	world_light_direction = world_light_direction.normalized()
	player_ship.shoot_requested.connect(_on_player_ship_shoot_requested)
	player_ship.area_entered.connect(_on_player_ship_area_entered)
	player_ship.boundary_warning_changed.connect(hud.set_boundary_warning)
	hud.pause_requested.connect(_pause_game)
	hud.resume_requested.connect(_resume_game)
	hud.restart_requested.connect(_start_new_game)
	hud.touch_action_changed.connect(_on_hud_touch_action_changed)
	# The sector is at least viewport-sized, so a resize changes where the world
	# ends. Entities are handed their bounds once at spawn and the camera its
	# limits once here, so without this they would keep using the size the
	# window had when they were created.
	get_viewport().size_changed.connect(_apply_sector_bounds)
	_apply_lighting_to_entity(player_ship)
	_apply_sector_bounds()
	follow_camera.set_target(player_ship)
	_build_star_layers()
	if auto_start:
		_start_new_game()


func _unhandled_input(event: InputEvent) -> void:
	if play_active and event.is_action_pressed("pause"):
		if paused:
			_resume_game()
		else:
			_pause_game()

	if not play_active and event.is_action_pressed("restart"):
		_start_new_game()

	if event.is_action_pressed("toggle_shader_lighting"):
		_toggle_shader_lighting()


func _start_new_game() -> void:
	_clear_dynamic_entities()
	feedback.clear_effects()
	score = starting_score
	lives = starting_lives
	wave = starting_wave
	play_active = true
	paused = false
	respawning = false
	get_tree().paused = false
	hud.hide_status()
	hud.set_pause_available(true)
	_update_hud()
	_respawn_player(false)
	_spawn_wave()
	feedback.spawn_wave_flash()


func _on_player_ship_shoot_requested(
	muzzle_position: Vector2,
	direction: Vector2,
	inherited_velocity: Vector2
) -> void:
	if not play_active or paused or respawning:
		return

	var bullet := bullet_scene.instantiate()
	entities.add_child(bullet)
	bullet.add_to_group("bullets")
	bullet.global_position = muzzle_position
	_apply_lighting_to_entity(bullet)

	if bullet.has_method("launch"):
		bullet.launch(direction, inherited_velocity)

	feedback.spawn_muzzle_flash(muzzle_position, direction)


func _on_player_ship_area_entered(area: Area2D) -> void:
	if not play_active or paused or respawning or not area.is_in_group("asteroids"):
		return

	lives = max(0, lives - 1)
	feedback.spawn_player_hit(player_ship.global_position)
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
	var visual_asset := _get_random_asteroid_visual_asset()
	var initial_rotation := random.randf_range(0.0, TAU)

	if asteroid.has_method("setup"):
		asteroid.setup(size_tier, velocity, visual_asset, initial_rotation)

	entities.add_child(asteroid)
	asteroid.add_to_group("asteroids")
	asteroid.global_position = spawn_position
	_apply_lighting_to_entity(asteroid)

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
	feedback.spawn_asteroid_burst(hit_position, size_tier)
	_update_hud()

	if size_tier < ASTEROID_SMALL:
		var next_size := size_tier + 1
		call_deferred("_spawn_split_asteroids", next_size, hit_position, incoming_velocity)

	call_deferred("_check_wave_cleared")


func _spawn_split_asteroids(size_tier: int, hit_position: Vector2, incoming_velocity: Vector2) -> void:
	if not play_active:
		return

	for index in split_child_count:
		var velocity := _get_split_velocity(size_tier, incoming_velocity, index)
		_spawn_asteroid(size_tier, hit_position, velocity)


func _begin_respawn() -> void:
	respawning = true
	player_ship.set_controls_enabled(false)
	player_ship.set_invulnerable(true)
	await get_tree().create_timer(respawn_delay_seconds).timeout

	if not play_active:
		return

	_respawn_player(true)


func _respawn_player(use_invulnerability_timer: bool) -> void:
	player_ship.reset_for_respawn(sector.get_center())
	player_ship.set_controls_enabled(true)
	player_ship.set_invulnerable(use_invulnerability_timer)
	follow_camera.set_target(player_ship)
	feedback.spawn_respawn_ring(player_ship.global_position)
	respawning = false

	if use_invulnerability_timer:
		_end_invulnerability_after_delay()


func _end_invulnerability_after_delay() -> void:
	await get_tree().create_timer(respawn_invulnerability_seconds).timeout

	if play_active and not respawning:
		player_ship.set_invulnerable(false)


func _end_game() -> void:
	get_tree().paused = false
	play_active = false
	paused = false
	respawning = false
	player_ship.set_controls_enabled(false)
	player_ship.set_invulnerable(true)
	hud.show_game_over(score, wave)


func _check_wave_cleared() -> void:
	if not play_active or paused or _get_active_asteroid_count() > 0:
		return

	wave += 1
	_update_hud()
	_clear_bullets()
	_spawn_wave()
	feedback.spawn_wave_flash()


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


func _pause_game() -> void:
	if not play_active or paused:
		return

	paused = true
	player_input.clear_touch_actions()
	get_tree().paused = true
	hud.show_paused()


func _resume_game() -> void:
	if not play_active or not paused:
		return

	paused = false
	get_tree().paused = false
	hud.hide_status()


func _toggle_shader_lighting() -> void:
	shader_lighting_enabled = not shader_lighting_enabled
	_apply_lighting_to_entities()


func _apply_lighting_to_entities() -> void:
	for entity in entities.get_children():
		_apply_lighting_to_entity(entity)


func _apply_lighting_to_entity(entity: Node) -> void:
	if entity == null:
		return

	if entity.has_method("set_world_light_direction"):
		entity.set_world_light_direction(world_light_direction)

	if entity.has_method("set_shader_lighting_enabled"):
		entity.set_shader_lighting_enabled(shader_lighting_enabled)

	_apply_sector_bounds_to_entity(entity)


## Push the current sector extent to everything that draws a box from it. The
## camera's limits and the entities' sector boxes come from the same authority
## and have to move together: Sector.get_bounds() never reports smaller than
## the visible rect, so a window resize can move where the world ends, and a
## camera left on its startup limits would show past the sector edge.
func _apply_sector_bounds() -> void:
	follow_camera.apply_sector_limits(sector.get_bounds())
	_apply_sector_bounds_to_entities()


func _apply_sector_bounds_to_entities() -> void:
	for entity in entities.get_children():
		_apply_sector_bounds_to_entity(entity)


func _apply_sector_bounds_to_entity(entity: Node) -> void:
	if entity == null:
		return

	if entity.has_method("set_sector_bounds"):
		entity.set_sector_bounds(sector.get_bounds())

	if entity.has_method("set_boundary_margin"):
		entity.set_boundary_margin(sector.get_boundary_margin())


func _build_star_layers() -> void:
	var bounds := sector.get_bounds()
	var sector_seed := random_seed

	if sector.definition != null and "sector_seed" in sector.definition:
		sector_seed = sector.definition.sector_seed

	stars_far.build_stars(bounds, sector_seed + stars_far.layer_seed)
	stars_mid.build_stars(bounds, sector_seed + stars_mid.layer_seed)


func _on_hud_touch_action_changed(action: StringName, pressed: bool) -> void:
	player_input.set_touch_action(action, pressed)


func _get_safe_spawn_position(index: int, asteroid_count: int) -> Vector2:
	for attempt in 32:
		var spawn_position := sector.get_random_position(random)

		if spawn_position.distance_to(player_ship.global_position) >= spawn_safe_radius:
			return spawn_position

	var fallback_angle := TAU * float(index) / maxf(1.0, float(asteroid_count))
	var fallback_radius := spawn_safe_radius + 80.0
	return player_ship.global_position + Vector2.RIGHT.rotated(fallback_angle) * fallback_radius


func _get_random_asteroid_velocity(size_tier: int) -> Vector2:
	var angle := random.randf_range(0.0, TAU)
	var speed := random.randf_range(_get_min_speed(size_tier), _get_max_speed(size_tier))
	return Vector2.RIGHT.rotated(angle) * speed


func _get_random_asteroid_visual_asset() -> Resource:
	var valid_assets := _get_valid_asteroid_visual_assets()
	if valid_assets.is_empty():
		return null
	return valid_assets[random.randi_range(0, valid_assets.size() - 1)]


func _get_valid_asteroid_visual_assets() -> Array[Resource]:
	var valid_assets: Array[Resource] = []
	for asset: Resource in asteroid_visual_assets:
		if (
			asset != null
			and asset.has_method("is_primary_polygon_valid")
			and asset.is_primary_polygon_valid()
		):
			valid_assets.append(asset)
	return valid_assets


func get_active_asteroid_debug_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for asteroid in get_tree().get_nodes_in_group("asteroids"):
		if not is_instance_valid(asteroid) or asteroid.is_queued_for_deletion():
			continue

		var visual_asset_id := StringName()
		if asteroid.has_method("get_visual_asset_id"):
			visual_asset_id = asteroid.get_visual_asset_id()

		snapshot.append({
			"position": asteroid.global_position,
			"velocity": asteroid.get("velocity"),
			"size_tier": asteroid.get("size_tier"),
			"visual_asset_id": visual_asset_id,
			"rotation": asteroid.rotation,
		})

	snapshot.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a["position"].x, b["position"].x):
			return a["position"].x < b["position"].x
		return a["position"].y < b["position"].y
	)
	return snapshot


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
