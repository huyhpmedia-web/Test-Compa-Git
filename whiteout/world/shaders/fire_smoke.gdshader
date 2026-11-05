shader_type spatial;
// Soft smoke puffs: blended, noisy, dark, fading with age.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

uniform vec3 smoke_color : source_color = vec3(0.09, 0.09, 0.1);
uniform float density = 0.32;
varying float age;
varying float rnd;

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
	age = INSTANCE_CUSTOM.y;
	rnd = fract(sin(float(INSTANCE_ID) * 78.233) * 43758.5453);
	mat4 mw = mat4(
		normalize(INV_VIEW_MATRIX[0]) * length(MODEL_MATRIX[0]),
		normalize(INV_VIEW_MATRIX[1]) * length(MODEL_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]) * length(MODEL_MATRIX[2]),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float n = vnoise(p * 2.5 + rnd * 20.0 + TIME * 0.15) * 0.6 + vnoise(p * 5.0 - rnd * 9.0) * 0.4;
	float a = smoothstep(1.0, 0.1, r + (n - 0.5) * 0.6);
	a *= smoothstep(0.0, 0.2, age) * (1.0 - smoothstep(0.35, 1.0, age));
	ALBEDO = smoke_color + vec3(0.08) * (1.0 - age);
	ALPHA = a * density;
}
