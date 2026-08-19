extends Node2D
class_name Sector


@export var definition: Resource


func get_bounds() -> Rect2:
	if definition != null and definition.has_method("get_bounds"):
		return definition.get_bounds()

	return get_viewport_rect()


func get_center() -> Vector2:
	return get_bounds().get_center()


func get_boundary_margin() -> float:
	if definition != null and "boundary_margin" in definition:
		return definition.boundary_margin

	return 0.0


func get_random_position(rng: RandomNumberGenerator, inset: float = 0.0) -> Vector2:
	var bounds := get_bounds()
	return Vector2(
		rng.randf_range(bounds.position.x + inset, bounds.end.x - inset),
		rng.randf_range(bounds.position.y + inset, bounds.end.y - inset)
	)
