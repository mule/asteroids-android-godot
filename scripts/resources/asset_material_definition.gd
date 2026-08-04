extends Resource
class_name AssetMaterialDefinition


enum ShaderMode {
	UNLIT,
	LIT_VECTOR,
	ASTEROID_FACETED,
	EMISSIVE,
}


@export var material_id: StringName
@export var shader_mode: ShaderMode = ShaderMode.UNLIT
@export var shader: Shader
@export var base_tint: Color = Color.WHITE
@export_range(0.0, 1.0, 0.01) var ambient: float = 0.35
@export_range(0.0, 2.0, 0.01) var diffuse_strength: float = 0.65
@export_range(1, 8, 1) var light_band_count: int = 4
@export_range(0.0, 1.0, 0.01) var highlight_strength: float = 0.15
@export var emission_color: Color = Color.TRANSPARENT
@export_range(0.0, 8.0, 0.01, "or_greater") var emission_intensity: float = 0.0
@export var noise_seed: int = 0
@export_range(0.0, 0.25, 0.001) var noise_scale: float = 0.035
@export_range(0.0, 1.0, 0.01) var noise_strength: float = 0.0
@export_range(0.0, 1.0, 0.01) var facet_strength: float = 0.0


func create_material() -> ShaderMaterial:
	if shader == null:
		return null

	var material := ShaderMaterial.new()
	material.shader = shader
	apply_to_material(material)
	return material


func apply_to_material(material: ShaderMaterial) -> void:
	if material == null:
		return

	material.set_shader_parameter("base_tint", base_tint)
	material.set_shader_parameter("ambient", ambient)
	material.set_shader_parameter("diffuse_strength", diffuse_strength)
	material.set_shader_parameter("light_band_count", light_band_count)
	material.set_shader_parameter("highlight_strength", highlight_strength)
	material.set_shader_parameter("emission_color", emission_color)
	material.set_shader_parameter("emission_intensity", emission_intensity)
	material.set_shader_parameter("noise_seed", noise_seed)
	material.set_shader_parameter("noise_scale", noise_scale)
	material.set_shader_parameter("noise_strength", noise_strength)
	material.set_shader_parameter("facet_strength", facet_strength)
