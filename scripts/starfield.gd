extends Node2D


@export var star_count: int = 90
@export var random_seed: int = 404
@export var min_radius: float = 1.0
@export var max_radius: float = 2.4

var random := RandomNumberGenerator.new()


func _ready() -> void:
	random.seed = random_seed
	_build_stars()


func _build_stars() -> void:
	var viewport_rect := get_viewport_rect()

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
			random.randf_range(viewport_rect.position.x, viewport_rect.end.x),
			random.randf_range(viewport_rect.position.y, viewport_rect.end.y)
		)
		star.color = Color(0.65, 0.82, 1.0, random.randf_range(0.28, 0.7))
		add_child(star)
