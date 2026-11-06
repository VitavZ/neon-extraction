extends "res://scripts/dock/panels.gd"
## Ekran statku matki, część 4/8: zakładka ZBROJOWNIA (karty broni i ich ulepszenia).


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
		draw_colored_polygon(Style.chamfer_pts(card, 14.0), Color(cc.r * 0.04, cc.g * 0.04, cc.b * 0.06 + 0.03, 0.96))
		_hud_panel(self, card, cc, Color(0, 0, 0, 0), 14.0)

		# nagłówek: ikona w ośmiokącie, nazwa, stan
		var head := Rect2(card.position + Vector2(10, 10), Vector2(card.size.x - 20, 64))
		draw_rect(head, Color(cc.r * 0.12, cc.g * 0.12, cc.b * 0.14, 0.9))
		draw_line(Vector2(head.position.x, head.end.y), Vector2(head.end.x, head.end.y), Color(cc.r, cc.g, cc.b, 0.5), 1.5)
		var ic := head.position + Vector2(34, 32)
		var oct := _octagon(ic, 24.0)
		draw_colored_polygon(oct, Color(cc.r * 0.15, cc.g * 0.15, cc.b * 0.18, 1.0))
		draw_polyline(Style.closed(oct), cc, 2.0, true)
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
			var bp := Style.chamfer_pts(br.grow(2.0 if hov else 0.0), 10.0)
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
			var plate := Style.chamfer_pts(rr.grow(2.0 if hov else 0.0), 9.0)
			draw_colored_polygon(plate, fill)
			plate.append(plate[0])
			draw_polyline(plate, Color(border.r, border.g, border.b, 1.0 if hov else 0.8), 2.0 if hov else 1.3, true)
			if f > 0.0:
				draw_polyline(Style.chamfer_pts(rr.grow(4.0 + (1.0 - f) * 10.0), 9.0), Color(wc.r, wc.g, wc.b, f), 2.0, true)
			# ikona
			var uc := rr.position + Vector2(26, 35)
			var uo := _octagon(uc, 16.0)
			draw_colored_polygon(uo, Color(border.r * 0.15, border.g * 0.15, border.b * 0.15, 1.0))
			draw_polyline(Style.closed(uo), border, 1.5, true)
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
