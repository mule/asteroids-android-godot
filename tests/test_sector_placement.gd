extends SceneTree


const ASTEROID_FIELD_SCENE := "res://scenes/world/AsteroidField.tscn"
const ASTEROID_SCENE := "res://scenes/entities/Asteroid.tscn"
const GAME_SCENE := "res://scenes/game/Game.tscn"
const GAME_SCRIPT := "res://scripts/game.gd"


func _init() -> void:
	var failures: Array[String] = []

	await _test_same_seed_reproduces_identical_layout(failures)
	await _test_different_seeds_produce_different_layouts(failures)
	await _test_fields_respect_minimum_separation(failures)
	await _test_fields_stay_inside_sector_bounds(failures)
	await _test_oversubscribed_placement_terminates(failures)
	await _test_field_seeding_keeps_asteroid_group_membership(failures)
	await _test_a_field_rock_scores_splits_and_refuels(failures)
	await _test_seeding_an_empty_field_is_not_a_clear(failures)
	_test_game_no_longer_owns_spawn_wave(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL SECTOR PLACEMENT TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


func _make_definition(seed: int = 1729) -> SectorDefinition:
	var definition := SectorDefinition.new()
	definition.world_size = Vector2(3000.0, 2200.0)
	definition.sector_seed = seed
	definition.asteroid_field_count = 6
	definition.asteroid_field_radius_min = 110.0
	definition.asteroid_field_radius_max = 190.0
	definition.asteroid_field_budget = 3
	definition.min_landmark_separation = 360.0
	return definition


func _make_sector(definition: SectorDefinition) -> Sector:
	var sector := Sector.new()
	sector.definition = definition
	root.add_child(sector)
	return sector


func _layout_for(definition: SectorDefinition) -> Array[Dictionary]:
	var sector := _make_sector(definition)
	await process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = definition.sector_seed
	sector.place_content(rng)
	var snapshot := _field_snapshot(sector)
	sector.queue_free()
	await process_frame
	return snapshot


func _field_snapshot(sector: Sector) -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for field in sector.get_fields():
		snapshot.append({
			"name": field.field_name,
			"position": field.global_position,
			"radius": field.field_radius,
			"budget": field.asteroid_budget,
		})

	snapshot.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["name"] != b["name"]:
			return String(a["name"]) < String(b["name"])
		if not is_equal_approx(a["position"].x, b["position"].x):
			return a["position"].x < b["position"].x
		return a["position"].y < b["position"].y
	)
	return snapshot


func _snapshots_match(left: Array[Dictionary], right: Array[Dictionary]) -> bool:
	if left.size() != right.size():
		return false

	for index in left.size():
		var a := left[index]
		var b := right[index]
		if a["name"] != b["name"]:
			return false
		if not (a["position"] as Vector2).is_equal_approx(b["position"]):
			return false
		if not is_equal_approx(a["radius"], b["radius"]):
			return false
		if a["budget"] != b["budget"]:
			return false

	return true


func _test_same_seed_reproduces_identical_layout(failures: Array[String]) -> void:
	var first := await _layout_for(_make_definition(314159))
	var second := await _layout_for(_make_definition(314159))

	if first.is_empty():
		failures.append("Seeded layout: expected fields to be placed")
	if not _snapshots_match(first, second):
		failures.append("Seeded layout: same seed produced different snapshots: %s vs %s" % [str(first), str(second)])


func _test_different_seeds_produce_different_layouts(failures: Array[String]) -> void:
	var first := await _layout_for(_make_definition(111))
	var second := await _layout_for(_make_definition(222))

	if _snapshots_match(first, second):
		failures.append("Seeded layout: different seeds produced the same field snapshot")


func _test_fields_respect_minimum_separation(failures: Array[String]) -> void:
	var definition := _make_definition(8675309)
	var sector := _make_sector(definition)
	await process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = definition.sector_seed
	sector.place_content(rng)

	var fields: Array[Node2D] = sector.get_fields()
	for i in fields.size():
		for j in range(i + 1, fields.size()):
			var distance: float = fields[i].global_position.distance_to(fields[j].global_position)
			if distance < definition.min_landmark_separation:
				failures.append(
					"Field separation: %s and %s are %f apart, expected at least %f"
					% [fields[i].field_name, fields[j].field_name, distance, definition.min_landmark_separation]
				)

	sector.queue_free()
	await process_frame


func _test_fields_stay_inside_sector_bounds(failures: Array[String]) -> void:
	var definition := _make_definition(99)
	var sector := _make_sector(definition)
	await process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = definition.sector_seed
	sector.place_content(rng)

	var bounds := definition.get_bounds()
	for field in sector.get_fields():
		var radius: float = field.field_radius
		var inside: bool = (
			field.global_position.x - radius >= bounds.position.x
			and field.global_position.y - radius >= bounds.position.y
			and field.global_position.x + radius <= bounds.end.x
			and field.global_position.y + radius <= bounds.end.y
		)
		if not inside:
			failures.append("Field bounds: %s with radius %f was placed outside %s" % [field.field_name, radius, str(bounds)])

	sector.queue_free()
	await process_frame


func _test_oversubscribed_placement_terminates(failures: Array[String]) -> void:
	var definition := SectorDefinition.new()
	definition.world_size = Vector2(700.0, 700.0)
	definition.sector_seed = 444
	definition.asteroid_field_count = 24
	definition.asteroid_field_radius_min = 80.0
	definition.asteroid_field_radius_max = 80.0
	definition.asteroid_field_budget = 1
	definition.min_landmark_separation = 550.0

	var sector := _make_sector(definition)
	await process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = definition.sector_seed
	var started := Time.get_ticks_msec()
	sector.place_content(rng)
	var elapsed := Time.get_ticks_msec() - started

	if sector.get_fields().size() != definition.asteroid_field_count:
		failures.append("Oversubscribed layout: expected %d fields, got %d" % [definition.asteroid_field_count, sector.get_fields().size()])
	if elapsed > 500:
		failures.append("Oversubscribed layout: placement took %dms, expected bounded rejection sampling" % elapsed)

	sector.queue_free()
	await process_frame


func _test_field_seeding_keeps_asteroid_group_membership(failures: Array[String]) -> void:
	var field := (load(ASTEROID_FIELD_SCENE) as PackedScene).instantiate()
	field.field_radius = 220.0
	field.asteroid_budget = 5
	root.add_child(field)

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var visual_assets: Array[Resource] = []
	field.seed_field(rng, load(ASTEROID_SCENE) as PackedScene, visual_assets)

	if field.get_active_asteroid_count() != field.asteroid_budget:
		failures.append("AsteroidField: active count %d must equal budget %d after seeding" % [field.get_active_asteroid_count(), field.asteroid_budget])

	for child in field.get_children():
		if child is Area2D and not child.is_in_group("asteroids"):
			failures.append("AsteroidField: spawned asteroid %s is missing the asteroids group" % child.name)

	field.queue_free()
	await physics_frame


func _test_game_no_longer_owns_spawn_wave(failures: Array[String]) -> void:
	var source := FileAccess.get_file_as_string(GAME_SCRIPT)
	if source.contains("func _spawn_wave"):
		failures.append("Game ownership: scripts/game.gd must no longer define _spawn_wave()")


## The field only *seeds* its rocks; `game.gd` is what makes them count. Until
## this test, nothing in the suite destroyed a field-parented asteroid inside a
## running game: `_test_field_seeding_keeps_asteroid_group_membership` above
## seeds a bare field outside any Game, `test_asteroid_collisions` frees every
## field rock before firing, and `test_ship_systems` drives
## `_on_asteroid_field_cleared` directly rather than through the signal. So
## every wire `_place_sector_content` runs -- scoring, credits, splitting, and
## the field-clear refuel -- could be cut and the whole suite would stay green,
## while #48's "existing scoring, splitting and bounds wiring continue to work"
## acceptance criterion silently stopped holding for the only asteroids the
## shipped game now starts with.
func _test_a_field_rock_scores_splits_and_refuels(failures: Array[String]) -> void:
	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	game.auto_start = false  # Set before add_child: _ready() reads it.
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	# A field may be placed on top of the ship's start at the sector centre, and
	# a hull that runs out mid-test would clear `play_active` and make every
	# assertion below fail for a reason that has nothing to do with the wiring.
	game.player_ship.set_invulnerable(true)

	var fields: Array[Node2D] = game.sector.get_fields()
	if fields.is_empty():
		failures.append("Field wiring: starting a run placed no asteroid fields")
		await _free_game(game)
		return

	var field: Node2D = fields[0]
	var rocks := _field_rocks(field)
	if rocks.is_empty():
		failures.append("Field wiring: field %s seeded no asteroids" % field.field_name)
		await _free_game(game)
		return

	# An empty tank is the only state a top-up is visible in: reset_systems()
	# hands every run a full one and refuel() clamps at max_fuel, so a working
	# and a severed field_cleared wire both read 100.
	var systems: Node = game.ship_systems
	systems.consume_fuel(systems.max_fuel / systems.fuel_burn_per_second)
	if systems.fuel > 0.0:
		failures.append("Field wiring: the tank should start this test empty, holds %f" % systems.fuel)

	var score_before: int = game.score
	var credits_before: int = systems.credits
	var counted_before: int = field.get_active_asteroid_count()
	var splits_before := _entity_rock_count(game)

	rocks[0].handle_bullet_hit(null)
	await physics_frame
	await physics_frame

	if game.score <= score_before:
		failures.append(
			"Field wiring: destroying a field rock scored nothing -- score stayed at %d"
			% game.score
		)
	if systems.credits <= credits_before:
		failures.append(
			"Field wiring: destroying a field rock paid no credits -- stayed at %d"
			% systems.credits
		)
	if field.get_active_asteroid_count() != counted_before - 1:
		failures.append(
			"Field wiring: the field counts %d rocks after one was destroyed, expected %d"
			% [field.get_active_asteroid_count(), counted_before - 1]
		)
	if _entity_rock_count(game) <= splits_before:
		failures.append("Field wiring: a destroyed large field rock spawned no split children")

	for rock in _field_rocks(field):
		rock.handle_bullet_hit(null)
	await physics_frame
	await physics_frame

	if not field.is_cleared():
		failures.append(
			"Field wiring: the field still counts %d rocks after every one was destroyed"
			% field.get_active_asteroid_count()
		)
	if systems.fuel <= 0.0:
		failures.append(
			"Field wiring: clearing a field returned no fuel -- the field_cleared wire is cut"
		)

	await _free_game(game)


func _field_rocks(field: Node2D) -> Array[Area2D]:
	var rocks: Array[Area2D] = []
	for child in field.get_children():
		if child is Area2D and child.is_in_group("asteroids") and not child.is_queued_for_deletion():
			rocks.append(child)
	return rocks


## Splits are parented to Entities, not to the field the rock came from, so the
## only place a new split child shows up is Entities' asteroid children.
func _entity_rock_count(game: Node) -> int:
	var count := 0
	for child in game.entities.get_children():
		if child.is_in_group("asteroids") and not child.is_queued_for_deletion():
			count += 1
	return count


func _free_game(game: Node) -> void:
	root.remove_child(game)
	game.free()
	await physics_frame


## `_place_sector_content` connects `field_cleared` to the refuel *before* it
## calls `seed_field`, so anything the field emits while seeding is paid out
## before the run has started. A field whose `asteroid_budget` is 0 -- a legal
## value on the exported SectorDefinition, and the same path a null
## `asteroid_scene` takes -- emitted on exactly that beat, handing the player
## `field_clear_refuel` per field for a sector nobody had touched: the shipped
## five fields at a quarter tank each is more than the whole 100-unit tank the
## refuel is deliberately scoped to stay under, collected before the first
## shot. Seeding is not a clear. `is_cleared()` still reports the *state* for
## anything that polls; the signal marks only the transition a destroyed
## asteroid makes.
func _test_seeding_an_empty_field_is_not_a_clear(failures: Array[String]) -> void:
	var field := (load(ASTEROID_FIELD_SCENE) as PackedScene).instantiate()
	field.field_radius = 200.0
	field.asteroid_budget = 0
	root.add_child(field)

	var clears: Array[Node2D] = []
	field.field_cleared.connect(func(cleared: Node2D) -> void: clears.append(cleared))

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var visual_assets: Array[Resource] = []
	field.seed_field(rng, load(ASTEROID_SCENE) as PackedScene, visual_assets)

	if not clears.is_empty():
		failures.append(
			"Empty field: seeding a 0-budget field emitted field_cleared %d time(s) --"
			% clears.size()
			+ " that pays the field-clear refuel before the run starts"
		)
	if not field.is_cleared():
		failures.append("Empty field: a field holding no asteroids must still report is_cleared()")

	field.queue_free()
	await physics_frame
