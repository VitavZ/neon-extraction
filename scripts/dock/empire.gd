extends "res://scripts/dock/bridge.gd"
## Ekran statku matki, część 6/8: zakładka IMPERIUM (flota wydobywcza, myśliwce Imperium, tranzyt, wybór surowca).


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
	draw_polyline(Style.closed(oct), gold, 2.0, true)
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
		var appear := Style.ease_out((tab_t - 0.1 - i * 0.15) / 0.5)
		r.position.y += (1.0 - appear) * 16.0
		_hud_panel(self, r, c, Color(c.r * 0.08, c.g * 0.08, c.b * 0.1, 0.94), 12.0)
		var ic := r.position + Vector2(40, 52)
		var o := _octagon(ic, 24.0)
		draw_colored_polygon(o, Color(c.r * 0.18, c.g * 0.18, c.b * 0.2))
		draw_polyline(Style.closed(o), c, 2.0, true)
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
		var pp := Style.chamfer_pts(pr, 8.0)
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
	var sp := Style.chamfer_pts(soon, 8.0)
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
	draw_polyline(Style.closed(o), gold, 2.0, true)
	Style.draw_icon(self, Style.icon_for(unlock["id"]), ic, 15.0, gold, 1.8)
	draw_string(pf, card.position + Vector2(100, 50), String(unlock["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, gold)
	draw_multiline_string(font, card.position + Vector2(100, 76), GameState.keys_text(String(unlock["desc"])), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 420, 12, 3, Color(0.85, 0.78, 0.6))
	var br := Rect2(card.end.x - 300, card.position.y + 44, 276, 56)
	var can := GameState.can_buy(unlock)
	var hov: bool = hovered.get("id", "") == unlock["id"]
	var bc: Color = C_BUY if can else Color(0.55, 0.45, 0.6)
	var bp := Style.chamfer_pts(br.grow(2.0 if hov else 0.0), 10.0)
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
		var p := Style.chamfer_pts(r, 9.0)
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
		var p := Style.chamfer_pts(r, 9.0)
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
		var p := Style.chamfer_pts(r, 9.0)
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
				var halo := Style.chamfer_pts(rr.grow(3.0 + g * 3.0), 11.0 + g * 2.0)
				halo.append(halo[0])
				draw_polyline(halo, Color(border.r, border.g, border.b, (0.28 - g * 0.08) * (0.6 + 0.4 * gp)), 2.0, true)
		var plate := Style.chamfer_pts(rr.grow(2.0 if hov else 0.0), 9.0)
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
			var tp := Style.chamfer_pts(tg, 5.0)
			draw_colored_polygon(tp, Color(0.16, 0.03, 0.12, 1.0))
			tp.append(tp[0])
			draw_polyline(tp, border, 1.4, true)
			Style.draw_icon(self, "star", tg.position + Vector2(13, 9), 5.0, Color(1.3, 1.0, 0.5), 1.3)
			draw_string(font_b, Vector2(tg.position.x + 24, tg.position.y + 13), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.3, 1.0, 0.5))
		var uc := rr.position + Vector2(26, 34)
		var uo := _octagon(uc, 16.0)
		draw_colored_polygon(uo, Color(border.r * 0.15, border.g * 0.15, border.b * 0.15))
		draw_polyline(Style.closed(uo), border, 1.5, true)
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
	var a := Style.ease_out(picker_t / 0.15)
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
