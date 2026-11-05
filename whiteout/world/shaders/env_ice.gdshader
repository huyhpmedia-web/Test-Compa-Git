shader_type spatial;
// Translucent ice: screen-space refraction, fresnel rim, subsurface tint and internal cloudiness. Opaque pass (no sorting issues).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.45, 0.75, 0.92);
uniform float refract_amt = 0.045;
uniform float glow = 0.35;
varying vec3 wpos;
float hash21(vec2 p){ p = fract(p*vec2(123.34,456.21)); p += dot(p,p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){ vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y); }
void vertex(){ wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.5);
	float cloud = vnoise(wpos.xy*3.0 + wpos.z*1.7)*0.6 + vnoise(wpos.zy*7.0)*0.4;
	vec2 off = NORMAL.xy * refract_amt * (0.6 + cloud);
	vec3 bg = textureLod(screen_tex, SCREEN_UV + off, 1.0 + cloud * 2.0).rgb;
	ALBEDO = tint * (0.25 + 0.2 * cloud);
	EMISSION = bg * (0.55 - 0.25 * fres) * tint * 1.4 + tint * (glow * (0.4 + cloud * 0.6) + fres * 0.5);
	ROUGHNESS = 0.06 + cloud * 0.12;
	SPECULAR = 0.9;
	METALLIC = 0.0;
}
