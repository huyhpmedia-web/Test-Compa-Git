shader_type spatial;
// Conifer needle cards: alpha-scissor frond atlas, snow settles on up-facing cards and fills the gaps.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D frond_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D clump_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.8;
uniform vec3 snow_color : source_color = vec3(0.86, 0.89, 0.94);
uniform float world_noise_scale = 1.7;

varying vec3 wpos;
varying vec3 wnormal;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// gentle wind sway, stronger with height above the ground
	float h = max(wpos.y - MODEL_MATRIX[3].y, 0.0);
	float s = sin(TIME * 0.9 + MODEL_MATRIX[3].x * 0.7 + MODEL_MATRIX[3].z * 0.5 + VERTEX.x * 0.4) * 0.012 * h * 0.12;
	VERTEX.x += s;
}

void fragment() {
	vec4 f = texture(frond_tex, UV);
	float clump = texture(clump_tex, UV).r;
	vec3 n = normalize(wnormal);
	if (!FRONT_FACING) n = -n;
	float nz = vnoise(wpos.xz * world_noise_scale + wpos.y * 0.5);
	float upmask = clamp((n.y - 0.15 + (nz - 0.5) * 0.5) * 3.0, 0.0, 1.0) * snow_amount;
	float snow = upmask * clump;
	float alpha = max(f.a, snow * 0.95);
	if (alpha < 0.5) discard;
	vec3 base = f.rgb * tint.rgb;
	vec3 alb = mix(base, snow_color * (0.9 + 0.1 * nz), clamp(snow * 1.6, 0.0, 1.0));
	ALBEDO = alb;
	ROUGHNESS = mix(0.82, 0.7, snow);
	SPECULAR = 0.25;
	AO = 1.0;
	// translucent backlight so thin cards don't go black
	BACKLIGHT = vec3(0.04, 0.07, 0.05) * (1.0 - snow);
	NORMAL = n;
}
