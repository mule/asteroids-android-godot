extends Node2D
class_name StarLayer


@export var star_count: int = 90
@export var layer_seed: int = 404
@export var min_radius: float = 1.0
@export var max_radius: float = 2.4
@export var star_color: Color = Color(0.65, 0.82, 1.0)
@export var min_alpha: float = 0.28
@export var max_alpha: float = 0.7

var random := RandomNumberGenerator.new()


func build_stars(bounds: Rect2, seed_value: int) -> void:
	for child in get_children():
		child.queue_free()

	random.seed = seed_value

	for index in star_count:
		var star := Polygon2D.new()
		var radius := random.randf_range(min_radius, max_radius)
		star.polygon = PackedVector2Array([
			Vector2(0.0, -radius),
			Vector2(radius, 0.0),
			Vector2(0.0, radius),
			Vector2(-radius, 0.0)
		])
		star.position = Vector2(
			random.randf_range(bounds.position.x, bounds.end.x),
			random.randf_range(bounds.position.y, bounds.end.y)
		)
		star.color = Color(
			star_color.r,
			star_color.g,
			star_color.b,
			random.randf_range(min_alpha, max_alpha)
		)
		add_child(star)
