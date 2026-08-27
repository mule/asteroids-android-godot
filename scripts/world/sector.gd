## Runtime authority for the extent of the active sector. Every gameplay
## script asks this node where the world ends instead of asking the viewport.
extends Node2D
class_name Sector


const ASTEROID_FIELD_SCENE := preload("res://scenes/world/AsteroidField.tscn")

@export var definition: Resource

## Rejection-sampling budget for landmark placement. See
## get_station_positions() for what happens when it runs out.
const _PLACEMENT_ATTEMPTS := 48

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

## How many stations this sector wants. Asked of the Sector for the same reason
## as get_seed() and get_sector_name(): the caller owns the default it would
## have used, the sector owns the answer when it has one.
func get_station_count(fallback: int) -> int:
	if definition != null and "station_count" in definition:
		return maxi(0, definition.station_count)

	return fallback


func get_min_landmark_separation(fallback: float) -> float:
	if definition != null and "min_landmark_separation" in definition:
		return definition.min_landmark_separation

	return fallback


## Where this sector's stations sit.
##
## Rejection sampling against everything already placed, against `avoid` -- the
## player's own spawn, in practice -- and against the asteroid fields this
## sector has already laid down. Two stations on top of each other put one ship
## inside two dock zones and hand the dock to whichever polled first; a station
## on the spawn point docks the player before the run starts; and a station
## inside a field parks the player, controls disabled, in the one part of the
## sector that is manufacturing rocks.
##
## The field test is deliberately not folded into `separation`. `separation` is
## a centre-to-centre figure between landmarks of no particular size, but a
## field is a disc with a radius of its own, and what has to clear it is not
## the station's centre -- it is the whole dock zone the player has to sit
## still inside. Both are measured off the live radii, so widening a field or a
## dock zone later cannot silently drop a dock zone back into a belt.
##
## Best effort, not a guarantee: after `_PLACEMENT_ATTEMPTS` tries the candidate
## that misses by the least is taken. A sector too small to separate the
## stations it asks for must still produce them -- silently returning fewer
## would leave the sector with no destination at all, which is worse than a
## crowded one.
func get_station_positions(
	rng: RandomNumberGenerator,
	count: int,
	edge_inset: float = 0.0,
	min_separation: float = -1.0,
	avoid: Array = [],
	field_clearance: float = 0.0
) -> Array[Vector2]:
	var separation := get_min_landmark_separation(0.0) if min_separation < 0.0 else min_separation
	var placed: Array[Vector2] = []

	for _index in maxi(0, count):
		placed.append(
			_pick_separated_position(rng, placed, avoid, separation, edge_inset, field_clearance)
		)

	return placed


func _pick_separated_position(
	rng: RandomNumberGenerator,
	placed: Array[Vector2],
	avoid: Array,
	separation: float,
	edge_inset: float,
	field_clearance: float
) -> Vector2:
	var best := Vector2.ZERO
	# Scored on slack rather than on distance, because the two requirements are
	# not in the same units of "far enough": one is a centre-to-centre gap, the
	# other is clearance beyond a field's edge. Subtracting each requirement
	# makes them comparable, and the tighter of the two is what the candidate is
	# worth. Seeded at -INF, not -1.0: a candidate can now miss by more than a
	# whole pixel and still be the best one seen.
	var best_slack := -INF

	for _attempt in _PLACEMENT_ATTEMPTS:
		var candidate := get_random_position(rng, edge_inset)
		var slack := minf(
			_get_nearest_gap(candidate, placed, avoid) - separation,
			_get_field_edge_gap(candidate) - field_clearance
		)

		if slack >= 0.0:
			return candidate

		if slack > best_slack:
			best_slack = slack
			best = candidate

	return best


## Distance from `candidate` to the nearest asteroid field's EDGE rather than
## its centre -- a field is a disc, and what is being kept out of it is a disc
## too, so the centre-to-centre figure the other landmarks use would have to
## guess at a radius it cannot see. INF when the sector holds no fields, which
## leaves a station in an empty sector unconstrained instead of unplaceable.
##
## Measured against `field.position` for the reason
## `_get_nearest_field_distance` gives: placement works in the definition's own
## bounds space and `place_content` writes that straight to `field.position`.
func _get_field_edge_gap(candidate: Vector2) -> float:
	var gap := INF

	for field in get_fields():
		var radius: float = field.field_radius if "field_radius" in field else 0.0
		gap = minf(gap, candidate.distance_to(field.position) - radius)

	return gap


func _get_nearest_gap(candidate: Vector2, placed: Array[Vector2], avoid: Array) -> float:
	var gap := INF

	for other: Vector2 in placed:
		gap = minf(gap, candidate.distance_to(other))

	for other: Vector2 in avoid:
		gap = minf(gap, candidate.distance_to(other))

	return gap
