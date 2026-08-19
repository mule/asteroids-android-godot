## Runtime authority for the extent of the active sector. Every gameplay
## script asks this node where the world ends instead of asking the viewport.
extends Node2D
class_name Sector


@export var definition: Resource


func get_bounds() -> Rect2:
	if definition != null and definition.has_method("get_bounds"):
		# The sector may never be smaller than what the player can see.
		# project.godot stretches with aspect "expand", so the visible rect
		# grows past the 1152x648 base on any other aspect ratio -- 1440x648 on
		# a 20:9 phone. Without this merge the default viewport-sized sector
		# would wrap entities in the middle of the screen instead of at its
		# edge, which is exactly the behaviour change #44 must not introduce.
		# Once #45 grows the sector past the viewport this merge is a no-op.
		return definition.get_bounds().merge(get_viewport_rect())

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
