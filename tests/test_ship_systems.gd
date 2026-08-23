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
