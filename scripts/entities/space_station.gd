## A space station: an obstacle on the outside, a service on the inside.
##
## Two areas, deliberately on separate nodes. The station node itself is the
## hull and damages whatever flies into it; the `DockZone` child is a much
## wider trigger that docks a ship approaching slowly. Keeping them apart is
## the whole point -- ramming a station at full speed must not be the same
## input as docking, and a single area cannot tell those apart.
extends Area2D
class_name SpaceStation


signal dock_requested(ship: Node2D)
signal undocked(ship: Node2D)

## A ship crossing the dock zone faster than this is passing through, not
## arriving. What it meets next is the hull.
@export var dock_speed_limit: float = 60.0
@export var repair_cost_per_point: int = 2
@export var refuel_cost_per_point: int = 1
@export var station_name: StringName = &"relay"
## Gap left outside the dock zone when a ship is released, on top of the zone
## radius and the ship's own hull. Everything here is measured off the actual
## zone shape rather than hard-coded, so retuning the zone later cannot
## silently drop the release point back inside the trigger -- an undock
## position inside the zone is an inescapable dock loop, because a released
## ship is stationary and therefore always under the speed limit.
@export var undock_clearance: float = 48.0
## The same idea for the hull. A ship left touching it is billed again every
## time the post-damage window closes, which is the defect
## `test_ship_systems.gd` documents for a rock resting on the ship.
@export var hull_clearance: float = 10.0
## How much of a ramming ship's speed survives the bounce off the hull.
@export var hull_bounce_factor: float = 0.35
@export var hull_color: Color = Color(0.46, 0.52, 0.62, 1.0)
@export var dock_ring_color: Color = Color(0.45, 0.85, 0.95, 0.22)

@onready var dock_zone: Area2D = $DockZone
@onready var dock_zone_shape: CollisionShape2D = $DockZone/DockZoneShape
@onready var hull_shape: CollisionShape2D = $CollisionShape2D

var docked_ship: Node2D = null
## Where the docking ship came in from, so releasing it puts it back on its own
## approach line instead of teleporting it round to a fixed side.
var _release_direction: Vector2 = Vector2.RIGHT
var _docked_ship_radius: float = 0.0


func _ready() -> void:
	queue_redraw()


## Polled rather than driven by `area_entered`, because the enter transition
## fires once and answers the wrong question. A ship that crosses the zone
## boundary too fast, then slows to a stop inside it, has already spent its
## one transition: on a signal-only station it could never dock without
## leaving and coming back. The zone's overlap list is cached by the engine,
## so asking it every frame costs nothing.
func _physics_process(_delta: float) -> void:
	if docked_ship != null:
		return

	for area in dock_zone.get_overlapping_areas():
		if can_dock(area):
			dock_requested.emit(area)
			return


func can_dock(ship: Node2D) -> bool:
	if ship == null or not is_instance_valid(ship) or docked_ship != null:
		return false

	# The dock zone's collision mask already narrows this to the player's
	# layer; the capability check is what keeps a future entity on that layer
	# from being handed a dock it cannot answer.
	if not ship.has_method("enter_dock") or not ship.has_method("exit_dock"):
		return false

	if ship.has_method("is_docked") and ship.is_docked():
		return false

	# The overlap list proposes, the geometry confirms. An Area2D's overlap
	# list is only refreshed by a physics step, so for one frame after a ship
	# is teleported out of the zone the list still reports it inside -- and a
	# just-released ship is stationary, therefore always under the speed limit,
	# therefore re-docked on the very frame it was let go. That is the
	# inescapable dock loop, arriving through the stale list rather than
	# through a bad release point. Asking where the ship actually is cannot be
	# fooled by either.
	if ship.global_position.distance_to(global_position) > get_dock_zone_radius():
		return false

	return _get_ship_speed(ship) <= dock_speed_limit


func dock(ship: Node2D) -> void:
	if not can_dock(ship):
		return

	docked_ship = ship
	_release_direction = _get_release_direction(ship)
	_docked_ship_radius = _get_ship_radius(ship)
	ship.enter_dock(self)


func undock(ship: Node2D) -> void:
	if ship == null or ship != docked_ship:
		return

	docked_ship = null

	if is_instance_valid(ship):
		# Moved before the controls come back, so the ship never spends a frame
		# flyable inside the trigger it is being released from.
		ship.global_position = get_undock_position()
		ship.exit_dock()

	undocked.emit(ship)


## A point clear of the dock zone, the released ship's own hull, and a margin.
## Derived from the live zone radius on purpose -- see `undock_clearance`.
func get_undock_position() -> Vector2:
	var distance := get_dock_zone_radius() + _docked_ship_radius + undock_clearance
	return global_position + _release_direction * distance


func get_dock_zone_radius() -> float:
	return _get_shape_radius(dock_zone_shape)


func get_hull_radius() -> float:
	return _get_shape_radius(hull_shape)


## What a repair would actually deliver, without buying it.
##
## The panel asks this rather than comparing hull to max_hull itself. Those
## two questions have different answers and the difference is reachable: hull
## and fuel are continuous, the prices are per whole point, so a deficit under
## one full point buys nothing -- and neither does any deficit a broke player
## cannot pay for. A button offered on `hull < max_hull` alone is a button
## that a player at 99.4 fuel, or at zero credits, can press all day for
## nothing. One authority on what a purchase does, asked by both the button
## and the purchase.
func get_affordable_repair_points(systems: Node) -> int:
	if systems == null or not is_instance_valid(systems):
		return 0

	return _affordable_points(
		systems.credits,
		floori(systems.max_hull - systems.hull),
		repair_cost_per_point
	)


func get_affordable_refuel_points(systems: Node) -> int:
	if systems == null or not is_instance_valid(systems):
		return 0

	return _affordable_points(
		systems.credits,
		floori(systems.max_fuel - systems.fuel),
		refuel_cost_per_point
	)


## Buy whole points of hull, as many as the balance covers, and charge for
## exactly those. Returns the points bought, 0 when nothing was -- a ship with
## no credits and a wrecked hull is a refused purchase, not an error.
func buy_repair(systems: Node) -> int:
	var points := get_affordable_repair_points(systems)

	if points <= 0 or not systems.spend_credits(points * repair_cost_per_point):
		return 0

	systems.repair(float(points))
	return points


func buy_refuel(systems: Node) -> int:
	var points := get_affordable_refuel_points(systems)

	if points <= 0 or not systems.spend_credits(points * refuel_cost_per_point):
		return 0

	systems.refuel(float(points))
	return points


## Put a ship that hit the hull back outside it, travelling away. The damage
## itself is `game.gd`'s to apply; this is what stops the pair still touching
## once the post-damage window closes and the hull is billed all over again.
func repel(ship: Node2D) -> void:
	if ship == null or not is_instance_valid(ship):
		return

	var outward := ship.global_position - global_position
	if outward.length_squared() <= 0.01:
		outward = Vector2.UP
	outward = outward.normalized()

	ship.global_position = (
		global_position + outward * (get_hull_radius() + _get_ship_radius(ship) + hull_clearance)
	)

	if not ("velocity" in ship):
		return

	var velocity: Vector2 = ship.velocity
	if velocity.dot(outward) < 0.0:
		velocity = velocity.bounce(outward)
	ship.velocity = velocity * hull_bounce_factor


func _draw() -> void:
	var zone_radius := get_dock_zone_radius()
	if zone_radius > 0.0:
		draw_arc(Vector2.ZERO, zone_radius, 0.0, TAU, 64, dock_ring_color, 2.0, true)


func _affordable_points(credits: int, wanted: int, cost_per_point: int) -> int:
	if wanted <= 0 or credits <= 0:
		return 0

	if cost_per_point <= 0:
		return wanted

	return mini(wanted, credits / cost_per_point)


func _get_ship_speed(ship: Node2D) -> float:
	if "velocity" in ship:
		var velocity: Vector2 = ship.velocity
		return velocity.length()

	return 0.0


func _get_ship_radius(ship: Node2D) -> float:
	if ship.has_method("get_collision_radius"):
		return ship.get_collision_radius()

	return 0.0


func _get_release_direction(ship: Node2D) -> Vector2:
	var approach := ship.global_position - global_position
	if approach.length_squared() <= 0.01:
		return _release_direction

	return approach.normalized()


func _get_shape_radius(shape_node: CollisionShape2D) -> float:
	if shape_node == null:
		return 0.0

	var shape := shape_node.shape

	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius

	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.length() * 0.5

	if shape is ConvexPolygonShape2D:
		var radius := 0.0
		for point in (shape as ConvexPolygonShape2D).points:
			radius = maxf(radius, point.length())
		return radius

	return 0.0
