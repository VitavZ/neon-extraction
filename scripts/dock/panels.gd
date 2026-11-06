extends "res://scripts/dock/grid.gd"
## Ekran statku matki, część 3/8: oprawa (tło, hangar, górny pasek, zakładki, prawa szyna z magazynem, WYLOT),
## nakładki PARAMETRY / ROZKAZY, Punkty Lojalności w locie, komunikaty i przejścia.


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
