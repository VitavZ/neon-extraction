extends Control
## HUD w locie (styl Agrivore + synthwave):
## lewa kolumna: emblemat, kadłub/tarcza, liczniki surowców w ramkach (z "pyknięciem" przy zbiorze),
## dół: długi pasek paliwa z błyskawicą, sloty narzędzi, przycisk dokowania;
## prawa strona: minimapa, statystyki, stan broni. Komunikaty na środku u góry.

const Style = preload("res://scripts/style.gd")
const Sectors = preload("res://scripts/sectors.gd")

var ship: Node2D
var world: Node2D
var mothership: Node2D
var weapons: Node2D
var wingmen: Node2D
var transit: Node2D
var font: Font
var font_b: Font
var messages: Array = []   # {text, life, color}
var time := 0.0
var last_counts: Dictionary = {}
var pops: Dictionary = {}   # zasób -> czas "pyknięcia" licznika
var show_fps := false
var view_sector := -1            # sektor na minimapie (zmienia się dopiero kawałek za granicą)
var view_origin := Vector2.ZERO  # lewy górny róg minimapy w kafelkach, płynnie dąży do sektora
var banner_t := -1.0             # czas od wejścia do sektora (< 0 = brak baneru)
var banner_dir := Vector2.ZERO   # kierunek przelotu (do fali na ekranie)
var big_t := -1.0                # duży napis na środku (zniszczenie miasta)
var big_title := ""
var big_sub := ""
var left_bottom := 0.0            # dół paneli po lewej i prawej (strzałki je omijają)
var right_bottom := 0.0
var speed_k := 0.0                # efekty pędu (0 = wolno, 1 = pełna prędkość i więcej)
var speed_lines: Array = []       # {p, dir, v, len, life, max} - linie pędu w przestrzeni ekranu
var track_a := 0.0                # widoczność znacznika "namierzony" (0..1)
var track_n := 0                  # ilu myśliwców ściga gracza
var track_hint := ""              # podpowiedź, jak zgubić pościg
var mine_idx := -1                # kafelek pod laserem (podgląd łupu)
var mine_a := 0.0
const BANNER_TIME := 3.4
const BIG_TIME := 5.0
const SECTOR_MARGIN := 2         # tyle kafelków za granicą minimapa zmienia sektor


func _ready() -> void:
	font = Style.font()
	font_b = Style.font_bold()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	if GameState.key_hit(event, "fps"):
		show_fps = not show_fps


## Ten sam komunikat nie piętrzy się na ekranie: odświeża się i dostaje licznik (x3).
func message(text: String, c := Color(0.83, 0.67, 1.0)) -> void:
	var up := text.to_upper()
	for m in messages:
		if m["base"] == up:
			m["n"] += 1
			m["text"] = "%s  x%d" % [up, m["n"]]
			m["life"] = 3.5
			return
	messages.push_front({"text": up, "base": up, "n": 1, "life": 3.5, "color": c})
	if messages.size() > 4:
		messages.resize(4)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	time += delta
	_update_sector_view(delta)
	_update_speed_fx(delta)
	_update_tracking(delta)
	# podgląd łupu: trzyma się chwilę po przerwie w strzelaniu, żeby nie migał
	if world.target_idx >= 0 and not ship.docked:
		mine_idx = world.target_idx
		mine_a = move_toward(mine_a, 1.0, delta * 8.0)
	else:
		mine_a = move_toward(mine_a, 0.0, delta * 2.5)
	for m in messages:
		m["life"] -= delta
	messages = messages.filter(func(m): return m["life"] > 0.0)
	# "pyknięcie" licznika przy przyroście
	var all := GameState.cargo.duplicate()
	for k in GameState.bio_cargo:
		all[k] = GameState.bio_cargo[k]
	for k in all:
		if int(all[k]) > int(last_counts.get(k, 0)):
			pops[k] = 0.25
	last_counts = all
	for k in pops.keys():
		pops[k] -= delta
		if pops[k] <= 0.0:
			pops.erase(k)
	queue_redraw()


## Linie pędu: przy dużej prędkości przy krawędziach ekranu przelatują smugi wzdłuż kierunku lotu.
func _update_speed_fx(delta: float) -> void:
	var active: bool = not ship.docked and not ship.dead
	var sf: float = ship.vel.length() / maxf(1.0, GameState.stat("max_speed")) if active else 0.0
	speed_k = move_toward(speed_k, clampf((sf - 0.7) / 0.6, 0.0, 1.1), delta * 2.5)
	for l in speed_lines:
		l["life"] -= delta
		l["p"] -= l["dir"] * l["v"] * delta
	if not speed_lines.is_empty():
		speed_lines = speed_lines.filter(func(l): return l["life"] > 0.0)
	if speed_k <= 0.05 or ship.vel.length() < 1.0:
		return
	var vs := get_viewport_rect().size
	var c := vs * 0.5
	var dir: Vector2 = ship.vel.normalized()
	var n := int(speed_k * 60.0 * delta + randf())
	for k in n:
		if speed_lines.size() >= 40:
			break
		# na obrzeżach ekranu, środek (statek) zostaje czysty
		var a := randf() * TAU
		var rr := randf_range(0.5, 1.15)
		var p := c + Vector2(cos(a) * vs.x * 0.5, sin(a) * vs.y * 0.5) * rr
		var life := randf_range(0.18, 0.32)
		speed_lines.append({"p": p, "dir": dir, "v": randf_range(1800.0, 3000.0) * (0.6 + 0.4 * speed_k),
			"len": randf_range(50.0, 130.0) * speed_k, "life": life, "max": life})


func _draw_speed_fx(vs: Vector2) -> void:
	if speed_k <= 0.02:
		return
	# winieta: krawędzie ekranu ciemnieją, wzrok idzie do środka
	var k := minf(speed_k, 1.0)
	var w := minf(vs.x, vs.y) * 0.22
	var outer := Color(0.0, 0.0, 0.03, 0.28 * k)
	var inner := Color(0.0, 0.0, 0.03, 0.0)
	var r := Rect2(Vector2.ZERO, vs)
	var ri := r.grow(-w)
	var bands := [
		[r.position, Vector2(r.end.x, r.position.y), Vector2(ri.end.x, ri.position.y), ri.position],
		[Vector2(r.end.x, r.position.y), r.end, ri.end, Vector2(ri.end.x, ri.position.y)],
		[r.end, Vector2(r.position.x, r.end.y), Vector2(ri.position.x, ri.end.y), ri.end],
		[Vector2(r.position.x, r.end.y), r.position, ri.position, Vector2(ri.position.x, ri.end.y)],
	]
	for b in bands:
		draw_polygon(PackedVector2Array(b), PackedColorArray([outer, outer, inner, inner]))
	for l in speed_lines:
		var f: float = l["life"] / l["max"]
		var fa := sin(f * PI)
		var p: Vector2 = l["p"]
		var tail: Vector2 = p + l["dir"] * l["len"]
		draw_line(p, tail, Color(0.55, 0.85, 1.0, 0.08 * fa * k), 3.0)
		draw_line(p, tail, Color(0.85, 0.95, 1.0, 0.28 * fa * k), 1.2)


## Duży napis na środku ekranu.
func show_big(title: String, sub: String) -> void:
	big_t = 0.0
	big_title = title
	big_sub = sub


func _draw_big(vs: Vector2) -> void:
	if big_t < 0.0:
		return
	var pf: Font = Style.font_pixel()
	var fade := minf(clampf(big_t / 0.3, 0.0, 1.0), clampf((BIG_TIME - big_t) / 0.8, 0.0, 1.0))
	var pop := 1.0 + (1.0 - clampf(big_t / 0.25, 0.0, 1.0)) * 0.5
	var fsize := 56
	var w := pf.get_string_size(big_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var c := vs * Vector2(0.5, 0.42)
	draw_set_transform(c, 0.0, Vector2(pop, pop))
	draw_string_outline(pf, Vector2(-w * 0.5, 0.0), big_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 10, Color(0, 0, 0, 0.9 * fade))
	draw_string(pf, Vector2(-w * 0.5, 0.0), big_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1.3, 0.35, 1.0, fade))
	draw_set_transform(Vector2.ZERO)
	var sw := pf.get_string_size(big_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var sp := Vector2(c.x - sw * 0.5, c.y + 42.0).round()
	draw_string_outline(pf, sp, big_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 6, Color(0, 0, 0, 0.9 * fade))
	draw_string(pf, sp, big_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.8, 0.3, fade))


## Strzałka przy krawędzi ekranu do punktu poza widokiem.
func _edge_arrow(world_pos: Vector2, label: String, col: Color, vs: Vector2) -> void:
	var p: Vector2 = get_viewport().get_canvas_transform() * world_pos
	if Rect2(Vector2.ZERO, vs).grow(-60).has_point(p):
		return
	var center := vs * 0.5
	var d := p - center
	var tt := minf(absf((vs.x * 0.5 - 70) / maxf(absf(d.x), 0.001)), absf((vs.y * 0.5 - 70) / maxf(absf(d.y), 0.001)))
	var ep := center + d * tt
	# strzałka omija panele po bokach
	if ep.y < left_bottom + 20.0 and ep.x < 340.0:
		ep.x = 340.0
	elif ep.y < right_bottom + 20.0 and ep.x > vs.x - 300.0:
		ep.x = vs.x - 300.0
	# nad dolnym paskiem paliwa i slotami narzędzi
	ep.y = minf(ep.y, vs.y - 120.0)
	var dir := d.normalized()
	draw_colored_polygon(PackedVector2Array([ep + dir * 20, ep + dir.rotated(2.5) * 16, ep + dir.rotated(-2.5) * 16]), Color(0, 0, 0, 0.7 * col.a))
	draw_colored_polygon(PackedVector2Array([ep + dir * 16, ep + dir.rotated(2.5) * 12, ep + dir.rotated(-2.5) * 12]), col)
	var lbl := "%s %dm" % [label, int(ship.global_position.distance_to(world_pos) / 10.0)]
	var lw := _tw(lbl, 12, true)
	var lp := ep - dir * 28 + Vector2(-lw * 0.5, 5)
	# podpis też nie wchodzi na panele po bokach
	if lp.y < right_bottom + 20.0:
		lp.x = minf(lp.x, vs.x - 330.0 - lw)
	if lp.y < left_bottom + 20.0:
		lp.x = maxf(lp.x, 370.0)
	lp.x = clampf(lp.x, 8.0, vs.x - 8.0 - lw)
	draw_string_outline(font_b, lp, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.8 * col.a))
	_t(lp, lbl, 12, col, true)


## Śledzi sektor statku. Margines chroni przed miganiem przy locie wzdłuż granicy.
func _update_sector_view(delta: float) -> void:
	if big_t >= 0.0:
		big_t += delta
		if big_t > BIG_TIME:
			big_t = -1.0
	if banner_t >= 0.0:
		banner_t += delta
		if banner_t > BANNER_TIME:
			banner_t = -1.0
	var cur: int = world.sector_at_pos(ship.global_position)
	if ship.docked or view_sector < 0:
		view_sector = cur
		view_origin = Vector2(Sectors.sector_rect(cur).position)
		banner_t = -1.0
		return
	if cur != view_sector:
		var cell := Vector2i(ship.global_position / float(world.T))
		if Sectors.sector_rect(cur).grow(-SECTOR_MARGIN).has_point(cell):
			var a: Rect2i = Sectors.sector_rect(view_sector)
			var b: Rect2i = Sectors.sector_rect(cur)
			banner_dir = Vector2(b.position - a.position).normalized()
			view_sector = cur
			banner_t = 0.0
			Audio.play("popup", 0.0)
	var target := Vector2(Sectors.sector_rect(view_sector).position)
	view_origin = view_origin.lerp(target, 1.0 - exp(-5.0 * delta))
	if view_origin.distance_to(target) < 0.05:
		view_origin = target


## Wejście do sektora: fala przelatująca przez ekran i napis z nazwą regionu.
func _draw_sector_banner(vs: Vector2) -> void:
	if banner_t < 0.0:
		return
	# fala w kierunku lotu
	var sweep := banner_t / 0.7
	if sweep < 1.0:
		var e := 1.0 - pow(1.0 - sweep, 2.0)
		var a := (1.0 - sweep) * 0.5
		var c := Color(0.35, 0.9, 1.0)
		var len_x := vs.x + 300.0
		var len_y := vs.y + 300.0
		if absf(banner_dir.x) > 0.5:
			var x := (e * len_x - 150.0) if banner_dir.x > 0.0 else (vs.x + 150.0 - e * len_x)
			var w := 140.0 * signf(banner_dir.x)
			draw_rect(Rect2(minf(x, x - w), 0.0, absf(w), vs.y), Color(c.r, c.g, c.b, a * 0.25))
			draw_line(Vector2(x, 0.0), Vector2(x, vs.y), Color(c.r, c.g, c.b, a), 3.0)
		else:
			var y := (e * len_y - 150.0) if banner_dir.y > 0.0 else (vs.y + 150.0 - e * len_y)
			var h := 140.0 * signf(banner_dir.y)
			draw_rect(Rect2(0.0, minf(y, y - h), vs.x, absf(h)), Color(c.r, c.g, c.b, a * 0.25))
			draw_line(Vector2(0.0, y), Vector2(vs.x, y), Color(c.r, c.g, c.b, a), 3.0)
	# napis
	var fade := minf(clampf(banner_t / 0.35, 0.0, 1.0), clampf((BANNER_TIME - banner_t) / 0.7, 0.0, 1.0))
	var open := 1.0 - pow(1.0 - clampf(banner_t / 0.5, 0.0, 1.0), 3.0)
	var pf: Font = Style.font_pixel()
	var info: Dictionary = Sectors.LIST[view_sector]
	var name_txt: String = info["name"]
	var city_txt: String = ("METROPOLIA: " + GameState.city_name(view_sector)) if Sectors.has_city(view_sector) else Sectors.label(view_sector)
	var cx := vs.x * 0.5
	var y0 := vs.y * 0.24 + (1.0 - open) * 14.0
	var half := maxf(pf.get_string_size(name_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x * 0.5 + 40.0, 200.0) * open
	draw_rect(Rect2(cx - half, y0 - 52.0, half * 2.0, 102.0), Color(0.0, 0.0, 0.03, 0.62 * fade))
	var lc := Color(0.35, 0.9, 1.0, fade)
	draw_line(Vector2(cx - half, y0 - 52.0), Vector2(cx + half, y0 - 52.0), lc, 2.0)
	draw_line(Vector2(cx - half, y0 + 50.0), Vector2(cx + half, y0 + 50.0), lc, 2.0)
	var head := "SEKTOR"
	draw_string(pf, Vector2(cx - pf.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x * 0.5, y0 - 30.0).round(), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.35, 0.9, 1.0, 0.9 * fade))
	draw_string(pf, Vector2(cx - pf.get_string_size(name_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x * 0.5, y0 + 12.0).round(), name_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1.0, 0.6, 0.95, fade))
	draw_string(pf, Vector2(cx - pf.get_string_size(city_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x * 0.5, y0 + 38.0).round(), city_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.8, 0.3, fade))


## Czerwone znaczniki wokół statku wskazują nadlatujące rakiety (też te spoza ekranu).
func _draw_missile_warnings() -> void:
	if world.missiles.is_empty() or ship.docked or ship.dead:
		return
	var sp: Vector2 = get_viewport().get_canvas_transform() * ship.global_position
	var blink := 0.55 + 0.45 * sin(time * 16.0)
	for m in world.missiles:
		var dir: Vector2 = (m["pos"] - ship.global_position).normalized()
		var p := sp + dir * 62.0
		var tri := PackedVector2Array([p + dir * 15.0, p + dir.rotated(2.4) * 11.0, p + dir.rotated(-2.4) * 11.0])
		draw_colored_polygon(tri, Color(1.4, 0.1, 0.1, blink))
	var txt := "RAKIETY: %d" % world.missiles.size()
	var tw := _tw(txt, 16, true)
	draw_string_outline(font_b, Vector2(sp.x - tw * 0.5, sp.y - 74.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.9))
	_t(Vector2(sp.x - tw * 0.5, sp.y - 74.0), txt, 16, Color(1.0, 0.2, 0.2, 0.5 + 0.5 * blink), true)


## Myśliwce, które cię ścigają, a są poza ekranem: strzałki przy krawędzi jak do Statku Matki
## (z odległością do najbliższego). Myśliwce z tego samego kierunku łączą się w jedną strzałkę z licznikiem.
func _draw_enemy_markers(vs: Vector2) -> void:
	if ship.docked or ship.dead or weapons == null or weapons.enemies == null:
		return
	var ct := get_viewport().get_canvas_transform()
	var scr := Rect2(Vector2.ZERO, vs).grow(-60.0)
	var groups: Array = []   # {ang, dist, n, pos}
	for f in weapons.enemies.chasers():
		var sp: Vector2 = ct * f["pos"]
		if scr.has_point(sp):
			continue
		var ang := (sp - vs * 0.5).angle()
		var d: float = f["pos"].distance_to(ship.global_position)
		var merged := false
		for g in groups:
			if absf(angle_difference(g["ang"], ang)) < 0.22:
				g["n"] += 1
				if d < g["dist"]:
					g["dist"] = d
					g["pos"] = f["pos"]
				merged = true
				break
		if not merged:
			groups.append({"ang": ang, "dist": d, "n": 1, "pos": f["pos"]})
	var blink := 0.75 + 0.25 * sin(time * 9.0)
	for g in groups:
		var lbl: String = "MYŚLIWIEC" if g["n"] == 1 else "MYŚLIWCE x%d" % g["n"]
		_edge_arrow(g["pos"], lbl, Color(1.35, 0.22, 0.2, blink), vs)


## Panel ze ściętymi rogami, który razem z ramką płynnie znika (alfa z kolorów).
func _chamfer(r: Rect2, border: Color, fill: Color, cut: float) -> void:
	var pts := PackedVector2Array([r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - cut),
		r.end - Vector2(cut, 0), Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut)])
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, border, 1.6, true)


## Liczebnik: 1 myśliwiec, 2-4 myśliwce, 5+ myśliwców.
func _fighters_word(n: int) -> String:
	if n == 1:
		return "1 MYŚLIWIEC"
	if n % 10 >= 2 and n % 10 <= 4 and (n % 100 < 12 or n % 100 > 14):
		return "%d MYŚLIWCE" % n
	return "%d MYŚLIWCÓW" % n


## "Nadal cię ścigają": znacznik namierzenia u góry ekranu i czerwone obramowanie,
## dopóki choć jeden myśliwiec jest na tropie. Podpowiada, jak się ich pozbyć.
func _draw_tracking(vs: Vector2) -> void:
	if track_a <= 0.01:
		return
	var a := track_a
	var pulse := 0.5 + 0.5 * sin(time * 3.2)
	# obramowanie ekranu: miękka czerwona poświata przy krawędziach
	var full := Rect2(Vector2.ZERO, vs)
	for k in 4:
		var wk := 6.0 + k * 10.0
		draw_rect(full.grow(-wk * 0.5), Color(1.0, 0.05, 0.1, (0.07 - k * 0.015) * (0.6 + 0.4 * pulse) * a), false, wk)
	draw_rect(full.grow(-1.5), Color(1.3, 0.15, 0.2, (0.3 + 0.25 * pulse) * a), false, 3.0)
	# znacznik u góry
	var title := "NAMIERZONY"
	var sub := _fighters_word(track_n) + "  •  " + track_hint
	var w := maxf(_tw(title, 16, true), _tw(sub, 11, true)) + 66.0
	var r := Rect2(vs.x * 0.5 - w * 0.5, 30.0 + (24.0 if show_fps else 0.0), w, 40.0)
	var red := Color(1.35, 0.2, 0.22)
	_chamfer(r, Color(red.r, red.g, red.b, (0.6 + 0.4 * pulse) * a), Color(0.1, 0.0, 0.02, 0.9 * a), 8.0)
	# celownik: obracające się klamry wokół kropki
	var ic := Vector2(r.position.x + 24.0, r.get_center().y)
	var rot := time * 2.0
	for k in 4:
		var s := rot + k * TAU / 4.0
		draw_arc(ic, 11.0, s, s + 0.9, 8, Color(red.r, red.g, red.b, a), 2.0, true)
	draw_circle(ic, 3.0 + 1.5 * pulse, Color(1.5, 0.6, 0.6, a))
	var tc := Color(red.r, red.g, red.b, (0.75 + 0.25 * pulse) * a)
	_t(Vector2(r.position.x + 44.0, r.position.y + 18.0), title, 16, tc, true)
	_t(Vector2(r.position.x + 44.0, r.position.y + 33.0), sub, 11, Color(1.0, 0.8, 0.8, 0.9 * a), true)


## Stan pościgu (liczony co klatkę): ilu ściga, ile zostało do odpuszczenia, podpowiedź.
func _update_tracking(delta: float) -> void:
	var ch: Array = []
	if weapons and weapons.enemies and not ship.docked and not ship.dead:
		ch = weapons.enemies.chasers()
	if not ch.is_empty():
		track_n = ch.size()
		var stubborn := false
		var hunt := 0.0
		for f in ch:
			if f.has("hunt_t"):
				hunt = maxf(hunt, f["hunt_t"])
			else:
				stubborn = true
		if stubborn:
			track_hint = "ZESTRZEL ICH ALBO ZADOKUJ"
		elif hunt > 0.0:
			track_hint = "ODPUSZCZĄ ZA %d s" % int(ceil(hunt))
		else:
			track_hint = "ODLEĆ DALEJ, BY ICH ZGUBIĆ"
	track_a = move_toward(track_a, 1.0 if not ch.is_empty() else 0.0, delta * 3.0)


## Podgląd wydobywanego kafelka: nazwa terenu i co może z niego wypaść (z obecnymi mnożnikami).
func _draw_mine_info(vs: Vector2) -> void:
	if mine_a <= 0.01 or mine_idx < 0 or not world.is_minable(mine_idx) or ship.docked:
		return
	var a := mine_a
	var rows: Array = world.tile_drops_preview(mine_idx)
	var hidden: String = world.hidden_deposit_name(mine_idx)
	var title: String = world.tile_name(mine_idx).to_upper()
	var acc: Color
	if world.layer[mine_idx] == world.L_DEPOSIT:
		acc = world.DEP_DEFS[world.deposit[mine_idx]]["color"]
	else:
		acc = world.TILE_DEFS[world.surface[mine_idx]]["line"]
	var w := _tw(title, 13, true) + 24.0
	for row in rows:
		w = maxf(w, 30.0 + _tw(String(GameState.RES_NAMES[row[0]]), 12) + 18.0 + _tw(row[1], 12, true) + 12.0)
	var hid_txt := "POD SPODEM: " + hidden.to_upper()
	if hidden != "":
		w = maxf(w, _tw(hid_txt, 11, true) + 24.0)
	var h := 28.0 + rows.size() * 17.0 + (18.0 if hidden != "" else 0.0) + 4.0
	var ct := get_viewport().get_canvas_transform()
	var tp: Vector2 = ct * world.idx_center(mine_idx)
	var half: float = world.T * 0.5 * ct.get_scale().x
	var pos := Vector2(tp.x - w * 0.5, tp.y - half - 16.0 - h)
	var below := pos.y < 74.0
	if below:
		pos.y = tp.y + half + 16.0
	pos.x = clampf(pos.x, 12.0, vs.x - 12.0 - w)
	var r := Rect2(pos.round(), Vector2(w, h))
	# łącznik do kafelka
	var anchor := Vector2(clampf(tp.x, r.position.x + 10.0, r.end.x - 10.0), r.position.y if below else r.end.y)
	draw_line(anchor, tp + Vector2(0, -half if not below else half), Color(acc.r, acc.g, acc.b, 0.6 * a), 1.5, true)
	_chamfer(r, Color(acc.r, acc.g, acc.b, 0.85 * a), Color(0.02, 0.0, 0.05, 0.9 * a), 6.0)
	_t(r.position + Vector2(12, 19), title, 13, Color(acc.r, acc.g, acc.b, a).lerp(Color(1, 1, 1, a), 0.25), true)
	draw_line(r.position + Vector2(10, 26), Vector2(r.end.x - 10, r.position.y + 26), Color(acc.r, acc.g, acc.b, 0.3 * a), 1.0)
	var y := r.position.y + 42.0
	for row in rows:
		var c: Color = GameState.RES_COLORS[row[0]]
		var ic := Vector2(r.position.x + 17.0, y - 4.0)
		draw_colored_polygon(PackedVector2Array([ic + Vector2(0, -5), ic + Vector2(5, 0), ic + Vector2(0, 5), ic + Vector2(-5, 0)]), Color(c.r, c.g, c.b, a))
		_t(Vector2(r.position.x + 30.0, y), String(GameState.RES_NAMES[row[0]]), 12, Color(c.r, c.g, c.b, a).lerp(Color(1, 1, 1, a), 0.25))
		var amt: String = row[1]
		_t(Vector2(r.end.x - 12.0 - _tw(amt, 12, true), y), amt, 12, Color(1, 1, 1, a), true)
		y += 17.0
	if hidden != "":
		_t(Vector2(r.position.x + 12.0, y + 1.0), hid_txt, 11, Color(0.85, 0.5, 1.3, (0.7 + 0.3 * sin(time * 5.0)) * a), true)


func _t(p: Vector2, s: String, fsize: int, c: Color, bold := false) -> void:
	draw_string(font_b if bold else font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, c)


func _tw(s: String, fsize: int, bold := false) -> float:
	return (font_b if bold else font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x


func _mini_bar(r: Rect2, frac: float, c: Color) -> void:
	draw_rect(r, Color(0.0, 0.0, 0.0, 0.85))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), c)
	draw_rect(r, Color(c.r, c.g, c.b, 0.5), false, 1.0)


func _emblem(r: Rect2) -> void:
	# emblemat Imperium Vex: oko w trójkącie + korona (wektor, synthwave)
	Style.chamfer_panel(self, r, Style.PINK)
	var c := r.get_center() + Vector2(0, 4)
	var tri := PackedVector2Array([c + Vector2(0, -20), c + Vector2(22, 16), c + Vector2(-22, 16), c + Vector2(0, -20)])
	draw_polyline(tri, Style.PINK, 2.0, true)
	draw_arc(c + Vector2(0, 4), 7.0, 0.0, TAU, 16, Style.CYAN, 1.8, true)
	var blink := 1.0 if fmod(time, 4.0) > 0.12 else 0.2
	draw_circle(c + Vector2(0, 4), 2.8 * blink, Style.CYAN)
	var crown := PackedVector2Array([c + Vector2(-14, -24), c + Vector2(-14, -30), c + Vector2(-7, -26), c + Vector2(0, -33), c + Vector2(7, -26), c + Vector2(14, -30), c + Vector2(14, -24)])
	draw_polyline(crown, Style.GOLD, 1.6, true)


func _draw() -> void:
	if ship == null:
		return
	var vs := get_viewport_rect().size
	_draw_speed_fx(vs)

	# ================= LEWA KOLUMNA =================
	_emblem(Rect2(12, 12, 76, 66))
	# kadłub + tarcza
	var hb := Rect2(96, 12, 230, 66)
	Style.chamfer_panel(self, hb, Color(0.4, 1.0, 0.5))
	var hull_c := Color(0.35, 1.0, 0.45)
	if ship.hull < GameState.stat("max_hull") * 0.3:
		hull_c = Style.RED if int(time * 4.0) % 2 == 0 else Color(1.0, 0.6, 0.3)
	_t(hb.position + Vector2(10, 22), "KADŁUB", 12, hull_c, true)
	var hv := "%d/%d" % [int(ceil(ship.hull)), int(GameState.stat("max_hull"))]
	_t(Vector2(hb.end.x - 10 - _tw(hv, 12), hb.position.y + 22), hv, 12, Style.TEXT)
	_mini_bar(Rect2(hb.position + Vector2(10, 27), Vector2(hb.size.x - 20, 7)), ship.hull / maxf(1.0, GameState.stat("max_hull")), hull_c)
	var ms_ := GameState.stat("max_shield")
	_t(hb.position + Vector2(10, 50), "TARCZA", 12, Style.CYAN if ms_ > 0.0 else Style.DIM, true)
	var sv := "%d/%d" % [int(ceil(ship.shield)), int(ms_)]
	_t(Vector2(hb.end.x - 10 - _tw(sv, 12), hb.position.y + 50), sv, 12, Style.TEXT)
	_mini_bar(Rect2(hb.position + Vector2(10, 55), Vector2(hb.size.x - 20, 5)), ship.shield / maxf(1.0, ms_), Style.CYAN)

	# ŁADOWNIA - duży, wyraźny panel tuż pod kadłubem
	_draw_cargo_panel(Rect2(12, 86, 314, 46))
	_draw_cargo_ring()

	_draw_resources(Vector2(12, 140))

	# ================= DÓŁ: pasek paliwa (jak "stamina" w Agrivore) =================
	var mf := GameState.stat("max_fuel")
	var fc := Color(0.55, 1.0, 0.3)
	var flabel := "PALIWO"
	if ship.fuel <= 0.0:
		fc = Style.RED if int(time * 4.0) % 2 == 0 else Color(0.5, 0.05, 0.05)
		flabel = "PALIWO — PUSTO! WRACAJ"
	elif ship.fuel < mf * 0.25:
		fc = Color(1.0, 0.45, 0.1) if int(time * 3.0) % 2 == 0 else Color(1.0, 0.85, 0.2)
		flabel = "PALIWO — NISKI POZIOM"
	var fb := Rect2(8, vs.y - 22, vs.x - 16, 12)
	draw_rect(fb.grow(3), Color(0, 0, 0, 0.85))
	draw_rect(fb.grow(3), Color(Style.GOLD.r, Style.GOLD.g, Style.GOLD.b, 0.55), false, 1.0)
	draw_rect(Rect2(fb.position, Vector2(fb.size.x * clampf(ship.fuel / maxf(1.0, mf), 0.0, 1.0), fb.size.y)), fc)
	draw_rect(Rect2(fb.position + Vector2(0, 1), Vector2(fb.size.x * clampf(ship.fuel / maxf(1.0, mf), 0.0, 1.0), 2)), Color(1, 1, 1, 0.35))
	# błyskawica + liczba
	var lp := Vector2(12, vs.y - 32)
	var bolt := PackedVector2Array([lp + Vector2(4, -12), lp + Vector2(-1, -3), lp + Vector2(3, -3), lp + Vector2(0, 5), lp + Vector2(7, -6), lp + Vector2(3, -6), lp + Vector2(6, -12)])
	draw_colored_polygon(bolt, fc)
	_t(lp + Vector2(14, 0), "%d/%d  %s" % [int(ceil(ship.fuel)), int(mf), flabel], 13, fc, true)

	# sloty narzędzi (żółta ramka aktywnego - jak w Agrivore)
	var tools := [[1, "bolt", "LASER", Style.PINK, true],
		[2, "ufo", "PORYWANIE", Color(0.45, 1.0, 0.55), GameState.stat("lab") > 0.0],
		[3, "hammer", "ODBUDOWA", Style.GOLD, GameState.stat("rebuild") > 0.0]]
	var shown: Array = tools.filter(func(t): return t[4])
	var sw := 46.0
	var sx := vs.x * 0.5 - (shown.size() * (sw + 8) - 8) * 0.5
	for t in shown:
		var r := Rect2(sx, vs.y - 84, sw, sw)
		var active: bool = ship.tool == t[0]
		var c: Color = t[3]
		Style.panel(self, r, Style.GOLD if active else Style.DIM, Color(0.05, 0.02, 0.08, 0.95) if not active else Color(0.12, 0.08, 0.02, 0.95))
		Style.draw_icon(self, t[1], r.get_center() + Vector2(0, -3), 12.0, c if active else Color(c.r * 0.5, c.g * 0.5, c.b * 0.5), 1.8)
		_t(r.position + Vector2(4, 12), str(t[0]), 10, Style.TEXT_DIM)
		if active:
			var lw := _tw(t[2], 11, true)
			_t(Vector2(r.get_center().x - lw * 0.5, r.end.y - 4), t[2], 11, Style.GOLD, true)
		sx += sw + 8

	# cel lasera
	if world.target_idx >= 0 and world.is_minable(world.target_idx):
		var i: int = world.target_idx
		var info: String = world.tile_name(i).to_upper() + "  %d/%d" % [int(ceil(world.hp[i])), int(world.max_hp[i])]
		var iw := _tw(info, 13, true)
		draw_string_outline(font_b, Vector2(vs.x * 0.5 - iw * 0.5, vs.y - 96), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5, Color(0, 0, 0, 0.85))
		_t(Vector2(vs.x * 0.5 - iw * 0.5, vs.y - 96), info, 13, Style.PINK, true)

	# koszt odbudowy celu (suma obszaru)
	if ship.rebuilding and ship.rebuild_idx >= 0:
		var total := {}
		for j in ship.rebuild_tiles(ship.rebuild_idx):
			var one: Dictionary = world.rebuild_cost(j)
			for k in one:
				total[k] = int(total.get(k, 0)) + int(one[k])
		if not total.is_empty():
			var ct := "KOSZT: " + GameState.cost_text(total).to_upper()
			var ctw := _tw(ct, 13, true)
			var ctc := Style.GOLD if GameState.can_afford(total) else Style.RED
			draw_string_outline(font_b, Vector2(vs.x * 0.5 - ctw * 0.5, vs.y - 96), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5, Color(0, 0, 0, 0.85))
			_t(Vector2(vs.x * 0.5 - ctw * 0.5, vs.y - 96), ct, 13, ctc, true)

	# ================= PRAWA STRONA: minimapa =================
	var ms := 210.0
	var mp := Vector2(vs.x - ms - 16, 16)
	if world.minimap_tex:
		var mframe := Rect2(mp - Vector2(6, 6), Vector2(ms + 12, ms + 12))
		Style.chamfer_panel(self, mframe, Style.PINK, Color(0.01, 0.0, 0.04, 0.95), 12.0)
		# minimapa pokazuje tylko sektor, w którym jest statek
		var sector := view_sector
		draw_texture_rect_region(world.minimap_tex, Rect2(mp, Vector2(ms, ms)), Rect2(view_origin, Vector2(Sectors.SIZE, Sectors.SIZE)))
		var sector_px := float(Sectors.SIZE * world.T)
		var k := ms / sector_px
		var origin := view_origin * float(world.T)
		var map_rect := Rect2(mp, Vector2(ms, ms))
		# delikatna siatka i linia skanera sunąca z góry na dół
		for g in range(1, 4):
			var gp := ms * g / 4.0
			draw_line(mp + Vector2(gp, 0), mp + Vector2(gp, ms), Color(0.5, 0.75, 1.0, 0.09), 1.0)
			draw_line(mp + Vector2(0, gp), mp + Vector2(ms, gp), Color(0.5, 0.75, 1.0, 0.09), 1.0)
		var scan := fmod(time * 0.22, 1.0) * ms
		for j in 5:
			var sy: float = mp.y + scan - j * 3.0
			if sy > mp.y:
				draw_rect(Rect2(mp.x, sy, ms, 3.0), Color(0.45, 0.95, 1.0, 0.07 * (1.0 - j / 5.0)))
		# przy przesuwaniu widać też miasto sąsiedniego sektora
		for s in Sectors.LIST.size():
			var cpos: Vector2 = mp + (world.city_pos(s) - origin) * k
			if not map_rect.has_point(cpos) or not Sectors.has_city(s):
				continue
			var cname: String = GameState.city_name(s)
			var cw := _tw(cname, 11, true)
			var cl := Vector2(clampf(cpos.x - cw * 0.5, mp.x + 2, mp.x + ms - cw - 2), cpos.y + 17 if cpos.y < mp.y + ms - 24 else cpos.y - 9)
			draw_string_outline(font_b, cl, cname, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, 0.95))
			_t(cl, cname, 11, Color(1.0, 0.8, 0.98), true)
		for lk in world.landmark_cells.size():
			var lmp: Vector2 = mp + (world.landmark_pos(lk) - origin) * k
			if not map_rect.has_point(lmp):
				continue
			var ln: String = Sectors.LANDMARKS[lk]["name"]
			var lw := _tw(ln, 10, true)
			var ll := Vector2(clampf(lmp.x - lw * 0.5, mp.x + 2, mp.x + ms - lw - 2), lmp.y + 15 if lmp.y < mp.y + ms - 24 else lmp.y - 9)
			draw_string_outline(font_b, ll, ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 4, Color(0, 0, 0, 0.95))
			_t(ll, ln, 10, Color(1.0, 0.8, 0.4), true)
		# ostatnie kafelki metropolii i punkt powrotu na bossa
		var dot_a := 0.5 + 0.5 * sin(time * 8.0)
		for tiles in world.metro_last:
			for i in tiles:
				var tp: Vector2 = mp + (world.idx_center(i) - origin) * k
				if map_rect.has_point(tp):
					draw_rect(Rect2(tp - Vector2(1.5, 1.5), Vector2(3, 3)), Color(1.0, 0.5, 0.95, 0.4 + 0.6 * dot_a))
		for s in Sectors.LIST.size():
			if GameState.boss_state(s) != "":
				var bp: Vector2 = mp + (world.city_pos(s) - origin) * k
				if map_rect.has_point(bp):
					draw_arc(bp, 7.0 + dot_a * 2.0, 0.0, TAU, 16, Style.PINK, 2.0, true)
		# granice sektorów na minimapie w czasie przesuwania
		for bx in range(1, Sectors.COLS):
			var gx: float = mp.x + (bx * Sectors.SIZE - view_origin.x) * ms / Sectors.SIZE
			if gx > mp.x and gx < mp.x + ms:
				draw_line(Vector2(gx, mp.y), Vector2(gx, mp.y + ms), Color(0.4, 0.9, 1.0, 0.8), 1.0)
		for by in range(1, Sectors.ROWS):
			var gy: float = mp.y + (by * Sectors.SIZE - view_origin.y) * ms / Sectors.SIZE
			if gy > mp.y and gy < mp.y + ms:
				draw_line(Vector2(mp.x, gy), Vector2(mp.x + ms, gy), Color(0.4, 0.9, 1.0, 0.8), 1.0)
		var mpos: Vector2 = mp + (mothership.global_position - origin) * k
		if map_rect.has_point(mpos):
			_mini_mother(mpos)
		# widok kamery: same narożniki, żeby nie zasłaniać mapy
		var ctf := get_viewport().get_canvas_transform()
		var tl: Vector2 = ctf.affine_inverse() * Vector2.ZERO
		var brc: Vector2 = ctf.affine_inverse() * vs
		var vr := Rect2(mp + (tl - origin) * k, (brc - tl) * k).intersection(map_rect)
		var arm := minf(vr.size.x, vr.size.y) * 0.22
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var cp: Vector2 = vr.position + vr.size * corner
			var sgx := 1.0 if corner.x == 0.0 else -1.0
			var sgy := 1.0 if corner.y == 0.0 else -1.0
			draw_line(cp, cp + Vector2(arm * sgx, 0), Color(1, 1, 1, 0.7), 1.0)
			draw_line(cp, cp + Vector2(0, arm * sgy), Color(1, 1, 1, 0.7), 1.0)
		# statek: strzałka w kierunku lotu i rozchodzący się sygnał
		var sp: Vector2 = (mp + (ship.global_position - origin) * k).clamp(mp, mp + Vector2(ms, ms))
		var ping := fmod(time * 0.8, 1.0)
		draw_arc(sp, 4.0 + ping * 11.0, 0.0, TAU, 20, Color(0.5, 1.0, 1.0, 0.7 * (1.0 - ping)), 1.2, true)
		var sd := Vector2.RIGHT.rotated(ship.rotation)
		var arrow := PackedVector2Array([sp + sd * 7.0, sp + sd.rotated(2.45) * 5.5, sp - sd * 1.5, sp + sd.rotated(-2.45) * 5.5])
		draw_colored_polygon(arrow, Color(1, 1, 1))

		# panel pod mapą: wysokość zależy od tego, co jest do pokazania
		var extra_rows := 2 + (3 if world.imperial_count > 0 else 0)
		if not GameState.research.is_empty():
			extra_rows += 1
		if GameState.stat("rocket_unlocked") > 0.0 and weapons:
			extra_rows += 1
		if GameState.stat("drone_count") > 0.0:
			extra_rows += 1
		if GameState.stat("wing_count") > 0.0:
			extra_rows += 1
		if GameState.stat("transit_count") > 0.0:
			extra_rows += 1
		if GameState.stat("gun_unlocked") > 0.0:
			extra_rows += 1
		if enemies_count() > 0:
			extra_rows += 1
		if mothership and (mothership.siege or mothership.wrecked or mothership.hp < mothership.max_hp() - 0.5):
			extra_rows += 1
		var lms: Array = world.landmarks_in_sector(sector)
		var info := Rect2(mp.x - 6, mframe.end.y + 8, ms + 12, 34.0 + (3.0 + lms.size()) * 25.0 + extra_rows * 16.0 + 14.0)
		Style.chamfer_panel(self, info, Color(0.55, 0.4, 0.85), Color(0.02, 0.0, 0.05, 0.86), 10.0)
		right_bottom = info.end.y
		var ly := info.position.y + 20.0
		_t(Vector2(mp.x, ly), String(Sectors.LIST[sector]["name"]), 12, Style.CYAN, true)
		draw_line(Vector2(mp.x, ly + 7.0), Vector2(mp.x + ms, ly + 7.0), Color(0.3, 0.95, 1.0, 0.3), 1.0)
		ly += 26.0
		_stat_bar(mp.x, ly, ms, "ZNISZCZENIE ZIEMI", "%.2f%%" % world.devastated_percent(), world.devastated_percent() / 100.0, Style.PINK)
		ly += 25.0
		_stat_bar(mp.x, ly, ms, "ODBUDOWA ZIEMI", "%.2f%%" % world.imperial_percent(), world.imperial_percent() / 100.0, Style.GOLD)
		ly += 25.0
		if Sectors.has_city(sector):
			_stat_bar(mp.x, ly, ms, GameState.city_name(sector), "%d%%" % int(world.metro_destroyed_fraction(sector) * 100.0), world.metro_destroyed_fraction(sector), Color(1.0, 0.55, 0.9))
			ly += 25.0
		for lk in lms:
			var lf: float = world.landmark_destroyed_fraction(lk)
			_stat_bar(mp.x, ly, ms, String(Sectors.LANDMARKS[lk]["name"]), "%d%%" % int(lf * 100.0), lf, Color(1.0, 0.75, 0.35))
			ly += 25.0
		var lines := [["ZNISZCZONE", str(GameState.tiles_destroyed), Style.TEXT_DIM], ["PRĘDKOŚĆ", str(int(ship.vel.length())), Style.TEXT_DIM]]
		if world.imperial_count > 0:
			lines.append(["IMPERIUM", str(world.imperial_count), Style.GOLD])
			lines.append(["POTĘGA", str(int(GameState.bank.get("power", 0))), Style.GOLD])
			lines.append(["  /MIN", "+%.1f" % (world.power_rate() * 60.0), Style.GOLD])
		for ln in lines:
			_t(Vector2(mp.x, ly), ln[0], 11, ln[2])
			_t(Vector2(mp.x + ms - _tw(ln[1], 12, true), ly), ln[1], 12, ln[2], true)
			ly += 16
		# stan broni / badania
		ly += 6
		if not GameState.research.is_empty():
			var rf: float = float(GameState.research["progress"]) / float(GameState.research["duration"])
			_t(Vector2(mp.x, ly), "BADANIE %ds" % int(ceil(GameState.research_time_left())), 11, Color(0.5, 1.0, 0.6), true)
			_mini_bar(Rect2(mp.x + 100, ly - 8, ms - 100, 6), rf, Color(0.45, 1.0, 0.5))
			ly += 16
		if GameState.stat("rocket_unlocked") > 0.0 and weapons:
			var cd: float = weapons.rocket_cooldown()
			var full: bool = weapons.rocket_ammo >= weapons.ROCKET_MAG
			var frac: float = 1.0 if full else 1.0 - clampf(weapons.rocket_timer / cd, 0.0, 1.0)
			var rc := Color(1.0, 0.6, 0.3) if weapons.rocket_ammo > 0 else Color(0.6, 0.45, 0.4)
			_t(Vector2(mp.x, ly), GameState.keys_text("RAKIETY x%d [{rocket}]" % weapons.rocket_ammo), 11, rc, true)
			_mini_bar(Rect2(mp.x + 100, ly - 8, ms - 100, 6), frac, Color(1.0, 0.55, 0.2))
			ly += 16
		if mothership and (mothership.siege or mothership.wrecked or mothership.hp < mothership.max_hp() - 0.5):
			var mc := Color(1.0, 0.3, 0.35) if mothership.siege or mothership.wrecked else Color(1.0, 0.5, 0.95)
			if mothership.wrecked:
				_t(Vector2(mp.x, ly), "MATKA: ODBUDOWA %ds" % int(ceil(mothership.wreck_t)), 11, mc, true)
			else:
				var mhf: float = mothership.hp / maxf(1.0, mothership.max_hp())
				_t(Vector2(mp.x, ly), ("! MATKA %d%%" if mothership.siege else "MATKA %d%%") % int(round(mhf * 100.0)), 11, mc, true)
				_mini_bar(Rect2(mp.x + 100, ly - 8, ms - 100, 6), mhf, mc)
			ly += 16
		if GameState.stat("drone_count") > 0.0:
			_t(Vector2(mp.x, ly), "DRONY x%d" % int(GameState.stat("drone_count")), 11, Color(0.4, 1.0, 0.9), true)
			ly += 16
		if GameState.stat("wing_count") > 0.0:
			var wl: String = "MYŚLIWCE %d/%d: W ESKORCIE" % [wingmen.wings.size(), wingmen.count()] if wingmen and wingmen.called \
				else GameState.keys_text("MYŚLIWCE %d/%d: WEZWIJ [{wing}]" % [wingmen.ready_count(), wingmen.count()])
			_t(Vector2(mp.x, ly), wl, 11, Style.GOLD, true)
			ly += 16
		if GameState.stat("transit_count") > 0.0 and transit:
			var trl: String = "TRANZYT: W DRODZE" if not transit.ships.is_empty() else "TRANZYT ZA %ds" % int(ceil(maxf(0.0, transit.timer)))
			_t(Vector2(mp.x, ly), trl, 11, Style.GOLD, true)
			ly += 16
		if GameState.stat("gun_unlocked") > 0.0:
			_t(Vector2(mp.x, ly), "KARABINY AKTYWNE", 11, Color(1.0, 0.9, 0.5), true)
			ly += 16
		if enemies_count() > 0:
			var a := 0.6 + 0.4 * sin(time * 8.0)
			var nt: int = weapons.enemies.tank_count()
			var nf: int = enemies_count() - nt
			var et := ("! MYŚLIWCE: %d" % nf) if nt == 0 else (("! CZOŁGI: %d" % nt) if nf == 0 else "! MYŚL.: %d  CZOŁGI: %d" % [nf, nt])
			_t(Vector2(mp.x, ly), et, 12, Color(1.0, 0.3, 0.3, a), true)

	# ================= statek matka: wskaźnik i dokowanie =================
	var dist := ship.global_position.distance_to(mothership.global_position)
	_edge_arrow(mothership.global_position, "MATKA", Style.GOLD, vs)
	# różowa strzałka do punktu powrotu na bossa
	for s in Sectors.LIST.size():
		if GameState.boss_state(s) != "":
			_edge_arrow(world.city_pos(s), "BOSS", Style.PINK, vs)
	if not ship.dead and dist < mothership.DOCK_RADIUS:
		var dr := Rect2(vs.x - 180, vs.y - 92, 168, 34)
		var a2 := 0.6 + 0.4 * sin(time * 6.0)
		Style.panel(self, dr, Color(Style.GOLD.r, Style.GOLD.g, Style.GOLD.b, a2), Color(0.12, 0.08, 0.02, 0.95))
		var dt := GameState.keys_text("DOKUJ  [{dock}]")
		_t(Vector2(dr.get_center().x - _tw(dt, 15, true) * 0.5, dr.position.y + 23), dt, 15, Style.GOLD, true)
	# przy punkcie bossa wejście tylko klawiszem, jak dokowanie
	if not ship.dead and not ship.docked and world.boss_portal_at(ship.global_position) >= 0:
		var br := Rect2(vs.x - 250, vs.y - 92, 238, 34)
		var a4 := 0.6 + 0.4 * sin(time * 6.0)
		Style.panel(self, br, Color(Style.PINK.r, Style.PINK.g, Style.PINK.b, a4), Color(0.12, 0.02, 0.1, 0.95))
		var bt := GameState.keys_text("WEJDŹ DO WALKI  [{dock}]")
		_t(Vector2(br.get_center().x - _tw(bt, 15, true) * 0.5, br.position.y + 23), bt, 15, Style.PINK, true)

	# podpowiedź sterowania (u góry, dyskretnie)
	var help := GameState.keys_text("LPM STRZAŁ • {tool1}/{tool2}/{tool3} NARZĘDZIA • {rocket} RAKIETA • PPM/{thrust} CIĄG • {drift} DRIFT • {brake} HAMULEC • {stop} STOP •{left}/{right} BOK • KÓŁKO ZOOM • {dock} DOK • {pause} PAUZA • {crt} CRT • {fps} FPS")
	var hw := _tw(help, 11)
	draw_rect(Rect2(vs.x * 0.5 - hw * 0.5 - 8, 4, hw + 16, 17), Color(0, 0, 0, 0.7))
	_t(Vector2(vs.x * 0.5 - hw * 0.5, 16), help, 11, Color(0.6, 0.5, 0.75, 0.85))

	_draw_tracking(vs)
	_draw_mine_info(vs)

	# ================= komunikaty =================
	var my := 70.0 + (44.0 if track_a > 0.01 else 0.0) + (24.0 if show_fps and track_a > 0.01 else 0.0)
	for m in messages:
		var a3: float = clampf(m["life"], 0.0, 1.0)
		var c3: Color = m["color"]
		var w3 := _tw(m["text"], 17, true)
		var mpos := Vector2(vs.x * 0.5 - w3 * 0.5, my)
		draw_string_outline(font_b, mpos, m["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 6, Color(0, 0, 0, 0.85 * a3))
		_t(mpos, m["text"], 17, Color(c3.r, c3.g, c3.b, a3), true)
		my += 26.0

	if show_fps:
		var fps := "FPS %d" % Engine.get_frames_per_second()
		draw_rect(Rect2(vs.x * 0.5 - 50, 26, 100, 22), Color(0, 0, 0, 0.8))
		_t(Vector2(vs.x * 0.5 - _tw(fps, 15, true) * 0.5, 43), fps, 15, Style.GREEN, true)

	_draw_sector_banner(vs)
	_draw_big(vs)
	_draw_missile_warnings()
	_draw_enemy_markers(vs)

	# czerwony błysk przy trafieniu kadłuba
	if ship.hit_flash > 0.0 and ship.shield <= 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.0, 0.1, ship.hit_flash * 0.15))


const RES_ROW := 21.0


## Ładunek: jedna czysta lista. Świeżo zebrany surowiec rozbłyskuje w swoim kolorze.
func _draw_resources(at: Vector2) -> void:
	var keys: Array = GameState.RES_ORDER.filter(func(k): return GameState.cargo.has(k))
	var has_bio: bool = GameState.stat("lab") > 0.0
	left_bottom = at.y
	if keys.is_empty() and not has_bio:
		return
	var w := 236.0
	var rows := keys.size() + (1 if has_bio else 0)
	var panel := Rect2(at, Vector2(w, rows * RES_ROW + 12.0))
	left_bottom = panel.end.y
	Style.chamfer_panel(self, panel, Color(0.55, 0.4, 0.85), Color(0.02, 0.0, 0.05, 0.86), 8.0)
	var y := at.y + 6.0
	for k in keys:
		var c: Color = GameState.RES_COLORS[k]
		var pop: float = pops.get(k, 0.0) / 0.25
		var row := Rect2(at.x + 5.0, y, w - 10.0, RES_ROW)
		if pop > 0.0:
			draw_rect(row, Color(c.r, c.g, c.b, 0.3 * pop))
		var ic := Vector2(at.x + 17.0, y + RES_ROW * 0.5)
		var d := 5.0 + 2.0 * pop
		draw_colored_polygon(PackedVector2Array([ic + Vector2(0, -d), ic + Vector2(d, 0), ic + Vector2(0, d), ic + Vector2(-d, 0)]), c)
		_t(Vector2(at.x + 30.0, y + 15.0), String(GameState.RES_NAMES[k]), 13, Color(c.r, c.g, c.b).lerp(Color(1, 1, 1), 0.2))
		var n := str(int(GameState.cargo[k]))
		_t(Vector2(at.x + w - 12.0 - _tw(n, 14, true), y + 15.0), n, 14, Color(1, 1, 1), true)
		y += RES_ROW
	if has_bio:
		var bc := Color(0.45, 1.0, 0.55)
		if not keys.is_empty():
			draw_line(Vector2(at.x + 10.0, y), Vector2(at.x + w - 10.0, y), Color(bc.r, bc.g, bc.b, 0.25), 1.0)
		Style.draw_icon(self, "ufo", Vector2(at.x + 17.0, y + RES_ROW * 0.5), 7.0, bc, 1.3)
		var bl := ""
		for ck in GameState.CREATURES:
			if GameState.bio_cargo.has(ck):
				bl += "%s %d  " % [String(GameState.RES_NAMES[ck]), int(GameState.bio_cargo[ck])]
		_t(Vector2(at.x + 30.0, y + 15.0), bl if bl != "" else "Komory bio", 12, bc)
		var bn := "%d/%d" % [GameState.bio_total(), int(GameState.stat("bio_capacity"))]
		_t(Vector2(at.x + w - 12.0 - _tw(bn, 13, true), y + 15.0), bn, 13, Color(1, 1, 1), true)


## Rząd statystyki z paskiem pod spodem.
func _stat_bar(x: float, y: float, w: float, label: String, value: String, frac: float, c: Color) -> void:
	_t(Vector2(x, y), label, 11, c)
	_t(Vector2(x + w - _tw(value, 12, true), y), value, 12, c, true)
	var bar := Rect2(x, y + 4.0, w, 4.0)
	draw_rect(bar, Color(c.r * 0.2, c.g * 0.2, c.b * 0.2, 0.9))
	draw_rect(Rect2(bar.position, Vector2(w * clampf(frac, 0.0, 1.0), bar.size.y)), c)


## Znacznik Statku Matki na minimapie: mały złoty ośmiokąt.
func _mini_mother(p: Vector2) -> void:
	var pts := PackedVector2Array()
	for k in 9:
		pts.append(p + Vector2.from_angle(time * 0.6 + k / 8.0 * TAU) * 6.5)
	draw_polyline(pts, Style.GOLD, 1.6, true)
	draw_circle(p, 2.0, Style.GOLD)


## Kolor ładowni zależny od zapełnienia: zielony -> żółty -> pomarańczowy -> migający czerwony.
func _cargo_color(fr: float) -> Color:
	if fr >= 1.0:
		return Style.RED if int(time * 4.0) % 2 == 0 else Color(1.0, 0.75, 0.2)
	if fr >= 0.8:
		return Color(1.0, 0.45, 0.15)
	if fr >= 0.5:
		return Color(1.0, 0.85, 0.25)
	return Color(0.35, 1.0, 0.75)


func _draw_cargo_panel(r: Rect2) -> void:
	var total := GameState.cargo_total()
	var cap := maxi(1, GameState.cargo_cap())
	var fr := float(total) / cap
	var c := _cargo_color(fr)
	# "pyknięcie" całego panelu przy zbiorze
	var pop := 0.0
	for k in pops:
		pop = maxf(pop, pops[k] / 0.25)
	var rr := r.grow(pop * 2.0)
	Style.chamfer_panel(self, rr, c, Color(c.r * 0.1, c.g * 0.1, c.b * 0.1, 0.94))
	# ikona skrzyni
	var ic := rr.position + Vector2(22, rr.size.y * 0.5)
	var box := Rect2(ic - Vector2(11, 9), Vector2(22, 18))
	draw_rect(box, Color(c.r * 0.3, c.g * 0.3, c.b * 0.3))
	draw_rect(box, c, false, 1.8)
	draw_line(box.position + Vector2(0, 6), box.position + Vector2(22, 6), c, 1.5)
	draw_rect(Rect2(ic + Vector2(-3, -5), Vector2(6, 5)), c)
	# napis + liczby
	var label := "ŁADOWNIA"
	if fr >= 1.0:
		label = GameState.keys_text("ŁADOWNIA PEŁNA - WRACAJ [{dock}]")
	elif fr >= 0.8:
		label = "ŁADOWNIA PRAWIE PEŁNA"
	_t(rr.position + Vector2(44, 19), label, 12, c, true)
	var nums := "%d/%d" % [total, cap]
	_t(Vector2(rr.end.x - 12 - _tw(nums, 17, true), rr.position.y + 21), nums, 17, Color(1, 1, 1).lerp(c, 0.3), true)
	# gruby pasek z podziałką
	var bar := Rect2(rr.position + Vector2(44, 27), Vector2(rr.size.x - 56, 11))
	draw_rect(bar, Color(0, 0, 0, 0.9))
	# pasek składa się z kolorów tego, co jest w ładowni
	var bx := bar.position.x
	for k in GameState.RES_ORDER:
		if GameState.cargo.has(k):
			var seg := bar.size.x * minf(float(GameState.cargo[k]) / cap, 1.0)
			seg = minf(seg, bar.end.x - bx)
			if seg > 0.0:
				draw_rect(Rect2(bx, bar.position.y, seg, bar.size.y), GameState.RES_COLORS[k])
				bx += seg
	draw_rect(Rect2(bar.position + Vector2(0, 1), Vector2(bx - bar.position.x, 2)), Color(1, 1, 1, 0.3))
	draw_rect(bar, Color(c.r, c.g, c.b, 0.8), false, 1.0)


## Łuk zapełnienia ładowni wokół statku - widoczny bez odrywania wzroku od akcji.
func _draw_cargo_ring() -> void:
	if ship.docked or ship.dead:
		return
	var total := GameState.cargo_total()
	if total <= 0:
		return
	var fr := clampf(float(total) / maxf(1.0, GameState.cargo_cap()), 0.0, 1.0)
	var c := _cargo_color(fr)
	var sp: Vector2 = get_viewport().get_canvas_transform() * ship.global_position
	var rad := 34.0
	var a0 := PI * 0.75
	var span := PI * 1.5
	var base_a := 0.25 if fr < 0.8 else 0.5
	draw_arc(sp, rad, a0, a0 + span, 40, Color(0, 0, 0, 0.55), 5.0, true)
	draw_arc(sp, rad, a0, a0 + span, 40, Color(c.r, c.g, c.b, base_a * 0.6), 1.0, true)
	draw_arc(sp, rad, a0, a0 + span * fr, maxi(4, int(40 * fr)), Color(c.r, c.g, c.b, 0.85), 3.0, true)


func enemies_count() -> int:
	if weapons and weapons.enemies:
		return weapons.enemies.alive_count()
	return 0
