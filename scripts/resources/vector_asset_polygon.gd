extends Resource
class_name VectorAssetPolygon


@export var polygon_id: StringName
@export var polygon: PackedVector2Array
@export var fill_color: Color = Color.WHITE
@export var material_definition: Resource
@export var visible_by_default: bool = true


func is_valid() -> bool:
	return polygon.size() >= 3
