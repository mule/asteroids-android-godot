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


func _ready() -> void:
	repair_button.pressed.connect(repair_requested.emit)
	refuel_button.pressed.connect(refuel_requested.emit)
	undock_button.pressed.connect(undock_requested.emit)
	hide_panel()


func show_for(dock_station: Node2D, ship_systems: Node) -> void:
	_release_systems()
	station = dock_station
	systems = ship_systems
	_follow_systems()
	root_control.visible = true
	refresh()


func hide_panel() -> void:
	_release_systems()
	station = null
	root_control.visible = false


func is_open() -> bool:
	return root_control.visible


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
	repair_button.disabled = systems.hull >= systems.max_hull
	refuel_button.disabled = systems.fuel >= systems.max_fuel
	# Never the undock button. A player with nothing left has to be able to
	# fly away, so leaving is the one action that is never gated on anything.
	undock_button.disabled = false


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
