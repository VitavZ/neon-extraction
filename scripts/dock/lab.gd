extends "res://scripts/dock/empire.gd"
## Ekran statku matki, część 7/8: zakładka LABORATORIUM (badania).


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
