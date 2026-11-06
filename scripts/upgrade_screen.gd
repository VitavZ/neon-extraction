extends Control
## Ekran statku matki: siatka ulepszeń (graf węzłów na siatce), magazyn surowców, przycisk wylotu,
## a parametry statku i rozkazy schowane pod przyciskami. Całość rysowana wektorowo w stylu synthwave.

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


func _ready() -> void:
	font = Style.font()
	font_b = Style.font_bold()
	pf = Style.font_pixel()
	GameState.bank_changed.connect(func(): nodes_dirty = true)
	GameState.stats_changed.connect(func(): nodes_dirty = true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	grid_view = Control.new()
	grid_view.clip_contents = true
	grid_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grid_view)
	grid_view.draw.connect(_draw_grid_view)
	# płytki i napisy rysują się tylko po zmianie, a co klatkę tylko ta cienka warstwa animacji
	grid_fx = Control.new()
	grid_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_view.add_child(grid_fx)
	grid_fx.draw.connect(_draw_grid_fx)
	# dymek z opisem nad wszystkim (osobna warstwa, żeby nie chował się pod węzłami)
	tip_view = Control.new()
	tip_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(tip_view)
	tip_view.draw.connect(_draw_tip_view)


func open(unloaded: Dictionary, status: String) -> void:
	last_unload = unloaded
	status_text = status
	reset_armed = false
	visible = true
	open_t = 0.0
	overlay = ""
	overlay_k = 0.0
	# liczniki startują sprzed rozładunku i doliczają się na oczach gracza
	for k in GameState.RES_ORDER:
		disp[k] = maxf(0.0, float(GameState.bank.get(k, 0)) - float(unloaded.get(k, 0)))
	if GameState.empire_unlocked() and not GameState.empire_seen and not empire_announced:
		empire_announced = true
		toasts.append({"line1": "NOWA ZAKŁADKA NA STATKU MATCE", "line2": "IMPERIUM", "t": 0.0})


func _process(delta: float) -> void:
	if not visible:
		return
	time += delta
	if nodes_dirty:
		_refresh_nodes()
	open_t = minf(open_t + delta, OPEN_LEN)
	tab_t = minf(tab_t + delta * 2.6, 1.0)
	overlay_t += delta
	overlay_k = move_toward(overlay_k, 1.0 if overlay != "" else 0.0, delta * 4.0)
	var tip_now: String = hovered.get("id", "")
	if tip_now != tip_id:
		tip_id = tip_now
		tip_t = 0.0
	tip_t = minf(tip_t + delta * 7.0, 1.0)
	_update_pl_fx(delta)
	picker_t += delta
	if not toasts.is_empty() and open_t >= OPEN_LEN:
		toasts[0]["t"] += delta
		if toasts[0]["t"] > 3.5:
			toasts.pop_front()
	if open_t > 0.75:
		for k in GameState.RES_ORDER:
			var goal := float(GameState.bank.get(k, 0))
			var cur: float = disp.get(k, goal)
			disp[k] = move_toward(cur, goal, maxf(absf(goal - cur) * 5.0, 12.0) * delta)
	var gr := _grid_view_rect()
	grid_view.position = gr.position
	grid_view.size = gr.size
	grid_view.visible = tab == "grid"
	grid_view.modulate.a = clampf((open_t - 0.35) / 0.4, 0.0, 1.0)
	grid_fx.size = gr.size
	if grid_view.visible:
		grid_fx.queue_redraw()
		if grid_force or tip_t < 1.0 or not flash.is_empty() or view_offset != drawn_offset or view_zoom != drawn_zoom or gr != drawn_rect:
			grid_force = false
			drawn_offset = view_offset
			drawn_zoom = view_zoom
			drawn_rect = gr
			grid_view.queue_redraw()
	tip_view.queue_redraw()
	for k in flash.keys():
		flash[k] -= delta
		if flash[k] <= 0.0:
			flash.erase(k)
			grid_force = true
	queue_redraw()


# ---------------- układ ----------------

func _grid_area() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(20.0, 92.0, vs.x - 340.0 - 20.0 - 20.0, vs.y - 92.0 - 20.0)


## Prostokąt widoku siatki (bez paska zakładek u góry i legendy na dole).
func _grid_view_rect() -> Rect2:
	var ga := _grid_area()
	return Rect2(ga.position + Vector2(1, 46), ga.size - Vector2(2, 46 + 30))


func _draw_grid_view() -> void:
	grid_view.draw_set_transform(-grid_view.position)
	_draw_grid_on(grid_view)


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


func _unhandled_input(event: InputEvent) -> void:
	if visible:
		if GameState.key_hit(event, "center"):
			reset_view()
		elif GameState.key_hit(event, "params"):
			_toggle_overlay("stats")


## ESC najpierw zamyka nakładkę, dopiero potem otwiera pauzę.
func _input(event: InputEvent) -> void:
	if visible and overlay != "" and GameState.key_hit(event, "pause"):
		overlay = ""
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var ga := _grid_area()
	if event is InputEventMouseMotion:
		mouse_pos = event.position
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _stats_rect().has_point(event.position):
				_toggle_overlay("stats")
				return
			if _brief_rect().has_point(event.position):
				_toggle_overlay("brief")
				return
			if overlay == "brief":
				for h in claim_hits:
					if h[0].has_point(event.position):
						_claim(h[1], h[0].get_center())
						return
		if overlay == "brief" and _over_overlay(event.position):
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_brief(1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_brief(-1)
		# nakładka zasłania to, co pod nią
		if _over_overlay(event.position):
			return
	# zakładki
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var tl := _tabs()
		for k in tl.size():
			if _tab_rect(k).has_point(event.position):
				if tab != tl[k]:
					tab_t = 0.0
				tab = tl[k]
				if tab == "empire":
					GameState.empire_seen = true
				Audio.play("ui_click", 0.0)
				hovered = {}
				dragging = false
				return
	if not tab in _tabs():
		tab = "grid"
	if tab == "bridge":
		_bridge_input(event)
		return
	if tab == "empire" and event is InputEventMouseButton and event.pressed and not _over_overlay(event.position):
		# otwarta lista surowców: wybór albo zamknięcie klikiem obok
		if res_picker >= 0:
			for h in picker_hits:
				if h[0].has_point(event.position):
					GameState.miner_res[res_picker] = h[1]
					Audio.play("ui_click", 0.0)
			res_picker = -1
			return
		for h in project_hits:
			if h[0].has_point(event.position):
				if emp_section != h[1]:
					emp_section = h[1]
					Audio.play("ui_click", 0.0)
				return
		for h in miner_hits:
			if h[0].has_point(event.position):
				res_picker = h[1]
				picker_t = 0.0
				Audio.play("ui_click", 0.0)
				return
	if tab == "armory" or tab == "lab" or tab == "empire":
		_armory_input(event)
		return
	if event is InputEventMouseMotion:
		var mp: Vector2 = event.position
		if dragging:
			view_offset += event.relative
			drag_moved += event.relative.length()
		hovered = {}
		if _grid_view_rect().has_point(mp) and not dragging and not _over_overlay(mp):
			for u in vis_nodes:
				if mp.distance_to(_node_pos(u)) < _node_r() + 4:
					hovered = u
					break
		hover_launch = _launch_rect().has_point(mp)
		hover_reset = _reset_rect().has_point(mp)
	elif event is InputEventMouseButton:
		var mp: Vector2 = event.position
		if event.pressed and ga.has_point(mp):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(mp, 1.12)
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(mp, 1.0 / 1.12)
				return
		# przeciąganie: prawy/środkowy przycisk zawsze, lewy - na pustym miejscu siatki
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			dragging = event.pressed and ga.has_point(mp)
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if not event.pressed:
			dragging = false
			return
		if hover_launch:
			Audio.play("ui_click", 0.0)
			launch_requested.emit()
		elif hover_reset:
			_go_menu()
		elif _center_view_rect().has_point(mp):
			reset_view()
		elif not hovered.is_empty():
			if GameState.buy(hovered):
				flash[hovered["id"]] = 0.6
				Audio.play("buy", 0.0)
			else:
				Audio.play("error", 0.0)
			reset_armed = false
		elif ga.has_point(mp):
			dragging = true
			drag_moved = 0.0


func _go_menu() -> void:
	if world:
		GameState.save_game(world.export_save())
	get_tree().change_scene_to_file("res://menu.tscn")


# ---------------- rysowanie ----------------

func _text(p: Vector2, s: String, fsize: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, p, s, align, width, fsize, c)


# ---------------- Sterownia ----------------

## Mapa USA w Sterowni (proporcje jak świat 3:2).
func _bridge_map_rect() -> Rect2:
	var ga := _grid_area()
	# mapa musi zostawić miejsce na panel przenosin pod spodem
	var h := minf((ga.size.x - 24.0) * float(Sectors.ROWS) / Sectors.COLS, ga.size.y - 52.0 - 130.0)
	var w := h * float(Sectors.COLS) / Sectors.ROWS
	return Rect2(ga.get_center().x - w * 0.5, ga.position.y + 52.0, w, h)


func _bridge_sector_rect(s: int) -> Rect2:
	var m := _bridge_map_rect()
	var size := m.size / Vector2(Sectors.COLS, Sectors.ROWS)
	return Rect2(m.position + Vector2(s % Sectors.COLS, s / Sectors.COLS) * size, size)


func _bridge_button_rect() -> Rect2:
	var ga := _grid_area()
	var m := _bridge_map_rect()
	return Rect2(ga.end.x - 212.0, m.end.y + 70.0, 200.0, 44.0)


func _bridge_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mp: Vector2 = event.position
		bridge_hover = -1
		for s in Sectors.LIST.size():
			if _bridge_sector_rect(s).has_point(mp):
				bridge_hover = s
		bridge_hover_btn = _bridge_button_rect().has_point(mp)
		hover_launch = _launch_rect().has_point(mp)
		hover_reset = _reset_rect().has_point(mp)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hover_launch:
			Audio.play("ui_click", 0.0)
			launch_requested.emit()
		elif hover_reset:
			_go_menu()
		elif bridge_hover_btn and bridge_sel >= 0:
			var to := bridge_sel
			bridge_sel = -1
			mother_move_requested.emit(to)
		elif bridge_hover >= 0 and bridge_hover != GameState.mother_sector:
			if GameState.sector_open(bridge_hover):
				bridge_sel = bridge_hover
				Audio.play("ui_click", 0.0)
			else:
				Audio.play("error", 0.0)


func _draw_bridge() -> void:
	if world == null:
		return
	var m := _bridge_map_rect()
	draw_texture_rect(world.minimap_tex, m, false)
	for s in Sectors.LIST.size():
		var r := _bridge_sector_rect(s)
		var info: Dictionary = Sectors.LIST[s]
		var here: bool = s == GameState.mother_sector
		if Sectors.is_void(s):
			draw_rect(r, Color(0.0, 0.0, 0.03, 0.75))
			continue
		if not GameState.sector_open(s):
			# zamknięty Dystrykt Federalny: czerwona kratka i licznik metropolii
			draw_rect(r, Color(0.12, 0.0, 0.02, 0.55))
			var step := 14.0
			var o := 0.0
			while o < r.size.x + r.size.y:
				var a := r.position + Vector2(minf(o, r.size.x), maxf(0.0, o - r.size.x))
				var b := r.position + Vector2(maxf(0.0, o - r.size.y), minf(o, r.size.y))
				draw_line(a, b, Color(1.2, 0.15, 0.15, 0.18), 1.0)
				o += step
			draw_rect(r.grow(-1.0), Color(1.2, 0.2, 0.2, 0.9 if s == bridge_hover else 0.6), false, 2.0)
			var pr: Vector2i = GameState.metros_progress()
			var lt := "ZABLOKOWANY"
			var st := "Zniszcz metropolie: %d/%d" % [pr.x, pr.y]
			_text(r.position + Vector2(10, 20), String(info["name"]), 12, Color(1.0, 0.4, 0.4))
			var lb := Rect2(r.position.x + 8, r.end.y - 52, r.size.x - 16, 44)
			draw_rect(lb, Color(0.05, 0.0, 0.01, 0.9))
			draw_rect(lb, Color(1.2, 0.2, 0.2, 0.7), false, 1.0)
			draw_string(font_b, Vector2(lb.get_center().x - font_b.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x * 0.5, lb.position.y + 18), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.2, 0.3, 0.3))
			draw_string(font, Vector2(lb.get_center().x - font.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x * 0.5, lb.position.y + 36), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.7, 0.7))
		var col: Color = Style.GOLD if here else (C_LINE_ON if s == bridge_sel else (Color(1, 1, 1) if s == bridge_hover else Color(0.4, 0.9, 1.0, 0.6)))
		if not GameState.sector_open(s):
			col = Color(1.0, 0.4, 0.4)
		if s == bridge_sel or s == bridge_hover:
			draw_rect(r, Color(col.r, col.g, col.b, 0.12))
		draw_rect(r.grow(-1.0), col, false, 2.0 if here or s == bridge_sel or s == bridge_hover else 1.0)
		draw_rect(Rect2(r.position + Vector2(5, 5), Vector2(font.get_string_size(String(info["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10, 20)), Color(0, 0, 0, 0.75))
		_text(r.position + Vector2(10, 20), String(info["name"]), 12, col)
		var world_size := Vector2(Sectors.W, Sectors.H) * float(world.T)
		if Sectors.has_city(s):
			var cp: Vector2 = m.position + world.city_pos(s) / world_size * m.size
			draw_rect(Rect2(cp - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.4, 0.95))
			var cname: String = info["city"]
			var cw := font_b.get_string_size(cname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var cl := Vector2(clampf(cp.x - cw * 0.5, r.position.x + 4, r.end.x - cw - 4), clampf(cp.y - 8, r.position.y + 40, r.end.y - 6))
			draw_string_outline(font_b, cl, cname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.95))
			draw_string(font_b, cl, cname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.8, 1.0))
		for lk in world.landmarks_in_sector(s):
			var lp: Vector2 = m.position + world.landmark_pos(lk) / world_size * m.size
			var red := Color(1.3, 0.2, 0.2)
			draw_rect(Rect2(lp - Vector2(4, 4), Vector2(8, 8)), red)
			draw_rect(Rect2(lp - Vector2(7, 7), Vector2(14, 14)), Color(red.r, red.g, red.b, 0.5), false, 1.5)
			var ln: String = Sectors.LANDMARKS[lk]["name"]
			var lw := font_b.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			# podpisy na prawo od znaczników (Waszyngton wyżej, Pentagon niżej) - nie zasłaniają nazwy sektora
			var ll := Vector2(minf(lp.x + 12.0, r.end.x - lw - 4), maxf(lp.y + (-2.0 if lk % 2 == 0 else 16.0), r.position.y + (46.0 if lk % 2 == 0 else 64.0)))
			draw_string_outline(font_b, ll, ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.95))
			draw_string(font_b, ll, ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.3, 0.3))
		if here:
			var mp: Vector2 = m.position + world.dock_pos(s) / world_size * m.size
			draw_arc(mp, 8.0, 0.0, TAU, 20, Style.GOLD, 2.0, true)
			draw_circle(mp, 3.0, Style.GOLD)
	# panel przenosin
	var ga := _grid_area()
	var y := m.end.y + 26.0
	var x := ga.position.x + 14.0
	var cur: Dictionary = Sectors.LIST[GameState.mother_sector]
	_text(Vector2(x, y), "STATEK MATKA: %s (%s)" % [cur["name"], Sectors.label(GameState.mother_sector)], 14, Style.GOLD)
	y += 24.0
	if bridge_sel < 0:
		_text(Vector2(x, y), "Kliknij sektor na mapie, aby wybrać cel przenosin.", 12, Style.TEXT_DIM)
		_text(Vector2(x, y + 20.0), "Do sąsiednich sektorów dolecisz też samym statkiem: wystarczy przekroczyć granicę.", 12, Style.TEXT_DIM)
		return
	var dest: Dictionary = Sectors.LIST[bridge_sel]
	var n := Sectors.steps(GameState.mother_sector, bridge_sel)
	_text(Vector2(x, y), "CEL: %s (%s), odległość: %d" % [dest["name"], Sectors.label(bridge_sel), n], 13, C_LINE_ON)
	y += 22.0
	_text(Vector2(x, y), "Koszt:", 12, Style.TEXT_DIM)
	var cost := GameState.move_cost(bridge_sel)
	_cost_inline(Vector2(x, y + 18.0), cost, 12)
	var br := _bridge_button_rect()
	var ok := GameState.can_afford(cost)
	Style.panel(self, br, C_LINE_ON if ok else Style.DIM, Color(0.04, 0.14, 0.07, 0.95) if ok else Color(0.06, 0.03, 0.08, 0.95))
	var label := "PRZENIEŚ MATKĘ" if ok else "ZA MAŁO SUROWCÓW"
	var lw := font_b.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font_b, br.position + Vector2(br.size.x * 0.5 - lw * 0.5, 28), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_LINE_ON if ok else Style.TEXT_DIM)


func _armory_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mp: Vector2 = event.position
		hovered = {}
		for h in armory_hits:
			if h[0].has_point(mp) and not _over_overlay(mp):
				hovered = h[1]
				break
		hover_launch = _launch_rect().has_point(mp)
		hover_reset = _reset_rect().has_point(mp)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hover_launch:
			Audio.play("ui_click", 0.0)
			launch_requested.emit()
		elif hover_reset:
			_go_menu()
		elif not hovered.is_empty():
			if tab == "lab":
				Audio.play("ui_click" if GameState.start_research(hovered) else "error", 0.0)
			elif GameState.buy(hovered):
				Audio.play("buy", 0.0)
				flash[hovered["id"]] = 0.6
			else:
				Audio.play("error", 0.0)


func _draw() -> void:
	var vs := get_viewport_rect().size
	_draw_background(vs)
	if not tab in _tabs():
		tab = "grid"
	if tab == "grid":
		_draw_grid()
	elif tab == "armory":
		_draw_armory()
	elif tab == "bridge":
		_draw_bridge()
	elif tab == "empire":
		_draw_empire()
	else:
		_draw_lab()
	_draw_tabs()
	_draw_top_bar(vs)
	_draw_rail(vs)


func _draw_background(vs: Vector2) -> void:
	# prawie czarne tło z delikatną szachownicą rombów (Agrivore) + przygaszony horyzont synthwave
	draw_rect(Rect2(Vector2.ZERO, vs), Style.BG)
	if bg_mesh == null or bg_size != vs:
		bg_size = vs
		var mp = MeshPainter.new()
		var cell := 64.0
		for yy in range(0, int(vs.y / cell) + 2):
			for xx in range(0, int(vs.x / cell) + 2):
				if (xx + yy) % 2 == 0:
					continue
				var c := Vector2(xx * cell, yy * cell)
				mp.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -cell * 0.5), c + Vector2(cell * 0.5, 0), c + Vector2(0, cell * 0.5), c + Vector2(-cell * 0.5, 0)]), Color(0.07, 0.02, 0.1))
		bg_mesh = mp.build_mesh()
	draw_mesh(bg_mesh, null)
	var horizon := vs.y * 0.7
	var sr := 170.0
	var sc := Vector2(vs.x * 0.5, horizon)
	for k in 9:
		var yy := -sr + k * 20.0
		var half := sqrt(maxf(0.0, sr * sr - yy * yy))
		draw_line(Vector2(sc.x - half, sc.y + yy), Vector2(sc.x + half, sc.y + yy), Color(1.0, 0.35, 0.5, 0.08 + k * 0.012), 3.0)
	var gc := Color(0.8, 0.2, 0.7, 0.13)
	for k in range(-20, 21):
		draw_line(Vector2(vs.x * 0.5 + k * 40.0, horizon), Vector2(vs.x * 0.5 + k * 220.0, vs.y), gc, 1.0)
	var off := fmod(time * 0.3, 1.0)
	for k in 10:
		var f := (float(k) + off) / 10.0
		var y := horizon + (vs.y - horizon) * f * f
		draw_line(Vector2(0, y), Vector2(vs.x, y), Color(gc.r, gc.g, gc.b, gc.a * f + 0.03), 1.0)
	draw_line(Vector2(0, horizon), Vector2(vs.x, horizon), Color(1.0, 0.3, 0.75, 0.35), 1.5)
	# obszar siatki
	var gr := _grid_area()
	draw_colored_polygon(_chamfer(gr, 14.0), Color(0.01, 0.0, 0.025, 0.93))
	_draw_hangar(gr)
	var dot := 48.0
	var gx := gr.position.x + fmod(view_offset.x, dot)
	while gx < gr.end.x:
		var gy := gr.position.y + 46 + fmod(view_offset.y, dot)
		while gy < gr.end.y - 30:
			if gx > gr.position.x and gy > gr.position.y + 46:
				draw_rect(Rect2(gx, gy, 1, 1), Color(0.45, 0.3, 0.55, 0.35))
			gy += dot
		gx += dot
	_hud_panel(self, gr, Color(0.8, 0.35, 0.9), Color(0, 0, 0, 0), 14.0)


func _node_state(u: Dictionary) -> String:
	var lv := GameState.get_level(u["id"])
	if lv >= int(u["max"]):
		return "max"
	if not GameState.is_reachable(u):
		return "locked"
	if GameState.can_afford(GameState.cost_of(u)):
		return "buy"
	if lv > 0:
		return "owned"
	return "available"


const C_BUY := Color(0.36, 1.0, 0.48)
const C_LOCK := Color(0.32, 0.28, 0.38)


const C_LINE_ON := Color(0.35, 1.0, 0.45)
const C_LINE_OFF := Color(0.42, 0.2, 0.5, 0.75)


## Stany węzłów liczone tylko po zmianie magazynu lub poziomów, nie w każdej klatce.
func _refresh_nodes() -> void:
	nodes_dirty = false
	grid_force = true
	vis_nodes.clear()
	vis_ids.clear()
	node_states.clear()
	for u in Upgrades.LIST:
		if _is_visible(u):
			vis_nodes.append(u)
			vis_ids[u["id"]] = true
			node_states[u["id"]] = _node_state(u)
	# plus przy zakładce tylko wtedy, gdy naprawdę jest co kupić
	armory_dot = Upgrades.ARMORY.any(func(u): return GameState.can_buy(u))
	lab_dot = GameState.research.is_empty() and Upgrades.LAB.any(func(u): return GameState.can_buy(u))


## Ośmiokąt ze ściętymi rogami, ten sam kształt co kadłub Statku Matki.
func _octagon(c: Vector2, half: float) -> PackedVector2Array:
	var cut := half * 0.34
	var a := half - cut
	return PackedVector2Array([c + Vector2(-a, -half), c + Vector2(a, -half), c + Vector2(half, -a), c + Vector2(half, a),
		c + Vector2(a, half), c + Vector2(-a, half), c + Vector2(-half, a), c + Vector2(-half, -a)])


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


func _draw_grid_on(cv: CanvasItem) -> void:
	var z := view_zoom
	var half := _node_r() * 0.86
	var w := clampf(z, 0.6, 1.4)
	# przewody: kupione świecą i płynie nimi energia, reszta to przygaszone łącza
	# tylko przewody drzewka: węzeł -> jego rodzic
	for u in vis_nodes:
		var pid := Upgrades.parent_of(u["id"])
		if pid != "" and vis_ids.has(pid):
			var n: Dictionary = Upgrades.by_id(pid)
			var a := _node_pos(u)
			var b := _node_pos(n)
			var dir := (b - a).normalized()
			var p0 := a + dir * half
			var p1 := b - dir * half
			if GameState.get_level(u["id"]) > 0 and GameState.get_level(n["id"]) > 0:
				cv.draw_line(p0, p1, Color(C_LINE_ON.r, C_LINE_ON.g, C_LINE_ON.b, 0.2), 6.0 * w)
				cv.draw_line(p0, p1, Color(C_LINE_ON.r, C_LINE_ON.g, C_LINE_ON.b, 0.85), 1.6 * w)
			else:
				cv.draw_line(p0, p1, C_LINE_OFF, 1.4 * w)

	for u in vis_nodes:
		var id: String = u["id"]
		var p := _node_pos(u)
		var cat: Color = Upgrades.CAT_COLORS[u["cat"]]
		var st: String = node_states.get(id, "locked")
		var lv := GameState.get_level(id)
		var mx := int(u["max"])
		var hov: bool = hovered.get("id", "") == id
		var f: float = flash.get(id, 0.0) / 0.6
		# węzeł wyskakuje pod kursorem i po zakupie
		var hs := half * (1.0 + (0.1 * _ease(tip_t) if hov else 0.0) + 0.2 * f)
		var plate := _octagon(p, hs)

		var fill := Color(cat.r * 0.05, cat.g * 0.05, cat.b * 0.07, 0.98)
		var border := Color(cat.r * 0.42, cat.g * 0.42, cat.b * 0.42)
		var icon_c := Color(cat.r * 0.5, cat.g * 0.5, cat.b * 0.5)
		var rim := 1.5
		match st:
			"buy":
				fill = Color(0.03 + cat.r * 0.06, 0.08 + cat.g * 0.06, 0.05 + cat.b * 0.06, 0.98)
				border = C_LINE_ON
				icon_c = cat
				rim = 2.0
			"owned":
				fill = Color(cat.r * 0.14, cat.g * 0.14, cat.b * 0.16, 0.98)
				border = cat
				icon_c = cat
				rim = 1.8
			"max":
				fill = Color(cat.r * 0.2, cat.g * 0.2, cat.b * 0.22, 0.98)
				border = Style.GOLD
				icon_c = cat
				rim = 2.2
		if id == "core":
			fill = Color(0.1, 0.0, 0.16, 0.98)
			border = Color(1.3, 0.2, 1.0)
			rim = 2.5

		if f > 0.0:
			fill = fill.lerp(Color(0.7, 0.7, 0.7), f * 0.5)

		cv.draw_colored_polygon(plate, fill)
		var outline := _closed(plate)
		cv.draw_polyline(outline, Color(border.r, border.g, border.b, 0.25), (rim + 3.0) * w, true)
		cv.draw_polyline(outline, border, rim * w, true)
		if st == "max":
			cv.draw_polyline(_closed(_octagon(p, hs - 4.0 * w)), Color(Style.GOLD.r, Style.GOLD.g, Style.GOLD.b, 0.4), 1.0, true)

		if id != "core":
			# ikona na górze płytki, poziom pod nią
			var has_pips: bool = mx > 1 and z >= 0.5
			var ic := p + Vector2(0, -half * 0.14 if has_pips else 0.0)
			Style.draw_icon(cv, Style.icon_for(id), ic, half * 0.5, icon_c, 1.7 * clampf(z, 0.7, 1.3))
			if has_pips:
				_draw_pips(cv, p + Vector2(0, half * 0.62), half, lv, mx, Style.GOLD if st == "max" else cat, z)
		if st == "buy":
			Style.plus_badge(cv, p + Vector2(hs - 2.0 * z, -hs + 2.0 * z), 5.0 * clampf(z, 0.7, 1.3), Style.PINK)

		# nazwa pod węzłem (ukryta przy mocnym oddaleniu)
		if z >= 0.6:
			var lsz := maxi(9, int(11 * z))
			var lab: String = String(u["label"]).to_upper()
			var lw := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, lsz).x
			var lp := p + Vector2(-lw * 0.5, half + 15 * z)
			var lc := C_LINE_ON if st == "buy" else (Style.GOLD if st == "max" else (Color(cat.r * 0.85, cat.g * 0.85, cat.b * 0.85) if lv > 0 else Style.TEXT_DIM))
			cv.draw_rect(Rect2(lp + Vector2(-3, -lsz + 1), Vector2(lw + 6, lsz + 3)), Color(0.0, 0.0, 0.02, 0.8))
			_text_on(cv, lp, lab, lsz, lc)


## Wszystko, co w siatce rusza się co klatkę: energia w przewodach, fale, iskry, celownik i wybuch zakupu.
func _draw_grid_fx() -> void:
	var cv := grid_fx
	cv.draw_set_transform(-grid_view.position)
	var z := view_zoom
	var half := _node_r() * 0.86
	var w := clampf(z, 0.6, 1.4)
	var area := Rect2(grid_view.position, grid_view.size).grow(half * 2.0)
	for u in vis_nodes:
		var id: String = u["id"]
		var p := _node_pos(u)
		if not area.has_point(p):
			continue
		var lv := GameState.get_level(id)
		var pid := Upgrades.parent_of(id)
		if lv > 0 and pid != "" and GameState.get_level(pid) > 0:
			# energia płynie od rodzica do węzła
			var pp := _node_pos(Upgrades.by_id(pid))
			var dir := (p - pp).normalized()
			var phase := fmod(time * 0.55 + u["pos"].x * 0.37 + u["pos"].y * 0.61 + 8.0, 1.0)
			cv.draw_circle((pp + dir * half).lerp(p - dir * half, phase), 2.4 * w, Color(0.85, 1.2, 0.9))
		var st: String = node_states.get(id, "locked")
		if st == "buy":
			# stać cię: fala rozchodząca się od węzła
			var wave := fmod(time * 0.7 + u["pos"].x * 0.3, 1.0)
			cv.draw_polyline(_closed(_octagon(p, half + 2.0 + wave * 10.0 * z)), Color(C_LINE_ON.r, C_LINE_ON.g, C_LINE_ON.b, 0.32 * (1.0 - wave)), 1.0, true)
		elif st == "max":
			# iskra krążąca po złotej ramie
			var perim := half * 8.0 * 0.83
			cv.draw_circle(_along(_octagon(p, half), fmod(time * 42.0 * z + u["pos"].x * 19.0, perim)), 2.0 * w, Color(1.3, 1.1, 0.7))
		if id == "core":
			_draw_emblem(cv, p, half * 0.52)
		var f: float = flash.get(id, 0.0) / 0.6
		if f > 0.0:
			# zakup: pierścień, kolczaste słońce i odłamki w kolorze kategorii
			var cat: Color = Upgrades.CAT_COLORS[u["cat"]]
			var g := 1.0 - f
			cv.draw_arc(p, half * (1.2 + g * 1.9), 0.0, TAU, 32, Color(cat.r, cat.g, cat.b, f), 2.5, true)
			Style.sunburst(cv, p, half * (1.0 + g * 1.3), 10, g * 1.4, Color(cat.r, cat.g, cat.b, f * 0.85), 1.6)
			for s in 10:
				var sd := Vector2.from_angle(s / 10.0 * TAU + 0.3)
				cv.draw_line(p + sd * half * (1.1 + g * 1.9), p + sd * half * (1.3 + g * 2.5), Color(1.0, 0.95, 0.8, f), 2.0)
		if hovered.get("id", "") == id:
			# celownik: narożniki oddychają wokół węzła
			var hs := half * (1.0 + 0.1 * _ease(tip_t))
			var hr := Rect2(p - Vector2(hs, hs), Vector2(hs, hs) * 2.0).grow((5.0 + 2.5 * sin(time * 7.0)) * z)
			var arm := hr.size.x * 0.2
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
				var cp: Vector2 = hr.position + hr.size * corner
				var sx := 1.0 if corner.x == 0.0 else -1.0
				var sy := 1.0 if corner.y == 0.0 else -1.0
				cv.draw_line(cp, cp + Vector2(arm * sx, 0), Style.CYAN, 2.0)
				cv.draw_line(cp, cp + Vector2(0, arm * sy), Style.CYAN, 2.0)


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


func _draw_tip_view() -> void:
	_draw_tab_wipe(tip_view)
	_draw_overlay(tip_view)
	_draw_toast(tip_view)
	_draw_pl_fx(tip_view)
	_draw_res_picker(tip_view)
	if tab == "grid" and not hovered.is_empty() and _grid_view_rect().has_point(mouse_pos):
		_draw_tooltip(tip_view, hovered)
	elif (tab == "armory" or tab == "lab" or tab == "empire") and not hovered.is_empty() and res_picker < 0:
		_draw_tooltip(tip_view, hovered)
	_draw_iris(tip_view, get_viewport_rect().size)


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


## Dymek w stylu Agrivore przy kursorze: nazwa / efekt / wartości / kupiono / koszt.
func _draw_tooltip(cv: CanvasItem, u: Dictionary) -> void:
	var vs := get_viewport_rect().size
	var cat: Color = Upgrades.CAT_COLORS.get(u["cat"], Style.TEXT)
	var lv := GameState.get_level(u["id"])
	var mx := int(u["max"])
	var rows: Array = []   # [tekst, kolor, rozmiar] ; "-" = linia podziału
	rows.append([String(u["name"]).to_upper(), cat, 14])
	rows.append("-")
	for ln in _wrap(GameState.keys_text(String(u.get("desc", ""))), 12, 270.0):
		rows.append([ln, Color(0.85, 0.78, 0.95), 12])
	var eff: Dictionary = u["effects"]
	for k in eff:
		rows.append([GameState.format_stat(k, float(eff[k]), true) + " " + String(GameState.STAT_NAMES[k]).to_upper(), C_LINE_ON, 12])
	if eff.size() > 0 and lv < mx:
		var k0: String = eff.keys()[0]
		var cur := GameState.stat(k0)
		rows.append("-")
		rows.append([GameState.format_stat(k0, cur) + "  ->  " + GameState.format_stat(k0, cur + GameState.gain(u, k0)), Style.GOLD, 13])
		if mx > 1 and lv == mx - 1:
			rows.append(["OSTATNI POZIOM: MISTRZOSTWO +25% EFEKTU", Style.GOLD, 12])
	elif mx > 1 and lv >= mx:
		rows.append(["MISTRZOSTWO: EFEKT +25%", Style.GOLD, 12])
	rows.append("-")
	rows.append(["KUPIONO: %d/%d" % [lv, mx], Style.TEXT, 12])
	rows.append("-")
	if lv >= mx:
		rows.append(["MAKSYMALNY POZIOM", Style.GOLD, 12])
	elif not GameState.is_reachable(u):
		var why := "ZABLOKOWANE: NAJPIERW KUP " + String(Upgrades.by_id(Upgrades.parent_of(u["id"])).get("label", "")).to_upper()
		if not GameState.requires_met(u):
			if u.has("pos") and u["requires"] is String:
				why = "ZABLOKOWANE: NAJPIERW KUP " + String(Upgrades.by_id(u["requires"]).get("label", "")).to_upper()
			else:
				why = "ZABLOKOWANE: NAJPIERW ODBLOKUJ BROŃ"
		rows.append([why, Style.RED, 12])
	else:
		var cost := GameState.cost_of(u)
		for k in cost:
			var have := int(GameState.bank.get(k, 0))
			var ok := have >= int(cost[k])
			rows.append(["%s  %d/%d" % [String(GameState.RES_NAMES[k]).to_upper(), have, int(cost[k])], C_LINE_ON if ok else Style.RED, 12, GameState.RES_COLORS[k]])
		if u.has("time"):
			rows.append(["CZAS BADANIA: %d s" % int(ceil(GameState.research_duration(u) / maxf(0.1, GameState.stat("research_speed")))), C_LINE_ON, 12])
			if not GameState.research.is_empty():
				rows.append(["LABORATORIUM ZAJĘTE", Style.GOLD, 12])
	var w := 320.0
	var h := 14.0
	for r in rows:
		h += 9.0 if r is String else 20.0
	var pos := mouse_pos + Vector2(22, 18)
	if pos.x + w > vs.x - 8:
		pos.x = mouse_pos.x - w - 22
	pos.y = clampf(pos.y, 8, vs.y - h - 8)
	pos.y += (1.0 - _ease(tip_t)) * 10.0
	var box := Rect2(pos, Vector2(w, h))
	_hud_panel(cv, box, cat, Color(0.0, 0.0, 0.02, 0.97), 10.0)
	var y := pos.y + 10
	for r in rows:
		if r is String:
			cv.draw_line(Vector2(pos.x + 8, y + 3), Vector2(pos.x + w - 8, y + 3), Color(1, 1, 1, 0.35), 1.0)
			y += 9
			continue
		var t: String = r[0]
		var sz: int = r[2]
		var tw := font_b.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var x := pos.x + w * 0.5 - tw * 0.5
		if r.size() > 3:
			var ic: Color = r[3]
			cv.draw_rect(Rect2(x - 14, y + 5, 8, 8), ic)
		cv.draw_string(font_b, Vector2(x, y + 14), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, r[1])
		y += 20


func _draw_grid() -> void:
	var ga := _grid_area()
	# legenda + podpowiedź sterowania (stałe miejsce na dole obszaru siatki)
	var ly := ga.end.y - 14
	var lx := ga.position.x + 14
	Style.plus_badge(self, Vector2(lx + 6, ly - 5), 5.0, Style.PINK)
	_text(Vector2(lx + 18, ly), "STAĆ CIĘ", 11, Style.TEXT_DIM)
	lx += 100
	draw_polyline(_closed(_octagon(Vector2(lx + 6, ly - 5), 6.5)), Upgrades.CAT_COLORS["defense"], 1.6, true)
	_text(Vector2(lx + 18, ly), "KUPIONE", 11, Style.TEXT_DIM)
	lx += 100
	draw_polyline(_closed(_octagon(Vector2(lx + 6, ly - 5), 6.5)), Style.GOLD, 1.6, true)
	_text(Vector2(lx + 18, ly), "MAKS.", 11, Style.TEXT_DIM)
	var hint := GameState.keys_text("PRZECIĄGNIJ: PRZESUŃ • KÓŁKO: ZOOM • {center}: WYŚRODKUJ")
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_text(Vector2(ga.end.x - 14 - hw, ly), hint, 11, Style.TEXT_DIM)
	# przycisk wyśrodkowania
	var cr := _center_view_rect()
	Style.panel(self, cr, Style.DIM, Color(0.03, 0.0, 0.06, 0.95))
	# napis dokładnie na środku przycisku (w poziomie i w pionie)
	var ct := "WYŚRODKUJ"
	var cw := font.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var cy := cr.get_center().y + (font.get_ascent(11) - font.get_descent(11)) * 0.5
	_text(Vector2(cr.get_center().x - cw * 0.5, cy), ct, 11, Style.TEXT)



func _draw_tabs() -> void:
	var names := {"grid": "ULEPSZENIA STATKU", "armory": "ZBROJOWNIA", "bridge": "STEROWNIA", "lab": "LABORATORIUM", "empire": "IMPERIUM"}
	var cols := {"grid": Color(1.0, 0.4, 0.8), "armory": Color(1.0, 0.45, 0.3), "bridge": Color(0.4, 0.9, 1.0), "lab": Color(0.55, 1.0, 0.45), "empire": Style.GOLD}
	var tl := _tabs()
	for k in tl.size():
		var key: String = tl[k]
		var r := _tab_rect(k)
		var active := tab == key
		var c: Color = cols[key]
		# zakładki tekstowe jak w Agrivore: aktywna złota z podkreśleniem, separatory "|"
		var tw := font_b.get_string_size(names[key], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var tx := r.position.x + r.size.x * 0.5 - tw * 0.5
		var hov := r.has_point(mouse_pos)
		var tc: Color = Style.GOLD if active else (c if hov else Style.TEXT_DIM)
		# zakładka w kształcie równoległoboku
		var sl := 9.0
		var shape := PackedVector2Array([r.position + Vector2(sl, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(sl, 0), Vector2(r.position.x, r.end.y)])
		if active or hov:
			draw_colored_polygon(shape, Color(tc.r, tc.g, tc.b, 0.13 if active else 0.07))
		shape.append(shape[0])
		draw_polyline(shape, Color(tc.r, tc.g, tc.b, 0.75 if active else 0.28), 1.2, true)
		draw_string(font_b, Vector2(tx, r.position.y + 20), names[key], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tc)
		if active:
			var goal := Rect2(tx, r.end.y - 3, tw, 2)
			tab_glide = goal if tab_glide.size.x <= 0.0 else Rect2(tab_glide.position.lerp(goal.position, 0.22), tab_glide.size.lerp(goal.size, 0.22))
			draw_rect(tab_glide, Style.GOLD)
		# zielona kropka: coś do zrobienia w tej zakładce
		var dot := false
		if key != tab:
			dot = armory_dot if key == "armory" else (lab_dot if key == "lab" else (key == "empire" and not GameState.empire_seen))
		if dot:
			Style.plus_badge(self, Vector2(tx + tw + 9, r.position.y + 9), 4.0, Style.PINK)


func _weapon_icon(key: String, c: Vector2, col: Color) -> void:
	Style.draw_icon(self, Style.icon_for(key), c, 13.0, col, 1.8)


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


## Kolor przewodni każdej broni (nagłówek, ramki, paski).
const WEAPON_COLORS := {"rockets": Color(1.0, 0.5, 0.25), "drones": Color(0.35, 1.0, 0.9), "guns": Color(1.0, 0.85, 0.35), "escort": Color(1.0, 0.45, 1.0)}


## Największa możliwa wartość statystyki broni (wszystkie ulepszenia z Mistrzostwem) - do pasków.
func _stat_bounds(key: String) -> Array:
	var base := float(GameState.BASE_STATS.get(key, 0.0))
	var best := base
	for u in Upgrades.ARMORY:
		if u["effects"].has(key):
			best += float(u["effects"][key]) * int(u["max"]) * (1.0 + Upgrades.MASTERY_BONUS if int(u["max"]) > 1 else 1.0)
	return [base, best]


func _draw_armory() -> void:
	armory_hits.clear()
	var ga := _grid_area()
	var margin := 14.0
	var top := ga.position.y + 54
	var nw := Upgrades.WEAPONS.size()
	var cw := (ga.size.x - margin * (nw + 1)) / float(nw)
	var ch := ga.end.y - 16 - top
	for wi in Upgrades.WEAPONS.size():
		var w: Dictionary = Upgrades.WEAPONS[wi]
		var key: String = w["key"]
		var wc: Color = WEAPON_COLORS.get(key, Style.PINK)
		var card := Rect2(ga.position.x + margin + wi * (cw + margin), top, cw, ch)
		var unlock: Dictionary = {}
		var ups: Array = []
		for u in Upgrades.ARMORY:
			if u["weapon"] == key:
				if u.get("unlock", false):
					unlock = u
				else:
					ups.append(u)
		var owned := GameState.get_level(unlock["id"]) > 0
		var cc: Color = wc if owned else Color(0.45, 0.38, 0.55)
		draw_colored_polygon(_chamfer(card, 14.0), Color(cc.r * 0.04, cc.g * 0.04, cc.b * 0.06 + 0.03, 0.96))
		_hud_panel(self, card, cc, Color(0, 0, 0, 0), 14.0)

		# nagłówek: ikona w ośmiokącie, nazwa, stan
		var head := Rect2(card.position + Vector2(10, 10), Vector2(card.size.x - 20, 64))
		draw_rect(head, Color(cc.r * 0.12, cc.g * 0.12, cc.b * 0.14, 0.9))
		draw_line(Vector2(head.position.x, head.end.y), Vector2(head.end.x, head.end.y), Color(cc.r, cc.g, cc.b, 0.5), 1.5)
		var ic := head.position + Vector2(34, 32)
		var oct := _octagon(ic, 24.0)
		draw_colored_polygon(oct, Color(cc.r * 0.15, cc.g * 0.15, cc.b * 0.18, 1.0))
		draw_polyline(_closed(oct), cc, 2.0, true)
		Style.draw_icon(self, Style.icon_for(key), ic, 13.0, cc, 1.8)
		draw_string(pf, head.position + Vector2(70, 34), String(w["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, cc if owned else Color(0.75, 0.7, 0.85))
		var state_txt := "AKTYWNE" if owned else "ZABLOKOWANE"
		var stc: Color = Color(0.45, 1.0, 0.55) if owned else Color(0.6, 0.55, 0.7)
		draw_string(font_b, head.position + Vector2(71, 54), state_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, stc)
		draw_multiline_string(font, card.position + Vector2(16, 98), String(w["desc"]), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32, 12, 3, Color(0.8, 0.75, 0.9))
		var y := card.position.y + 150

		if not owned:
			# duży przycisk odblokowania
			var br := Rect2(card.position.x + 16, y, card.size.x - 32, 54)
			var can := GameState.can_buy(unlock)
			var hov: bool = hovered.get("id", "") == unlock["id"]
			var pulse := 0.5 + 0.5 * sin(time * 4.0)
			var bc: Color = C_BUY if can else Color(0.5, 0.42, 0.6)
			var bp := _chamfer(br.grow(2.0 if hov else 0.0), 10.0)
			draw_colored_polygon(bp, Color(0.04, 0.16, 0.08, 0.95) if can else Color(0.07, 0.03, 0.1, 0.95))
			bp.append(bp[0])
			draw_polyline(bp, Color(bc.r, bc.g, bc.b, (0.6 + 0.4 * pulse) if can else 0.7), 2.0, true)
			var t := "ODBLOKUJ"
			draw_string(pf, Vector2(br.get_center().x - pf.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x * 0.5, br.position.y + 36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, bc)
			if can:
				Style.plus_badge(self, Vector2(br.end.x - 10, br.position.y + 10), 5.0, Style.PINK)
			armory_hits.append([br, unlock])
			_cost_inline(Vector2(br.position.x + 2, br.end.y + 26), GameState.cost_of(unlock), 12, br.size.x - 2, true)
			# co się odkryje
			var ly := br.end.y + 66
			_text(Vector2(br.position.x, ly), "PO ODBLOKOWANIU:", 11, Color(0.6, 0.55, 0.7))
			for u in ups:
				ly += 24
				Style.draw_icon(self, Style.icon_for(u["id"]), Vector2(br.position.x + 10, ly - 4), 7.0, Color(0.55, 0.5, 0.65), 1.4)
				_text(Vector2(br.position.x + 26, ly), String(u["label"]), 12, Color(0.6, 0.55, 0.7))
			continue

		# parametry broni z paskami: ile już z tego, co da się wycisnąć
		for st in w["stats"]:
			var v := GameState.stat(st)
			var bounds := _stat_bounds(st)
			var span: float = bounds[1] - bounds[0]
			var frac: float = 1.0 if absf(span) < 0.001 else clampf((v - bounds[0]) / span, 0.0, 1.0)
			_text(Vector2(card.position.x + 16, y), String(GameState.STAT_NAMES[st]), 12, Color(0.8, 0.75, 0.9))
			var vs_txt := GameState.format_stat(st, v)
			_text(Vector2(card.end.x - 16 - font_b.get_string_size(vs_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, y), vs_txt, 13, Color(1, 1, 1))
			var bar := Rect2(card.position.x + 16, y + 6, card.size.x - 32, 4)
			draw_rect(bar, Color(wc.r * 0.2, wc.g * 0.2, wc.b * 0.2, 0.9))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), wc)
			y += 30
		y += 8
		draw_line(Vector2(card.position.x + 16, y), Vector2(card.end.x - 16, y), Color(wc.r, wc.g, wc.b, 0.3), 1.0)
		y += 12

		# ulepszenia: płytki jak węzły siatki
		for u in ups:
			var rr := Rect2(card.position.x + 12, y, card.size.x - 24, 70)
			var lv := GameState.get_level(u["id"])
			var mx := int(u["max"])
			var st: String = "max" if lv >= mx else ("buy" if GameState.can_buy(u) else ("owned" if lv > 0 else "available"))
			var hov: bool = hovered.get("id", "") == u["id"]
			var border := Color(0.45, 0.38, 0.55)
			var fill := Color(0.04, 0.0, 0.07, 0.95)
			match st:
				"buy":
					border = C_BUY
					fill = Color(0.03, 0.11, 0.06, 0.95)
				"owned":
					border = wc
				"max":
					border = Style.GOLD
					fill = Color(0.1, 0.07, 0.02, 0.95)
			var f: float = flash.get(u["id"], 0.0) / 0.6
			if f > 0.0:
				fill = fill.lerp(Color(0.6, 0.6, 0.6), f * 0.6)
			var plate := _chamfer(rr.grow(2.0 if hov else 0.0), 9.0)
			draw_colored_polygon(plate, fill)
			plate.append(plate[0])
			draw_polyline(plate, Color(border.r, border.g, border.b, 1.0 if hov else 0.8), 2.0 if hov else 1.3, true)
			if f > 0.0:
				draw_polyline(_chamfer(rr.grow(4.0 + (1.0 - f) * 10.0), 9.0), Color(wc.r, wc.g, wc.b, f), 2.0, true)
			# ikona
			var uc := rr.position + Vector2(26, 35)
			var uo := _octagon(uc, 16.0)
			draw_colored_polygon(uo, Color(border.r * 0.15, border.g * 0.15, border.b * 0.15, 1.0))
			draw_polyline(_closed(uo), border, 1.5, true)
			Style.draw_icon(self, Style.icon_for(u["id"]), uc, 8.5, wc if lv > 0 or st == "buy" else Color(0.55, 0.5, 0.65), 1.5)
			var lx := rr.position.x + 52
			_text(Vector2(lx, rr.position.y + 22), String(u["label"]), 13, C_BUY if st == "buy" else (Style.GOLD if st == "max" else Color(0.95, 0.9, 1.0)))
			var eff: Dictionary = u["effects"]
			var es := ""
			for ek in eff:
				es += GameState.format_stat(ek, float(eff[ek]), true) + " " + String(GameState.STAT_NAMES[ek]) + "  "
			_text(Vector2(lx, rr.position.y + 40), es, 11, Color(0.5, 1.0, 0.6))
			if st == "max":
				_text(Vector2(lx, rr.position.y + 59), "MISTRZOSTWO: EFEKT +25%" if mx > 1 else "MAKSYMALNY POZIOM", 11, Style.GOLD)
			else:
				_cost_inline(Vector2(lx, rr.position.y + 59), GameState.cost_of(u), 11, rr.end.x - 8 - lx)
			# poziom: kreski w prawym górnym rogu
			var pw := 9.0
			for k in mx:
				var pr := Rect2(rr.end.x - 12 - (mx - k) * (pw + 3), rr.position.y + 12, pw, 4)
				draw_rect(pr, (Style.GOLD if st == "max" else wc) if k < lv else Color(0.3, 0.25, 0.38))
			if st == "buy":
				Style.plus_badge(self, Vector2(rr.end.x - 6, rr.position.y + 6), 4.5, Style.PINK)
			armory_hits.append([rr, u])
			y += 78


## Zakładka Imperium: skarbiec Punktów Chwały i Lojalności oraz miejsca na przyszłe dekrety.
func _draw_empire() -> void:
	armory_hits.clear()
	var ga := _grid_area()
	var top := ga.position.y + 56
	var gold := Style.GOLD
	# nagłówek z koroną
	var head := Rect2(ga.position.x + 14, top, ga.size.x - 28, 92)
	_hud_panel(self, head, gold, Color(0.08, 0.05, 0.0, 0.92), 14.0)
	var crown_c := head.position + Vector2(52, 46)
	var oct := _octagon(crown_c, 30.0)
	draw_colored_polygon(oct, Color(0.2, 0.13, 0.02))
	draw_polyline(_closed(oct), gold, 2.0, true)
	Style.draw_icon(self, "crown", crown_c, 16.0, gold, 2.0)
	draw_string(pf, head.position + Vector2(98, 46), "IMPERIUM VEX", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, gold)
	_text(head.position + Vector2(100, 72), "Skarbiec zasług Kapitana. Dekrety Imperium wymagają Punktów Chwały i Lojalności.", 12, Color(0.85, 0.78, 0.6))

	# dwie waluty: duże karty
	var cw := (head.size.x - 16) * 0.5
	var cards := [
		["glory", "PUNKTY CHWAŁY", "Za zniszczenie metropolii, Waszyngtonu, Pentagonu i za pokonanie bossów."],
		["loyalty", "PUNKTY LOJALNOŚCI", "Za wykonane rozkazy z Imperium Vex."],
	]
	for i in cards.size():
		var key: String = cards[i][0]
		var c: Color = GameState.RES_COLORS[key]
		var r := Rect2(head.position.x + i * (cw + 16), head.end.y + 16, cw, 150)
		var appear := _ease((tab_t - 0.1 - i * 0.15) / 0.5)
		r.position.y += (1.0 - appear) * 16.0
		_hud_panel(self, r, c, Color(c.r * 0.08, c.g * 0.08, c.b * 0.1, 0.94), 12.0)
		var ic := r.position + Vector2(40, 52)
		var o := _octagon(ic, 24.0)
		draw_colored_polygon(o, Color(c.r * 0.18, c.g * 0.18, c.b * 0.2))
		draw_polyline(_closed(o), c, 2.0, true)
		Style.draw_icon(self, GameState.CURRENCY_ICONS[key], ic, 13.0, c, 1.8)
		draw_string(font_b, r.position + Vector2(78, 40), cards[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)
		var n := str(int(GameState.bank.get(key, 0)))
		draw_string(pf, r.position + Vector2(78, 96), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(1.2, 1.2, 1.25))
		draw_multiline_string(font, r.position + Vector2(18, 126), cards[i][2], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36, 12, 2, Color(0.8, 0.75, 0.9))

	# projekty Imperium: zakładki nad treścią, każdy projekt ma swoją sekcję
	var dy := head.end.y + 16 + 150 + 20
	project_hits.clear()
	miner_hits.clear()
	var px := head.position.x
	for p in EMPIRE_PROJECTS:
		var pr := Rect2(px, dy, 250, 40)
		var on: bool = emp_section == p[0]
		var owned := GameState.get_level(p[3]) > 0
		var hov := pr.has_point(mouse_pos)
		var pc: Color = gold if on else (Color(0.85, 0.75, 0.5) if hov else Color(0.6, 0.52, 0.4))
		var pp := _chamfer(pr, 8.0)
		draw_colored_polygon(pp, Color(0.16, 0.1, 0.02, 0.95) if on else Color(0.05, 0.03, 0.02, 0.92))
		pp.append(pp[0])
		draw_polyline(pp, pc, 1.8 if on else 1.2, true)
		Style.draw_icon(self, p[2], pr.position + Vector2(22, 20), 9.0, pc, 1.6)
		_text(pr.position + Vector2(40, 25), p[1], 13, pc)
		if not owned and GameState.can_buy(Upgrades.by_id(p[3])):
			Style.plus_badge(self, Vector2(pr.end.x - 8, pr.position.y + 8), 4.5, Style.PINK)
		project_hits.append([pr, p[0]])
		px += 262
	# miejsce na kolejne projekty
	var soon := Rect2(px, dy, 200, 40)
	var sp := _chamfer(soon, 8.0)
	draw_colored_polygon(sp, Color(0.03, 0.02, 0.03, 0.8))
	sp.append(sp[0])
	draw_polyline(sp, Color(0.35, 0.3, 0.25), 1.0, true)
	_text(soon.position + Vector2(18, 25), "WKRÓTCE...", 13, Color(0.4, 0.35, 0.3))
	draw_line(Vector2(head.position.x, dy + 52), Vector2(head.end.x, dy + 52), Color(gold.r, gold.g, gold.b, 0.3), 1.0)
	var group: String = emp_section
	var unlock: Dictionary = {}
	for p in EMPIRE_PROJECTS:
		if p[0] == group:
			unlock = Upgrades.by_id(p[3])
	var y := dy + 68
	if GameState.get_level(unlock["id"]) <= 0:
		_draw_project_unlock(Rect2(head.position.x, y, head.size.x, 150), unlock)
		return
	if group == "miners":
		y = _draw_miner_slots(head, y)
	elif group == "transit":
		y = _draw_transit_slots(head, y)
	else:
		y = _draw_wing_slots(head, y)
	_draw_group_upgrades(head, y + 16, group)


func _draw_project_unlock(card: Rect2, unlock: Dictionary) -> void:
	var gold := Style.GOLD
	_hud_panel(self, card, gold, Color(0.06, 0.04, 0.0, 0.92), 12.0)
	var ic := card.position + Vector2(52, 60)
	var o := _octagon(ic, 30.0)
	draw_colored_polygon(o, Color(0.2, 0.13, 0.02))
	draw_polyline(_closed(o), gold, 2.0, true)
	Style.draw_icon(self, Style.icon_for(unlock["id"]), ic, 15.0, gold, 1.8)
	draw_string(pf, card.position + Vector2(100, 50), String(unlock["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, gold)
	draw_multiline_string(font, card.position + Vector2(100, 76), GameState.keys_text(String(unlock["desc"])), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 420, 12, 3, Color(0.85, 0.78, 0.6))
	var br := Rect2(card.end.x - 300, card.position.y + 44, 276, 56)
	var can := GameState.can_buy(unlock)
	var hov: bool = hovered.get("id", "") == unlock["id"]
	var bc: Color = C_BUY if can else Color(0.55, 0.45, 0.6)
	var bp := _chamfer(br.grow(2.0 if hov else 0.0), 10.0)
	draw_colored_polygon(bp, Color(0.04, 0.16, 0.08, 0.95) if can else Color(0.07, 0.03, 0.1, 0.95))
	bp.append(bp[0])
	draw_polyline(bp, bc, 2.0, true)
	var bt := "ODBLOKUJ"
	draw_string(pf, Vector2(br.get_center().x - pf.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x * 0.5, br.position.y + 36), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, bc)
	_cost_inline(Vector2(br.position.x + 4, br.end.y + 22), GameState.cost_of(unlock), 12)
	armory_hits.append([br, unlock])


## Statki wydobywcze: karta każdego statku, klik otwiera listę surowców.
func _draw_miner_slots(head: Rect2, y: float) -> float:
	var gold := Style.GOLD
	var n := mini(int(GameState.stat("miner_count")), 6)
	var sw := (head.size.x - 5 * 12.0) / 6.0
	for k in 6:
		var r := Rect2(head.position.x + k * (sw + 12.0), y, sw, 96)
		var on := k < n
		var res := String(GameState.miner_res[k])
		var rc: Color = GameState.RES_COLORS[res]
		var hov := on and (r.has_point(mouse_pos) or res_picker == k)
		var bc: Color = (rc if hov else Color(gold.r, gold.g, gold.b, 0.8)) if on else Color(0.35, 0.3, 0.4)
		var p := _chamfer(r, 9.0)
		draw_colored_polygon(p, Color(rc.r * 0.08, rc.g * 0.08, rc.b * 0.1, 0.95) if on else Color(0.03, 0.02, 0.05, 0.9))
		p.append(p[0])
		draw_polyline(p, bc, 1.6 if on else 1.0, true)
		_text(r.position + Vector2(12, 20), "STATEK %d" % (k + 1), 11, gold if on else Color(0.45, 0.4, 0.5))
		if not on:
			_text(r.position + Vector2(12, 58), "ZABLOKOWANY", 12, Color(0.45, 0.4, 0.5))
			continue
		miner_hits.append([r, k])
		# pole wyboru: aktualny surowiec i strzałka listy
		var field := Rect2(r.position.x + 10, r.position.y + 36, r.size.x - 20, 30)
		draw_rect(field, Color(0.0, 0.0, 0.02, 0.8))
		draw_rect(field, Color(rc.r, rc.g, rc.b, 0.7), false, 1.2)
		var dc := field.position + Vector2(14, 15)
		draw_colored_polygon(PackedVector2Array([dc + Vector2(0, -6), dc + Vector2(6, 0), dc + Vector2(0, 6), dc + Vector2(-6, 0)]), rc)
		draw_string(font_b, field.position + Vector2(28, 20), String(GameState.RES_NAMES[res]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, field.size.x - 52, 13, rc)
		var ax := field.end.x - 14
		var ay := field.position.y + 15
		draw_colored_polygon(PackedVector2Array([Vector2(ax - 5, ay - 3), Vector2(ax + 5, ay - 3), Vector2(ax, ay + 3)]), rc)
		_text(r.position + Vector2(12, 86), "Kliknij, aby wybrać surowiec", 10, Color(0.6, 0.55, 0.7) if not hov else Color(1.0, 0.9, 0.6))
	_text(Vector2(head.position.x, y + 116), "Statki pracują w locie: szukają złóż do ok. 75 kafelków od Statku Matki, poza zasięgiem miast i wieżyczek. Patrole mogą je zestrzelić.", 12, Color(0.7, 0.62, 0.5))
	return y + 124


## Myśliwce Imperium: trzy miejsca w hangarze i podpowiedź klawisza wezwania.
func _draw_wing_slots(head: Rect2, y: float) -> float:
	var gold := Style.GOLD
	var n := mini(int(GameState.stat("wing_count")), 3)
	var sw := (head.size.x - 2 * 12.0) / 3.0
	for k in 3:
		var r := Rect2(head.position.x + k * (sw + 12.0), y, sw, 96)
		var on := k < n
		var p := _chamfer(r, 9.0)
		draw_colored_polygon(p, Color(0.08, 0.05, 0.0, 0.95) if on else Color(0.03, 0.02, 0.05, 0.9))
		p.append(p[0])
		draw_polyline(p, Color(gold.r, gold.g, gold.b, 0.85) if on else Color(0.35, 0.3, 0.4), 1.6 if on else 1.0, true)
		var c := r.position + Vector2(48, 50)
		var body := PackedVector2Array([Vector2(18, 0), Vector2(0, -6), Vector2(-8, -15), Vector2(-12, -12), Vector2(-7, 0), Vector2(-12, 12), Vector2(-8, 15), Vector2(0, 6)])
		var xf := Transform2D(-PI * 0.5 + (sin(time * 1.5 + k) * 0.1 if on else 0.0), c) .scaled_local(Vector2(1.6, 1.6))
		var pts := xf * body
		draw_colored_polygon(pts, Color(0.18, 0.11, 0.02, 0.95) if on else Color(0.06, 0.05, 0.08))
		pts.append(pts[0])
		draw_polyline(pts, Color(1.35, 0.9, 0.3) if on else Color(0.35, 0.3, 0.4), 2.0, true)
		_text(r.position + Vector2(96, 32), "MYŚLIWIEC %d" % (k + 1), 13, gold if on else Color(0.45, 0.4, 0.5))
		_text(r.position + Vector2(96, 58), "GOTOWY W HANGARZE" if on else "ZABLOKOWANY", 11, Color(0.5, 1.0, 0.6) if on else Color(0.45, 0.4, 0.5))
	_text(Vector2(head.position.x, y + 116), GameState.keys_text("W locie klawisz [{wing}] wzywa myśliwce do Ciebie, a drugie wciśnięcie odsyła je do hangaru. Wróg też w nie celuje - zestrzelone wracają po dokowaniu."), 12, Color(0.7, 0.62, 0.5))
	return y + 124


## Statki tranzytowe: trzy miejsca w hangarze i co ile przylatują.
func _draw_transit_slots(head: Rect2, y: float) -> float:
	var gold := Style.GOLD
	var n := mini(int(GameState.stat("transit_count")), 3)
	var sw := (head.size.x - 2 * 12.0) / 3.0
	for k in 3:
		var r := Rect2(head.position.x + k * (sw + 12.0), y, sw, 96)
		var on := k < n
		var p := _chamfer(r, 9.0)
		draw_colored_polygon(p, Color(0.08, 0.05, 0.0, 0.95) if on else Color(0.03, 0.02, 0.05, 0.9))
		p.append(p[0])
		draw_polyline(p, Color(gold.r, gold.g, gold.b, 0.85) if on else Color(0.35, 0.3, 0.4), 1.6 if on else 1.0, true)
		var c := r.position + Vector2(50, 50)
		var xf := Transform2D(-PI * 0.5 + (sin(time * 1.2 + k) * 0.08 if on else 0.0), c).scaled_local(Vector2(1.5, 1.5))
		var hull := xf * PackedVector2Array([Vector2(22, 0), Vector2(12, -11), Vector2(-16, -11), Vector2(-22, -6), Vector2(-22, 6), Vector2(-16, 11), Vector2(12, 11)])
		draw_colored_polygon(hull, Color(0.18, 0.11, 0.02, 0.95) if on else Color(0.06, 0.05, 0.08))
		hull.append(hull[0])
		draw_polyline(hull, Color(1.35, 0.9, 0.3) if on else Color(0.35, 0.3, 0.4), 2.0, true)
		_text(r.position + Vector2(100, 32), "FRACHTOWIEC %d" % (k + 1), 13, gold if on else Color(0.45, 0.4, 0.5))
		_text(r.position + Vector2(100, 58), "GOTOWY DO KURSU" if on else "ZABLOKOWANY", 11, Color(0.5, 1.0, 0.6) if on else Color(0.45, 0.4, 0.5))
	var every := maxf(12.0, GameState.stat("transit_interval")) / maxf(1.0, float(n))
	_text(Vector2(head.position.x, y + 116), "W locie statek przylatuje co ok. %d s (gdy ładownia jest zapełniona choć w 15%%) i zabiera %d%% każdego surowca prosto do magazynu." % [int(every), int(round(GameState.stat("transit_share") * 100.0))], 12, Color(0.7, 0.62, 0.5))
	return y + 124


func _draw_group_upgrades(head: Rect2, uy: float, group: String) -> void:
	var gold := Style.GOLD
	var ups: Array = Upgrades.EMPIRE.filter(func(u): return not u.get("unlock", false) and u.get("group", "") == group)
	var uw := (head.size.x - (ups.size() - 1) * 12.0) / ups.size()
	# karty rosną, gdy któreś ulepszenie ma długą listę kosztów (np. Skaner planetarny)
	var uh := 122.0
	for u in ups:
		if GameState.get_level(u["id"]) < int(u["max"]):
			uh = maxf(uh, 88.0 + GameState.cost_of(u).size() * 14.0)
	for i in ups.size():
		var u: Dictionary = ups[i]
		var rr := Rect2(head.position.x + i * (uw + 12.0), uy, uw, uh)
		var lv := GameState.get_level(u["id"])
		var mx := int(u["max"])
		var st: String = "max" if lv >= mx else ("buy" if GameState.can_buy(u) else "available")
		var hov: bool = hovered.get("id", "") == u["id"]
		var border := Color(0.5, 0.42, 0.3)
		var fill := Color(0.05, 0.03, 0.0, 0.95)
		match st:
			"buy":
				border = C_BUY
				fill = Color(0.03, 0.11, 0.06, 0.95)
			"max":
				border = gold
		# ulepszenia za Punkt Chwały są wyróżnione: różowo-złota pulsująca ramka, poświata i gwiazda
		var glory: bool = u["cost"].has("glory")
		var gp := 0.5 + 0.5 * sin(time * 3.0)
		if glory:
			border = Style.PINK.lerp(gold, gp) if st != "max" else gold
			fill = Color(0.09, 0.02, 0.07, 0.96) if st != "buy" else Color(0.06, 0.09, 0.05, 0.96)
		var f: float = flash.get(u["id"], 0.0) / 0.6
		if f > 0.0:
			fill = fill.lerp(Color(0.6, 0.6, 0.6), f * 0.6)
		if glory:
			for g in 3:
				var halo := _chamfer(rr.grow(3.0 + g * 3.0), 11.0 + g * 2.0)
				halo.append(halo[0])
				draw_polyline(halo, Color(border.r, border.g, border.b, (0.28 - g * 0.08) * (0.6 + 0.4 * gp)), 2.0, true)
		var plate := _chamfer(rr.grow(2.0 if hov else 0.0), 9.0)
		draw_colored_polygon(plate, fill)
		if glory:
			# ukośne pasy w tle karty
			var sx := rr.position.x + 18.0
			while sx < rr.end.x - 8.0:
				var x2 := minf(sx + 40.0, rr.end.x - 4.0)
				draw_line(Vector2(sx, rr.end.y - 4.0), Vector2(x2, rr.end.y - 4.0 - (x2 - sx)), Color(1.0, 0.35, 0.8, 0.05), 6.0)
				sx += 26.0
		plate.append(plate[0])
		draw_polyline(plate, border, 2.0 if hov or glory else 1.3, true)
		if glory:
			# wstążka "PUNKT CHWAŁY" z gwiazdą na dolnej krawędzi
			var tag := "ZA PUNKT CHWAŁY"
			var tgw := font_b.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 32.0
			var tg := Rect2(rr.get_center().x - tgw * 0.5, rr.end.y - 9.0, tgw, 18.0)
			var tp := _chamfer(tg, 5.0)
			draw_colored_polygon(tp, Color(0.16, 0.03, 0.12, 1.0))
			tp.append(tp[0])
			draw_polyline(tp, border, 1.4, true)
			Style.draw_icon(self, "star", tg.position + Vector2(13, 9), 5.0, Color(1.3, 1.0, 0.5), 1.3)
			draw_string(font_b, Vector2(tg.position.x + 24, tg.position.y + 13), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.3, 1.0, 0.5))
		var uc := rr.position + Vector2(26, 34)
		var uo := _octagon(uc, 16.0)
		draw_colored_polygon(uo, Color(border.r * 0.15, border.g * 0.15, border.b * 0.15))
		draw_polyline(_closed(uo), border, 1.5, true)
		Style.draw_icon(self, Style.icon_for(u["id"]), uc, 8.5, gold, 1.5)
		var lx := rr.position.x + 52
		var pw := 8.0
		var tw := rr.end.x - 10.0 - lx
		# nazwa obok paska poziomów, efekt zawinięty w dwie linie, każdy koszt w osobnej linii
		_fit_text(Vector2(lx, rr.position.y + 24), String(u["label"]), 13, C_BUY if st == "buy" else (gold if st == "max" else Color(0.95, 0.9, 1.0)), tw - mx * (pw + 3) - 6.0)
		var eff: Dictionary = u["effects"]
		var es := ""
		for ek in eff:
			es += GameState.format_stat(ek, float(eff[ek]), true) + " " + String(GameState.STAT_NAMES[ek])
		draw_multiline_string(font, Vector2(lx, rr.position.y + 42), es, HORIZONTAL_ALIGNMENT_LEFT, tw, 11, 2, Color(0.5, 1.0, 0.6))
		if st == "max":
			_text(Vector2(lx, rr.position.y + 84), "MAKSYMALNY POZIOM", 11, gold)
		else:
			var cy := rr.position.y + 80
			var cost := GameState.cost_of(u)
			for ck in cost:
				_cost_inline(Vector2(lx, cy), {ck: cost[ck]}, 11)
				cy += 14
		for k in mx:
			draw_rect(Rect2(rr.end.x - 12 - (mx - k) * (pw + 3), rr.position.y + 12, pw, 4), gold if k < lv else Color(0.3, 0.25, 0.2))
		if st == "buy":
			Style.plus_badge(self, Vector2(rr.end.x - 6, rr.position.y + 6), 4.5, Style.PINK)
		armory_hits.append([rr, u])


## Lista surowców do wyboru dla statku wydobywczego (nad resztą ekranu).
func _draw_res_picker(cv: CanvasItem) -> void:
	picker_hits.clear()
	if res_picker < 0 or tab != "empire" or emp_section != "miners":
		res_picker = -1
		return
	var anchor := Rect2()
	for h in miner_hits:
		if h[1] == res_picker:
			anchor = h[0]
	if anchor.size == Vector2.ZERO:
		res_picker = -1
		return
	var rs: Array = MinersScript.RESOURCES
	var cols := 2
	var cw := 170.0
	var rh := 30.0
	var rows := int(ceil(rs.size() / float(cols)))
	var panel := Rect2(anchor.position.x, anchor.end.y + 6, cols * cw + 16, rows * rh + 46)
	var vs := get_viewport_rect().size
	panel.position.x = minf(panel.position.x, vs.x - 360.0 - panel.size.x)
	var a := _ease(picker_t / 0.15)
	panel.position.y += (1.0 - a) * -8.0
	_hud_panel(cv, panel, Style.GOLD, Color(0.03, 0.02, 0.04, 0.98), 10.0)
	cv.draw_string(font_b, panel.position + Vector2(12, 22), "SUROWIEC DLA STATKU %d" % (res_picker + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Style.GOLD)
	for i in rs.size():
		var res: String = rs[i]
		var r := Rect2(panel.position.x + 8 + (i % cols) * cw, panel.position.y + 34 + (i / cols) * rh, cw - 6, rh - 4)
		var rc: Color = GameState.RES_COLORS[res]
		var cur: bool = GameState.miner_res[res_picker] == res
		var hov := r.has_point(mouse_pos)
		if hov or cur:
			cv.draw_rect(r, Color(rc.r, rc.g, rc.b, 0.18 if hov else 0.1))
		if cur:
			cv.draw_rect(r, Color(rc.r, rc.g, rc.b, 0.8), false, 1.2)
		var dc := r.position + Vector2(12, r.size.y * 0.5)
		cv.draw_colored_polygon(PackedVector2Array([dc + Vector2(0, -5), dc + Vector2(5, 0), dc + Vector2(0, 5), dc + Vector2(-5, 0)]), rc)
		cv.draw_string(font, r.position + Vector2(24, 18), String(GameState.RES_NAMES[res]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, rc.lerp(Color(1, 1, 1), 0.2))
		var n := str(int(GameState.bank.get(res, 0)))
		cv.draw_string(font, Vector2(r.end.x - 8 - font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, r.position.y + 18), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.7, 0.8))
		picker_hits.append([r, res])


func _draw_lab() -> void:
	armory_hits.clear()
	var ga := _grid_area()
	var lc: Color = Upgrades.CAT_COLORS["lab"]
	var top := ga.position.y + 52
	# ---- lewa kolumna: istoty, aktualne badanie ----
	var lw := 250.0
	var lr := Rect2(ga.position.x + 12, top, lw, ga.end.y - 14 - top)
	_hud_panel(self, lr, Color(lc.r, lc.g, lc.b, 0.8), Color(0.03, 0.06, 0.03, 0.95), 12.0)
	var y := lr.position.y + 26
	var x := lr.position.x + 14
	_text(Vector2(x, y), "OKAZY W KRIOKOMORACH", 14, lc)
	y += 24
	for ck in GameState.CREATURES:
		var c: Color = GameState.RES_COLORS[ck]
		draw_rect(Rect2(x, y - 9, 8, 8), c)
		_text(Vector2(x + 14, y), String(GameState.RES_NAMES[ck]), 13, c)
		var n := str(int(GameState.bank.get(ck, 0)))
		_text(Vector2(lr.end.x - 14 - font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, y), n, 13, Color(1, 1, 1))
		y += 20
	_text(Vector2(x, y + 4), GameState.keys_text("Porywaj klawiszem [{tool2}] w locie."), 11, Color(0.6, 0.7, 0.6))
	y += 36
	_text(Vector2(x, y), "AKTUALNE BADANIE", 14, lc)
	y += 24
	if GameState.research.is_empty():
		_text(Vector2(x, y), "Brak - wybierz badanie.", 11, Color(0.7, 0.7, 0.7))
		y += 20
	else:
		var ru: Dictionary = Upgrades.by_id(String(GameState.research["id"]))
		_text(Vector2(x, y), String(ru.get("name", "?")), 13, Color(1, 1, 1))
		y += 12
		var rf: float = float(GameState.research["progress"]) / float(GameState.research["duration"])
		draw_rect(Rect2(x, y, lw - 28, 12), Color(0.0, 0.0, 0.0, 0.8))
		draw_rect(Rect2(x, y, (lw - 28) * rf, 12), lc)
		y += 30
		_text(Vector2(x, y), "Pozostało: %d s  (szybkość %s)" % [int(ceil(GameState.research_time_left())), GameState.format_stat("research_speed", GameState.stat("research_speed"))], 12, Color(0.8, 0.9, 0.8))
		y += 14

	# ---- prawa część: projekty badawcze (tylko odkryte) ----
	var area := Rect2(lr.end.x + 12, top, ga.end.x - 12 - (lr.end.x + 12), ga.end.y - 14 - top)
	var colw := (area.size.x - 10) / 2.0
	var hidden_cnt := 0
	var k := 0
	for u in Upgrades.LAB:
		if not GameState.is_reachable(u) and GameState.get_level(u["id"]) == 0:
			hidden_cnt += 1
			continue
		var col := k % 2
		var row := k / 2
		var rr := Rect2(area.position.x + col * (colw + 10), area.position.y + row * 84, colw, 76)
		k += 1
		var lv := GameState.get_level(u["id"])
		var mx := int(u["max"])
		var active: bool = not GameState.research.is_empty() and String(GameState.research["id"]) == u["id"]
		var st := "max" if lv >= mx else ("buy" if GameState.can_buy(u) and GameState.research.is_empty() else "available")
		var border := Color(0.45, 0.5, 0.45)
		var fill := Color(0.04, 0.06, 0.04, 0.95)
		if active:
			border = lc
			fill = Color(0.06, 0.16, 0.06, 0.95)
		elif st == "buy":
			border = C_BUY
			fill = Color(0.04, 0.14, 0.07, 0.95)
		elif st == "max":
			border = Color(1.0, 0.85, 0.35)
		if flash.has(u["id"]):
			fill = fill.lerp(Color(0.6, 0.6, 0.6), flash[u["id"]])
		_plate(rr, fill, border, 2.5 if hovered == u else 1.2)
		_text(rr.position + Vector2(10, 20), String(u["label"]), 12, C_BUY if st == "buy" else Color(0.95, 1.0, 0.95))
		var lvs := "%d/%d" % [lv, mx]
		_text(Vector2(rr.end.x - 10 - font.get_string_size(lvs, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, rr.position.y + 20), lvs, 13, Color(0.8, 0.9, 0.8))
		var eff: Dictionary = u["effects"]
		var es := ""
		for ek in eff:
			es += GameState.format_stat(ek, float(eff[ek]), true) + " " + String(GameState.STAT_NAMES[ek]) + "  "
		if es == "":
			es = "Odblokowuje nowe badania"
		_text(rr.position + Vector2(10, 38), es, 11, Color(0.5, 1.0, 0.6))
		if active:
			var rf: float = float(GameState.research["progress"]) / float(GameState.research["duration"])
			draw_rect(Rect2(rr.position.x + 10, rr.position.y + 50, rr.size.x - 20, 10), Color(0, 0, 0, 0.8))
			draw_rect(Rect2(rr.position.x + 10, rr.position.y + 50, (rr.size.x - 20) * rf, 10), lc)
			_text(rr.position + Vector2(10, 72), "W TOKU — %d s" % int(ceil(GameState.research_time_left())), 11, lc)
		elif st == "max":
			_text(rr.position + Vector2(10, 58), "ZBADANE", 11, Color(1.0, 0.85, 0.35))
		else:
			_cost_inline(rr.position + Vector2(10, 56), GameState.cost_of(u), 11)
			var ts := "%d s" % int(ceil(GameState.research_duration(u) / maxf(0.1, GameState.stat("research_speed"))))
			_text(Vector2(rr.end.x - 10 - font.get_string_size(ts, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, rr.position.y + 70), ts, 11, Color(0.7, 0.8, 0.7))
		armory_hits.append([rr, u])
	if hidden_cnt > 0:
		var hy := area.position.y + ((k + 1) / 2) * 84 + 18
		_text(Vector2(area.position.x, hy), "Nieodkryte badania: %d — odkryją się po ukończeniu wcześniejszych." % hidden_cnt, 12, Color(0.55, 0.65, 0.55))


func _text_on(cv: CanvasItem, p: Vector2, txt: String, fsize: int, c: Color) -> void:
	cv.draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, c)


func _cat_label_on(cv: CanvasItem, p: Vector2, cat: String) -> void:
	var s: String = Upgrades.CAT_NAMES[cat]
	var c: Color = Upgrades.CAT_COLORS[cat]
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_text_on(cv, p + Vector2(-w * 0.5, 0), s, 14, c)


func _cat_label(p: Vector2, cat: String) -> void:
	var s: String = Upgrades.CAT_NAMES[cat]
	var c: Color = Upgrades.CAT_COLORS[cat]
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_text(p + Vector2(-w * 0.5, 0), s, 14, c)


# ---------------- panele i animacje ----------------

## Płytka ze ściętymi rogami, bez krążącego światła (na karty, których jest dużo).
func _plate(r: Rect2, fill: Color, border: Color, w := 1.2) -> void:
	var pts := _chamfer(r, 8.0)
	draw_colored_polygon(pts, fill)
	draw_polyline(_closed(pts), border, w, true)


func _ease(k: float) -> float:
	var c := clampf(k, 0.0, 1.0)
	return 1.0 - pow(1.0 - c, 3.0)


func _chamfer(r: Rect2, cut: float) -> PackedVector2Array:
	return PackedVector2Array([r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - cut),
		r.end - Vector2(cut, 0), Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut)])


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
	var pts := _chamfer(r, cut)
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


## Tło siatki: wielki, przygaszony przekrój Statku Matki i omiatający go radar.
func _draw_hangar(gr: Rect2) -> void:
	var c := gr.get_center() + (view_offset * 0.05).limit_length(30.0)
	var rad := minf(gr.size.y * 0.42, 340.0)
	var rot := time * 0.05
	var line := Color(0.9, 0.2, 0.8, 0.12)
	var ring := PackedVector2Array()
	for k in 9:
		ring.append(c + Vector2.from_angle(rot + k / 8.0 * TAU) * rad * 0.8)
	draw_polyline(ring, line, 2.0, true)
	var core := PackedVector2Array()
	for k in 7:
		core.append(c + Vector2.from_angle(-rot * 1.5 + k / 6.0 * TAU) * rad * 0.42)
	draw_polyline(core, Color(1.0, 0.75, 0.25, 0.1), 2.0, true)
	draw_arc(c, rad * 0.22, 0.0, TAU, 48, line, 1.5, true)
	for k in 4:
		var d := Vector2.from_angle(rot + k / 4.0 * TAU + PI / 8.0)
		var n := d.orthogonal()
		draw_polyline(PackedVector2Array([c + d * rad * 0.8 + n * 16.0, c + d * rad + n * 7.0, c + d * rad * 1.08, c + d * rad - n * 7.0, c + d * rad * 0.8 - n * 16.0]), Color(0.3, 0.9, 1.0, 0.12), 2.0, true)
	var sweep := time * 0.7
	for k in 14:
		var a0 := sweep - k * 0.035
		draw_line(c, c + Vector2.from_angle(a0) * rad * 1.08, Color(0.3, 0.95, 1.0, 0.075 * (1.0 - k / 14.0)), 2.0)
	# drobiny dryfujące przez hangar
	for k in 26:
		var sx := fmod(k * 137.5, gr.size.x)
		var speed := 8.0 + fmod(k * 13.0, 18.0)
		var sy := gr.size.y - 76.0 - fmod(time * speed + k * 61.0, gr.size.y - 76.0)
		var tw := 0.25 + 0.2 * sin(time * 2.0 + k)
		draw_rect(Rect2(gr.position + Vector2(sx, 46.0 + sy), Vector2(2, 2)), Color(0.7, 0.5, 1.0, tw))


func _draw_top_button(r: Rect2, label: String, c: Color, on: bool) -> void:
	var hov := r.has_point(mouse_pos)
	var col := Style.GOLD if on else c
	_hud_panel(self, r, col, Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.96) if (on or hov) else Color(col.r * 0.07, col.g * 0.07, col.b * 0.1, 0.94), 8.0)
	var w := font_b.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font_b, Vector2(r.get_center().x - w * 0.5, r.position.y + 23), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _draw_top_bar(vs: Vector2) -> void:
	var k := _ease((open_t - 0.3) / 0.6)
	draw_set_transform(Vector2(0.0, -(1.0 - k) * 100.0))
	draw_rect(Rect2(0, 0, vs.x, 78), Color(0.02, 0.0, 0.05, 0.92))
	_draw_emblem(self, Vector2(58, 40), 21.0)
	# rzadkie, krótkie zakłócenie tytułu
	var glitch := 3.0 if fmod(time, 5.3) < 0.08 else 0.0
	var title := "STATEK MATKA"
	draw_string(pf, Vector2(103 + glitch, 41), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(0.2, 0.9, 1.0, 0.55))
	draw_string(pf, Vector2(100 - glitch, 39), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Style.PINK)
	var sector_name: String = Sectors.LIST[GameState.mother_sector]["name"]
	_text(Vector2(101, 62), "WYPRAWA NR %d  //  SEKTOR: %s" % [GameState.sorties + 1, sector_name], 12, Style.CYAN)
	_draw_top_button(_stats_rect(), "PARAMETRY", Style.CYAN, overlay == "stats")
	_draw_top_button(_brief_rect(), "ROZKAZY", Style.PINK, overlay == "brief")
	if GameState.quests_new > 0 and overlay != "brief":
		var bc := Vector2(_brief_rect().end.x - 4, _brief_rect().position.y + 4)
		var pulse := 0.5 + 0.5 * sin(time * 6.0)
		draw_circle(bc, 9.0 + pulse * 1.5, Style.PINK)
		var n := str(mini(GameState.quests_new, 9))
		draw_string(font_b, bc + Vector2(-font_b.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x * 0.5, 4.5), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.05, 0.0, 0.08))
	_draw_top_button(_reset_rect(), "MENU GŁÓWNE", Color(0.8, 0.68, 0.95), false)
	# linia pod paskiem z biegnącym światłem
	draw_line(Vector2(0, 78), Vector2(vs.x, 78), Color(1.0, 0.3, 0.8, 0.55), 1.5)
	var run := fmod(time * 220.0, vs.x + 300.0) - 150.0
	draw_line(Vector2(run - 90.0, 78), Vector2(run + 90.0, 78), Color(0.5, 1.0, 1.2, 0.9), 2.0)
	draw_set_transform(Vector2.ZERO)


func _draw_rail(vs: Vector2) -> void:
	var k := _ease((open_t - 0.4) / 0.6)
	draw_set_transform(Vector2((1.0 - k) * 380.0, 0.0))
	var x := vs.x - 340.0
	# raport z ostatniego lotu
	var rr := Rect2(x, 92, 320, 104)
	_hud_panel(self, rr, Style.GOLD)
	_text(rr.position + Vector2(16, 24), "RAPORT Z LOTU", 13, Style.GOLD)
	draw_multiline_string(font, rr.position + Vector2(16, 46), status_text, HORIZONTAL_ALIGNMENT_LEFT, 288, 12, 2, Color(0.95, 0.9, 1.0))
	var tot := 0
	for r_key in last_unload:
		tot += int(last_unload[r_key])
	if tot > 0:
		_text(rr.position + Vector2(16, 92), "Rozładowano: %d jedn." % tot, 12, C_LINE_ON)

	# magazyn: liczniki doliczają się po rozładunku i zjeżdżają po zakupie
	var br := Rect2(x, 206, 320, _launch_rect().position.y - 216)
	_hud_panel(self, br, Color(1.0, 0.5, 0.15))
	_text(br.position + Vector2(16, 24), "MAGAZYN", 13, Color(1.0, 0.6, 0.2))
	draw_line(br.position + Vector2(16, 33), br.position + Vector2(304, 33), Color(1.0, 0.5, 0.15, 0.3), 1.0)
	var y := br.position.y + 54
	# waluty Imperium: osobne kafelki na górze magazynu, poza listą surowców
	var cur: Array = GameState.CURRENCIES.filter(func(c): return int(GameState.bank.get(c, 0)) > 0)
	if not cur.is_empty():
		var cw := (br.size.x - 32.0 - (cur.size() - 1) * 8.0) / cur.size()
		for i in cur.size():
			var ck: String = cur[i]
			var cc: Color = GameState.RES_COLORS[ck]
			var appear_c := _ease((open_t - 0.6 - i * 0.06) / 0.25)
			var cr := Rect2(br.position.x + 16 + i * (cw + 8.0), br.position.y + 44 + (1.0 - appear_c) * 12.0, cw, 54)
			var cp := _chamfer(cr, 8.0)
			draw_colored_polygon(cp, Color(cc.r * 0.14, cc.g * 0.14, cc.b * 0.16, 0.95 * appear_c))
			cp.append(cp[0])
			draw_polyline(cp, Color(cc.r, cc.g, cc.b, 0.85 * appear_c), 1.6, true)
			Style.draw_icon(self, GameState.CURRENCY_ICONS[ck], cr.position + Vector2(16, 18), 8.0, Color(cc.r, cc.g, cc.b, appear_c), 1.6)
			draw_string(font_b, cr.position + Vector2(30, 22), GameState.CURRENCY_SHORT[ck], HORIZONTAL_ALIGNMENT_LEFT, cw - 34, 10, Color(cc.r, cc.g, cc.b, appear_c))
			var cv_txt := str(int(round(disp.get(ck, float(GameState.bank.get(ck, 0))))))
			var cvw := font_b.get_string_size(cv_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			draw_string(font_b, Vector2(cr.end.x - 10 - cvw, cr.end.y - 10), cv_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.2, 1.2, 1.25, appear_c))
		y = br.position.y + 44 + 54 + 30
		_text(Vector2(br.position.x + 16, y - 6), "SUROWCE", 11, Color(1.0, 0.6, 0.2, 0.8))
		draw_line(Vector2(br.position.x + 80, y - 10), Vector2(br.end.x - 16, y - 10), Color(1.0, 0.5, 0.15, 0.25), 1.0)
		y += 18
	var any := not cur.is_empty()
	var row := 0
	for r_key in GameState.RES_ORDER:
		if r_key in GameState.CURRENCIES:
			continue
		var n := int(GameState.bank.get(r_key, 0))
		if n <= 0 and not last_unload.has(r_key):
			continue
		if y > br.end.y - 8:
			break
		any = true
		var c: Color = GameState.RES_COLORS[r_key]
		var shown: float = disp.get(r_key, float(n))
		var appear := _ease((open_t - 0.65 - row * 0.025) / 0.25)
		var ox := (1.0 - appear) * 26.0
		var ca := Color(c.r, c.g, c.b, appear)
		if row % 2 == 0:
			draw_rect(Rect2(br.position.x + 8, y - 14, 304, 20), Color(1, 1, 1, 0.022))
		var dia := Vector2(br.position.x + 21 + ox, y - 4)
		draw_colored_polygon(PackedVector2Array([dia + Vector2(0, -5), dia + Vector2(5, 0), dia + Vector2(0, 5), dia + Vector2(-5, 0)]), ca)
		_text(Vector2(br.position.x + 34 + ox, y), String(GameState.RES_NAMES[r_key]), 13, ca)
		var num := Color(1, 1, 1, appear)
		if shown < n - 0.5:
			num = Color(C_LINE_ON.r, C_LINE_ON.g, C_LINE_ON.b, appear)
		elif shown > n + 0.5:
			num = Color(Style.RED.r, Style.RED.g, Style.RED.b, appear)
		var s := str(int(round(shown)))
		var w := font_b.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font_b, Vector2(br.end.x - 16 - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, num)
		if last_unload.has(r_key):
			var plus := "+%d" % int(last_unload[r_key])
			var pw := font.get_string_size(plus, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			_text(Vector2(br.end.x - 16 - w - 10 - pw, y), plus, 11, Color(C_LINE_ON.r, C_LINE_ON.g, C_LINE_ON.b, 0.75 * appear))
		y += 20.0
		row += 1
	if not any:
		_text(br.position + Vector2(16, 58), "Pusto. Czas na pierwszy lot!", 13, Color(0.7, 0.6, 0.8))
	_draw_launch()
	draw_set_transform(Vector2.ZERO)


func _draw_launch() -> void:
	var r := _launch_rect()
	var pulse := 0.93 + 0.07 * sin(time * 4.0)
	var c := Style.GOLD if hover_launch else Color(Style.GOLD.r * pulse, Style.GOLD.g * pulse, Style.GOLD.b * pulse)
	_hud_panel(self, r, c, Color(0.2, 0.13, 0.02, 0.98) if hover_launch else Color(0.09, 0.055, 0.01, 0.97), 14.0)
	# odblask przesuwający się po przycisku
	var sx := fmod(time * 0.45, 1.3) / 1.3 * (r.size.x + 120.0) - 60.0
	var xa := clampf(r.position.x + sx, r.position.x + 12.0, r.end.x - 12.0)
	var xb := clampf(r.position.x + sx + 44.0, r.position.x + 12.0, r.end.x - 12.0)
	if xb - xa > 2.0:
		var xc := clampf(xa + 24.0, xa, r.end.x - 12.0)
		var xd := clampf(xb + 24.0, xb, r.end.x - 12.0)
		draw_colored_polygon(PackedVector2Array([Vector2(xc, r.position.y + 4), Vector2(xd, r.position.y + 4), Vector2(xb, r.end.y - 4), Vector2(xa, r.end.y - 4)]), Color(1.0, 0.9, 0.6, 0.07))
	var s := "WYLOT"
	var w := font_b.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var cy := r.position.y + r.size.y * 0.5
	draw_string(font_b, Vector2(r.get_center().x - w * 0.5, cy + 9), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, c)
	# szewrony pędzące na zewnątrz od napisu
	for side in [-1.0, 1.0]:
		for k in 3:
			var phase := fmod(time * 1.6 - k * 0.33 + 3.0, 1.0)
			var px: float = r.get_center().x + side * (w * 0.5 + 16.0 + k * 13.0)
			var a := 0.2 + 0.8 * phase
			draw_polyline(PackedVector2Array([Vector2(px - side * 5.0, cy - 9), Vector2(px + side * 3.0, cy), Vector2(px - side * 5.0, cy + 9)]), Color(c.r, c.g, c.b, a), 2.0, true)


# ---------------- nakładki: parametry, rozkazy, otwarcie ----------------

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


func _draw_overlay(cv: CanvasItem) -> void:
	if overlay_k <= 0.0 or overlay_shown == "":
		return
	var k := _ease(overlay_k)
	var r := _overlay_rect(overlay_shown)
	r.position.x -= (1.0 - k) * (r.size.x + 40.0)
	if overlay_shown == "stats":
		_draw_stats(cv, r)
	else:
		_draw_brief(cv, r)


func _draw_stats(cv: CanvasItem, r: Rect2) -> void:
	_hud_panel(cv, r, Style.CYAN, Color(0.01, 0.02, 0.06, 0.985), 14.0)
	cv.draw_string(font_b, r.position + Vector2(16, 28), "PARAMETRY STATKU", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Style.CYAN)
	var hov_effects: Dictionary = hovered.get("effects", {}) if not hovered.is_empty() else {}
	var can_show_delta := not hovered.is_empty() and GameState.get_level(hovered.get("id", "")) < int(hovered.get("max", 0))
	var y := r.position.y + 42.0
	var idx := 0
	for g in STAT_GROUPS:
		var gc: Color = g[1]
		y += 18.0
		var ga := clampf(overlay_t * 14.0 - idx * 0.3, 0.0, 1.0)
		cv.draw_string(font_b, Vector2(r.position.x + 16, y), g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(gc.r, gc.g, gc.b, ga))
		cv.draw_line(Vector2(r.position.x + 100, y - 4), Vector2(r.end.x - 16, y - 4), Color(gc.r, gc.g, gc.b, 0.3 * ga), 1.0)
		y += 8.0
		for key in g[2]:
			idx += 1
			var a := clampf(overlay_t * 14.0 - idx * 0.3, 0.0, 1.0)
			y += 18.0
			var v := GameState.stat(key)
			var hl: bool = hov_effects.has(key) and can_show_delta
			var ox := (1.0 - a) * 16.0
			var name_c := Color(1.0, 0.77, 0.23, a) if hl else Color(0.85, 0.75, 0.95, a)
			cv.draw_string(font, Vector2(r.position.x + 16 + ox, y - 8), String(GameState.STAT_NAMES[key]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, name_c)
			var vs_str := GameState.format_stat(key, v)
			if hl:
				vs_str += "  →  " + GameState.format_stat(key, v + GameState.gain(hovered, key))
			var w := font.get_string_size(vs_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			cv.draw_string(font, Vector2(r.end.x - 16 - w, y - 8), vs_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.77, 0.23, a) if hl else Color(1, 1, 1, a))


const QUEST_ROW := 58.0


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


func _draw_brief(cv: CanvasItem, r: Rect2) -> void:
	claim_hits.clear()
	_hud_panel(cv, r, Style.PINK, Color(0.05, 0.0, 0.05, 0.985), 14.0)
	_draw_emblem(cv, r.position + Vector2(32, 34), 13.0)
	cv.draw_string(font_b, r.position + Vector2(60, 40), "ROZKAZY Z IMPERIUM VEX", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Style.PINK)
	# licznik pokazuje tylko punkty, które już doleciały; podskakuje przy każdym trafieniu
	var pl := "%d PL" % (int(GameState.bank.get("loyalty", 0)) - pl_pending)
	var fs := 14 + int(round(pl_pop * 5.0))
	var plw := font_b.get_string_size(pl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var lc: Color = GameState.RES_COLORS["loyalty"]
	pl_target = Vector2(r.end.x - 18 - plw * 0.5, r.position.y + 34)
	if pl_pop > 0.0:
		cv.draw_circle(pl_target, 14.0 + pl_pop * 10.0, Color(lc.r, lc.g, lc.b, 0.18 * pl_pop))
	cv.draw_string(font_b, Vector2(r.end.x - 18 - plw, r.position.y + 40), pl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lc.lerp(Color(1.3, 1.3, 1.3), pl_pop * 0.6))
	cv.draw_line(r.position + Vector2(16, 60), Vector2(r.end.x - 16, r.position.y + 60), Color(1.0, 0.35, 0.8, 0.35), 1.0)
	var items := _brief_items()
	var top := r.position.y + 72.0
	var bottom := r.end.y - 18.0
	# ile wierszy od końca mieści się w oknie - dalej nie ma sensu przewijać
	var fit := 0.0
	var max_scroll := items.size()
	for k in range(items.size() - 1, -1, -1):
		fit += float(items[k][1])
		if fit > bottom - top + 6.0:
			break
		max_scroll = k
	brief_scroll = clampi(brief_scroll, 0, max_scroll)
	var done_n := 0
	for it in items:
		if not it[0].is_empty() and GameState.quests.get(it[0]["id"], "") == "done":
			done_n += 1
	var y := top
	var idx := 0
	var last := brief_scroll - 1
	for k in range(brief_scroll, items.size()):
		var q: Dictionary = items[k][0]
		var h: float = items[k][1]
		if y + h > bottom + 6.0:
			break
		if q.is_empty():
			cv.draw_string(font_b, Vector2(r.position.x + 18, y + 16), "WYKONANE: %d" % done_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Style.TEXT_DIM)
		else:
			_draw_quest(cv, Rect2(r.position.x + 12, y, r.size.x - 24, QUEST_ROW - 6), q, idx)
		y += h
		idx += 1
		last = k
	if max_scroll <= 0:
		return
	# pasek przewijania z prawej i podpowiedź, że niżej jest więcej
	var track := Rect2(r.end.x - 7, top, 3, bottom - top)
	cv.draw_rect(track, Color(1.0, 0.35, 0.8, 0.15))
	var vis := float(last - brief_scroll + 1) / float(items.size())
	var th := maxf(18.0, track.size.y * vis)
	var ty := track.position.y + (track.size.y - th) * float(brief_scroll) / float(max_scroll)
	cv.draw_rect(Rect2(track.position.x, ty, track.size.x, th), Color(1.0, 0.35, 0.8, 0.7))
	if last < items.size() - 1:
		var more := "▼ przewiń w dół (%d)" % (items.size() - 1 - last)
		var mw := font.get_string_size(more, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		cv.draw_string(font, Vector2(r.get_center().x - mw * 0.5, r.end.y - 7), more, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.6, 0.9, 0.55 + 0.3 * sin(time * 4.0)))


func _draw_quest(cv: CanvasItem, r: Rect2, q: Dictionary, idx: int) -> void:
	var state: String = GameState.quests.get(q["id"], "")
	var done := state == "done"
	var ready := state == "ready"
	var a := clampf(overlay_t * 8.0 - idx * 0.35, 0.0, 1.0)
	r.position.x += (1.0 - a) * 20.0
	var pulse := 0.5 + 0.5 * sin(time * 5.0)
	var c: Color = Style.TEXT_DIM if done else (Style.GOLD if ready else Style.PINK)
	var pts := _chamfer(r, 7.0)
	cv.draw_colored_polygon(pts, Color(0.08, 0.05, 0.0, 0.92 * a) if ready else Color(0.03, 0.0, 0.06, 0.9 * a))
	var closed := pts.duplicate()
	closed.append(pts[0])
	cv.draw_polyline(closed, Color(c.r, c.g, c.b, (0.6 + 0.4 * pulse if ready else 0.6) * a), 1.6 if ready else 1.2, true)
	var title: String = String(q["title"]).to_upper()
	cv.draw_string(font_b, r.position + Vector2(12, 19), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.7, 0.8, a) if done else Color(1.3, 1.0, 0.45, a))
	var lc: Color = GameState.RES_COLORS["loyalty"]
	if ready:
		# przycisk odbioru nagrody
		var br := Rect2(r.end.x - 132, r.position.y + 12, 120, 28)
		claim_hits.append([br, q["id"]])
		var hov := br.has_point(mouse_pos)
		var bp := _chamfer(br, 6.0)
		cv.draw_colored_polygon(bp, Color(lc.r * 0.35, lc.g * 0.35, lc.b * 0.35, a) if hov else Color(lc.r * 0.15, lc.g * 0.15, lc.b * 0.18, a))
		bp.append(bp[0])
		cv.draw_polyline(bp, Color(lc.r, lc.g, lc.b, (0.7 + 0.3 * pulse) * a), 1.6, true)
		var bt := "ODBIERZ +%d" % int(q["reward"])
		var btw := font_b.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		cv.draw_string(font_b, Vector2(br.get_center().x - btw * 0.5, br.position.y + 19), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.2, 1.2, 1.3, a) if hov else Color(lc.r, lc.g, lc.b, a))
		cv.draw_string(font, r.position + Vector2(12, 38), "WYKONANO - ODBIERZ NAGRODĘ", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 1.0, 0.55, a))
		return
	var rw := "+%d PL" % int(q["reward"])
	var rww := font_b.get_string_size(rw, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	cv.draw_string(font_b, Vector2(r.end.x - 12 - rww, r.position.y + 19), rw, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(lc.r, lc.g, lc.b, a * (0.5 if done else 1.0)))
	if done:
		cv.draw_string(font, r.position + Vector2(12, 38), "ODEBRANO", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.7, 0.7 * a))
		return
	cv.draw_string(font, r.position + Vector2(12, 36), String(q["desc"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24, 11, Color(0.85, 0.78, 0.95, a))
	var pr: Array = GameState.quest_progress(q)
	if int(pr[1]) > 1:
		var bar := Rect2(r.position.x + 12, r.end.y - 9, r.size.x - 110, 4)
		cv.draw_rect(bar, Color(0.25, 0.1, 0.25, a))
		cv.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(pr[0]) / float(pr[1]), bar.size.y)), Color(c.r, c.g, c.b, a))
		var pt := "%d/%d" % [pr[0], pr[1]]
		cv.draw_string(font, Vector2(r.end.x - 12 - font.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, r.end.y - 5), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.8 * a))


## Odbiór nagrody: punkty wylatują z przycisku i jeden po drugim wpadają do licznika.
func _claim(id: String, from: Vector2) -> void:
	var reward: int = GameState.claim_quest(id)
	if reward <= 0:
		return
	Audio.play("buy", 0.0)
	var n := clampi(reward, 1, 20)
	var each := reward / n
	var rest := reward - each * n
	pl_pending += reward
	for k in n:
		var amount := each + (1 if k < rest else 0)
		var side := Vector2(randf_range(-60, 60), randf_range(-90, -20))
		pl_fx.append({"from": from + Vector2(randf_range(-30, 30), randf_range(-6, 6)), "ctrl": from + side, "t": -k * 0.05, "amount": amount})


func _update_pl_fx(delta: float) -> void:
	pl_pop = maxf(0.0, pl_pop - delta * 4.0)
	var k := pl_fx.size() - 1
	while k >= 0:
		var p: Dictionary = pl_fx[k]
		p["t"] += delta * 1.6
		if p["t"] >= 1.0:
			pl_pending -= int(p["amount"])
			pl_pop = 1.0
			Audio.play("pickup", 0.05, -4.0)
			pl_fx.remove_at(k)
		k -= 1


func _draw_pl_fx(cv: CanvasItem) -> void:
	var lc: Color = GameState.RES_COLORS["loyalty"]
	for p in pl_fx:
		var t: float = clampf(p["t"], 0.0, 1.0)
		if p["t"] < 0.0:
			continue
		var e := t * t
		var a: Vector2 = p["from"]
		var b: Vector2 = p["ctrl"]
		var pos := a.lerp(b, e).lerp(b.lerp(pl_target, e), e)
		var prev := a.lerp(b, maxf(0.0, e - 0.08)).lerp(b.lerp(pl_target, maxf(0.0, e - 0.08)), maxf(0.0, e - 0.08))
		cv.draw_line(prev, pos, Color(lc.r, lc.g, lc.b, 0.5), 3.0, true)
		var s := 5.0 - 2.0 * t
		cv.draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -s), pos + Vector2(s, 0), pos + Vector2(0, s), pos + Vector2(-s, 0)]), Color(lc.r * 1.2, lc.g * 1.2, lc.b * 1.2))


## Plakietka "ROZKAZ WYKONANY" nad siatką; kolejne czekają w kolejce.
func toast(title: String, reward: int) -> void:
	toasts.append({"title": title, "reward": reward, "t": 0.0})


func _draw_toast(cv: CanvasItem) -> void:
	if toasts.is_empty():
		return
	var tt: Dictionary = toasts[0]
	var t: float = tt["t"]
	var k := _ease(t / 0.3) * (1.0 - _ease((t - 3.2) / 0.3))
	var ga := _grid_area()
	var line1: String = tt.get("line1", "+%d PL DO ODEBRANIA W ROZKAZACH" % int(tt.get("reward", 0)))
	var line2: String = tt.get("line2", "%s - WYKONANO!" % String(tt.get("title", "")).to_upper())
	var w := maxf(font_b.get_string_size(line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, 300.0) + 60.0
	var r := Rect2(ga.get_center().x - w * 0.5, ga.position.y + 56.0 - (1.0 - k) * 30.0, w, 62)
	cv.draw_colored_polygon(_chamfer(r, 10.0), Color(0.05, 0.03, 0.0, 0.95 * k))
	var pts := _chamfer(r, 10.0)
	pts.append(pts[0])
	cv.draw_polyline(pts, Color(Style.GOLD.r, Style.GOLD.g, Style.GOLD.b, k), 2.0, true)
	var w1 := font_b.get_string_size(line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var w2 := font_b.get_string_size(line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	cv.draw_string(font_b, Vector2(r.get_center().x - w2 * 0.5, r.position.y + 26), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.3, 1.0, 0.45, k))
	cv.draw_string(font_b, Vector2(r.get_center().x - w1 * 0.5, r.position.y + 48), line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(Style.PINK.r, Style.PINK.g, Style.PINK.b, k))

## Przejście przy zmianie zakładki: linia skanera ciągnie za sobą ciemną kurtynę.
func _draw_tab_wipe(cv: CanvasItem) -> void:
	if tab_t >= 1.0:
		return
	var ga := _grid_area()
	var top := ga.position.y + 44.0
	var h := ga.end.y - top - 2.0
	var x := ga.position.x + 2.0 + (ga.size.x - 4.0) * _ease(tab_t)
	cv.draw_rect(Rect2(x, top, ga.end.x - 2.0 - x, h), Color(0.01, 0.0, 0.025, 0.96))
	cv.draw_line(Vector2(x, top), Vector2(x, top + h), Color(0.4, 1.1, 1.3, 1.0 - tab_t * 0.6), 3.0)
	cv.draw_rect(Rect2(x - 26.0, top, 26.0, h), Color(0.3, 0.9, 1.0, 0.09 * (1.0 - tab_t)))


## Otwarcie po dokowaniu: dwie grodzie rozsuwają się na boki.
func _draw_iris(cv: CanvasItem, vs: Vector2) -> void:
	if open_t >= OPEN_LEN:
		return
	var k := _ease((open_t - 0.28) / 0.6)
	var half := vs.x * 0.5 * (1.0 - k)
	if half > 0.5:
		cv.draw_rect(Rect2(0, 0, half, vs.y), Style.BG)
		cv.draw_rect(Rect2(vs.x - half, 0, half, vs.y), Style.BG)
		for i in 7:
			var yy := vs.y * (i + 0.5) / 7.0
			cv.draw_line(Vector2(maxf(0.0, half - 150.0), yy), Vector2(half - 10.0, yy), Color(1.0, 0.3, 0.8, 0.22), 2.0)
			cv.draw_line(Vector2(vs.x - half + 10.0, yy), Vector2(minf(vs.x, vs.x - half + 150.0), yy), Color(1.0, 0.3, 0.8, 0.22), 2.0)
		cv.draw_line(Vector2(half, 0), Vector2(half, vs.y), Color(1.3, 0.3, 1.1), 3.0)
		cv.draw_line(Vector2(vs.x - half, 0), Vector2(vs.x - half, vs.y), Color(0.3, 1.1, 1.3), 3.0)
	var a := 1.0 - clampf((open_t - 0.28) / 0.25, 0.0, 1.0)
	if a > 0.0:
		_draw_emblem(cv, vs * 0.5, 54.0 + open_t * 30.0, a)
		var label := "DOKOWANIE"
		var w := pf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		cv.draw_string(pf, vs * 0.5 + Vector2(-w * 0.5, 110), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.4, 1.0, 1.2, a))
