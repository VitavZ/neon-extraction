extends Control
## Ekran startowy: włączenie monitora CRT, rysujący się Statek Matka, napis "IMPERIUM VEX PRZEDSTAWIA",
## a na końcu monitor gaśnie i otwiera się menu główne. Dowolny klawisz lub klik przewija do końca.

const Style = preload("res://scripts/style.gd")
const CrtScript = preload("res://scripts/crt.gd")

const POWER_ON := 0.7
const EMBLEM_END := 2.5
const TEXT_START := 2.75
const TEXT_END := 4.3
const HOLD_END := 5.8
const OFF_LEN := 0.6
const STUDIO := "IMPERIUM VEX"
const PRESENTS := "PRZEDSTAWIA"

var t := 0.0
var pf: Font
var cue := {}          # dźwięki już zagrane
var leaving := false


func _ready() -> void:
	pf = Style.font_pixel()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = bool(GameState.settings["glow"])
	env.glow_intensity = 0.45
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	we.environment = env
	add_child(we)
	add_child(CrtScript.new())


func _process(delta: float) -> void:
	t += delta
	_cue("imperial", POWER_ON * 0.6)
	_cue("dock", EMBLEM_END)
	_cue("launch", HOLD_END)
	if t >= HOLD_END + OFF_LEN + 0.15 and not leaving:
		leaving = true
		get_tree().change_scene_to_file("res://menu.tscn")
	queue_redraw()


func _cue(sfx: String, at: float) -> void:
	if t >= at and not cue.has(sfx):
		cue[sfx] = true
		Audio.play(sfx, 0.0, -4.0)


## Klik albo klawisz: od razu gaśnięcie ekranu.
func _gui_input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		_skip()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_skip()


func _skip() -> void:
	if t < HOLD_END:
		t = HOLD_END
		cue["imperial"] = true
		cue["dock"] = true


func _ease(k: float) -> float:
	var c := clampf(k, 0.0, 1.0)
	return 1.0 - pow(1.0 - c, 3.0)


func _draw() -> void:
	var vs := get_viewport_rect().size
	var c := vs * 0.5 + Vector2(0, -40)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0))
	# włączanie: jasna linia, która rozwiera się w obraz
	if t < POWER_ON:
		var k := t / POWER_ON
		var w := vs.x * _ease(k * 1.6)
		var h := maxf(2.0, vs.y * pow(maxf(0.0, k - 0.55) / 0.45, 2.0))
		draw_rect(Rect2(c.x - w * 0.5, vs.y * 0.5 - h * 0.5, w, h), Color(0.6, 0.9, 1.3, 1.0 - maxf(0.0, k - 0.55) * 1.6))
		return
	# gaśnięcie: obraz zgniata się do linii, a linia do punktu
	var off := clampf((t - HOLD_END) / OFF_LEN, 0.0, 1.0)
	var sy := 1.0 - _ease(off / 0.6)
	var sx := 1.0 - _ease((off - 0.6) / 0.4)
	draw_set_transform(vs * 0.5 * (Vector2.ONE - Vector2(maxf(sx, 0.002), maxf(sy, 0.004))), 0.0, Vector2(maxf(sx, 0.002), maxf(sy, 0.004)))
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.0, 0.06))
	_draw_rays(c)
	_draw_emblem(c)
	_draw_text(vs, c)
	if off > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.8, 0.9, 1.3, off * 0.8))
	draw_set_transform(Vector2.ZERO)
	if off >= 0.6 and off < 1.0:
		draw_circle(vs * 0.5, 6.0 * (1.0 - off) / 0.4 + 1.0, Color(1.3, 1.3, 1.4))


## Wolno obracające się promienie za Statkiem Matką.
func _draw_rays(c: Vector2) -> void:
	var a := clampf((t - EMBLEM_END) / 0.9, 0.0, 1.0)
	if a <= 0.0:
		return
	for k in 16:
		var ang := t * 0.12 + k / 16.0 * TAU
		var d := Vector2.from_angle(ang)
		var n := d.orthogonal()
		var col := Color(1.0, 0.2, 0.7, 0.05 * a) if k % 2 == 0 else Color(0.2, 0.8, 1.0, 0.04 * a)
		draw_colored_polygon(PackedVector2Array([c + d * 120.0 + n * 6.0, c + d * 900.0 + n * 90.0, c + d * 900.0 - n * 90.0, c + d * 120.0 - n * 6.0]), col)


## Statek Matka rysuje się kreska po kresce: ośmiokąt, ramiona, rdzeń.
func _draw_emblem(c: Vector2) -> void:
	var rot := t * 0.25
	var k1 := clampf((t - POWER_ON) / 1.0, 0.0, 1.0)
	var k2 := clampf((t - POWER_ON - 0.9) / 0.65, 0.0, 1.0)
	var k3 := clampf((t - EMBLEM_END + 0.3) / 0.3, 0.0, 1.0)
	var r := 120.0
	# ośmiokąt: rysuje się po obwodzie
	var pts := PackedVector2Array()
	for k in 9:
		pts.append(c + Vector2.from_angle(rot + k / 8.0 * TAU) * r)
	if k3 > 0.0:
		draw_colored_polygon(pts.slice(0, 8), Color(0.1, 0.0, 0.16, 0.92 * k3))
	var seg := k1 * 8.0
	for i in 8:
		var f := clampf(seg - i, 0.0, 1.0)
		if f <= 0.0:
			break
		draw_line(pts[i], pts[i].lerp(pts[i + 1], f), Color(1.4, 0.22, 1.05), 3.0, true)
	if seg < 8.0 and seg > 0.0:
		var head: Vector2 = pts[int(seg)].lerp(pts[mini(int(seg) + 1, 8)], seg - floor(seg))
		draw_circle(head, 5.0, Color(1.5, 1.2, 1.5))
	# ramiona wysuwają się na zewnątrz
	for k in 4:
		var a := rot + k / 4.0 * TAU + PI / 8.0
		var d := Vector2.from_angle(a)
		var n := d.orthogonal()
		var len := 72.0 + 90.0 * _ease(k2)
		if k2 <= 0.0:
			continue
		var arm := PackedVector2Array([c + d * 50.0 + n * 14.0, c + d * (len - 12.0) + n * 6.0, c + d * len, c + d * (len - 12.0) - n * 6.0, c + d * 50.0 - n * 14.0])
		draw_colored_polygon(arm, Color(0.12, 0.0, 0.2, 0.95 * k2))
		arm.append(arm[0])
		draw_polyline(arm, Color(0.19, 0.93, 1.3, k2), 2.0, true)
		draw_circle(c + d * len, 5.0, Color(1.3, 0.43, 1.13, k2))
	# rdzeń zapala się z błyskiem
	if k3 > 0.0:
		var inner := PackedVector2Array()
		for k in 7:
			inner.append(c + Vector2.from_angle(-rot * 1.5 + k / 6.0 * TAU) * 62.0)
		draw_polyline(inner, Color(1.3, 0.84, 0.23, k3), 2.5, true)
		draw_arc(c, 34.0, 0.0, TAU, 48, Color(1.3, 0.25, 1.1, k3), 2.0, true)
		var pulse := 0.5 + 0.5 * sin(t * 4.0)
		draw_circle(c, (14.0 + pulse * 3.0) * k3, Color(0.8 + 0.3 * pulse, 0.3, 1.2))
		draw_circle(c, 6.0 * k3, Color(1.4, 1.4, 1.4))
		var burst := clampf((t - EMBLEM_END) / 0.7, 0.0, 1.0)
		if burst > 0.0 and burst < 1.0:
			draw_arc(c, 60.0 + burst * 260.0, 0.0, TAU, 64, Color(1.2, 0.5, 1.3, 1.0 - burst), 3.0, true)


## "IMPERIUM VEX" pisze się litera po literze, potem pojawia się "PRZEDSTAWIA".
func _draw_text(vs: Vector2, c: Vector2) -> void:
	var k := clampf((t - TEXT_START) / (TEXT_END - TEXT_START - 0.35), 0.0, 1.0)
	if k <= 0.0:
		return
	var n := int(round(k * STUDIO.length()))
	var shown := STUDIO.substr(0, n)
	var fs := 48
	var full_w := pf.get_string_size(STUDIO, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(c.x - full_w * 0.5, c.y + 240.0).round()
	draw_string(pf, p + Vector2(4, 3), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.2, 0.9, 1.0, 0.7))
	draw_string(pf, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.3, 1.0, 0.45))
	if n < STUDIO.length() and int(t * 8.0) % 2 == 0:
		var cx := p.x + pf.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 4.0
		draw_rect(Rect2(cx, p.y - 34, 18, 38), Color(1.3, 1.0, 0.45))
	var k2 := clampf((t - TEXT_END + 0.3) / 0.6, 0.0, 1.0)
	if k2 > 0.0:
		var w2 := pf.get_string_size(PRESENTS, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		var line_w := full_w * _ease(k2)
		draw_line(Vector2(c.x - line_w * 0.5, p.y + 20), Vector2(c.x + line_w * 0.5, p.y + 20), Color(1.0, 0.3, 0.8, 0.7 * k2), 2.0)
		draw_string(pf, Vector2(c.x - w2 * 0.5, p.y + 58).round(), PRESENTS, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.3, 0.95, 1.2, k2))
