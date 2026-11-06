extends "res://scripts/world/base.gd"
## Mapa świata, część 2/5: rysowanie kafelków (statyczne paint_terrain używa też menu), kawałki mapy i minimapa.


func _mini_color(i: int) -> Color:
	if turrets.has(i) and turrets[i].get("kind", "") == "missile":
		return Color(1.0, 0.0, 0.0)
	match layer[i]:
		L_CRATER:
			var base: Color = MINI_COLORS[surface[i]]
			var g := 0.2 + base.get_luminance() * 0.22
			return Color(g, g, g * 1.08)
		L_IMPERIAL:
			return Color(0.95, 0.72, 0.25)
		L_DEPOSIT:
			# złoża przygaszone, żeby nie zamieniały mapy w konfetti
			var c: Color = DEP_DEFS[deposit[i]]["color"]
			return Color(minf(c.r, 1.0) * 0.72, minf(c.g, 1.0) * 0.72, minf(c.b, 1.0) * 0.72)
	return MINI_COLORS[surface[i]]


func _build_minimap() -> void:
	# cały obraz naraz: tysiące set_pixel wyraźnie wydłużały wczytywanie
	var data := PackedByteArray()
	data.resize(TOTAL * 4)
	for i in TOTAL:
		var c := _mini_color(i)
		var o := i * 4
		data[o] = c.r8
		data[o + 1] = c.g8
		data[o + 2] = c.b8
		data[o + 3] = 255
	minimap_img = Image.create_from_data(N, H, false, Image.FORMAT_RGBA8, data)
	if minimap_tex == null:
		minimap_tex = ImageTexture.create_from_image(minimap_img)
	else:
		minimap_tex.set_image(minimap_img)


func _update_minimap_pixel(i: int) -> void:
	minimap_img.set_pixel(i % N, i / N, _mini_color(i))
	_minimap_dirty = true


# =====================================================================
# RYSOWANIE
# =====================================================================


func _draw_chunk(ci: Node2D, cx: int, cy: int) -> void:
	# fragmenty daleko od kamery nie mają siatki (Godot rysuje każdy węzeł raz po wejściu do drzewa)
	if chunk_ready[cy * CHUNK_COLS + cx] == 0:
		return
	# wszystkie kształty fragmentu -> jedna siatka trójkątów -> jedno wywołanie rysowania
	var k := cy * CHUNK_COLS + cx
	if not tile_meshes.has(k):
		var empty: Array = []
		empty.resize(CHUNK * CHUNK)
		tile_meshes[k] = empty
	var cache: Array = tile_meshes[k]
	var mp = MeshPainter.new()
	for ly in CHUNK:
		for lx in CHUNK:
			var entry = cache[ly * CHUNK + lx]
			if entry == null:
				# każdy kafelek pamięta swoje trójkąty, więc po zniszczeniu liczony jest tylko on
				var one = MeshPainter.new()
				_draw_tile(one, cx * CHUNK + lx, cy * CHUNK + ly)
				entry = [one.verts, one.cols]
				cache[ly * CHUNK + lx] = entry
			mp.verts.append_array(entry[0])
			mp.cols.append_array(entry[1])
	var m: ArrayMesh = mp.build_mesh()
	# siatkę trzeba trzymać w pamięci, inaczej zniknie po wyjściu z funkcji
	ci.set_meta("mesh", m)
	if m:
		ci.draw_mesh(m, null)


func _draw_tile(ci, x: int, y: int) -> void:
	var i := y * N + x
	var r := Rect2(x * T, y * T, T, T)
	var h := _hash(x, y)
	var o := r.position
	var l := layer[i]

	if l == L_DEPOSIT:
		var dc: Color = DEP_DEFS[deposit[i]]["color"]
		ci.draw_rect(r, Color(0.06, 0.02, 0.07))
		ci.draw_rect(r, Color(dc.r, dc.g, dc.b, 0.12))
		_draw_crystals(ci, r, dc, h)
		ci.draw_rect(r.grow(-1.5), Color(dc.r * 0.6, dc.g * 0.6, dc.b * 0.6, 0.9), false, 1.5)
		return

	paint_terrain(ci, r, surface[i], h, _hash(x * 31, y * 17), l == L_IMPERIAL, l == L_CRATER)
	if l != L_SURFACE:
		return
	if abducted[i] == 1:
		# pole, z którego już porwano istoty
		ci.draw_arc(o + Vector2(8, 8), 4.0, 0.0, TAU, 10, Color(0.6, 0.9, 0.7, 0.55), 1.2, true)
		ci.draw_line(o + Vector2(5, 11), o + Vector2(11, 5), Color(0.6, 0.9, 0.7, 0.55), 1.2, true)


## Sam wygląd kafelka: tło, źdźbła, ikona i rama. Bez stanu świata, więc korzysta z tego też menu główne.
static func paint_terrain(ci, r: Rect2, t: int, h: int, hh: int, imp: bool, dead: bool) -> void:
	var o := r.position
	var def: Dictionary = TILE_DEFS[t]
	var lc: Color = def["line"]
	lc = Color(lc.r * 0.62, lc.g * 0.62, lc.b * 0.62)
	# zniszczony kafelek to ten sam teren, tylko wyszarzony i nieaktywny
	if dead:
		lc = _greyed(lc, 0.8)
	# ciemne, przygaszone tło terenu - na nim jedna wyraźna, świecąca ikona (styl Agrivore)
	var fl: Color = def["fill"]
	var base_fill := Color(fl.r * 0.38, fl.g * 0.38, fl.b * 0.38)
	if dead:
		var v := 0.095 + fl.get_luminance() * 0.25
		base_fill = Color(v, v, v * 1.05)
	ci.draw_rect(r, IMP_FILL if imp else base_fill)
	# drobne "źdźbła" w tle, żeby teren nie był płaski
	var dc2 := Color(lc.r, lc.g, lc.b, 0.18) if not imp else Color(IMP_PINK.r, IMP_PINK.g, IMP_PINK.b, 0.3)
	for k in 2:
		var dp := o + Vector2(5 + (hh >> (k * 5)) % 38, 6 + (hh >> (k * 5 + 3)) % 36)
		ci.draw_line(dp, dp + Vector2(2, -3), dc2, 1.0)
	var c := r.get_center() + Vector2(((h >> 2) % 5) - 2, ((h >> 5) % 5) - 2)
	_draw_terrain_icon(ci, t, c, h, imp, dead)
	if imp:
		_draw_imperial_frame(ci, r)
		return
	# siatka
	ci.draw_rect(r, Color(lc.r * 0.4, lc.g * 0.4, lc.b * 0.4, 0.3), false, 1.0)


# =====================================================================
# KAFELKI IMPERIUM (odbudowane) - osobny, geometryczny styl: złoto + fiolet + cyjan
# =====================================================================


static func _draw_imperial_frame(ci, r: Rect2) -> void:
	# neonowa rama ze ściętymi narożnikami: szeroka poświata i ostra linia
	var rr := r.grow(-2.5)
	var cut := 6.0
	var frame := PackedVector2Array([
		rr.position + Vector2(cut, 0), Vector2(rr.end.x - cut, rr.position.y), Vector2(rr.end.x, rr.position.y + cut),
		Vector2(rr.end.x, rr.end.y - cut), Vector2(rr.end.x - cut, rr.end.y), Vector2(rr.position.x + cut, rr.end.y),
		Vector2(rr.position.x, rr.end.y - cut), rr.position + Vector2(0, cut), rr.position + Vector2(cut, 0)])
	ci.draw_polyline(frame, Color(IMP_PINK.r, IMP_PINK.g, IMP_PINK.b, 0.22), 4.0, true)
	ci.draw_polyline(frame, IMP_PINK, 1.3, true)

# =====================================================================
# IKONY TERENU (styl Agrivore: wypełniony kształt + neonowy obrys + odblask)
# =====================================================================


static func _poly(ci, pts: PackedVector2Array, fill: Color, line: Color, w := 1.5) -> void:
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, line, w, true)


## Szara wersja koloru, przyciemniona o podany mnożnik.
static func _greyed(col: Color, k: float) -> Color:
	var v := minf(col.get_luminance(), 1.0) * k
	return Color(v, v, v * 1.05, col.a)


static func _draw_terrain_icon(ci, t: int, c: Vector2, h: int, imp: bool, dead := false) -> void:
	var cols: Array = ICON_COLS[t]
	var fill: Color = cols[0]
	var line: Color = cols[1]
	var acc: Color = cols[2]
	var shine := Color(1, 1, 1, 0.5)
	if imp:
		fill = Color(0.3, 0.03, 0.3)
		line = IMP_PINK
		acc = IMP_CYAN
		shine = Color(IMP_CYAN.r, IMP_CYAN.g, IMP_CYAN.b, 0.6)
	elif dead:
		fill = _greyed(fill, 0.55)
		line = _greyed(line, 0.68)
		acc = _greyed(acc, 0.6)
		shine = Color(0.5, 0.5, 0.52, 0.25)
	var s := 14.0
	match t:
		FOREST:
			# choinka (czasem dwie mniejsze)
			var trees := [Vector2.ZERO] if h % 4 != 0 else [Vector2(-7, 2), Vector2(7, -1)]
			var sc := 1.0 if trees.size() == 1 else 0.72
			for tp in trees:
				var b: Vector2 = c + tp
				var k := s * sc
				ci.draw_rect(Rect2(b + Vector2(-0.14, 0.55) * k, Vector2(0.28, 0.4) * k), acc if not imp else line)
				_poly(ci, PackedVector2Array([b + Vector2(0, -0.2) * k, b + Vector2(0.85, 0.62) * k, b + Vector2(-0.85, 0.62) * k]), fill, line)
				_poly(ci, PackedVector2Array([b + Vector2(0, -1.0) * k, b + Vector2(0.62, -0.05) * k, b + Vector2(-0.62, -0.05) * k]), fill, line)
				ci.draw_line(b + Vector2(-0.15, -0.6) * k, b + Vector2(-0.4, -0.2) * k, shine, 1.2)
		PLAINS:
			# kępka trawy z kłosem
			for k in 5:
				var x := (k - 2) * 0.32
				var hgt := 0.55 + 0.35 * float((h >> k) & 1)
				_poly(ci, PackedVector2Array([c + Vector2(x - 0.12, 0.7) * s, c + Vector2(x + 0.12, 0.7) * s, c + Vector2(x + x * 0.4, 0.7 - hgt * 1.6) * s]), fill, line, 1.1)
			if h % 3 == 0:
				ci.draw_circle(c + Vector2(0.1, -0.75) * s, 2.6, acc)
		SAND:
			# wydma z kamyczkami
			var dune := PackedVector2Array()
			for k in 11:
				var a := PI + k / 10.0 * PI
				dune.append(c + Vector2(cos(a) * 0.95, sin(a) * 0.6 + 0.45) * s)
			_poly(ci, dune, fill, line)
			ci.draw_circle(c + Vector2(-0.3, 0.2) * s, 1.6, acc)
			ci.draw_circle(c + Vector2(0.35, 0.3) * s, 1.3, acc)
			ci.draw_line(c + Vector2(-0.5, -0.05) * s, c + Vector2(-0.15, -0.12) * s, shine, 1.2)
		RIVER:
			# kropla wody
			var drop := PackedVector2Array([c + Vector2(0, -1.0) * s])
			for k in 13:
				var a := -0.25 * PI + k / 12.0 * 1.5 * PI
				drop.append(c + Vector2(cos(a), sin(a)) * 0.62 * s + Vector2(0, 0.25) * s)
			_poly(ci, drop, fill, line)
			ci.draw_arc(c + Vector2(-0.15, 0.3) * s, 0.32 * s, PI * 0.6, PI * 1.1, 6, acc, 1.6, true)
		OCEAN, DEEP:
			# fala (głęboki ocean: dwie ciemniejsze)
			var rows := 1 if t == OCEAN else 2
			for k in rows:
				var oy := (0.0 if rows == 1 else (k - 0.5) * 0.75) * s
				var wv := PackedVector2Array()
				for j in 9:
					var xx := -1.0 + j * 0.25
					wv.append(c + Vector2(xx * s, oy + sin(j * 0.8) * 0.28 * s))
				for j in range(8, -1, -1):
					var xx := -1.0 + j * 0.25
					wv.append(c + Vector2(xx * s, oy + sin(j * 0.8) * 0.28 * s + 0.32 * s))
				_poly(ci, wv, fill, line, 1.2)
				ci.draw_circle(c + Vector2(0.55 * s, oy - 0.05 * s), 1.6, acc)
		MOUNTAIN, SNOW:
			# góra z cienistą stroną (+ śnieżna czapa)
			var top := c + Vector2(0, -1.0) * s
			var lft := c + Vector2(-1.0, 0.75) * s
			var rgt := c + Vector2(1.0, 0.75) * s
			_poly(ci, PackedVector2Array([top, rgt, lft]), fill, line)
			ci.draw_colored_polygon(PackedVector2Array([top, rgt, c + Vector2(0.1, 0.75) * s]), Color(acc.r, acc.g, acc.b, 0.55) if t == MOUNTAIN else Color(0.2, 0.15, 0.3, 0.45))
			if t == SNOW or imp:
				var cap_c := acc if imp or dead else Color(1, 1, 1)
				_poly(ci, PackedVector2Array([top, c + Vector2(0.38, -0.42) * s, c + Vector2(0.1, -0.3) * s, c + Vector2(-0.12, -0.45) * s, c + Vector2(-0.38, -0.42) * s]), cap_c, line, 1.0)
			ci.draw_polyline(PackedVector2Array([top, lft, rgt, top]), line, 1.6, true)
		CAPITOL:
			# kopuła Kapitolu na kolumnadzie
			_poly(ci, PackedVector2Array([c + Vector2(-0.95, 0.85) * s, c + Vector2(0.95, 0.85) * s, c + Vector2(0.95, 0.55) * s, c + Vector2(-0.95, 0.55) * s]), fill, line, 1.2)
			for k in 4:
				var cx := -0.65 + k * 0.43
				ci.draw_line(c + Vector2(cx, 0.55) * s, c + Vector2(cx, 0.0) * s, line, 1.4)
			_poly(ci, PackedVector2Array([c + Vector2(-0.85, 0.0) * s, c + Vector2(0.85, 0.0) * s, c + Vector2(0.7, -0.15) * s, c + Vector2(-0.7, -0.15) * s]), fill, line, 1.2)
			var dome := PackedVector2Array()
			for k in 9:
				dome.append(c + Vector2(cos(PI + k / 8.0 * PI) * 0.5, -0.15 + sin(PI + k / 8.0 * PI) * 0.55) * s)
			_poly(ci, dome, fill, line, 1.3)
			ci.draw_line(c + Vector2(0, -0.7) * s, c + Vector2(0, -0.95) * s, acc, 1.6)
		PENTAGON:
			# pięciokąt z dziedzińcem
			var outer := PackedVector2Array()
			var inner := PackedVector2Array()
			for k in 5:
				var a := -PI * 0.5 + k / 5.0 * TAU
				outer.append(c + Vector2.from_angle(a) * 0.9 * s)
				inner.append(c + Vector2.from_angle(a) * 0.4 * s)
			_poly(ci, outer, fill, line, 1.5)
			_poly(ci, inner, Color(fill.r * 0.4, fill.g * 0.4, fill.b * 0.4), line, 1.2)
			ci.draw_circle(c, 1.8, acc)
		CITY, METRO:
			# trzy wieżowce z oknami
			var bx := [-0.85, -0.25, 0.35]
			var bw := [0.5, 0.55, 0.5]
			var bh := [1.1 + 0.3 * float(h & 1), 1.65, 0.9 + 0.3 * float((h >> 1) & 1)]
			for k in 3:
				var br := Rect2(c + Vector2(bx[k], 0.85 - bh[k]) * s, Vector2(bw[k], bh[k]) * s)
				ci.draw_rect(br, fill)
				ci.draw_rect(br, line, false, 1.4)
				var wy := br.position.y + 3.0
				var row := 0
				while wy < br.end.y - 3.0:
					if ((h >> (row + k * 3)) & 1) == 1:
						ci.draw_rect(Rect2(br.position.x + 2.0, wy, 2.0, 2.0), acc)
					if ((h >> (row + k * 3 + 1)) & 1) == 1:
						ci.draw_rect(Rect2(br.end.x - 4.0, wy, 2.0, 2.0), acc)
					wy += 4.5
					row += 1


func _draw_crystals(ci, r: Rect2, c: Color, h: int) -> void:
	# kryształy rudy: wypełnione klejnoty z odblaskiem
	var center := r.get_center() + Vector2(0, 2)
	var cc := Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0))
	var offs := [Vector2(-8, 3), Vector2(7, 4), Vector2(0, -4)]
	var sizes := [6.0, 6.5, 8.5]
	for k in 3:
		var p: Vector2 = center + offs[k] + Vector2(((h >> (k * 2)) % 3) - 1, 0)
		var sz: float = sizes[k]
		var gem := PackedVector2Array([p + Vector2(0, -sz * 1.3), p + Vector2(sz * 0.7, -sz * 0.2), p + Vector2(sz * 0.45, sz * 0.8), p + Vector2(-sz * 0.45, sz * 0.8), p + Vector2(-sz * 0.7, -sz * 0.2)])
		_poly(ci, gem, Color(cc.r * 0.55, cc.g * 0.55, cc.b * 0.55), c, 1.5)
		ci.draw_line(p + Vector2(0, -sz * 1.3), p + Vector2(0, sz * 0.8), Color(cc.r, cc.g, cc.b, 0.6), 1.0)
		ci.draw_line(p + Vector2(-sz * 0.35, -sz * 0.6), p + Vector2(-sz * 0.15, -sz * 0.95), Color(1, 1, 1, 0.8), 1.4)
