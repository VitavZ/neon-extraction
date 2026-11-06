extends Control
## Menu główne: START (3 sloty zapisu), OSIĄGNIĘCIA, OPCJE, WYJŚCIE.
## Tło to żywa mapa z gry: statek leci za kursorem, a przytrzymanie LPM niszczy kafelki.
## Kliknięcie Statku Matki wypuszcza kolejny statek do eskadry.

const Style = preload("res://scripts/style.gd")
const CrtScript = preload("res://scripts/crt.gd")
const WorldScript = preload("res://scripts/world.gd")
const MeshPainter = preload("res://scripts/mesh_painter.gd")

const T := 48
const LEFT_X := 80.0
const MOTHER_R := 170.0
const BEAM_RANGE := 340.0
const BURN_TIME := 0.32           # tyle sekund wiązki niszczy kafelek
const MAX_SHIPS := 8
enum { F_LIVE, F_DEAD, F_IMPERIAL }
const SHIP_SHAPE := [Vector2(22, 0), Vector2(4, -7), Vector2(-6, -18), Vector2(-14, -16), Vector2(-9, -6),
	Vector2(-13, 0), Vector2(-9, 6), Vector2(-14, 16), Vector2(-6, 18), Vector2(4, 7)]
const MAIN_ITEMS := ["START", "TUTORIAL", "OSIĄGNIĘCIA", "OPCJE", "WYJŚCIE"]
const VERSION := "Version 0.3.1"
const Options = preload("res://scripts/options.gd")
const OPT_ITEMS := Options.ITEMS

var pf: Font
var time := 0.0
var screen := "main"        # main / slots / achievements / options
var sel := 0                # zaznaczona pozycja na bieżącym ekranie
var hits: Array = []        # [Rect2, akcja] - aktualizowane przy rysowaniu
var delete_armed := -1      # slot czekający na potwierdzenie usunięcia
var slot_cache: Array = []
var fade := 1.0             # wejście z czerni
var leaving := false
var leave_t := 0.0
var leave_action := Callable()
var screen_t := 1.0         # wjazd bieżącego ekranu
var rebinding := ""         # akcja czekająca na nowy klawisz
var btn_anim: Dictionary = {}
# pole kafelków
var field_size := Vector2.ZERO
var field_cols := 0
var field_rows := 0
var f_kind := PackedInt32Array()
var f_state := PackedInt32Array()
var f_hp := PackedFloat32Array()
var f_timer := PackedFloat32Array()
var f_cache: Array = []     # trójkąty każdego kafelka
var field_mesh: ArrayMesh
var field_dirty := false
var tile_timers: Dictionary = {}   # kafelki, które odrastają
var menu_score := 0
var score_pop := 0.0
# statek
var mouse := Vector2(800, 450)
var ships: Array = []       # eskadra: {pos, vel, rot, w, thrust, trail, offset, beam_on, beam_end, beam_tile}
var firing_held := false
var mother_hover := false
var mother_pulse := 0.0
var sparks: Array = []
var rings: Array = []
var bursts: Array = []
var logo_glow: Control
var logo_spin := 0.0
var logo_meshes: Array = []          # litery logo: zwykłe i przygaszone
var logo_boost := 0.0              # kursor nad logo: ośmiokąt przyspiesza
var shutters: Control
var crt: CanvasLayer
var env: Environment


func _ready() -> void:
	# powrót ze szkolenia: dalej gra się już normalnymi slotami
	GameState.training = false
	pf = Style.font_pixel()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	grab_focus()
	mouse = get_viewport().get_mouse_position()
	_add_ship(Vector2(1000, 700), Vector2.ZERO, Vector2.ZERO)
	# logo i grodzie mają osobne warstwy nad mapą, a grodzie muszą zasłaniać logo
	logo_glow = _layer(_draw_logo_glow)
	shutters = _layer(_draw_shutters)
	# poświata neonów (jak w grze)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = bool(GameState.settings["glow"])
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.0)
	we.environment = env
	add_child(we)
	crt = CrtScript.new()
	add_child(crt)
	_refresh_slots()
	Audio.stop_loops()
	Audio.play_menu_music()


func _layer(cb: Callable) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(cb)
	add_child(c)
	return c


func _refresh_slots() -> void:
	slot_cache.clear()
	for n in range(1, GameState.SAVE_SLOTS + 1):
		slot_cache.append(GameState.slot_info(n))


# =====================================================================
# LOGIKA
# =====================================================================

func _process(delta: float) -> void:
	time += delta
	fade = maxf(0.0, fade - delta * 1.5)
	if leaving:
		leave_t += delta * 2.5
		if leave_t >= 1.0 and leave_action.is_valid():
			var a := leave_action
			leave_action = Callable()
			a.call()
	screen_t = minf(screen_t + delta * 3.5, 1.0)
	var vs := get_viewport_rect().size
	if vs != field_size:
		_build_field(vs)
	_update_field(delta)
	_update_ship(delta)
	_update_fx(delta)
	if field_dirty:
		_rebuild_field()
	queue_redraw()
	_update_logo(delta)
	logo_glow.queue_redraw()
	shutters.queue_redraw()


func _count() -> int:
	match screen:
		"main": return MAIN_ITEMS.size()
		"slots": return GameState.SAVE_SLOTS + 1
		"options": return OPT_ITEMS.size()
		"controls": return GameState.KEY_ACTIONS.size() + 2
		"achievements": return 1
	return 1


func _gui_input(event: InputEvent) -> void:
	if leaving:
		return
	if event is InputEventMouseMotion:
		mouse = event.position
		# przeciąganie po suwaku głośności
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			for h in hits:
				if h[1] is String and h[1].begins_with("vol:") and h[0].has_point(event.position):
					_click(h[1], MOUSE_BUTTON_LEFT)
					return
		if firing_held:
			return
		for h in hits:
			if h[0].has_point(event.position):
				if h[1] is int:
					if sel != h[1]:
						Audio.play("ui_hover", 0.0)
					sel = h[1]
				break
	elif event is InputEventMouseButton:
		mouse = event.position
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			firing_held = false
			return
		if not event.pressed:
			return
		for h in hits:
			if h[0].has_point(event.position):
				_click(h[1], event.button_index)
				accept_event()
				return
		# LPM poza przyciskami: statek strzela w kursor
		if event.button_index == MOUSE_BUTTON_LEFT:
			firing_held = true
	elif event is InputEventKey and event.pressed and rebinding != "":
		# przypisanie: następny wciśnięty klawisz trafia do wybranej akcji
		if not event.echo:
			GameState.bind_key(rebinding, event.physical_keycode)
			rebinding = ""
			Audio.play("ui_click", 0.0)
		accept_event()
	elif event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_UP, KEY_W, KEY_DOWN, KEY_S:
				Audio.play("ui_hover", 0.0)
		match event.physical_keycode:
			KEY_UP, KEY_W:
				sel = posmod(sel - 1, _count()); delete_armed = -1
			KEY_DOWN, KEY_S:
				sel = posmod(sel + 1, _count()); delete_armed = -1
			KEY_LEFT, KEY_A:
				if screen == "options": _change_option(OPT_ITEMS[sel], -1)
				elif screen == "slots": sel = posmod(sel - 1, _count())
			KEY_RIGHT, KEY_D:
				if screen == "options": _change_option(OPT_ITEMS[sel], 1)
				elif screen == "slots": sel = posmod(sel + 1, _count())
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate(sel)
			KEY_DELETE:
				if screen == "slots" and sel < GameState.SAVE_SLOTS:
					_click("del%d" % sel, MOUSE_BUTTON_LEFT)
			KEY_ESCAPE, KEY_BACKSPACE:
				if screen == "controls":
					_go("options", OPT_ITEMS.find("controls"))
				elif screen != "main":
					_go("main", MAIN_ITEMS.find({"slots": "START", "achievements": "OSIĄGNIĘCIA"}.get(screen, "OPCJE")))
		accept_event()


func _go(s: String, select := 0) -> void:
	screen = s
	sel = select
	delete_armed = -1
	screen_t = 0.0
	firing_held = false
	rebinding = ""
	if s == "slots":
		_refresh_slots()


func _click(action, button: int) -> void:
	if rebinding != "":
		# klik gdziekolwiek przerywa czekanie na klawisz
		rebinding = ""
		return
	if action is String and action == "mother":
		if button == MOUSE_BUTTON_LEFT:
			_launch_wingman()
		return
	if action is int:
		sel = action
		if screen == "controls":
			if button == MOUSE_BUTTON_LEFT:
				_activate(action)
			return
		if screen == "options" and action < OPT_ITEMS.size() and OPT_ITEMS[action] != "back":
			_change_option(OPT_ITEMS[action], -1 if button == MOUSE_BUTTON_RIGHT else 1)
		elif button == MOUSE_BUTTON_LEFT:
			_activate(action)
	elif action is String:
		if action.begins_with("vol:"):
			Options.set_volume_from(action)
		elif action.begins_with("del"):
			var n := int(action.substr(3))
			if delete_armed == n:
				GameState.delete_slot(n + 1)
				delete_armed = -1
				_refresh_slots()
			else:
				delete_armed = n
		elif action.begins_with("opt-"):
			_change_option(action.substr(4), -1)
		elif action.begins_with("opt+"):
			_change_option(action.substr(4), 1)


func _activate(i: int) -> void:
	Audio.play("ui_click", 0.0)
	match screen:
		"main":
			match MAIN_ITEMS[i]:
				"START": _go("slots", 0)
				"TUTORIAL": _leave(_start_training)
				"OSIĄGNIĘCIA": _go("achievements", 0)
				"OPCJE": _go("options", 0)
				"WYJŚCIE": _leave(func(): get_tree().quit())
		"achievements":
			_go("main", MAIN_ITEMS.find("OSIĄGNIĘCIA"))
		"controls":
			var n: int = GameState.KEY_ACTIONS.size()
			if i < n:
				rebinding = GameState.KEY_ACTIONS[i][0]
			elif i == n:
				GameState.reset_keys()
				GameState.save_settings()
			else:
				_go("options", OPT_ITEMS.find("controls"))
		"slots":
			if i >= GameState.SAVE_SLOTS:
				_go("main", 0)
			else:
				_start_slot(i + 1)
		"options":
			if OPT_ITEMS[i] == "back":
				_go("main", MAIN_ITEMS.find("OPCJE"))
			else:
				_change_option(OPT_ITEMS[i], 1)


## Szkolenie w Roswell: osobna rozgrywka bez zapisu (scripts/training.gd).
func _start_training() -> void:
	GameState.start_training()
	get_tree().change_scene_to_file("res://main.tscn")


func _start_slot(n: int) -> void:
	GameState.slot = n
	if slot_cache[n - 1].is_empty():
		GameState.new_game()
	_leave(func(): get_tree().change_scene_to_file("res://main.tscn"))


func _leave(action: Callable) -> void:
	Audio.stop_loops()
	firing_held = false
	leaving = true
	leave_t = 0.0
	leave_action = action


func _change_option(key: String, d: int) -> void:
	if key == "controls":
		Audio.play("ui_click", 0.0)
		_go("controls", 0)
		return
	Options.change(key, d, crt, env)


# =====================================================================
# POLE KAFELKÓW W TLE (można je niszczyć statkiem)
# =====================================================================

func _build_field(vs: Vector2) -> void:
	field_size = vs
	field_cols = int(ceil(vs.x / T)) + 1
	field_rows = int(ceil(vs.y / T)) + 1
	var total := field_cols * field_rows
	f_kind.resize(total)
	f_state.resize(total)
	f_hp.resize(total)
	f_timer.resize(total)
	f_cache.resize(total)
	f_cache.fill(null)
	var noise := FastNoiseLite.new()
	noise.seed = randi() % 100000
	noise.frequency = 0.075
	var city := FastNoiseLite.new()
	city.seed = noise.seed + 1
	city.frequency = 0.14
	for i in total:
		var x := i % field_cols
		var y := i / field_cols
		var v := noise.get_noise_2d(x, y)
		var kind: int = WorldScript.PLAINS
		if v < -0.28:
			kind = WorldScript.OCEAN
		elif v < -0.2:
			kind = WorldScript.RIVER
		elif v < -0.15:
			kind = WorldScript.SAND
		elif v > 0.33:
			kind = WorldScript.SNOW if v > 0.42 else WorldScript.MOUNTAIN
		elif v > 0.08:
			kind = WorldScript.FOREST
		if v > -0.15 and v < 0.3 and city.get_noise_2d(x, y) > 0.34:
			kind = WorldScript.CITY
		f_kind[i] = kind
		f_state[i] = F_LIVE
		f_hp[i] = 1.0
		f_timer[i] = 0.0
	field_dirty = true


func _tile_at(p: Vector2) -> int:
	var x := int(floor(p.x / T))
	var y := int(floor(p.y / T))
	if x < 0 or y < 0 or x >= field_cols or y >= field_rows:
		return -1
	return y * field_cols + x


func _tile_center(i: int) -> Vector2:
	return Vector2(i % field_cols + 0.5, i / field_cols + 0.5) * T


func _set_tile(i: int, state: int) -> void:
	f_state[i] = state
	f_cache[i] = null
	field_dirty = true


## Siatka całego pola składana z zapamiętanych kafelków; liczony jest tylko zmieniony.
func _rebuild_field() -> void:
	field_dirty = false
	var mp = MeshPainter.new()
	for i in f_kind.size():
		if f_cache[i] == null:
			var one = MeshPainter.new()
			var x := i % field_cols
			var y := i / field_cols
			var h := (x * 73856093) ^ (y * 19349663)
			h = absi(h) & 0xFFFF
			WorldScript.paint_terrain(one, Rect2(x * T, y * T, T, T), f_kind[i], h, (h * 31) & 0xFFFF, f_state[i] == F_IMPERIAL, f_state[i] == F_DEAD)
			f_cache[i] = [one.verts, one.cols]
		mp.verts.append_array(f_cache[i][0])
		mp.cols.append_array(f_cache[i][1])
	field_mesh = mp.build_mesh()


func _update_field(delta: float) -> void:
	for i in tile_timers.keys():
		f_timer[i] -= delta
		if f_timer[i] > 0.0:
			continue
		if f_state[i] == F_DEAD:
			# zniszczony kafelek przejmuje Imperium...
			_set_tile(i, F_IMPERIAL)
			f_timer[i] = randf_range(14.0, 26.0)
			_ring(_tile_center(i), Color(1.2, 0.25, 0.9, 0.8), 30.0, 0.4)
		else:
			# ...a po chwili teren wraca, żeby było co niszczyć
			_set_tile(i, F_LIVE)
			f_hp[i] = 1.0
			tile_timers.erase(i)


# =====================================================================
# STATEK W TLE
# =====================================================================

func _add_ship(p: Vector2, v: Vector2, offset: Vector2) -> void:
	ships.append({"pos": p, "vel": v, "rot": v.angle() if v != Vector2.ZERO else -PI * 0.5, "w": 0.0, "thrust": 0.0,
		"trail": PackedVector2Array(), "offset": offset, "beam_on": false, "beam_end": Vector2.ZERO, "beam_tile": -1})


## Statek Matka wypuszcza kolejny statek; dołącza do szyku wokół kursora.
func _launch_wingman() -> void:
	var c := _mother_pos(get_viewport_rect().size)
	mother_pulse = 1.0
	_ring(c, Color(0.3, 1.1, 1.3, 0.9), MOTHER_R + 40.0, 0.5)
	if ships.size() >= MAX_SHIPS:
		Audio.play("error", 0.0)
		return
	Audio.play("launch", 0.05)
	var dir := Vector2.from_angle(randf() * TAU)
	# miejsca w szyku rozkładają się równo wokół kursora
	var slot := float(ships.size() - 1) / (MAX_SHIPS - 1) * TAU * 2.0
	_add_ship(c + dir * 60.0, dir * 380.0, Vector2.from_angle(slot) * randf_range(90.0, 150.0))


func _update_ship(delta: float) -> void:
	var vs := get_viewport_rect().size
	var any_beam := false
	for sh in ships:
		if _update_one_ship(sh, vs, delta):
			any_beam = true
	Audio.set_loop("laser_loop", any_beam and not leaving)


func _update_one_ship(sh: Dictionary, vs: Vector2, delta: float) -> bool:
	var offset: Vector2 = sh["offset"]
	# przy strzelaniu szyk się zacieśnia, żeby wiązki cięły obok siebie
	var aim: Vector2 = mouse + offset * (0.45 if firing_held else 1.0)
	var to: Vector2 = aim - sh["pos"]
	var want_w := 0.0
	if to.length() > 26.0:
		want_w = clampf(wrapf(to.angle() - sh["rot"], -PI, PI) * 11.0, -7.0, 7.0)
	sh["w"] = lerpf(sh["w"], want_w, 1.0 - exp(-24.0 * delta))
	sh["rot"] += sh["w"] * delta
	var dir := Vector2.from_angle(sh["rot"])
	# leci do celu, a przy nim zwalnia i krąży na wiązce
	var keep: float = BEAM_RANGE * 0.6 if firing_held else 90.0
	sh["thrust"] = lerpf(sh["thrust"], 1.0 if to.length() > keep else 0.0, 1.0 - exp(-14.0 * delta))
	var vel: Vector2 = sh["vel"] + dir * 620.0 * sh["thrust"] * delta
	vel *= exp(-(1.5 if sh["thrust"] > 0.3 else 3.2) * delta)
	var spd := vel.length()
	if spd > 480.0:
		vel = vel.normalized() * 480.0
	sh["vel"] = vel
	sh["pos"] = (sh["pos"] + vel * delta).clamp(Vector2(-20, -20), vs + Vector2(20, 20))
	var pos: Vector2 = sh["pos"]
	# smuga
	var trail: PackedVector2Array = sh["trail"]
	if trail.is_empty() or pos.distance_to(trail[-1]) > 12.0:
		trail.append(pos - dir * 12.0)
	var max_pts := 6 + int(minf(spd / 480.0, 1.0) * 26.0)
	while trail.size() > max_pts:
		trail.remove_at(0)
	sh["trail"] = trail
	if sh["thrust"] > 0.3 and randf() < 0.5:
		_spark(pos - dir * 14.0, vel * 0.3 - dir * randf_range(100, 220), Color(1.2, 0.6, 0.25), 0.28)

	# wiązka
	sh["beam_on"] = false
	sh["beam_tile"] = -1
	if not firing_held or leaving:
		return false
	var nose := pos + dir * 22.0
	var off := aim - nose
	if off.length() > BEAM_RANGE:
		off = off.normalized() * BEAM_RANGE
	sh["beam_end"] = nose + off
	sh["beam_on"] = true
	var i := _tile_at(sh["beam_end"])
	if i >= 0 and f_state[i] == F_LIVE:
		sh["beam_tile"] = i
		f_hp[i] -= delta / BURN_TIME
		if randf() < 0.3:
			_spark(sh["beam_end"], Vector2.from_angle(randf() * TAU) * randf_range(40, 110), Color(1.0, 0.45, 0.85), 0.35)
		if f_hp[i] <= 0.0:
			_destroy_tile(i)
	return true

func _destroy_tile(i: int) -> void:
	var p := _tile_center(i)
	_set_tile(i, F_DEAD)
	f_timer[i] = randf_range(6.0, 11.0)
	tile_timers[i] = true
	menu_score += 1
	Achievements.menu_tile()
	Audio.play("tile_break", 0.15)
	_ring(p, Color(1.0, 0.45, 0.85, 0.8), 36.0, 0.3)
	for k in 8:
		_spark(p, Vector2.from_angle(randf() * TAU) * randf_range(60, 240), Color(1.0, 0.45, 0.85), randf_range(0.25, 0.6))
	bursts.append({"pos": p, "r": 26.0, "life": 0.3, "max": 0.3, "rot": randf() * TAU})
	if menu_score % 25 == 0:
		_ring(p, Color(1.3, 1.0, 0.45, 0.9), 150.0, 0.7)
		Audio.play("research_done", 0.0, -8.0)
		score_pop = 1.0


func _spark(p: Vector2, v: Vector2, c: Color, life: float) -> void:
	if sparks.size() < 260:
		sparks.append({"pos": p, "vel": v, "life": life, "max": life, "color": c})


func _ring(p: Vector2, c: Color, r: float, life: float) -> void:
	if rings.size() < 40:
		rings.append({"pos": p, "r": r, "life": life, "max": life, "color": c})


func _update_fx(delta: float) -> void:
	var k := sparks.size() - 1
	while k >= 0:
		var s: Dictionary = sparks[k]
		s["life"] -= delta
		if s["life"] <= 0.0:
			sparks[k] = sparks[-1]
			sparks.pop_back()
		else:
			s["pos"] += s["vel"] * delta
			s["vel"] *= exp(-3.0 * delta)
		k -= 1
	for r in rings:
		r["life"] -= delta
	if not rings.is_empty():
		rings = rings.filter(func(r): return r["life"] > 0.0)
	for b in bursts:
		b["life"] -= delta
	if not bursts.is_empty():
		bursts = bursts.filter(func(b): return b["life"] > 0.0)
	score_pop = maxf(0.0, score_pop - delta * 2.0)
	mother_pulse = maxf(0.0, mother_pulse - delta * 2.5)


# =====================================================================
# RYSOWANIE
# =====================================================================

func _txt(p: Vector2, s: String, fsize: int, c: Color) -> void:
	draw_string(pf, p.round(), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, c)


func _tw(s: String, fsize: int) -> float:
	return pf.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x


func _ctxt(cx: float, y: float, s: String, fsize: int, c: Color) -> void:
	_txt(Vector2(cx - _tw(s, fsize) * 0.5, y), s, fsize, c)


func _draw() -> void:
	var vs := get_viewport_rect().size
	hits.clear()
	_draw_field_layer(vs)
	# delikatna winieta z lewej: pod logo i przyciskami ciemniej, w stronę środka jaśniej
	var vw := vs.x * 0.55
	var dark := Color(0.01, 0.0, 0.03, 0.5)
	var clear := Color(0.01, 0.0, 0.03, 0.0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vw, 0), Vector2(vw, vs.y), Vector2(0, vs.y)]),
		PackedColorArray([dark, clear, clear, dark]))
	# ekrany wjeżdżają z lewej
	var slide := (1.0 - Style.ease_out(screen_t)) * -60.0
	draw_set_transform(Vector2(slide, 0.0))
	match screen:
		"main": _draw_main(vs)
		"slots": _draw_slots(vs)
		"options": _draw_options(vs)
		"controls": _draw_controls(vs)
		"achievements": _draw_achievements(vs)
	draw_set_transform(Vector2.ZERO)
	_draw_score(vs)
	# stopka
	_txt(Vector2(20, vs.y - 16), VERSION, 16, Style.TEXT_DIM)


func _draw_field_layer(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.0, 0.05))
	if field_mesh:
		draw_mesh(field_mesh, null)
	# przygaszenie mapy: mocne pod menu po lewej, słabsze po prawej
	var left := Color(0.01, 0.0, 0.03, 0.92 if screen == "main" else 0.86)
	var right := Color(0.01, 0.0, 0.03, 0.42 if screen == "main" else 0.8)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]), PackedColorArray([left, right, right, left]))
	for sh in ships:
		var bt: int = sh["beam_tile"]
		if bt >= 0 and f_state[bt] == F_LIVE:
			# trafiony kafelek: ramka i pasek życia
			var r := Rect2(_tile_center(bt) - Vector2(T, T) * 0.5, Vector2(T, T))
			draw_rect(r, Color(1, 1, 1, 0.18))
			draw_rect(Rect2(r.position + Vector2(7, T - 8), Vector2(T - 14, 4)), Color(0.35, 0.02, 0.06))
			draw_rect(Rect2(r.position + Vector2(7, T - 8), Vector2((T - 14) * clampf(f_hp[bt], 0.0, 1.0), 4)), Color(1.0, 0.22, 0.32))
	_draw_mother(vs)
	_draw_ship_fx()


func _mother_pos(vs: Vector2) -> Vector2:
	return Vector2(vs.x * 0.74, vs.y * 0.52) + (mouse - vs * 0.5) * -0.015 + Vector2(0, sin(time * 0.8) * 6.0)


## Duży Statek Matka: ten sam kształt co w locie. Kliknięcie to START.
func _draw_mother(vs: Vector2) -> void:
	if screen != "main":
		return
	var c := _mother_pos(vs)
	var rot := time * 0.15
	var pulse := 0.5 + 0.5 * sin(time * 3.0)
	var hov: bool = c.distance_to(mouse) < MOTHER_R
	mother_hover = hov
	var zone := Color(1.3, 0.3, 1.0, 0.75) if hov else Color(0.15, 1.1, 1.3, 0.25 + 0.2 * pulse)
	var rad := MOTHER_R + mother_pulse * 30.0
	draw_arc(c, rad, 0.0, TAU, 96, zone, 2.0, true)
	for k in 12:
		var a := rot * -2.0 + k / 12.0 * TAU
		draw_arc(c, rad + 9.0, a, a + 0.25, 6, zone, 2.0, true)
	var s := 1.0 + (0.04 if hov else 0.0) + mother_pulse * 0.08
	var outer := PackedVector2Array()
	for k in 8:
		outer.append(c + Vector2.from_angle(rot + k / 8.0 * TAU) * 120.0 * s)
	draw_colored_polygon(outer, Color(0.1, 0.0, 0.16, 0.95))
	outer.append(outer[0])
	draw_polyline(outer, Color(1.3, 0.2, 1.0), 3.0, true)
	for k in 4:
		var a := rot + k / 4.0 * TAU + PI / 8.0
		var d := Vector2.from_angle(a)
		var n := d.orthogonal()
		var arm := PackedVector2Array([c + d * 50.0 * s + n * 14.0, c + d * 150.0 * s + n * 6.0, c + d * 162.0 * s, c + d * 150.0 * s - n * 6.0, c + d * 50.0 * s - n * 14.0])
		draw_colored_polygon(arm, Color(0.12, 0.0, 0.2, 0.95))
		arm.append(arm[0])
		draw_polyline(arm, Color(0.19, 0.93, 1.3), 2.0, true)
		draw_circle(c + d * 162.0 * s, 5.0, Color(1.3, 0.43, 1.13) if int(time * 2.0 + k) % 2 == 0 else Color(1.0, 0.3, 0.9))
	var inner := PackedVector2Array()
	for k in 7:
		inner.append(c + Vector2.from_angle(-rot * 1.5 + k / 6.0 * TAU) * 62.0 * s)
	draw_polyline(inner, Color(1.3, 0.84, 0.23), 2.5, true)
	draw_arc(c, 34.0 * s, 0.0, TAU, 48, Color(1.3, 0.25, 1.1), 2.0, true)
	draw_circle(c, 14.0 + pulse * 3.0, Color(0.8 + 0.3 * pulse, 0.3, 1.2))
	draw_circle(c, 6.0, Color(1.3, 1.3, 1.3))


func _draw_ship_fx() -> void:
	for sh in ships:
		var trail: PackedVector2Array = sh["trail"]
		for k in range(1, trail.size()):
			var f := float(k) / trail.size()
			draw_line(trail[k - 1], trail[k], Color(0.5 + 0.8 * f, 0.5 - 0.3 * f, 1.3, f * 0.8), 1.0 + f * 4.0, true)
		if sh["beam_on"]:
			var nose: Vector2 = sh["pos"] + Vector2.from_angle(sh["rot"]) * 22.0
			var be: Vector2 = sh["beam_end"]
			draw_line(nose, be, Color(1.0, 0.3, 0.8, 0.18), 7.0, true)
			draw_line(nose, be, Color(1.0, 0.55, 0.9, 0.9), 2.0, true)
			draw_circle(be, 4.5 + sin(time * 30.0), Color(1.0, 0.45, 0.85, 0.55))
	for b in bursts:
		var f: float = 1.0 - b["life"] / b["max"]
		Style.sunburst(self, b["pos"], b["r"] * (0.4 + 0.6 * f), 10, b["rot"], Color(1.0, 0.8, 0.3, 1.0 - f), 2.0)
	for s in sparks:
		var f: float = s["life"] / s["max"]
		var c: Color = s["color"]
		draw_line(s["pos"], s["pos"] - s["vel"] * 0.05, Color(c.r, c.g, c.b, f), 2.0, true)
	for r in rings:
		var f: float = 1.0 - r["life"] / r["max"]
		var c: Color = r["color"]
		draw_arc(r["pos"], r["r"] * f, 0.0, TAU, 32, Color(c.r, c.g, c.b, (1.0 - f) * c.a), 2.0, true)
	for sh in ships:
		var xf := Transform2D(sh["rot"], sh["pos"])
		var pts := xf * PackedVector2Array(SHIP_SHAPE)
		draw_colored_polygon(pts, Color(0.12, 0.0, 0.18, 0.95))
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, Color(1.4, 0.23, 1.28), 2.2, true)
		draw_polyline(xf * PackedVector2Array([Vector2(12, 0), Vector2(2, -4), Vector2(-3, 0), Vector2(2, 4), Vector2(12, 0)]), Color(0.16, 1.08, 1.4), 1.6, true)
		if sh["thrust"] > 0.03:
			var fl: float = (14.0 + sin(time * 50.0) * 4.0 + randf() * 4.0) * sh["thrust"]
			draw_polyline(xf * PackedVector2Array([Vector2(-11, -4), Vector2(-11 - fl, 0), Vector2(-11, 4)]), Color(1.4, 0.75, 0.19), 2.5, true)

func _draw_score(vs: Vector2) -> void:
	if menu_score <= 0:
		return
	var txt := str(menu_score)
	var w := _tw(txt, 16) + 32.0
	var r := Rect2(vs.x - 20 - w, 20, w, 36).grow(score_pop * 4.0)
	Style.chamfer_panel(self, r, Style.GOLD if score_pop > 0.0 else Style.PINK, Color(0.02, 0.0, 0.05, 0.88), 8.0)
	_txt(r.position + Vector2(16, 24), txt, 16, Color(1.3, 1.0, 0.45) if score_pop > 0.0 else Style.PINK)


## Grodzie: rozsuwają się na starcie i zamykają przy wyjściu z menu.
func _draw_shutters() -> void:
	var vs := get_viewport_rect().size
	var closed := maxf(fade, clampf(leave_t, 0.0, 1.0) if leaving else 0.0)
	if closed <= 0.0:
		return
	var half := vs.x * 0.5 * Style.ease_out(closed)
	shutters.draw_rect(Rect2(0, 0, half, vs.y), Style.BG)
	shutters.draw_rect(Rect2(vs.x - half, 0, half, vs.y), Style.BG)
	shutters.draw_line(Vector2(half, 0), Vector2(half, vs.y), Color(1.3, 0.3, 1.1), 3.0)
	shutters.draw_line(Vector2(vs.x - half, 0), Vector2(vs.x - half, vs.y), Color(0.3, 1.1, 1.3), 3.0)


## Logo w stylu prawdziwego szyldu neonowego: każda litera to wygięta szklana rurka
## (świecący rdzeń, kolorowe szkło, poświata na ścianie), z przerwami tam, gdzie rurki się spotykają,
## i ciemnymi elektrodami na końcach. "O" w "NEON" to ośmiokąt Statku Matki, też z rurki.
## Siatka liter: 4 x 6 jednostek.
const NEON_GLYPHS := {
	"N": [[Vector2(0, 6), Vector2(0, 0), Vector2(4, 6), Vector2(4, 0)]],
	"E": [[Vector2(4, 0), Vector2(0, 0), Vector2(0, 6), Vector2(4, 6)], [Vector2(0.8, 3), Vector2(3.1, 3)]],
}
const GLYPHS := {
	"E": [[Vector2(4, 0), Vector2(0, 0), Vector2(0, 6), Vector2(4, 6)], [Vector2(0.9, 3), Vector2(3, 3)]],
	"X": [[Vector2(0, 0), Vector2(4, 6)], [Vector2(4, 0), Vector2(2.4, 2.4)], [Vector2(1.6, 3.6), Vector2(0, 6)]],
	"T": [[Vector2(0, 0), Vector2(4, 0)], [Vector2(2, 0.9), Vector2(2, 6)]],
	"R": [[Vector2(0, 6), Vector2(0, 0), Vector2(4, 0), Vector2(4, 3), Vector2(0.9, 3)], [Vector2(2.2, 3.9), Vector2(4, 6)]],
	"A": [[Vector2(0, 6), Vector2(0, 0), Vector2(4, 0), Vector2(4, 6)], [Vector2(0.9, 3.4), Vector2(3.1, 3.4)]],
	"C": [[Vector2(4, 0), Vector2(0, 0), Vector2(0, 6), Vector2(4, 6)]],
	"I": [[Vector2(2, 0), Vector2(2, 6)]],
	"O": [[Vector2(0, 0), Vector2(4, 0), Vector2(4, 6), Vector2(0, 6), Vector2(0, 0)]],
	"N": [[Vector2(0, 6), Vector2(0, 0), Vector2(4, 6), Vector2(4, 0)]],
}
const GLYPH_W := {"I": 0.0}      # szerokość litery w jednostkach (domyślnie 4)
const BIG_UNIT := 24.0
const BIG_TUBE := 9.0
const BIG_GAP := 1.6             # odstęp między literami w jednostkach
const SMALL_UNIT := 5.6
const SMALL_TUBE := 3.0
const SMALL_GAP := 3.1
const LOGO_SKEW := 0.08
const NEON_GLASS := Color(1.0, 0.22, 0.72)
const NEON_CORE := Color(1.55, 1.05, 1.45)
const CYAN_GLASS := Color(0.2, 0.85, 1.15)
const CYAN_CORE := Color(1.15, 1.5, 1.55)
const SUB_GLASS := Color(0.75, 0.9, 1.1)
const SUB_CORE := Color(1.35, 1.4, 1.5)


## Rurka: [punkty po zaokrągleniu zgięć, grubość, szkło, rdzeń, migocze?]
func _logo_tubes() -> Array:
	var out: Array = []
	var x := 0.0
	var k := 0
	for ch in "NEON":
		if k == 2:
			x += (4.0 + BIG_GAP) * BIG_UNIT
			k += 1
			continue
		for line in NEON_GLYPHS[ch]:
			var pts := PackedVector2Array()
			for v in line:
				pts.append(Vector2(x, 0.0) + v * BIG_UNIT)
			# ostatnie N to "zmęczona" rurka, która czasem przygasa
			out.append([_bend(pts, 0.7 * BIG_UNIT), BIG_TUBE, NEON_GLASS, NEON_CORE, k == 3])
		x += (4.0 + BIG_GAP) * BIG_UNIT
		k += 1
	x = _logo_sub_x()
	var y := _logo_small_y()
	for ch in "EXTRACTION":
		# wąskie "I" nie zostawia dziury: zajmuje tylko swoją kreskę
		var gw: float = GLYPH_W.get(ch, 4.0)
		var shift := (gw - 4.0) * 0.5
		for line in GLYPHS[ch]:
			var pts := PackedVector2Array()
			for v in line:
				pts.append(Vector2(x, y) + (v + Vector2(shift, 0)) * SMALL_UNIT)
			out.append([_bend(pts, 0.9 * SMALL_UNIT), SMALL_TUBE, SUB_GLASS, SUB_CORE, false])
		x += (gw + SMALL_GAP) * SMALL_UNIT
	# cienkie linie po bokach podtytułu
	var my := y + 3.0 * SMALL_UNIT
	var sw := _logo_sub_w()
	out.append([PackedVector2Array([Vector2(0, my), Vector2(_logo_sub_x() - 18.0, my)]), 2.0, NEON_GLASS, NEON_CORE, false])
	out.append([PackedVector2Array([Vector2(_logo_sub_x() + sw + 18.0, my), Vector2(_logo_small_width(), my)]), 2.0, NEON_GLASS, NEON_CORE, false])
	return out


## Zaokrągla zgięcia łamanej (krzywa Béziera w każdym rogu), jak wygięte na palniku szkło.
func _bend(pts: PackedVector2Array, r: float) -> PackedVector2Array:
	var closed := pts.size() > 2 and pts[0].distance_to(pts[-1]) < 0.5
	var src := pts.duplicate()
	if closed:
		src.remove_at(src.size() - 1)
	var n := src.size()
	if n < 3 and not closed:
		return pts
	var out := PackedVector2Array()
	for i in n:
		var p: Vector2 = src[i]
		if not closed and (i == 0 or i == n - 1):
			out.append(p)
			continue
		var a: Vector2 = src[(i - 1 + n) % n]
		var b: Vector2 = src[(i + 1) % n]
		var ra := minf(r, p.distance_to(a) * 0.45)
		var rb := minf(r, p.distance_to(b) * 0.45)
		var s := p + (a - p).normalized() * ra
		var e := p + (b - p).normalized() * rb
		for t in 7:
			var u := t / 6.0
			out.append(s.lerp(p, u).lerp(p.lerp(e, u), u))
	if closed:
		out.append(out[0])
	return out


func _logo_small_width() -> float:
	return (4.0 * 4.0 + 3.0 * BIG_GAP) * BIG_UNIT


func _logo_sub_w() -> float:
	var w := 9.0 * SMALL_GAP
	for ch in "EXTRACTION":
		w += GLYPH_W.get(ch, 4.0)
	return w * SMALL_UNIT


func _logo_sub_x() -> float:
	return (_logo_small_width() - _logo_sub_w()) * 0.5


func _logo_small_y() -> float:
	return 6.0 * BIG_UNIT + 30.0


## Środek ośmiokąta, który zastępuje "O".
func _logo_emblem() -> Vector2:
	return Vector2((2.0 * (4.0 + BIG_GAP) + 2.0) * BIG_UNIT, 3.0 * BIG_UNIT)


func _logo_xform(vs: Vector2) -> Transform2D:
	var s := 1.0 if screen == "main" else 0.4
	var o := Vector2(LEFT_X + 24.0, 64.0) if screen == "main" else Vector2(vs.x * 0.5 - _logo_small_width() * 0.5 * s, 18.0)
	o.x += (1.0 - Style.ease_out(screen_t)) * -60.0
	return Transform2D(Vector2(s, 0.0), Vector2(-LOGO_SKEW * s, s), o)


## Jedna rurka neonu. Warstwy: poświata na ścianie, szkło, gorący rdzeń, elektrody na końcach.
## glow = 0..1 (przygaszenie migającej rurki).
func _paint_tube(cv, pts: PackedVector2Array, w: float, glass: Color, core: Color, glow: float) -> void:
	var closed := pts[0].distance_to(pts[-1]) < 0.5
	# poświata rozlana po ścianie za szyldem
	for g in [[w * 4.2, 0.035], [w * 2.6, 0.06], [w * 1.7, 0.12]]:
		var gc := Color(glass.r, glass.g, glass.b, g[1] * glow)
		cv.draw_polyline(pts, gc, g[0])
		if not closed:
			cv.draw_circle(pts[0], g[0] * 0.5, gc)
			cv.draw_circle(pts[-1], g[0] * 0.5, gc)
	# szkło: przy przygaśnięciu ciemnieje, ale rurka zostaje widoczna
	var gl := glass.lerp(Color(0.18, 0.04, 0.16), 1.0 - glow)
	cv.draw_polyline(pts, gl, w)
	for p in pts:
		cv.draw_circle(p, w * 0.5, gl)
	# gorący środek gazu
	if glow > 0.05:
		var cc := core.lerp(gl, 1.0 - glow)
		cv.draw_polyline(pts, cc, w * 0.36)
		for p in pts:
			cv.draw_circle(p, w * 0.18, cc)
	# elektrody: krótkie ciemne nasadki na wolnych końcach rurki
	if not closed and w > 4.0:
		for e in [[pts[0], pts[1]], [pts[-1], pts[-2]]]:
			var d: Vector2 = (e[0] - e[1]).normalized()
			cv.draw_line(e[0] - d * 1.0, e[0] + d * 4.0, Color(0.12, 0.03, 0.12), w * 0.7)


## Ośmiokąt Statku Matki w miejscu "O": obraca się, a pod kursorem przyspiesza.
func _emblem_points(r: float) -> PackedVector2Array:
	var c := _logo_emblem()
	var pts := PackedVector2Array()
	for k in 9:
		pts.append(c + Vector2.from_angle(logo_spin + PI / 8.0 + k / 8.0 * TAU) * r)
	return pts


## Jasność migającej rurki: przez większość czasu świeci, raz na kilka sekund krótko się krztusi.
func _tube_flicker() -> float:
	var ft := fmod(time, 6.3)
	if ft > 5.62 and ft < 5.7:
		return 0.15
	if ft > 5.78 and ft < 5.83:
		return 0.35
	if ft > 5.9 and ft < 5.93:
		return 0.1
	return 1.0


func _draw_logo_glow() -> void:
	var vs := get_viewport_rect().size
	var cv := logo_glow
	var xf := _logo_xform(vs)
	cv.draw_set_transform_matrix(xf)
	var ec := _logo_emblem()
	var fl := _tube_flicker()
	# rurki liter są nieruchome: liczone raz (wersja z zapaloną i przygaszoną "zmęczoną" rurką)
	if logo_meshes.is_empty():
		for dim in [false, true]:
			var mp = MeshPainter.new()
			for t in _logo_tubes():
				_paint_tube(mp, t[0], t[1], t[2], t[3], 0.15 if dim and t[4] else 1.0)
			logo_meshes.append(mp.build_mesh())
	cv.draw_mesh(logo_meshes[0 if fl > 0.5 else 1], null)
	# ośmiokąt: rurka w kolorze cyjanu, wnętrze jak w Statku Matce
	var ring := _bend(_emblem_points(3.1 * BIG_UNIT), 0.5 * BIG_UNIT)
	_paint_tube(cv, ring, BIG_TUBE, CYAN_GLASS, CYAN_CORE, 1.0)
	for k in 4:
		var d := Vector2.from_angle(-logo_spin * 1.6 + k / 4.0 * TAU + PI / 4.0)
		var arm := PackedVector2Array([ec + d * 0.95 * BIG_UNIT, ec + d * 2.15 * BIG_UNIT])
		_paint_tube(cv, arm, 4.0, CYAN_GLASS, CYAN_CORE, 1.0)
	var pulse := 0.5 + 0.5 * sin(time * 2.4)
	var hub := _bend(PackedVector2Array([ec + Vector2(0.8 * BIG_UNIT, 0), ec + Vector2(0, 0.8 * BIG_UNIT), ec + Vector2(-0.8 * BIG_UNIT, 0), ec + Vector2(0, -0.8 * BIG_UNIT), ec + Vector2(0.8 * BIG_UNIT, 0)]), 0.25 * BIG_UNIT)
	_paint_tube(cv, hub, 4.0, NEON_GLASS, NEON_CORE, 1.0)
	cv.draw_circle(ec, 0.42 * BIG_UNIT + 6.0 * pulse + logo_boost * 4.0, Color(1.0, 0.25, 0.75, 0.12))
	cv.draw_circle(ec, 0.22 * BIG_UNIT + logo_boost * 2.0, Color(1.5, 1.2, 1.5))
	cv.draw_set_transform_matrix(Transform2D.IDENTITY)


## Obrót ośmiokąta; pod kursorem przyspiesza.
func _update_logo(delta: float) -> void:
	var vs := get_viewport_rect().size
	var xf := _logo_xform(vs)
	var local := xf.affine_inverse() * mouse
	var over := Rect2(-30.0, -20.0, _logo_small_width() + 60.0, _logo_small_y() + 90.0).has_point(local)
	logo_boost = lerpf(logo_boost, 1.0 if over else 0.0, 1.0 - exp(-6.0 * delta))
	logo_spin += delta * (0.25 + 2.2 * logo_boost)


## Przycisk: po najechaniu wysuwa się w prawo, zapala pasek i biegnące szewrony.
func _button(r: Rect2, text: String, fsize: int, idx, selected: bool, anim_key: String, col := Style.PINK) -> void:
	hits.append([r, idx])
	var k: float = btn_anim.get(anim_key, 0.0)
	btn_anim[anim_key] = lerpf(k, 1.0 if selected else 0.0, 0.25)
	var e := Style.ease_out(k)
	var b := Rect2(r.position + Vector2(18.0 * e, 0), r.size)
	var c: Color = col.lerp(Style.GOLD, e)
	Style.chamfer_panel(self, b, c, Color(0.03 + 0.13 * e, 0.0 + 0.07 * e, 0.06 - 0.03 * e, 0.92), 10.0)
	if e > 0.02:
		draw_rect(Rect2(b.position.x, b.position.y + 10, 5.0 * e, b.size.y - 20), Color(1.3, 1.0, 0.45))
		var sw := fmod(time * 0.8, 1.0)
		var sx := b.position.x + sw * b.size.x
		draw_line(Vector2(sx, b.position.y + 1), Vector2(minf(sx + 50.0, b.end.x), b.position.y + 1), Color(1.3, 1.1, 0.6, e), 2.0)
		for j in 3:
			var cx := b.end.x - 30.0 - j * 12.0
			var a := 0.25 + 0.75 * fmod(time * 1.6 + j * 0.33, 1.0)
			var cy := b.get_center().y
			draw_polyline(PackedVector2Array([Vector2(cx - 4, cy - 8), Vector2(cx + 4, cy), Vector2(cx - 4, cy + 8)]), Color(1.3, 1.0, 0.45, a * e), 2.0, true)
	var tc := Color(c.r, c.g, c.b).lerp(Color(1.3, 1.0, 0.45), e)
	# linia bazowa nieco niżej, żeby kreski nad literami (Ś, Ó) nie dotykały ramki
	_txt(Vector2(b.position.x + 24.0, b.get_center().y + fsize * 0.33 + 3.0), text, fsize, tc)


func _draw_main(_vs: Vector2) -> void:
	for i in MAIN_ITEMS.size():
		_button(Rect2(LEFT_X, 310 + i * 76, 400, 60), MAIN_ITEMS[i], 32, i, sel == i, "m%d" % i)
	# Statek Matka jest klikalny tylko w swoim okręgu
	if mother_hover:
		var c := _mother_pos(get_viewport_rect().size)
		hits.append([Rect2(c - Vector2(MOTHER_R, MOTHER_R), Vector2(MOTHER_R, MOTHER_R) * 2.0), "mother"])


func _draw_slots(vs: Vector2) -> void:
	_ctxt(vs.x * 0.5, 170, "WYBIERZ ZAPIS", 32, Style.CYAN)
	var cw := 420.0
	var ch := 300.0
	var gap := 36.0
	var x0 := vs.x * 0.5 - (cw * 3 + gap * 2) * 0.5
	var y0 := 210.0
	for i in GameState.SAVE_SLOTS:
		var info: Dictionary = slot_cache[i] if i < slot_cache.size() else {}
		var selected := sel == i
		var k: float = btn_anim.get("s%d" % i, 0.0)
		btn_anim["s%d" % i] = lerpf(k, 1.0 if selected else 0.0, 0.25)
		var e := Style.ease_out(k)
		var base := Rect2(x0 + i * (cw + gap), y0, cw, ch)
		hits.append([base, i])
		var r := Rect2(base.position - Vector2(0, 12.0 * e), base.size)
		var bc: Color = Style.PINK.lerp(Style.GOLD, e)
		Style.chamfer_panel(self, r, bc, Color(0.03 + 0.08 * e, 0.0 + 0.05 * e, 0.06, 0.96), 14.0)
		var cx := r.get_center().x
		_ctxt(cx, r.position.y + 46, "ZAPIS %d" % (i + 1), 32, Style.GOLD.lerp(Color(1.3, 1.0, 0.45), e))
		draw_line(r.position + Vector2(24, 62), Vector2(r.end.x - 24, r.position.y + 62), Color(bc.r, bc.g, bc.b, 0.4), 1.0)
		if info.is_empty():
			# pusty slot: mały Statek Matka czeka na załogę
			var c := Vector2(cx, r.position.y + 130)
			var oct := PackedVector2Array()
			for j in 9:
				oct.append(c + Vector2.from_angle(time * 0.4 + j / 8.0 * TAU) * 28.0)
			draw_polyline(oct, Color(Style.PINK.r, Style.PINK.g, Style.PINK.b, 0.5 + 0.5 * e), 2.0, true)
			draw_circle(c, 5.0, Style.CYAN)
			_ctxt(cx, r.position.y + 210, "NOWA GRA", 24, Style.GREEN.lerp(Color(0.6, 1.2, 0.65), e))
		else:
			var lines := [
				["WYPRAWY", str(info["sorties"])],
				["ULEPSZENIA", str(info["upgrades"])],
				["ZNISZCZONE", str(info["tiles"])],
				["SUROWCE", str(info["resources"])],
				["POTĘGA", str(info["power"])],
			]
			var ly := r.position.y + 100
			for ln in lines:
				_txt(Vector2(r.position.x + 28, ly), ln[0], 16, Style.TEXT_DIM)
				_txt(Vector2(r.end.x - 28 - _tw(ln[1], 16), ly), ln[1], 16, Style.TEXT)
				ly += 28
			var dt := Time.get_datetime_string_from_unix_time(int(info["time"]) + _tz_bias(), true)
			_ctxt(cx, r.end.y - 18, dt.substr(0, 16), 16, Color(0.6, 0.55, 0.72))
			# usuwanie (z potwierdzeniem)
			var dr := Rect2(base.end.x - 130, base.end.y + 10, 130, 34)
			hits.push_front([dr, "del%d" % i])
			var armed := delete_armed == i
			var dc := Style.RED if armed else Color(0.72, 0.42, 0.55)
			Style.chamfer_panel(self, dr, dc, Color(0.08, 0.0, 0.02, 0.9), 6.0)
			var dtx := "NA PEWNO?" if armed else "USUŃ"
			_txt(Vector2(dr.get_center().x - _tw(dtx, 16) * 0.5, dr.position.y + 23), dtx, 16, dc)
	_button(Rect2(vs.x * 0.5 - 130, y0 + ch + 70, 260, 52), "< WRÓĆ", 24, GameState.SAVE_SLOTS, sel == GameState.SAVE_SLOTS, "sb")


func _tz_bias() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _draw_options(vs: Vector2) -> void:
	_ctxt(vs.x * 0.5, 150, "OPCJE", 32, Style.CYAN)
	var w := 820.0
	var x := vs.x * 0.5 - w * 0.5
	var y := 176.0
	for i in OPT_ITEMS.size():
		var key: String = OPT_ITEMS[i]
		if key == "back":
			_button(Rect2(vs.x * 0.5 - 130, y + 12, 260, 52), "< WRÓĆ", 24, i, sel == i, "ob")
			break
		var selected := sel == i
		var k: float = btn_anim.get("o%d" % i, 0.0)
		btn_anim["o%d" % i] = lerpf(k, 1.0 if selected else 0.0, 0.25)
		var e := Style.ease_out(k)
		var r := Rect2(x + 10.0 * e, y, w, 50)
		hits.append([Rect2(x, y, w, 50), i])
		var bc: Color = Color(Style.PINK.r, Style.PINK.g, Style.PINK.b, 0.6).lerp(Style.GOLD, e)
		Style.chamfer_panel(self, r, bc, Color(0.03 + 0.08 * e, 0.0 + 0.05 * e, 0.06, 0.93), 8.0)
		_txt(Vector2(r.position.x + 24, y + 34), Options.NAMES[key], 24, Style.TEXT.lerp(Color(1.3, 1.0, 0.45), e))
		var val := Options.value_text(key)
		var vx := x + w - 300
		var lr := Rect2(vx, y + 5, 40, 40)
		var rr := Rect2(x + w - 50, y + 5, 40, 40)
		hits.push_front([lr, "opt-" + key])
		hits.push_front([rr, "opt+" + key])
		var ac := Style.GOLD if selected else Color(0.65, 0.55, 0.75)
		_txt(Vector2(lr.position.x + 12, y + 34), "<", 24, ac)
		_txt(Vector2(rr.position.x + 14, y + 34), ">", 24, ac)
		var mid := (lr.end.x + rr.position.x) * 0.5
		if key in ["volume", "music", "sfx"]:
			# suwak: kliknij lub przeciągnij po kreskach
			var segs := 10
			var bw := 160.0
			var bx := mid - bw * 0.5 - 20
			var v := int(GameState.settings[key]) / 10
			for s in segs:
				var sr := Rect2(bx + s * (bw / segs), y + 16, bw / segs - 3, 18)
				hits.push_front([sr.grow(2.0), Options.volume_action(key, (s + 1) * 10)])
				draw_rect(sr, Style.CYAN if s < v else Color(0.2, 0.15, 0.25))
			_txt(Vector2(bx + bw + 10, y + 34), val, 16, Style.TEXT)
		else:
			var vc := Style.TEXT
			if val == "WŁ.":
				vc = Color(0.5, 1.2, 0.55)
			elif val == "WYŁ.":
				vc = Color(1.0, 0.4, 0.45)
			_ctxt(mid, y + 34, val, 24, vc)
		y += 54


## Osiągnięcia: karty z neonowymi odznakami (rysuje je autoload Achievements).
func _draw_achievements(vs: Vector2) -> void:
	_ctxt(vs.x * 0.5, 150, "OSIĄGNIĘCIA", 32, Style.CYAN)
	var n: int = Achievements.DEFS.size()
	_ctxt(vs.x * 0.5, 182, "ZDOBYTE: %d / %d" % [Achievements.count(), n], 16, Style.TEXT_DIM)
	var w := minf(980.0, vs.x - 80.0)
	var h: float = Achievements.draw_list(self, Rect2(vs.x * 0.5 - w * 0.5, 210, w, 0), time)
	_button(Rect2(vs.x * 0.5 - 130, 210 + h + 36, 260, 52), "< WRÓĆ", 24, 0, sel == 0, "ab")


## Sterowanie: dwie kolumny akcji. Klik (albo ENTER) na wierszu czeka na nowy klawisz.
func _draw_controls(vs: Vector2) -> void:
	_ctxt(vs.x * 0.5, 160, "STEROWANIE", 32, Style.CYAN)
	var acts: Array = GameState.KEY_ACTIONS
	var per_col := int(ceil(acts.size() / 2.0))
	var w := 520.0
	var gap := 28.0
	var x0 := vs.x * 0.5 - w - gap * 0.5
	var y0 := 190.0
	for i in acts.size():
		var col := i / per_col
		var row := i % per_col
		var r := Rect2(x0 + col * (w + gap), y0 + row * 52, w, 44)
		hits.append([r, i])
		var selected := sel == i
		var waiting: bool = rebinding == acts[i][0]
		var k: float = btn_anim.get("c%d" % i, 0.0)
		btn_anim["c%d" % i] = lerpf(k, 1.0 if selected or waiting else 0.0, 0.25)
		var e := Style.ease_out(k)
		var bc: Color = Color(Style.PINK.r, Style.PINK.g, Style.PINK.b, 0.6).lerp(Style.GOLD, e)
		Style.chamfer_panel(self, r, bc, Color(0.03 + 0.08 * e, 0.0 + 0.05 * e, 0.06, 0.93), 8.0)
		_txt(Vector2(r.position.x + 18, r.position.y + 30), String(acts[i][1]).to_upper(), 16, Style.TEXT.lerp(Color(1.3, 1.0, 0.45), e))
		# klawisz w ramce po prawej
		var label := "NACIŚNIJ KLAWISZ..." if waiting else GameState.key_name(acts[i][0])
		var kw := maxf(_tw(label, 16) + 24.0, 64.0)
		var kr := Rect2(r.end.x - 12 - kw, r.position.y + 7, kw, 30)
		var pulse := 0.5 + 0.5 * sin(time * 8.0)
		var kc: Color = Style.CYAN if not waiting else Color(1.3, 1.0, 0.45, 0.5 + 0.5 * pulse)
		Style.chamfer_panel(self, kr, kc, Color(0.02, 0.05, 0.08, 0.95), 5.0)
		_txt(Vector2(kr.get_center().x - _tw(label, 16) * 0.5, kr.position.y + 22), label, 16, kc)
	var by := y0 + per_col * 52 + 24
	var n: int = acts.size()
	_button(Rect2(vs.x * 0.5 - 290, by, 300, 52), "DOMYŚLNE", 24, n, sel == n, "cd")
	_button(Rect2(vs.x * 0.5 + 30, by, 260, 52), "< WRÓĆ", 24, n + 1, sel == n + 1, "cb")
	var hint := "KLIKNIJ AKCJĘ I NACIŚNIJ NOWY KLAWISZ. ZAJĘTY KLAWISZ ZAMIENIA SIĘ MIEJSCAMI."
	_ctxt(vs.x * 0.5, by + 92, hint, 16, Style.TEXT_DIM)
