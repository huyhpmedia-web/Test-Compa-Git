shader_type spatial;
// Textured ice formation (rock base + ice in one baked texture): bluish texels become translucent-looking ice
// (screen-space refraction, rim, subsurface glow); the rest stays rock.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.5, 0.78, 0.95);
uniform float refract_amt = 0.04;
uniform float glow = 0.3;
void fragment(){
	vec3 a = texture(albedo_tex, UV).rgb;
	float ice = smoothstep(0.0, 0.1, a.b - a.r) * smoothstep(0.25, 0.5, a.b + a.g);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.5);
	vec3 bg = textureLod(screen_tex, SCREEN_UV + NORMAL.xy * refract_amt, 1.5).rgb;
	ALBEDO = mix(a, a * 0.35, ice);
	EMISSION = ice * (bg * tint * 0.7 + tint * (glow + fres * 0.5));
	vec3 orm = texture(orm_tex, UV).rgb;
	ROUGHNESS = mix(orm.g, 0.06, ice);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.95, ice);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.4, ice);
}
