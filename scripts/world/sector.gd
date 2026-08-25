## Runtime authority for the extent of the active sector. Every gameplay
## script asks this node where the world ends instead of asking the viewport.
extends Node2D
class_name Sector


const ASTEROID_FIELD_SCENE := preload("res://scenes/world/AsteroidField.tscn")

@export var definition: Resource

var _fields: Array[Node2D] = []


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


func place_content(rng: RandomNumberGenerator) -> void:
	_clear_fields()

	if definition == null:
		return

	var field_count: int = definition.asteroid_field_count if "asteroid_field_count" in definition else 0
	var radius_min: float = definition.asteroid_field_radius_min if "asteroid_field_radius_min" in definition else 320.0
	var radius_max: float = definition.asteroid_field_radius_max if "asteroid_field_radius_max" in definition else radius_min
	var budget: int = definition.asteroid_field_budget if "asteroid_field_budget" in definition else 4
	var min_separation: float = definition.min_landmark_separation if "min_landmark_separation" in definition else 0.0

	if radius_max < radius_min:
		var swap := radius_min
		radius_min = radius_max
		radius_max = swap

	for index in field_count:
		var field := ASTEROID_FIELD_SCENE.instantiate() as Node2D
		field.field_name = StringName("asteroid_field_%02d" % (index + 1))
		field.field_radius = rng.randf_range(radius_min, radius_max)
		field.asteroid_budget = budget
		field.position = find_free_position(rng, field.field_radius, min_separation)
		add_child(field)
		_fields.append(field)


func get_fields() -> Array[Node2D]:
	var fields: Array[Node2D] = []
	for field in _fields:
		if is_instance_valid(field) and not field.is_queued_for_deletion():
			fields.append(field)
	return fields


func find_free_position(rng: RandomNumberGenerator, radius: float, min_separation: float) -> Vector2:
	var best_position := Vector2.ZERO
	var best_distance := -INF

	for attempt in 32:
		var candidate := get_random_position(rng, radius)
		var nearest_distance := _get_nearest_field_distance(candidate)

		if nearest_distance >= min_separation:
			return candidate

		if nearest_distance > best_distance:
			best_distance = nearest_distance
			best_position = candidate

	return best_position


func _get_nearest_field_distance(candidate: Vector2) -> float:
	if _fields.is_empty():
		return INF

	var nearest_distance := INF
	for field in get_fields():
		# find_free_position samples get_random_position, which works in the
		# definition's own bounds space, and place_content writes the result
		# straight to field.position. Compare against the same space rather
		# than global_position, which would silently drift apart from it the
		# first time this node is placed anywhere but the origin.
		nearest_distance = minf(nearest_distance, candidate.distance_to(field.position))

	return nearest_distance


func _clear_fields() -> void:
	for field in _fields:
		if not is_instance_valid(field):
			continue

		# Detach before queueing the free. queue_free() only runs at the end of
		# the frame, and it flags the field alone -- its asteroids would answer
		# is_queued_for_deletion() with false and stay in the `asteroids` group,
		# so a restart would count the previous sector's rocks as live. Leaving
		# the tree drops the whole subtree from its groups now.
		var parent := field.get_parent()
		if parent != null:
			parent.remove_child(field)
		field.queue_free()
	_fields.clear()
