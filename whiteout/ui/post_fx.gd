extends CanvasLayer
## Full-screen "camera" pass over the 3D view (below every UI layer): RE7-style film grain, subtle
## chromatic aberration toward the edges, lens vignette and a cold/teal shadow grade. Added by UI._ready().
## Settings: UI.post_fx.strength (0 = off).

var rect: ColorRect
var mat: ShaderMaterial

const SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.045;
uniform float aberration = 0.0022;
uniform float vignette = 0.42;
uniform float strength = 1.0;
uniform vec3 shadow_tint = vec3(0.92, 0.98, 1.06);
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - vec2(0.5);
	float r2 = dot(d, d);
	vec2 off = d * aberration * (0.6 + 4.0 * r2) * strength;
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, col * shadow_tint, (1.0 - smoothstep(0.0, 0.45, lum)) * strength);
	float v = 1.0 - vignette * strength * smoothstep(0.12, 0.62, r2 * 1.6);
	col *= v;
	float n = hash(uv * vec2(1920.0, 1080.0) + fract(TIME * 13.0) * 97.0) - 0.5;
	col += n * grain * strength * (1.15 - lum);
	COLOR = vec4(col, 1.0);
}
"""

func _ready() -> void:
	layer = 1
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	add_child(rect)

func set_strength(s: float) -> void:
	mat.set_shader_parameter("strength", s)
	rect.visible = s > 0.001
