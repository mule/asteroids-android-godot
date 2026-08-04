shader_type canvas_item;

uniform vec4 base_tint : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(1.0);
uniform float emission_intensity : hint_range(0.0, 8.0) = 1.0;
uniform float lighting_enabled = 1.0;

void fragment() {
	vec3 base_color = COLOR.rgb * base_tint.rgb;
	vec3 emission = emission_color.rgb * emission_intensity;
	COLOR = vec4(base_color + emission, COLOR.a * base_tint.a);
}
