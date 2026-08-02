extends Area2D


@export var speed: float = 760.0
@export var lifetime_seconds: float = 1.2
@export var wrap_margin: float = 8.0

var velocity: Vector2 = Vector2.ZERO
var lifetime_remaining: float = 0.0


func _ready() -> void:
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
