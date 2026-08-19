extends Resource
class_name SectorDefinition


@export var sector_name: StringName = &"vega_7"
@export var world_size: Vector2 = Vector2(1152.0, 648.0)
@export var sector_seed: int = 1729
@export var boundary_margin: float = 600.0
@export var asteroid_field_count: int = 5
@export var planet_count: int = 2
@export var moon_count: int = 3
@export var station_count: int = 1
@export var min_landmark_separation: float = 900.0
@export var threat_curve: Curve


func get_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, world_size)
