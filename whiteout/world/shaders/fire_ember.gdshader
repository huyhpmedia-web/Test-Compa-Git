shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform float glow = 6.0;
varying float age;
varying float idf;
void vertex() {
	age = INSTANCE_CUSTOM.y;
	idf = float(INSTANCE_ID);
	mat4 mw = mat4(
		normalize(INV_VIEW_MATRIX[0]) * length(MODEL_MATRIX[0]),
		normalize(INV_VIEW_MATRIX[1]) * length(MODEL_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]) * length(MODEL_MATRIX[2]),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float a = smoothstep(1.0, 0.0, r);
	a *= a;
	float flick = 0.6 + 0.4 * sin(TIME * 23.0 + idf * 3.7);
	vec3 c = mix(vec3(1.0, 0.65, 0.2), vec3(0.8, 0.12, 0.02), age);
	ALBEDO = c * glow * a * flick * (1.0 - age);
	ALPHA = a * (1.0 - age);
}
