extends "res://scripts/dock/armory.gd"
## Ekran statku matki, część 5/8: zakładka STEROWNIA (mapa sektorów, przenoszenie Statku Matki).


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
			var cname: String = GameState.city_name(s)
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
