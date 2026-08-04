shader_type canvas_item;

uniform vec4 base_tint : source_color = vec4(1.0);
uniform vec2 local_light_dir = vec2(-0.55, -0.83);
uniform float ambient : hint_range(0.0, 1.0) = 0.32;
uniform float diffuse_strength : hint_range(0.0, 2.0) = 0.72;
uniform int light_band_count : hint_range(1, 8) = 4;
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.08;
uniform int noise_seed = 0;
uniform float noise_scale : hint_range(0.0, 0.25) = 0.035;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.18;
uniform float facet_strength : hint_range(0.0, 1.0) = 0.65;
uniform float lighting_enabled = 1.0;

varying vec2 local_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + float(noise_seed) * 17.17) * 43758.5453123);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 facet_cell = floor(local_pos * max(noise_scale, 0.001));
	float angle = hash(facet_cell) * 6.28318530718;
	vec2 facet_normal = vec2(cos(angle), sin(angle));
	vec2 radial_normal = normalize(local_pos);
	vec2 normal_dir = normalize(mix(radial_normal, facet_normal, facet_strength));
	vec2 light_dir = normalize(local_light_dir);
	float diffuse = max(dot(normal_dir, -light_dir), 0.0);
	float bands = max(float(light_band_count), 1.0);
	float stepped = floor(diffuse * bands) / max(bands - 1.0, 1.0);
	float grain = (hash(facet_cell + vec2(23.0, 41.0)) - 0.5) * noise_strength;
	float lighting = ambient + stepped * diffuse_strength + grain;
	vec3 shaded = COLOR.rgb * base_tint.rgb * clamp(lighting, 0.0, 1.6);
	vec3 highlight = vec3(highlight_strength) * pow(diffuse, 5.0);
	vec3 unlit = COLOR.rgb * base_tint.rgb;
	COLOR = vec4(mix(unlit, shaded + highlight, lighting_enabled), COLOR.a * base_tint.a);
}
