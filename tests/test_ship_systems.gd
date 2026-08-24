extends SceneTree


const PLAYER_SCENE := "res://scenes/entities/PlayerShip.tscn"
const GAME_SCENE := "res://scenes/game/Game.tscn"
const SHIP_SYSTEMS := preload("res://scripts/entities/ship_systems.gd")

const SECTOR_BOUNDS := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))
const OPEN_SPACE := Vector2(4000.0, 3000.0)


## Stands in for PlayerInput so a test can hold the thrust key down.
class ThrustHeld:
	extends Node

	func get_turn_axis() -> float:
		return 0.0

	func is_thrust_pressed() -> bool:
		return true

	func is_shoot_pressed() -> bool:
		return false


func _init() -> void:
	var failures: Array[String] = []

	await _test_damage_reduces_hull_and_reports_it(failures)
	await _test_destruction_is_announced_exactly_once(failures)
	await _test_thrusting_drains_fuel_at_the_declared_rate(failures)
	await _test_an_empty_tank_never_removes_thrust(failures)
	await _test_reserve_thrust_is_announced_when_it_starts_and_ends(failures)
	await _test_a_ship_with_no_fuel_still_accelerates(failures)
	await _test_fuel_drains_only_while_thrusting(failures)
	await _test_credits_cannot_be_overspent(failures)
	await _test_repair_and_refuel_clamp_at_their_maxima(failures)
	await _test_the_game_runs_on_hull_instead_of_lives(failures)
	await _test_the_run_ends_when_the_hull_is_gone(failures)
	await _test_one_frame_of_asteroids_costs_one_hit(failures)
	await _test_a_rock_resting_on_the_ship_costs_one_hit(failures)
	await _test_a_hit_against_the_sector_wall_still_separates(failures)
	await _test_clearing_a_wave_returns_some_fuel(failures)
	await _test_the_hud_shows_hull_fuel_credits_and_reserve(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL SHIP SYSTEMS TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


func _make_systems() -> Node:
	var systems := SHIP_SYSTEMS.new()
	root.add_child(systems)
	return systems


func _test_damage_reduces_hull_and_reports_it(failures: Array[String]) -> void:
	var systems := _make_systems()
	var reports: Array[Vector2] = []
	systems.hull_changed.connect(func(current: float, maximum: float) -> void:
		reports.append(Vector2(current, maximum))
	)

	systems.apply_damage(30.0)

	if not is_equal_approx(systems.hull, 70.0):
		failures.append("Damage: hull should be 70 after 30 damage, got %f" % systems.hull)
	if reports.size() != 1:
		failures.append("Damage: expected one hull_changed report, got %d" % reports.size())
	elif not is_equal_approx(reports[0].x, 70.0) or not is_equal_approx(reports[0].y, 100.0):
		failures.append("Damage: hull_changed reported %s, expected (70, 100)" % reports[0])

	systems.queue_free()
	await process_frame


func _test_destruction_is_announced_exactly_once(failures: Array[String]) -> void:
	var systems := _make_systems()
	# A lambda captures by value, so an int counter would never leave zero.
	var destroyed_calls: Array[int] = []
	systems.destroyed.connect(func() -> void: destroyed_calls.append(1))

	systems.apply_damage(60.0)
	if not destroyed_calls.is_empty():
		failures.append("Destruction: announced while hull was still %f" % systems.hull)

	systems.apply_damage(60.0)
	systems.apply_damage(60.0)
	systems.apply_damage(1.0)

	if systems.hull > 0.0:
		failures.append("Destruction: hull should clamp at zero, got %f" % systems.hull)
	if destroyed_calls.size() != 1:
		failures.append(
			"Destruction: destroyed must fire once per run, fired %d times" % destroyed_calls.size()
		)

	systems.queue_free()
	await process_frame


func _test_thrusting_drains_fuel_at_the_declared_rate(failures: Array[String]) -> void:
	var systems := _make_systems()
	systems.fuel_burn_per_second = 4.0

	for _step in 10:
		systems.consume_fuel(0.1)

	# 10 x 0.1s at 4/s is exactly one second of burn.
	if not is_equal_approx(systems.fuel, 96.0):
		failures.append("Fuel burn: one second at 4/s should leave 96 fuel, got %f" % systems.fuel)

	systems.queue_free()
	await process_frame


func _test_an_empty_tank_never_removes_thrust(failures: Array[String]) -> void:
	var systems := _make_systems()
	systems.reserve_thrust_factor = 0.25

	if not is_equal_approx(systems.get_thrust_factor(), 1.0):
		failures.append(
			"Reserve: a full tank should give factor 1.0, got %f" % systems.get_thrust_factor()
		)

	for _step in 100:
		systems.consume_fuel(1.0)

	if systems.fuel > 0.0:
		failures.append("Reserve: tank should be empty, holds %f" % systems.fuel)

	var factor: float = systems.get_thrust_factor()
	if is_zero_approx(factor):
		failures.append("Reserve: an empty tank removed thrust entirely -- that is a soft-lock")
	if not is_equal_approx(factor, systems.reserve_thrust_factor):
		failures.append(
			"Reserve: empty tank should give factor %f, got %f"
			% [systems.reserve_thrust_factor, factor]
		)
	if systems.consume_fuel(0.1):
		failures.append("Reserve: consume_fuel must report false while running on reserve")

	systems.queue_free()
	await process_frame


func _test_reserve_thrust_is_announced_when_it_starts_and_ends(failures: Array[String]) -> void:
	var systems := _make_systems()
	var reports: Array[bool] = []
	systems.reserve_thrust_changed.connect(func(active: bool) -> void: reports.append(active))

	for _step in 100:
		systems.consume_fuel(1.0)

	if reports != [true]:
		failures.append("Reserve signal: emptying the tank should report [true], got %s" % [reports])

	systems.refuel(50.0)

	if reports != [true, false]:
		failures.append("Reserve signal: refuelling should report [true, false], got %s" % [reports])

	systems.queue_free()
	await process_frame


func _test_a_ship_with_no_fuel_still_accelerates(failures: Array[String]) -> void:
	var ship := (load(PLAYER_SCENE) as PackedScene).instantiate() as Area2D
	root.add_child(ship)
	var thrust := ThrustHeld.new()
	root.add_child(thrust)
	ship.input_source = thrust
	ship.set_sector_bounds(SECTOR_BOUNDS)
	ship.global_position = OPEN_SPACE
	ship.rotation = 0.0
	ship.velocity = Vector2.ZERO

	var systems: Node = ship.get_node("ShipSystems")
	for _step in 100:
		systems.consume_fuel(1.0)

	if systems.fuel > 0.0:
		failures.append("Dry thrust: the tank should be empty, holds %f" % systems.fuel)

	for _step in 30:
		await physics_frame

	# 30 frames of full thrust is roughly 175 px/s; a quarter of it is roughly 40.
	var speed: float = ship.velocity.length()
	if speed <= 0.0:
		failures.append("Dry thrust: a ship with no fuel did not move at all -- soft-lock")
	elif speed >= 100.0:
		failures.append(
			"Dry thrust: a dry ship reached %f px/s, which is not a reduced reserve burn" % speed
		)

	ship.queue_free()
	thrust.queue_free()
	await physics_frame


func _test_fuel_drains_only_while_thrusting(failures: Array[String]) -> void:
	var ship := (load(PLAYER_SCENE) as PackedScene).instantiate() as Area2D
	root.add_child(ship)
	ship.set_sector_bounds(SECTOR_BOUNDS)
	ship.global_position = OPEN_SPACE

	var systems: Node = ship.get_node("ShipSystems")
	var idle_fuel: float = systems.fuel

	# No input source and no held key: the ship coasts.
	for _step in 30:
		await physics_frame

	if not is_equal_approx(systems.fuel, idle_fuel):
		failures.append("Idle drain: a coasting ship burned %f fuel" % (idle_fuel - systems.fuel))

	var thrust := ThrustHeld.new()
	root.add_child(thrust)
	ship.input_source = thrust

	for _step in 30:
		await physics_frame

	if systems.fuel >= idle_fuel:
		failures.append("Thrust drain: thrusting for 30 frames burned no fuel")

	ship.queue_free()
	thrust.queue_free()
	await physics_frame


func _test_credits_cannot_be_overspent(failures: Array[String]) -> void:
	var systems := _make_systems()
	var reports: Array[int] = []
	systems.credits_changed.connect(func(amount: int) -> void: reports.append(amount))

	systems.add_credits(40)
	if systems.credits != 40:
		failures.append("Credits: expected 40 after add_credits(40), got %d" % systems.credits)

	if systems.spend_credits(60):
		failures.append("Credits: spend_credits(60) succeeded on a balance of 40")
	if systems.credits != 40:
		failures.append("Credits: a refused purchase changed the balance to %d" % systems.credits)
	if reports != [40]:
		failures.append("Credits: a refused purchase reported %s" % [reports])

	if not systems.spend_credits(40):
		failures.append("Credits: spend_credits(40) failed on a balance of exactly 40")
	if systems.credits != 0:
		failures.append("Credits: balance should be 0 after spending it all, got %d" % systems.credits)

	systems.queue_free()
	await process_frame


func _test_repair_and_refuel_clamp_at_their_maxima(failures: Array[String]) -> void:
	var systems := _make_systems()

	systems.apply_damage(10.0)
	systems.repair(500.0)
	if not is_equal_approx(systems.hull, systems.max_hull):
		failures.append("Repair: hull should clamp at %f, got %f" % [systems.max_hull, systems.hull])

	systems.consume_fuel(1.0)
	systems.refuel(500.0)
	if not is_equal_approx(systems.fuel, systems.max_fuel):
		failures.append("Refuel: fuel should clamp at %f, got %f" % [systems.max_fuel, systems.fuel])

	systems.queue_free()
	await process_frame


## True when `name` appears as a whole word in `source` outside its comments.
func _find_identifier(source: String, name: String) -> bool:
	var code_lines := PackedStringArray()
	for line in source.split("\n"):
		var comment := line.find("#")
		code_lines.append(line if comment < 0 else line.substr(0, comment))

	var identifier := RegEx.new()
	identifier.compile("\\b%s\\b" % name)
	return identifier.search("\n".join(code_lines)) != null


func _test_the_game_runs_on_hull_instead_of_lives(failures: Array[String]) -> void:
	# Comments are stripped and the match is word-bounded before this looks for
	# the identifier. game.gd is heavily annotated by repo convention, and a
	# plain substring search over the raw text would fail CI on any future
	# prose that happens to contain the letters -- "delivers", "the authority
	# lives here" -- with a message claiming the lives model is back.
	var source := FileAccess.get_file_as_string("res://scripts/game.gd")
	if source.is_empty():
		failures.append("Lives: could not read scripts/game.gd")
	elif _find_identifier(source, "lives"):
		failures.append("Lives: scripts/game.gd still declares or reads a lives identifier")

	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	# Before add_child: _ready() runs inside add_child, so setting it after
	# has already let a whole throwaway game start and fill the sector with
	# drifting asteroids -- the same ordering test_star_layer.gd documents.
	game.auto_start = false
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	if "lives" in game:
		failures.append("Lives: game.gd still exposes a lives property")

	var systems: Node = game.ship_systems
	var starting_hull: float = systems.hull
	game.player_ship.set_invulnerable(false)
	game._spawn_asteroid(0, game.player_ship.global_position, Vector2.ZERO)

	for _step in 5:
		await physics_frame

	if systems.hull >= starting_hull:
		failures.append("Hull: an asteroid collision did not damage the hull")
	if not game.play_active:
		failures.append("Hull: a single collision ended the run")

	root.remove_child(game)
	game.free()
	await physics_frame


func _test_the_run_ends_when_the_hull_is_gone(failures: Array[String]) -> void:
	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	game.auto_start = false  # Before add_child -- see the note above.
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	game.ship_systems.apply_damage(game.ship_systems.max_hull)
	await physics_frame

	if game.play_active:
		failures.append("Run end: the run continued with the hull at zero")

	root.remove_child(game)
	game.free()
	await physics_frame


## The post-damage window has to cover the frame it was opened on. Godot can
## only clear an Area2D's `monitoring` deferred, so every asteroid that began
## overlapping during the same physics step still reports in afterwards; a ship
## flying into a cluster must not be charged one full hit per asteroid.
func _test_one_frame_of_asteroids_costs_one_hit(failures: Array[String]) -> void:
	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	game.auto_start = false  # Before add_child -- see the note above.
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	var systems: Node = game.ship_systems
	game.player_ship.set_invulnerable(false)
	await physics_frame

	var starting_hull: float = systems.hull
	for _index in 3:
		game._spawn_asteroid(0, game.player_ship.global_position, Vector2.ZERO)

	for _step in 5:
		await physics_frame

	var lost: float = starting_hull - systems.hull
	if not is_equal_approx(lost, game.asteroid_collision_damage):
		failures.append(
			"Damage chaining: three asteroids in one frame cost %f hull, one hit is %f"
			% [lost, game.asteroid_collision_damage]
		)

	root.remove_child(game)
	game.free()
	await physics_frame


func _test_the_hud_shows_hull_fuel_credits_and_reserve(failures: Array[String]) -> void:
	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	game.auto_start = false  # Before add_child -- see the note above.
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	var hud: CanvasLayer = game.hud
	game.ship_systems.apply_damage(25.0)
	game.ship_systems.add_credits(7)
	await physics_frame

	if not is_equal_approx(hud.hull_bar.value, 75.0):
		failures.append("HUD: hull bar shows %f after 25 damage" % hud.hull_bar.value)
	if not hud.credits_label.text.contains("7"):
		failures.append("HUD: credits readout is '%s' after earning 7" % hud.credits_label.text)
	if not hud.sector_label.text.to_lower().contains("vega_7"):
		failures.append("HUD: sector label is '%s', expected the sector name" % hud.sector_label.text)
	if not hud.sector_label.text.contains("1729"):
		failures.append("HUD: sector label is '%s', expected the seed" % hud.sector_label.text)
	if hud.reserve_label.visible:
		failures.append("HUD: the reserve indicator is showing on a full tank")

	for _step in 100:
		game.ship_systems.consume_fuel(1.0)
	await physics_frame

	if not hud.reserve_label.visible:
		failures.append("HUD: reserve thrust is active but nothing tells the player")
	if hud.fuel_bar.value > 0.0:
		failures.append("HUD: fuel bar shows %f on an empty tank" % hud.fuel_bar.value)

	root.remove_child(game)
	game.free()
	await physics_frame


## Start a game with no asteroids in it, so a test owns every rock on screen.
func _start_empty_game(window_seconds: float = -1.0) -> Node:
	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	game.auto_start = false  # Before add_child -- see the note above.
	if window_seconds > 0.0:
		game.damage_invulnerability_seconds = window_seconds
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	# Freed rather than destroyed: `handle_bullet_hit` would pay credits and
	# spawn splits, and this is meant to be an empty sector, not a cleared one.
	for asteroid in get_nodes_in_group("asteroids"):
		asteroid.free()
	await physics_frame
	return game


func _end_game_scene(game: Node) -> void:
	root.remove_child(game)
	game.free()
	await physics_frame


## A rock that has settled on the ship must cost one hit, not one per window.
##
## The post-damage window only stops the hit being counted. When it closes,
## `set_invulnerable(false)` switches `monitoring` back on, Godot re-reports the
## pair -- which never stopped overlapping, because nothing moved either body --
## and charges the hull again. Measured on the unfixed head, one large rock
## drifting at 6 px/s took 75 hull in five seconds and was still sitting on the
## ship at the end. A ship out of fuel limps at quarter acceleration and cannot
## leave; that is a dead run with no input that changes it.
func _test_a_rock_resting_on_the_ship_costs_one_hit(failures: Array[String]) -> void:
	# A short window keeps the suite quick; the timer is real seconds. Three
	# windows fit inside the 1.5s below, so an unresolved overlap bills three
	# times over.
	var game: Node = await _start_empty_game(0.4)
	var systems: Node = game.ship_systems
	var player: Area2D = game.player_ship
	player.set_invulnerable(false)
	await physics_frame

	var starting_hull: float = systems.hull
	var rock: Area2D = game._spawn_asteroid(0, player.global_position, Vector2(6.0, 0.0))

	for _step in 90:
		await physics_frame

	var lost: float = starting_hull - systems.hull
	if not is_equal_approx(lost, game.asteroid_collision_damage):
		failures.append(
			"Repeat damage: one resting rock cost %f hull over three windows, one hit is %f"
			% [lost, game.asteroid_collision_damage]
		)
	if not game.play_active:
		failures.append("Repeat damage: one rock ended the run by hitting the ship repeatedly")

	if not is_instance_valid(rock):
		failures.append("Repeat damage: the rock vanished; a hit should deflect it, not consume it")
	elif rock.get_overlapping_areas().has(player):
		# The engine's own answer, not a distance guess: this overlap is exactly
		# what `area_entered` re-reports the moment the window closes.
		failures.append(
			"Repeat damage: the rock is still overlapping the ship %f px away once the window closed"
			% rock.global_position.distance_to(player.global_position)
		)

	await _end_game_scene(game)


## Same defect, at the sector edge -- where deflecting the rock cannot work on
## its own, because the rock's own containment clamps it straight back onto the
## ship. Every hit still has to end with the two apart.
##
## Counted per hit rather than as a hull total, deliberately: a ship this close
## to the edge is also being shoved inwards by the soft boundary of #46, fast
## enough to fly back into the rock it just knocked away. Those are real
## collisions with real input available, and lumping them into one number would
## measure the boundary push instead of the thing under test.
func _test_a_hit_against_the_sector_wall_still_separates(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game(0.4)
	var systems: Node = game.ship_systems
	var player: Area2D = game.player_ship
	var bounds: Rect2 = game.sector.get_bounds()
	player.global_position = bounds.position + Vector2(2.0, 2.0)
	player.velocity = Vector2.ZERO
	player.set_invulnerable(false)
	await physics_frame

	# Between the ship and the corner, so "away from the ship" is into the wall.
	var rock: Area2D = game._spawn_asteroid(0, player.global_position - Vector2(30.0, 0.0), Vector2.ZERO)
	var hits := 0
	var unresolved := 0
	var hull_before_frame: float = systems.hull

	for _step in 60:
		await physics_frame

		if systems.hull >= hull_before_frame:
			continue

		hits += 1
		# A physics step is what refreshes an Area2D's overlap list, so ask it
		# one step after the hit rather than in the middle of the step that
		# resolved it, where the answer is still the pre-collision one.
		await physics_frame
		if is_instance_valid(rock) and rock.get_overlapping_areas().has(player):
			unresolved += 1
		hull_before_frame = systems.hull

	if hits == 0:
		failures.append("Wall pin: a rock spawned on the ship at the sector edge never damaged it")
	if unresolved > 0:
		failures.append(
			"Wall pin: %d of %d hits at the sector edge left the rock sitting on the ship,"
			% [unresolved, hits]
			+ " which bills the hull again every window"
		)

	await _end_game_scene(game)


## Fuel has to come back from somewhere before #54 lands.
##
## `max_fuel / fuel_burn_per_second` is 25 seconds of thrust for a whole run,
## and nothing in the game calls `refuel()`: `reset_systems()` runs only on a
## new game. Without a top-up, reserve thrust is not a setback but the terminal
## state of every run -- quarter acceleration for the rest of it, against waves
## that keep getting faster. A wave clear returns part of a tank, never all of
## it: stations are #54's job and must stay worth flying to.
func _test_clearing_a_wave_returns_some_fuel(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var systems: Node = game.ship_systems
	var reserve_reports: Array[bool] = []

	for _step in 100:
		systems.consume_fuel(1.0)

	if systems.fuel > 0.0:
		failures.append("Wave refuel: the tank should start this test empty, holds %f" % systems.fuel)

	systems.reserve_thrust_changed.connect(func(active: bool) -> void: reserve_reports.append(active))
	var wave_before: int = game.wave
	game._check_wave_cleared()
	await physics_frame

	if game.wave <= wave_before:
		failures.append("Wave refuel: an empty sector did not advance the wave")
	if systems.fuel <= 0.0:
		failures.append(
			"Wave refuel: clearing a wave left the tank dry -- every run is locked on reserve"
		)
	if systems.fuel > systems.max_fuel * 0.5:
		# Deliberately a bound on the design rather than the exact constant:
		# a wave clear is a top-up, so that docking at a station in #54 is still
		# the thing worth crossing the sector for. Tuning the amount is free;
		# turning it into a full tank is the change this refuses.
		failures.append(
			"Wave refuel: a wave clear returned %f of a %f tank; stations (#54) must stay the"
			% [systems.fuel, systems.max_fuel]
			+ " primary refuel"
		)
	if reserve_reports != [false]:
		failures.append(
			"Wave refuel: reserve thrust should end when fuel returns, reported %s" % [reserve_reports]
		)

	await _end_game_scene(game)
