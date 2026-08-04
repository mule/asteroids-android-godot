extends RefCounted
class_name MaterialRuntime


static func apply_material_definition(target: CanvasItem, material_definition: Resource) -> ShaderMaterial:
	if target == null:
		return null

	if (
		material_definition == null
		or not material_definition.has_method("create_material")
	):
		target.material = null
		return null

	var material: ShaderMaterial = material_definition.create_material()
	target.material = material
	return material


static func set_lighting_enabled(material: ShaderMaterial, enabled: bool) -> void:
	if material != null:
		material.set_shader_parameter("lighting_enabled", 1.0 if enabled else 0.0)


static func set_world_light_direction(material: ShaderMaterial, node: Node2D, world_light_direction: Vector2) -> void:
	if material == null or node == null:
		return

	var normalized_world_light := world_light_direction.normalized()
	if normalized_world_light == Vector2.ZERO:
		normalized_world_light = Vector2(-0.55, -0.83).normalized()

	var local_light_direction := normalized_world_light.rotated(-node.global_rotation)
	material.set_shader_parameter("local_light_dir", local_light_direction)
