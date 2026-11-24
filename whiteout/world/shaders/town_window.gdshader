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

varying vec3 v_p;     // fragment position in window-local metres (glass plane z = 0, room behind at z < 0)
varying vec3 v_cam;   // camera in the same space

void vertex() {
	v_p = vec3(VERTEX.xy * win_size, 0.0);
	vec3 c = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	v_cam = vec3(c.xy * win_size, c.z);
}

// ray vs axis-aligned box, returns entry t (or 1e9) and entry normal
float box_hit(vec3 ro, vec3 rd, vec3 mn, vec3 mx, out vec3 nrm) {
	vec3 inv = 1.0 / rd;
	vec3 a = (mn - ro) * inv, b = (mx - ro) * inv;
	vec3 tn = min(a, b), tx = max(a, b);
	float t0 = max(max(tn.x, tn.y), tn.z), t1 = min(min(tx.x, tx.y), tx.z);
	if (t1 < max(t0, 0.0)) return 1e9;
	nrm = (t0 == tn.x) ? vec3(-sign(rd.x), 0, 0) : ((t0 == tn.y) ? vec3(0, -sign(rd.y), 0) : vec3(0, 0, -sign(rd.z)));
	return t0;
}

// Interior mapping: trace the view ray into a box room behind the glass.
// returns rgb brightness (white-ish, tinted later by win_col) and writes the hit depth
vec3 room(vec3 ro, vec3 rd, float s, bool shop, out float depth) {
	float a = h1(s), b = h1(s + 1.7), c = h1(s + 3.1);
	float rw = max(win_size.x * 1.8, shop ? 5.0 : 3.2);        // room width
	float D = shop ? mix(5.0, 8.0, a) : mix(2.6, 4.2, a);      // room depth
	float fl = -win_size.y * 0.5 - (shop ? 0.25 : 0.85);       // floor (sill ~0.85 m above it)
	float ce = fl + (shop ? 3.4 : 2.55);                       // ceiling
	vec3 bmin = vec3(-rw * 0.5 + (b - 0.5) * 0.8, fl, -D);
	vec3 bmax = vec3(bmin.x + rw, ce, 0.0);
	vec3 inv = 1.0 / rd;
	vec3 t1 = (bmin - ro) * inv, t2 = (bmax - ro) * inv;
	vec3 tf = max(t1, t2);
	float t = min(min(tf.x, tf.y), tf.z);
	vec3 h = ro + rd * t;
	depth = t;
	// which surface did we hit
	vec3 base;
	vec3 n;
	if (t == tf.z) { n = vec3(0, 0, 1); base = vec3(0.78, 0.7, 0.6); }                   // back wall
	else if (t == tf.y) {
		if (rd.y < 0.0) { n = vec3(0, 1, 0); base = vec3(0.42, 0.28, 0.18); }            // floor (wood)
		else { n = vec3(0, -1, 0); base = vec3(0.5, 0.48, 0.45); }                       // ceiling
	} else { n = vec3(-sign(rd.x), 0, 0); base = vec3(0.66, 0.58, 0.5); }               // side wall
	if (!shop && n.y < -0.5) base *= 1.0 - 0.5 * smoothstep(0.0, 1.5, -h.z);             // ceiling falls into shadow away from the lamp
	if (!shop) {
		// wallpaper stripes / a picture frame and a sofa back on the back wall
		if (n.z > 0.5) {
			base *= 0.9 + 0.1 * step(0.5, fract(h.x * 4.0 + s));
			vec2 pc = vec2(mix(bmin.x + 0.8, bmax.x - 0.8, c), fl + 1.6);
			vec2 q = abs(h.xy - pc) - vec2(0.42, 0.3);
			if (max(q.x, q.y) < 0.0) base = max(q.x, q.y) > -0.04 ? vec3(0.25, 0.18, 0.1) : vec3(0.35, 0.42, 0.38);
			if (h.y < fl + 0.85 && abs(h.x - pc.x) < 1.0) base = vec3(0.4, 0.22, 0.16) * (h.y < fl + 0.5 ? 1.0 : 0.8);
		}
		if (n.y > 0.5) base *= 0.85 + 0.15 * step(0.5, fract(h.x * 6.0));           // floor boards
		if (n.y > 0.5 && length((h.xz - vec2(0.0, -D * 0.5)) * vec2(0.6, 1.0)) < 0.9) base = vec3(0.45, 0.2, 0.15); // rug
		// a door opening on one side wall leading to a dark hall
		if (abs(n.x) > 0.5 && abs(h.z + D * 0.55) < 0.45 && h.y < fl + 2.05 && b > 0.4) base *= 0.15;
	} else {
		// free-standing aisle shelves (parallel to the glass) and a checkout counter by the window
		vec3 bn;
		bool furn = false;
		// shell first (walls/floor/ceiling patterns), furniture drawn over it
		if (n.y < 0.5) base *= 0.6 + 0.4 * smoothstep(0.02, 0.06, abs(fract((h.y - fl) * 2.2) - 0.5));
		if (n.y < 0.5 && n.y > -0.5 && fract((h.y - fl) * 2.2) < 0.45 && h.y < ce - 0.8) base *= mix(vec3(0.6, 0.9, 1.2), vec3(1.2, 0.8, 0.6), h1(floor(h.x * 3.0) + s));
		if (n.y > 0.5) base *= 0.8 + 0.2 * step(0.5, fract(h.x * 1.6) + step(0.5, fract(h.z * 1.6)) * 0.5);
		if (n.y < -0.5) base *= 1.0 + 3.0 * smoothstep(0.08, 0.0, abs(fract(h.z * 0.4) - 0.5) - 0.06) * step(abs(h.x), 0.6); // tube lights
		for (int k = 0; k < 3; k++) {
			float zc = -D * (0.3 + 0.22 * float(k));
			float hw = rw * 0.32;
			float ox = (h1(s + float(k)) - 0.5) * 1.2;
			float tb = box_hit(ro, rd, vec3(ox - hw, fl, zc - 0.3), vec3(ox + hw, fl + 1.55, zc + 0.3), bn);
			if (tb < t) {
				t = tb; h = ro + rd * t; n = bn; depth = t;
				base = vec3(0.35, 0.36, 0.38);
				if (n.z > 0.5) {
					float row = fract((h.y - fl) * 2.6);
					base = row < 0.62 ? mix(vec3(0.8, 0.25, 0.15), vec3(0.2, 0.45, 0.7), h1(floor(h.x * 7.0) + float(k) * 3.0 + s)) * 0.9 : vec3(0.75);
					if (h.y < fl + 0.12) base = vec3(0.15);
				}
			}
		}
		float tc = box_hit(ro, rd, vec3(bmin.x + 0.3, fl, -1.4), vec3(bmin.x + 1.6, fl + 1.0, -0.8), bn);
		if (tc < t) { t = tc; h = ro + rd * t; n = bn; depth = t; base = vec3(0.4, 0.3, 0.22); }
	}
	// lighting: a lamp (or ceiling tubes) inside the room, falloff + facing term
	vec3 lp = shop ? vec3(0.0, ce - 0.3, -D * 0.5) : vec3(mix(bmin.x + 0.5, bmax.x - 0.5, a), fl + 1.3, -D * mix(0.35, 0.75, b));
	vec3 L = lp - h;
	float dl = length(L);
	float lit = max(dot(n, L / dl), 0.0) * (shop ? 2.4 : 2.6) / (1.0 + dl * dl * (shop ? 0.08 : 1.1));
	float amb = shop ? 0.12 : 0.04;
	vec3 cl = base * (amb + lit);
	if (!shop) {
		// the lamp itself: a glowing fabric shade where the ray passes close to it
		vec3 w = lp - ro;
		float tl = clamp(dot(w, rd), 0.0, t);
		vec3 q = ro + rd * tl - lp;
		float shade = smoothstep(0.17, 0.12, length(q * vec3(1.0, 1.4, 1.0)));
		cl = mix(cl, vec3(2.2, 1.7, 1.1), shade * step(tl, t));
		cl += vec3(1.0, 0.75, 0.45) * 0.25 * exp(-dot(q, q) * 6.0);
	}
	return cl;
}

void fragment() {
	vec2 uv = UV;                       // (0,0) top-left
	float s = win_seed;
	float a = h1(s), b = h1(s + 1.7), c = h1(s + 3.1), d = h1(s + 5.9);
	// interior: warm lamp hot-spot somewhere low in the room, darker ceiling corners
	vec3 rd = normalize(v_p - v_cam);
	float depth;
	vec3 rm = room(v_p, rd.z < -0.02 ? rd : normalize(vec3(rd.xy, -0.02)), s, win_mode > 2.5, depth);
	float pat = 1.0;
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
			float zp = -mix(0.8, 1.6, b);
			float tp = zp / min(rd.z, -0.02);
			vec3 hp = v_p + rd * tp;
			if (tp < depth) {
				float fl = -win_size.y * 0.5 - 0.85;
				float px = mix(-0.6, 0.6, a) + 0.12 * sin(TIME * 0.3 + s);
				float head = length((hp.xy - vec2(px, fl + 1.62)) * vec2(1.0, 0.85)) - 0.11;
				float torso = length(max(abs(hp.xy - vec2(px, fl + 1.1)) - vec2(0.16, 0.38), 0.0)) - 0.06;
				float body = smoothstep(0.02, -0.02, min(head, torso));
				pat *= 1.0 - body * 0.9;
			}
		}
	} else {
		// shop: flat bright tube light, shelves as darker horizontal bands
		pat = 1.0;
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
		pat = mix(pat, 1.3, 0.4);
	} else if (win_mode > 1.5 && win_mode < 2.5) {
		float t = floor(TIME * 14.0 + s * 5.0);
		e *= (h1(t) < 0.22) ? 0.08 : (0.8 + 0.2 * h1(t + 2.0));
	}
	ALBEDO = mix(col, vec3(1.0, 0.9, 0.8), 0.25) * rm * pat * e * 0.6 * win_power;
}
