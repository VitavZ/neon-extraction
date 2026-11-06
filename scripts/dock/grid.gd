extends "res://scripts/dock/base.gd"
## Ekran statku matki, część 2/8: zakładka ULEPSZENIA STATKU - siatka węzłów, animacje, dymek z opisem.


func _draw_grid_view() -> void:
	grid_view.draw_set_transform(-grid_view.position)
	_draw_grid_on(grid_view)


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
		var hs := half * (1.0 + (0.1 * Style.ease_out(tip_t) if hov else 0.0) + 0.2 * f)
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
		var outline := Style.closed(plate)
		cv.draw_polyline(outline, Color(border.r, border.g, border.b, 0.25), (rim + 3.0) * w, true)
		cv.draw_polyline(outline, border, rim * w, true)
		if st == "max":
			cv.draw_polyline(Style.closed(_octagon(p, hs - 4.0 * w)), Color(Style.GOLD.r, Style.GOLD.g, Style.GOLD.b, 0.4), 1.0, true)

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
			cv.draw_polyline(Style.closed(_octagon(p, half + 2.0 + wave * 10.0 * z)), Color(C_LINE_ON.r, C_LINE_ON.g, C_LINE_ON.b, 0.32 * (1.0 - wave)), 1.0, true)
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
			var hs := half * (1.0 + 0.1 * Style.ease_out(tip_t))
			var hr := Rect2(p - Vector2(hs, hs), Vector2(hs, hs) * 2.0).grow((5.0 + 2.5 * sin(time * 7.0)) * z)
			var arm := hr.size.x * 0.2
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
				var cp: Vector2 = hr.position + hr.size * corner
				var sx := 1.0 if corner.x == 0.0 else -1.0
				var sy := 1.0 if corner.y == 0.0 else -1.0
				cv.draw_line(cp, cp + Vector2(arm * sx, 0), Style.CYAN, 2.0)
				cv.draw_line(cp, cp + Vector2(0, arm * sy), Style.CYAN, 2.0)


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
		if GameState.has_mastery(u) and lv == mx - 1:
			rows.append(["OSTATNI POZIOM: PREMIA MISTRZOSTWA (OK. +25%)", Style.GOLD, 12])
	elif GameState.has_mastery(u) and lv >= mx:
		rows.append(["MISTRZOSTWO: EFEKT OK. +25%", Style.GOLD, 12])
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
	pos.y += (1.0 - Style.ease_out(tip_t)) * 10.0
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
	draw_polyline(Style.closed(_octagon(Vector2(lx + 6, ly - 5), 6.5)), Upgrades.CAT_COLORS["defense"], 1.6, true)
	_text(Vector2(lx + 18, ly), "KUPIONE", 11, Style.TEXT_DIM)
	lx += 100
	draw_polyline(Style.closed(_octagon(Vector2(lx + 6, ly - 5), 6.5)), Style.GOLD, 1.6, true)
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
