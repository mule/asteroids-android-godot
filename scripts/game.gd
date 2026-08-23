extends Node2D


const ASTEROID_LARGE := 0
const ASTEROID_MEDIUM := 1
const ASTEROID_SMALL := 2

@export var asteroid_scene: PackedScene
@export var bullet_scene: PackedScene
@export var starting_score: int = 0
@export var starting_wave: int = 1
@export var split_child_count: int = 2
@export var asteroid_collision_damage: float = 25.0
## Brief post-damage immunity. Inherited from the deleted respawn cycle so a
## single collision cannot chain into instant destruction: an asteroid resting
## on the ship would otherwise land a hit every physics frame.
@export var damage_invulnerability_seconds: float = 2.0
## Outward speed given to an asteroid that has just damaged the ship. The
## window above only stops the hit being counted; this is what stops the pair
## touching, so it has to clear the ship's radius well inside one window.
@export var asteroid_deflect_speed: float = 140.0
## Fuel returned for clearing one asteroid field -- a quarter tank, 6.25 seconds
## of thrust, deliberately less than crossing the sector to the next field costs.
##
## Interim measure until the stations of #54, which are meant to be the primary
## refuel and must not be made pointless here. Nothing else in the game refuels:
## a 100-unit tank at 4/s is 25 seconds of thrust for an entire run, after which
## the rest of the sector is flown at quarter acceleration with no counterplay.
## This tops the tank up on a beat the player already earns. It rode the wave
## loop until #48 deleted that loop; it now rides the field-clear signal, which
## #57's threat director supersedes -- so it still cannot outlive the gap it
## fills.
## It refuels only: hull repair stays a station service, so damage still costs.
@export var field_clear_refuel: float = 25.0
@export var random_seed: int = 1729
@export var world_light_direction: Vector2 = Vector2(-0.55, -0.83)
@export var shader_lighting_enabled: bool = true
@export var asteroid_visual_assets: Array[Resource] = []
@export var auto_start: bool = true

@onready var entities: Node2D = $Entities
@onready var player_ship: Area2D = $Entities/PlayerShip
@onready var ship_systems: ShipSystems = $Entities/PlayerShip/ShipSystems
@onready var sector: Sector = $Sector
@onready var follow_camera: Camera2D = $FollowCamera
@onready var stars_far: StarLayer = $StarsFar/Layer
@onready var stars_mid: StarLayer = $StarsMid/Layer
@onready var player_input: Node = $PlayerInput
@onready var feedback: Node = $Feedback
@onready var hud: CanvasLayer = $Hud

var random := RandomNumberGenerator.new()
var score: int = 0
var wave: int = 0
var play_active: bool = false
var paused: bool = false
var invulnerability_token: int = 0


func _ready() -> void:
	random.seed = random_seed
	world_light_direction = world_light_direction.normalized()
	player_ship.shoot_requested.connect(_on_player_ship_shoot_requested)
	player_ship.area_entered.connect(_on_player_ship_area_entered)
	player_ship.boundary_warning_changed.connect(hud.set_boundary_warning)
	ship_systems.hull_changed.connect(hud.set_hull)
	ship_systems.fuel_changed.connect(hud.set_fuel)
	ship_systems.credits_changed.connect(hud.set_credits)
	ship_systems.reserve_thrust_changed.connect(hud.set_reserve_thrust)
	ship_systems.destroyed.connect(_end_game)
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
	wave = starting_wave
	play_active = true
	paused = false
	get_tree().paused = false
	ship_systems.reset_systems()
	hud.hide_status()
	hud.set_pause_available(true)
	_update_hud()
	_spawn_player()
	_place_sector_content()
	feedback.spawn_wave_flash()


func _on_player_ship_shoot_requested(
	muzzle_position: Vector2,
	direction: Vector2,
	inherited_velocity: Vector2
) -> void:
	if not play_active or paused:
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
	if not play_active or paused or not area.is_in_group("asteroids"):
		return

	# Asked of the ship's own flag, not its `monitoring` state: set_invulnerable
	# can only switch overlap detection off deferred, so every asteroid that
	# began overlapping during this same physics step still reports in after
	# the window opened. Without this check the window does not cover the frame
	# that opened it, and a ship flying into a cluster is charged one full hit
	# per asteroid at once -- the chaining damage_invulnerability_seconds
	# exists to prevent. This is what the deleted `respawning` flag used to do.
	if player_ship.is_invulnerable():
		return

	feedback.spawn_player_hit(player_ship.global_position)
	# The hull is the authority on whether the run continues: apply_damage
	# emits `destroyed` once at zero, and _end_game is connected to it.
	ship_systems.apply_damage(asteroid_collision_damage)
	_deflect_asteroid_from_player(area)

	if ship_systems.is_destroyed():
		return

	_begin_damage_invulnerability()


## A damaging hit has to leave the two apart. Nothing else does this any more:
## the lives model's `_respawn_player` used to move the ship away on every hit,
## and deleting it left the collision unresolved. The window that replaced it is
## only a timer -- `set_invulnerable(false)` switches `monitoring` back on, Godot
## re-reports a pair that never stopped overlapping, and a rock resting on the
## ship bills 25 hull every window until the run is over. A player who has run
## the tank dry, on quarter acceleration, cannot fly out from under it.
func _deflect_asteroid_from_player(asteroid: Area2D) -> void:
	if not is_instance_valid(asteroid) or not asteroid.has_method("deflect_from"):
		return

	asteroid.deflect_from(
		player_ship.global_position,
		player_ship.get_collision_radius(),
		asteroid_deflect_speed
	)


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
	ship_systems.add_credits(_get_credit_value(size_tier))
	feedback.spawn_asteroid_burst(hit_position, size_tier)
	_update_hud()

	if size_tier < ASTEROID_SMALL:
		var next_size := size_tier + 1
		call_deferred("_spawn_split_asteroids", next_size, hit_position, incoming_velocity)

	call_deferred("_check_asteroid_fields_cleared")


func _spawn_split_asteroids(size_tier: int, hit_position: Vector2, incoming_velocity: Vector2) -> void:
	if not play_active:
		return

	for index in split_child_count:
		var velocity := _get_split_velocity(size_tier, incoming_velocity, index)
		_spawn_asteroid(size_tier, hit_position, velocity)


## The ship is placed once per run. There is no respawn: damage accumulates on
## the hull and the run ends when it is gone.
func _spawn_player() -> void:
	player_ship.reset_for_respawn(sector.get_center())
	player_ship.set_controls_enabled(true)
	player_ship.set_invulnerable(false)
	follow_camera.set_target(player_ship)
	feedback.spawn_respawn_ring(player_ship.global_position)


## Each window carries a token so a timer left running by an abandoned run --
## restart the game mid-window and the old timeout still arrives -- cannot cut
## the current window short.
func _begin_damage_invulnerability() -> void:
	invulnerability_token += 1
	var token := invulnerability_token
	player_ship.set_invulnerable(true)
	await get_tree().create_timer(damage_invulnerability_seconds).timeout

	if play_active and token == invulnerability_token:
		player_ship.set_invulnerable(false)


func _end_game() -> void:
	get_tree().paused = false
	play_active = false
	paused = false
	player_ship.set_controls_enabled(false)
	player_ship.set_invulnerable(true)
	hud.show_game_over(score, wave)


func _check_asteroid_fields_cleared() -> void:
	if not play_active or paused or _get_active_asteroid_count() > 0:
		return

	_clear_bullets()
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
	hud.set_wave(wave)
	hud.set_sector(sector.get_sector_name("unknown"), sector.get_seed(random_seed))


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

	for field in sector.get_fields():
		for asteroid in field.get_children():
			_apply_lighting_to_entity(asteroid)


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

	for field in sector.get_fields():
		for asteroid in field.get_children():
			_apply_sector_bounds_to_entity(asteroid)


func _apply_sector_bounds_to_entity(entity: Node) -> void:
	if entity == null:
		return

	if entity.has_method("set_sector_bounds"):
		entity.set_sector_bounds(sector.get_bounds())

	if entity.has_method("set_boundary_margin"):
		entity.set_boundary_margin(sector.get_boundary_margin())


func _build_star_layers() -> void:
	var bounds := sector.get_bounds()
	var sector_seed := sector.get_seed(random_seed)

	_build_star_layer(stars_far, bounds, sector_seed)
	_build_star_layer(stars_mid, bounds, sector_seed)


## Each layer is scattered over the band its own scroll_scale can bring on
## screen rather than over the whole sector -- see StarLayer.parallax_span().
## The sector still decides how big the world is; the viewport is asked only
## how big the screen is, which is the same split Sector.get_bounds() uses.
func _build_star_layer(layer: StarLayer, bounds: Rect2, sector_seed: int) -> void:
	var parallax := layer.get_parent() as Parallax2D
	var scroll_scale := Vector2.ONE if parallax == null else parallax.scroll_scale
	var span := StarLayer.parallax_span(bounds, scroll_scale, get_viewport_rect().size)
	layer.build_stars(span, sector_seed + layer.layer_seed)


func _place_sector_content() -> void:
	random.seed = sector.get_seed(random_seed)
	sector.place_content(random)

	for field in sector.get_fields():
		if field.has_signal("field_cleared"):
			field.connect("field_cleared", _on_asteroid_field_cleared)
		if field.has_method("seed_field"):
			field.seed_field(random, asteroid_scene, asteroid_visual_assets)
		_wire_field_asteroids(field)


func _wire_field_asteroids(field: Node2D) -> void:
	for child in field.get_children():
		if not child is Area2D or not child.is_in_group("asteroids"):
			continue

		var asteroid := child as Area2D
		_apply_lighting_to_entity(asteroid)

		if asteroid.has_signal("destroyed"):
			var callback := Callable(self, "_on_asteroid_destroyed")
			if not asteroid.is_connected("destroyed", callback):
				asteroid.connect("destroyed", callback)


func _on_asteroid_field_cleared(field: Node2D) -> void:
	# Partial, on a beat the player earns. See `field_clear_refuel`.
	ship_systems.refuel(field_clear_refuel)
	call_deferred("_check_asteroid_fields_cleared")


func _on_hud_touch_action_changed(action: StringName, pressed: bool) -> void:
	player_input.set_touch_action(action, pressed)


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


## Credits are the spendable currency #54 charges for repair and refuel, so
## they are deliberately a much smaller number than the raw arcade score.
func _get_credit_value(size_tier: int) -> int:
	match size_tier:
		ASTEROID_LARGE:
			return 4
		ASTEROID_MEDIUM:
			return 7
		_:
			return 12
