extends Resource
class_name SectorDefinition


@export var sector_name: StringName = &"vega_7"
## The epic's sector is 8000x6000. #44 shipped this default at the old
## viewport size so growing the world stayed #45's job; #45 has since grown
## it, and a leftover 1152x648 default would hand any new SectorDefinition a
## pre-epic world.
@export var world_size: Vector2 = Vector2(8000.0, 6000.0)
@export var sector_seed: int = 1729
@export var boundary_margin: float = 600.0
@export var asteroid_field_count: int = 5
@export var asteroid_field_radius_min: float = 320.0
@export var asteroid_field_radius_max: float = 560.0
@export var asteroid_field_budget: int = 4
@export var planet_count: int = 2
@export var moon_count: int = 3
@export var station_count: int = 1
@export var min_landmark_separation: float = 900.0
@export var threat_curve: Curve


func get_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, world_size)
