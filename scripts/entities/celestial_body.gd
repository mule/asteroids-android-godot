extends Area2D
class_name CelestialBody


const MATERIAL_RUNTIME := preload("res://scripts/material_runtime.gd")


@export var definition: Resource
@export var shader_lighting_enabled: bool = true

@onready var body_shape: Polygon2D = $BodyShape
@onready var detail_shapes: Node2D = $DetailShapes
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var orbit_parent: Node2D = null
var initial_orbit_angle: float = 0.0
var world_light_direction: Vector2 = Vector2(-0.55, -0.83).normalized()

var _elapsed_orbit_seconds: float = 0.0
var _body_material: ShaderMaterial
var _detail_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	_join_groups()
	_apply_definition()
	_update_orbit_position()


func _physics_process(delta: float) -> void:
	if definition == null:
		return

	if _has_orbit():
		_elapsed_orbit_seconds += delta
		_update_orbit_position()

	_update_shader_light_direction()


func setup(selected_definition: Resource, parent_body: Node2D, initial_angle: float) -> void:
	definition = selected_definition
	orbit_parent = parent_body
	initial_orbit_angle = initial_angle
	_elapsed_orbit_seconds = 0.0
	_join_groups()

	if is_node_ready():
		_apply_definition()
		_update_orbit_position()


func get_body_radius() -> float:
	if definition != null and "body_radius" in definition:
		return maxf(0.0, definition.body_radius)

	return 0.0


func get_influence_radius() -> float:
	if definition == null:
		return 0.0

	var multiplier: float = definition.influence_multiplier if "influence_multiplier" in definition else 4.0
	return get_body_radius() * maxf(0.0, multiplier)


func set_shader_lighting_enabled(value: bool) -> void:
	shader_lighting_enabled = value
	MATERIAL_RUNTIME.set_lighting_enabled(_body_material, value)
	for detail_material in _detail_materials:
		MATERIAL_RUNTIME.set_lighting_enabled(detail_material, value)


func set_world_light_direction(value: Vector2) -> void:
	world_light_direction = value.normalized()
	_update_shader_light_direction()


func set_sector_bounds(_bounds: Rect2) -> void:
	pass


func set_boundary_margin(_margin: float) -> void:
	pass


func _join_groups() -> void:
	add_to_group("gravity_sources")
	add_to_group("celestial_bodies")


func _has_orbit() -> bool:
	return (
		orbit_parent != null
		and is_instance_valid(orbit_parent)
		and definition != null
		and "orbit_radius" in definition
		and "orbit_period_seconds" in definition
		and definition.orbit_radius > 0.0
		and definition.orbit_period_seconds > 0.0
	)


func _update_orbit_position() -> void:
	if not _has_orbit():
		return

	var angle: float = initial_orbit_angle + TAU * (_elapsed_orbit_seconds / definition.orbit_period_seconds)
	global_position = orbit_parent.global_position + Vector2.RIGHT.rotated(angle) * definition.orbit_radius


func _apply_definition() -> void:
	if definition == null:
		return

	name = String(definition.body_id) if "body_id" in definition and definition.body_id != StringName() else "CelestialBody"
	_apply_visual_asset()
	_apply_collision_radius()
	set_shader_lighting_enabled(shader_lighting_enabled)
	_update_shader_light_direction()


func _apply_visual_asset() -> void:
	_clear_details()
	if not _is_valid_visual_asset(definition.visual_asset):
		body_shape.scale = Vector2.ONE
		return

	var asset: Resource = definition.visual_asset
	var visual_scale := _get_visual_scale(asset)
	body_shape.polygon = asset.primary_polygon
	body_shape.color = asset.fill_color
	body_shape.scale = Vector2.ONE * visual_scale
	_body_material = MATERIAL_RUNTIME.apply_material_definition(body_shape, asset.material_definition)

	if "outline_color" in asset and asset.outline_color.a > 0.0:
		body_shape.texture = null

	if "secondary_polygons" in asset:
		for secondary_polygon: Resource in asset.secondary_polygons:
			if secondary_polygon != null and secondary_polygon.has_method("is_valid") and secondary_polygon.is_valid():
				_add_detail_shape(secondary_polygon, visual_scale, asset.material_definition)


func _add_detail_shape(secondary_polygon: Resource, visual_scale: float, fallback_material: Resource) -> void:
	var detail := Polygon2D.new()
	detail.name = String(secondary_polygon.polygon_id)
	detail.polygon = secondary_polygon.polygon
	detail.color = secondary_polygon.fill_color
	detail.scale = Vector2.ONE * visual_scale
	detail_shapes.add_child(detail)

	var material_definition: Resource = secondary_polygon.material_definition
	if material_definition == null:
		material_definition = fallback_material
	var detail_material := MATERIAL_RUNTIME.apply_material_definition(detail, material_definition)
	if detail_material != null:
		_detail_materials.append(detail_material)


func _apply_collision_radius() -> void:
	if collision_shape.shape is CircleShape2D:
		var circle := collision_shape.shape.duplicate() as CircleShape2D
		circle.radius = get_body_radius()
		collision_shape.shape = circle


func _get_visual_scale(asset: Resource) -> float:
	var source_radius: float = asset.collision_radius if "collision_radius" in asset else 0.0
	if source_radius <= 0.0:
		source_radius = _get_polygon_radius(asset.primary_polygon)
	if source_radius <= 0.0:
		return 1.0

	return get_body_radius() / source_radius


func _get_polygon_radius(points: PackedVector2Array) -> float:
	var radius := 0.0
	for point in points:
		radius = maxf(radius, point.length())
	return radius


func _clear_details() -> void:
	for child in detail_shapes.get_children():
		child.queue_free()
	_detail_materials.clear()


func _is_valid_visual_asset(candidate: Resource) -> bool:
	return (
		candidate != null
		and candidate.has_method("is_primary_polygon_valid")
		and candidate.is_primary_polygon_valid()
	)


func _update_shader_light_direction() -> void:
	MATERIAL_RUNTIME.set_world_light_direction(_body_material, self, world_light_direction)
	for detail_material in _detail_materials:
		MATERIAL_RUNTIME.set_world_light_direction(detail_material, self, world_light_direction)
