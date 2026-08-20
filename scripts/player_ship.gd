extends Area2D


const MATERIAL_RUNTIME := preload("res://scripts/material_runtime.gd")
const WORLD_BOUNDS := preload("res://scripts/world/world_bounds.gd")

signal shoot_requested(muzzle_position: Vector2, direction: Vector2, inherited_velocity: Vector2)

@export var visual_asset: Resource = preload("res://assets/generated/ships/ship_delta_01.tres")
@export var shader_lighting_enabled: bool = true
@export var acceleration: float = 360.0
@export var max_speed: float = 520.0
@export var turn_speed_degrees: float = 180.0
@export var linear_drag: float = 12.0
@export var wrap_margin: float = 32.0
@export var fire_cooldown_seconds: float = 0.18
@export var muzzle_distance: float = 34.0
@export var input_source_path: NodePath = ^"../../PlayerInput"

@onready var ship_shape: Polygon2D = $ShipShape
@onready var thrust_flame: Polygon2D = $ThrustFlame
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var input_source: Node = get_node_or_null(input_source_path)

var velocity: Vector2 = Vector2.ZERO
var fire_cooldown_remaining: float = 0.0
var controls_enabled: bool = true
var invulnerable: bool = false
var world_light_direction: Vector2 = Vector2(-0.55, -0.83).normalized()
var ship_material: ShaderMaterial
var thrust_material: ShaderMaterial
var sector_bounds: Rect2 = Rect2()


func _ready() -> void:
	_apply_visual_asset()
	_update_shader_light_direction()


func _physics_process(delta: float) -> void:
	if not controls_enabled:
		return

	_update_fire_cooldown(delta)
	_apply_rotation_input(delta)
	_apply_thrust_input(delta)
	_apply_shoot_input()
	_apply_drift(delta)
	_move(delta)
	_wrap_to_visible_viewport()
	_update_shader_light_direction()


func _apply_rotation_input(delta: float) -> void:
	var turn_input := _get_turn_axis()
	rotation += deg_to_rad(turn_speed_degrees) * turn_input * delta


func _apply_thrust_input(delta: float) -> void:
	var is_thrusting := _is_thrust_pressed()
	thrust_flame.visible = is_thrusting

	if is_thrusting:
		velocity += Vector2.UP.rotated(rotation) * acceleration * delta
		velocity = velocity.limit_length(max_speed)


func _apply_shoot_input() -> void:
	if not _is_shoot_pressed() or fire_cooldown_remaining > 0.0:
		return

	var direction := Vector2.UP.rotated(global_rotation)
	var muzzle_position := global_position + direction * muzzle_distance
	shoot_requested.emit(muzzle_position, direction, velocity)
	fire_cooldown_remaining = fire_cooldown_seconds


func _update_fire_cooldown(delta: float) -> void:
	fire_cooldown_remaining = maxf(0.0, fire_cooldown_remaining - delta)


func _get_turn_axis() -> float:
	if input_source != null and input_source.has_method("get_turn_axis"):
		return input_source.get_turn_axis()

	return Input.get_axis("rotate_left", "rotate_right")


func _is_thrust_pressed() -> bool:
	if input_source != null and input_source.has_method("is_thrust_pressed"):
		return input_source.is_thrust_pressed()

	return Input.is_action_pressed("thrust")


func _is_shoot_pressed() -> bool:
	if input_source != null and input_source.has_method("is_shoot_pressed"):
		return input_source.is_shoot_pressed()

	return Input.is_action_pressed("shoot")


func _apply_drift(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, linear_drag * delta)


func _move(delta: float) -> void:
	position += velocity * delta


func set_sector_bounds(bounds: Rect2) -> void:
	sector_bounds = bounds


func _get_sector_bounds() -> Rect2:
	if sector_bounds.size.x > 0.0 and sector_bounds.size.y > 0.0:
		return sector_bounds

	return get_viewport_rect()


func _wrap_to_visible_viewport() -> void:
	position = WORLD_BOUNDS.wrap_to_bounds(position, _get_sector_bounds(), wrap_margin)


func reset_for_respawn(spawn_position: Vector2) -> void:
	global_position = spawn_position
	rotation = 0.0
	velocity = Vector2.ZERO
	fire_cooldown_remaining = 0.0
	thrust_flame.visible = false


func set_controls_enabled(value: bool) -> void:
	controls_enabled = value
	thrust_flame.visible = false


func set_invulnerable(value: bool) -> void:
	invulnerable = value
	set_deferred("monitoring", not value)
	set_deferred("monitorable", not value)
	modulate = Color(1.0, 1.0, 1.0, 0.45) if value else Color.WHITE


func set_shader_lighting_enabled(value: bool) -> void:
	shader_lighting_enabled = value
	MATERIAL_RUNTIME.set_lighting_enabled(ship_material, value)
	MATERIAL_RUNTIME.set_lighting_enabled(thrust_material, value)


func set_world_light_direction(value: Vector2) -> void:
	world_light_direction = value.normalized()
	_update_shader_light_direction()


func _apply_visual_asset() -> void:
	if (
		visual_asset == null
		or not visual_asset.has_method("is_primary_polygon_valid")
		or not visual_asset.is_primary_polygon_valid()
	):
		return

	ship_shape.polygon = visual_asset.primary_polygon
	ship_shape.color = visual_asset.fill_color
	ship_material = MATERIAL_RUNTIME.apply_material_definition(ship_shape, visual_asset.material_definition)

	var flame_asset: Resource = visual_asset.get_secondary_polygon(&"thrust_flame")
	if flame_asset != null and flame_asset.is_valid():
		thrust_flame.polygon = flame_asset.polygon
		thrust_flame.color = flame_asset.fill_color
		thrust_material = MATERIAL_RUNTIME.apply_material_definition(
			thrust_flame,
			flame_asset.get("material_definition")
		)
		thrust_flame.visible = flame_asset.visible_by_default

	if visual_asset.use_collision_polygon and visual_asset.collision_polygon.size() >= 3:
		var ship_collision := ConvexPolygonShape2D.new()
		ship_collision.points = visual_asset.collision_polygon
		collision_shape.shape = ship_collision

	set_shader_lighting_enabled(shader_lighting_enabled)
	_update_shader_light_direction()


func _update_shader_light_direction() -> void:
	MATERIAL_RUNTIME.set_world_light_direction(ship_material, self, world_light_direction)
