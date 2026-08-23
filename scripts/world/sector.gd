## Runtime authority for the extent of the active sector. Every gameplay
## script asks this node where the world ends instead of asking the viewport.
extends Node2D
class_name Sector


@export var definition: Resource


func get_bounds() -> Rect2:
	if definition == null or not definition.has_method("get_bounds"):
		return get_viewport_rect()

	# The sector may never be smaller than what the player can see.
	# project.godot stretches with aspect "expand", so the visible rect grows
	# past the 1152x648 base on any other aspect ratio -- 1440x648 on a 20:9
	# phone. Without this the default viewport-sized sector would stop entities
	# in the middle of the screen instead of at its edge, which is exactly the
	# behaviour change #44 must not introduce.
	#
	# Grown per axis rather than merged: Rect2.merge would take the bounding box
	# of both rects and so balloon an offset sector towards the origin. Once #45
	# grows world_size past the viewport this is a no-op.
	var bounds: Rect2 = definition.get_bounds()
	bounds.size = bounds.size.max(get_viewport_rect().size)
	return bounds


func get_center() -> Vector2:
	return get_bounds().get_center()


## The sector's layout seed. Callers pass what they would have used had this
## sector carried no definition, because the caller -- not the sector -- owns
## that default: `game.gd` seeds its asteroid spawns from its own exported
## `random_seed`, and the star layers must land on the same sky as those
## asteroids whether or not a definition is present.
##
## Here rather than read off `sector.definition` at the call site so that the
## "ask the Sector, not the resource behind it" rule this node exists to
## enforce holds for the seed as it already does for bounds and margin.
func get_seed(fallback: int) -> int:
	if definition != null and "sector_seed" in definition:
		return definition.sector_seed

	return fallback


## The sector's display name, asked of the Sector rather than read off
## `sector.definition` at the call site, for the same reason as get_seed():
## this node is the one authority on what the active sector is.
func get_sector_name(fallback: String) -> String:
	if definition != null and "sector_name" in definition:
		return String(definition.sector_name)

	return fallback


func get_boundary_margin() -> float:
	if definition != null and "boundary_margin" in definition:
		return definition.boundary_margin

	return 0.0


func get_random_position(rng: RandomNumberGenerator, inset: float = 0.0) -> Vector2:
	var bounds := get_bounds()
	# An inset wider than half the sector would invert the range and sample
	# backwards; collapse it to the centre line of that axis instead.
	var limit := Vector2(
		minf(inset, bounds.size.x * 0.5),
		minf(inset, bounds.size.y * 0.5)
	)
	return Vector2(
		rng.randf_range(bounds.position.x + limit.x, bounds.end.x - limit.x),
		rng.randf_range(bounds.position.y + limit.y, bounds.end.y - limit.y)
	)
