shader_type spatial;
// Procedural flame sprite for GPUParticles3D billboards: teardrop mask distorted by scrolling fbm noise,
// colour ramp white-yellow core -> orange -> deep red tips driven by particle age (INSTANCE_CUSTOM.y).
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform float intensity = 2.2;
uniform float seed = 0.0;
uniform float flame_speed = 1.6;

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
float fbm(vec2 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	age = INSTANCE_CUSTOM.y;
	rnd = fract(sin(float(INSTANCE_ID) * 12.9898 + seed) * 43758.5453);
	mat4 mw = mat4(
		normalize(INV_VIEW_MATRIX[0]) * length(MODEL_MATRIX[0]),
		normalize(INV_VIEW_MATRIX[1]) * length(MODEL_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]) * length(MODEL_MATRIX[2]),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV;                       // 0..1, v=0 at the top of the quad
	float y = 1.0 - uv.y;               // 0 bottom .. 1 top
	float x = (uv.x - 0.5) * 2.0;
	float t = TIME * flame_speed + rnd * 10.0;
	// noise warps the sprite sideways, more towards the tip
	float n1 = fbm(vec2(uv.x * 3.0 + rnd * 7.0, y * 3.2 - t * 1.4));
	float n2 = fbm(vec2(uv.x * 6.0 - rnd * 3.0, y * 5.0 - t * 2.2) + 7.3);
	x += (n1 - 0.5) * 0.9 * y;
	float width = (1.0 - pow(y, 1.15)) * (0.55 + 0.4 * sin(y * 3.14159));   // teardrop
	float d = abs(x) / max(width, 0.001);
	float body = smoothstep(1.0, 0.25, d);
	float fade_top = smoothstep(1.0, 0.55, y + (n2 - 0.5) * 0.45);
	float fade_bot = smoothstep(0.0, 0.1, y);
	float f = body * fade_top * fade_bot;
	f *= 0.55 + 0.9 * n2;
	float heat = clamp(f * (1.15 - age * 0.9), 0.0, 1.0);
	vec3 col = mix(vec3(0.55, 0.06, 0.01), vec3(1.0, 0.38, 0.05), smoothstep(0.1, 0.5, heat));
	col = mix(col, vec3(1.0, 0.82, 0.38), smoothstep(0.45, 0.85, heat));
	col = mix(col, vec3(1.0, 0.97, 0.8), smoothstep(0.85, 1.0, heat) * (1.0 - y));
	float life_fade = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.55, 1.0, age));
	ALBEDO = col * intensity * f * life_fade;
	ALPHA = clamp(f * life_fade, 0.0, 1.0);
}
