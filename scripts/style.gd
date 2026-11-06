extends RefCounted
## Wspólny styl graficzny (inspiracja: Agrivore + synthwave):
## czarne tło, świecące wektory, czcionka terminalowa, ikony rysowane liniami,
## panele z podwójną ramką. Wszystko statyczne - używaj: const Style = preload("res://scripts/style.gd")

const BG := Color(0.02, 0.0, 0.04)
const PANEL := Color(0.03, 0.01, 0.06, 0.94)
const PINK := Color(1.0, 0.35, 0.8)
const CYAN := Color(0.3, 0.95, 1.0)
const GOLD := Color(1.0, 0.8, 0.3)
const GREEN := Color(0.45, 1.0, 0.45)
const RED := Color(1.0, 0.25, 0.3)
const DIM := Color(0.42, 0.36, 0.5)
const TEXT := Color(0.94, 0.9, 1.0)
const TEXT_DIM := Color(0.62, 0.56, 0.7)

static var _font: Font
static var _font_bold: Font
static var _font_pixel: Font


## Pikselowa czcionka "Neon Pixel" (własna, 5x7, z polskimi znakami).
## Najostrzej wygląda w rozmiarach będących wielokrotnością 8 (16, 24, 32, 48...).
static func font_pixel() -> Font:
	if _font_pixel == null:
		var path := "res://fonts/neon_pixel.ttf"
		var f: FontFile = null
		if ResourceLoader.exists(path):
			f = load(path) as FontFile
		if f == null:
			f = FontFile.new()
			f.load_dynamic_font(path)
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.generate_mipmaps = false
		_font_pixel = f
	return _font_pixel


## Czcionka terminalowa (monospace) - na Windowsie Consolas.
static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Consolas", "Lucida Console", "Cascadia Mono", "Courier New", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
		_font = f
	return _font


static func font_bold() -> Font:
	if _font_bold == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Consolas", "Lucida Console", "Cascadia Mono", "Courier New", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
		f.font_weight = 700
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font_bold = f
	return _font_bold


## Panel w stylu Agrivore: ciemne wypełnienie, cienka ramka zewnętrzna + jaśniejsza wewnętrzna.
static func panel(ci: CanvasItem, r: Rect2, c: Color, fill := PANEL) -> void:
	ci.draw_rect(r, fill)
	ci.draw_rect(r, Color(c.r, c.g, c.b, 0.35), false, 1.0)
	ci.draw_rect(r.grow(-3), Color(c.r, c.g, c.b, 0.85), false, 1.0)


## Panel ze ściętymi rogami (lewy górny i prawy dolny), jak na ekranie Statku Matki.
static func chamfer_panel(ci: CanvasItem, r: Rect2, c: Color, fill := PANEL, cut := 10.0) -> void:
	var pts := PackedVector2Array([r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - cut),
		r.end - Vector2(cut, 0), Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut)])
	ci.draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(c.r, c.g, c.b, 0.8), 1.4, true)


## Zielony plus "stać cię" (jak w Agrivore).
static func plus_badge(ci: CanvasItem, p: Vector2, s := 5.0, c := GREEN) -> void:
	ci.draw_line(p + Vector2(-s, 0), p + Vector2(s, 0), c, 2.5)
	ci.draw_line(p + Vector2(0, -s), p + Vector2(0, s), c, 2.5)


## Kolczaste "słońce" - wybuch / trafienie.
static func sunburst(ci: CanvasItem, p: Vector2, r: float, spikes: int, rot: float, c: Color, w := 1.6) -> void:
	var pts := PackedVector2Array()
	for k in spikes * 2 + 1:
		var a := rot + float(k) / (spikes * 2) * TAU
		var rr := r if k % 2 == 0 else r * 0.62
		pts.append(p + Vector2(cos(a), sin(a)) * rr)
	ci.draw_polyline(pts, c, w, true)


# =====================================================================
# IKONY ULEPSZEŃ (wektorowe, rysowane w kwadracie o promieniu s)
# =====================================================================

const ICON_OF := {
	"core": "core", "laser_dmg": "bolt", "laser_range": "target", "laser_splash": "burst",
	"laser_drill": "drill", "laser_overdrive": "star", "chain": "chain", "chain_jumps": "chain",
	"chain_power": "bolt", "chain_rate": "clock", "chain_range": "target", "hull": "heart", "shield": "shield",
	"shield_regen": "regen", "shield_phase": "shield2", "armor": "armor", "repair": "wrench",
	"thrust": "flame", "max_speed": "chevrons", "turn": "rotate", "brake": "brake", "warp": "warp",
	"cargo": "crate", "yield": "gem", "cargo2": "compress", "dep_yield": "ore", "scanner": "radar",
	"magnet": "magnet", "fuel_tank": "fuel", "fuel_eff": "leaf", "fuel_siphon": "siphon",
	"drift_boost": "drift", "cargo_pocket": "crate", "cargo_mult": "compress", "cargo_dim": "portal",
	"armory": "rocket", "bridge": "radar", "bio_probe": "dna", "lab": "flask", "abduct_speed": "ufo", "bio_capacity": "pod",
	"abduct_amount": "ufo", "research_speed": "clock", "abduct_range": "target", "research_speed2": "cpu",
	"abduct_area": "expand", "rebuild": "hammer", "rebuild_speed": "clock", "rebuild_range": "target",
	"rebuild_area": "expand", "power_mult": "crown",
	"rockets": "rocket", "drones": "drone", "guns": "gun", "escort": "ufo", "escort_more": "ufo", "escort_dmg": "bolt", "escort_hp": "heart",
	"laser_combat": "target", "drill2": "drill", "laser_focus": "star", "hull_siphon": "regen", "armor2": "armor",
	"shield_cap": "shield2", "fuel_cell": "fuel", "strafe2": "chevrons", "salvage": "gem", "yield2": "gem", "power_mult2": "crown",
	"detonate": "burst", "det_chance": "star", "det_power": "bolt", "det_radius": "expand",
	"rocket_reload": "clock", "rocket_radius": "burst", "rocket_dmg": "bolt",
	"drone_more": "drone", "drone_dmg": "bolt", "drone_rate": "clock",
	"gun_dmg": "bolt", "gun_rate": "clock", "gun_range": "target",
	"miner": "ore", "miner_fleet": "drone", "miner_drill": "drill", "miner_hold": "crate", "miner_engine": "chevrons",
	"wing_armor": "armor", "miner_armor": "armor", "miner_scan": "radar",
	"cargo_hull": "crate", "cargo_lattice": "compress", "cargo_sing": "portal",
	"transit": "crate", "transit_more": "crate", "transit_rate": "clock", "transit_hold": "expand", "transit_armor": "armor",
	"wing": "rocket", "wing_more": "rocket", "wing_dmg": "bolt", "wing_rate": "clock", "wing_speed": "chevrons",
	"ally_turrets": "target", "ally_dmg": "bolt", "ally_range": "radar",
	"laser_resonator": "star", "hull_plating": "armor", "maneuver": "chevrons", "fuel_tank2": "fuel", "cargo_b": "crate",
}


static func icon_for(id: String) -> String:
	return String(ICON_OF.get(id, "core"))


static func draw_icon(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color, w := 1.6) -> void:
	var L := func(a: Vector2, b: Vector2): ci.draw_line(c + a * s, c + b * s, col, w, true)
	var P := func(arr: Array):
		var pts := PackedVector2Array()
		for v in arr:
			pts.append(c + v * s)
		ci.draw_polyline(pts, col, w, true)
	match kind:
		"core":
			P.call([Vector2(0, -0.8), Vector2(0.8, 0), Vector2(0, 0.8), Vector2(-0.8, 0), Vector2(0, -0.8)])
			ci.draw_circle(c, s * 0.22, col)
		"bolt":
			P.call([Vector2(0.15, -0.9), Vector2(-0.45, 0.1), Vector2(0.05, 0.1), Vector2(-0.15, 0.9), Vector2(0.45, -0.15), Vector2(-0.05, -0.15), Vector2(0.15, -0.9)])
		"chain":
			P.call([Vector2(-0.85, -0.7), Vector2(-0.2, -0.35), Vector2(-0.45, 0.05), Vector2(0.15, 0.3), Vector2(-0.05, 0.85)])
			P.call([Vector2(-0.45, 0.05), Vector2(0.45, -0.3), Vector2(0.85, -0.75)])
			ci.draw_circle(c + Vector2(-0.85, -0.7) * s, s * 0.12, col)
			ci.draw_circle(c + Vector2(-0.05, 0.85) * s, s * 0.12, col)
			ci.draw_circle(c + Vector2(0.85, -0.75) * s, s * 0.12, col)
		"target":
			ci.draw_arc(c, s * 0.7, 0, TAU, 20, col, w, true)
			ci.draw_arc(c, s * 0.3, 0, TAU, 12, col, w, true)
			L.call(Vector2(-0.95, 0), Vector2(-0.5, 0)); L.call(Vector2(0.5, 0), Vector2(0.95, 0))
			L.call(Vector2(0, -0.95), Vector2(0, -0.5)); L.call(Vector2(0, 0.5), Vector2(0, 0.95))
		"burst":
			sunburst(ci, c, s * 0.85, 8, 0.0, col, w)
			ci.draw_circle(c, s * 0.18, col)
		"drill":
			P.call([Vector2(-0.3, -0.8), Vector2(0.3, -0.8), Vector2(0.3, 0.1), Vector2(0, 0.9), Vector2(-0.3, 0.1), Vector2(-0.3, -0.8)])
			L.call(Vector2(-0.3, -0.3), Vector2(0.3, -0.1)); L.call(Vector2(-0.3, 0.05), Vector2(0.25, 0.25))
		"star":
			var pts: Array = []
			for k in 11:
				var a := -PI * 0.5 + k / 10.0 * TAU
				var rr := 0.9 if k % 2 == 0 else 0.4
				pts.append(Vector2(cos(a), sin(a)) * rr)
			P.call(pts)
		"heart":
			P.call([Vector2(0, 0.8), Vector2(-0.8, -0.05), Vector2(-0.75, -0.55), Vector2(-0.35, -0.75), Vector2(0, -0.4), Vector2(0.35, -0.75), Vector2(0.75, -0.55), Vector2(0.8, -0.05), Vector2(0, 0.8)])
		"shield", "shield2":
			P.call([Vector2(0, -0.85), Vector2(0.7, -0.55), Vector2(0.6, 0.25), Vector2(0, 0.85), Vector2(-0.6, 0.25), Vector2(-0.7, -0.55), Vector2(0, -0.85)])
			if kind == "shield2":
				P.call([Vector2(0, -0.45), Vector2(0.35, -0.3), Vector2(0.3, 0.15), Vector2(0, 0.45), Vector2(-0.3, 0.15), Vector2(-0.35, -0.3), Vector2(0, -0.45)])
		"regen":
			ci.draw_arc(c, s * 0.65, -0.3, PI, 16, col, w, true)
			P.call([Vector2(0.65, -0.55), Vector2(0.65, -0.15), Vector2(0.25, -0.2)])
			ci.draw_arc(c, s * 0.65, PI - 0.3, TAU - 0.3, 16, Color(col.r, col.g, col.b, 0.55), w, true)
		"armor":
			ci.draw_rect(Rect2(c - Vector2(0.7, 0.7) * s, Vector2(1.4, 1.4) * s), col, false, w)
			L.call(Vector2(-0.7, -0.2), Vector2(0.7, -0.2)); L.call(Vector2(-0.7, 0.3), Vector2(0.7, 0.3))
			ci.draw_circle(c + Vector2(-0.45, -0.45) * s, s * 0.08, col); ci.draw_circle(c + Vector2(0.45, -0.45) * s, s * 0.08, col)
		"wrench":
			L.call(Vector2(-0.6, 0.6), Vector2(0.25, -0.25))
			ci.draw_arc(c + Vector2(0.4, -0.4) * s, s * 0.32, 0.6, TAU - 0.9, 14, col, w, true)
		"flame":
			P.call([Vector2(0, -0.9), Vector2(0.5, -0.1), Vector2(0.4, 0.5), Vector2(0, 0.85), Vector2(-0.4, 0.5), Vector2(-0.5, -0.1), Vector2(-0.15, -0.35), Vector2(0, -0.9)])
			P.call([Vector2(0, -0.1), Vector2(0.2, 0.35), Vector2(0, 0.6), Vector2(-0.2, 0.35), Vector2(0, -0.1)])
		"chevrons":
			P.call([Vector2(-0.8, -0.6), Vector2(-0.2, 0), Vector2(-0.8, 0.6)])
			P.call([Vector2(-0.2, -0.6), Vector2(0.4, 0), Vector2(-0.2, 0.6)])
			P.call([Vector2(0.4, -0.6), Vector2(0.95, 0), Vector2(0.4, 0.6)])
		"rotate":
			ci.draw_arc(c, s * 0.65, -PI * 0.2, PI * 1.4, 20, col, w, true)
			P.call([Vector2(0.53, -0.75), Vector2(0.53, -0.38), Vector2(0.9, -0.38)])
		"brake":
			for k in 3:
				var x := -0.6 + k * 0.6
				L.call(Vector2(x, -0.7), Vector2(x, 0.7))
			L.call(Vector2(-0.85, 0), Vector2(0.85, 0))
		"warp":
			var pts: Array = []
			for k in 24:
				var a := k / 24.0 * TAU * 2.0
				var rr := 0.1 + k / 24.0 * 0.8
				pts.append(Vector2(cos(a), sin(a)) * rr)
			P.call(pts)
		"crate":
			ci.draw_rect(Rect2(c - Vector2(0.75, 0.6) * s, Vector2(1.5, 1.2) * s), col, false, w)
			L.call(Vector2(-0.75, -0.2), Vector2(0.75, -0.2)); L.call(Vector2(0, -0.6), Vector2(0, 0.6))
		"gem":
			P.call([Vector2(-0.7, -0.25), Vector2(-0.35, -0.7), Vector2(0.35, -0.7), Vector2(0.7, -0.25), Vector2(0, 0.85), Vector2(-0.7, -0.25), Vector2(0.7, -0.25)])
			P.call([Vector2(-0.35, -0.7), Vector2(0, -0.25), Vector2(0.35, -0.7)])
		"compress":
			P.call([Vector2(-0.8, -0.8), Vector2(-0.25, -0.25)]); P.call([Vector2(-0.25, -0.6), Vector2(-0.25, -0.25), Vector2(-0.6, -0.25)])
			P.call([Vector2(0.8, 0.8), Vector2(0.25, 0.25)]); P.call([Vector2(0.25, 0.6), Vector2(0.25, 0.25), Vector2(0.6, 0.25)])
			ci.draw_rect(Rect2(c - Vector2(0.15, 0.15) * s, Vector2(0.3, 0.3) * s), col, false, w)
		"ore":
			P.call([Vector2(-0.8, 0.5), Vector2(-0.4, -0.5), Vector2(0.1, -0.2), Vector2(0.5, -0.7), Vector2(0.85, 0.5), Vector2(-0.8, 0.5)])
			ci.draw_circle(c + Vector2(0.1, 0.15) * s, s * 0.15, col)
		"radar":
			ci.draw_arc(c, s * 0.8, 0, TAU, 20, col, w, true)
			ci.draw_arc(c, s * 0.45, 0, TAU, 14, Color(col.r, col.g, col.b, 0.6), w, true)
			L.call(Vector2.ZERO, Vector2(0.55, -0.55))
			ci.draw_circle(c + Vector2(-0.3, 0.35) * s, s * 0.1, col)
		"magnet":
			ci.draw_arc(c + Vector2(0, 0.05) * s, s * 0.55, 0, PI, 14, col, w * 1.6, true)
			L.call(Vector2(-0.55, 0.05), Vector2(-0.55, -0.75)); L.call(Vector2(0.55, 0.05), Vector2(0.55, -0.75))
		"fuel":
			P.call([Vector2(-0.55, -0.5), Vector2(-0.2, -0.85), Vector2(0.55, -0.85), Vector2(0.55, 0.85), Vector2(-0.55, 0.85), Vector2(-0.55, -0.5)])
			L.call(Vector2(-0.2, -0.1), Vector2(0.25, 0.45)); L.call(Vector2(0.25, -0.1), Vector2(-0.2, 0.45))
		"leaf":
			P.call([Vector2(-0.7, 0.7), Vector2(-0.6, -0.2), Vector2(0.1, -0.75), Vector2(0.75, -0.75), Vector2(0.7, -0.1), Vector2(0.1, 0.6), Vector2(-0.7, 0.7)])
			L.call(Vector2(-0.7, 0.7), Vector2(0.4, -0.4))
		"siphon":
			ci.draw_arc(c, s * 0.75, 0, TAU, 20, col, w, true)
			P.call([Vector2(0, -0.45), Vector2(0, 0.45)]); P.call([Vector2(-0.3, 0.15), Vector2(0, 0.45), Vector2(0.3, 0.15)])
		"drift":
			ci.draw_arc(c + Vector2(-0.1, 0.25) * s, s * 0.6, PI, PI * 1.9, 14, col, w, true)
			P.call([Vector2(0.2, -0.75), Vector2(0.85, -0.3), Vector2(0.25, 0.05)])
		"portal":
			ci.draw_arc(c, s * 0.8, 0, TAU, 22, col, w, true)
			ci.draw_arc(c, s * 0.5, 0, TAU, 16, Color(col.r, col.g, col.b, 0.7), w, true)
			ci.draw_arc(c, s * 0.2, 0, TAU, 10, Color(col.r, col.g, col.b, 0.5), w, true)
		"rocket":
			P.call([Vector2(0, -0.9), Vector2(0.3, -0.45), Vector2(0.3, 0.45), Vector2(-0.3, 0.45), Vector2(-0.3, -0.45), Vector2(0, -0.9)])
			P.call([Vector2(-0.3, 0.15), Vector2(-0.6, 0.6), Vector2(-0.3, 0.45)])
			P.call([Vector2(0.3, 0.15), Vector2(0.6, 0.6), Vector2(0.3, 0.45)])
			L.call(Vector2(0, 0.55), Vector2(0, 0.9))
		"drone":
			ci.draw_rect(Rect2(c - Vector2(0.25, 0.25) * s, Vector2(0.5, 0.5) * s), col, false, w)
			for d in [Vector2(-0.65, -0.65), Vector2(0.65, -0.65), Vector2(-0.65, 0.65), Vector2(0.65, 0.65)]:
				L.call(d * 0.4, d)
				ci.draw_arc(c + d * s, s * 0.2, 0, TAU, 8, col, w * 0.8, true)
		"gun":
			L.call(Vector2(-0.8, -0.2), Vector2(0.85, -0.2)); L.call(Vector2(-0.8, 0.15), Vector2(0.85, 0.15))
			ci.draw_rect(Rect2(c + Vector2(-0.85, -0.45) * s, Vector2(0.55, 0.95) * s), col, false, w)
		"dna":
			for k in 2:
				var pts: Array = []
				for j in 13:
					var t := j / 12.0
					pts.append(Vector2(sin(t * TAU + k * PI) * 0.45, -0.85 + t * 1.7))
				P.call(pts)
			for j in 4:
				var t := (j + 0.5) / 4.0
				L.call(Vector2(sin(t * TAU) * 0.45, -0.85 + t * 1.7), Vector2(sin(t * TAU + PI) * 0.45, -0.85 + t * 1.7))
		"flask":
			P.call([Vector2(-0.2, -0.85), Vector2(-0.2, -0.3), Vector2(-0.7, 0.75), Vector2(0.7, 0.75), Vector2(0.2, -0.3), Vector2(0.2, -0.85)])
			L.call(Vector2(-0.35, -0.85), Vector2(0.35, -0.85)); L.call(Vector2(-0.48, 0.3), Vector2(0.48, 0.3))
		"ufo":
			ci.draw_arc(c + Vector2(0, -0.15) * s, s * 0.35, PI, TAU, 12, col, w, true)
			P.call([Vector2(-0.85, -0.05), Vector2(0.85, -0.05), Vector2(0.5, 0.2), Vector2(-0.5, 0.2), Vector2(-0.85, -0.05)])
			P.call([Vector2(-0.3, 0.3), Vector2(-0.55, 0.85)]); P.call([Vector2(0.3, 0.3), Vector2(0.55, 0.85)])
		"pod":
			ci.draw_arc(c, s * 0.75, 0, TAU, 20, col, w, true)
			ci.draw_circle(c + Vector2(-0.2, -0.1) * s, s * 0.12, col)
			ci.draw_circle(c + Vector2(0.25, 0.2) * s, s * 0.12, col)
		"clock":
			ci.draw_arc(c, s * 0.8, 0, TAU, 20, col, w, true)
			L.call(Vector2.ZERO, Vector2(0, -0.55)); L.call(Vector2.ZERO, Vector2(0.4, 0.15))
		"cpu":
			ci.draw_rect(Rect2(c - Vector2(0.5, 0.5) * s, Vector2(1.0, 1.0) * s), col, false, w)
			ci.draw_rect(Rect2(c - Vector2(0.2, 0.2) * s, Vector2(0.4, 0.4) * s), col, false, w)
			for k in 3:
				var o := -0.3 + k * 0.3
				L.call(Vector2(o, -0.5), Vector2(o, -0.85)); L.call(Vector2(o, 0.5), Vector2(o, 0.85))
				L.call(Vector2(-0.5, o), Vector2(-0.85, o)); L.call(Vector2(0.5, o), Vector2(0.85, o))
		"expand":
			for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				P.call([d * Vector2(0.85, 0.45), d * 0.85, d * Vector2(0.45, 0.85)])
				L.call(d * 0.2, d * 0.8)
		"hammer":
			ci.draw_rect(Rect2(c + Vector2(-0.6, -0.8) * s, Vector2(1.0, 0.45) * s), col, false, w)
			L.call(Vector2(-0.1, -0.35), Vector2(0.55, 0.85))
		"crown":
			P.call([Vector2(-0.8, 0.5), Vector2(-0.8, -0.4), Vector2(-0.4, 0.0), Vector2(0, -0.7), Vector2(0.4, 0.0), Vector2(0.8, -0.4), Vector2(0.8, 0.5), Vector2(-0.8, 0.5)])
			L.call(Vector2(-0.8, 0.75), Vector2(0.8, 0.75))
		_:
			ci.draw_arc(c, s * 0.6, 0, TAU, 16, col, w, true)
