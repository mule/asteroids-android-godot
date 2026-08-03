extends Area2D


signal destroyed(asteroid: Area2D, size_tier: int, hit_position: Vector2, incoming_velocity: Vector2)

enum AsteroidSize {
	LARGE,
	MEDIUM,
	SMALL,
}

@export var visual_asset: Resource = preload("res://assets/vector/baseline_asteroid.tres")
@export_enum("Large", "Medium", "Small") var size_tier: int = AsteroidSize.LARGE
@export var drift_speed: float = 90.0
@export var rotation_speed_degrees: float = 25.0
@export var wrap_margin: float = 48.0

@onready var rock_shape: Polygon2D = $RockShape
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	_apply_visual_asset()
	_apply_size_tier()


func _physics_process(delta: float) -> void:
	position += velocity * delta
	rotation += deg_to_rad(rotation_speed_degrees) * delta
	_wrap_to_visible_viewport()


func setup(tier: int, initial_velocity: Vector2) -> void:
	size_tier = tier
	velocity = initial_velocity

	if is_node_ready():
		_apply_size_tier()


func get_next_size_tier() -> int:
	return size_tier + 1


func can_split() -> bool:
	return size_tier < AsteroidSize.SMALL


func handle_bullet_hit(bullet: Area2D) -> void:
	destroyed.emit(self, size_tier, global_position, velocity)
	queue_free()


func _apply_size_tier() -> void:
	rock_shape.scale = Vector2.ONE * _get_visual_scale()

	if collision_shape.shape is CircleShape2D:
		var circle_shape := collision_shape.shape.duplicate() as CircleShape2D
		circle_shape.radius = _get_collision_radius()
		collision_shape.shape = circle_shape


func _apply_visual_asset() -> void:
	if (
		visual_asset == null
		or not visual_asset.has_method("is_primary_polygon_valid")
		or not visual_asset.is_primary_polygon_valid()
	):
		return

	rock_shape.polygon = visual_asset.primary_polygon
	rock_shape.color = visual_asset.fill_color


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
