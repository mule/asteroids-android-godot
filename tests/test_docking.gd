## Docking, station services, and the two ways a station touches a ship.
##
## A station is the only thing in the sector that is both an obstacle and a
## destination, so almost every test here is about keeping those two apart:
## the hull damages, the dock zone docks, and nothing may confuse them.
extends SceneTree


const GAME_SCENE := "res://scenes/game/Game.tscn"
const STATION_SCENE := "res://scenes/entities/SpaceStation.tscn"


func _init() -> void:
	var failures: Array[String] = []

	await _test_a_slow_approach_docks(failures)
	await _test_a_fast_approach_does_not_dock(failures)
	await _test_docking_zeroes_velocity_and_disables_controls(failures)
	await _test_repair_costs_credits_and_raises_hull(failures)
	await _test_repair_fails_cleanly_without_credits(failures)
	await _test_refuel_costs_credits_and_fills_the_tank(failures)
	await _test_refuel_fails_cleanly_without_credits(failures)
	await _test_a_repair_after_the_run_ended_takes_no_credits(failures)
	await _test_undocking_restores_control_and_does_not_redock(failures)
	await _test_undocking_is_never_gated_on_payment(failures)
	await _test_the_station_hull_damages_the_ship(failures)
	await _test_the_dock_zone_alone_does_not_damage_the_ship(failures)
	await _test_the_dock_panel_never_pauses_the_tree(failures)
	await _test_pause_still_works_after_a_dock_panel_was_used(failures)
	await _test_a_service_that_cannot_be_bought_is_not_offered(failures)
	await _test_a_deficit_under_one_point_is_not_offered(failures)
	await _test_pausing_stands_the_dock_panel_down(failures)
	await _test_stations_are_placed_in_the_sector_clear_of_the_player(failures)
	await _test_stations_are_placed_clear_of_the_asteroid_fields(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL DOCKING TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


## A started game holding nothing the test did not put there: no asteroids to
## collide with the ship mid-test, and no randomly placed stations competing
## with the one each test positions itself.
func _start_empty_game() -> Node:
	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	# Before add_child: _ready() runs inside add_child, so setting it after has
	# already let a throwaway run fill the sector -- same ordering the star
	# layer and ship systems suites document.
	game.auto_start = false
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	for asteroid in get_nodes_in_group("asteroids"):
		asteroid.free()
	for station in get_nodes_in_group("stations"):
		station.free()
	await physics_frame
	return game


func _end_game_scene(game: Node) -> void:
	root.remove_child(game)
	game.free()
	await physics_frame


## One station, at a known offset from the player, wired exactly the way
## `game.gd` wires the ones it places itself.
func _add_station(game: Node, offset: Vector2) -> Area2D:
	var station: Area2D = game._spawn_station(game.player_ship.global_position + offset)
	await physics_frame
	return station


## Put the ship inside the dock zone at `speed`, travelling at the station.
func _approach(game: Node, station: Area2D, speed: float) -> void:
	var ship: Area2D = game.player_ship
	var direction := (station.global_position - ship.global_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	ship.global_position = station.global_position - direction * (station.get_dock_zone_radius() - 8.0)
	ship.velocity = direction * speed
	await physics_frame
	await physics_frame


func _test_a_slow_approach_docks(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))

	await _approach(game, station, station.dock_speed_limit * 0.5)

	if station.docked_ship != game.player_ship:
		failures.append("Dock: a ship drifting in under the speed limit did not dock")
	if not game.player_ship.is_docked():
		failures.append("Dock: the station docked a ship that does not think it is docked")
	if not game.dock_panel.is_open():
		failures.append("Dock: docking did not open the dock panel")

	await _end_game_scene(game)


## Ramming a station at full speed must not be the same input as docking.
func _test_a_fast_approach_does_not_dock(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))

	await _approach(game, station, station.dock_speed_limit * 4.0)

	if station.docked_ship != null:
		failures.append(
			"Dock speed: a ship crossing the zone at %f px/s docked, the limit is %f"
			% [station.dock_speed_limit * 4.0, station.dock_speed_limit]
		)
	if game.player_ship.is_docked():
		failures.append("Dock speed: a ship above the speed limit reports itself docked")
	if game.dock_panel.is_open():
		failures.append("Dock speed: ramming a station opened the dock panel")

	await _end_game_scene(game)


func _test_docking_zeroes_velocity_and_disables_controls(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))

	await _approach(game, station, station.dock_speed_limit * 0.5)
	var docked_position: Vector2 = game.player_ship.global_position

	for _step in 10:
		await physics_frame

	if game.player_ship.velocity.length() > 0.0:
		failures.append(
			"Dock hold: a docked ship still carries %f px/s" % game.player_ship.velocity.length()
		)
	if game.player_ship.controls_enabled:
		failures.append("Dock hold: a docked ship still answers the controls")
	if not game.player_ship.global_position.is_equal_approx(docked_position):
		failures.append(
			"Dock hold: a docked ship drifted %f px"
			% game.player_ship.global_position.distance_to(docked_position)
		)

	await _end_game_scene(game)


func _test_repair_costs_credits_and_raises_hull(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))
	var systems: Node = game.ship_systems
	await _approach(game, station, station.dock_speed_limit * 0.5)

	systems.apply_damage(30.0)
	systems.add_credits(20)
	var bought: int = station.buy_repair(systems)

	if bought <= 0:
		failures.append("Repair: a damaged ship with 20 credits bought no repair")
	if not is_equal_approx(systems.hull, 70.0 + float(bought)):
		failures.append(
			"Repair: bought %d points but the hull went from 70 to %f" % [bought, systems.hull]
		)
	if systems.credits != 20 - bought * station.repair_cost_per_point:
		failures.append(
			"Repair: %d points at %d credits each left a balance of %d"
			% [bought, station.repair_cost_per_point, systems.credits]
		)

	# Clamped at the maximum: a full hull is never worth paying for.
	systems.add_credits(500)
	var before: int = systems.credits
	station.buy_repair(systems)
	if systems.hull > systems.max_hull:
		failures.append("Repair: the hull passed its maximum at %f" % systems.hull)
	if systems.hull < systems.max_hull:
		failures.append("Repair: 500 credits did not fill a %f hull" % systems.max_hull)
	var spare: int = systems.credits
	station.buy_repair(systems)
	if systems.credits != spare:
		failures.append("Repair: repairing a full hull charged %d credits" % (spare - systems.credits))
	if before <= spare:
		failures.append("Repair: filling the hull was free")

	await _end_game_scene(game)


func _test_repair_fails_cleanly_without_credits(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))
	var systems: Node = game.ship_systems
	await _approach(game, station, station.dock_speed_limit * 0.5)

	systems.apply_damage(40.0)
	var hull_before: float = systems.hull
	var bought: int = station.buy_repair(systems)

	if bought != 0:
		failures.append("Repair: a broke ship bought %d points of hull" % bought)
	if not is_equal_approx(systems.hull, hull_before):
		failures.append("Repair: a refused purchase moved the hull to %f" % systems.hull)
	if systems.credits != 0:
		failures.append("Repair: a refused purchase left the balance at %d" % systems.credits)

	await _end_game_scene(game)


## `ShipSystems.repair()` refuses once the run has ended, but `spend_credits()`
## does not, so an unguarded `buy_repair()` charges for hull it cannot deliver.
## The UI does not reach this today, but `buy_repair` is public and the station
## is the single authority on what a purchase is worth -- an authority that has
## to be right for callers as well as for buttons.
func _test_a_repair_after_the_run_ended_takes_no_credits(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))
	var systems: Node = game.ship_systems
	await _approach(game, station, station.dock_speed_limit * 0.5)

	systems.add_credits(500)
	systems.apply_damage(systems.max_hull)

	if not systems.run_ended:
		failures.append("Run-ended repair: the setup did not actually end the run")

	var credits_before: int = systems.credits
	var hull_before: float = systems.hull

	if station.get_affordable_repair_points(systems) != 0:
		failures.append("Run-ended repair: a repair was still offered after the run ended")

	var bought: int = station.buy_repair(systems)

	if bought != 0:
		failures.append("Run-ended repair: bought %d points on a ship whose run had ended" % bought)
	if systems.credits != credits_before:
		failures.append(
			"Run-ended repair: charged %d credits for hull it could not deliver"
			% [credits_before - systems.credits]
		)
	if not is_equal_approx(systems.hull, hull_before):
		failures.append("Run-ended repair: the hull moved to %f after the run ended" % systems.hull)

	await _end_game_scene(game)


func _test_refuel_costs_credits_and_fills_the_tank(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))
	var systems: Node = game.ship_systems
	await _approach(game, station, station.dock_speed_limit * 0.5)

	for _step in 100:
		systems.consume_fuel(1.0)
	systems.add_credits(15)
	var bought: int = station.buy_refuel(systems)

	if bought <= 0:
		failures.append("Refuel: a dry ship with 15 credits bought no fuel")
	if not is_equal_approx(systems.fuel, float(bought)):
		failures.append("Refuel: bought %d points but the tank holds %f" % [bought, systems.fuel])
	if systems.credits != 15 - bought * station.refuel_cost_per_point:
		failures.append("Refuel: the balance is %d after buying %d points" % [systems.credits, bought])

	systems.add_credits(500)
	station.buy_refuel(systems)
	if systems.fuel > systems.max_fuel:
		failures.append("Refuel: the tank passed its maximum at %f" % systems.fuel)
	if systems.fuel < systems.max_fuel:
		failures.append("Refuel: 500 credits did not fill a %f tank" % systems.max_fuel)

	await _end_game_scene(game)


func _test_refuel_fails_cleanly_without_credits(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))
	var systems: Node = game.ship_systems
	await _approach(game, station, station.dock_speed_limit * 0.5)

	for _step in 100:
		systems.consume_fuel(1.0)
	var bought: int = station.buy_refuel(systems)

	if bought != 0:
		failures.append("Refuel: a broke ship bought %d points of fuel" % bought)
	if systems.fuel > 0.0:
		failures.append("Refuel: a refused purchase put %f fuel in the tank" % systems.fuel)

	await _end_game_scene(game)


## An undock position inside the trigger area is an inescapable dock loop: the
## zone re-reports the overlap, the ship is stationary and so always under the
## speed limit, and it docks again on the next frame forever.
func _test_undocking_restores_control_and_does_not_redock(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))
	await _approach(game, station, station.dock_speed_limit * 0.5)

	if station.docked_ship == null:
		failures.append("Undock: the ship never docked, so undocking was not tested")
		await _end_game_scene(game)
		return

	var ship: Area2D = game.player_ship
	station.undock(ship)
	await physics_frame

	var distance: float = ship.global_position.distance_to(station.global_position)
	var clearance: float = station.get_dock_zone_radius() + ship.get_collision_radius()
	if distance <= clearance:
		failures.append(
			"Undock: released %f px from the station, inside the %f px dock zone plus hull"
			% [distance, clearance]
		)

	for _step in 10:
		await physics_frame
		if station.docked_ship != null:
			failures.append("Undock: the ship re-docked on its own after being released")
			break

	if not ship.controls_enabled:
		failures.append("Undock: the released ship still does not answer the controls")
	if ship.is_docked():
		failures.append("Undock: the released ship still reports itself docked")
	if game.dock_panel.is_open():
		failures.append("Undock: the dock panel is still open after undocking")

	await _end_game_scene(game)


## A player with nothing left has to be able to leave.
func _test_undocking_is_never_gated_on_payment(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))
	await _approach(game, station, station.dock_speed_limit * 0.5)

	game.ship_systems.apply_damage(50.0)
	for _step in 100:
		game.ship_systems.consume_fuel(1.0)

	game.dock_panel.undock_requested.emit()
	await physics_frame

	if station.docked_ship != null:
		failures.append("Undock: a broke, damaged, dry ship was held at the station")
	if not game.player_ship.controls_enabled:
		failures.append("Undock: a broke ship was released without its controls")

	await _end_game_scene(game)


func _test_the_station_hull_damages_the_ship(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))
	var systems: Node = game.ship_systems
	var ship: Area2D = game.player_ship
	ship.set_invulnerable(false)
	await physics_frame

	# Rammed, not drifted. A ship slow enough to dock never reaches the hull:
	# the dock zone is far wider than it is, so the only way to touch the
	# station is to cross that zone too fast to be docked by it.
	var hull_before: float = systems.hull
	ship.velocity = Vector2.RIGHT * station.dock_speed_limit * 4.0
	ship.global_position = station.global_position
	for _step in 5:
		await physics_frame

	if systems.hull >= hull_before:
		failures.append("Station hull: flying into the station did not damage the ship")
	if station.docked_ship != null:
		failures.append("Station hull: hitting the hull docked the ship instead of hurting it")

	# The pair must end up apart. A ship left sitting inside the hull is billed
	# again every time the post-damage window closes, and a dry ship on quarter
	# thrust cannot fly out of it -- the defect test_ship_systems.gd documents
	# for a rock resting on the ship.
	if station.get_overlapping_areas().has(ship):
		failures.append(
			"Station hull: the ship is still inside the station hull %f px from its centre"
			% ship.global_position.distance_to(station.global_position)
		)

	await _end_game_scene(game)


func _test_the_dock_zone_alone_does_not_damage_the_ship(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))
	var systems: Node = game.ship_systems
	game.player_ship.set_invulnerable(false)
	await physics_frame

	var hull_before: float = systems.hull
	await _approach(game, station, station.dock_speed_limit * 0.5)
	for _step in 10:
		await physics_frame

	if systems.hull < hull_before:
		failures.append(
			"Dock zone: docking cost %f hull -- the zone must not damage" % (hull_before - systems.hull)
		)

	await _end_game_scene(game)


## `get_tree().paused` belongs to the pause feature. Game.tscn's process_mode
## values are configured around it, so a dock panel that borrowed it would
## freeze exactly the nodes the pause overlay expects to keep running.
func _test_the_dock_panel_never_pauses_the_tree(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))

	await _approach(game, station, station.dock_speed_limit * 0.5)

	if paused:
		failures.append("Dock pause: opening the dock panel paused the scene tree")
	if game.paused:
		failures.append("Dock pause: opening the dock panel put the game in its paused state")

	await _end_game_scene(game)


func _test_pause_still_works_after_a_dock_panel_was_used(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))

	await _approach(game, station, station.dock_speed_limit * 0.5)
	game.dock_panel.undock_requested.emit()
	await physics_frame

	game._pause_game()
	await physics_frame

	if not game.paused or not paused:
		failures.append(
			"Pause: after a dock panel opened and closed, pausing left game.paused=%s tree.paused=%s"
			% [game.paused, paused]
		)

	game._resume_game()
	await physics_frame

	if game.paused or paused:
		failures.append("Pause: resuming after a dock left the game paused")
	if not game.player_ship.controls_enabled:
		failures.append("Pause: the ship lost its controls across a dock and a pause")

	await _end_game_scene(game)


## An enabled button that does nothing when pressed is worse than a disabled
## one: it tells the player the service is available and then silently refuses.
func _test_a_service_that_cannot_be_bought_is_not_offered(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))
	await _approach(game, station, station.dock_speed_limit * 0.5)

	var systems: Node = game.ship_systems
	var panel: CanvasLayer = game.dock_panel
	systems.apply_damage(60.0)
	for _step in 100:
		systems.consume_fuel(1.0)
	# Zero balance: every point of the deficit is unaffordable.
	systems.spend_credits(systems.credits)
	panel.refresh()

	if not panel.repair_button.disabled:
		failures.append("Prices: a broke ship was offered a repair it cannot pay for")
	if not panel.refuel_button.disabled:
		failures.append("Prices: a broke ship was offered a refuel it cannot pay for")
	if panel.undock_button.disabled:
		failures.append("Prices: leaving was gated on the balance")

	# One point's worth, and only the repair becomes buyable at 2 cr a point.
	systems.add_credits(station.repair_cost_per_point)
	panel.refresh()
	if panel.repair_button.disabled:
		failures.append("Prices: a repair the balance covers was still refused by the button")

	await _end_game_scene(game)


## Fuel is continuous and prices are per whole point, so a nearly-full tank is
## a deficit that no amount of credits can buy. The button has to agree.
func _test_a_deficit_under_one_point_is_not_offered(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))
	await _approach(game, station, station.dock_speed_limit * 0.5)

	var systems: Node = game.ship_systems
	var panel: CanvasLayer = game.dock_panel
	systems.add_credits(500)
	# 0.6 of a point short: richly affordable, and still not one whole point.
	systems.refuel(systems.max_fuel)
	systems.consume_fuel(0.6 / systems.fuel_burn_per_second)
	panel.refresh()

	if systems.fuel >= systems.max_fuel:
		failures.append("Prices: the test failed to leave a partial fuel deficit")
	if not panel.refuel_button.disabled:
		failures.append(
			"Prices: a %f point deficit was offered as a refuel that buys nothing"
			% (systems.max_fuel - systems.fuel)
		)

	var credits_before: int = systems.credits
	panel.refuel_requested.emit()
	if systems.credits != credits_before:
		failures.append("Prices: a refuel that delivered no points still charged the player")

	await _end_game_scene(game)


## The pause overlay owns the screen while the game is paused. The dock panel
## is a higher CanvasLayer than the Hud and runs with process_mode ALWAYS, so
## without this it draws over that overlay and keeps taking button presses.
func _test_pausing_stands_the_dock_panel_down(failures: Array[String]) -> void:
	var game: Node = await _start_empty_game()
	var station: Area2D = await _add_station(game, Vector2(900.0, 0.0))
	await _approach(game, station, station.dock_speed_limit * 0.5)

	var systems: Node = game.ship_systems
	var panel: CanvasLayer = game.dock_panel
	systems.apply_damage(50.0)
	systems.add_credits(500)

	game._pause_game()
	await physics_frame

	if panel.root_control.visible:
		failures.append("Pause: the dock panel kept drawing over the pause overlay")
	if not panel.is_open():
		failures.append("Pause: pausing let go of the dock the ship is still parked at")

	var hull_before: float = systems.hull
	var credits_before: int = systems.credits
	panel.repair_requested.emit()
	panel.refuel_requested.emit()
	if systems.hull != hull_before or systems.credits != credits_before:
		failures.append("Pause: a station service changed run state while the game was paused")

	panel.undock_requested.emit()
	await physics_frame
	if station.docked_ship == null:
		failures.append("Pause: the ship undocked while the game was paused")

	game._resume_game()
	await physics_frame

	if not panel.root_control.visible:
		failures.append("Pause: resuming did not put the dock panel back on screen")

	panel.repair_requested.emit()
	if systems.hull <= hull_before:
		failures.append("Pause: the dock panel stayed dead after the game resumed")

	await _end_game_scene(game)


func _test_stations_are_placed_in_the_sector_clear_of_the_player(failures: Array[String]) -> void:
	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	game.auto_start = false
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	var stations := get_nodes_in_group("stations")
	if stations.is_empty():
		failures.append("Placement: a new run placed no stations at all")
	else:
		# The invariant itself, not just the sample that happened to come out
		# of it: a seeded draw only lands in the offending band occasionally,
		# so asserting on the placement alone would pass by luck.
		var probe: Node2D = stations[0]
		var required: float = game.sector.get_boundary_margin() + probe.get_dock_zone_radius()
		var used: float = game._get_station_edge_inset(probe)
		if used < required:
			failures.append(
				"Placement: stations are inset %f px, but the dock zone only clears the %f px boundary band at %f"
				% [used, game.sector.get_boundary_margin(), required]
			)

	var bounds: Rect2 = game.sector.get_bounds()
	for station: Node2D in stations:
		if not bounds.has_point(station.global_position):
			failures.append(
				"Placement: a station at %s sits outside the sector %s"
				% [station.global_position, bounds]
			)
		var gap: float = station.global_position.distance_to(game.player_ship.global_position)
		if gap < station.get_dock_zone_radius():
			failures.append("Placement: a station spawned %f px from the player" % gap)
		if station.is_in_group("gravity_sources"):
			failures.append("Placement: a station joined gravity_sources without a gravity definition")

		# The whole dock zone has to clear the boundary band, not just the
		# station at the centre of it. Inside the band the containment push
		# accelerates a ship that is trying to hold still, and a ship being
		# accelerated is a ship over `dock_speed_limit`.
		var margin: float = game.sector.get_boundary_margin()
		var reach: float = margin + station.get_dock_zone_radius()
		var wall_gap: float = minf(
			minf(station.global_position.x - bounds.position.x, bounds.end.x - station.global_position.x),
			minf(station.global_position.y - bounds.position.y, bounds.end.y - station.global_position.y)
		)
		if wall_gap < reach:
			failures.append(
				"Placement: a station %f px from the wall puts its dock zone inside the %f px boundary band"
				% [wall_gap, margin]
			)

	await _end_game_scene(game)


## A station inside an asteroid field is a destination inside a hazard, and the
## player arrives at it with the controls switched off. This is not a rare
## draw: before the fix the shipped sector put the only station's dock zone
## 93 px inside `asteroid_field_05` on every single run, and a ship docked
## there lost 50 hull in 30 seconds -- at the one place in the sector that
## sells hull back. A station moved clear of the fields on the same seed took
## none.
##
## Asserted twice: once on the sector the game actually ships, and once across
## 64 draws of the sampler itself, because the existing placement test's own
## warning applies here too -- a single seeded draw can pass by luck.
func _test_stations_are_placed_clear_of_the_asteroid_fields(failures: Array[String]) -> void:
	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	game.auto_start = false
	root.add_child(game)
	await physics_frame
	game._start_new_game()
	await physics_frame

	if game.sector.get_fields().is_empty():
		failures.append("Field clearance: the sector placed no asteroid fields to test against")

	var stations := get_nodes_in_group("stations")
	if stations.is_empty():
		failures.append("Field clearance: a new run placed no stations at all")
	else:
		for station: Node2D in stations:
			var overlap := _get_worst_field_overlap(
				game, station.global_position, station.get_dock_zone_radius()
			)
			if overlap > 0.0:
				failures.append(
					"Field clearance: the shipped sector put a dock zone %f px inside an asteroid field"
					% overlap
				)

		# The invariant, not the sample. The shipped seed is one draw -- the one
		# that happened to expose this -- so re-run the sampler on its own across
		# many seeds against the same live fields.
		var probe: Node2D = stations[0]
		var zone: float = probe.get_dock_zone_radius()
		var inset: float = game._get_station_edge_inset(probe)
		var rng := RandomNumberGenerator.new()
		var offenders := 0
		for draw in 64:
			rng.seed = draw
			var positions: Array[Vector2] = game.sector.get_station_positions(
				rng, 1, inset, -1.0, [game.player_ship.global_position], zone
			)
			for position: Vector2 in positions:
				if _get_worst_field_overlap(game, position, zone) > 0.0:
					offenders += 1

		if offenders > 0:
			failures.append(
				"Field clearance: %d of 64 sampler draws put a dock zone inside an asteroid field"
				% offenders
			)

	await _end_game_scene(game)


## How far a disc of `radius` around `point` reaches into the nearest asteroid
## field, in pixels. Zero or less is clear. Negative infinity when the sector
## holds no fields, which is clear by default rather than an error here -- the
## missing-fields case is reported on its own above.
func _get_worst_field_overlap(game: Node, point: Vector2, radius: float) -> float:
	var worst := -INF

	for field: Node2D in game.sector.get_fields():
		worst = maxf(worst, (field.field_radius + radius) - point.distance_to(field.global_position))

	return worst
