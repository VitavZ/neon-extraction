extends Control
## Pauza pod ESC: zatrzymuje grę (także walkę z bossem) i pozwala wrócić albo wyjść do menu.
## W locie można też przerwać wyprawę i wrócić na Statek Matkę. W obu przypadkach mapa zostaje,
## ale ładunek z bieżącej wyprawy przepada. OPCJE to te same ustawienia co w menu głównym.

signal quit_requested
signal return_requested

const Style = preload("res://scripts/style.gd")
const CrtScript = preload("res://scripts/crt.gd")
const ITEMS_DOCKED := ["WZNÓW", "OSIĄGNIĘCIA", "OPCJE", "MENU GŁÓWNE"]
const ITEMS_FLIGHT := ["WZNÓW", "POWRÓT NA STATEK MATKĘ", "OSIĄGNIĘCIA", "OPCJE", "MENU GŁÓWNE"]
const OPT_ITEMS := ["resolution", "fullscreen", "vsync", "volume", "music", "sfx", "quality", "comfort", "crt", "glow", "shake", "controls", "back"]
const OPT_NAMES := {
	"resolution": "ROZDZIELCZOŚĆ", "fullscreen": "TRYB EKRANU", "vsync": "V-SYNC", "volume": "GŁOŚNOŚĆ OGÓLNA", "music": "MUZYKA", "sfx": "EFEKTY DŹWIĘKOWE",
	"quality": "JAKOŚĆ OBRAZU", "comfort": "JASKRAWOŚĆ", "crt": "FILTR CRT", "glow": "POŚWIATA NEONÓW", "shake": "WSTRZĄSY EKRANU", "controls": "STEROWANIE", "back": "< WRÓĆ",
}

var pf: Font
var font: Font
var sel := 0
var time := 0.0
var appear := 0.0
var in_flight := false
var hits: Array = []           # [Rect2, akcja]: int = pozycja listy, String = strzałka / suwak
var was_paused := false
var screen := "main"           # main / achievements / options / controls
var rebinding := ""            # akcja czekająca na nowy klawisz
var crt: CanvasLayer           # ustawiane przez main: filtr CRT i poświata włączane od razu
var env: Environment


func _ready() -> void:
	pf = Style.font_pixel()
	font = Style.font()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open(flying: bool) -> void:
	in_flight = flying
	sel = 0
	appear = 0.0
	screen = "main"
	rebinding = ""
	visible = true
	was_paused = get_tree().paused
	get_tree().paused = true
	GameState.pause_menu = true
	Audio.stop_loops()
	Audio.play("ui_click", 0.0)


func close() -> void:
	visible = false
	rebinding = ""
	GameState.pause_menu = false
	# boss i samouczek same trzymają pauzę drzewa - nie zdejmujemy jej za nie
	get_tree().paused = was_paused
	Audio.play("ui_click", 0.0)


func _process(delta: float) -> void:
	if not visible:
		return
	time += delta
	appear = minf(1.0, appear + delta * 6.0)
	queue_redraw()


func _items() -> Array:
	return ITEMS_FLIGHT if in_flight else ITEMS_DOCKED


func _count() -> int:
	match screen:
		"options": return OPT_ITEMS.size()
		"controls": return GameState.KEY_ACTIONS.size() + 2
		"achievements": return 1
	return _items().size()


func _go(s: String, select := 0) -> void:
	screen = s
	sel = select
	rebinding = ""
	appear = minf(appear, 0.6)


func _back() -> void:
	match screen:
		"controls": _go("options", OPT_ITEMS.find("controls"))
		"options": _go("main", _items().find("OPCJE"))
		"achievements": _go("main", _items().find("OSIĄGNIĘCIA"))
		_: close()


func _activate(i: int) -> void:
	if screen == "achievements":
		Audio.play("ui_click", 0.0)
		_back()
		return
	if screen == "options":
		if OPT_ITEMS[i] == "back":
			Audio.play("ui_click", 0.0)
			_back()
		else:
			_change_option(OPT_ITEMS[i], 1)
		return
	if screen == "controls":
		Audio.play("ui_click", 0.0)
		var n: int = GameState.KEY_ACTIONS.size()
		if i < n:
			rebinding = GameState.KEY_ACTIONS[i][0]
		elif i == n:
			GameState.reset_keys()
			GameState.save_settings()
		else:
			_back()
		return
	var item: String = _items()[i]
	if item == "WZNÓW":
		close()
		return
	if item == "OPCJE":
		Audio.play("ui_click", 0.0)
		_go("options", 0)
		return
	if item == "OSIĄGNIĘCIA":
		Audio.play("ui_click", 0.0)
		_go("achievements", 0)
		return
	visible = false
	GameState.pause_menu = false
	get_tree().paused = false
	if item == "MENU GŁÓWNE":
		quit_requested.emit()
	else:
		return_requested.emit()


func _change_option(key: String, d: int) -> void:
	var st := GameState.settings
	match key:
		"controls":
			Audio.play("ui_click", 0.0)
			_go("controls", 0)
			return
		"resolution":
			st["resolution"] = posmod(int(st["resolution"]) + d, GameState.RESOLUTIONS.size())
		"volume", "music", "sfx":
			st[key] = clampi(int(st[key]) + d * 10, 0, 100)
		"fullscreen", "vsync", "crt", "glow", "shake":
			st[key] = not bool(st[key])
		"quality":
			st["quality"] = posmod(int(st.get("quality", 0)) + d, GameState.QUALITY_LEVELS.size())
		"comfort":
			st["comfort"] = posmod(int(st.get("comfort", 1)) + d, CrtScript.COMFORT_LEVELS.size())
		_:
			return
	_apply(key)


func _apply(key: String) -> void:
	var st := GameState.settings
	GameState.save_settings()
	Audio.play("ui_click", 0.0)
	if key in ["resolution", "fullscreen", "vsync"]:
		GameState.apply_settings()
	if key in ["volume", "music", "sfx"]:
		Audio.apply_volumes()
	if key == "crt" and crt:
		crt.rect.visible = bool(st["crt"])
	if key == "glow" and env:
		env.glow_enabled = bool(st["glow"])
	if key == "comfort" and crt:
		crt.apply_comfort()
	if key == "quality":
		GameState.apply_quality()


func _value_text(key: String) -> String:
	var st := GameState.settings
	match key:
		"resolution":
			var r: Vector2i = GameState.RESOLUTIONS[int(st["resolution"])]
			return "%d × %d" % [r.x, r.y]
		"fullscreen":
			return "PEŁNY EKRAN" if st["fullscreen"] else "OKNO"
		"volume", "music", "sfx":
			return "%d%%" % int(st[key])
		"vsync", "crt", "glow", "shake":
			return "WŁ." if st[key] else "WYŁ."
		"controls":
			return "PRZYPISZ"
		"comfort":
			return CrtScript.comfort_name()
		"quality":
			return GameState.quality_name()
	return ""


func _click(action, button: int) -> void:
	if action is int:
		if sel != action:
			sel = action
		if screen == "options" and OPT_ITEMS[action] != "back":
			_change_option(OPT_ITEMS[action], -1 if button == MOUSE_BUTTON_RIGHT else 1)
		elif button == MOUSE_BUTTON_LEFT:
			_activate(action)
		return
	var a: String = action
	if a.begins_with("vol:"):
		var parts: PackedStringArray = a.split(":")
		if int(GameState.settings[parts[1]]) != int(parts[2]):
			GameState.settings[parts[1]] = int(parts[2])
			GameState.save_settings()
			Audio.apply_volumes()
			Audio.play("ui_hover", 0.0)
	elif a.begins_with("opt-"):
		_change_option(a.substr(4), -1)
	elif a.begins_with("opt+"):
		_change_option(a.substr(4), 1)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if rebinding != "":
		# przypisanie: następny wciśnięty klawisz trafia do wybranej akcji, klik myszą przerywa
		if event is InputEventKey and event.pressed and not event.echo:
			GameState.bind_key(rebinding, event.physical_keycode)
			rebinding = ""
			Audio.play("ui_click", 0.0)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed:
			rebinding = ""
			get_viewport().set_input_as_handled()
		return
	if GameState.key_hit(event, "pause") and screen == "main":
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE, KEY_BACKSPACE:
				_back()
			KEY_UP, KEY_W:
				sel = posmod(sel - 1, _count())
				Audio.play("ui_hover", 0.0)
			KEY_DOWN, KEY_S:
				sel = posmod(sel + 1, _count())
				Audio.play("ui_hover", 0.0)
			KEY_LEFT, KEY_A:
				if screen == "options":
					_change_option(OPT_ITEMS[sel], -1)
			KEY_RIGHT, KEY_D:
				if screen == "options":
					_change_option(OPT_ITEMS[sel], 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate(sel)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		# przeciąganie po suwaku głośności
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			for h in hits:
				if h[1] is String and h[1].begins_with("vol:") and h[0].has_point(event.position):
					_click(h[1], MOUSE_BUTTON_LEFT)
					return
		for h in hits:
			if h[0].has_point(event.position):
				if h[1] is int and sel != h[1]:
					sel = h[1]
					Audio.play("ui_hover", 0.0)
				break
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		for h in hits:
			if h[0].has_point(event.position):
				_click(h[1], event.button_index)
				get_viewport().set_input_as_handled()
				return


func _draw() -> void:
	var vs := get_viewport_rect().size
	var e := 1.0 - pow(1.0 - appear, 3.0)
	hits.clear()
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.0, 0.03, 0.72 * e))
	match screen:
		"options": _draw_options(vs, e)
		"controls": _draw_controls(vs, e)
		"achievements": _draw_achievements(vs, e)
		_: _draw_main(vs, e)


func _title(r: Rect2, title: String, y: float, size: int) -> void:
	var tw := pf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var tp := Vector2(r.get_center().x - tw * 0.5, r.position.y + y)
	draw_string(pf, tp + Vector2(4, 3), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.2, 0.9, 1.0, 0.7))
	draw_string(pf, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1.25, 0.35, 0.85))


func _button(br: Rect2, label: String, i: int, max_fs := 24) -> void:
	hits.append([br, i])
	var on := sel == i
	var c: Color = Style.GOLD if on else Style.PINK
	Style.chamfer_panel(self, br, c, Color(0.14, 0.08, 0.02, 0.95) if on else Color(0.03, 0.0, 0.06, 0.92), 8.0)
	if on:
		draw_rect(Rect2(br.position.x, br.position.y + 10, 4, br.size.y - 20), Color(1.3, 1.0, 0.45))
	var fs := max_fs
	while fs > 14 and pf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > br.size.x - 24:
		fs -= 2
	var lw := pf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(pf, Vector2(br.get_center().x - lw * 0.5, br.get_center().y + fs * 0.38), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.3, 1.0, 0.45) if on else c)


func _draw_main(vs: Vector2, e: float) -> void:
	var w := 440.0
	var items := _items()
	var h := 140.0 + items.size() * 66.0 + (34.0 if in_flight else 0.0)
	var r := Rect2(vs * 0.5 - Vector2(w, h) * 0.5 + Vector2(0, (1.0 - e) * 30.0), Vector2(w, h))
	Style.chamfer_panel(self, r, Style.PINK, Color(0.02, 0.0, 0.05, 0.96), 16.0)
	_title(r, "PAUZA", 72, 48)
	for i in items.size():
		_button(Rect2(r.position.x + 40, r.position.y + 110 + i * 66, w - 80, 52), items[i], i)
	if in_flight:
		var warn := "Przerwanie wyprawy: jej ładunek przepada."
		var ww := font.get_string_size(warn, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, Vector2(r.get_center().x - ww * 0.5, r.end.y - 22), warn, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.55, 0.45))


func _draw_options(vs: Vector2, e: float) -> void:
	var w := 720.0
	var row := 46.0
	var n := OPT_ITEMS.size() - 1
	var h := 110.0 + n * row + 80.0
	var r := Rect2(vs * 0.5 - Vector2(w, h) * 0.5 + Vector2(0, (1.0 - e) * 30.0), Vector2(w, h))
	Style.chamfer_panel(self, r, Style.CYAN, Color(0.02, 0.0, 0.05, 0.96), 16.0)
	_title(r, "OPCJE", 62, 40)
	var x := r.position.x + 30
	var rw := w - 60
	var y := r.position.y + 96
	for i in n:
		var key: String = OPT_ITEMS[i]
		var on := sel == i
		var rr := Rect2(x, y, rw, row - 6)
		hits.append([rr, i])
		var bc: Color = Style.GOLD if on else Color(Style.PINK.r, Style.PINK.g, Style.PINK.b, 0.6)
		Style.chamfer_panel(self, rr, bc, Color(0.11, 0.05, 0.06, 0.93) if on else Color(0.03, 0.0, 0.06, 0.93), 7.0)
		var ty := y + 27
		draw_string(pf, Vector2(rr.position.x + 18, ty), OPT_NAMES[key], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.3, 1.0, 0.45) if on else Style.TEXT)
		var lr := Rect2(x + rw - 270, y + 3, 34, 34)
		var ar := Rect2(x + rw - 40, y + 3, 34, 34)
		hits.push_front([lr, "opt-" + key])
		hits.push_front([ar, "opt+" + key])
		var ac := Style.GOLD if on else Color(0.65, 0.55, 0.75)
		draw_string(pf, Vector2(lr.position.x + 10, ty), "<", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ac)
		draw_string(pf, Vector2(ar.position.x + 12, ty), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ac)
		var mid := (lr.end.x + ar.position.x) * 0.5
		var val := _value_text(key)
		if key in ["volume", "music", "sfx"]:
			# suwak: kliknij lub przeciągnij po kreskach
			var bw := 130.0
			var bx := mid - bw * 0.5 - 18
			var v := int(GameState.settings[key]) / 10
			for s in 10:
				var sr := Rect2(bx + s * (bw / 10.0), y + 12, bw / 10.0 - 3, 16)
				hits.push_front([sr.grow(2.0), "vol:%s:%d" % [key, (s + 1) * 10]])
				draw_rect(sr, Style.CYAN if s < v else Color(0.2, 0.15, 0.25))
			draw_string(font, Vector2(bx + bw + 8, ty - 2), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Style.TEXT)
		else:
			var vc := Style.TEXT
			if val == "WŁ.":
				vc = Color(0.5, 1.2, 0.55)
			elif val == "WYŁ.":
				vc = Color(1.0, 0.4, 0.45)
			var vw := pf.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			draw_string(pf, Vector2(mid - vw * 0.5, ty), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, vc)
		y += row
	_button(Rect2(r.get_center().x - 120, y + 14, 240, 48), "< WRÓĆ", n)


func _draw_achievements(vs: Vector2, e: float) -> void:
	var w := minf(1040.0, vs.x - 60.0)
	var rows := int(ceil(Achievements.DEFS.size() / 2.0))
	var h := 150.0 + rows * 120.0 + 80.0
	var r := Rect2(vs * 0.5 - Vector2(w, h) * 0.5 + Vector2(0, (1.0 - e) * 30.0), Vector2(w, h))
	Style.chamfer_panel(self, r, Style.CYAN, Color(0.02, 0.0, 0.05, 0.96), 16.0)
	_title(r, "OSIĄGNIĘCIA", 62, 40)
	var sub := "ZDOBYTE: %d / %d" % [Achievements.count(), Achievements.DEFS.size()]
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(r.get_center().x - sw * 0.5, r.position.y + 92), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Style.TEXT_DIM)
	var lh: float = Achievements.draw_list(self, Rect2(r.position.x + 30, r.position.y + 118, w - 60, 0), time)
	_button(Rect2(r.get_center().x - 120, r.position.y + 118 + lh + 26, 240, 48), "< WRÓĆ", 0)


## Sterowanie: dwie kolumny akcji. Klik (albo ENTER) na wierszu czeka na nowy klawisz.
func _draw_controls(vs: Vector2, e: float) -> void:
	var acts: Array = GameState.KEY_ACTIONS
	var per_col := int(ceil(acts.size() / 2.0))
	var cw := 470.0
	var gap := 20.0
	var w := cw * 2 + gap + 60
	var h := 110.0 + per_col * 46.0 + 120.0
	var r := Rect2(vs * 0.5 - Vector2(w, h) * 0.5 + Vector2(0, (1.0 - e) * 30.0), Vector2(w, h))
	Style.chamfer_panel(self, r, Style.CYAN, Color(0.02, 0.0, 0.05, 0.96), 16.0)
	_title(r, "STEROWANIE", 62, 40)
	var x0 := r.position.x + 30
	var y0 := r.position.y + 96
	for i in acts.size():
		var col := i / per_col
		var rr := Rect2(x0 + col * (cw + gap), y0 + (i % per_col) * 46, cw, 40)
		hits.append([rr, i])
		var waiting: bool = rebinding == acts[i][0]
		var on := sel == i or waiting
		var bc: Color = Style.GOLD if on else Color(Style.PINK.r, Style.PINK.g, Style.PINK.b, 0.6)
		Style.chamfer_panel(self, rr, bc, Color(0.11, 0.05, 0.06, 0.93) if on else Color(0.03, 0.0, 0.06, 0.93), 7.0)
		draw_string(font, Vector2(rr.position.x + 14, rr.position.y + 26), String(acts[i][1]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 150, 14, Color(1.3, 1.0, 0.45) if on else Style.TEXT)
		var label := "NACIŚNIJ KLAWISZ..." if waiting else GameState.key_name(acts[i][0])
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var kw := maxf(lw + 22.0, 60.0)
		var kr := Rect2(rr.end.x - 10 - kw, rr.position.y + 6, kw, 28)
		var kc: Color = Style.CYAN if not waiting else Color(1.3, 1.0, 0.45, 0.5 + 0.5 * (0.5 + 0.5 * sin(time * 8.0)))
		Style.chamfer_panel(self, kr, kc, Color(0.02, 0.05, 0.08, 0.95), 5.0)
		draw_string(font, Vector2(kr.get_center().x - lw * 0.5, kr.position.y + 19), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, kc)
	var by := y0 + per_col * 46 + 16
	var n: int = acts.size()
	_button(Rect2(r.get_center().x - 270, by, 260, 48), "DOMYŚLNE", n)
	_button(Rect2(r.get_center().x + 10, by, 260, 48), "< WRÓĆ", n + 1)
	var hint := "KLIKNIJ AKCJĘ I NACIŚNIJ NOWY KLAWISZ. ZAJĘTY KLAWISZ ZAMIENIA SIĘ MIEJSCAMI."
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(r.get_center().x - hw * 0.5, by + 76), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Style.TEXT_DIM)
