extends Resource
class_name VectorAssetDefinition


enum Category {
	SHIP,
	ASTEROID,
	BULLET,
	EFFECT,
	PRESENTATION,
	AUDIO,
	CELESTIAL,
	STATION,
}


@export var asset_id: StringName
@export var category: Category = Category.SHIP
@export var primary_polygon: PackedVector2Array
@export var fill_color: Color = Color.WHITE
@export var outline_color: Color = Color.TRANSPARENT
@export_range(0.0, 16.0, 0.25, "or_greater") var outline_width: float = 0.0
@export var material_definition: Resource
@export var secondary_polygons: Array[Resource] = []
@export var use_collision_polygon: bool = false
@export var collision_polygon: PackedVector2Array
@export var collision_radius: float = 0.0
@export var tags: PackedStringArray
@export var provenance_reference: String = ""


func is_primary_polygon_valid() -> bool:
	return primary_polygon.size() >= 3


func get_secondary_polygon(polygon_id: StringName) -> Resource:
	for secondary_polygon: Resource in secondary_polygons:
		if (
			secondary_polygon != null
			and secondary_polygon.get("polygon_id") == polygon_id
			and secondary_polygon.has_method("is_valid")
		):
			return secondary_polygon

	return null
