extends Node2D
## Efekty wizualne w stylu Agrivore + synthwave:
## liczby obrażeń, kolczaste wybuchy ("słoneczka"), iskry, pierścienie, surowce lecące do statku,
## wstrząs ekranu oraz promienie narzędzi (laser, porywanie, odbudowa).

const Style = preload("res://scripts/style.gd")
const MAX_NUMBERS := 50
const MAX_PICKUPS := 120
const MAX_SPARKS := 320
const MAX_FLASHES := 48    # kolczaste słońca i pierścienie

var ship: Node2D
var enemies: Node2D          # plazma z driftu rani wrogie myśliwce
var world: Node2D            # ... i strąca rakiety
var sparks_list: Array = []   # {pos, vel, life, max, color}
var rings: Array = []         # {pos, max_r, life, max, color}
var texts: Array = []         # {pos, text, life, color}
var numbers: Array = []       # {pos, vel, text, life, max, color, size}
var bursts: Array = []        # {pos, r, life, max, color, rot, spikes}
var pickups: Array = []       # {pos, vel, color, life}
var plasma: Array = []        # {pos, vel, r, grow, life, max, color} - kule plazmy z wyrzutu po drifcie
var jets: Array = []          # {pos, dir, len, w, life, max} - stożek odrzutu
var time := 0.0
var font: Font
var shake_amount := 0.0


func _ready() -> void:
	z_index = 7
	font = Style.font_bold()


# ---------------- API ----------------

func sparks(p: Vector2, c: Color, n: int, speed := 160.0) -> void:
	for k in n:
		if sparks_list.size() >= MAX_SPARKS:
			return
		var a := randf() * TAU
		var life := randf_range(0.25, 0.7)
		sparks_list.append({"pos": p, "vel": Vector2.from_angle(a) * randf_range(speed * 0.3, speed), "life": life, "max": life, "color": c})


## Pojedyncza smuga o zadanej prędkości (spaliny, pęd statku).
func streak(p: Vector2, v: Vector2, c: Color, life := 0.25) -> void:
	if sparks_list.size() < MAX_SPARKS:
		sparks_list.append({"pos": p, "vel": v, "life": life, "max": life, "color": c})


func ring(p: Vector2, c: Color, max_r: float, life := 0.4) -> void:
	if rings.size() >= MAX_FLASHES:
		return
	rings.append({"pos": p, "max_r": max_r, "life": life, "max": life, "color": c})


## Kolczaste "słoneczko" jak w Agrivore.
func sunburst(p: Vector2, c: Color, r := 26.0, life := 0.35, spikes := 10) -> void:
	if bursts.size() >= MAX_FLASHES:
		return
	bursts.append({"pos": p, "r": r, "life": life, "max": life, "color": c, "rot": randf() * TAU, "spikes": spikes})


func explosion(p: Vector2, c: Color, big := false) -> void:
	if big:
		sparks(p, c, 34, 320.0)
		sunburst(p, Style.GOLD, 70.0, 0.55, 14)
		ring(p, Color(c.r, c.g, c.b, 0.8), 120.0, 0.6)
		ring(p, Color(1.0, 1.0, 1.0, 0.6), 60.0, 0.35)
		shake(10.0)
	else:
		sparks(p, c, 6, 120.0)
		sunburst(p, Color(c.r, c.g, c.b, 0.9), 22.0, 0.3, 10)
		ring(p, Color(c.r, c.g, c.b, 0.5), 26.0, 0.25)


## Liczba obrażeń wyskakująca z trafionego miejsca.
func damage_number(p: Vector2, value: float, c: Color, big := false) -> void:
	if numbers.size() >= MAX_NUMBERS:
		numbers.pop_front()
	var txt := str(int(round(value))) if value >= 1.0 else "%.1f" % value
	var life := 0.75 if not big else 1.0
	numbers.append({"pos": p + Vector2(randf_range(-8, 8), randf_range(-6, 2)),
		"vel": Vector2(randf_range(-30, 30), randf_range(-95, -60)), "text": txt,
		"life": life, "max": life, "color": c, "size": 20 if big else 14})


func float_text(p: Vector2, text: String, c: Color) -> void:
	texts.append({"pos": p + Vector2(randf_range(-10, 10), 0), "text": text, "life": 1.4, "color": c})


## Zebrany surowiec: drobinki lecą łukiem do statku.
func pickup(p: Vector2, c: Color, n := 3) -> void:
	for k in mini(n, 6):
		if pickups.size() >= MAX_PICKUPS:
			return
		pickups.append({"pos": p + Vector2(randf_range(-10, 10), randf_range(-10, 10)),
			"vel": Vector2.from_angle(randf() * TAU) * randf_range(120, 220), "color": c, "life": 2.0})


## Wyrzut plazmy z tyłu statku przy zrywie z driftu: stożek odrzutu, kule plazmy i fala.
## Obrażenia rosną z mocą lasera i naładowaniem driftu: stożek trafia wszystko na swojej drodze od razu,
## a każda kula plazmy rani pierwszy statek, którego dotknie.
func plasma_burst(p: Vector2, back: Vector2, charge: float, carry: Vector2) -> void:
	var c := clampf(charge, 0.0, 1.0)
	var power := GameState.stat("laser_dps")
	var jet := {"pos": p, "dir": back, "len": 150.0 + 220.0 * c, "w": 26.0 + 30.0 * c, "life": 0.24, "max": 0.24}
	jets.append(jet)
	_jet_damage(jet, power * (1.2 + 1.8 * c))
	var n := int(10.0 + 16.0 * c)
	for k in n:
		if plasma.size() >= 80:
			break
		var life := randf_range(0.35, 0.75)
		var col := Color(0.35, 1.0, 1.4).lerp(Color(1.4, 0.3, 1.2), randf() * 0.8)
		plasma.append({"pos": p + back * randf_range(0.0, 10.0), "life": life, "max": life, "color": col,
			"vel": back.rotated(randf_range(-0.38, 0.38)) * randf_range(300.0, 950.0) * (0.6 + 0.4 * c) + carry * 0.3,
			"r": randf_range(5.0, 12.0) * (0.7 + 0.5 * c), "grow": randf_range(30.0, 80.0), "dmg": power * (0.5 + 0.7 * c)})
	sunburst(p, Color(0.6, 1.2, 1.4, 0.9), 34.0 + 30.0 * c, 0.3, 12)
	ring(p + back * 30.0, Color(1.3, 0.4, 1.2, 0.8), 70.0 + 70.0 * c, 0.35)
	ring(p, Color(0.5, 1.2, 1.4, 0.9), 40.0 + 40.0 * c, 0.22)


## Stożek odrzutu: trafia myśliwce i rakiety, które są w jego obrysie.
func _jet_damage(j: Dictionary, dmg: float) -> void:
	var d: Vector2 = j["dir"]
	var n := d.orthogonal()
	var p: Vector2 = j["pos"]
	if enemies:
		for f in enemies.fighters:
			if f.get("dead", false):
				continue
			var rel: Vector2 = f["pos"] - p
			var along := rel.dot(d)
			if along >= -10.0 and along <= j["len"] and absf(rel.dot(n)) < j["w"] * 0.7 + enemies.HIT_RADIUS:
				enemies.damage_fighter(f, dmg)
				sparks(f["pos"], Color(0.6, 1.2, 1.4), 6, 200.0)
	if world:
		for m in world.missiles:
			var rel: Vector2 = m["pos"] - p
			var along := rel.dot(d)
			if along >= -10.0 and along <= j["len"] and absf(rel.dot(n)) < j["w"] * 0.7 + 20.0:
				world.damage_missile(m, dmg)


## Kula plazmy rani pierwszy wrogi statek, którego dotknie, i gaśnie jako pocisk (zostaje tylko blask).
func _plasma_hits(pl: Dictionary) -> void:
	if pl["dmg"] <= 0.0 or enemies == null:
		return
	for f in enemies.fighters:
		if f.get("dead", false):
			continue
		if f["pos"].distance_to(pl["pos"]) < pl["r"] + enemies.HIT_RADIUS:
			enemies.damage_fighter(f, pl["dmg"])
			pl["dmg"] = 0.0
			sparks(pl["pos"], pl["color"], 5, 180.0)
			Audio.play("hit_tick", 0.1, 4.0)
			return


func shake(amount: float) -> void:
	shake_amount = minf(shake_amount + amount, 18.0)


## Przesunięcie kamery od wstrząsu (wywoływane przez main co klatkę).
func shake_offset() -> Vector2:
	if shake_amount <= 0.05 or not GameState.settings["shake"]:
		return Vector2.ZERO
	return Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amount


# ---------------- aktualizacja ----------------

func _process(delta: float) -> void:
	time += delta
	shake_amount = maxf(0.0, shake_amount - delta * 30.0)
	var slow := exp(-3.0 * delta)
	var k := sparks_list.size() - 1
	while k >= 0:
		var s: Dictionary = sparks_list[k]
		s["life"] -= delta
		if s["life"] <= 0.0:
			# zamiana z ostatnim: bez przesuwania całej tablicy, kolejność iskier nie ma znaczenia
			sparks_list[k] = sparks_list[-1]
			sparks_list.pop_back()
		else:
			s["pos"] += s["vel"] * delta
			s["vel"] *= slow
		k -= 1
	for r in rings:
		r["life"] -= delta
	if not rings.is_empty():
		rings = rings.filter(func(r): return r["life"] > 0.0)
	for b in bursts:
		b["life"] -= delta
		b["rot"] += delta * 2.0
	if not bursts.is_empty():
		bursts = bursts.filter(func(b): return b["life"] > 0.0)
	if not plasma.is_empty():
		var drag := exp(-2.6 * delta)
		for pl in plasma:
			pl["life"] -= delta
			pl["pos"] += pl["vel"] * delta
			pl["vel"] *= drag
			pl["r"] += pl["grow"] * delta
			_plasma_hits(pl)
		plasma = plasma.filter(func(pl): return pl["life"] > 0.0)
	if not jets.is_empty():
		for j in jets:
			j["life"] -= delta
		jets = jets.filter(func(j): return j["life"] > 0.0)
	for t in texts:
		t["pos"] += Vector2(0, -38.0) * delta
		t["life"] -= delta
	texts = texts.filter(func(t): return t["life"] > 0.0)
	for n in numbers:
		n["pos"] += n["vel"] * delta
		n["vel"] *= exp(-4.0 * delta)
		n["life"] -= delta
	numbers = numbers.filter(func(n): return n["life"] > 0.0)
	# drobinki surowców: najpierw rozbryzg, potem przyciąganie do statku
	if ship:
		var sp: Vector2 = ship.global_position
		for pk in pickups:
			pk["life"] -= delta
			var to: Vector2 = sp - pk["pos"]
			var age: float = 2.0 - pk["life"]
			var pull := clampf(age * 2.5, 0.0, 1.0)
			pk["vel"] = pk["vel"].lerp(to.normalized() * (500.0 + age * 600.0), pull * 8.0 * delta)
			pk["pos"] += pk["vel"] * delta
			if to.length() < 18.0 or ship.docked:
				if not ship.docked:
					Audio.play("pickup", 0.12)
				pk["life"] = 0.0
		pickups = pickups.filter(func(pk): return pk["life"] > 0.0)

	# drobne iskry z punktu trafienia lasera
	if ship and ship.firing and ship.beam_hit and randf() < 0.25:
		sparks(ship.beam_target, Color(1.0, 0.45, 0.8), 1, 90.0)
	if visible:
		queue_redraw()


# ---------------- rysowanie ----------------

func _draw() -> void:
	# poza ekranem nic nie rysujemy
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var tl: Vector2 = inv * Vector2.ZERO
	var view := Rect2(tl, (inv * get_viewport_rect().size) - tl).grow(60.0)
	# wiązka lasera - wyraźna, ale bez oślepiania
	if ship and ship.firing and not ship.docked and not ship.dead:
		var a: Vector2 = ship.nose()
		var b: Vector2 = ship.beam_target
		var flick := 0.9 + 0.1 * sin(time * 40.0)
		draw_line(a, b, Color(1.0, 0.3, 0.8, 0.16 * flick), 7.0, true)
		draw_line(a, b, Color(1.0, 0.55, 0.9, 0.85), 2.0, true)
		draw_line(a, b, Color(1.0, 0.95, 1.0, 0.75), 0.8, true)
		var rr := 4.5 + sin(time * 30.0) * 1.0
		draw_circle(b, rr, Color(1.0, 0.45, 0.85, 0.45) if ship.beam_hit else Color(0.8, 0.3, 0.7, 0.2))
		draw_circle(b, 1.8, Color(1.0, 0.9, 1.0, 0.9))
		# okrąg rozprysku i wiązki od punktu trafienia do kafelków w jego zasięgu
		if ship.beam_hit and GameState.stat("laser_splash") > 0.0:
			draw_arc(b, GameState.stat("laser_splash") * ship.world.T, 0.0, TAU, 48, Color(1.0, 0.5, 0.85, 0.45), 1.5, true)
		for sp in ship.splash_points:
			var j := Vector2(randf_range(-2, 2), randf_range(-2, 2))
			draw_line(b, sp + j, Color(1.0, 0.4, 0.85, 0.12), 4.0, true)
			draw_line(b, sp + j, Color(1.0, 0.6, 0.9, 0.6), 1.2, true)
			draw_circle(sp + j, 2.5, Color(1.0, 0.5, 0.85, 0.6))
		# cel poza zasięgiem - pokaż granicę zasięgu i czerwony krzyżyk przy kursorze
		if not ship.beam_in_range:
			var m := get_global_mouse_position()
			var rng := GameState.stat("laser_range")
			draw_arc(ship.nose(), rng, 0.0, TAU, 64, Color(1.0, 0.3, 0.4, 0.25), 1.0, true)
			draw_line(m + Vector2(-7, -7), m + Vector2(7, 7), Color(1.0, 0.3, 0.35, 0.9), 2.0, true)
			draw_line(m + Vector2(-7, 7), m + Vector2(7, -7), Color(1.0, 0.3, 0.35, 0.9), 2.0, true)

	# promień porywania (zielony stożek + postęp porwania)
	if ship and ship.abducting and not ship.docked and not ship.dead:
		var a: Vector2 = ship.global_position
		var b: Vector2 = ship.beam_target
		var ok: bool = ship.abduct_valid
		var col := Color(0.4, 1.0, 0.5) if ok else Color(0.7, 0.7, 0.75)
		var area := maxf(0.0, GameState.stat("abduct_area") - 0.5)
		var cw := 18.0 + area * 48.0
		var perp := (b - a).normalized().orthogonal()
		var cone := PackedVector2Array([a + perp * 4.0, b + perp * cw, b - perp * cw, a - perp * 4.0])
		draw_colored_polygon(cone, Color(col.r, col.g, col.b, 0.10 + 0.05 * sin(time * 12.0)))
		draw_line(a, b + perp * cw, Color(col.r, col.g, col.b, 0.5), 1.0, true)
		draw_line(a, b - perp * cw, Color(col.r, col.g, col.b, 0.5), 1.0, true)
		# kafelki, które zostaną porwane
		for j in ship.abduct_tiles(ship.abduct_idx):
			var tc: Vector2 = ship.world.idx_center(j)
			draw_rect(Rect2(tc - Vector2(22, 22), Vector2(44, 44)), Color(0.4, 1.0, 0.5, 0.35), false, 1.5)
		if area > 0.0:
			draw_arc(b, (area + 0.75) * 48.0, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.35), 1.5, true)
		# unoszące się drobinki
		for k in 4:
			var f := fmod(time * 0.9 + k * 0.25, 1.0)
			draw_circle(b.lerp(a, f) + perp * sin(time * 5.0 + k) * 6.0 * (1.0 - f), 1.8, Color(col.r, col.g, col.b, 0.8))
		if ok:
			draw_arc(b, 22.0 + area * 48.0, -PI * 0.5, -PI * 0.5 + TAU * ship.abduct_progress, 48, Color(0.5, 1.1, 0.6), 3.0, true)
		draw_arc(b, 22.0, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.25), 1.0, true)

	# promień odbudowy (złoty, imperialny)
	if ship and ship.rebuilding and not ship.docked and not ship.dead:
		var a: Vector2 = ship.nose()
		var b: Vector2 = ship.beam_target
		var ok: bool = ship.rebuild_valid
		var col := Color(1.0, 0.78, 0.3) if ok else Color(0.6, 0.55, 0.5)
		draw_line(a, b, Color(col.r, col.g, col.b, 0.18), 6.0, true)
		draw_line(a, b, Color(col.r, col.g, col.b, 0.85), 1.5, true)
		if ok:
			# każdy kafelek w obszarze: ramka + "skanowanie" od dołu do góry w miarę postępu
			var center_idx: int = ship.rebuild_idx if ship.rebuild_idx >= 0 else ship.world.pos_to_idx(b)
			for j in ship.rebuild_tiles(center_idx):
				var tc: Vector2 = ship.world.idx_center(j)
				var trc := Rect2(tc - Vector2(24, 24), Vector2(48, 48))
				draw_rect(trc, Color(col.r, col.g, col.b, 0.10))
				draw_rect(trc, col, false, 1.2)
				var yy: float = trc.end.y - trc.size.y * ship.rebuild_progress
				draw_line(Vector2(trc.position.x, yy), Vector2(trc.end.x, yy), Color(0.4, 0.95, 1.0), 1.5, true)
				draw_rect(Rect2(trc.position.x, yy, trc.size.x, trc.end.y - yy), Color(col.r, col.g, col.b, 0.18))
		if not ship.beam_in_range:
			draw_arc(ship.global_position, GameState.stat("rebuild_range"), 0.0, TAU, 64, Color(col.r, col.g, col.b, 0.25), 1.0, true)

	for b in bursts:
		var f: float = 1.0 - b["life"] / b["max"]
		var c: Color = b["color"]
		var rr: float = b["r"] * (0.4 + 0.6 * f)
		var a: float = (1.0 - f)
		Style.sunburst(self, b["pos"], rr, b["spikes"], b["rot"], Color(c.r, c.g, c.b, a), 2.0)
		draw_circle(b["pos"], rr * 0.28 * (1.0 - f), Color(1.0, 0.95, 0.8, a * 0.8))
	# iskry hurtem: dwa wywołania na wszystkie (przy setkach iskier to duża oszczędność)
	if not sparks_list.is_empty():
		var sp_a := PackedVector2Array()
		var sc_a := PackedColorArray()
		var sp_b := PackedVector2Array()
		var sc_b := PackedColorArray()
		for s in sparks_list:
			var p: Vector2 = s["pos"]
			if not view.has_point(p):
				continue
			var f: float = s["life"] / s["max"]
			var c: Color = s["color"]
			var v: Vector2 = s["vel"]
			sp_a.append_array([p, p - v * 0.05])
			var ca := Color(c.r, c.g, c.b, f)
			sc_a.append(ca)
			sp_b.append_array([p, p - v * 0.015])
			var cb := Color(1, 1, 1, f * 0.8)
			sc_b.append(cb)
		if not sp_a.is_empty():
			draw_multiline_colors(sp_a, sc_a, 2.0)
			draw_multiline_colors(sp_b, sc_b, 1.0)
	# odrzut plazmy: jasny stożek (bez triangulacji - wschód mapy ma duże współrzędne) i kule plazmy
	for j in jets:
		var f: float = j["life"] / j["max"]
		var d: Vector2 = j["dir"]
		var n := d.orthogonal()
		var p: Vector2 = j["pos"]
		var ln: float = j["len"] * (1.25 - 0.25 * f)
		var w: float = j["w"] * (1.3 - 0.3 * f)
		var tip := Color(1.4, 1.4, 1.5, 0.95 * f)
		var mid := Color(0.4, 1.1, 1.4, 0.55 * f)
		var end := Color(1.3, 0.3, 1.2, 0.0)
		draw_primitive(PackedVector2Array([p, p + d * ln * 0.5 + n * w * 0.6, p + d * ln, p + d * ln * 0.5 - n * w * 0.6]),
			PackedColorArray([tip, mid, end, mid]), PackedVector2Array())
		draw_line(p, p + d * ln * 0.7, Color(1.5, 1.5, 1.5, 0.8 * f), 3.0, true)
	for pl in plasma:
		if not view.has_point(pl["pos"]):
			continue
		var f: float = pl["life"] / pl["max"]
		var c: Color = pl["color"]
		draw_circle(pl["pos"], pl["r"] * 1.9, Color(c.r, c.g, c.b, 0.16 * f))
		draw_circle(pl["pos"], pl["r"], Color(c.r, c.g, c.b, 0.6 * f))
		draw_circle(pl["pos"], pl["r"] * 0.4, Color(1.5, 1.5, 1.5, 0.85 * f))
	for r in rings:
		var f: float = 1.0 - r["life"] / r["max"]
		var c: Color = r["color"]
		draw_arc(r["pos"], r["max_r"] * f, 0.0, TAU, 40, Color(c.r, c.g, c.b, (1.0 - f) * c.a), 2.0, true)
	for pk in pickups:
		var c: Color = pk["color"]
		var p: Vector2 = pk["pos"]
		var v: Vector2 = pk["vel"]
		if not p.is_finite() or not view.has_point(p):
			continue
		draw_line(p, p - v.normalized() * 8.0, Color(c.r, c.g, c.b, 0.5), 2.0, true)
		# czworokąt bez triangulacji: przy dużych współrzędnych (wschód mapy) Godot gubi małe wielokąty
		var dia := PackedVector2Array([p + Vector2(0, -3.5), p + Vector2(3.5, 0), p + Vector2(0, 3.5), p + Vector2(-3.5, 0)])
		draw_primitive(dia, PackedColorArray([c, c, c, c]), PackedVector2Array())
	for n in numbers:
		if not view.has_point(n["pos"]):
			continue
		var f: float = n["life"] / n["max"]
		var c: Color = n["color"]
		var age: float = n["max"] - n["life"]
		# "pop": przez pierwsze 0.08 s liczba jest większa
		var sz: int = int(n["size"] * (1.45 if age < 0.08 else 1.0))
		var a := clampf(f * 2.0, 0.0, 1.0)
		var tw := font.get_string_size(n["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var tp: Vector2 = n["pos"] - Vector2(tw * 0.5, 0)
		draw_string_outline(font, tp, n["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, a * 0.85))
		draw_string(font, tp, n["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(c.r, c.g, c.b, a))
	for t in texts:
		var f: float = clampf(t["life"] / 0.6, 0.0, 1.0)
		var c: Color = t["color"]
		var tp: Vector2 = t["pos"] - Vector2(font.get_string_size(t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x * 0.5, 0)
		draw_string_outline(font, tp, t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0.0, 0.0, 0.0, f * 0.85))
		draw_string(font, tp, t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(c.r, c.g, c.b, f))
