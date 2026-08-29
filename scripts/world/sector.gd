## Runtime authority for the extent of the active sector. Every gameplay
## script asks this node where the world ends instead of asking the viewport.
extends Node2D
class_name Sector


const ASTEROID_FIELD_SCENE := preload("res://scenes/world/AsteroidField.tscn")
const CELESTIAL_BODY_SCENE := preload("res://scenes/entities/CelestialBody.tscn")
const CELESTIAL_BODY_DEFINITION_SCRIPT := preload("res://scripts/resources/celestial_body_definition.gd")
const PLANET_VISUAL_ASSET := preload("res://assets/generated/celestial/celestial_planet_01.tres")
const MOON_VISUAL_ASSET := preload("res://assets/generated/celestial/celestial_moon_01.tres")

@export var definition: Resource

## Rejection-sampling budget for landmark placement. See
## get_station_positions() for what happens when it runs out.
const _PLACEMENT_ATTEMPTS := 48

var _fields: Array[Node2D] = []
var _celestial_bodies: Array[Area2D] = []
var _celestial_footprints: Array[Dictionary] = []


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
	_clear_celestial_bodies()

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

	var celestial_rng := RandomNumberGenerator.new()
	celestial_rng.seed = rng.seed + 9109
	_place_celestial_bodies(celestial_rng, min_separation)


func get_fields() -> Array[Node2D]:
	var fields: Array[Node2D] = []
	for field in _fields:
		if is_instance_valid(field) and not field.is_queued_for_deletion():
			fields.append(field)
	return fields


func get_celestial_bodies() -> Array[Area2D]:
	var bodies: Array[Area2D] = []
	for body in _celestial_bodies:
		if is_instance_valid(body) and not body.is_queued_for_deletion():
			bodies.append(body)
	return bodies


func find_free_position(rng: RandomNumberGenerator, radius: float, min_separation: float) -> Vector2:
	var best_position := Vector2.ZERO
	var best_slack := -INF

	for attempt in 32:
		var candidate := get_random_position(rng, radius)
		var slack := _get_nearest_field_distance(candidate) - min_separation

		if slack >= 0.0:
			return candidate

		if slack > best_slack:
			best_slack = slack
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


func _place_celestial_bodies(rng: RandomNumberGenerator, min_separation: float) -> void:
	var planet_count: int = definition.planet_count if "planet_count" in definition else 0
	var moon_count: int = definition.moon_count if "moon_count" in definition else 0
	planet_count = maxi(0, planet_count)
	moon_count = maxi(0, moon_count)

	if planet_count <= 0:
		return

	var planets: Array[Area2D] = []
	for index in planet_count:
		var planet_definition := _make_planet_definition(index)
		var system_radius := _get_planet_system_radius(index, planet_count, moon_count, min_separation)
		var center := _pick_celestial_system_center(rng, system_radius, min_separation)
		var planet := _spawn_celestial_body(planet_definition, null, 0.0, center)
		planets.append(planet)
		_celestial_footprints.append({
			"position": center,
			"radius": system_radius,
		})

	for index in moon_count:
		var parent_index := index % planets.size()
		var orbit_slot := index / planets.size()
		var parent := planets[parent_index]
		var moon_definition := _make_moon_definition(index, orbit_slot, parent.get_body_radius(), min_separation)
		var initial_angle := rng.randf_range(0.0, TAU)
		_spawn_celestial_body(moon_definition, parent, initial_angle)
		_celestial_footprints.append({
			"position": parent.global_position,
			"radius": moon_definition.orbit_radius + moon_definition.body_radius,
		})


func _spawn_celestial_body(
	body_definition: Resource,
	parent_body: Node2D,
	initial_angle: float,
	spawn_position: Vector2 = Vector2.ZERO
) -> Area2D:
	var body := CELESTIAL_BODY_SCENE.instantiate() as Area2D
	add_child(body)
	body.global_position = spawn_position
	body.setup(body_definition, parent_body, initial_angle)
	_celestial_bodies.append(body)
	return body


func _make_planet_definition(index: int) -> Resource:
	var body_definition := CELESTIAL_BODY_DEFINITION_SCRIPT.new()
	body_definition.body_id = StringName("planet_%02d" % (index + 1))
	body_definition.body_radius = maxf(170.0, 220.0 - float(index % 3) * 20.0)
	body_definition.gravity_strength = 1400.0
	body_definition.influence_multiplier = 4.0
	body_definition.visual_asset = PLANET_VISUAL_ASSET
	body_definition.orbit_radius = 0.0
	body_definition.orbit_period_seconds = 0.0
	return body_definition


func _make_moon_definition(index: int, orbit_slot: int, parent_radius: float, min_separation: float) -> Resource:
	var moon_radius := maxf(64.0, 86.0 - float(index % 2) * 10.0)
	var body_definition := CELESTIAL_BODY_DEFINITION_SCRIPT.new()
	body_definition.body_id = StringName("moon_%02d" % (index + 1))
	body_definition.body_radius = moon_radius
	body_definition.gravity_strength = 350.0
	body_definition.influence_multiplier = 4.0
	body_definition.visual_asset = MOON_VISUAL_ASSET
	body_definition.orbit_radius = parent_radius + moon_radius + min_separation + 180.0
	body_definition.orbit_radius += float(orbit_slot) * (min_separation + moon_radius * 2.0 + 180.0)
	body_definition.orbit_period_seconds = 24.0 + float(index) * 6.0
	return body_definition


func _get_planet_system_radius(index: int, planet_count: int, moon_count: int, min_separation: float) -> float:
	var planet_definition := _make_planet_definition(index)
	var system_radius: float = planet_definition.body_radius

	var moon_index := index
	while moon_index < moon_count:
		var orbit_slot := moon_index / planet_count
		var moon_definition := _make_moon_definition(
			moon_index,
			orbit_slot,
			planet_definition.body_radius,
			min_separation
		)
		system_radius = maxf(system_radius, moon_definition.orbit_radius + moon_definition.body_radius)
		moon_index += planet_count

	return system_radius


func _pick_celestial_system_center(
	rng: RandomNumberGenerator,
	system_radius: float,
	min_separation: float
) -> Vector2:
	var best := Vector2.ZERO
	var best_slack := -INF

	for _attempt in _PLACEMENT_ATTEMPTS * 8:
		var candidate := get_random_position(rng, system_radius)
		var slack := _get_celestial_system_slack(candidate, system_radius, min_separation)
		if slack >= 0.0:
			return candidate

		if slack > best_slack:
			best_slack = slack
			best = candidate

	for candidate in _get_celestial_anchor_positions(system_radius):
		var slack := _get_celestial_system_slack(candidate, system_radius, min_separation)
		if slack >= 0.0:
			return candidate

		if slack > best_slack:
			best_slack = slack
			best = candidate

	return best


func _get_celestial_system_slack(candidate: Vector2, radius: float, min_separation: float) -> float:
	return minf(
		_get_nearest_celestial_gap(candidate, radius) - min_separation,
		_get_field_edge_gap(candidate) - radius - min_separation
	)


func _get_nearest_celestial_gap(candidate: Vector2, radius: float) -> float:
	var gap := INF

	for footprint in _celestial_footprints:
		var footprint_position: Vector2 = footprint["position"]
		var footprint_radius: float = footprint["radius"]
		gap = minf(gap, candidate.distance_to(footprint_position) - radius - footprint_radius)

	return gap


func _get_celestial_anchor_positions(radius: float) -> Array[Vector2]:
	var bounds := get_bounds()
	var limit := Vector2(
		minf(radius, bounds.size.x * 0.5),
		minf(radius, bounds.size.y * 0.5)
	)
	var left := bounds.position.x + limit.x
	var right := bounds.end.x - limit.x
	var top := bounds.position.y + limit.y
	var bottom := bounds.end.y - limit.y
	var center := bounds.get_center()

	return [
		Vector2(left, top),
		Vector2(right, top),
		Vector2(left, bottom),
		Vector2(right, bottom),
		Vector2(center.x, top),
		Vector2(center.x, bottom),
		Vector2(left, center.y),
		Vector2(right, center.y),
		center,
	]


func _clear_celestial_bodies() -> void:
	for body in _celestial_bodies:
		if not is_instance_valid(body):
			continue

		var parent := body.get_parent()
		if parent != null:
			parent.remove_child(body)
		body.queue_free()

	_celestial_bodies.clear()
	_celestial_footprints.clear()


func _get_nearest_gap(candidate: Vector2, placed: Array[Vector2], avoid: Array) -> float:
	var gap := INF

	for other: Vector2 in placed:
		gap = minf(gap, candidate.distance_to(other))

	for other: Vector2 in avoid:
		gap = minf(gap, candidate.distance_to(other))

	return gap
