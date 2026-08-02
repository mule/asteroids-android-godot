extends Area2D


signal bullet_hit(bullet: Area2D)

@export var drift_speed: float = 90.0
@export var rotation_speed_degrees: float = 25.0


func _ready() -> void:
	pass


func handle_bullet_hit(bullet: Area2D) -> void:
	bullet_hit.emit(bullet)
	modulate = Color(1.0, 0.78, 0.35, 1.0)
