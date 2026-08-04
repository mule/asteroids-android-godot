shader_type canvas_item;

uniform vec4 base_tint : source_color = vec4(1.0);
uniform vec2 local_light_dir = vec2(-0.55, -0.83);
uniform float ambient : hint_range(0.0, 1.0) = 0.35;
uniform float diffuse_strength : hint_range(0.0, 2.0) = 0.65;
uniform int light_band_count : hint_range(1, 8) = 4;
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.15;
uniform float lighting_enabled = 1.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 normal_dir = normalize(local_pos + vec2(0.0, -16.0));
	vec2 light_dir = normalize(local_light_dir);
	float diffuse = max(dot(normal_dir, -light_dir), 0.0);
	float bands = max(float(light_band_count), 1.0);
	float stepped = floor(diffuse * bands) / max(bands - 1.0, 1.0);
	float lighting = ambient + stepped * diffuse_strength;
	vec3 lit = COLOR.rgb * base_tint.rgb * lighting;
	vec3 highlight = vec3(highlight_strength) * pow(diffuse, 4.0);
	vec3 shaded = lit + highlight;
	vec3 unlit = COLOR.rgb * base_tint.rgb;
	COLOR = vec4(mix(unlit, shaded, lighting_enabled), COLOR.a * base_tint.a);
}
