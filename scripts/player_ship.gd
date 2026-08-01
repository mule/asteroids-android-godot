extends Area2D


@export var acceleration: float = 360.0
@export var max_speed: float = 520.0
@export var turn_speed_degrees: float = 180.0
@export var linear_drag: float = 12.0
@export var wrap_margin: float = 32.0

@onready var thrust_flame: Polygon2D = $ThrustFlame

var velocity: Vector2 = Vector2.ZERO


func _physics_process(delta: float) -> void:
	_apply_rotation_input(delta)
	_apply_thrust_input(delta)
	_apply_drift(delta)
	_move(delta)
	_wrap_to_visible_viewport()


func _apply_rotation_input(delta: float) -> void:
	var turn_input := Input.get_axis("rotate_left", "rotate_right")
	rotation += deg_to_rad(turn_speed_degrees) * turn_input * delta


func _apply_thrust_input(delta: float) -> void:
	var is_thrusting := Input.is_action_pressed("thrust")
	thrust_flame.visible = is_thrusting

	if is_thrusting:
		velocity += Vector2.UP.rotated(rotation) * acceleration * delta
		velocity = velocity.limit_length(max_speed)


func _apply_drift(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, linear_drag * delta)


func _move(delta: float) -> void:
	position += velocity * delta


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
