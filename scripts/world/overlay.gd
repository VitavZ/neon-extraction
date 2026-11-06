extends "res://scripts/world/defense.gd"
## Mapa świata, część 5/5: warstwy rysowane co klatkę - skaner, wieżyczki, okręgi zasięgu, granice sektorów, rakiety, napisy miast.


var _scan_pts := PackedVector2Array()
var _scan_cols := PackedColorArray()
var _scan_built_center := -1
var _scan_built_t := -10.0


func _draw_scan() -> void:
	var rad := int(GameState.stat("scanner"))
	if rad <= 0 or ship == null or ship.docked:
		return
	var ctr := pos_to_idx(ship.global_position)
	if ctr < 0:
		return
	# przeszukanie tylko po zmianie kafelka pod statkiem
	if ctr != scan_center:
		scan_center = ctr
		scan_tiles.clear()
		var cx := ctr % N
		var cy := ctr / N
		for y in range(maxi(0, cy - rad), mini(H, cy + rad + 1)):
			for x in range(maxi(0, cx - rad), mini(N, cx + rad + 1)):
				if (x - cx) * (x - cx) + (y - cy) * (y - cy) > rad * rad:
					continue
				var i := y * N + x
				if deposit[i] != 0:
					scan_tiles.append(i)
	# romby złóż jednym wywołaniem; geometria składana po zmianie kafelka pod statkiem albo co 0,5 s
	if ctr != _scan_built_center or time - _scan_built_t > 0.5:
		_scan_built_center = ctr
		_scan_built_t = time
		_scan_pts = PackedVector2Array()
		_scan_cols = PackedColorArray()
		var s := 7.0
		for i in scan_tiles:
			if layer[i] != L_SURFACE:
				continue
			var c: Color = DEP_DEFS[deposit[i]]["color"]
			var p := idx_center(i)
			var a := p + Vector2(0, -s)
			var b := p + Vector2(s, 0)
			var d := p + Vector2(0, s)
			var e := p + Vector2(-s, 0)
			_scan_pts.append_array([a, b, b, d, d, e, e, a])
			_scan_cols.append_array([c, c, c, c])
	if not _scan_pts.is_empty():
		scan_layer.draw_multiline_colors(_scan_pts, _scan_cols, 1.5)
	scan_layer.self_modulate.a = 0.6 + 0.4 * sin(time * 4.0)
	var sp: Vector2 = ship.global_position
	scan_layer.draw_arc(sp, rad * T + T * 0.5, 0.0, TAU, 64, Color(0.5, 0.17, 1.25, 0.25), 1.0, true)


func _draw_overlay() -> void:
	# przygaszenie mapy: lekkie przy szybkim locie, mocniejsze w walce, najmocniejsze w obu naraz
	var dim := minf(0.3 * speed_k + 0.38 * combat_k, 0.55)
	if dim > 0.004:
		var ivt := get_viewport().get_canvas_transform().affine_inverse()
		var tl0: Vector2 = ivt * Vector2.ZERO
		overlay.draw_rect(Rect2(tl0, (ivt * get_viewport_rect().size) - tl0).grow(60), Color(0.0, 0.0, 0.02, dim))
	# kafelki niedawno trafione: błysk + mały czerwony pasek HP pod spodem (jak w Agrivore)
	for i in recent_hits:
		var r := Rect2(Vector2((i % N) * T, (i / N) * T), Vector2(T, T))
		if tile_flash.get(i, 0.0) > 0.0:
			overlay.draw_rect(r, Color(1.0, 1.0, 1.0, 0.22))
		var frac := clampf(hp[i] / max(1.0, max_hp[i]), 0.0, 1.0)
		var a := clampf(recent_hits[i] / 0.4, 0.0, 1.0)
		var bar := Rect2(r.position + Vector2(7, T - 8), Vector2(T - 14, 4))
		overlay.draw_rect(bar.grow(1), Color(0.0, 0.0, 0.0, 0.8 * a))
		overlay.draw_rect(bar, Color(0.35, 0.02, 0.06, a))
		overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(1.0, 0.22, 0.32, a))
	# cel lasera: ramka w narożnikach
	if target_idx >= 0 and is_minable(target_idx):
		var r := Rect2(Vector2((target_idx % N) * T, (target_idx / N) * T), Vector2(T, T)).grow(2)
		var cl := Color(1.0, 1.0, 1.0, 0.9)
		var k := 10.0
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var sx: float = 1.0 if c.x == r.position.x else -1.0
			var sy: float = 1.0 if c.y == r.position.y else -1.0
			overlay.draw_line(c, c + Vector2(k * sx, 0), cl, 2.0)
			overlay.draw_line(c, c + Vector2(0, k * sy), cl, 2.0)

	# wieżyczki
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var vsz := get_viewport_rect().size
	var tl: Vector2 = inv * Vector2.ZERO
	var cam_rect := Rect2(tl, (inv * vsz) - tl).grow(40)
	# szkolenie to jeden obszar: bez granic sektorów USA i podpisów metropolii (Roswell rysuje training.gd)
	if not GameState.training:
		_draw_sector_borders(cam_rect)
		_draw_metro_last(cam_rect)
	# zwykłe wieżyczki rysowane hurtem: trzy wywołania na wszystkie zamiast pięciu na każdą
	var body_pts := PackedVector2Array()
	var body_col := PackedColorArray()
	var top_pts := PackedVector2Array()
	var top_col := PackedColorArray()
	var outline := PackedVector2Array()
	for i in turrets_in_rect(cam_rect):
		var tp := idx_center(i)
		if not cam_rect.has_point(tp):
			continue
		if turrets[i].get("kind", "") == "missile":
			_draw_missile_turret(tp, turrets[i], i)
			continue
		var t: Dictionary = turrets[i]
		var fill := Color(0.3, 0.02, 0.02, 0.9)
		for k in 6:
			var h0: Vector2 = tp + HEX_UNIT[k] * 11.0
			var h1: Vector2 = tp + HEX_UNIT[k + 1] * 11.0
			body_pts.append_array([tp, h0, h1])
			body_col.append_array([fill, fill, fill])
			outline.append_array([h0, h1])
		# lufa jako wąski prostokąt
		var dir := Vector2.from_angle(t["angle"])
		var nrm := dir.orthogonal() * 1.5
		var tip := tp + dir * 17.0
		var bc := Color(1.25, 0.45, 0.13)
		top_pts.append_array([tp + nrm, tip + nrm, tip - nrm, tp + nrm, tip - nrm, tp - nrm])
		top_col.append_array([bc, bc, bc, bc, bc, bc])
		# migająca kropka ostrzegawcza
		var warn := 0.3 + 0.3 * sin(time * 6.0 + i)
		var dc := Color(1.25, 0.09, 0.09, 0.6 + warn)
		for k in 6:
			top_pts.append_array([tp, tp + HEX_UNIT[k] * 3.2, tp + HEX_UNIT[k + 1] * 3.2])
			top_col.append_array([dc, dc, dc])
	if not body_pts.is_empty():
		var ci := overlay.get_canvas_item()
		RenderingServer.canvas_item_add_triangle_array(ci, _seq_indices(body_pts.size()), body_pts, body_col)
		overlay.draw_multiline(outline, Color(1.25, 0.22, 0.09), 1.8)
		RenderingServer.canvas_item_add_triangle_array(ci, _seq_indices(top_pts.size()), top_pts, top_col)
	_flush_rings(cam_rect)

	# wieżyczki Imperium i ich strzały
	for i in ally_turrets:
		var ap := idx_center(i)
		if not cam_rect.has_point(ap):
			continue
		var at: Dictionary = ally_turrets[i]
		var hx := PackedVector2Array()
		for k in 7:
			hx.append(ap + Vector2.from_angle(k / 6.0 * TAU + PI / 6.0) * 10.0)
		overlay.draw_colored_polygon(hx, Color(0.2, 0.12, 0.02, 0.95))
		overlay.draw_polyline(hx, Color(1.3, 0.9, 0.35), 1.8, true)
		overlay.draw_line(ap, ap + Vector2.from_angle(at["angle"]) * 16.0, Color(0.4, 1.1, 1.3), 3.0, true)
		overlay.draw_circle(ap, 3.0, Color(0.5, 1.2, 1.4))
	for sh in ally_shots:
		var sa: float = sh["life"] / 0.14
		overlay.draw_line(sh["a"], sh["b"], Color(0.4, 1.0, 1.3, 0.35 * sa), 5.0, true)
		overlay.draw_line(sh["a"], sh["b"], Color(1.2, 1.3, 1.4, sa), 1.6, true)

	# pociski: ciemna obwódka, czerwony żar i białe jądro - widać je na każdym kafelku
	for b in bullets:
		var p: Vector2 = b["pos"]
		var v: Vector2 = b["vel"].normalized()
		overlay.draw_circle(p, 8.0, Color(0.0, 0.0, 0.0, 0.6))
		overlay.draw_line(p - v * 16.0, p, Color(1.35, 0.2, 0.08, 0.75), 4.0, true)
		overlay.draw_circle(p, 5.0, Color(1.4, 0.3, 0.1))
		overlay.draw_circle(p, 2.2, Color(1.5, 1.4, 1.2))
	for m in missiles:
		_draw_missile(m)
	_draw_city_labels(cam_rect)


## Granice sektorów: delikatny, sunący pas świateł widoczny tylko, gdy statek jest blisko.
func _draw_sector_borders(_view: Rect2) -> void:
	if ship == null or ship.docked:
		return
	var sp: Vector2 = ship.global_position
	for k in range(1, Sectors.COLS):
		var x := float(k * Sectors.SIZE * T)
		var near := 1.0 - absf(sp.x - x) / BORDER_FADE
		if near > 0.0:
			_border_strip(Vector2(x, sp.y), Vector2(0, 1), near)
	for k in range(1, Sectors.ROWS):
		var y := float(k * Sectors.SIZE * T)
		var near := 1.0 - absf(sp.y - y) / BORDER_FADE
		if near > 0.0:
			_border_strip(Vector2(sp.x, y), Vector2(1, 0), near)
	# pole siłowe zamkniętych sektorów: pas wzdłuż każdej krawędzi graniczącej z resztą mapy
	for s in Sectors.LIST.size():
		if GameState.sector_open(s):
			continue
		var r: Rect2i = Sectors.sector_rect(s)
		var rp := Rect2(Vector2(r.position) * T, Vector2(r.size) * T)
		var fade := BORDER_FADE * 1.6
		var cx := clampf(sp.x, rp.position.x + 40.0, rp.end.x - 40.0)
		var cy := clampf(sp.y, rp.position.y + 40.0, rp.end.y - 40.0)
		if rp.position.y > 0.0:
			_barrier_strip(Vector2(cx, rp.position.y), Vector2(1, 0), 1.0 - absf(sp.y - rp.position.y) / fade, rp.position.x, rp.end.x)
		if rp.end.y < H * T:
			_barrier_strip(Vector2(cx, rp.end.y), Vector2(1, 0), 1.0 - absf(sp.y - rp.end.y) / fade, rp.position.x, rp.end.x)
		if rp.position.x > 0.0:
			_barrier_strip(Vector2(rp.position.x, cy), Vector2(0, 1), 1.0 - absf(sp.x - rp.position.x) / fade, rp.position.y, rp.end.y)
		if rp.end.x < N * T:
			_barrier_strip(Vector2(rp.end.x, cy), Vector2(0, 1), 1.0 - absf(sp.x - rp.end.x) / fade, rp.position.y, rp.end.y)


## Pole siłowe: czerwone, gęste pasy z poprzecznymi żebrami (lo/hi - granice krawędzi wzdłuż dir).
func _barrier_strip(center: Vector2, dir: Vector2, near: float, lo: float, hi: float) -> void:
	if near <= 0.0:
		return
	var a := near * near
	var span := BORDER_DASH * 10.0
	var along := center.dot(dir)
	var p0 := center + dir * (maxf(along - span, lo) - along)
	var p1 := center + dir * (minf(along + span, hi) - along)
	overlay.draw_line(p0, p1, Color(1.4, 0.1, 0.15, 0.12 * a), 40.0)
	overlay.draw_line(p0, p1, Color(1.5, 0.3, 0.3, 0.85 * a), 3.0)
	var n := dir.orthogonal()
	var scroll := fposmod(center.dot(dir) + time * 90.0, 48.0)
	for k in range(-20, 21):
		var q := center + dir * (k * 48.0 - scroll)
		var qa := q.dot(dir)
		if qa < lo or qa > hi:
			continue
		var f := clampf(1.0 - absf(k * 48.0) / span, 0.0, 1.0)
		overlay.draw_line(q - n * 14.0, q + n * 14.0, Color(1.4, 0.2, 0.2, 0.6 * a * f), 2.0)


func _border_strip(center: Vector2, dir: Vector2, near: float) -> void:
	var world_rect := Rect2(0.0, 0.0, N * T, H * T)
	var along := center.dot(dir)
	var scroll := fposmod(along + time * 60.0, BORDER_DASH)
	for n in range(-9, 10):
		var o := n * BORDER_DASH - scroll + BORDER_DASH * 0.5
		var f := clampf(1.0 - absf(o) / (BORDER_DASH * 8.5), 0.0, 1.0)
		var a := center + dir * o
		var b := a + dir * BORDER_DASH * 0.55
		if f <= 0.0 or not world_rect.has_point(a) or not world_rect.has_point(b):
			continue
		var alpha := near * near * f
		overlay.draw_line(a, b, Color(0.3, 0.9, 1.2, 0.14 * alpha), 14.0)
		overlay.draw_line(a, b, Color(0.5, 1.0, 1.3, 0.7 * alpha), 2.5)


## Wieżyczka rakietowa: duży, jaskrawoczerwony znak, pulsuje szybciej tuż przed strzałem.
func _draw_missile_turret(tp: Vector2, t: Dictionary, i: int) -> void:
	var soon: bool = t["cd"] < 1.2
	var pulse := 0.5 + 0.5 * sin(time * (14.0 if soon else 5.0) + i)
	var r := 19.0 + pulse * 2.5
	var dia := PackedVector2Array([tp + Vector2(0, -r), tp + Vector2(r, 0), tp + Vector2(0, r), tp + Vector2(-r, 0)])
	overlay.draw_colored_polygon(dia, Color(1.1 + pulse * 0.3, 0.03, 0.03))
	dia.append(dia[0])
	overlay.draw_polyline(dia, Color(1.5, 0.9, 0.8), 2.5, true)
	overlay.draw_arc(tp, 27.0 + pulse * 7.0, 0.0, TAU, 28, Color(1.4, 0.1, 0.1, 0.9 - pulse * 0.5), 2.5, true)
	# biała rakieta skierowana w stronę gracza
	var d := Vector2.from_angle(t["angle"])
	var n := d.orthogonal()
	overlay.draw_colored_polygon(PackedVector2Array([tp + d * 12.0, tp + n * 4.5, tp - d * 7.0 + n * 4.5, tp - d * 7.0 - n * 4.5, tp - n * 4.5]), Color(1.4, 1.4, 1.4))
	overlay.draw_line(tp - d * 7.0 + n * 7.0, tp - d * 7.0 - n * 7.0, Color(1.4, 1.4, 1.4), 2.0)


## Indeksy 0..n-1 dla tablic trójkątów (pamiętane, żeby nie budować ich co klatkę).
func _seq_indices(n: int) -> PackedInt32Array:
	if _idx_cache.size() < n:
		var old := _idx_cache.size()
		_idx_cache.resize(maxi(n, old * 2))
		for k in range(old, _idx_cache.size()):
			_idx_cache[k] = k
	return _idx_cache.slice(0, n)


## Zasięgi wrogich wieżyczek jako strefy chronione: zasięgi tego samego rodzaju zlewają się w jeden obszar
## z przezroczystym wypełnieniem i świecącym obrysem (zwykłe wieżyczki i rakietowe mają własne kolory).
## Pokazywane są wszystkie strefy, które wchodzą w kadr kamery.
## - Obrys: każda wieżyczka ma zapamiętane tylko te łuki swojego okręgu, które nie leżą w zasięgu sąsiadki
##   tego samego rodzaju (liczone raz; pamięć czyszczona, gdy zmieni się liczba wieżyczek).
## - Wypełnienie: nieprzezroczyste koła w CanvasGroup, a przezroczystość nadaje cała grupa - dzięki temu
##   nakładające się zasięgi nie ciemnieją, tylko tworzą jednolity obszar.
## - Strefy składane są najwyżej co 0,25 s albo gdy kamera przesunie się o 80 px; w pozostałych klatkach
##   rysuje się zapamiętane linie, a wypełnienie w ogóle nie jest przerysowywane.
const RING_CHORD := 18.0                  # długość odcinka obrysu w pikselach (gęsto = gładki łuk)
const RING_BUILDS_PER_FRAME := 16         # nowe obrysy liczone na klatkę (wlot do miasta nie zacina gry)
const RING_LINE := [Color(1.4, 0.32, 0.1), Color(0.95, 0.3, 1.5)]      # zwykłe (pomarańczowo-czerwone) / rakietowe (fioletowe)
const RING_FILL := [Color(1.0, 0.3, 0.08, 0.10), Color(0.6, 0.2, 1.0, 0.10)]
var _ring_arcs: Dictionary = {}           # indeks wieżyczki -> PackedVector2Array par końców odcinków
var _ring_arcs_n := -1                    # liczba wieżyczek, dla której liczono łuki
var _ring_stale: Dictionary = {}          # obrysy do przeliczenia (sąsiadki zniszczonej wieżyczki); do tego czasu rysuje się stary
var _ring_skip := false                   # ta klatka rysuje zapamiętane strefy
var _ring_pending := false                # część obrysów czeka na policzenie
var _ring_cache_pts: Array = [PackedVector2Array(), PackedVector2Array()]
var _ring_cache_t := -10.0
var _ring_cache_pos := Vector2.INF
var _fill_groups: Array = []              # 2 x CanvasGroup
var _fill_nodes: Array = []               # 2 x Node2D rysujące koła
var _fill_circles: Array = [PackedVector2Array(), PackedVector2Array()]


func _ring_outline(i: int, tp: Vector2, r: float) -> PackedVector2Array:
	if _ring_arcs.has(i):
		return _ring_arcs[i]
	var missile: bool = turrets[i].get("kind", "") == "missile"
	var others := PackedVector2Array()
	for j in turrets_in_rect(Rect2(tp - Vector2(r, r) * 2.0, Vector2(r, r) * 4.0)):
		if j != i and (turrets[j].get("kind", "") == "missile") == missile:
			var oc := idx_center(j)
			if oc.distance_squared_to(tp) < r * r * 4.0:
				others.append(oc)
	var rr := r * r - 1.0
	var n := maxi(24, int(TAU * r / RING_CHORD))
	var pts := PackedVector2Array()
	var ins := PackedByteArray()
	pts.resize(n + 1)
	ins.resize(n + 1)
	for k in n + 1:
		var p := tp + Vector2.from_angle(TAU * k / n) * r
		pts[k] = p
		var hit := 0
		for o in others:
			if p.distance_squared_to(o) < rr:
				hit = 1
				break
		ins[k] = hit
	var out := PackedVector2Array()
	for k in range(1, n + 1):
		var a_in := ins[k - 1] == 1
		var b_in := ins[k] == 1
		if a_in and b_in:
			continue
		var p0 := pts[k - 1]
		var p1 := pts[k]
		if a_in != b_in:
			# dokładny punkt styku dwóch zasięgów (połowienie kąta), żeby obrysy domykały się bez szpar
			var lo := TAU * (k - 1) / n
			var hi := TAU * k / n
			for it in 6:
				var mid := (lo + hi) * 0.5
				var mp := tp + Vector2.from_angle(mid) * r
				var m_in := false
				for o in others:
					if mp.distance_squared_to(o) < rr:
						m_in = true
						break
				if m_in == a_in:
					lo = mid
				else:
					hi = mid
			var edge := tp + Vector2.from_angle((lo + hi) * 0.5) * r
			if a_in:
				p0 = edge
			else:
				p1 = edge
		out.append(p0)
		out.append(p1)
	_ring_arcs[i] = out
	return out


## Zniszczona wieżyczka: jej obrys znika, a sąsiadki w zasięgu dostają obrys do przeliczenia (bez czyszczenia wszystkiego,
## żeby strzelanie w miasto nie powodowało migania stref).
func _ring_turrets_changed() -> void:
	_ring_arcs_n = turrets.size()
	var removed: Array = []
	for i in _ring_arcs.keys():
		if not turrets.has(i):
			removed.append(idx_center(i))
			_ring_arcs.erase(i)
			_ring_stale.erase(i)
	for p in removed:
		var reach := MISSILE_RANGE * 2.0
		for j in turrets_in_rect(Rect2(p - Vector2(reach, reach), Vector2(reach, reach) * 2.0)):
			if _ring_arcs.has(j):
				_ring_stale[j] = true


func _ensure_fill() -> void:
	if not _fill_groups.is_empty():
		return
	for g in 2:
		var grp := CanvasGroup.new()
		grp.z_index = 2
		grp.self_modulate = RING_FILL[g]
		add_child(grp)
		var node := Node2D.new()
		grp.add_child(node)
		node.draw.connect(_draw_fill.bind(g))
		_fill_groups.append(grp)
		_fill_nodes.append(node)


func _draw_fill(g: int) -> void:
	var r: float = MISSILE_RANGE if g == 1 else TURRET_RANGE
	var node: Node2D = _fill_nodes[g]
	for c in _fill_circles[g]:
		node.draw_circle(c, r, Color(1, 1, 1, 1))


func _flush_rings(view: Rect2) -> void:
	_ensure_fill()
	var on: bool = show_ranges and ship != null and not ship.docked
	for g in 2:
		_fill_groups[g].visible = on
	if not on:
		return
	var center := view.get_center()
	if not (_ring_pending or _ring_arcs_n != turrets.size() or time - _ring_cache_t >= 0.25 or center.distance_to(_ring_cache_pos) >= 80.0):
		_draw_ring_cache()
		return
	if _ring_arcs_n != turrets.size():
		_ring_turrets_changed()
	var q: Array = []
	for i in turrets_in_rect(view.grow(MISSILE_RANGE + T)):
		var tp := idx_center(i)
		var r: float = MISSILE_RANGE if turrets[i].get("kind", "") == "missile" else TURRET_RANGE
		if view.intersects(Rect2(tp - Vector2(r, r), Vector2(r, r) * 2.0)):
			q.append([tp.distance_squared_to(center), tp, r, i])
	# najbliższe środka kadru najpierw (sortowanie tylko, gdy są obrysy do policzenia)
	for e in q:
		if not _ring_arcs.has(int(e[3])) or _ring_stale.has(int(e[3])):
			q.sort_custom(func(x, y): return x[0] < y[0])
			break
	var pts := [PackedVector2Array(), PackedVector2Array()]
	var circles := [PackedVector2Array(), PackedVector2Array()]
	var builds := 0
	_ring_pending = false
	for e in q:
		var i: int = e[3]
		var g := 1 if float(e[2]) == MISSILE_RANGE else 0
		circles[g].append(e[1])
		if not _ring_arcs.has(i) or _ring_stale.has(i):
			if builds >= RING_BUILDS_PER_FRAME:
				_ring_pending = true
				if _ring_arcs.has(i):
					pts[g].append_array(_ring_arcs[i])   # stary obrys, dopóki nowy nie jest policzony
				continue
			builds += 1
			_ring_arcs.erase(i)
			_ring_stale.erase(i)
		pts[g].append_array(_ring_outline(i, e[1], e[2]))
	_ring_cache_pts = pts
	_ring_cache_t = time
	_ring_cache_pos = center
	for g in 2:
		if circles[g] != _fill_circles[g]:
			_fill_circles[g] = circles[g]
			_fill_nodes[g].queue_redraw()
	_draw_ring_cache()


func _draw_ring_cache() -> void:
	var pulse := 0.5 + 0.5 * sin(time * 3.0)
	for g in 2:
		var pts: PackedVector2Array = _ring_cache_pts[g]
		if pts.is_empty():
			continue
		var c: Color = RING_LINE[g]
		overlay.draw_multiline(pts, Color(c.r, c.g, c.b, 0.12), 12.0)
		overlay.draw_multiline(pts, Color(c.r, c.g, c.b, 0.5 + 0.2 * pulse), 2.5)


func _draw_missile(m: Dictionary) -> void:
	var p: Vector2 = m["pos"]
	var d := Vector2.from_angle(m["rot"])
	var n := d.orthogonal()
	var blink := 0.6 + 0.4 * sin(time * 24.0)
	overlay.draw_arc(p, 20.0, 0.0, TAU, 20, Color(1.4, 0.15, 0.1, 0.6 * blink), 2.0, true)
	overlay.draw_line(p - d * 12.0, p - d * (30.0 + randf() * 12.0), Color(1.4, 0.7, 0.2, 0.9), 4.0, true)
	overlay.draw_colored_polygon(PackedVector2Array([p + d * 15.0, p + n * 4.5, p - d * 11.0 + n * 4.5, p - d * 11.0 - n * 4.5, p - n * 4.5]), Color(1.3, 0.12, 0.1))
	overlay.draw_circle(p + d * 7.0, 2.5, Color(1.5, 1.4, 1.2))


## Ostatnie kafelki metropolii pulsują i drżą.
func _draw_metro_last(view: Rect2) -> void:
	for tiles in metro_last:
		for i in tiles:
			var p := idx_center(i)
			if not view.has_point(p):
				continue
			var pulse := 0.5 + 0.5 * sin(time * 9.0 + i)
			var r := Rect2(p - Vector2(T, T) * 0.5, Vector2(T, T))
			r.position += Vector2(sin(time * 33.0 + i), cos(time * 41.0 + i)) * 2.5
			overlay.draw_rect(r, Color(1.4, 0.2, 1.1, 0.14 + 0.3 * pulse))
			overlay.draw_rect(r.grow(2.0 + pulse * 3.0), Color(1.5, 0.5, 1.3, 0.5 + 0.5 * pulse), false, 2.5)


## Różowy punkt powrotu do walki z bossem.
func _draw_boss_portal(p: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(time * 4.0)
	var c := Color(1.5, 0.3, 1.2)
	overlay.draw_circle(p, BOSS_PORTAL_RADIUS * 0.8, Color(0.5, 0.02, 0.4, 0.45))
	for k in 3:
		var a := time * (1.3 + k * 0.5) * (1.0 if k % 2 == 0 else -1.0)
		var rad := BOSS_PORTAL_RADIUS * (0.5 + k * 0.25)
		for seg in 3:
			var s0 := a + seg * TAU / 3.0
			overlay.draw_arc(p, rad, s0, s0 + 1.4, 16, Color(c.r, c.g, c.b, 0.6 + 0.4 * pulse), 3.0, true)
	overlay.draw_circle(p, 12.0 + pulse * 6.0, Color(1.5, 1.2, 1.5))


## Podpisy metropolii na mapie.
func _draw_city_labels(view: Rect2) -> void:
	if GameState.training:
		return
	var font := Style.font_pixel()
	var fsize := 72
	for s in Sectors.LIST.size():
		var p := city_pos(s)
		if not view.grow(600.0).has_point(p):
			continue
		if GameState.boss_state(s) != "":
			_draw_boss_portal(p)
		var txt: String = GameState.city_name(s)
		if txt == "":
			continue
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var at := p + Vector2(-w * 0.5, 24.0)
		overlay.draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 14, Color(0.02, 0.0, 0.06, 0.92))
		overlay.draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1.3, 0.75, 1.2))
	# obiekty specjalne: mniejszy, złoto-czerwony podpis
	for k in landmark_cells.size():
		var p := landmark_pos(k)
		if not view.grow(600.0).has_point(p):
			continue
		var txt: String = Sectors.LANDMARKS[k]["name"]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x
		var at := p + Vector2(-w * 0.5, 16.0)
		overlay.draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 48, 12, Color(0.02, 0.0, 0.06, 0.92))
		overlay.draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(1.3, 0.85, 0.4))
