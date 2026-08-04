extends Area2D


const MATERIAL_RUNTIME := preload("res://scripts/material_runtime.gd")

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
@export var wrap_margin: float = 48.0

@onready var rock_shape: Polygon2D = $RockShape
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var velocity: Vector2 = Vector2.ZERO
var world_light_direction: Vector2 = Vector2(-0.55, -0.83).normalized()
var rock_material: ShaderMaterial


func _ready() -> void:
	_apply_visual_asset()
	_apply_size_tier()
	_update_shader_light_direction()


func _physics_process(delta: float) -> void:
	position += velocity * delta
	rotation += deg_to_rad(rotation_speed_degrees) * delta
	_wrap_to_visible_viewport()
	_update_shader_light_direction()


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


func _get_collision_radius() -> float:
	match size_tier:
		AsteroidSize.LARGE:
			return 44.0
		AsteroidSize.MEDIUM:
			return 28.0
		_:
			return 16.0


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


func _wrap_to_visible_viewport() -> void:
	var viewport_rect := get_viewport_rect()
	var min_position := viewport_rect.position - Vector2.ONE * wrap_margin
	var max_position := viewport_rect.position + viewport_rect.size + Vector2.ONE * wrap_margin

	if position.x < min_position.x:
		position.x = max_position.x
	elif position.x > max_position.x:
		position.x = min_position.x

	if position.y < min_position.y:
		position.y = max_position.y
	elif position.y > max_position.y:
		position.y = min_position.y


func _update_shader_light_direction() -> void:
	MATERIAL_RUNTIME.set_world_light_direction(rock_material, self, world_light_direction)
