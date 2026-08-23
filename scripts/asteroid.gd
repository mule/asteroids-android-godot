extends Area2D


const MATERIAL_RUNTIME := preload("res://scripts/material_runtime.gd")
const WORLD_BOUNDS := preload("res://scripts/world/world_bounds.gd")

signal destroyed(asteroid: Area2D, size_tier: int, hit_position: Vector2, incoming_velocity: Vector2)

enum AsteroidSize {
	LARGE,
	MEDIUM,
	SMALL,
}

@export var visual_asset: Resource = preload("res://assets/generated/asteroids/asteroid_baseline_01.tres")
@export var shader_lighting_enabled: bool = true
@export_enum("Large", "Medium", "Small") var size_tier: int = AsteroidSize.LARGE
@export var drift_speed: float = 90.0
@export var rotation_speed_degrees: float = 25.0
@export var bounce_restitution: float = 1.0
## Extra gap left between this rock and a body it has been deflected off,
## so a rounding error cannot leave the pair technically still touching.
@export var deflect_clearance: float = 6.0

@onready var rock_shape: Polygon2D = $RockShape
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var velocity: Vector2 = Vector2.ZERO
var world_light_direction: Vector2 = Vector2(-0.55, -0.83).normalized()
var rock_material: ShaderMaterial
var sector_bounds: Rect2 = Rect2()


func _ready() -> void:
	_apply_visual_asset()
	_apply_size_tier()
	_update_shader_light_direction()
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	_limit_velocity_for_discrete_collision(delta)
	position += velocity * delta
	rotation += deg_to_rad(rotation_speed_degrees) * delta
	_contain_in_sector()
	_update_shader_light_direction()
	_resolve_asteroid_overlaps()


func _limit_velocity_for_discrete_collision(delta: float) -> void:
	if delta <= 0.0:
		return

	# Each asteroid may travel at most its own radius per physics tick. For any
	# pair, their combined relative travel is therefore no greater than their
	# combined radii, so they cannot cross completely between overlap snapshots.
	var max_safe_speed := get_collision_radius() / delta
	velocity = velocity.limit_length(max_safe_speed)


func setup(tier: int, initial_velocity: Vector2, selected_visual_asset: Resource = null, initial_rotation: float = 0.0) -> void:
	size_tier = tier
	velocity = initial_velocity
	rotation = initial_rotation

	if _is_valid_visual_asset(selected_visual_asset):
		visual_asset = selected_visual_asset

	if is_node_ready():
		_apply_visual_asset()
		_apply_size_tier()


func get_next_size_tier() -> int:
	return size_tier + 1


func can_split() -> bool:
	return size_tier < AsteroidSize.SMALL


func handle_bullet_hit(bullet: Area2D) -> void:
	destroyed.emit(self, size_tier, global_position, velocity)
	queue_free()


func set_shader_lighting_enabled(value: bool) -> void:
	shader_lighting_enabled = value
	MATERIAL_RUNTIME.set_lighting_enabled(rock_material, value)


func set_world_light_direction(value: Vector2) -> void:
	world_light_direction = value.normalized()
	_update_shader_light_direction()


func _apply_size_tier() -> void:
	rock_shape.scale = Vector2.ONE * _get_visual_scale()

	if collision_shape.shape is CircleShape2D:
		var circle_shape := collision_shape.shape.duplicate() as CircleShape2D
		circle_shape.radius = _get_collision_radius()
		collision_shape.shape = circle_shape


func _apply_visual_asset() -> void:
	if not _is_valid_visual_asset(visual_asset):
		return

	rock_shape.polygon = visual_asset.primary_polygon
	rock_shape.color = visual_asset.fill_color
	rock_material = MATERIAL_RUNTIME.apply_material_definition(rock_shape, visual_asset.material_definition)
	set_shader_lighting_enabled(shader_lighting_enabled)
	_update_shader_light_direction()


func _get_visual_scale() -> float:
	match size_tier:
		AsteroidSize.LARGE:
			return 1.0
		AsteroidSize.MEDIUM:
			return 0.62
		_:
			return 0.36


func get_collision_radius() -> float:
	match size_tier:
		AsteroidSize.LARGE:
			return 44.0
		AsteroidSize.MEDIUM:
			return 28.0
		_:
			return 16.0


func _get_collision_radius() -> float:
	return get_collision_radius()


func get_mass() -> float:
	match size_tier:
		AsteroidSize.LARGE:
			return 4.0
		AsteroidSize.MEDIUM:
			return 2.0
		_:
			return 1.0


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("asteroids") and is_instance_valid(area) and not area.is_queued_for_deletion():
		if get_instance_id() < area.get_instance_id():
			_resolve_asteroid_collision(area)


func _resolve_asteroid_overlaps() -> void:
	for area in get_overlapping_areas():
		if area.is_in_group("asteroids") and is_instance_valid(area) and not area.is_queued_for_deletion():
			if get_instance_id() < area.get_instance_id():
				_resolve_asteroid_collision(area)


func _resolve_asteroid_collision(other: Area2D) -> void:
	if not is_instance_valid(other) or other.is_queued_for_deletion():
		return

	var radius_a := get_collision_radius()
	var radius_b: float = other.get_collision_radius() if other.has_method("get_collision_radius") else 28.0
	var min_distance := radius_a + radius_b

	var delta_pos := global_position - other.global_position
	var current_distance := delta_pos.length()

	if current_distance >= min_distance:
		return

	var normal: Vector2
	if current_distance < 0.001:
		var other_vel: Vector2 = other.get("velocity") if other.get("velocity") != null else Vector2.ZERO
		var rel_vel := velocity - other_vel
		if rel_vel.length_squared() > 0.01:
			normal = -rel_vel.normalized()
		else:
			normal = Vector2.RIGHT.rotated(randf() * TAU)
	else:
		normal = delta_pos / current_distance

	var overlap := min_distance - current_distance

	var mass_a := get_mass()
	var mass_b: float = other.get_mass() if other.has_method("get_mass") else 2.0
	var total_mass := mass_a + mass_b

	# Separate positions proportionally to inverse mass to prevent sticking and tunneling
	var separation_a := normal * (overlap * (mass_b / total_mass))
	var separation_b := normal * (overlap * (mass_a / total_mass))
	global_position += separation_a
	other.global_position -= separation_b

	# Calculate velocity response (elastic bounce)
	var vel_b: Vector2 = other.get("velocity") if other.get("velocity") != null else Vector2.ZERO
	var rel_velocity := velocity - vel_b
	var vel_along_normal := rel_velocity.dot(normal)

	# Only apply impulse if objects are moving towards each other
	if vel_along_normal < 0.0:
		var impulse_scalar := -(1.0 + bounce_restitution) * vel_along_normal / ((1.0 / mass_a) + (1.0 / mass_b))
		var impulse := normal * impulse_scalar
		velocity += impulse / mass_a
		if "velocity" in other:
			other.velocity -= impulse / mass_b

	# Contain after the impulse, not before it. Separation can shove either rock
	# through a wall, and _contain_in_sector reflects velocity as well as
	# clamping position -- run first, its reflection is simply overwritten by an
	# impulse that can point straight back out, leaving a rock clamped on the
	# wall taking a fresh impulse every frame until the sign happens to flip.
	_contain_in_sector()
	if other.has_method("_contain_in_sector"):
		other._contain_in_sector()


## Push this rock clear of a body it just struck and send it back outward.
##
## Contact with the ship has to *end*, not merely stop being counted. The
## post-damage window is a timer: when it closes, `monitoring` comes back on,
## Godot re-evaluates a pair that is still overlapping, and the hull is charged
## again -- every window, for as long as a slow rock sits on the ship. This is
## the same separate-then-impulse rule `_resolve_asteroid_collision` already
## applies to rock-on-rock contact, with the struck body treated as immovable:
## the ship keeps its own momentum and the rock takes the whole response.
func deflect_from(origin: Vector2, origin_radius: float, separation_speed: float) -> void:
	var clearance := origin_radius + get_collision_radius() + deflect_clearance
	var normal := _get_deflect_normal(origin)
	var target := _get_contained_position(origin + normal * clearance)

	# The sector wall outranks the deflection: containment clamps a rock shoved
	# past the edge straight back onto the ship, and a ship pinned against that
	# edge is exactly the one with no room to dodge. When the wall is in the
	# way, throw the rock towards open space instead of into it.
	if target.distance_to(origin) < clearance:
		var open_space := _get_sector_bounds().get_center() - origin
		if open_space.length_squared() > 0.01:
			normal = open_space.normalized()
			target = _get_contained_position(origin + normal * clearance)

	global_position = target

	# Set the outward speed rather than adding to it, so a rock closing at any
	# speed leaves at the same one. A rock already leaving faster keeps its own.
	var outward_speed := velocity.dot(normal)
	if outward_speed < separation_speed:
		velocity += normal * (separation_speed - outward_speed)

	_contain_in_sector()


func _get_deflect_normal(origin: Vector2) -> Vector2:
	var away := global_position - origin
	var distance := away.length()

	if distance > 0.001:
		return away / distance

	# Dead centre on the struck body leaves no direction to separate along. Back
	# the rock out the way it came; a rock that is not moving has to pick some
	# direction, and its own facing is at least reproducible from the seed --
	# `_resolve_asteroid_collision`'s randf() would make a hit untestable.
	if velocity.length_squared() > 0.01:
		return -velocity.normalized()

	return Vector2.RIGHT.rotated(rotation)


func _get_contained_position(candidate: Vector2) -> Vector2:
	return WORLD_BOUNDS.clamp_to_sector(candidate, _get_sector_bounds(), get_collision_radius())


func get_visual_asset_id() -> StringName:
	if visual_asset != null:
		return visual_asset.asset_id
	return &""


func _is_valid_visual_asset(candidate: Resource) -> bool:
	return (
		candidate != null
		and candidate.has_method("is_primary_polygon_valid")
		and candidate.is_primary_polygon_valid()
	)


func set_sector_bounds(bounds: Rect2) -> void:
	sector_bounds = bounds


func _get_sector_bounds() -> Rect2:
	if sector_bounds.size.x > 0.0 and sector_bounds.size.y > 0.0:
		return sector_bounds

	return get_viewport_rect()


func _contain_in_sector() -> void:
	var bounds := _get_sector_bounds()
	var radius := get_collision_radius()
	# Sector bounds are world space, so containment reads and writes
	# global_position. An asteroid seeded by an AsteroidField is parented to
	# that field, not to Entities, so its own `position` is an offset from the
	# field centre -- clamping that against a world rect walls every field rock
	# in at its own field's origin.
	var world_position := global_position
	velocity = WORLD_BOUNDS.reflect_velocity_at_edge(world_position, velocity, bounds, radius)
	global_position = WORLD_BOUNDS.clamp_to_sector(world_position, bounds, radius)


func _update_shader_light_direction() -> void:
	MATERIAL_RUNTIME.set_world_light_direction(rock_material, self, world_light_direction)
