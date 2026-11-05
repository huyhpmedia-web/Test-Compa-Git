shader_type spatial;
// Generic PBR prop shader with a wind-blown "snow on top" mask driven by the WORLD normal.
// Used by world/env_assets.gd for every imported .glb prop, tree and vehicle.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable; // R=ao G=rough B=metal
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float roughness_mul = 1.0;
uniform float metallic_mul = 1.0;
uniform float normal_depth = 1.0;
uniform vec2 uv_scale = vec2(1.0);
uniform bool use_orm = true;

uniform float snow_amount : hint_range(0.0, 1.0) = 0.6;
uniform vec3 snow_color : source_color = vec3(0.86, 0.89, 0.94);
uniform float snow_sharp = 4.0;
uniform bool two_sided = false;
uniform float world_noise_scale = 2.3;
uniform float emission_energy = 0.0;
uniform vec3 emission_color : source_color = vec3(1.0);

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
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 a = texture(albedo_tex, uv) * albedo_tint;
	vec3 n_geo = normalize(wnormal);
	if (two_sided && !FRONT_FACING) {
		n_geo = -n_geo;
	}
	// snow cover: up-facing surfaces, broken up with world-space noise
	float nz = vnoise(wpos.xz * world_noise_scale + wpos.y * 0.7) * 0.6 + vnoise(wpos.xz * world_noise_scale * 3.1) * 0.4;
	float up = n_geo.y;
	float m = clamp((up - (0.55 - 0.45 * snow_amount) + (nz - 0.5) * 0.45) * snow_sharp, 0.0, 1.0);
	m *= step(0.001, snow_amount);
	vec3 alb = mix(a.rgb, snow_color * (0.92 + 0.08 * nz), m);
	ALBEDO = alb;
	vec3 orm = use_orm ? texture(orm_tex, uv).rgb : vec3(1.0, 0.7, 0.0);
	float rough = mix(orm.g * roughness_mul, 0.72, m);
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = mix(orm.b * metallic_mul, 0.0, m);
	AO = mix(orm.r, 1.0, m * 0.6);
	AO_LIGHT_AFFECT = 0.4;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth * mix(1.0, 0.18, m);
	if (emission_energy > 0.0) {
		EMISSION = emission_color * emission_energy;
	}
}
