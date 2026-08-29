extends SceneTree


const ASTEROID_FIELD_SCENE := "res://scenes/world/AsteroidField.tscn"
const ASTEROID_SCENE := "res://scenes/entities/Asteroid.tscn"
const GAME_SCENE := "res://scenes/game/Game.tscn"

const TEST_GROUP := &"activation_test_entities"
const RADIUS := 500.0
## Physics frames the budget check runs the shipped sector for. Two seconds at
## 60Hz -- long enough for the camera's look-ahead to settle and for every
## awake rock to have resolved overlaps many times over.
const BUDGET_FRAMES := 120
## Discarded frames run before every measurement. The runs are compared against
## each other, so anything that makes one of them systematically more expensive
## -- shader compilation, the physics server growing its broadphase, the first
## pass through each script -- shows up as a saving that is really just
## warm-up.
##
## 180 rather than 60 because 60 is not past it. Measured on the shipped sector
## at a fixed workload, per-60-frame means: 1.10, **6.36**, 0.67, 0.63, 0.66,
## 0.69, ... -- a one-off spike lands in frames 60-119 and steady state does
## not arrive until frame ~120. A 60-frame warm-up puts that spike inside the
## first measurement window, and at 60 the same workload measured twice in a
## row came out 2.97 ms then 0.70 ms. That 2.2 ms of position penalty is larger
## than the entire saving being measured, so whichever run went first lost:
## reversing the order reversed the verdict. At 180 the same A/A pair agrees to
## within 2-10% and the activated run is the cheaper one in both orders.
## `BUDGET_DRIFT_TOLERANCE` is what keeps that true.
const BUDGET_WARMUP_FRAMES := 180
## How far apart the two identical activated runs may be before the comparison
## against the control stops meaning anything. The pathology this guards was
## 320%; the residual at BUDGET_WARMUP_FRAMES is 2-10%. Set between the two,
## nearer the pathology, so a loaded CI box does not flake but a warm-up that
## has stopped being long enough is caught.
const BUDGET_DRIFT_TOLERANCE := 0.5
## Frames `_park_camera` will wait for the drawn view to catch up with the
## camera node before calling the setup broken.
const PARK_TIMEOUT_FRAMES := 40

## Games stood up so far. Only `_test_the_focus_is_on_the_ship_from_the_first_frame`
## reads it, and only to refuse to report a pass it cannot back up.
var _games_instanced: int = 0


func _init() -> void:
	var failures: Array[String] = []

	# First, and it has to stay first -- it is the only case that needs a
	# Camera2D that has never been current in this process. It says so itself
	# if it is moved.
	await _test_the_focus_is_on_the_ship_from_the_first_frame(failures)
	await _test_distant_entity_sleeps(failures)
	await _test_returning_focus_fully_restores_the_entity(failures)
	await _test_boundary_does_not_oscillate(failures)
	await _test_deactivation_never_frees_or_ungroups(failures)
	await _test_is_within_counts_the_entity_extent(failures)
	await _test_field_asteroids_stop_simulating_while_asleep(failures)
	await _test_game_sleeps_distant_fields_from_the_camera(failures)
	await _test_a_rock_that_drifted_out_of_its_field_simulates_on_its_own(failures)
	await _test_a_split_child_sleeps_once_the_camera_leaves_it(failures)
	await _test_activation_follows_the_view_not_the_camera_node(failures)
	await _test_full_sector_survives_a_frame_budget_run(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL ACTIVATION TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


func _make_entity(at: Vector2) -> Node2D:
	var entity := Node2D.new()
	entity.position = at
	root.add_child(entity)
	entity.add_to_group(TEST_GROUP)
	return entity


## Park the camera at a point and wait for the *view* to arrive there, rather
## than assuming it has.
##
## Assigning `global_position` moves the camera node and leaves the drawn view
## behind: `FollowCamera` enables position smoothing, and for the first frames
## after a scene enters the tree Camera2D keeps publishing its previous
## transform even through a `reset_smoothing()`. Activation is measured from
## the view -- see `Game._get_activation_focus()` -- so a test that parked the
## node and read the result two frames later would be asserting against a
## state the setup had not reached. That is the shape of bug this suite's own
## budget control already had once; it does not get to come back in the
## fixture.
##
## Polls for arrival and reports if it never happens, so a silent non-arrival
## fails loudly instead of turning some later assertion into a mystery.
## Every Game this suite stands up goes through here, so
## `_test_the_focus_is_on_the_ship_from_the_first_frame` can tell whether it
## still has the cold process it needs. See that test.
func _make_game() -> Node:
	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	game.auto_start = false
	_games_instanced += 1
	return game


func _park_camera(game: Node, at: Vector2, failures: Array[String], label: String) -> void:
	game.follow_camera.set_target(null)
	game.follow_camera.global_position = at
	game.follow_camera.reset_smoothing()

	# The view never coincides exactly with the camera node: FollowCamera's
	# drag margins hold it a fixed fraction of a screen behind. Arrival means
	# "within the margin the drag can account for", not "equal".
	var tolerance: float = root.get_visible_rect().size.length() * 0.25

	for _step in PARK_TIMEOUT_FRAMES:
		await physics_frame
		if game._get_activation_focus().distance_to(at) <= tolerance:
			# One more frame for `Game`'s activation pass to read the arrived
			# view: `Game` is the camera's parent, so its _physics_process runs
			# first and sees the previous frame's focus.
			await physics_frame
			return

	failures.append(
		"%s: the view never reached the parked point -- it is %f away after %d frames, so nothing after this proves anything"
		% [label, game._get_activation_focus().distance_to(at), PARK_TIMEOUT_FRAMES]
	)


func _free_entity(entity: Node2D) -> void:
	entity.remove_from_group(TEST_GROUP)
	entity.queue_free()
	await process_frame


func _test_distant_entity_sleeps(failures: Array[String]) -> void:
	var entity := _make_entity(Vector2(4000.0, 0.0))
	await process_frame

	var active := Activation.update_group(TEST_GROUP, Vector2.ZERO, RADIUS)

	if active != 0:
		failures.append("Distant sleep: update_group reported %d active entities, expected 0" % active)
	if entity.process_mode != Node.PROCESS_MODE_DISABLED:
		failures.append("Distant sleep: entity is still processing (process_mode %d)" % entity.process_mode)
	if entity.visible:
		failures.append("Distant sleep: entity is still visible")
	if Activation.is_active(entity):
		failures.append("Distant sleep: entity still reports itself active")

	await _free_entity(entity)


## The important case. A permanently frozen entity is the failure mode that
## makes a returning player find a dead sector, so the restore is asserted
## against the exact state the entity had before it ever slept.
func _test_returning_focus_fully_restores_the_entity(failures: Array[String]) -> void:
	var entity := _make_entity(Vector2(4000.0, 0.0))
	entity.process_mode = Node.PROCESS_MODE_PAUSABLE
	await process_frame

	Activation.update_group(TEST_GROUP, Vector2.ZERO, RADIUS)
	entity.position = Vector2(100.0, 0.0)
	var active := Activation.update_group(TEST_GROUP, Vector2.ZERO, RADIUS)

	if active != 1:
		failures.append("Restore: update_group reported %d active entities, expected 1" % active)
	if entity.process_mode != Node.PROCESS_MODE_PAUSABLE:
		failures.append(
			"Restore: process_mode came back as %d, expected the pre-sleep PROCESS_MODE_PAUSABLE"
			% entity.process_mode
		)
	if not entity.visible:
		failures.append("Restore: entity was not made visible again")
	if not Activation.is_active(entity):
		failures.append("Restore: entity still reports itself asleep")

	# A restored entity must leave no bookkeeping behind, or the next sleep
	# would restore a stale snapshot.
	if entity.has_meta(&"activation_process_mode") or entity.has_meta(&"activation_visible"):
		failures.append("Restore: sleep metadata outlived the wake")

	# And it must survive a second round trip -- one-shot restores are the
	# subtle version of the same freeze.
	entity.position = Vector2(4000.0, 0.0)
	Activation.update_group(TEST_GROUP, Vector2.ZERO, RADIUS)
	entity.position = Vector2(100.0, 0.0)
	Activation.update_group(TEST_GROUP, Vector2.ZERO, RADIUS)

	if entity.process_mode != Node.PROCESS_MODE_PAUSABLE or not entity.visible:
		failures.append("Restore: second sleep/wake cycle left the entity frozen")

	await _free_entity(entity)


## An entity parked in the hysteresis band must hold whatever state it is in.
## Without the band it flips every physics frame and the bookkeeping costs more
## than the sleep saves.
func _test_boundary_does_not_oscillate(failures: Array[String]) -> void:
	var entity := _make_entity(Vector2(RADIUS + 1.0, 0.0))
	await process_frame

	# Starts awake: just outside the wake radius but inside the sleep radius,
	# so it must stay awake for as long as it sits there.
	for frame in 30:
		Activation.update_group(TEST_GROUP, Vector2.ZERO, RADIUS)
		if not Activation.is_active(entity):
			failures.append("Hysteresis: awake entity slept at frame %d while inside the sleep radius" % frame)
			break

	# Push it out, let it sleep, then bring it back to the same band position.
	# It must now stay asleep, because waking needs the narrower radius.
	entity.position = Vector2(4000.0, 0.0)
	Activation.update_group(TEST_GROUP, Vector2.ZERO, RADIUS)
	entity.position = Vector2(RADIUS + 1.0, 0.0)

	for frame in 30:
		Activation.update_group(TEST_GROUP, Vector2.ZERO, RADIUS)
		if Activation.is_active(entity):
			failures.append("Hysteresis: sleeping entity woke at frame %d inside the hysteresis band" % frame)
			break

	await _free_entity(entity)


func _test_deactivation_never_frees_or_ungroups(failures: Array[String]) -> void:
	var entity := _make_entity(Vector2(9000.0, 9000.0))
	var child := Node2D.new()
	entity.add_child(child)
	await process_frame

	Activation.update_group(TEST_GROUP, Vector2.ZERO, RADIUS)
	await process_frame
	await physics_frame

	if not is_instance_valid(entity):
		failures.append("Deactivation: the entity was freed")
		return
	if entity.is_queued_for_deletion():
		failures.append("Deactivation: the entity was queued for deletion")
	if not entity.is_in_group(TEST_GROUP):
		failures.append("Deactivation: the entity was dropped from its group")
	if entity.get_parent() == null:
		failures.append("Deactivation: the entity was removed from the tree")
	if not is_instance_valid(child) or child.get_parent() != entity:
		failures.append("Deactivation: the entity's children did not survive")

	await _free_entity(entity)


## is_within measures to the entity's edge, not its origin: a field whose
## centre is just out of range still has rocks inside it, and waking on the
## centre alone pops half a field in ahead of the player.
func _test_is_within_counts_the_entity_extent(failures: Array[String]) -> void:
	var field := (load(ASTEROID_FIELD_SCENE) as PackedScene).instantiate() as Node2D
	field.field_radius = 300.0
	field.asteroid_budget = 0
	field.position = Vector2(RADIUS + 200.0, 0.0)
	root.add_child(field)
	await process_frame

	if not Activation.is_within(field, Vector2.ZERO, RADIUS):
		failures.append("Extent: a field overlapping the activation circle was reported outside it")

	field.position = Vector2(RADIUS + 400.0, 0.0)
	if Activation.is_within(field, Vector2.ZERO, RADIUS):
		failures.append("Extent: a field clear of the activation circle was reported inside it")

	var bare := Node2D.new()
	bare.position = Vector2(RADIUS + 1.0, 0.0)
	root.add_child(bare)
	if Activation.is_within(bare, Vector2.ZERO, RADIUS):
		failures.append("Extent: an entity with no extent was reported inside the radius")

	bare.queue_free()
	field.queue_free()
	await process_frame


## Field granularity is the point of the whole issue: one distance check per
## field, and every rock inside it stops running _physics_process.
func _test_field_asteroids_stop_simulating_while_asleep(failures: Array[String]) -> void:
	var field := (load(ASTEROID_FIELD_SCENE) as PackedScene).instantiate() as Node2D
	field.field_radius = 200.0
	field.asteroid_budget = 4
	field.position = Vector2(6000.0, 0.0)
	root.add_child(field)
	await process_frame

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	field.seed_field(rng, load(ASTEROID_SCENE) as PackedScene, [] as Array[Resource])
	await physics_frame

	var rocks := _field_asteroids(field)
	if rocks.is_empty():
		failures.append("Field sleep: the field seeded no asteroids to test")
		field.queue_free()
		await process_frame
		return

	Activation.set_entity_active(field, false)
	await physics_frame

	var frozen := {}
	for rock in rocks:
		frozen[rock] = rock.global_position

	for _step in 10:
		await physics_frame

	for rock in rocks:
		if not is_instance_valid(rock):
			failures.append("Field sleep: a sleeping field's asteroid was freed")
			continue
		if not rock.global_position.is_equal_approx(frozen[rock]):
			failures.append("Field sleep: asteroid %s kept moving while its field slept" % rock.name)
		if rock.is_visible_in_tree():
			failures.append("Field sleep: asteroid %s is still drawn while its field sleeps" % rock.name)
		if rock.monitoring or rock.monitorable:
			failures.append("Field sleep: asteroid %s can still be hit while its field sleeps" % rock.name)
		if not rock.is_in_group("asteroids"):
			failures.append("Field sleep: asteroid %s lost its group while asleep" % rock.name)

	Activation.set_entity_active(field, true)
	for _step in 10:
		await physics_frame

	var moved := false
	for rock in rocks:
		if not is_instance_valid(rock):
			continue
		if not rock.monitoring or not rock.monitorable:
			failures.append("Field wake: asteroid %s did not get its collision back" % rock.name)
		if not rock.is_visible_in_tree():
			failures.append("Field wake: asteroid %s stayed hidden" % rock.name)
		if not rock.global_position.is_equal_approx(frozen[rock]):
			moved = true

	if not moved:
		failures.append("Field wake: no asteroid resumed drifting after the field woke")

	field.queue_free()
	await process_frame


## The shipped game must drive activation from the camera, not the ship: the
## camera leads the ship by up to max_look_ahead, and simulating what the ship
## is next to instead of what the player is looking at is the whole bug.
func _test_game_sleeps_distant_fields_from_the_camera(failures: Array[String]) -> void:
	var game := _make_game()
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	var fields: Array[Node2D] = game.sector.get_fields()
	if fields.size() < 2:
		failures.append("Game activation: the shipped sector placed %d fields, expected at least 2" % fields.size())
		game.queue_free()
		await process_frame
		return

	# Park the camera on the first field and let activation run.
	var near_field: Node2D = fields[0]
	await _park_camera(game, near_field.global_position, failures, "Game activation")

	if not Activation.is_active(near_field):
		failures.append("Game activation: the field under the camera is asleep")

	var slept := 0
	for field in fields:
		var distance: float = field.global_position.distance_to(near_field.global_position)
		if distance > game.activation_radius * Activation.SLEEP_SCALE + field.field_radius:
			if Activation.is_active(field):
				failures.append("Game activation: field %s is %f away and still awake" % [field.field_name, distance])
			else:
				slept += 1

	if slept == 0:
		failures.append("Game activation: no field slept -- the sector is too small for the radius to mean anything")

	# Fly the camera to a sleeping field and confirm it comes back.
	var far_field: Node2D = null
	for field in fields:
		if not Activation.is_active(field):
			far_field = field
			break

	if far_field != null:
		await _park_camera(game, far_field.global_position, failures, "Game activation")

		if not Activation.is_active(far_field):
			failures.append("Game activation: field %s never woke when the camera arrived" % far_field.field_name)
		if far_field.process_mode == Node.PROCESS_MODE_DISABLED:
			failures.append("Game activation: field %s woke but is still disabled" % far_field.field_name)

	game.queue_free()
	await process_frame


## A rock is untethered from the moment it exists: `asteroid.gd` integrates its
## own velocity and `_contain_in_sector()` clamps it to the SECTOR, not to the
## field it was scattered in. So a field's true reach grows without bound while
## `field_radius` stays frozen at its spawn value, and activation -- which is
## field-granular and measured from the field CENTRE -- hands a far-flung rock
## the sleep state of a point it is nowhere near.
##
## Parked exactly on such a rock the player gets an asteroid at the dead centre
## of the screen that is invisible, frozen, and cannot be hit or hit them, and
## that materialises on top of them the moment the field's centre drifts back
## into range. That is the mirror image of the failure this issue exists to
## prevent, so it is asserted here rather than left to the field's extent.
func _test_a_rock_that_drifted_out_of_its_field_simulates_on_its_own(failures: Array[String]) -> void:
	var game := _make_game()
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	var fields: Array[Node2D] = game.sector.get_fields()
	if fields.is_empty():
		failures.append("Drifted rock: the shipped sector placed no fields")
		game.queue_free()
		await process_frame
		return

	var field: Node2D = fields[0]
	var rocks := _field_asteroids(field)
	if rocks.is_empty():
		failures.append("Drifted rock: field %s seeded no asteroids" % field.field_name)
		game.queue_free()
		await process_frame
		return

	# Park the camera on the field first. A rock can only drift while its field
	# is awake -- a slept field is PROCESS_MODE_DISABLED, so its rocks are not
	# integrating either -- and starting from a slept field would set up a
	# state the running game cannot reach.
	await _park_camera(game, field.global_position, failures, "Drifted rock")

	if not Activation.is_active(field):
		failures.append("Drifted rock: the field under the camera never woke, so nothing could drift")
		game.queue_free()
		await process_frame
		return

	# Drift the rock toward the sector centre, so the displacement cannot be
	# undone by the boundary containment that would fire near an edge.
	var rock: Area2D = rocks[0]
	var inward: Vector2 = game.sector.get_center() - field.global_position
	var direction := inward.normalized() if inward.length() > 1.0 else Vector2.RIGHT
	rock.global_position = field.global_position + direction * 2500.0
	await physics_frame
	await physics_frame

	# Park the camera exactly on the rock. Its field is now far outside the
	# activation radius and must sleep; the rock the player is looking at
	# must not.
	await _park_camera(game, rock.global_position, failures, "Drifted rock")

	if not is_instance_valid(rock):
		failures.append("Drifted rock: the rock was freed before it could be measured")
		game.queue_free()
		await process_frame
		return

	var separation: float = rock.global_position.distance_to(field.global_position)
	var field_reach: float = game.activation_radius * Activation.SLEEP_SCALE + field.field_radius
	if separation <= field_reach:
		failures.append(
			"Drifted rock: the rock is %f from its field, inside the field's %f reach -- the setup never left the field"
			% [separation, field_reach]
		)
	if Activation.is_active(field):
		failures.append(
			"Drifted rock: field %s is still awake at %f away, so the rock proves nothing"
			% [field.field_name, separation]
		)

	if not rock.can_process():
		failures.append(
			"Drifted rock: a rock at the centre of the screen is frozen, inheriting its field's sleep from %f away"
			% separation
		)
	if not rock.is_visible_in_tree():
		failures.append("Drifted rock: a rock at the centre of the screen is invisible")
	if not rock.monitoring or not rock.monitorable:
		failures.append("Drifted rock: a rock at the centre of the screen can neither be hit nor hit the player")
	if not rock.is_in_group("asteroids"):
		failures.append("Drifted rock: the rock lost its asteroids group")

	game.queue_free()
	await process_frame


## A split child is parented to `Entities`, not to the field whose rock it came
## from, so no field's sleep state is an answer about it. It has to be enrolled
## as a loose rock or it simulates for the rest of the run at any distance.
##
## This is the population, not an edge case: at the shipped `asteroid_budget`
## of 4 and `split_child_count` of 2, clearing a single field yields 8 medium
## plus 16 small rocks -- more permanently-awake rocks than the 20 the entire
## sector starts with.
func _test_a_split_child_sleeps_once_the_camera_leaves_it(failures: Array[String]) -> void:
	var game := _make_game()
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	var centre: Vector2 = game.sector.get_center()
	# Spawned through the same call a split goes through, so the test cannot
	# pass by a route the game does not take.
	var fragment: Area2D = game._spawn_asteroid(1, centre, Vector2(30.0, 0.0))
	await physics_frame

	if not fragment.is_in_group("asteroids"):
		failures.append("Split child: the fragment is not in the asteroids group")

	# Park the view in the opposite corner of the sector. Inset by half a
	# viewport because that is as far as the view can be taken: the camera
	# limits `Game._apply_sector_bounds()` installs stop the drawn rect at the
	# sector edge, so a park on the corner itself would never arrive.
	var bounds: Rect2 = game.sector.get_bounds()
	var inset: Vector2 = root.get_visible_rect().size * 0.5
	await _park_camera(game, bounds.position + inset, failures, "Split child")

	if not is_instance_valid(fragment):
		failures.append("Split child: the fragment was freed before it could be measured")
		game.queue_free()
		await process_frame
		return

	var separation: float = fragment.global_position.distance_to(game._get_activation_focus())
	if separation <= game.activation_radius * Activation.SLEEP_SCALE:
		failures.append(
			"Split child: the fragment is only %f from the focus, inside the %f sleep radius -- the setup never left it"
			% [separation, game.activation_radius * Activation.SLEEP_SCALE]
		)

	if fragment.can_process():
		failures.append(
			"Split child: a fragment %f from the view is still simulating -- it is in no activation group"
			% separation
		)
	if fragment.is_visible_in_tree():
		failures.append("Split child: a fragment %f from the view is still drawing" % separation)
	if fragment.monitoring or fragment.monitorable:
		failures.append("Split child: a fragment %f from the view is still collidable" % separation)
	if not fragment.is_in_group("asteroids"):
		failures.append("Split child: the fragment lost its asteroids group")

	# And back. A fragment that sleeps and never wakes is worse than one that
	# never slept: #49 calls a permanently frozen entity the failure mode that
	# makes a sector feel broken, and a fragment is the one rock the player has
	# already gone out of their way to create.
	await _park_camera(game, fragment.global_position, failures, "Split child")

	if not fragment.can_process():
		failures.append("Split child: the fragment never woke when the camera came back")
	if not fragment.is_visible_in_tree():
		failures.append("Split child: the fragment came back invisible")
	if not fragment.monitoring or not fragment.monitorable:
		failures.append("Split child: the fragment came back unhittable")

	game.queue_free()
	await process_frame


## Activation is measured from what is on screen, not from where the camera
## node is. `FollowCamera` smooths, drags, and is clamped to the sector by
## `apply_sector_limits()`, so at a sector corner the node sits on the corner
## while the drawn view stops half a screen inside it. Measured from the node,
## the far edge of the visible rect is a full viewport diagonal away instead of
## a half one, and a rock the player is looking at goes to sleep.
func _test_activation_follows_the_view_not_the_camera_node(failures: Array[String]) -> void:
	var game := _make_game()
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	# Fly the ship hard into a corner, so the look-ahead is saturated at the
	# same time the rendered view is clamped -- the worst case for the gap
	# between the camera node and the view.
	var bounds: Rect2 = game.sector.get_bounds()
	var corner: Vector2 = bounds.position + bounds.size
	game.player_ship.global_position = corner - Vector2(1200.0, 900.0)
	for _step in 180:
		game.player_ship.velocity = (corner - game.player_ship.global_position).normalized() * 900.0
		await physics_frame

	var view: Vector2 = root.get_visible_rect().size
	var screen_centre: Vector2 = game.follow_camera.get_screen_center_position()
	var away: Vector2 = screen_centre - game.follow_camera.global_position

	if away.length() <= view.length() * 0.25:
		failures.append(
			"View focus: the camera node and the view centre are only %f apart, so the corner never clamped and the test proves nothing"
			% away.length()
		)

	# The corner of the visible rect furthest from the camera node -- on screen,
	# and the point the two candidate focuses disagree about most.
	var direction := away.normalized() if away.length() > 1.0 else Vector2.RIGHT
	var far_visible := screen_centre + Vector2(
		signf(direction.x) * view.x * 0.5,
		signf(direction.y) * view.y * 0.5
	)

	var rock: Area2D = game._spawn_asteroid(0, far_visible, Vector2.ZERO)
	for _step in 6:
		game.player_ship.velocity = (corner - game.player_ship.global_position).normalized() * 900.0
		await physics_frame

	if not is_instance_valid(rock):
		failures.append("View focus: the rock was freed before it could be measured")
		game.queue_free()
		await process_frame
		return

	var on_screen: bool = (
		absf(rock.global_position.x - screen_centre.x) <= view.x * 0.5
		and absf(rock.global_position.y - screen_centre.y) <= view.y * 0.5
	)
	if not on_screen:
		failures.append("View focus: the rock was not placed on screen, so the assertion is vacuous")

	if not rock.can_process():
		failures.append(
			"View focus: a rock on screen is frozen -- it is %f from the camera node but only %f from the view centre"
			% [
				rock.global_position.distance_to(game.follow_camera.global_position),
				rock.global_position.distance_to(screen_centre),
			]
		)
	if not rock.is_visible_in_tree():
		failures.append("View focus: a rock on screen is invisible")
	if not rock.monitoring or not rock.monitorable:
		failures.append("View focus: a rock on screen can neither be hit nor hit the player")

	game.queue_free()
	await process_frame


## A run must not open with everything around the player asleep.
##
## Camera2D publishes nothing until it has run a frame while current, so the
## `reset_smoothing()` that `FollowCamera.set_target()` does at `_ready()` time
## does not stick: left alone the view spends the opening frames of a run at
## its top-left limit clamp, a whole sector from the ship. That was harmless
## while only the renderer read the view -- it corrects itself before anything
## is drawn -- but `Game._get_activation_focus()` now decides what to simulate
## from it, so those frames would sleep the sector around the player at every
## single start. `FollowCamera` seeds its smoothing on its first
## `_physics_process` for this.
func _test_the_focus_is_on_the_ship_from_the_first_frame(failures: Array[String]) -> void:
	# Camera2D warms up once per process, not once per camera: a Game stood up
	# after another one gets a viewport that has already had a current camera,
	# and publishes its transform immediately whether or not the seed is there.
	# So this case can only be proved from a cold process. Refuse to report a
	# pass it cannot back up rather than going quietly green in the wrong slot.
	if _games_instanced > 0:
		failures.append(
			"First frame: %d games were already stood up before this case ran, so a cold camera is gone and this proves nothing -- it must run first"
			% _games_instanced
		)
		return

	var game := _make_game()
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	var focus: Vector2 = game._get_activation_focus()
	var drift: float = focus.distance_to(game.player_ship.global_position)
	# The view is never exactly on the ship -- the drag margins hold it a fixed
	# fraction of a screen behind -- but it must be on the same screen.
	var tolerance: float = root.get_visible_rect().size.length() * 0.5

	if drift > tolerance:
		failures.append(
			"First frame: the run opens with the focus %f from the ship (tolerance %f) -- the sector around the player starts asleep"
			% [drift, tolerance]
		)

	game.queue_free()
	await process_frame


## The budget baseline later issues must not regress.
##
## Measured with Performance.TIME_PHYSICS_PROCESS, not wall clock: the headless
## main loop still paces itself at 60Hz, so timing `await physics_frame` would
## measure the tick interval and report a flat 16.6ms whatever the sector cost.
## The engine's own counter is the actual work done inside _physics_process.
##
## The assertion is structural -- fewer rocks simulating than exist, and the
## run survives -- rather than a millisecond threshold, which would be a flaky
## test on shared CI. The numbers are printed so the PR can record them.
func _test_full_sector_survives_a_frame_budget_run(failures: Array[String]) -> void:
	var game := _make_game()
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	var rocks: int = game.get_tree().get_nodes_in_group("asteroids").size()
	var fields: int = game.sector.get_fields().size()

	for _step in BUDGET_WARMUP_FRAMES:
		await physics_frame

	var activated_ms := await _measure_physics_ms(BUDGET_FRAMES)
	var awake_fields := _awake_field_count(game)
	var awake_rocks := _awake_asteroid_count(game)

	# The same workload again, back to back. Nothing about the sector changed
	# between the two, so any gap between them is the measurement's own
	# position penalty -- and the number this test exists to report is only
	# worth reporting while that penalty is small next to the saving. See
	# BUDGET_WARMUP_FRAMES for the run where it was four times the saving and
	# the reported baseline was really just "whichever ran first".
	var activated_again_ms := await _measure_physics_ms(BUDGET_FRAMES)

	# Control run: the same sector with activation defeated, which is what it
	# cost before this issue and what it would cost again if activation
	# regressed. See _measure_physics_ms_all_awake() for why it is defeated by
	# widening the radius rather than by waking the fields from here.
	var control := await _measure_physics_ms_all_awake(game, BUDGET_FRAMES)
	var all_awake_ms: float = control["ms"]
	var control_awake_rocks: int = control["awake_rocks"]

	var drift: float = (
		absf(activated_ms - activated_again_ms) / maxf(0.0001, maxf(activated_ms, activated_again_ms))
	)

	print(
		"ACTIVATION BUDGET: %d fields / %d asteroids in the sector; %d fields / %d asteroids awake; "
		% [fields, rocks, awake_fields, awake_rocks]
		+ "%.4f ms physics/frame activated vs %.4f ms all-awake (%d/%d rocks awake) over %d frames; "
		% [activated_ms, all_awake_ms, control_awake_rocks, rocks, BUDGET_FRAMES]
		+ "repeat of the activated run %.4f ms, drift %.1f%%"
		% [activated_again_ms, drift * 100.0]
	)

	# A baseline nobody can reproduce is worse than no baseline: it becomes the
	# number later issues are held to.
	if drift > BUDGET_DRIFT_TOLERANCE:
		failures.append(
			"Budget run: the same workload measured %f then %f ms -- %.1f%% apart, over the %.1f%% tolerance. The warm-up is no longer reaching steady state, so these numbers are measurement position, not workload."
			% [activated_ms, activated_again_ms, drift * 100.0, BUDGET_DRIFT_TOLERANCE * 100.0]
		)

	# The control is only evidence if it actually ran the sector awake. If
	# activation is still holding the rocks down underneath it, both numbers
	# describe the same run and the saving they bracket is noise.
	if control_awake_rocks < rocks:
		failures.append(
			"Budget control: %d of %d asteroids were awake -- the control run did not defeat activation"
			% [control_awake_rocks, rocks]
		)

	if awake_rocks >= rocks:
		failures.append(
			"Budget run: %d of %d asteroids were still simulating -- activation saved nothing"
			% [awake_rocks, rocks]
		)
	if game.get_tree().get_nodes_in_group("asteroids").size() != rocks:
		failures.append("Budget run: the sector gained or lost asteroids over the run")
	if not is_instance_valid(game.player_ship):
		failures.append("Budget run: the player ship did not survive the run")

	game.queue_free()
	await process_frame


func _measure_physics_ms(frames: int) -> float:
	var total := 0.0
	for _step in frames:
		await physics_frame
		total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	return total / float(maxi(1, frames))


## Same measurement with activation defeated, so the sector runs the way it did
## before this issue.
##
## Defeated by widening the shipped `activation_radius`, not by forcing each
## field awake between frames. `game.gd` drives activation from its own
## `_physics_process`, and the Game node is the parent of `$Sector`, so its
## pass runs *before* the fields it owns in the same frame: a wake applied from
## this loop is undone before a single rock simulates, and the control quietly
## measures the activated sector a second time. That reads as "activation saved
## nothing measurable" -- the reported saving is then just the noise between
## two identical runs. Widening the radius leaves the shipped drive itself
## holding everything awake, which is the state worth comparing against.
##
## Returns the mean ms alongside how many rocks were actually awake at the end,
## so the caller can assert the control did what it claims rather than trusting
## the number it produced.
func _measure_physics_ms_all_awake(game: Node, frames: int) -> Dictionary:
	# Larger than the 8000x6000 sector's diagonal, so every field is inside the
	# radius no matter where the camera sits.
	var saved_radius: float = game.activation_radius
	game.activation_radius = 100000.0

	for _step in BUDGET_WARMUP_FRAMES:
		await physics_frame

	var total := 0.0
	for _step in frames:
		await physics_frame
		total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	var awake_rocks := _awake_asteroid_count(game)
	game.activation_radius = saved_radius

	return {"ms": total / float(maxi(1, frames)), "awake_rocks": awake_rocks}


func _awake_asteroid_count(game: Node) -> int:
	var awake := 0
	for rock in game.get_tree().get_nodes_in_group("asteroids"):
		if rock is Node and rock.can_process():
			awake += 1
	return awake


func _awake_field_count(game: Node) -> int:
	var awake := 0
	for field in game.sector.get_fields():
		if Activation.is_active(field):
			awake += 1
	return awake


func _field_asteroids(field: Node2D) -> Array[Area2D]:
	var rocks: Array[Area2D] = []
	for child in field.get_children():
		if child is Area2D and child.is_in_group("asteroids"):
			rocks.append(child as Area2D)
	return rocks
