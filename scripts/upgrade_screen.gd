extends "res://scripts/dock/lab.gd"
## Ekran statku matki, część 8/8: cykl życia (open, _process), obsługa wejścia i główne _draw.
## Ekran: siatka ulepszeń, zbrojownia, sterownia, laboratorium, imperium, magazyn, wylot. Rysowany wektorowo.
## Reszta kodu w scripts/dock/ (łańcuch extends: base -> grid -> panels -> armory -> bridge -> empire -> lab -> ten plik).


func _ready() -> void:
	font = Style.font()
	font_b = Style.font_bold()
	pf = Style.font_pixel()
	GameState.bank_changed.connect(func(): nodes_dirty = true)
	GameState.stats_changed.connect(func(): nodes_dirty = true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	grid_view = Control.new()
	grid_view.clip_contents = true
	grid_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grid_view)
	grid_view.draw.connect(_draw_grid_view)
	# płytki i napisy rysują się tylko po zmianie, a co klatkę tylko ta cienka warstwa animacji
	grid_fx = Control.new()
	grid_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_view.add_child(grid_fx)
	grid_fx.draw.connect(_draw_grid_fx)
	# dymek z opisem nad wszystkim (osobna warstwa, żeby nie chował się pod węzłami)
	tip_view = Control.new()
	tip_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(tip_view)
	tip_view.draw.connect(_draw_tip_view)


func open(unloaded: Dictionary, status: String) -> void:
	last_unload = unloaded
	status_text = status
	reset_armed = false
	visible = true
	open_t = 0.0
	overlay = ""
	overlay_k = 0.0
	# liczniki startują sprzed rozładunku i doliczają się na oczach gracza
	for k in GameState.RES_ORDER:
		disp[k] = maxf(0.0, float(GameState.bank.get(k, 0)) - float(unloaded.get(k, 0)))
	if GameState.empire_unlocked() and not GameState.empire_seen and not empire_announced:
		empire_announced = true
		toasts.append({"line1": "NOWA ZAKŁADKA NA STATKU MATCE", "line2": "IMPERIUM", "t": 0.0})


func _process(delta: float) -> void:
	if not visible:
		return
	time += delta
	if nodes_dirty:
		_refresh_nodes()
	open_t = minf(open_t + delta, OPEN_LEN)
	tab_t = minf(tab_t + delta * 2.6, 1.0)
	overlay_t += delta
	overlay_k = move_toward(overlay_k, 1.0 if overlay != "" else 0.0, delta * 4.0)
	var tip_now: String = hovered.get("id", "")
	if tip_now != tip_id:
		tip_id = tip_now
		tip_t = 0.0
	tip_t = minf(tip_t + delta * 7.0, 1.0)
	_update_pl_fx(delta)
	picker_t += delta
	if not toasts.is_empty() and open_t >= OPEN_LEN:
		toasts[0]["t"] += delta
		if toasts[0]["t"] > 3.5:
			toasts.pop_front()
	if open_t > 0.75:
		for k in GameState.RES_ORDER:
			var goal := float(GameState.bank.get(k, 0))
			var cur: float = disp.get(k, goal)
			disp[k] = move_toward(cur, goal, maxf(absf(goal - cur) * 5.0, 12.0) * delta)
	var gr := _grid_view_rect()
	grid_view.position = gr.position
	grid_view.size = gr.size
	grid_view.visible = tab == "grid"
	grid_view.modulate.a = clampf((open_t - 0.35) / 0.4, 0.0, 1.0)
	grid_fx.size = gr.size
	if grid_view.visible:
		grid_fx.queue_redraw()
		if grid_force or tip_t < 1.0 or not flash.is_empty() or view_offset != drawn_offset or view_zoom != drawn_zoom or gr != drawn_rect:
			grid_force = false
			drawn_offset = view_offset
			drawn_zoom = view_zoom
			drawn_rect = gr
			grid_view.queue_redraw()
	tip_view.queue_redraw()
	for k in flash.keys():
		flash[k] -= delta
		if flash[k] <= 0.0:
			flash.erase(k)
			grid_force = true
	queue_redraw()


# ---------------- układ ----------------


func _unhandled_input(event: InputEvent) -> void:
	if visible:
		if GameState.key_hit(event, "center"):
			reset_view()
		elif GameState.key_hit(event, "params"):
			_toggle_overlay("stats")


## ESC najpierw zamyka nakładkę, dopiero potem otwiera pauzę.
func _input(event: InputEvent) -> void:
	if visible and overlay != "" and GameState.key_hit(event, "pause"):
		overlay = ""
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var ga := _grid_area()
	if event is InputEventMouseMotion:
		mouse_pos = event.position
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _stats_rect().has_point(event.position):
				_toggle_overlay("stats")
				return
			if _brief_rect().has_point(event.position):
				_toggle_overlay("brief")
				return
			if overlay == "brief":
				for h in claim_hits:
					if h[0].has_point(event.position):
						_claim(h[1], h[0].get_center())
						return
		if overlay == "brief" and _over_overlay(event.position):
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_brief(1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_brief(-1)
		# nakładka zasłania to, co pod nią
		if _over_overlay(event.position):
			return
	# zakładki
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var tl := _tabs()
		for k in tl.size():
			if _tab_rect(k).has_point(event.position):
				if tab != tl[k]:
					tab_t = 0.0
				tab = tl[k]
				if tab == "empire":
					GameState.empire_seen = true
				Audio.play("ui_click", 0.0)
				hovered = {}
				dragging = false
				return
	if not tab in _tabs():
		tab = "grid"
	if tab == "bridge":
		_bridge_input(event)
		return
	if tab == "empire" and event is InputEventMouseButton and event.pressed and not _over_overlay(event.position):
		# otwarta lista surowców: wybór albo zamknięcie klikiem obok
		if res_picker >= 0:
			for h in picker_hits:
				if h[0].has_point(event.position):
					GameState.miner_res[res_picker] = h[1]
					Audio.play("ui_click", 0.0)
			res_picker = -1
			return
		for h in project_hits:
			if h[0].has_point(event.position):
				if emp_section != h[1]:
					emp_section = h[1]
					Audio.play("ui_click", 0.0)
				return
		for h in miner_hits:
			if h[0].has_point(event.position):
				res_picker = h[1]
				picker_t = 0.0
				Audio.play("ui_click", 0.0)
				return
	if tab == "armory" or tab == "lab" or tab == "empire":
		_armory_input(event)
		return
	if event is InputEventMouseMotion:
		var mp: Vector2 = event.position
		if dragging:
			view_offset += event.relative
			drag_moved += event.relative.length()
		hovered = {}
		if _grid_view_rect().has_point(mp) and not dragging and not _over_overlay(mp):
			for u in vis_nodes:
				if mp.distance_to(_node_pos(u)) < _node_r() + 4:
					hovered = u
					break
		hover_launch = _launch_rect().has_point(mp)
		hover_reset = _reset_rect().has_point(mp)
	elif event is InputEventMouseButton:
		var mp: Vector2 = event.position
		if event.pressed and ga.has_point(mp):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(mp, 1.12)
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(mp, 1.0 / 1.12)
				return
		# przeciąganie: prawy/środkowy przycisk zawsze, lewy - na pustym miejscu siatki
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			dragging = event.pressed and ga.has_point(mp)
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if not event.pressed:
			dragging = false
			return
		if hover_launch:
			Audio.play("ui_click", 0.0)
			launch_requested.emit()
		elif hover_reset:
			_go_menu()
		elif _center_view_rect().has_point(mp):
			reset_view()
		elif not hovered.is_empty():
			if (GameState.buy_max(hovered) > 0 if event.shift_pressed else GameState.buy(hovered)):
				flash[hovered["id"]] = 0.6
				Audio.play("buy", 0.0)
			else:
				Audio.play("error", 0.0)
			reset_armed = false
		elif ga.has_point(mp):
			dragging = true
			drag_moved = 0.0


func _draw() -> void:
	var vs := get_viewport_rect().size
	_draw_background(vs)
	if not tab in _tabs():
		tab = "grid"
	if tab == "grid":
		_draw_grid()
	elif tab == "armory":
		_draw_armory()
	elif tab == "bridge":
		_draw_bridge()
	elif tab == "empire":
		_draw_empire()
	else:
		_draw_lab()
	_draw_tabs()
	_draw_top_bar(vs)
	_draw_rail(vs)


func _draw_tip_view() -> void:
	_draw_tab_wipe(tip_view)
	_draw_overlay(tip_view)
	_draw_toast(tip_view)
	_draw_pl_fx(tip_view)
	_draw_res_picker(tip_view)
	if tab == "grid" and not hovered.is_empty() and _grid_view_rect().has_point(mouse_pos):
		_draw_tooltip(tip_view, hovered)
	elif (tab == "armory" or tab == "lab" or tab == "empire") and not hovered.is_empty() and res_picker < 0:
		_draw_tooltip(tip_view, hovered)
	_draw_iris(tip_view, get_viewport_rect().size)
