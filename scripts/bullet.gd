extends Area2D


const MATERIAL_RUNTIME := preload("res://scripts/material_runtime.gd")

@export var visual_asset: Resource = preload("res://assets/generated/bullets/bullet_baseline_01.tres")
@export var shader_lighting_enabled: bool = true
@export var speed: float = 760.0
@export var lifetime_seconds: float = 1.2
@export var wrap_margin: float = 8.0

@onready var bullet_shape: Polygon2D = $BulletShape

var velocity: Vector2 = Vector2.ZERO
var lifetime_remaining: float = 0.0
var bullet_material: ShaderMaterial


func _ready() -> void:
	_apply_visual_asset()
	lifetime_remaining = lifetime_seconds
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	lifetime_remaining -= delta

	if lifetime_remaining <= 0.0:
		queue_free()
		return

	position += velocity * delta
	_wrap_to_visible_viewport()


func launch(direction: Vector2, inherited_velocity: Vector2 = Vector2.ZERO) -> void:
	rotation = direction.angle() + (PI / 2.0)
	velocity = direction.normalized() * speed + inherited_velocity


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("handle_bullet_hit"):
		area.handle_bullet_hit(self)
		queue_free()


func set_shader_lighting_enabled(value: bool) -> void:
	shader_lighting_enabled = value
	MATERIAL_RUNTIME.set_lighting_enabled(bullet_material, value)


func set_world_light_direction(value: Vector2) -> void:
	pass


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


func _apply_visual_asset() -> void:
	if (
		visual_asset == null
		or not visual_asset.has_method("is_primary_polygon_valid")
		or not visual_asset.is_primary_polygon_valid()
	):
		return

	bullet_shape.polygon = visual_asset.primary_polygon
	bullet_shape.color = visual_asset.fill_color
	bullet_material = MATERIAL_RUNTIME.apply_material_definition(bullet_shape, visual_asset.material_definition)
	set_shader_lighting_enabled(shader_lighting_enabled)
