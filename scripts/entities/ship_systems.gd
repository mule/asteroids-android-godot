## The ship's consumable state: hull, fuel and credits.
##
## A plain Node child of the ship rather than fields on `player_ship.gd`, which
## already owns input, movement, shooting, containment and materials. Everything
## that has to react to a change -- the HUD, the run-end path in `game.gd`,
## later the stations of #54 -- subscribes to a signal here instead of polling
## the ship every frame.
extends Node
class_name ShipSystems


signal hull_changed(current: float, maximum: float)
signal fuel_changed(current: float, maximum: float)
signal credits_changed(amount: int)
signal destroyed()
signal reserve_thrust_changed(active: bool)

@export var max_hull: float = 100.0
@export var max_fuel: float = 100.0
@export var fuel_burn_per_second: float = 4.0
## At zero fuel the ship keeps this fraction of its acceleration. It is a
## design constraint, not a balance value: a hard fuel-out in an 8000x6000
## sector strands the player with no way to reach a station and no way to die,
## which is an unwinnable soft-lock no amount of tuning removes. Reserve thrust
## turns it into a slow, costly, survivable limp home.
@export var reserve_thrust_factor: float = 0.25
@export var starting_credits: int = 0

var hull: float = max_hull
var fuel: float = max_fuel
var credits: int = starting_credits
var reserve_thrust_active: bool = false
var run_ended: bool = false


func _ready() -> void:
	reset_systems()


## Restore a fresh ship. Called on every new run, so the signals fire and the
## HUD redraws from the same path that a mid-run change uses.
func reset_systems() -> void:
	hull = max_hull
	fuel = max_fuel
	credits = starting_credits
	run_ended = false
	hull_changed.emit(hull, max_hull)
	fuel_changed.emit(fuel, max_fuel)
	credits_changed.emit(credits)
	_set_reserve_thrust_active(false)


func apply_damage(amount: float) -> void:
	if amount <= 0.0 or run_ended:
		return

	hull = maxf(0.0, hull - amount)
	hull_changed.emit(hull, max_hull)

	if hull > 0.0:
		return

	# Once per run, not once per hit. `game.gd` ends the run from this signal,
	# and a second asteroid landing on the wreck in the same frame must not
	# start a second game-over.
	run_ended = true
	destroyed.emit()


## Burn `delta` seconds of thrust. Returns false when the tank was already
## empty, i.e. when this burn is running on reserve.
func consume_fuel(delta: float) -> bool:
	if delta <= 0.0:
		return not reserve_thrust_active

	if fuel <= 0.0:
		_set_reserve_thrust_active(true)
		return false

	fuel = maxf(0.0, fuel - fuel_burn_per_second * delta)
	fuel_changed.emit(fuel, max_fuel)
	_set_reserve_thrust_active(fuel <= 0.0)
	return true


func refuel(amount: float) -> void:
	if amount <= 0.0:
		return

	fuel = minf(max_fuel, fuel + amount)
	fuel_changed.emit(fuel, max_fuel)
	_set_reserve_thrust_active(fuel <= 0.0)


func repair(amount: float) -> void:
	if amount <= 0.0 or run_ended:
		return

	hull = minf(max_hull, hull + amount)
	hull_changed.emit(hull, max_hull)


func add_credits(amount: int) -> void:
	if amount <= 0:
		return

	credits += amount
	credits_changed.emit(credits)


## Returns false and leaves the balance untouched when it cannot be paid, so a
## caller can branch on the purchase without checking the balance itself.
func spend_credits(amount: int) -> bool:
	if amount < 0 or amount > credits:
		return false

	if amount == 0:
		return true

	credits -= amount
	credits_changed.emit(credits)
	return true


## 1.0 normally, `reserve_thrust_factor` on an empty tank. Never 0.0.
func get_thrust_factor() -> float:
	return reserve_thrust_factor if fuel <= 0.0 else 1.0


func is_destroyed() -> bool:
	return run_ended


func _set_reserve_thrust_active(active: bool) -> void:
	if active == reserve_thrust_active:
		return

	reserve_thrust_active = active
	reserve_thrust_changed.emit(active)
