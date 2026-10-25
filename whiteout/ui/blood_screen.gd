extends ColorRect
## Blood on the lens: a full-screen overlay that splatters when the player is hurt, runs and
## dries over a few seconds, and stays at the edges (pulsing) while health is low.
## Owned by the gore system; UI adds it under the HUD and calls hit() from flash_damage().
## Also ticks Gore.player_bleed() so a wounded player leaves a blood trail.

const Gore = preload("res://world/gore.gd")

const SHADER := """shader_type canvas_item;
uniform sampler2D blood : repeat_disable, filter_linear_mipmap;
uniform sampler2D blood_n : repeat_disable, filter_linear_mipmap;
uniform vec4 xf_a = vec4(1.0, 0.0, 0.0, 1.0);   // 2x2 uv transform (layer A)
uniform vec4 xf_b = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec4 xf_c = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec2 off_a = vec2(0.0);
uniform vec2 off_b = vec2(0.0);
uniform vec2 off_c = vec2(0.0);
uniform float amt_a = 0.0;
uniform float amt_b = 0.0;
uniform float amt_c = 0.0;     // chronic low-health layer
uniform float time_c = 0.0;

vec2 xf(vec2 uv, vec4 m, vec2 o) {
	vec2 p = uv - vec2(0.5);
	return vec2(m.x * p.x + m.y * p.y, m.z * p.x + m.w * p.y) + vec2(0.5) + o;
}

// returns rgb + coverage for one layer. amt: 1 = fresh, 0 = gone; the stain runs down as it dries.
vec4 layer(vec2 uv, vec4 m, vec2 o, float amt, float edge_bias) {
	if (amt <= 0.001) return vec4(0.0);
	vec2 q = xf(uv, m, o);
	q.y -= (1.0 - amt) * 0.035;                // slow run-down
	if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) return vec4(0.0);
	vec4 t = texture(blood, q);
	vec3 n = normalize(texture(blood_n, q).xyz * 2.0 - 1.0);
	vec3 l = normalize(vec3(-0.45, -0.55, 0.7));
	float diff = clamp(dot(n, l), 0.0, 1.0);
	float spec = pow(clamp(dot(reflect(-l, n), vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 22.0);
	vec3 col = t.rgb * (0.45 + 0.7 * diff) * mix(1.0, 0.55, 1.0 - amt) + vec3(0.9, 0.5, 0.5) * spec * 0.22 * amt;
	// stains dry from the thin edges inward: threshold rises as amt falls
	float a = smoothstep(0.0, 0.25, t.a - (1.0 - amt) * 0.75) * clamp(amt * 2.0, 0.0, 1.0);
	return vec4(col, a * edge_bias);
}

void fragment() {
	vec2 uv = UV;
	float edge = smoothstep(0.1, 0.62, length((uv - vec2(0.5)) * vec2(1.25, 1.0)));
	vec4 a = layer(uv, xf_a, off_a, amt_a, mix(0.75, 1.0, edge));
	vec4 b = layer(uv, xf_b, off_b, amt_b, mix(0.75, 1.0, edge));
	float pulse = 0.88 + 0.12 * sin(time_c * 5.5);
	vec4 c = layer(uv, xf_c, off_c, amt_c * pulse, edge);
	vec4 o = a;
	if (b.a > o.a) o = b;
	if (c.a > o.a) o = c;
	// deep red wash at the very edges when badly hurt
	float wash = amt_c * edge * 0.35 * pulse;
	COLOR = vec4(mix(o.rgb, vec3(0.16, 0.0, 0.0), clamp(wash / max(o.a + wash, 0.001), 0.0, 1.0)), clamp(o.a + wash, 0.0, 1.0));
}
"""

var _mat: ShaderMaterial
var _a := 0.0
var _b := 0.0
var _next_b := false
var _chronic := 0.0
var _t := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(1, 1, 1, 1)
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	if ResourceLoader.exists("res://textures/gore/screen_blood_a.png"):
		_mat.set_shader_parameter("blood", load("res://textures/gore/screen_blood_a.png"))
		_mat.set_shader_parameter("blood_n", load("res://textures/gore/screen_blood_n.png"))
	material = _mat
	_randomize("a")
	_randomize("b")
	_randomize("c")

func _randomize(layer: String) -> void:
	var ang := randf() * TAU
	var flip := 1.0 if randf() < 0.5 else -1.0
	var s := randf_range(0.9, 1.25)
	var c := cos(ang) / s
	var sn := sin(ang) / s
	_mat.set_shader_parameter("xf_" + layer, Vector4(c * flip, sn, -sn * flip, c))
	_mat.set_shader_parameter("off_" + layer, Vector2(randf_range(-0.08, 0.08), randf_range(-0.08, 0.08)))

## A hit: splatters a fresh stain (alternating between two layers so hits stack).
func hit(intensity := 1.0) -> void:
	# freezing-cloud damage also calls flash_damage(): that is not blood
	if Game.player != null and is_instance_valid(Game.player) and Game.player.has_meta("slow"):
		return
	Gore.player_hurt_fx()
	if _next_b:
		_randomize("b")
		_b = clamp(0.55 + 0.5 * intensity, 0.0, 1.0)
	else:
		_randomize("a")
		_a = clamp(0.55 + 0.5 * intensity, 0.0, 1.0)
	_next_b = not _next_b

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_t += delta
	_a = max(0.0, _a - delta * 0.17)
	_b = max(0.0, _b - delta * 0.17)
	var frac := float(Game.hp) / float(Game.MAX_HP)
	var want: float = clamp((0.5 - frac) / 0.5, 0.0, 1.0) * 0.85 if Game.hp > 0 else 0.9
	_chronic = move_toward(_chronic, want, delta * 0.4)
	_mat.set_shader_parameter("amt_a", _a)
	_mat.set_shader_parameter("amt_b", _b)
	_mat.set_shader_parameter("amt_c", _chronic)
	_mat.set_shader_parameter("time_c", _t)
	Gore.player_bleed(delta)
