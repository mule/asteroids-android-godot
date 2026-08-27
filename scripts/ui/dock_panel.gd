## The station services overlay: repair, refuel, leave.
##
## Deliberately does not touch `get_tree().paused`. The pause feature already
## owns that flag and `Game.tscn` is configured around it -- borrowing it here
## would freeze the very nodes the pause overlay expects to keep running, and
## a resume would have two owners disagreeing about who un-paused. Docking
## disables the ship's controls instead, which is the thing actually wanted:
## a parked ship, in a world that keeps moving around it.
extends CanvasLayer
class_name DockPanel


signal repair_requested()
signal refuel_requested()
signal undock_requested()

@onready var root_control: Control = $Root
@onready var title_label: Label = $Root/Panel/Margin/Body/TitleLabel
@onready var hull_label: Label = $Root/Panel/Margin/Body/HullLabel
@onready var fuel_label: Label = $Root/Panel/Margin/Body/FuelLabel
@onready var credits_label: Label = $Root/Panel/Margin/Body/CreditsLabel
@onready var repair_button: Button = $Root/Panel/Margin/Body/Actions/RepairButton
@onready var refuel_button: Button = $Root/Panel/Margin/Body/Actions/RefuelButton
@onready var undock_button: Button = $Root/Panel/Margin/Body/Actions/UndockButton

var station: Node2D = null
var systems: Node = null
## Open, but stood down while something else owns the screen. Kept apart from
## `station` so a resume puts the same panel back instead of needing a fresh
## `show_for` -- see set_suspended().
var suspended: bool = false


func _ready() -> void:
	repair_button.pressed.connect(repair_requested.emit)
	refuel_button.pressed.connect(refuel_requested.emit)
	undock_button.pressed.connect(undock_requested.emit)
	hide_panel()


func show_for(dock_station: Node2D, ship_systems: Node) -> void:
	_release_systems()
	station = dock_station
	systems = ship_systems
	suspended = false
	_follow_systems()
	_update_visibility()
	refresh()


func hide_panel() -> void:
	_release_systems()
	station = null
	suspended = false
	_update_visibility()


## Stand the panel down without letting go of the station it is showing.
##
## The pause overlay owns the screen while the game is paused, and this panel
## does not yield to it on its own: `Game.tscn` gives DockPanel a higher
## `layer` than the Hud, so it draws over the overlay, and both run with
## `process_mode` ALWAYS, so its buttons keep taking presses. Repairing a hull
## while the game is paused is a change to run state that every other handler
## in `game.gd` refuses to make. Hiding the panel answers both at once: a
## hidden Control neither draws nor receives input.
func set_suspended(value: bool) -> void:
	suspended = value
	_update_visibility()


## Asked of the binding rather than of `root_control.visible`, so a suspended
## panel still reports the dock it is holding. "Is the player docked" and "is
## the panel on screen" stopped being the same question when pause arrived.
func is_open() -> bool:
	return station != null and is_instance_valid(station)


func refresh() -> void:
	if station != null and is_instance_valid(station):
		title_label.text = "Docked at %s" % String(station.station_name).capitalize()
	else:
		title_label.text = "Docked"

	if systems == null or not is_instance_valid(systems):
		return

	hull_label.text = "Hull %d / %d  (%d cr per point)" % [
		roundi(systems.hull), roundi(systems.max_hull), _get_repair_price()
	]
	fuel_label.text = "Fuel %d / %d  (%d cr per point)" % [
		roundi(systems.fuel), roundi(systems.max_fuel), _get_refuel_price()
	]
	credits_label.text = "Credits %d" % systems.credits
	# Disabled on what the purchase would actually deliver, not on the deficit
	# alone. Prices are per whole point while hull and fuel are continuous, so
	# a deficit under one point -- or one the balance cannot cover -- is an
	# enabled button that does nothing when pressed.
	repair_button.disabled = _get_affordable_repair() <= 0
	refuel_button.disabled = _get_affordable_refuel() <= 0
	# Never the undock button. A player with nothing left has to be able to
	# fly away, so leaving is the one action that is never gated on anything.
	undock_button.disabled = false


func _get_affordable_repair() -> int:
	if station == null or not is_instance_valid(station):
		return 0

	return station.get_affordable_repair_points(systems)


func _get_affordable_refuel() -> int:
	if station == null or not is_instance_valid(station):
		return 0

	return station.get_affordable_refuel_points(systems)


func _get_repair_price() -> int:
	return 0 if station == null or not is_instance_valid(station) else station.repair_cost_per_point


func _get_refuel_price() -> int:
	return 0 if station == null or not is_instance_valid(station) else station.refuel_cost_per_point


## Redrawn from the same signals the HUD uses, so a purchase made here and a
## hit taken elsewhere reach the panel by the identical path.
func _follow_systems() -> void:
	if systems == null or not is_instance_valid(systems):
		return

	systems.hull_changed.connect(_on_hull_changed)
	systems.fuel_changed.connect(_on_fuel_changed)
	systems.credits_changed.connect(_on_credits_changed)


func _update_visibility() -> void:
	root_control.visible = is_open() and not suspended


func _release_systems() -> void:
	if systems == null or not is_instance_valid(systems):
		systems = null
		return

	if systems.hull_changed.is_connected(_on_hull_changed):
		systems.hull_changed.disconnect(_on_hull_changed)
	if systems.fuel_changed.is_connected(_on_fuel_changed):
		systems.fuel_changed.disconnect(_on_fuel_changed)
	if systems.credits_changed.is_connected(_on_credits_changed):
		systems.credits_changed.disconnect(_on_credits_changed)

	systems = null


func _on_hull_changed(_current: float, _maximum: float) -> void:
	refresh()


func _on_fuel_changed(_current: float, _maximum: float) -> void:
	refresh()


func _on_credits_changed(_amount: int) -> void:
	refresh()
