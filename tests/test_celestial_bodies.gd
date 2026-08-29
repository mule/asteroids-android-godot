extends SceneTree


const BODY_DEFINITION_SCRIPT := "res://scripts/resources/celestial_body_definition.gd"
const BODY_SCENE := "res://scenes/entities/CelestialBody.tscn"
const SECTOR_DEFINITION_SCRIPT := "res://scripts/resources/sector_definition.gd"
const SECTOR_SCRIPT := "res://scripts/world/sector.gd"


func _init() -> void:
	var failures: Array[String] = []

	await _test_moon_keeps_constant_orbit_radius(failures)
	await _test_moon_completes_orbit_period(failures)
	await _test_planet_does_not_move(failures)
	await _test_sector_places_bodies_inside_bounds_and_apart(failures)
	await _test_bodies_join_gravity_sources_group(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL CELESTIAL BODY TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


func _load_resource(path: String, failures: Array[String]) -> Resource:
	var resource := load(path)
	if resource == null:
		failures.append("Load: expected %s to exist" % path)
	return resource


func _make_body_definition(failures: Array[String], id: StringName, radius: float, orbit_radius: float, orbit_period: float) -> Resource:
	var script := _load_resource(BODY_DEFINITION_SCRIPT, failures) as Script
	if script == null:
		return null

	var definition := script.new() as Resource
	definition.body_id = id
	definition.body_radius = radius
	definition.gravity_strength = 0.0
	definition.influence_multiplier = 4.0
	definition.orbit_radius = orbit_radius
	definition.orbit_period_seconds = orbit_period
	return definition


func _make_body(failures: Array[String], definition: Resource, parent_body: Node2D, initial_angle: float, position: Vector2 = Vector2.ZERO) -> Area2D:
	var scene := _load_resource(BODY_SCENE, failures) as PackedScene
	if scene == null or definition == null:
		return null

	var body := scene.instantiate() as Area2D
	if body == null:
		failures.append("Scene: CelestialBody.tscn root must be Area2D")
		return null

	root.add_child(body)
	body.global_position = position
	body.setup(definition, parent_body, initial_angle)
	await process_frame
	return body


func _test_moon_keeps_constant_orbit_radius(failures: Array[String]) -> void:
	var parent := Node2D.new()
	parent.global_position = Vector2(420.0, 380.0)
	root.add_child(parent)

	var definition := _make_body_definition(failures, &"test_moon_radius", 36.0, 320.0, 5.0)
	var moon := await _make_body(failures, definition, parent, 0.35)
	if moon == null:
		parent.queue_free()
		await process_frame
		return

	var initial_distance := moon.global_position.distance_to(parent.global_position)
	var min_distance := initial_distance
	var max_distance := initial_distance

	for _frame in 300:
		await physics_frame
		var distance := moon.global_position.distance_to(parent.global_position)
		min_distance = minf(min_distance, distance)
		max_distance = maxf(max_distance, distance)

	if absf(initial_distance - definition.orbit_radius) > 0.01:
		failures.append("Orbit radius: expected initial distance %f to equal %f" % [initial_distance, definition.orbit_radius])
	if max_distance - min_distance > 0.05:
		failures.append("Orbit radius: drifted from %f to %f across 300 physics frames" % [min_distance, max_distance])

	moon.queue_free()
	parent.queue_free()
	await process_frame


func _test_moon_completes_orbit_period(failures: Array[String]) -> void:
	var parent := Node2D.new()
	parent.global_position = Vector2(900.0, 700.0)
	root.add_child(parent)

	var definition := _make_body_definition(failures, &"test_moon_period", 32.0, 260.0, 2.0)
	var moon := await _make_body(failures, definition, parent, 1.1)
	if moon == null:
		parent.queue_free()
		await process_frame
		return

	var starting_position := moon.global_position
	var frame_count := int(roundi(definition.orbit_period_seconds * Engine.physics_ticks_per_second))
	for _frame in frame_count + 1:
		await physics_frame

	if moon.global_position.distance_to(starting_position) > 0.75:
		failures.append(
			"Orbit period: expected %s to return near %s after %d frames"
			% [str(moon.global_position), str(starting_position), frame_count]
		)

	moon.queue_free()
	parent.queue_free()
	await process_frame


func _test_planet_does_not_move(failures: Array[String]) -> void:
	var definition := _make_body_definition(failures, &"test_planet_static", 96.0, 0.0, 0.0)
	var planet := await _make_body(failures, definition, null, 0.0, Vector2(1234.0, 987.0))
	if planet == null:
		return

	var starting_position := planet.global_position
	for _frame in 120:
		await physics_frame

	if not planet.global_position.is_equal_approx(starting_position):
		failures.append("Static planet: moved from %s to %s" % [str(starting_position), str(planet.global_position)])

	planet.queue_free()
	await process_frame


func _test_sector_places_bodies_inside_bounds_and_apart(failures: Array[String]) -> void:
	var sector_definition_script := _load_resource(SECTOR_DEFINITION_SCRIPT, failures) as Script
	var sector_script := _load_resource(SECTOR_SCRIPT, failures) as Script
	if sector_definition_script == null or sector_script == null:
		return

	var definition: Resource = sector_definition_script.new()
	definition.world_size = Vector2(9000.0, 7000.0)
	definition.sector_seed = 515151
	definition.asteroid_field_count = 3
	definition.asteroid_field_radius_min = 160.0
	definition.asteroid_field_radius_max = 180.0
	definition.planet_count = 2
	definition.moon_count = 3
	definition.min_landmark_separation = 760.0

	var sector := sector_script.new() as Node2D
	sector.definition = definition
	root.add_child(sector)
	await process_frame

	var rng := RandomNumberGenerator.new()
	rng.seed = definition.sector_seed
	sector.place_content(rng)
	await process_frame

	var bodies: Array = sector.get_celestial_bodies()
	if bodies.size() != definition.planet_count + definition.moon_count:
		failures.append("Sector bodies: expected %d, got %d" % [definition.planet_count + definition.moon_count, bodies.size()])

	var bounds: Rect2 = definition.get_bounds()
	var footprints: Array[Dictionary] = []
	var planets: Array = []
	for body in bodies:
		if body.get("definition") != null and is_equal_approx(body.get("definition").orbit_radius, 0.0):
			planets.append(body)

	for body in bodies:
		var radius: float = body.get_body_radius()
		if not _circle_inside_bounds(body.global_position, radius, bounds):
			failures.append("Sector bounds: %s radius %f was outside %s" % [body.name, radius, str(bounds)])

		var orbit_radius: float = body.get("definition").orbit_radius if body.get("definition") != null else 0.0
		var footprint_center: Vector2 = body.global_position
		if orbit_radius > 0.0:
			footprint_center = _find_orbit_center(body, planets)
		var footprint_radius := radius + orbit_radius
		if not _circle_inside_bounds(footprint_center, footprint_radius, bounds):
			failures.append("Sector orbit: %s footprint radius %f was outside %s" % [body.name, footprint_radius, str(bounds)])

		footprints.append({
			"name": body.name,
			"position": footprint_center,
			"body_radius": radius,
			"orbit_radius": orbit_radius,
		})

	for i in footprints.size():
		for j in range(i + 1, footprints.size()):
			var a := footprints[i]
			var b := footprints[j]
			var gap := _swept_landmark_gap(a, b)
			if gap < definition.min_landmark_separation:
				failures.append(
					"Sector separation: %s and %s leave gap %f, expected at least %f"
					% [a["name"], b["name"], gap, definition.min_landmark_separation]
				)

	sector.queue_free()
	await process_frame


func _test_bodies_join_gravity_sources_group(failures: Array[String]) -> void:
	var definition := _make_body_definition(failures, &"test_gravity_group", 72.0, 0.0, 0.0)
	var body := await _make_body(failures, definition, null, 0.0, Vector2(300.0, 300.0))
	if body == null:
		return

	if not body.is_in_group("gravity_sources"):
		failures.append("Groups: celestial body missing gravity_sources")
	if not body.is_in_group("celestial_bodies"):
		failures.append("Groups: celestial body missing celestial_bodies")

	body.queue_free()
	await process_frame


func _circle_inside_bounds(center: Vector2, radius: float, bounds: Rect2) -> bool:
	return (
		center.x - radius >= bounds.position.x
		and center.y - radius >= bounds.position.y
		and center.x + radius <= bounds.end.x
		and center.y + radius <= bounds.end.y
	)


func _find_orbit_center(moon: Node2D, planets: Array) -> Vector2:
	if moon.get("orbit_parent") is Node2D:
		return (moon.get("orbit_parent") as Node2D).global_position

	var orbit_radius: float = moon.get("definition").orbit_radius
	for planet in planets:
		if absf(moon.global_position.distance_to(planet.global_position) - orbit_radius) <= 1.0:
			return planet.global_position

	return moon.global_position


func _swept_landmark_gap(a: Dictionary, b: Dictionary) -> float:
	var center_a: Vector2 = a["position"]
	var center_b: Vector2 = b["position"]
	var orbit_a: float = a["orbit_radius"]
	var orbit_b: float = b["orbit_radius"]
	var radius_a: float = a["body_radius"]
	var radius_b: float = b["body_radius"]

	if center_a.distance_to(center_b) <= 0.01:
		return absf(orbit_a - orbit_b) - radius_a - radius_b

	return center_a.distance_to(center_b) - orbit_a - radius_a - orbit_b - radius_b
