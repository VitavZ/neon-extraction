extends Control
## Ekran statku matki, część 1/8: sygnały, stałe, cały stan, układ (prostokąty) i wspólne pomocniki rysowania.
## Łańcuch: base -> grid -> panels -> armory -> bridge -> empire -> lab -> scripts/upgrade_screen.gd.
## Każda część widzi tylko funkcje z części wcześniejszych (wywołania w dół łańcucha są niedozwolone).


signal launch_requested
signal mother_move_requested(sector: int)

const Upgrades = preload("res://scripts/upgrades.gd")
const Style = preload("res://scripts/style.gd")
const Sectors = preload("res://scripts/sectors.gd")
const MeshPainter = preload("res://scripts/mesh_painter.gd")

const CELL := 96.0
const NODE_R := 32.0
const OPEN_LEN := 1.6
const STAT_GROUPS := [
	["LASER", Color(1.0, 0.4, 0.8), ["laser_dps", "laser_range", "laser_splash", "deposit_damage_mult", "chain_jumps", "chain_power", "chain_interval", "chain_range"]],
	["KADŁUB", Color(0.45, 1.0, 0.5), ["max_hull", "armor", "max_shield", "shield_regen", "hull_regen"]],
	["NAPĘD", Color(0.3, 0.95, 1.0), ["thrust", "max_speed", "turn_rate", "drift_boost"]],
	["ŁADUNEK", Color(1.0, 0.6, 0.2), ["cargo", "cargo_mult", "yield_mult", "deposit_yield_mult", "scanner", "teleport"]],
	["PALIWO", Color(1.0, 0.8, 0.3), ["max_fuel", "fuel_efficiency", "fuel_siphon"]],
]

var font: Font
var font_b: Font
var pf: Font
var open_t := OPEN_LEN            # czas od otwarcia ekranu (animacja dokowania)
var tab_t := 1.0                  # postęp przejścia między zakładkami
var tab_glide := Rect2()          # podkreślenie sunące do aktywnej zakładki
var overlay := ""                 # otwarta nakładka: "stats" / "brief" / ""
var overlay_shown := ""           # co rysować też w czasie chowania
var overlay_k := 0.0
var overlay_t := 0.0
var disp: Dictionary = {}         # wyświetlane stany magazynu (płynnie doganiają prawdziwe)
var tip_id := ""
var tip_t := 0.0
var toasts: Array = []             # wykonane rozkazy do pokazania
var empire_announced := false
var claim_hits: Array = []         # [Rect2, id rozkazu] - przyciski ODBIERZ
var pl_fx: Array = []              # Punkty Lojalności w locie do licznika
var pl_pending := 0                # punkty już przyznane, ale jeszcze w drodze
var brief_scroll := 0              # o ile wierszy przewinięta lista rozkazów
var pl_pop := 0.0
var pl_target := Vector2.ZERO      # gdzie stoi licznik punktów
var nodes_dirty := true
var armory_dot := false
var lab_dot := false
var vis_nodes: Array = []          # widoczne węzły siatki
var vis_ids: Dictionary = {}
var node_states: Dictionary = {}    # id -> stan węzła
var bg_mesh: ArrayMesh              # szachownica tła, policzona raz
var bg_size := Vector2.ZERO
var grid_fx: Control                # animacje siatki (reszta jest zapamiętana)
var grid_force := true
var drawn_offset := Vector2.ZERO
var drawn_zoom := 1.0
var drawn_rect := Rect2()
var mouse_pos := Vector2.ZERO
var time := 0.0
var hovered: Dictionary = {}
var hover_launch := false
var hover_reset := false
var reset_armed := false
var last_unload: Dictionary = {}
var flash: Dictionary = {}   # id -> czas błysku po zakupie
var status_text := ""
var view_offset := Vector2.ZERO   # przesunięcie siatki (piksele ekranu)
var view_zoom := 1.0
var dragging := false
var tab := "grid"                 # "grid" = siatka ulepszeń, "armory" = zbrojownia, "lab" = laboratorium
var world: Node2D                 # mapa do Sterowni i zapis
var tip_view: Control
var grid_view: Control            # obszar siatki z przycinaniem (węzły przy krawędzi są ucięte, nie znikają)
var miner_hits: Array = []        # [Rect2, numer statku] - karty statków wydobywczych
var project_hits: Array = []      # [Rect2, projekt] - zakładki projektów Imperium
var picker_hits: Array = []       # [Rect2, surowiec] - lista wyboru surowca
var res_picker := -1              # statek, dla którego otwarta jest lista surowców
var picker_t := 0.0
var emp_section := "miners"
## Projekty Imperium: [grupa, nazwa, ikona, węzeł odblokowania].
const EMPIRE_PROJECTS := [["miners", "FLOTA WYDOBYWCZA", "ore", "miner"], ["wings", "MYŚLIWCE IMPERIUM", "rocket", "wing"], ["transit", "STATKI TRANZYTOWE", "crate", "transit"]]
const MinersScript = preload("res://scripts/miners.gd")
var armory_hits: Array = []       # [Rect2, Dictionary] - obszary klikalne w zbrojowni
var drag_moved := 0.0
var bridge_hover := -1            # sektor pod kursorem w Sterowni
var bridge_sel := -1              # sektor wybrany jako cel przenosin
var bridge_hover_btn := false
var highlight_id := ""             # szkolenie: węzeł do kupienia (wirujący pierścień i strzałka)

const C_BUY := Color(0.36, 1.0, 0.48)
const C_LINE_ON := Color(0.35, 1.0, 0.45)
const C_LINE_OFF := Color(0.42, 0.2, 0.5, 0.75)
## Kolor przewodni każdej broni (nagłówek, ramki, paski).
const WEAPON_COLORS := {"rockets": Color(1.0, 0.5, 0.25), "drones": Color(0.35, 1.0, 0.9), "guns": Color(1.0, 0.85, 0.35), "escort": Color(1.0, 0.45, 1.0)}
const QUEST_ROW := 58.0


func _grid_area() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(20.0, 92.0, vs.x - 340.0 - 20.0 - 20.0, vs.y - 92.0 - 20.0)


## Prostokąt widoku siatki (bez paska zakładek u góry i legendy na dole).
func _grid_view_rect() -> Rect2:
	var ga := _grid_area()
	return Rect2(ga.position + Vector2(1, 46), ga.size - Vector2(2, 46 + 30))


func _grid_origin() -> Vector2:
	return _grid_area().get_center() + view_offset


func _cell() -> float:
	return CELL * view_zoom


func _node_r() -> float:
	return NODE_R * view_zoom


func _node_pos(u: Dictionary) -> Vector2:
	return _grid_origin() + Upgrades.display_pos(u) * _cell()


## Węzeł jest widoczny, gdy jest kupiony albo kupiony jest jego rodzic (można go odblokować).
func _is_visible(u: Dictionary) -> bool:
	return GameState.get_level(u["id"]) > 0 or GameState.is_reachable(u)


func _launch_rect() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(vs.x - 340, vs.y - 92, 320, 72)


func _reset_rect() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(vs.x - 200, 22, 180, 36)


func _brief_rect() -> Rect2:
	var r := _reset_rect()
	return Rect2(r.position.x - 120, r.position.y, 110, r.size.y)


func _stats_rect() -> Rect2:
	var r := _brief_rect()
	return Rect2(r.position.x - 170, r.position.y, 160, r.size.y)


func _center_view_rect() -> Rect2:
	var ga := _grid_area()
	return Rect2(ga.end.x - 130, ga.position.y + 10, 120, 26)


## Zakładki widoczne po odblokowaniu w drzewku.
func _tabs() -> Array:
	var t := ["grid"]
	if GameState.stat("armory") > 0.0:
		t.append("armory")
	if GameState.stat("bridge") > 0.0:
		t.append("bridge")
	if GameState.stat("lab") > 0.0:
		t.append("lab")
	if GameState.empire_unlocked():
		t.append("empire")
	return t


func _tab_rect(k: int) -> Rect2:
	var ga := _grid_area()
	return Rect2(ga.position + Vector2(10 + k * 160, 8), Vector2(150, 30))


func reset_view() -> void:
	view_offset = Vector2.ZERO
	view_zoom = 1.0


func _zoom_at(mp: Vector2, factor: float) -> void:
	var old := view_zoom
	view_zoom = clampf(view_zoom * factor, 0.4, 2.2)
	# zoom względem kursora: punkt pod kursorem zostaje w miejscu
	var c := _grid_area().get_center()
	var k := view_zoom / old
	view_offset = (mp - c) - ((mp - c) - view_offset) * k


func _go_menu() -> void:
	if world:
		GameState.save_game(world.export_save())
	get_tree().change_scene_to_file("res://menu.tscn")


# ---------------- rysowanie ----------------


func _text(p: Vector2, s: String, fsize: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, p, s, align, width, fsize, c)


# ---------------- Sterownia ----------------


## Ośmiokąt ze ściętymi rogami, ten sam kształt co kadłub Statku Matki.
func _octagon(c: Vector2, half: float) -> PackedVector2Array:
	var cut := half * 0.34
	var a := half - cut
	return PackedVector2Array([c + Vector2(-a, -half), c + Vector2(a, -half), c + Vector2(half, -a), c + Vector2(half, a),
		c + Vector2(a, half), c + Vector2(-a, half), c + Vector2(-half, a), c + Vector2(-half, -a)])


## Poziom ulepszenia: rząd kresek, a przy dużej liczbie poziomów liczba.
func _draw_pips(cv: CanvasItem, c: Vector2, half: float, lv: int, mx: int, col: Color, z: float) -> void:
	if mx > 8:
		var t := "%d/%d" % [lv, mx]
		var sz := maxi(8, int(10 * z))
		var tw := font_b.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		cv.draw_string(font_b, c + Vector2(-tw * 0.5, sz * 0.4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		return
	var total := half * 1.25
	var gap := 2.0 * z
	var pw := (total - gap * (mx - 1)) / mx
	var ph := 3.5 * z
	for k in mx:
		var r := Rect2(c + Vector2(-total * 0.5 + k * (pw + gap), -ph * 0.5), Vector2(pw, ph))
		if k < lv:
			cv.draw_rect(r, col)
		else:
			cv.draw_rect(r, Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.9))


## Dzieli tekst na wiersze mieszczące się w szerokości dymka.
func _wrap(txt: String, fsize: int, width: float) -> Array:
	var out: Array = []
	var cur := ""
	for word in txt.split(" "):
		var next := word if cur == "" else cur + " " + word
		if font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > width and cur != "":
			out.append(cur)
			cur = word
		else:
			cur = next
	if cur != "":
		out.append(cur)
	return out


## Tekst w zadanej szerokości: najpierw mniejsza czcionka (do 10), potem ucięcie z "…".
func _fit_text(p: Vector2, s: String, fsize: int, c: Color, max_w: float) -> void:
	var fs := fsize
	while fs > 10 and font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 1
	var t := s
	while t.length() > 1 and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		t = t.substr(0, t.length() - 2) + "…"
	_text(p, t, fs, c)


## max_w > 0: koszt musi zmieścić się w tej szerokości - najpierw mniejsza czcionka, potem (wrap) kolejne
## wiersze albo, gdy nie ma na nie miejsca, same liczby przy kolorowych rombach.
func _cost_inline(p: Vector2, cost: Dictionary, fsize := 12, max_w := 0.0, wrap := false) -> void:
	var short := false
	if max_w > 0.0:
		while fsize > 10 and _cost_width(cost, fsize, false) > max_w:
			fsize -= 1
		short = not wrap and _cost_width(cost, fsize, false) > max_w
	var x := p.x
	for k in cost:
		var have := int(GameState.bank.get(k, 0))
		var ok := have >= int(cost[k])
		var s := str(int(cost[k])) if short else "%d %s" % [int(cost[k]), GameState.RES_NAMES[k]]
		if wrap and max_w > 0.0 and x > p.x and x - p.x + 10 + font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > max_w:
			x = p.x
			p.y += fsize + 6
		var dc := Vector2(x + 4, p.y - 4)
		draw_colored_polygon(PackedVector2Array([dc + Vector2(0, -4), dc + Vector2(4, 0), dc + Vector2(0, 4), dc + Vector2(-4, 0)]), GameState.RES_COLORS[k])
		_text(Vector2(x + 10, p.y), s, fsize, Color(0.55, 1.0, 0.6) if ok else Color(1.0, 0.45, 0.45))
		x += 10 + font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + 12


func _cost_width(cost: Dictionary, fsize: int, short: bool) -> float:
	var w := 0.0
	for k in cost:
		var s := str(int(cost[k])) if short else "%d %s" % [int(cost[k]), GameState.RES_NAMES[k]]
		w += 10 + font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + 12
	return w - 12


## Największa możliwa wartość statystyki broni (wszystkie ulepszenia z Mistrzostwem) - do pasków.
func _stat_bounds(key: String) -> Array:
	var base := float(GameState.BASE_STATS.get(key, 0.0))
	var best := base
	for u in Upgrades.ARMORY:
		if u["effects"].has(key):
			best += GameState.contribution(u, key, int(u["max"]))
	return [base, best]


func _text_on(cv: CanvasItem, p: Vector2, txt: String, fsize: int, c: Color) -> void:
	cv.draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, c)


## Płytka ze ściętymi rogami, bez krążącego światła (na karty, których jest dużo).
func _plate(r: Rect2, fill: Color, border: Color, w := 1.2) -> void:
	var pts := Style.chamfer_pts(r, 8.0)
	draw_colored_polygon(pts, fill)
	draw_polyline(Style.closed(pts), border, w, true)


## Punkt na zamkniętej łamanej w odległości d od początku.
func _along(pts: PackedVector2Array, d: float) -> Vector2:
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var l := a.distance_to(b)
		if d <= l:
			return a.lerp(b, d / maxf(l, 0.001))
		d -= l
	return pts[0]


## Panel ze ściętymi rogami, po którego ramce krąży światło.
func _hud_panel(cv: CanvasItem, r: Rect2, c: Color, fill := Style.PANEL, cut := 12.0) -> void:
	var pts := Style.chamfer_pts(r, cut)
	cv.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	cv.draw_polyline(closed, Color(c.r, c.g, c.b, 0.75), 1.5, true)
	var total := 2.0 * (r.size.x + r.size.y)
	var head := fmod(time * 70.0 + r.position.x + r.position.y * 3.0, total)
	for k in 6:
		var a := _along(pts, fmod(head + k * 7.0, total))
		var b := _along(pts, fmod(head + (k + 1) * 7.0, total))
		if a.distance_to(b) < 9.0:
			cv.draw_line(a, b, Color(c.r, c.g, c.b, 0.15 + k * 0.17), 2.5, true)


## Miniatura Statku Matki: ten sam ośmiokąt, ramiona i rdzeń co w locie.
func _draw_emblem(cv: CanvasItem, p: Vector2, s: float, a := 1.0) -> void:
	var rot := time * 0.5
	var pulse := 0.5 + 0.5 * sin(time * 3.0)
	for k in 4:
		var d := Vector2.from_angle(rot + k / 4.0 * TAU + PI / 8.0)
		cv.draw_line(p + d * s * 0.4, p + d * s * 1.3, Color(0.19, 0.93, 1.3, a), 1.6, true)
		cv.draw_circle(p + d * s * 1.3, 2.5, Color(1.3, 0.43, 1.13, a))
	var outer := PackedVector2Array()
	for k in 9:
		outer.append(p + Vector2.from_angle(rot + k / 8.0 * TAU) * s)
	cv.draw_colored_polygon(outer.slice(0, 8), Color(0.1, 0.0, 0.16, 0.92 * a))
	cv.draw_polyline(outer, Color(1.3, 0.2, 1.0, a), 2.0, true)
	var inner := PackedVector2Array()
	for k in 7:
		inner.append(p + Vector2.from_angle(-rot * 1.5 + k / 6.0 * TAU) * s * 0.52)
	cv.draw_polyline(inner, Color(1.3, 0.84, 0.23, a), 1.5, true)
	cv.draw_circle(p, s * (0.14 + pulse * 0.04), Color(1.0, 0.5, 1.2, a))


func _overlay_rect(which: String) -> Rect2:
	if which == "brief":
		var vs := get_viewport_rect().size
		return Rect2(20, 92, 470, minf(110.0 + _brief_rows() * QUEST_ROW, vs.y - 112.0))
	var rows := 0
	for g in STAT_GROUPS:
		rows += g[2].size()
	return Rect2(20, 92, 350, 50 + rows * 18 + STAT_GROUPS.size() * 26)


func _over_overlay(mp: Vector2) -> bool:
	return overlay != "" and _overlay_rect(overlay).has_point(mp)


func _toggle_overlay(which: String) -> void:
	overlay = "" if overlay == which else which
	if overlay != "":
		overlay_shown = overlay
		overlay_t = 0.0
		overlay_k = 0.0
	if overlay == "brief":
		GameState.quests_new = 0
		brief_scroll = 0
	Audio.play("ui_click", 0.0)


## Rozkazy na liście: najpierw te z nagrodą do odebrania, potem aktywne, na końcu ostatnio wykonane.
func _brief_lists() -> Array:
	var ready: Array = []
	var active: Array = []
	var done: Array = []
	for q in GameState.Quests.all():
		match GameState.quests.get(q["id"], ""):
			"ready": ready.append(q)
			"active": active.append(q)
			"done": done.append(q)
	return [ready + active, done]


func _brief_rows() -> int:
	var l := _brief_lists()
	return l[0].size() + l[1].size() + (1 if l[1].size() > 0 else 0)


## Wiersze listy rozkazów po kolei: [rozkaz albo {} dla nagłówka wykonanych, wysokość].
func _brief_items() -> Array:
	var lists := _brief_lists()
	var items: Array = []
	for q in lists[0]:
		items.append([q, QUEST_ROW])
	if not lists[1].is_empty():
		items.append([{}, QUEST_ROW * 0.5])
		var done: Array = lists[1].duplicate()
		done.reverse()
		for q in done:
			items.append([q, QUEST_ROW])
	return items


## Kółko myszy przewija listę rozkazów o jeden wiersz.
func _scroll_brief(dir: int) -> void:
	brief_scroll = maxi(0, brief_scroll + dir)
