shader_type spatial;
// Lit window card (world/town.gd): additive interior glow laid over the building's own window texture.
// One material for every card; per-window look comes from instance uniforms.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

instance uniform vec4 win_col : source_color = vec4(1.0, 0.62, 0.3, 1.0);
instance uniform float win_energy = 2.0;
instance uniform float win_mode = 0.0;    // 0 steady lamp, 1 TV (blue flicker), 2 faulty bulb, 3 shop (bright, no curtains)
instance uniform float win_seed = 0.0;
instance uniform float win_power = 1.0;   // 0..1 (staggered power-on)
instance uniform vec2 win_size = vec2(1.0, 1.5);

float h1(float x) { return fract(sin(x * 91.731 + 7.13) * 43758.5453); }
float n1(float x) { float i = floor(x); float f = fract(x); return mix(h1(i), h1(i + 1.0), f * f * (3.0 - 2.0 * f)); }

void fragment() {
	vec2 uv = UV;                       // (0,0) top-left
	float s = win_seed;
	float a = h1(s), b = h1(s + 1.7), c = h1(s + 3.1), d = h1(s + 5.9);
	// interior: warm lamp hot-spot somewhere low in the room, darker ceiling corners
	vec2 lp = vec2(mix(0.2, 0.8, a), mix(0.45, 0.8, b));
	vec2 dd = (uv - lp) * vec2(win_size.x, win_size.y) / max(win_size.x, win_size.y);
	float lamp = 0.35 + 0.9 * exp(-dot(dd, dd) * 6.0);
	float room = mix(0.75, 1.0, uv.y) * lamp;
	float pat = room;
	vec3 col = win_col.rgb;
	if (win_mode < 2.5) {
		// curtains / blinds
		if (c < 0.55) {
			float cw = mix(0.1, 0.34, d);
			float fold = 0.75 + 0.25 * sin(uv.x * win_size.x * 38.0 + s * 3.0);
			float cl = smoothstep(cw, cw - 0.05, uv.x);
			float cr = smoothstep(1.0 - cw, 1.0 - cw + 0.05, uv.x);
			float cur = max(cl, cr);
			// curtain fabric transmits a dimmer, redder light
			pat = mix(pat, 0.38 * fold, cur);
			col = mix(col, col * vec3(1.0, 0.75, 0.6), cur);
		} else if (c < 0.8) {
			float lvl = mix(0.25, 0.75, d);             // venetian blind pulled half down
			float slat = 0.35 + 0.65 * smoothstep(0.35, 0.55, fract(uv.y * win_size.y * 9.0));
			pat *= mix(1.0, slat * 0.55, step(uv.y, lvl));
		}
		// sash mullions on house windows
		if (win_size.x < 1.6) {
			float m = smoothstep(0.012, 0.0, abs(uv.y - 0.5) - 0.012) * 0.85;
			pat *= 1.0 - m;
		}
		// someone's silhouette / a plant in one window out of eight
		if (h1(s + 9.3) < 0.125) {
			vec2 q = (uv - vec2(mix(0.3, 0.7, a), 0.72)) * vec2(1.0, 0.55) * win_size / max(win_size.x, 0.5);
			float body = smoothstep(0.17, 0.12, length(q));
			pat *= 1.0 - body * 0.85;
		}
	} else {
		// shop: flat bright tube light, shelves as darker horizontal bands
		pat = 0.9 + 0.1 * uv.y;
		pat *= 1.0 - 0.35 * smoothstep(0.03, 0.0, abs(fract(uv.y * 3.0) - 0.5) - 0.03);
	}
	// soft frosted edges: ice creeping in from the bottom corners
	float fx = min(uv.x, 1.0 - uv.x) * win_size.x;
	float fy = (1.0 - uv.y) * win_size.y;
	float frost = smoothstep(0.0, 0.35, fx + fy * 0.8 + 0.1 * n1(uv.x * 30.0 + s));
	pat *= mix(0.45, 1.0, frost);
	pat *= smoothstep(0.0, 0.03, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)) * min(win_size.x, win_size.y));
	float e = win_energy;
	if (win_mode > 0.5 && win_mode < 1.5) {
		// TV: brightness and tint jump every few frames
		float t = floor(TIME * 7.0 + s * 13.0);
		e *= 0.45 + 0.75 * h1(t);
		col = mix(vec3(0.45, 0.62, 1.0), vec3(0.85, 0.9, 1.0), h1(t + 0.5));
		pat = mix(pat, 0.7 + 0.3 * uv.y, 0.6);
	} else if (win_mode > 1.5 && win_mode < 2.5) {
		float t = floor(TIME * 14.0 + s * 5.0);
		e *= (h1(t) < 0.22) ? 0.08 : (0.8 + 0.2 * h1(t + 2.0));
	}
	ALBEDO = col * pat * e * win_power;
}
