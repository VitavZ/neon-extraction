extends CanvasLayer
## Efekt ekranu CRT (jak w Agrivore): linie skanowania, delikatna aberracja kolorów i winieta.
## Włącz/wyłącz klawiszem z ustawień (domyślnie F2).
## Pod spodem warstwa "komfortu oczu" (ustawienie JASKRAWOŚĆ): przygasza nasycenie i zbyt jasne
## miejsca obrazu oraz osłabia poświatę neonów. Działa niezależnie od filtra CRT.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float scan_strength = 0.13;
uniform float vignette = 0.55;
uniform float aberration = 0.0007;
uniform float noise = 0.025;

float rand(vec2 co) { return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	// aberracja tylko przy krawędziach ekranu - środek (tekst, HUD) zostaje ostry
	float ab = aberration * smoothstep(0.12, 0.5, dot(d, d) * 2.0);
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(ab, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(ab, 0.0)).b;
	float line = sin(FRAGCOORD.y * 3.14159265) * 0.5 + 0.5;
	col *= 1.0 - scan_strength * line;
	col += (rand(FRAGCOORD.xy + vec2(TIME * 37.0, TIME * 13.0)) - 0.5) * noise;
	float v = 1.0 - dot(d, d) * vignette * 1.6;
	col *= clamp(v, 0.0, 1.0);
	COLOR = vec4(col, 1.0);
}
"""

const COMFORT_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float desat = 0.25;     // ile nasycenia zabrać
uniform float knee = 0.55;      // od tej jasności światła są łagodnie ściskane
uniform float squash = 1.5;     // siła ściskania jasnych miejsc
uniform float dim = 0.9;        // ogólna jasność

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(c, vec3(l), desat);
	vec3 over = max(c - knee, vec3(0.0));
	c = min(c, vec3(knee)) + over / (1.0 + over * squash);
	COLOR = vec4(c * dim, 1.0);
}
"""

## Poziomy jaskrawości: [nazwa, odbarwienie, próg, ściskanie, jasność, mnożnik poświaty]
const COMFORT_LEVELS := [
	["NEON", 0.0, 1.0, 0.0, 1.0, 1.0],
	["STONOWANA", 0.22, 0.6, 1.2, 0.92, 0.65],
	["ŁAGODNA", 0.38, 0.5, 2.2, 0.84, 0.4],
]

var rect: ColorRect
var comfort_layer: CanvasLayer
var comfort: ColorRect
var env: Environment
var base_glow := 0.0


func _ready() -> void:
	layer = 100
	rect = ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	add_child(rect)
	rect.visible = bool(GameState.settings["crt"])
	# komfort oczu: osobna warstwa tuż pod CRT, żeby CRT widział już przygaszony obraz
	comfort_layer = CanvasLayer.new()
	comfort_layer.layer = 99
	add_child(comfort_layer)
	comfort = ColorRect.new()
	comfort.mouse_filter = Control.MOUSE_FILTER_IGNORE
	comfort.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var csh := Shader.new()
	csh.code = COMFORT_SHADER
	var cmat := ShaderMaterial.new()
	cmat.shader = csh
	comfort.material = cmat
	comfort_layer.add_child(comfort)
	# poświata sceny (WorldEnvironment obok nas) też jest przygaszana
	if get_parent():
		for c in get_parent().get_children():
			if c is WorldEnvironment and c.environment:
				env = c.environment
				base_glow = env.glow_intensity
	apply_comfort()


static func comfort_name() -> String:
	return String(COMFORT_LEVELS[clampi(int(GameState.settings.get("comfort", 1)), 0, COMFORT_LEVELS.size() - 1)][0])


func apply_comfort() -> void:
	var lv: Array = COMFORT_LEVELS[clampi(int(GameState.settings.get("comfort", 1)), 0, COMFORT_LEVELS.size() - 1)]
	comfort.visible = float(lv[1]) > 0.0
	var m: ShaderMaterial = comfort.material
	m.set_shader_parameter("desat", lv[1])
	m.set_shader_parameter("knee", lv[2])
	m.set_shader_parameter("squash", lv[3])
	m.set_shader_parameter("dim", lv[4])
	if env:
		env.glow_intensity = base_glow * float(lv[5])


func _unhandled_input(event: InputEvent) -> void:
	if GameState.key_hit(event, "crt"):
		rect.visible = not rect.visible
		GameState.settings["crt"] = rect.visible
		GameState.save_settings()
