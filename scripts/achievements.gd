extends CanvasLayer
## Osiągnięcia (autoload). Wspólne dla wszystkich zapisów, trzymane w user://achievements.cfg.
## Zdobyte osiągnięcie wyjeżdża w prawym dolnym rogu ekranu - w menu, w locie i na pauzie.
## Lista z ikonami jest rysowana przez draw_list() w menu głównym i w menu pauzy.

const Style = preload("res://scripts/style.gd")
const PATH := "user://achievements.cfg"
const MENU_TILES_GOAL := 100
const TOAST_TIME := 5.0

## id, nazwa, opis, kolor przewodni, ukryte (do zdobycia nie widać nazwy ani opisu)
const DEFS := [
	{"id": "first_launch", "name": "Start z doku", "desc": "Wyleć po raz pierwszy ze Statku Matki.", "color": Color(0.3, 0.95, 1.0), "hidden": false},
	{"id": "armory", "name": "Arsenał otwarty", "desc": "Odblokuj Zbrojownię na Statku Matce.", "color": Color(1.0, 0.45, 0.3), "hidden": false, "icon": "rocket"},
	{"id": "bridge", "name": "Kapitan na mostku", "desc": "Odblokuj Sterownię na Statku Matce.", "color": Color(0.4, 0.9, 1.0), "hidden": false, "icon": "radar"},
	{"id": "lab", "name": "Pierwsza probówka", "desc": "Odblokuj Laboratorium na Statku Matce.", "color": Color(0.55, 1.0, 0.45), "hidden": false, "icon": "flask"},
	{"id": "empire", "name": "W łaskach Imperium", "desc": "Odblokuj zakładkę Imperium na Statku Matce.", "color": Color(1.0, 0.65, 0.2), "hidden": false, "icon": "crown"},
	{"id": "neonite", "name": "Neonowa gorączka", "desc": "Zbierz pierwsze kryształy neonitu ze złoża.", "color": Color(1.0, 0.3, 1.0), "hidden": false},
	{"id": "new_york", "name": "Wielkie Jabłko upada", "desc": "Zniszcz całą metropolię Nowego Jorku.", "color": Color(1.0, 0.8, 0.3), "hidden": false},
	{"id": "training", "name": "Absolwent Roswell", "desc": "Ukończ szkolenie w Roswell (TUTORIAL w menu).", "color": Color(0.45, 1.0, 0.6), "hidden": false, "icon": "shield"},
	{"id": "menu_wrecker", "name": "Za kulisami", "desc": "Zniszcz 100 kafelków w tle menu głównego.", "color": Color(1.0, 0.35, 0.8), "hidden": true},
]

var unlocked: Dictionary = {}     # id -> czas zdobycia (unix)
var menu_tiles := 0
var queue: Array = []             # osiągnięcia czekające na wyświetlenie
var toast_id := ""
var toast_t := 0.0
var time := 0.0
var check_t := 0.0
var view: Control


func _ready() -> void:
	layer = 98                     # pod filtrem jaskrawości i CRT, nad całą resztą (także pauzą)
	process_mode = Node.PROCESS_MODE_ALWAYS
	view = Control.new()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.draw.connect(_draw_toast)
	add_child(view)
	_load()


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for d in DEFS:
		if cf.has_section_key("unlocked", d["id"]):
			unlocked[d["id"]] = int(cf.get_value("unlocked", d["id"]))
	menu_tiles = int(cf.get_value("progress", "menu_tiles", 0))


func _save() -> void:
	var cf := ConfigFile.new()
	for k in unlocked:
		cf.set_value("unlocked", k, unlocked[k])
	cf.set_value("progress", "menu_tiles", menu_tiles)
	cf.save(PATH)


static func def(id: String) -> Dictionary:
	for d in DEFS:
		if d["id"] == id:
			return d
	return {}


func has(id: String) -> bool:
	return unlocked.has(id)


func count() -> int:
	return unlocked.size()


func unlock(id: String) -> void:
	if unlocked.has(id) or def(id).is_empty():
		return
	unlocked[id] = int(Time.get_unix_time_from_system())
	_save()
	queue.append(id)


## Kafelek zniszczony w tle menu głównego.
func menu_tile() -> void:
	if unlocked.has("menu_wrecker"):
		return
	menu_tiles += 1
	if menu_tiles >= MENU_TILES_GOAL:
		unlock("menu_wrecker")
	elif menu_tiles % 10 == 0:
		_save()


## Warunki sprawdzane na bieżącym zapisie - zdobywa też osiągnięcia z wcześniejszej gry.
func check() -> void:
	# szkolenie startuje z gotowym statkiem - nie może rozdawać osiągnięć za postęp
	if GameState.training:
		return
	if GameState.sorties >= 1:
		unlock("first_launch")
	for k in ["armory", "bridge", "lab"]:
		if GameState.stat(k) > 0.0:
			unlock(k)
	if GameState.empire_unlocked():
		unlock("empire")
	if GameState.metros_done.has(str(GameState.Sectors.START)):
		unlock("new_york")
	if int(GameState.collected.get("neonite", 0)) > 0 or int(GameState.cargo.get("neonite", 0)) > 0:
		unlock("neonite")


func _process(delta: float) -> void:
	time += delta
	check_t -= delta
	if check_t <= 0.0:
		check_t = 0.5
		check()
	if toast_id == "" and not queue.is_empty():
		toast_id = queue.pop_front()
		toast_t = 0.0
		Audio.play("research_done", 0.0)
	if toast_id != "":
		toast_t += delta
		if toast_t >= TOAST_TIME:
			toast_id = ""
		view.queue_redraw()


func _draw_toast() -> void:
	if toast_id == "":
		return
	var d := def(toast_id)
	var vs := view.get_viewport_rect().size
	var w := 400.0
	var h := 96.0
	# wjazd z prawej, chwila postoju, zjazd w dół
	var inn := clampf(toast_t / 0.35, 0.0, 1.0)
	var out := clampf((toast_t - (TOAST_TIME - 0.4)) / 0.4, 0.0, 1.0)
	var ei := 1.0 - pow(1.0 - inn, 3.0)
	var r := Rect2(vs.x - w - 24 + (1.0 - ei) * (w + 40), vs.y - h - 64 + out * (h + 80), w, h)
	var c: Color = d["color"]
	var flash := maxf(0.0, 1.0 - toast_t * 2.0)
	# poświata za panelem
	for k in 3:
		var g := r.grow(4.0 + k * 4.0)
		view.draw_rect(g, Color(c.r, c.g, c.b, (0.06 - k * 0.018) * (1.0 + flash)), false, 3.0)
	Style.chamfer_panel(view, r, c.lerp(Color(1.4, 1.4, 1.4), flash * 0.6), Color(0.03, 0.0, 0.06, 0.97), 12.0)
	# biegnący błysk po górnej krawędzi
	var sx := r.position.x + fmod(toast_t * 0.6, 1.0) * r.size.x
	view.draw_line(Vector2(sx, r.position.y + 1), Vector2(minf(sx + 70.0, r.end.x - 12.0), r.position.y + 1), Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 0.9), 2.0)
	draw_badge(view, r.position + Vector2(52, h * 0.5), 34.0, toast_id, true, time)
	var pf := Style.font_pixel()
	var fb := Style.font_bold()
	var f := Style.font()
	var tx := r.position.x + 100
	view.draw_string(fb, Vector2(tx, r.position.y + 26), "OSIĄGNIĘCIE ODBLOKOWANE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(c.r, c.g, c.b, 0.85))
	view.draw_string(pf, Vector2(tx, r.position.y + 54), String(d["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, r.end.x - tx - 14, 20, Color(1.3, 1.25, 1.35))
	view.draw_string(f, Vector2(tx, r.position.y + 76), String(d["desc"]), HORIZONTAL_ALIGNMENT_LEFT, r.end.x - tx - 14, 11, Color(0.8, 0.75, 0.9))


# ---------------- ikony ----------------

static func _hex(c: Vector2, r: float, rot := 0.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in 6:
		p.append(c + Vector2.from_angle(rot + k * TAU / 6.0) * r)
	return p


## Odznaka: neonowy sześciokąt z ikoną. Zablokowana jest szara, ukryta pokazuje znak zapytania.
static func draw_badge(ci: CanvasItem, c: Vector2, r: float, id: String, got: bool, t: float) -> void:
	var d := def(id)
	var col: Color = d["color"] if got else Color(0.4, 0.36, 0.48)
	var hex := _hex(c, r, PI / 6.0)
	ci.draw_colored_polygon(hex, Color(col.r * 0.12, col.g * 0.12, col.b * 0.14, 0.95) if got else Color(0.05, 0.04, 0.07, 0.95))
	if got:
		# obracający się zewnętrzny pierścień kresek
		for k in 12:
			var a := t * 0.6 + k * TAU / 12.0
			ci.draw_line(c + Vector2.from_angle(a) * (r + 5.0), c + Vector2.from_angle(a) * (r + 9.0), Color(col.r, col.g, col.b, 0.55), 1.5, true)
		ci.draw_polyline(Style.closed(_hex(c, r + 3.0, PI / 6.0)), Color(col.r, col.g, col.b, 0.3), 3.0, true)
	ci.draw_polyline(Style.closed(hex), col * Color(1.25, 1.25, 1.25, 1.0) if got else col, 2.0, true)
	ci.draw_polyline(Style.closed(_hex(c, r * 0.8, PI / 6.0)), Color(col.r, col.g, col.b, 0.35), 1.0, true)
	if not got and d.get("hidden", false):
		var pf := Style.font_pixel()
		var fs := int(r * 0.9)
		var w := pf.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(pf, c + Vector2(-w * 0.5, fs * 0.36), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		return
	var ic: Color = Color(col.r * 1.3, col.g * 1.3, col.b * 1.3) if got else Color(col.r, col.g, col.b, 0.7)
	var s := r * 0.55
	match id:
		"first_launch": _icon_launch(ci, c, s, ic, got, t)
		"neonite": _icon_crystals(ci, c, s, ic, got, t)
		"new_york": _icon_skyline(ci, c, s, ic, got, t)
		"menu_wrecker": _icon_shatter(ci, c, s, ic, got, t)
		_:
			# sekcje Statku Matki: ikona z zestawu gry, z delikatnym pulsowaniem po zdobyciu
			var p := (1.0 + 0.06 * sin(t * 3.0)) if got else 1.0
			Style.draw_icon(ci, String(d.get("icon", "star")), c, s * 0.95 * p, ic, 2.0)


## Statek wzbijający się z płomieniem i łukiem toru lotu.
static func _icon_launch(ci: CanvasItem, c: Vector2, s: float, col: Color, got: bool, t: float) -> void:
	var xf := Transform2D(-PI * 0.5, c + Vector2(0, -s * 0.15))
	var k := s / 22.0
	var shape := PackedVector2Array([Vector2(22, 0), Vector2(4, -7), Vector2(-6, -16), Vector2(-12, -14), Vector2(-8, -5),
		Vector2(-12, 0), Vector2(-8, 5), Vector2(-12, 14), Vector2(-6, 16), Vector2(4, 7)])
	var pts := PackedVector2Array()
	for p in shape:
		pts.append(xf * (p * k))
	ci.draw_polyline(Style.closed(pts), col, 1.8, true)
	var fl := (0.8 + 0.2 * sin(t * 18.0)) if got else 0.8
	var base := xf * (Vector2(-12, 0) * k)
	ci.draw_line(base, base + Vector2(0, s * 0.75 * fl), Color(1.3, 0.7, 0.3, col.a), 2.4, true)
	ci.draw_line(base, base + Vector2(0, s * 0.4 * fl), Color(1.4, 1.2, 0.8, col.a), 1.4, true)
	ci.draw_arc(c + Vector2(s * 0.9, s * 0.9), s * 1.1, PI * 1.05, PI * 1.45, 10, Color(col.r, col.g, col.b, 0.5 * col.a), 1.2, true)


## Trzy kryształy neonitu z błyskiem.
static func _icon_crystals(ci: CanvasItem, c: Vector2, s: float, col: Color, got: bool, t: float) -> void:
	var specs := [[Vector2(0, 0.15), 1.0, 0.0], [Vector2(-0.55, 0.35), 0.62, -0.45], [Vector2(0.55, 0.38), 0.55, 0.42]]
	for sp in specs:
		var base: Vector2 = c + sp[0] * s
		var h: float = s * 1.3 * sp[1]
		var wd: float = s * 0.32 * sp[1]
		var rot: float = sp[2]
		var tip := base + Vector2(0, -h).rotated(rot)
		var l := base + Vector2(-wd, -h * 0.25).rotated(rot)
		var rr := base + Vector2(wd, -h * 0.25).rotated(rot)
		var lt := base + Vector2(-wd, -h * 0.75).rotated(rot)
		var rt := base + Vector2(wd, -h * 0.75).rotated(rot)
		var poly := PackedVector2Array([base, l, lt, tip, rt, rr])
		ci.draw_colored_polygon(poly, Color(col.r * 0.25, col.g * 0.08, col.b * 0.25, 0.8 * col.a))
		ci.draw_polyline(Style.closed(poly), col, 1.5, true)
		ci.draw_line(base, tip, Color(col.r, col.g, col.b, 0.5 * col.a), 1.0, true)
	if got:
		var tw := 0.5 + 0.5 * sin(t * 4.0)
		var sp := c + Vector2(s * 0.35, -s * 1.0)
		ci.draw_line(sp + Vector2(-4, 0) * (0.6 + tw), sp + Vector2(4, 0) * (0.6 + tw), Color(1.4, 1.3, 1.4), 1.4, true)
		ci.draw_line(sp + Vector2(0, -4) * (0.6 + tw), sp + Vector2(0, 4) * (0.6 + tw), Color(1.4, 1.3, 1.4), 1.4, true)


## Panorama wieżowców z wybuchem nad najwyższym.
static func _icon_skyline(ci: CanvasItem, c: Vector2, s: float, col: Color, got: bool, t: float) -> void:
	var gy := c.y + s * 0.85
	var bld := [[-1.0, 0.45, 0.9], [-0.5, 0.4, 1.35], [-0.05, 0.42, 1.0], [0.4, 0.36, 1.65], [0.82, 0.3, 0.75]]
	for b in bld:
		var x0: float = c.x + b[0] * s
		var bw: float = b[1] * s
		var bh: float = b[2] * s
		var r := PackedVector2Array([Vector2(x0, gy), Vector2(x0, gy - bh), Vector2(x0 + bw, gy - bh), Vector2(x0 + bw, gy)])
		ci.draw_polyline(r, col, 1.5, true)
		var wy: float = gy - bh + 4.0
		while wy < gy - 4.0:
			ci.draw_line(Vector2(x0 + bw * 0.3, wy), Vector2(x0 + bw * 0.7, wy), Color(col.r, col.g, col.b, 0.45 * col.a), 1.0)
			wy += 5.0
	ci.draw_line(Vector2(c.x - s * 1.15, gy), Vector2(c.x + s * 1.2, gy), col, 1.6, true)
	# antena i wybuch nad najwyższym budynkiem
	var top := Vector2(c.x + 0.58 * s, gy - 1.65 * s)
	ci.draw_line(top, top + Vector2(0, -s * 0.25), col, 1.2, true)
	if got:
		var p := 0.75 + 0.25 * sin(t * 6.0)
		Style.sunburst(ci, top + Vector2(0, -s * 0.35), s * 0.45 * p, 8, t * 0.8, Color(1.4, 0.75, 0.35), 1.4)


## Pękający kafelek terenu z odłamkami.
static func _icon_shatter(ci: CanvasItem, c: Vector2, s: float, col: Color, got: bool, t: float) -> void:
	var r := Rect2(c - Vector2(s, s) * 0.75, Vector2(s, s) * 1.5)
	var cut := s * 0.25
	var p := PackedVector2Array([r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - cut),
		r.end - Vector2(cut, 0), Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut)])
	ci.draw_polyline(Style.closed(p), col, 1.6, true)
	# pęknięcie przez środek
	var crack := PackedVector2Array([c + Vector2(-0.2, -0.75) * s, c + Vector2(0.05, -0.25) * s, c + Vector2(-0.15, 0.05) * s,
		c + Vector2(0.2, 0.35) * s, c + Vector2(0.05, 0.75) * s])
	ci.draw_polyline(crack, Color(1.4, 1.3, 1.4, col.a), 1.6, true)
	ci.draw_line(c + Vector2(0.05, -0.25) * s, c + Vector2(0.45, -0.4) * s, Color(col.r, col.g, col.b, 0.7 * col.a), 1.0, true)
	# odłamki wylatujące z rogu
	var k := fmod(t * 0.7, 1.0) if got else 0.3
	for j in 3:
		var dir := Vector2.from_angle(-0.9 + j * 0.45)
		var sp := c + Vector2(0.75, -0.75) * s + dir * s * (0.25 + 0.5 * fmod(k + j * 0.33, 1.0))
		var tri := PackedVector2Array([sp, sp + dir.rotated(2.2) * 4.0, sp + dir.rotated(-2.2) * 4.0])
		ci.draw_colored_polygon(tri, Color(col.r, col.g, col.b, col.a * (1.0 - fmod(k + j * 0.33, 1.0))))


# ---------------- lista ----------------

## Karty wszystkich osiągnięć w prostokącie (menu główne i pauza). Zwraca wysokość zawartości.
func draw_list(ci: CanvasItem, area: Rect2, t: float) -> float:
	var pf := Style.font_pixel()
	var f := Style.font()
	var fb := Style.font_bold()
	var cols := 2 if area.size.x > 700.0 else 1
	var gap := 16.0
	var cw := (area.size.x - gap * (cols - 1)) / cols
	var ch := 104.0
	for i in DEFS.size():
		var d: Dictionary = DEFS[i]
		var got := unlocked.has(d["id"])
		var secret: bool = d.get("hidden", false) and not got
		var r := Rect2(area.position.x + (i % cols) * (cw + gap), area.position.y + (i / cols) * (ch + gap), cw, ch)
		var c: Color = d["color"] if got else Color(0.45, 0.4, 0.55)
		Style.chamfer_panel(ci, r, Color(c.r, c.g, c.b, 0.9 if got else 0.5), Color(c.r * 0.06, c.g * 0.04, c.b * 0.08 + 0.02, 0.95), 12.0)
		draw_badge(ci, r.position + Vector2(56, ch * 0.5), 34.0, d["id"], got, t)
		var tx := r.position.x + 108
		var tw := r.end.x - tx - 16
		var title := "UKRYTE OSIĄGNIĘCIE" if secret else String(d["name"]).to_upper()
		ci.draw_string(pf, Vector2(tx, r.position.y + 38), title, HORIZONTAL_ALIGNMENT_LEFT, tw, 20, Color(1.25, 1.2, 1.3) if got else Color(0.62, 0.56, 0.7))
		var desc := "Szczegóły odkryjesz, gdy je zdobędziesz." if secret else String(d["desc"])
		ci.draw_multiline_string(f, Vector2(tx, r.position.y + 62), desc, HORIZONTAL_ALIGNMENT_LEFT, tw, 12, 2, Color(0.82, 0.76, 0.92) if got else Color(0.55, 0.5, 0.62))
		var st := "ZDOBYTE " + Time.get_date_string_from_unix_time(int(unlocked[d["id"]]) + _tz_bias()) if got else "ZABLOKOWANE"
		ci.draw_string(fb, Vector2(r.end.x - 14 - fb.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x, r.end.y - 12), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(c.r, c.g, c.b, 0.9 if got else 0.6))
	var rows := int(ceil(DEFS.size() / float(cols)))
	return rows * (ch + gap) - gap


func _tz_bias() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
