extends Control
## Walka o metropolię: osobna minigra w stylu starych strzelanek z widokiem z góry.
## Statek leci cały czas do przodu i strzela sam, gracz tylko manewruje. Etap to fale wrogów,
## wieżowce-przeszkody i lasery, a na końcu boss. Główna gra stoi w tym czasie w pauzie.

signal finished(won: bool)

const Sectors = preload("res://scripts/sectors.gd")
const Style = preload("res://scripts/style.gd")

const FIELD_W := 1000.0
const SPEED := 470.0
const SPEED_FOCUS := 210.0
const ACCEL_RATE := 11.0     # jak szybko statek nabiera prędkości (większe = ostrzej)
const STOP_RATE := 8.0       # jak szybko wyhamowuje po puszczeniu klawiszy
const FOCUS_RATE := 18.0     # w precyzyjnym locie reaguje szybciej, do mijania pocisków
const TILT_RATE := 10.0
const HITBOX := 5.0
const STAGE_LEN := 62.0
const BOSS_HP := 1000.0
const SCROLL := 210.0
const MAX_BULLETS := 500
# animacja wejścia: skok przez nadprzestrzeń, uderzenie w chwili IMPACT, potem rozsuwane pasy i wlot statku
const INTRO_FADE := 0.2
const IMPACT := 0.75
const SHUTTER_END := 1.35
const SHIP_IN_END := 1.6
const INTRO_LEN := 3.6
const DEATH_LEN := 4.2
const CROWN_RAYS := 7
const MAX_SPARKS := 600
const MAX_DEBRIS := 140

## Scenariusz etapu: [sekunda, co, parametr].
const WAVES := [
	[2.0, "darts", -1.0], [6.0, "darts", 1.0], [10.0, "sweep", -1.0], [13.5, "towers", 0.3],
	[16.5, "gunship", 0.5], [20.0, "darts_v", 0.0], [23.0, "laser_h", 0.45], [24.0, "towers", 0.72],
	[26.5, "gunship", 0.25], [26.5, "gunship", 0.75], [30.5, "sweep", 1.0], [33.5, "towers", 0.2],
	[35.5, "towers", 0.55], [37.5, "towers", 0.85], [40.5, "laser_v", 0.25], [41.5, "laser_v", 0.6],
	[42.5, "laser_v", 0.85], [44.5, "gunship", 0.5], [45.0, "darts", -1.0], [46.5, "darts", 1.0],
	[50.0, "heavy", 0.5], [58.0, "laser_h", 0.6], [58.5, "darts_v", 0.0],
]

## Samouczek pierwszej walki: [tytuł, tekst]. W czasie czytania można już polatać.
const TUTORIAL := [
	["LOT I OGIEŃ",
		"Statek strzela sam, Ty tylko manewrujesz: {move} lub strzałki.\n\nMożesz już spróbować - etap ruszy dopiero po tym samouczku."],
	["PUNKT TRAFIENIA",
		"Pociski trafiają tylko w świecący punkt na środku statku, więc skrzydła mogą je muskać.\n\nPrzytrzymaj {focus}, żeby lecieć wolniej i precyzyjnie mijać pociski."],
	["BOMBY",
		"{drift} odpala bombę: kasuje wszystkie pociski, rani wrogów i na chwilę chroni statek.\n\nBomb jest mało, zachowaj je na trudne momenty. Stan kadłuba i bomb widzisz po lewej."],
	["ZAGROŻENIA",
		"Wieżowce nadlatują rzędami, szukaj w nich przerwy. Laser najpierw ostrzega, a po chwili strzela całą linią, więc zejdź z niej.\n\nZe zniszczonych wrogów wypadają znajdźki: siła ognia, kadłub i bomby."],
	["STRAŻNICZKA WOLNOŚCI",
		"Pasek DO CELU po prawej pokazuje drogę do bossa.\n\nJeśli zginiesz, stracisz ładunek i wrócisz do Statku Matki. Do walki wejdziesz znowu przez różowy punkt w mieście, klawiszem E."],
]

var sector := 0
var city_name := ""
var boss_title := "STRAŻNICZKA WOLNOŚCI"
var boss_kind := "liberty"
var boss_max_hp := BOSS_HP
var field_h := 900.0
var field_x := 0.0
var state := "intro"      # intro / tutorial / stage / warning / boss / boss_dead / win / lose
var state_t := INTRO_LEN
var time := 0.0
var stage_t := 0.0
var wave_idx := 0
var done := false

var player := Vector2.ZERO
var player_vel := Vector2.ZERO
var tilt := 0.0           # przechył statku w locie na boki (-1..1)
var trail := PackedVector2Array()
var reward := true        # Punkt Chwały tylko za pierwsze zwycięstwo
var hp := 4
var max_hp := 4
var inv_t := 0.0
var bombs := 2
var power := 1
var fire_t := 0.0
var focus := false
var bomb_held := false
var bomb_flash := 0.0

var shots: Array = []     # {pos, vel}
var bullets: Array = []   # {pos, vel, r, col}
var enemies: Array = []   # {kind, pos, hp, t, cd, ...}
var towers: Array = []    # {rect, seed}
var lasers: Array = []    # {axis, at, t}
var pickups: Array = []   # {pos, kind}
var sparks: Array = []    # {pos, vel, life, col}
var rings: Array = []     # {pos, r, life, max, col, w}
var bursts: Array = []    # kolczaste słońca: {pos, r, life, max, col, rot, spikes}
var flashes: Array = []   # błyski: {pos, r, life, max, col}
var debris: Array = []    # odłamki: {pos, vel, rot, spin, life, max, pts, col}
var smokes: Array = []    # dym: {pos, vel, r, life, max}
var queued: Array = []    # wybuchy z opóźnieniem: {t, kind, pos, col}
var shake_amt := 0.0
var hitstop := 0.0        # krótkie zamrożenie akcji przy mocnych trafieniach
var slowmo := 0.0
var full_flash := 0.0
var death_t := 0.0
var part_t := 0.0
var boss: Dictionary = {}

var font: Font
var pf: Font
var stars: Array = []
var blocks: Array = []    # panorama miasta: [x, szerokość, wysokość]
var streaks: Array = []   # smugi skoku: [kąt, faza, kolor 0-1]
var music_on := false
var neon := 0.0           # wygładzone pulsowanie neonów w tle (0..1)
var tut_page := 0
var tut_appear := 0.0
var tut_ok := Rect2()
var tut_skip := Rect2()


func setup(p_sector: int) -> void:
	sector = p_sector
	var info: Dictionary = Sectors.boss_info(p_sector)
	city_name = String(info.get("name", "")) if p_sector >= 100 else GameState.city_name(p_sector)
	boss_title = Sectors.boss_name(p_sector)
	boss_kind = String(info.get("boss_kind", "liberty"))
	boss_max_hp = 1400.0 if p_sector >= 100 else BOSS_HP
	# ulepszenia statku przekładają się na wytrzymałość i startową siłę ognia
	max_hp = clampi(3 + int((GameState.stat("max_hull") + GameState.stat("max_shield")) / 100.0), 3, 8)
	hp = max_hp
	reward = GameState.boss_state(p_sector) != "beaten"
	power = clampi(1 + int(GameState.stat("laser_dps") / 60.0), 1, 3)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = Style.font_bold()
	pf = Style.font_pixel()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for k in 120:
		stars.append(Vector3(rng.randf(), rng.randf() * 0.34, rng.randf_range(1.0, 2.0)))
	for k in 110:
		streaks.append(Vector3(rng.randf() * TAU, rng.randf(), rng.randf()))
	var x := -780.0
	while x < 780.0:
		var w := rng.randf_range(34.0, 70.0)
		blocks.append([x, w, rng.randf_range(50.0, 150.0)])
		x += w + rng.randf_range(2.0, 14.0)
	var vs := get_viewport_rect().size
	field_h = vs.y
	field_x = (vs.x - FIELD_W) * 0.5
	player = Vector2(FIELD_W * 0.5, field_h - 130.0)
	Audio.stop_loops()
	Audio.stop_music()
	Audio.play("boss_enter", 0.0)


func _process(delta: float) -> void:
	if GameState.pause_menu:
		return
	_step(minf(delta, 0.05))
	queue_redraw()


## ESC w walce otwiera pauzę (główna gra stoi, więc jej obsługa klawiszy tu nie dociera).
func _unhandled_input(event: InputEvent) -> void:
	if GameState.pause_menu or done:
		return
	if GameState.key_hit(event, "pause"):
		var main := get_tree().current_scene
		if main and main.get("pause_menu"):
			main.pause_menu.open(true)
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if state != "tutorial" or tut_appear < 0.5 or GameState.pause_menu:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER:
			_tutorial_next()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if tut_ok.has_point(event.position):
			_tutorial_next()
			get_viewport().set_input_as_handled()
		elif tut_skip.has_point(event.position):
			_tutorial_end()
			get_viewport().set_input_as_handled()


func _tutorial_next() -> void:
	tut_page += 1
	if tut_page >= TUTORIAL.size():
		_tutorial_end()
	else:
		tut_appear = 0.0
		Audio.play("popup", 0.0)


func _tutorial_end() -> void:
	GameState.boss_tutorial = true
	state = "stage"


# =====================================================================
# LOGIKA
# =====================================================================

func _step(delta: float) -> void:
	time += delta
	shake_amt = move_toward(shake_amt, 0.0, 42.0 * delta)
	full_flash = maxf(0.0, full_flash - delta * 1.6)
	if hitstop > 0.0:
		hitstop -= delta
		return
	if slowmo > 0.0:
		slowmo -= delta
		delta *= 0.35
	if not music_on and time >= IMPACT:
		music_on = true
		var track: String = String(Sectors.boss_info(sector).get("boss_music", ""))
		if track != "":
			Audio.play_boss_music(track)
		else:
			Audio.play_game_music()
	# szybkie narastanie, wolniejsze gaśnięcie: miękki puls zamiast migania
	var beat: float = Audio.beat_pulse
	neon = lerpf(neon, beat, 1.0 - exp(-(16.0 if beat > neon else 5.0) * delta))
	inv_t = maxf(0.0, inv_t - delta)
	bomb_flash = maxf(0.0, bomb_flash - delta * 2.0)
	match state:
		"intro":
			state_t -= delta
			if state_t <= 0.0:
				if GameState.boss_tutorial:
					state = "stage"
				else:
					state = "tutorial"
					Audio.play("popup", 0.0)
		"tutorial":
			tut_appear = minf(1.0, tut_appear + delta * 5.0)
		"stage":
			stage_t += delta
			_run_waves()
			if stage_t >= STAGE_LEN and (enemies.is_empty() or stage_t >= STAGE_LEN + 8.0):
				state = "warning"
				state_t = 3.0
				enemies.clear()
				Audio.play("alarm", 0.0)
		"warning":
			state_t -= delta
			if state_t <= 0.0:
				_spawn_boss()
		"boss":
			_update_boss(delta)
		"boss_dead":
			_update_boss_death(delta)
		"boss_final":
			state_t -= delta
			if state_t <= 0.0:
				state = "win"
				state_t = 3.5
				Audio.play("research_done", 0.0)
		"win", "lose":
			state_t -= delta
			if state_t <= 0.0 and not done:
				done = true
				finished.emit(state == "win")
	if state != "lose":
		_update_player(delta)
	_update_shots(delta)
	_update_bullets(delta)
	_update_enemies(delta)
	_update_towers(delta)
	_update_lasers(delta)
	_update_pickups(delta)
	_update_fx(delta)


func _run_waves() -> void:
	while wave_idx < WAVES.size() and stage_t >= WAVES[wave_idx][0]:
		_spawn_wave(WAVES[wave_idx][1], WAVES[wave_idx][2])
		wave_idx += 1


func _spawn_wave(what: String, p: float) -> void:
	match what:
		"darts":
			for k in 5:
				var x := FIELD_W * 0.5 + p * 320.0 - p * k * 40.0
				_add_enemy("dart", Vector2(x, -40.0 - k * 70.0), 3, p)
		"darts_v":
			for k in 7:
				_add_enemy("dart", Vector2(FIELD_W * 0.5 + (k - 3) * 95.0, -40.0 - absi(k - 3) * 60.0), 3, 0.0)
		"sweep":
			for k in 6:
				_add_enemy("sweeper", Vector2(FIELD_W * 0.5 - p * (FIELD_W * 0.5 + 60.0 + k * 80.0), 130.0 + k * 20.0), 2, p)
		"gunship":
			_add_enemy("gunship", Vector2(FIELD_W * p, -60.0), 16, 0.0)
		"heavy":
			_add_enemy("heavy", Vector2(FIELD_W * p, -90.0), 70, 0.0)
		"towers":
			_tower_row(p)
		"laser_h":
			lasers.append({"axis": "h", "at": field_h * p, "t": 0.0})
			Audio.play("warning", 0.0)
		"laser_v":
			lasers.append({"axis": "v", "at": FIELD_W * p, "t": 0.0})
			Audio.play("warning", 0.0)


func _add_enemy(kind: String, pos: Vector2, enemy_hp: int, side: float) -> void:
	enemies.append({"kind": kind, "pos": pos, "hp": float(enemy_hp), "t": randf() * 0.5, "cd": randf_range(0.8, 1.8), "side": side, "flash": 0.0, "angle": 0.0})


## Rząd wieżowców z przerwą (przelot) na szerokości p.
func _tower_row(p: float) -> void:
	var gap := 250.0
	var cx := FIELD_W * p
	var h := randf_range(110.0, 190.0)
	var left := cx - gap * 0.5
	if left > 10.0:
		towers.append({"rect": Rect2(0.0, -h, left, h), "seed": randi() % 1000})
	var right := cx + gap * 0.5
	if right < FIELD_W - 10.0:
		towers.append({"rect": Rect2(right, -h, FIELD_W - right, h), "seed": randi() % 1000})


func _update_player(delta: float) -> void:
	# w czasie animacji wejścia statek sam wlatuje na pole walki
	if time < SHIP_IN_END:
		var k := clampf((time - IMPACT) / (SHIP_IN_END - IMPACT), 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0)
		player = Vector2(FIELD_W * 0.5, lerpf(field_h + 60.0, field_h - 130.0, k))
		trail.append(player + Vector2(0, 15))
		if trail.size() > 16:
			trail.remove_at(0)
		return
	var mv := Vector2.ZERO
	if GameState.key_down("left") or Input.is_physical_key_pressed(KEY_LEFT):
		mv.x -= 1.0
	if GameState.key_down("right") or Input.is_physical_key_pressed(KEY_RIGHT):
		mv.x += 1.0
	if GameState.key_down("thrust") or Input.is_physical_key_pressed(KEY_UP):
		mv.y -= 1.0
	if GameState.key_down("brake") or Input.is_physical_key_pressed(KEY_DOWN):
		mv.y += 1.0
	focus = GameState.key_down("focus")
	# pęd: prędkość dąży do celu płynnie, a przy precyzyjnym locie statek reaguje ostrzej
	var want := mv.normalized() * (SPEED_FOCUS if focus else SPEED)
	var rate := FOCUS_RATE if focus else (ACCEL_RATE if mv != Vector2.ZERO else STOP_RATE)
	player_vel = player_vel.lerp(want, 1.0 - exp(-rate * delta))
	player += player_vel * delta
	var clamped := player.clamp(Vector2(22.0, 22.0), Vector2(FIELD_W - 22.0, field_h - 22.0))
	if clamped.x != player.x:
		player_vel.x = 0.0
	if clamped.y != player.y:
		player_vel.y = 0.0
	player = clamped
	tilt = lerpf(tilt, clampf(player_vel.x / SPEED, -1.0, 1.0), 1.0 - exp(-TILT_RATE * delta))
	trail.append(player + Vector2(0, 15))
	if trail.size() > 16:
		trail.remove_at(0)
	var bomb_key := GameState.key_down("drift")
	if bomb_key and not bomb_held:
		_use_bomb()
	bomb_held = bomb_key
	if state == "win" or state == "boss_dead" or state == "boss_final" or state == "tutorial":
		return
	fire_t -= delta
	if fire_t <= 0.0:
		fire_t = 0.1
		_fire()


func _fire() -> void:
	var angles := [0.0]
	match power:
		2: angles = [-0.03, 0.03]
		3: angles = [-0.14, 0.0, 0.14]
		4: angles = [-0.24, -0.08, 0.08, 0.24]
	if power >= 5:
		angles = [-0.3, -0.15, 0.0, 0.15, 0.3]
	for a in angles:
		shots.append({"pos": player + Vector2(0, -22), "vel": Vector2.UP.rotated(a) * 950.0})
	Audio.play("gun_shot", 0.1, -10.0)


func _use_bomb() -> void:
	if bombs <= 0 or state == "lose" or state == "win" or state == "tutorial":
		return
	bombs -= 1
	bomb_flash = 1.0
	bullets.clear()
	inv_t = maxf(inv_t, 1.0)
	for e in enemies:
		e["hp"] -= 12.0
	if not boss.is_empty():
		_hit_boss(25.0)
	_add_ring(player, 900.0, 0.6, Color(1.3, 0.8, 1.3), 8.0)
	_add_ring(player, 620.0, 0.45, Color(0.4, 1.2, 1.4), 5.0)
	_add_flash(player, 170.0, 0.3, Color(1.4, 1.2, 1.4))
	_add_burst(player, 240.0, 0.5, Color(1.3, 0.5, 1.2), 18)
	_sparks(player, Color(1.3, 0.7, 1.3), 50, 620.0)
	shake_amt = maxf(shake_amt, 15.0)
	Audio.play("bomb_blast", 0.0, 1.0)


func _update_shots(delta: float) -> void:
	for s in shots:
		s["pos"] += s["vel"] * delta
		var dead: bool = s["pos"].y < -20.0 or s["pos"].x < -20.0 or s["pos"].x > FIELD_W + 20.0
		if not dead:
			for t in towers:
				if t["rect"].has_point(s["pos"]):
					dead = true
					_sparks(s["pos"], Color(1.0, 0.5, 1.0), 2, 150.0)
					break
		if not dead:
			for e in enemies:
				if e["hp"] > 0.0 and e["pos"].distance_to(s["pos"]) < _enemy_radius(e["kind"]):
					e["hp"] -= 1.0
					e["flash"] = 0.08
					dead = true
					_impact(s["pos"])
					break
		if not dead and state == "boss" and _boss_rect().has_point(s["pos"]):
			_impact(s["pos"])
			_hit_boss(1.0)
			dead = true
		if dead:
			s["dead"] = true
	shots = shots.filter(func(s): return not s.get("dead", false))


func _enemy_radius(kind: String) -> float:
	match kind:
		"gunship": return 34.0
		"heavy": return 62.0
	return 22.0


func _update_bullets(delta: float) -> void:
	for b in bullets:
		b["pos"] += b["vel"] * delta
		if b["pos"].distance_to(player) < b["r"] + HITBOX and state != "win" and state != "lose":
			b["dead"] = true
			_hurt()
		elif b["pos"].y < -30.0 or b["pos"].y > field_h + 30.0 or b["pos"].x < -30.0 or b["pos"].x > FIELD_W + 30.0:
			b["dead"] = true
	bullets = bullets.filter(func(b): return not b.get("dead", false))


func _shoot(pos: Vector2, dir: Vector2, speed: float, col := Color(1.4, 0.3, 1.0), r := 7.0) -> void:
	if bullets.size() < MAX_BULLETS:
		bullets.append({"pos": pos, "vel": dir * speed, "r": r, "col": col})


func _fan(pos: Vector2, n: int, spread: float, speed: float, col := Color(1.4, 0.3, 1.0)) -> void:
	var base := (player - pos).angle()
	for k in n:
		var a := base + (k - (n - 1) * 0.5) * spread
		_shoot(pos, Vector2.from_angle(a), speed, col)


func _ring(pos: Vector2, n: int, off: float, speed: float, col := Color(0.3, 1.1, 1.4)) -> void:
	for k in n:
		_shoot(pos, Vector2.from_angle(off + k * TAU / n), speed, col)


func _update_enemies(delta: float) -> void:
	for e in enemies:
		e["t"] += delta
		e["flash"] = maxf(0.0, e["flash"] - delta)
		e["cd"] -= delta
		var p: Vector2 = e["pos"]
		match e["kind"]:
			"dart":
				p.y += 210.0 * delta
				p.x += sin(e["t"] * 2.6) * 120.0 * delta + e["side"] * -30.0 * delta
				if e["cd"] <= 0.0 and p.y > 0.0 and p.y < field_h * 0.7:
					e["cd"] = randf_range(1.7, 2.6)
					_fan(p, 1, 0.0, 300.0)
			"sweeper":
				p.x += e["side"] * 300.0 * delta
				p.y += 35.0 * delta
				if e["cd"] <= 0.0 and p.x > 0.0 and p.x < FIELD_W:
					e["cd"] = randf_range(1.0, 1.6)
					_shoot(p, Vector2.DOWN, 340.0)
			"gunship":
				if e["t"] < 6.5:
					p.y = move_toward(p.y, 190.0, 170.0 * delta)
				else:
					p.y += 150.0 * delta
				if e["cd"] <= 0.0 and p.y > 60.0:
					e["cd"] = 1.35
					_ring(p, 10, e["angle"], 215.0)
					e["angle"] += 0.3
			"heavy":
				if e["t"] < 7.0:
					p.y = move_toward(p.y, 210.0, 120.0 * delta)
				else:
					p.y += 110.0 * delta
				p.x += sin(e["t"]) * 70.0 * delta
				if e["cd"] <= 0.0 and p.y > 80.0:
					e["cd"] = 0.12
					e["angle"] += 0.42
					_shoot(p, Vector2.from_angle(e["angle"]), 230.0, Color(1.4, 0.9, 0.3))
					_shoot(p, Vector2.from_angle(e["angle"] + PI), 230.0, Color(1.4, 0.9, 0.3))
		e["pos"] = p
		if p.distance_to(player) < _enemy_radius(e["kind"]) * 0.7:
			_hurt()
		if e["hp"] <= 0.0:
			_kill_enemy(e)
		elif p.y > field_h + 90.0 or (e["kind"] == "sweeper" and (p.x < -600.0 or p.x > FIELD_W + 600.0)):
			e["dead"] = true
	enemies = enemies.filter(func(e): return not e.get("dead", false))


func _kill_enemy(e: Dictionary) -> void:
	e["dead"] = true
	# każdy typ wroga wybucha inaczej
	match e["kind"]:
		"dart":
			_blast_pop(e["pos"], Color(1.3, 0.3, 0.5))
		"sweeper":
			_blast_shatter(e["pos"], Color(0.4, 1.2, 1.4))
		"gunship":
			_blast_mid(e["pos"], Color(1.4, 0.8, 0.3))
			_queue_blasts(e["pos"], 3, 55.0, 0.14, "pop", Color(1.4, 0.6, 0.25))
		"heavy":
			_blast_big(e["pos"], Color(1.4, 0.45, 1.1))
			_queue_blasts(e["pos"], 7, 90.0, 0.11, "mid", Color(1.4, 0.7, 0.3))
	if e["kind"] == "gunship":
		pickups.append({"pos": e["pos"], "kind": "power"})
	elif e["kind"] == "heavy":
		pickups.append({"pos": e["pos"] + Vector2(-30, 0), "kind": "heart"})
		pickups.append({"pos": e["pos"] + Vector2(30, 0), "kind": "bomb"})
	elif randf() < 0.05:
		pickups.append({"pos": e["pos"], "kind": "power"})


func _update_towers(delta: float) -> void:
	for t in towers:
		t["rect"].position.y += SCROLL * delta
		if t["rect"].has_point(player):
			_hurt()
	towers = towers.filter(func(t): return t["rect"].position.y < field_h + 20.0)


func _update_lasers(delta: float) -> void:
	for l in lasers:
		l["t"] += delta
		var on: bool = l["t"] >= 1.1 and l["t"] < 2.0
		if on:
			var d: float = absf(player.y - l["at"]) if l["axis"] == "h" else absf(player.x - l["at"])
			if d < 16.0:
				_hurt()
	lasers = lasers.filter(func(l): return l["t"] < 2.0)


func _update_pickups(delta: float) -> void:
	for p in pickups:
		p["pos"].y += 120.0 * delta
		if p["pos"].distance_to(player) < 42.0:
			p["dead"] = true
			match p["kind"]:
				"power": power = mini(power + 1, 5)
				"heart": hp = mini(hp + 1, max_hp)
				"bomb": bombs = mini(bombs + 1, 4)
			Audio.play("buy", 0.0)
		elif p["pos"].y > field_h + 30.0:
			p["dead"] = true
	pickups = pickups.filter(func(p): return not p.get("dead", false))


func _update_fx(delta: float) -> void:
	for s in sparks:
		s["pos"] += s["vel"] * delta
		s["vel"] *= exp(-3.0 * delta)
		s["life"] -= delta
	sparks = sparks.filter(func(s): return s["life"] > 0.0)
	for r in rings:
		r["life"] -= delta
	rings = rings.filter(func(r): return r["life"] > 0.0)
	for b in bursts:
		b["life"] -= delta
		b["rot"] += delta * 2.5
	bursts = bursts.filter(func(b): return b["life"] > 0.0)
	for f in flashes:
		f["life"] -= delta
	flashes = flashes.filter(func(f): return f["life"] > 0.0)
	for d in debris:
		d["pos"] += d["vel"] * delta
		d["vel"] = d["vel"] * exp(-1.1 * delta) + Vector2(0.0, 240.0 * delta)
		d["rot"] += d["spin"] * delta
		d["life"] -= delta
		if d.get("trail", false) and randf() < 0.35:
			_sparks(d["pos"], Color(1.3, 0.6, 0.25), 1, 60.0)
	debris = debris.filter(func(d): return d["life"] > 0.0)
	for s in smokes:
		s["pos"] += s["vel"] * delta
		s["r"] += 26.0 * delta
		s["life"] -= delta
	smokes = smokes.filter(func(s): return s["life"] > 0.0)
	for q in queued:
		q["t"] -= delta
		if q["t"] <= 0.0:
			match q["kind"]:
				"pop": _blast_pop(q["pos"], q["col"])
				"shatter": _blast_shatter(q["pos"], q["col"])
				"mid": _blast_mid(q["pos"], q["col"])
	queued = queued.filter(func(q): return q["t"] > 0.0)


# ---------------- klocki wybuchów ----------------

func _sparks(p: Vector2, c: Color, n: int, speed: float) -> void:
	for k in n:
		if sparks.size() >= MAX_SPARKS:
			return
		sparks.append({"pos": p, "vel": Vector2.from_angle(randf() * TAU) * randf_range(speed * 0.25, speed), "life": randf_range(0.25, 0.75), "col": c})


func _add_ring(p: Vector2, r: float, life: float, c: Color, w := 2.5) -> void:
	rings.append({"pos": p, "r": r, "life": life, "max": life, "col": c, "w": w})


func _add_burst(p: Vector2, r: float, life: float, c: Color, spikes := 12) -> void:
	bursts.append({"pos": p, "r": r, "life": life, "max": life, "col": c, "rot": randf() * TAU, "spikes": spikes})


func _add_flash(p: Vector2, r: float, life: float, c: Color) -> void:
	flashes.append({"pos": p, "r": r, "life": life, "max": life, "col": c})


## Odłamki: poszarpane wielokąty lecące i obracające się.
func _debris(p: Vector2, c: Color, n: int, speed: float, size := 10.0) -> void:
	for k in n:
		if debris.size() >= MAX_DEBRIS:
			return
		var pts := PackedVector2Array()
		var corners := randi_range(3, 5)
		for j in corners:
			pts.append(Vector2.from_angle(j * TAU / corners + randf_range(-0.3, 0.3)) * size * randf_range(0.5, 1.2))
		var life := randf_range(0.6, 1.3)
		debris.append({"pos": p, "vel": Vector2.from_angle(randf() * TAU) * randf_range(speed * 0.3, speed), "rot": randf() * TAU,
			"spin": randf_range(-9.0, 9.0), "life": life, "max": life, "pts": pts, "col": c, "trail": size > 14.0})


func _smoke(p: Vector2, n: int) -> void:
	for k in n:
		var life := randf_range(0.5, 1.2)
		smokes.append({"pos": p + Vector2(randf_range(-14, 14), randf_range(-14, 14)), "vel": Vector2(randf_range(-22, 22), randf_range(-60, -15)), "r": randf_range(7.0, 16.0), "life": life, "max": life})


func _queue_blasts(p: Vector2, n: int, spread: float, gap: float, kind: String, c: Color) -> void:
	for k in n:
		queued.append({"t": (k + 1) * gap + randf() * gap * 0.5, "kind": kind, "pos": p + Vector2.from_angle(randf() * TAU) * randf_range(spread * 0.3, spread), "col": c})


func _impact(p: Vector2) -> void:
	_sparks(p, Color(1.3, 1.1, 0.8), 2, 170.0)
	_add_flash(p, 11.0, 0.07, Color(1.4, 1.3, 1.1))
	Audio.play("hit_tick", 0.2)


## Mały, ognisty wybuch.
func _blast_pop(p: Vector2, c: Color) -> void:
	_sparks(p, c, 12, 240.0)
	_add_flash(p, 26.0, 0.13, Color(1.4, 1.2, 1.0))
	_add_burst(p, 30.0, 0.28, c, 9)
	_add_ring(p, 44.0, 0.28, c)
	_debris(p, c, 2, 170.0, 5.0)
	Audio.play("blast_pop", 0.14)


## Rozpad na kawałki: dużo odłamków i świetliste promienie.
func _blast_shatter(p: Vector2, c: Color) -> void:
	_debris(p, c, 8, 330.0, 8.0)
	_sparks(p, Color(1.2, 1.3, 1.4), 8, 300.0)
	_add_flash(p, 22.0, 0.1, Color(1.3, 1.4, 1.4))
	_add_ring(p, 60.0, 0.22, c, 3.5)
	Audio.play("blast_shatter", 0.14)


## Średni wybuch z falą i wstrząsem.
func _blast_mid(p: Vector2, c: Color) -> void:
	_sparks(p, c, 26, 340.0)
	_add_flash(p, 58.0, 0.18, Color(1.4, 1.2, 0.9))
	_add_burst(p, 70.0, 0.4, c, 13)
	_add_ring(p, 110.0, 0.42, c, 4.0)
	_add_ring(p, 62.0, 0.28, Color(1.4, 1.3, 1.1), 2.0)
	_debris(p, c, 6, 300.0, 11.0)
	_smoke(p, 3)
	shake_amt = maxf(shake_amt, 6.0)
	Audio.play("blast_mid", 0.12)


## Duży wybuch: dwa słońca, kilka fal, zamrożenie klatki.
func _blast_big(p: Vector2, c: Color) -> void:
	_sparks(p, c, 44, 520.0)
	_sparks(p, Color(1.4, 1.2, 0.8), 22, 330.0)
	_add_flash(p, 85.0, 0.22, Color(1.4, 1.3, 1.2))
	_add_burst(p, 150.0, 0.55, c, 16)
	_add_burst(p, 85.0, 0.4, Color(1.4, 1.1, 0.5), 11)
	_add_ring(p, 240.0, 0.6, c, 6.0)
	_add_ring(p, 150.0, 0.42, Color(1.4, 1.3, 1.2), 3.0)
	_debris(p, c, 12, 430.0, 15.0)
	_smoke(p, 6)
	shake_amt = maxf(shake_amt, 15.0)
	hitstop = maxf(hitstop, 0.05)
	Audio.play("boss_phase", 0.08, -3.0)


func _hurt() -> void:
	if inv_t > 0.0 or state == "lose" or state == "win" or state == "boss_dead" or state == "boss_final":
		return
	hp -= 1
	inv_t = 1.7
	_blast_pop(player, Color(1.4, 0.3, 0.2))
	shake_amt = maxf(shake_amt, 10.0)
	full_flash = maxf(full_flash, 0.12)
	Audio.play("ship_hit", 0.0, 3.0)
	# oddech po trafieniu: znikają pociski wokół statku
	for b in bullets:
		if b["pos"].distance_to(player) < 170.0:
			b["dead"] = true
	if hp <= 0:
		state = "lose"
		state_t = 3.0
		_blast_big(player, Color(1.4, 0.3, 0.9))
		_debris(player, Color(1.4, 0.3, 1.2), 10, 380.0, 9.0)


# =====================================================================
# BOSS
# =====================================================================

func _spawn_boss() -> void:
	state = "boss"
	bullets.clear()
	boss = {"pos": Vector2(FIELD_W * 0.5, -180.0), "hp": boss_max_hp, "max_hp": boss_max_hp, "kind": boss_kind, "t": 0.0, "a1": 1.5, "a2": 0.0, "a3": 3.0, "spin": 0.0, "flash": 0.0, "phase": 0, "recoil": 0.0, "smoke_t": 0.0, "rays": [true, true, true, true, true, true, true]}
	Audio.play("alarm", 0.0)


func _boss_rect() -> Rect2:
	return Rect2(boss["pos"] - Vector2(125, 110), Vector2(250, 210))


func _hit_boss(amount: float) -> void:
	boss["hp"] -= amount
	boss["flash"] = 0.06
	boss["recoil"] = minf(boss["recoil"] + amount * 1.1, 6.0)
	if state != "boss":
		return
	var frac: float = boss["hp"] / maxf(1.0, float(boss.get("max_hp", boss_max_hp)))
	# korona traci promienie w miarę obrażeń
	var alive := 0
	for r in boss["rays"]:
		if r:
			alive += 1
	while alive > ceili(frac * CROWN_RAYS) and alive > 0:
		_break_ray()
		alive -= 1
	if boss["hp"] <= 0.0:
		state = "boss_dead"
		state_t = DEATH_LEN
		death_t = 0.0
		part_t = 0.4
		bullets.clear()
		lasers.clear()
		_blast_big(boss["pos"], Color(1.4, 0.6, 0.9))
		hitstop = 0.12
		Audio.play("boss_rumble", 0.0)
	elif frac < 0.33 and boss["phase"] < 2:
		_boss_phase_break(2)
	elif frac < 0.66 and boss["phase"] < 1:
		_boss_phase_break(1)


## Przejście fazy: boss obrywa wyraźnie, pociski znikają, jest chwila na oddech.
func _boss_phase_break(ph: int) -> void:
	boss["phase"] = ph
	bullets.clear()
	var p: Vector2 = boss["pos"]
	_blast_big(p + Vector2(0, -10), Color(0.4, 1.3, 1.2))
	_queue_blasts(p, 6, 120.0, 0.1, "mid", Color(1.4, 0.7, 0.3))
	_debris(p, Color(0.3, 1.2, 1.1), 10, 380.0, 16.0)
	full_flash = maxf(full_flash, 0.35)
	boss["a1"] = 1.7
	boss["a2"] = 1.2
	boss["a3"] = 2.0


## Odrywa losowy promień korony.
func _break_ray() -> void:
	var idx: Array = []
	for k in CROWN_RAYS:
		if boss["rays"][k]:
			idx.append(k)
	if idx.is_empty():
		return
	var k: int = idx[randi() % idx.size()]
	boss["rays"][k] = false
	var a := -PI * 0.5 + (k - 3) * 0.32
	var at: Vector2 = boss["pos"] + Vector2(0, -28) + Vector2.from_angle(a) * 66.0
	_blast_pop(at, Color(0.4, 1.3, 1.2))
	debris.append({"pos": at, "vel": Vector2.from_angle(a) * 340.0, "rot": a + PI * 0.5, "spin": randf_range(-7.0, 7.0), "life": 1.5, "max": 1.5,
		"pts": PackedVector2Array([Vector2(-10, 24), Vector2(0, -26), Vector2(10, 24)]), "col": Color(0.3, 1.2, 1.1), "trail": true})


## Agonia bossa: drży, opada i rozpada się coraz gęstszą serią wybuchów.
func _update_boss_death(delta: float) -> void:
	state_t -= delta
	var k := clampf(1.0 - state_t / DEATH_LEN, 0.0, 1.0)
	boss["recoil"] = 3.0 + k * 11.0
	boss["flash"] = 0.05 if randf() < 0.12 + k * 0.3 else 0.0
	boss["pos"].y += (8.0 + 62.0 * k) * delta
	shake_amt = maxf(shake_amt, 2.5 + k * 7.0)
	var p: Vector2 = boss["pos"]
	var at := p + Vector2(randf_range(-135, 135), randf_range(-115, 100))
	death_t -= delta
	if death_t <= 0.0:
		death_t = lerpf(0.26, 0.06, k)
		var roll := randf()
		if roll < 0.2 + k * 0.3:
			_blast_mid(at, Color(1.4, 0.65, 0.3))
		elif roll < 0.6:
			_blast_pop(at, Color(1.4, 0.4, 0.8))
		else:
			_blast_shatter(at, Color(0.4, 1.2, 1.2))
		_smoke(at, 2)
	part_t -= delta
	if part_t <= 0.0:
		part_t = 0.5
		_break_ray()
		_debris(at, Color(0.3, 1.2, 1.1), 3, 300.0, 18.0)
	if state_t <= 0.0:
		_boss_final()


## Ostateczny wybuch: biały błysk, zamrożenie, spowolnienie i deszcz wielkich odłamków.
func _boss_final() -> void:
	var p: Vector2 = boss["pos"]
	var teal := Color(0.3, 1.2, 1.1)
	boss = {}
	state = "boss_final"
	state_t = 2.2
	_blast_big(p, Color(1.4, 0.5, 1.1))
	_add_flash(p, 230.0, 0.4, Color(1.4, 1.35, 1.3))
	_add_burst(p, 420.0, 0.8, Color(1.4, 0.9, 0.4), 24)
	_add_ring(p, 900.0, 1.1, Color(1.4, 0.5, 1.1), 9.0)
	_add_ring(p, 620.0, 0.85, teal, 6.0)
	_add_ring(p, 340.0, 0.6, Color(1.4, 1.3, 1.2), 4.0)
	_sparks(p, Color(1.4, 1.0, 0.5), 90, 760.0)
	_debris(p, teal, 16, 560.0, 24.0)
	_debris(p, Color(1.4, 0.8, 0.3), 12, 460.0, 13.0)
	_smoke(p, 12)
	_queue_blasts(p, 8, 240.0, 0.13, "mid", Color(1.4, 0.65, 0.3))
	full_flash = 1.0
	shake_amt = 28.0
	hitstop = 0.2
	slowmo = 0.8
	Audio.play("boss_final", 0.0, 2.0)


func _update_boss(delta: float) -> void:
	boss["t"] += delta
	boss["flash"] = maxf(0.0, boss["flash"] - delta)
	boss["recoil"] = move_toward(boss["recoil"], 0.0, 30.0 * delta)
	var t: float = boss["t"]
	var kind: String = String(boss.get("kind", "liberty"))
	var sway_freq := 0.72 if kind in ["needle", "prism"] else (0.42 if kind in ["fortress", "pentagon"] else 0.55)
	var sway_amp := 310.0 if kind == "needle" else (220.0 if kind == "fortress" else 270.0)
	var target := Vector2(FIELD_W * 0.5 + sin(t * sway_freq) * sway_amp, 190.0 + sin(t * 1.1) * 18.0)
	if t < 3.0:
		boss["pos"] = boss["pos"].move_toward(target, 190.0 * delta)
		return
	boss["pos"] = boss["pos"].move_toward(target, 210.0 * delta)
	var frac: float = boss["hp"] / maxf(1.0, float(boss.get("max_hp", boss_max_hp)))
	var p: Vector2 = boss["pos"]
	# im mocniej uszkodzony, tym bardziej dymi i iskrzy
	boss["smoke_t"] -= delta
	if frac < 0.66 and boss["smoke_t"] <= 0.0:
		boss["smoke_t"] = 0.22 if frac > 0.33 else 0.1
		var spot := p + Vector2(randf_range(-95, 95), randf_range(-60, 80))
		_smoke(spot, 1)
		_sparks(spot, Color(1.4, 0.8, 0.3), 3, 170.0)
		if frac < 0.33 and randf() < 0.12:
			_blast_pop(spot, Color(1.4, 0.5, 0.3))
	boss["a1"] -= delta
	boss["a2"] -= delta
	boss["a3"] -= delta
	match kind:
		"fortress", "pentagon":
			# ciężki ostrzał z podwójnych baterii + pierścienie obronne + krzyżowe lasery
			if boss["a1"] <= 0.0:
				boss["a1"] = 0.95 if frac > 0.33 else 0.72
				_fan(p + Vector2(-72, 36), 4 if frac > 0.33 else 6, 0.22, 320.0)
				_fan(p + Vector2(72, 36), 4 if frac > 0.33 else 6, 0.22, 320.0)
				Audio.play("enemy_shot", 0.1)
			if frac < 0.66 and boss["a2"] <= 0.0:
				boss["a2"] = 0.55 if kind == "fortress" else 0.42
				boss["spin"] += 0.45
				_ring(p, 10 if kind == "fortress" else 15, boss["spin"], 230.0)
			if frac < 0.33 and boss["a3"] <= 0.0:
				boss["a3"] = 2.4
				lasers.append({"axis": "v", "at": player.x, "t": 0.0})
				lasers.append({"axis": "h", "at": clampf(player.y, 260.0, field_h - 80.0), "t": 0.0})
				Audio.play("warning", 0.0)
		"needle", "prism":
			# szybkie precyzyjne serie + podwójna spirala + pionowe wiązki laserowe
			if boss["a1"] <= 0.0:
				boss["a1"] = 0.78 if frac > 0.33 else 0.58
				_fan(p + Vector2(0, 46), 6 if frac > 0.33 else 8, 0.16, 360.0)
				Audio.play("enemy_shot", 0.1)
			if frac < 0.66 and boss["a2"] <= 0.0:
				boss["a2"] = 0.08
				boss["spin"] += 0.52
				_shoot(p + Vector2(-58, 10), Vector2.from_angle(boss["spin"]), 260.0, Color(0.4, 1.3, 1.5))
				_shoot(p + Vector2(58, 10), Vector2.from_angle(-boss["spin"] + PI), 260.0, Color(1.4, 0.4, 1.2))
			if frac < 0.33 and boss["a3"] <= 0.0:
				boss["a3"] = 2.5
				lasers.append({"axis": "v", "at": clampf(player.x - 90.0, 60.0, FIELD_W - 60.0), "t": 0.0})
				lasers.append({"axis": "v", "at": clampf(player.x + 90.0, 60.0, FIELD_W - 60.0), "t": 0.0})
				Audio.play("warning", 0.0)
		"capitol":
			# kopuła stolicy: gęste wachlarze, potrójna spirala i salwy laserowe
			if boss["a1"] <= 0.0:
				boss["a1"] = 0.85 if frac > 0.33 else 0.65
				_fan(p + Vector2(0, 42), 7 if frac > 0.33 else 9, 0.19, 330.0)
				Audio.play("enemy_shot", 0.1)
			if frac < 0.66 and boss["a2"] <= 0.0:
				boss["a2"] = 0.09
				boss["spin"] += 0.41
				for k in 3:
					_shoot(p + Vector2(0, -20), Vector2.from_angle(boss["spin"] + k * TAU / 3.0), 245.0, Color(1.5, 0.9, 0.35))
			if frac < 0.33 and boss["a3"] <= 0.0:
				boss["a3"] = 2.3
				lasers.append({"axis": "v", "at": player.x, "t": 0.0})
				_ring(p, 16, boss["spin"], 220.0)
				Audio.play("warning", 0.0)
		_:
			var torch := p + Vector2(112, -96)
			# faza 1: wachlarze z korony
			if boss["a1"] <= 0.0:
				boss["a1"] = 1.05 if frac > 0.33 else 0.85
				_fan(p + Vector2(0, 40), 5 if frac > 0.33 else 7, 0.2, 310.0)
				Audio.play("enemy_shot", 0.1)
			# faza 2: spirala z pochodni
			if frac < 0.66 and boss["a2"] <= 0.0:
				boss["a2"] = 0.1
				boss["spin"] += 0.37
				_shoot(torch, Vector2.from_angle(boss["spin"]), 235.0, Color(1.4, 0.8, 0.25))
			# faza 3: lasery na pozycję gracza i pierścienie
			if frac < 0.33 and boss["a3"] <= 0.0:
				boss["a3"] = 2.8
				lasers.append({"axis": "v", "at": player.x, "t": 0.0})
				_ring(p, 14, boss["spin"], 200.0)
				Audio.play("warning", 0.0)


# =====================================================================
# RYSOWANIE
# =====================================================================

func _draw() -> void:
	var vs := get_viewport_rect().size
	# chwilę po starcie pod spodem widać jeszcze zatrzymany świat gry
	if time < INTRO_FADE:
		_draw_intro(vs)
		return
	_draw_background(vs)
	var shake := Vector2.ZERO
	if time > IMPACT and time < IMPACT + 0.5:
		shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 16.0 * (1.0 - (time - IMPACT) / 0.5)
	shake += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amt
	draw_set_transform(Vector2(field_x, 0.0) + shake)
	_draw_field()
	draw_set_transform(Vector2.ZERO)
	_draw_side(vs)
	_draw_messages(vs)
	_draw_intro(vs)
	if bomb_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.8, 1.0, bomb_flash * 0.28))
	if full_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.95, 0.95, minf(full_flash, 1.0) * 0.55))


func _progress() -> float:
	if state == "intro":
		return 0.0
	return clampf(stage_t / STAGE_LEN, 0.0, 1.0)


## Wejście do walki: smugi nadprzestrzeni, błysk i rozsuwające się pasy.
func _draw_intro(vs: Vector2) -> void:
	if time >= SHUTTER_END + 0.4:
		return
	var c := vs * 0.5
	if time < IMPACT:
		var k := time / IMPACT
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.0, 0.02, clampf(time / INTRO_FADE, 0.0, 1.0)))
		var reach := vs.length() * 0.6
		for s in streaks:
			var phase := fposmod(s.y + time * (0.7 + k * 2.6), 1.0)
			var r0 := phase * phase * reach
			var length := (20.0 + k * k * 420.0) * (0.3 + phase)
			var dir := Vector2.from_angle(s.x)
			var col := Style.PINK.lerp(Style.CYAN, s.z)
			var alpha := phase * clampf(time / 0.15, 0.0, 1.0)
			draw_line(c + dir * r0, c + dir * (r0 + length), Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, alpha), 1.0 + k * 3.0)
		# rosnąca kula światła w punkcie skoku
		draw_circle(c, 6.0 + k * k * 90.0, Color(1.4, 1.2, 1.4, k * k))
		return
	# pasy rozsuwają się po uderzeniu
	var open := clampf((time - IMPACT) / (SHUTTER_END - IMPACT), 0.0, 1.0)
	open = 1.0 - pow(1.0 - open, 3.0)
	var bars := 10
	var bar_h := vs.y / bars
	for k in bars:
		var h := bar_h * (1.0 - open)
		var y := k * bar_h + (bar_h - h) * (0.0 if k % 2 == 0 else 1.0)
		if h > 0.5:
			draw_rect(Rect2(0.0, y, vs.x, h), Color(0.02, 0.0, 0.05))
			draw_line(Vector2(0.0, y + (h if k % 2 == 0 else 0.0)), Vector2(vs.x, y + (h if k % 2 == 0 else 0.0)), Color(1.4, 0.4, 1.2, 0.9), 2.0)
	# fala uderzeniowa i błysk
	var since := time - IMPACT
	var wave := since / 0.7
	if wave < 1.0:
		draw_arc(c, wave * vs.x * 0.7, 0.0, TAU, 72, Color(1.3, 1.1, 1.4, 1.0 - wave), 6.0 * (1.0 - wave) + 1.0, true)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.9, 1.0, clampf(1.0 - since / 0.35, 0.0, 1.0)))


## Tło: synthwave'owe słońce, panorama Nowego Jorku rosnąca w miarę zbliżania i siatka pędząca do gracza.
func _draw_background(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.0, 0.03))
	var hz := vs.y * 0.34
	for s in stars:
		draw_rect(Rect2(s.x * vs.x, s.y * vs.y, s.z, s.z), Color(0.8, 0.75, 1.0, 0.35 + 0.3 * sin(time * 2.0 + s.x * 40.0)))
	var sun := Vector2(vs.x * 0.5, hz)
	var sr := vs.y * 0.27
	var row := 0.0
	while row < sr:
		var gap := 1.0 + int(row / 8.0) * 0.4
		if row < sr * 0.2 or fmod(row, 8.0) > gap:
			var half := sqrt(maxf(0.0, sr * sr - row * row))
			var c := Color(1.0, 0.2, 0.55).lerp(Color(1.0, 0.7, 0.25), row / sr)
			c.a = 0.36 + neon * 0.1
			draw_line(Vector2(sun.x - half, hz - row), Vector2(sun.x + half, hz - row), c, 1.0)
		row += 1.0
	_draw_skyline(vs, hz)
	draw_rect(Rect2(0.0, hz, vs.x, vs.y - hz), Color(0.025, 0.0, 0.05))
	var gc := Color(1.0, 0.25, 0.75)
	var speed := 0.55 if state != "boss" else 0.3
	for k in 20:
		var t := fposmod(k / 20.0 + time * speed / 2.0, 1.0)
		var y := hz + (vs.y - hz) * t * t
		draw_line(Vector2(0.0, y), Vector2(vs.x, y), Color(gc.r, gc.g, gc.b, (0.08 + t * 0.32) * (0.8 + neon * 0.35)), 1.0)
	for i in range(-22, 23):
		draw_line(Vector2(vs.x * 0.5 + i * 22.0, hz), Vector2(vs.x * 0.5 + i * 170.0, vs.y), Color(gc.r, gc.g, gc.b, 0.16 + neon * 0.08), 1.0)
	draw_line(Vector2(0.0, hz), Vector2(vs.x, hz), Color(1.2, 0.4, 1.0, 0.6 + neon * 0.3), 2.0)


func _sil(pts: Array, fill: Color, line: Color, w := 1.5) -> void:
	var p := PackedVector2Array(pts)
	draw_colored_polygon(p, fill)
	p.append(p[0])
	draw_polyline(p, line, w, true)


## Panorama: zwykłe bloki, Empire State, Chrysler, One WTC, Statua Wolności i most Brookliński.
func _draw_skyline(vs: Vector2, hz: float) -> void:
	var s := lerpf(0.72, 1.15, _progress())
	draw_set_transform(Vector2(vs.x * 0.5, hz), 0.0, Vector2(s, s))
	var fill := Color(0.03, 0.0, 0.07)
	# w rytm muzyki neony tylko się rozjaśniają od przygaszonych do pełnych barw, bez białych błysków
	var glow := lerpf(0.5, 1.0, neon)
	var far := Color(0.75, 0.2, 0.85, 0.45 + neon * 0.3)
	for b in blocks:
		var r := Rect2(b[0], -b[2], b[1], b[2])
		draw_rect(r, fill)
		draw_rect(r, far, false, 1.0)
		var wy: float = -b[2] + 8.0
		while wy < -6.0:
			if int(b[0] + wy) % 3 != 0:
				draw_rect(Rect2(b[0] + 6.0, wy, b[1] - 12.0, 2.0), Color(1.0, 0.75, 0.3, 0.14 + neon * 0.16))
			wy += 11.0
	var pink_n := Color(1.4 * glow, 0.45 * glow, 1.2 * glow)
	var cyan := Color(0.3 * glow, 1.2 * glow, 1.4 * glow)
	var gold := Color(1.4 * glow, 0.95 * glow, 0.35 * glow)
	# Empire State Building: schodkowa sylwetka z iglicą
	var x := -60.0
	_sil([Vector2(x - 52, 0), Vector2(x - 52, -160), Vector2(x - 38, -160), Vector2(x - 38, -235), Vector2(x - 24, -235), Vector2(x - 24, -285),
		Vector2(x - 10, -285), Vector2(x - 6, -330), Vector2(x - 2, -400), Vector2(x + 2, -400), Vector2(x + 6, -330), Vector2(x + 10, -285),
		Vector2(x + 24, -285), Vector2(x + 24, -235), Vector2(x + 38, -235), Vector2(x + 38, -160), Vector2(x + 52, -160), Vector2(x + 52, 0)], fill, pink_n, 2.0)
	draw_circle(Vector2(x, -404), 3.0 + sin(time * 4.0), Color(1.5, 0.3, 0.3))
	for k in range(-2, 3):
		draw_line(Vector2(x + k * 15.0, -150), Vector2(x + k * 15.0, -4), Color(pink_n.r, pink_n.g, pink_n.b, 0.35), 1.0)
	# Chrysler Building: łuki korony
	x = 85.0
	_sil([Vector2(x - 34, 0), Vector2(x - 34, -200), Vector2(x - 20, -225), Vector2(x - 14, -270), Vector2(x - 6, -305), Vector2(x, -350),
		Vector2(x + 6, -305), Vector2(x + 14, -270), Vector2(x + 20, -225), Vector2(x + 34, -200), Vector2(x + 34, 0)], fill, cyan, 2.0)
	for k in 3:
		draw_arc(Vector2(x, -218 - k * 26.0), 19.0 - k * 5.0, PI, TAU, 10, gold, 1.5, true)
	# One World Trade Center: zwężająca się bryła
	x = -250.0
	_sil([Vector2(x - 38, 0), Vector2(x - 38, -70), Vector2(x - 20, -330), Vector2(x + 20, -330), Vector2(x + 38, -70), Vector2(x + 38, 0)], fill, cyan, 2.0)
	draw_line(Vector2(x - 38, -70), Vector2(x + 20, -330), Color(cyan.r, cyan.g, cyan.b, 0.5), 1.0)
	draw_line(Vector2(x + 38, -70), Vector2(x - 20, -330), Color(cyan.r, cyan.g, cyan.b, 0.5), 1.0)
	draw_line(Vector2(x, -330), Vector2(x, -395), cyan, 2.0)
	# Statua Wolności na wyspie
	x = -560.0
	_sil([Vector2(x - 60, 0), Vector2(x - 28, -40), Vector2(x - 26, -95), Vector2(x + 26, -95), Vector2(x + 28, -40), Vector2(x + 60, 0)], fill, pink_n, 1.5)
	_sil([Vector2(x - 20, -95), Vector2(x - 14, -180), Vector2(x - 7, -205), Vector2(x + 8, -205), Vector2(x + 14, -180), Vector2(x + 20, -95)], Color(0.02, 0.1, 0.1), cyan, 2.0)
	draw_circle(Vector2(x, -217), 12.0, Color(0.02, 0.1, 0.1))
	draw_arc(Vector2(x, -217), 12.0, 0.0, TAU, 16, cyan, 2.0, true)
	for k in 5:
		var a := -PI * 0.5 + (k - 2) * 0.42
		draw_line(Vector2(x, -222) + Vector2.from_angle(a) * 9.0, Vector2(x, -222) + Vector2.from_angle(a) * 22.0, cyan, 1.5, true)
	draw_line(Vector2(x + 12, -180), Vector2(x + 30, -250), cyan, 3.0, true)
	draw_circle(Vector2(x + 30, -258), 6.0 + sin(time * 9.0) * 1.5, gold)
	# most Brookliński
	x = 470.0
	for tx in [x - 110.0, x + 110.0]:
		_sil([Vector2(tx - 15, 0), Vector2(tx - 15, -135), Vector2(tx + 15, -135), Vector2(tx + 15, 0)], fill, gold, 1.5)
		draw_arc(Vector2(tx, -110), 8.0, PI, TAU, 8, gold, 1.5, true)
	draw_line(Vector2(x - 300, -36), Vector2(x + 300, -36), gold, 2.0)
	var last := Vector2(x - 300, -40)
	for k in range(1, 41):
		var u := k / 40.0
		var px := lerpf(x - 300.0, x + 300.0, u)
		var d := minf(absf(px - (x - 110.0)), absf(px - (x + 110.0)))
		var py := -135.0 + pow(minf(d, 110.0) / 110.0, 2.0) * 95.0
		var now := Vector2(px, py)
		draw_line(last, now, Color(gold.r, gold.g, gold.b, 0.8), 1.0, true)
		if k % 2 == 0:
			draw_line(now, Vector2(px, -36), Color(gold.r, gold.g, gold.b, 0.3), 1.0)
		last = now
	draw_set_transform(Vector2.ZERO)


func _draw_field() -> void:
	draw_rect(Rect2(0, 0, FIELD_W, field_h), Color(0.0, 0.0, 0.02, 0.38))
	for t in towers:
		_draw_tower(t)
	for l in lasers:
		_draw_laser(l)
	for p in pickups:
		_draw_pickup(p)
	for e in enemies:
		_draw_enemy(e)
	if not boss.is_empty():
		_draw_boss()
	for s in shots:
		var v: Vector2 = s["vel"].normalized()
		draw_line(s["pos"], s["pos"] - v * 18.0, Color(0.3, 1.2, 1.4, 0.7), 4.0)
		draw_line(s["pos"], s["pos"] - v * 14.0, Color(1.3, 1.4, 1.4), 1.6)
	if state != "lose":
		_draw_player()
	for s in smokes:
		var f: float = s["life"] / s["max"]
		draw_circle(s["pos"], s["r"], Color(0.16, 0.1, 0.2, f * 0.4))
		draw_arc(s["pos"], s["r"], 0.0, TAU, 14, Color(0.6, 0.5, 0.7, f * 0.35), 1.0, true)
	for b in bullets:
		draw_circle(b["pos"], b["r"] + 2.5, Color(b["col"].r, b["col"].g, b["col"].b, 0.4))
		draw_circle(b["pos"], b["r"] - 1.0, Color(1.4, 1.35, 1.4))
	for s in sparks:
		var c: Color = s["col"]
		draw_line(s["pos"], s["pos"] - s["vel"] * 0.04, Color(c.r, c.g, c.b, s["life"] * 1.6), 2.0)
	for r in rings:
		var f: float = 1.0 - r["life"] / r["max"]
		var c: Color = r["col"]
		draw_arc(r["pos"], r["r"] * (1.0 - pow(1.0 - f, 2.0)), 0.0, TAU, 56, Color(c.r, c.g, c.b, 1.0 - f), maxf(1.0, r["w"] * (1.0 - f)), true)
	for d in debris:
		var f: float = d["life"] / d["max"]
		var c: Color = d["col"]
		var pts: PackedVector2Array = Transform2D(d["rot"], d["pos"]) * d["pts"]
		draw_colored_polygon(pts, Color(c.r * 0.2, c.g * 0.2, c.b * 0.2, f))
		pts.append(pts[0])
		draw_polyline(pts, Color(c.r, c.g, c.b, f), 2.0, true)
	for b in bursts:
		var f: float = 1.0 - b["life"] / b["max"]
		var c: Color = b["col"]
		Style.sunburst(self, b["pos"], b["r"] * (0.35 + 0.65 * f), b["spikes"], b["rot"], Color(c.r, c.g, c.b, 1.0 - f), 3.0)
	for fl in flashes:
		var f: float = fl["life"] / fl["max"]
		var c: Color = fl["col"]
		draw_circle(fl["pos"], fl["r"] * (1.25 - f * 0.25), Color(c.r, c.g, c.b, f * 0.42))


func _draw_player() -> void:
	if inv_t > 0.0 and int(time * 16.0) % 2 == 0:
		return
	var hull := PackedVector2Array([Vector2(0, -24), Vector2(-8, -5), Vector2(-20, 7), Vector2(-18, 16), Vector2(-7, 10), Vector2(0, 15),
		Vector2(7, 10), Vector2(18, 16), Vector2(20, 7), Vector2(8, -5), Vector2(0, -24)])
	# smuga silnika zostająca za statkiem
	for k in range(1, trail.size()):
		var f := float(k) / trail.size()
		draw_line(trail[k - 1], trail[k], Color(1.3, 0.3, 1.2, f * 0.55), 1.0 + f * 4.0, true)
	# przechył: statek obraca się lekko i zwęża w locie na boki
	var xf := Transform2D(tilt * 0.17, Vector2(1.0 - absf(tilt) * 0.28, 1.0), 0.0, player)
	var pts := xf * hull
	draw_colored_polygon(pts, Color(0.12, 0.0, 0.18, 0.95))
	draw_polyline(pts, Color(1.4, 0.23, 1.28), 2.2, true)
	# płomień rośnie przy locie do przodu i maleje przy cofaniu
	var fl := (14.0 + sin(time * 50.0) * 4.0) * clampf(1.0 - player_vel.y / SPEED, 0.45, 1.7)
	draw_line(xf * Vector2(0, 15), xf * Vector2(0, 15 + fl), Color(1.4, 0.75, 0.19), 3.0, true)
	draw_line(xf * Vector2(0, 15), xf * Vector2(0, 15 + fl * 0.5), Color(1.4, 1.4, 1.17), 1.5, true)
	# widoczny punkt trafienia: tylko on liczy się przy pociskach
	draw_circle(player, HITBOX + 1.0, Color(0.2, 1.1, 1.4))
	draw_circle(player, HITBOX - 2.0, Color(1.4, 1.4, 1.4))
	if focus:
		draw_arc(player, 16.0, 0.0, TAU, 20, Color(0.3, 1.2, 1.4, 0.7), 1.5, true)


func _draw_tower(t: Dictionary) -> void:
	var r: Rect2 = t["rect"]
	draw_rect(r, Color(0.05, 0.0, 0.1, 0.97))
	draw_rect(r, Color(1.4, 0.25, 0.95), false, 2.5)
	draw_rect(r.grow(-6.0), Color(0.3, 1.1, 1.4, 0.4), false, 1.0)
	# układ okien zależy tylko od numeru okna, więc nie zmienia się przy przesuwaniu budynku
	var h: int = t["seed"]
	var rows := int((r.size.y - 28.0) / 24.0)
	var cols := int((r.size.x - 32.0) / 28.0)
	for row in rows:
		for col in cols:
			if (row * 13 + col * 7 + h) % 5 != 0:
				draw_rect(Rect2(r.position + Vector2(16.0 + col * 28.0, 16.0 + row * 24.0), Vector2(12.0, 8.0)), Color(1.2, 0.8, 0.3, 0.35))


func _draw_laser(l: Dictionary) -> void:
	var a := Vector2(0.0, l["at"]) if l["axis"] == "h" else Vector2(l["at"], 0.0)
	var b := Vector2(FIELD_W, l["at"]) if l["axis"] == "h" else Vector2(l["at"], field_h)
	var t: float = l["t"]
	if t < 1.1:
		var k := t / 1.1
		draw_line(a, b, Color(1.4, 0.2, 0.2, 0.15 + 0.5 * k), 1.0 + 2.0 * k)
		var m := a.lerp(b, 0.5)
		var blink := int(time * 10.0) % 2 == 0
		if blink:
			draw_string(font, m + Vector2(-34, -10), "UWAGA", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.4, 0.3, 0.3))
	else:
		var flick := 0.85 + 0.15 * sin(time * 50.0)
		draw_line(a, b, Color(1.3, 0.1, 0.15, 0.3 * flick), 34.0)
		draw_line(a, b, Color(1.4, 0.3, 0.25, 0.9 * flick), 12.0)
		draw_line(a, b, Color(1.5, 1.3, 1.2, flick), 4.0)


func _draw_pickup(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var col := Color(1.4, 0.4, 1.2)
	var txt := "P"
	match p["kind"]:
		"heart":
			col = Color(0.4, 1.3, 0.5)
			txt = "+"
		"bomb":
			col = Color(1.4, 0.95, 0.3)
			txt = "B"
	var pulse := 16.0 + sin(time * 8.0) * 2.0
	var d := PackedVector2Array([c + Vector2(0, -pulse), c + Vector2(pulse, 0), c + Vector2(0, pulse), c + Vector2(-pulse, 0), c + Vector2(0, -pulse)])
	draw_colored_polygon(d, Color(col.r * 0.15, col.g * 0.15, col.b * 0.15))
	draw_polyline(d, col, 2.0, true)
	draw_string(font, c + Vector2(-5, 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.4, 1.4, 1.4))


func _draw_enemy(e: Dictionary) -> void:
	var p: Vector2 = e["pos"]
	var hit: bool = e["flash"] > 0.0
	match e["kind"]:
		"dart":
			var pts := Transform2D(0.0, p) * PackedVector2Array([Vector2(0, 20), Vector2(-16, -14), Vector2(0, -7), Vector2(16, -14), Vector2(0, 20)])
			draw_colored_polygon(pts, Color(0.2, 0.03, 0.1))
			draw_polyline(pts, Color(1.4, 1.4, 1.4) if hit else Color(1.3, 0.3, 0.45), 2.0, true)
		"sweeper":
			var pts := Transform2D(0.0, p) * PackedVector2Array([Vector2(-22, -6), Vector2(0, -13), Vector2(22, -6), Vector2(12, 11), Vector2(-12, 11), Vector2(-22, -6)])
			draw_colored_polygon(pts, Color(0.03, 0.14, 0.17))
			draw_polyline(pts, Color(1.4, 1.4, 1.4) if hit else Color(0.3, 1.1, 1.4), 2.0, true)
			draw_circle(p, 4.0, Color(1.3, 0.3, 0.3))
		"gunship":
			var pts := PackedVector2Array()
			for k in 9:
				var a: float = e["t"] * 0.5 + k / 8.0 * TAU
				pts.append(p + Vector2(cos(a), sin(a)) * 36.0)
			draw_colored_polygon(pts, Color(0.18, 0.1, 0.02))
			draw_polyline(pts, Color(1.4, 1.4, 1.4) if hit else Color(1.4, 0.85, 0.3), 2.5, true)
			draw_circle(p, 11.0, Color(1.4, 0.4, 0.3))
		"heavy":
			var pts := Transform2D(0.0, p) * PackedVector2Array([Vector2(-80, -30), Vector2(-40, -56), Vector2(40, -56), Vector2(80, -30), Vector2(58, 34), Vector2(0, 62), Vector2(-58, 34), Vector2(-80, -30)])
			draw_colored_polygon(pts, Color(0.18, 0.02, 0.2))
			draw_polyline(pts, Color(1.4, 1.4, 1.4) if hit else Color(1.4, 0.35, 1.2), 3.0, true)
			draw_arc(p, 24.0, 0.0, TAU, 24, Color(1.4, 0.9, 0.3), 2.5, true)
			draw_circle(p, 9.0, Color(1.4, 0.4, 0.3))
			var frac: float = e["hp"] / 70.0
			draw_rect(Rect2(p + Vector2(-60, -74), Vector2(120, 6)), Color(0, 0, 0, 0.8))
			draw_rect(Rect2(p + Vector2(-60, -74), Vector2(120 * frac, 6)), Color(1.3, 0.3, 0.4))


## Boss metropolii lub kompleksu federalnego: warianty sylwetki zależne od boss_kind.
func _draw_boss() -> void:
	var p: Vector2 = boss["pos"] + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * boss["recoil"]
	var t: float = boss["t"]
	var hit: bool = boss["flash"] > 0.0
	var kind: String = String(boss.get("kind", "liberty"))
	var core_a := 0.6 + 0.4 * sin(t * 6.0)
	if kind != "liberty":
		_draw_boss_variant(p, t, hit, kind, core_a)
		return
	var teal := Color(0.3, 1.2, 1.1)
	var line := Color(1.4, 1.4, 1.4) if hit else teal
	var fill := Color(0.02, 0.13, 0.13, 0.97)
	# ramię z pochodnią
	var hand := p + Vector2(112, -60)
	draw_line(p + Vector2(62, 20), p + Vector2(100, -8), line, 9.0, true)
	draw_line(p + Vector2(100, -8), hand, line, 9.0, true)
	draw_rect(Rect2(hand + Vector2(-13, -36), Vector2(26, 36)), fill)
	draw_rect(Rect2(hand + Vector2(-13, -36), Vector2(26, 36)), Color(1.4, 0.95, 0.35), false, 2.0)
	var fl := 26.0 + sin(t * 14.0) * 6.0
	draw_colored_polygon(PackedVector2Array([hand + Vector2(-13, -36), hand + Vector2(0, -36 - fl), hand + Vector2(13, -36)]), Color(1.5, 0.8, 0.25))
	# ramiona i szata
	_sil([p + Vector2(-110, 100), p + Vector2(-66, 22), p + Vector2(66, 22), p + Vector2(110, 100), p + Vector2(40, 84), p + Vector2(0, 100), p + Vector2(-40, 84)], fill, line, 3.0)
	for k in range(-2, 3):
		draw_line(p + Vector2(k * 20.0, 30), p + Vector2(k * 32.0, 88), Color(teal.r, teal.g, teal.b, 0.45), 1.5, true)
	# korona: siedem promieni
	for k in CROWN_RAYS:
		if not boss["rays"][k]:
			continue
		var a := -PI * 0.5 + (k - 3) * 0.32
		var tip := p + Vector2(0, -28) + Vector2.from_angle(a) * (92.0 + sin(t * 3.0 + k) * 5.0)
		var d := Vector2.from_angle(a).orthogonal() * 10.0
		var base := p + Vector2(0, -28) + Vector2.from_angle(a) * 42.0
		_sil([base + d, tip, base - d], fill, line, 2.0)
	# twarz
	_sil([p + Vector2(-48, -42), p + Vector2(48, -42), p + Vector2(54, -2), p + Vector2(34, 36), p + Vector2(0, 50), p + Vector2(-34, 36), p + Vector2(-54, -2)], fill, line, 3.0)
	draw_line(p + Vector2(-48, -30), p + Vector2(48, -30), Color(1.4, 0.95, 0.35), 3.0)
	# świecące oczy i usta
	draw_rect(Rect2(p + Vector2(-34, -16), Vector2(24, 7)), Color(1.5, 0.15, 0.3, core_a))
	draw_rect(Rect2(p + Vector2(10, -16), Vector2(24, 7)), Color(1.5, 0.15, 0.3, core_a))
	draw_line(p + Vector2(0, -8), p + Vector2(-4, 10), Color(teal.r, teal.g, teal.b, 0.8), 2.0)
	draw_line(p + Vector2(-16, 25), p + Vector2(16, 25), Color(1.5, 0.3, 0.5, core_a), 3.0)
	# pęknięcia rosną z każdą fazą
	var crack := Color(1.4, 0.75, 0.3, 0.9)
	if boss["phase"] >= 1 or state == "boss_dead":
		draw_polyline(PackedVector2Array([p + Vector2(-48, -26), p + Vector2(-30, -2), p + Vector2(-38, 14), p + Vector2(-20, 34)]), crack, 2.0, true)
		draw_polyline(PackedVector2Array([p + Vector2(66, 26), p + Vector2(50, 50), p + Vector2(66, 66), p + Vector2(56, 90)]), crack, 2.0, true)
	if boss["phase"] >= 2 or state == "boss_dead":
		draw_polyline(PackedVector2Array([p + Vector2(46, -40), p + Vector2(22, -22), p + Vector2(30, 2), p + Vector2(10, 22), p + Vector2(14, 46)]), crack, 2.5, true)
		draw_polyline(PackedVector2Array([p + Vector2(-70, 34), p + Vector2(-48, 56), p + Vector2(-66, 72), p + Vector2(-44, 92)]), crack, 2.0, true)
		draw_circle(p + Vector2(22, -22), 3.0 + core_a * 2.0, Color(1.5, 0.8, 0.35))


func _draw_boss_variant(p: Vector2, t: float, hit: bool, kind: String, core_a: float) -> void:
	var accent := Color(1.35, 0.55, 0.2) if kind in ["fortress", "pentagon"] else (Color(0.35, 1.25, 1.45) if kind in ["needle", "prism"] else Color(1.45, 0.95, 0.35))
	var line := Color(1.4, 1.4, 1.4) if hit else accent
	var fill := Color(0.08, 0.04, 0.12, 0.97)
	# moduły korony/tarcz dookoła rdzenia
	for k in CROWN_RAYS:
		if not boss["rays"][k]:
			continue
		var a := -PI * 0.5 + (k - 3) * 0.42 + (t * 0.6 if kind in ["prism", "pentagon"] else 0.0)
		var base := p + Vector2.from_angle(a) * 62.0
		var tip := p + Vector2.from_angle(a) * 98.0
		var n := Vector2.from_angle(a).orthogonal() * 11.0
		_sil([base - n, tip, base + n], fill, line, 2.0)
	match kind:
		"pentagon":
			var outer: Array = []
			var inner: Array = []
			for k in 5:
				var a := -PI * 0.5 + k * TAU / 5.0 + sin(t * 0.8) * 0.08
				outer.append(p + Vector2.from_angle(a) * 92.0)
				inner.append(p + Vector2.from_angle(a) * 48.0)
			_sil(outer, fill, line, 3.0)
			_sil(inner, Color(0.16, 0.03, 0.06, 0.95), Color(1.5, 0.3, 0.35), 2.2)
		"capitol":
			_sil([p + Vector2(-115, 72), p + Vector2(-95, 16), p + Vector2(95, 16), p + Vector2(115, 72)], fill, line, 3.0)
			_sil([p + Vector2(-68, 16), p + Vector2(-46, -54), p + Vector2(0, -86), p + Vector2(46, -54), p + Vector2(68, 16)], fill, line, 3.0)
			for k in range(-3, 4):
				draw_line(p + Vector2(k * 24.0, 18), p + Vector2(k * 24.0, 68), line, 2.0)
		"needle", "prism":
			_sil([p + Vector2(0, -96), p + Vector2(88, 0), p + Vector2(46, 86), p + Vector2(-46, 86), p + Vector2(-88, 0)], fill, line, 3.0)
			draw_line(p + Vector2(-88, 0), p + Vector2(88, 0), Color(1.4, 0.4, 1.2, 0.85), 2.5)
			draw_line(p + Vector2(0, -96), p + Vector2(0, 86), Color(0.4, 1.3, 1.5, 0.85), 2.5)
		_:
			# ciężka forteca pancerna
			_sil([p + Vector2(-112, -48), p + Vector2(112, -48), p + Vector2(128, 34), p + Vector2(76, 88), p + Vector2(-76, 88), p + Vector2(-128, 34)], fill, line, 3.0)
			draw_rect(Rect2(p + Vector2(-86, 26), Vector2(32, 46)), fill)
			draw_rect(Rect2(p + Vector2(54, 26), Vector2(32, 46)), fill)
			draw_rect(Rect2(p + Vector2(-86, 26), Vector2(32, 46)), line, false, 2.0)
			draw_rect(Rect2(p + Vector2(54, 26), Vector2(32, 46)), line, false, 2.0)
	draw_circle(p, 24.0, Color(0.05, 0.02, 0.08, 0.95))
	draw_arc(p, 24.0, 0.0, TAU, 28, Color(1.5, 0.25, 0.45, core_a), 3.0, true)
	draw_circle(p, 10.0 + core_a * 4.0, Color(1.5, 0.85, 0.35, core_a))


func _draw_side(vs: Vector2) -> void:
	var c := Color(0.01, 0.0, 0.03, 0.82)
	draw_rect(Rect2(0, 0, field_x, vs.y), c)
	draw_rect(Rect2(field_x + FIELD_W, 0, field_x, vs.y), c)
	draw_line(Vector2(field_x, 0), Vector2(field_x, vs.y), Color(1.0, 0.3, 0.8, 0.7), 2.0)
	draw_line(Vector2(field_x + FIELD_W, 0), Vector2(field_x + FIELD_W, vs.y), Color(1.0, 0.3, 0.8, 0.7), 2.0)
	var x := 24.0
	draw_string(pf, Vector2(x, 60), "OPERACJA", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Style.CYAN)
	draw_string(pf, Vector2(x, 92), city_name, HORIZONTAL_ALIGNMENT_LEFT, field_x - 40.0, 24, Style.PINK)
	draw_string(font, Vector2(x, 140), "KADŁUB", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Style.GREEN)
	for k in max_hp:
		var r := Rect2(x + (k % 4) * 44.0, 150.0 + (k / 4) * 26.0, 38.0, 18.0)
		draw_rect(r, Color(0.3, 1.2, 0.4) if k < hp else Color(0.1, 0.13, 0.1))
		draw_rect(r, Color(0.5, 1.0, 0.55, 0.8), false, 1.0)
	draw_string(font, Vector2(x, 228), GameState.keys_text("BOMBY [{drift}]"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Style.GOLD)
	for k in bombs:
		draw_circle(Vector2(x + 12.0 + k * 32.0, 248.0), 10.0, Color(1.4, 0.95, 0.3))
	draw_string(font, Vector2(x, 292), "SIŁA OGNIA  %d/5" % power, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Style.PINK)
	draw_string(font, Vector2(x, vs.y - 92), GameState.keys_text("{move} / STRZAŁKI: LOT"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Style.TEXT_DIM)
	draw_string(font, Vector2(x, vs.y - 72), GameState.keys_text("{focus}: PRECYZJA"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Style.TEXT_DIM)
	draw_string(font, Vector2(x, vs.y - 52), "OGIEŃ: AUTOMATYCZNY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Style.TEXT_DIM)
	# postęp etapu
	var bx := field_x + FIELD_W + 40.0
	var bar := Rect2(bx, 90.0, 14.0, vs.y - 180.0)
	draw_string(font, Vector2(bx, 72), "DO CELU", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Style.CYAN)
	draw_rect(bar, Color(0, 0, 0, 0.8))
	var pr := _progress()
	draw_rect(Rect2(bar.position.x, bar.end.y - bar.size.y * pr, bar.size.x, bar.size.y * pr), Style.CYAN)
	draw_rect(bar, Color(0.4, 0.9, 1.0, 0.7), false, 1.0)
	# pasek bossa
	if not boss.is_empty() and state == "boss":
		var w := FIELD_W - 160.0
		var bb := Rect2(field_x + 80.0, 18.0, w, 14.0)
		draw_rect(bb, Color(0, 0, 0, 0.85))
		var bhp_max := maxf(1.0, float(boss.get("max_hp", boss_max_hp)))
		draw_rect(Rect2(bb.position, Vector2(w * clampf(boss["hp"] / bhp_max, 0.0, 1.0), bb.size.y)), Color(1.3, 0.25, 0.6))
		draw_rect(bb, Style.PINK, false, 1.5)
		for f in [0.33, 0.66]:
			draw_line(bb.position + Vector2(w * f, 0), bb.position + Vector2(w * f, bb.size.y), Color(0, 0, 0, 0.9), 2.0)
		draw_string(pf, Vector2(field_x + 80.0, 56), boss_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Style.PINK)


func _center_text(vs: Vector2, y: float, s: String, fsize: int, c: Color) -> void:
	var w := pf.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var at := Vector2(vs.x * 0.5 - w * 0.5, y).round()
	draw_string_outline(pf, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 8, Color(0, 0, 0, 0.85))
	draw_string(pf, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, c)


## Tytuł operacji: uderza w ekran po skoku, a na końcu znika z zakłóceniami.
func _draw_intro_title(vs: Vector2) -> void:
	var t := time - IMPACT - 0.1
	if t < 0.0:
		return
	var k := clampf(t / 0.28, 0.0, 1.0)
	var scale_now := lerpf(3.2, 1.0, k * k)
	var alpha := k * clampf((INTRO_LEN - time) / 0.5, 0.0, 1.0)
	var title := "OPERACJA: " + city_name
	var fsize := 48
	var w := pf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var at := Vector2(vs.x * 0.5, vs.y * 0.42)
	# po wylądowaniu napisu krótkie drganie i rzadkie zakłócenia
	var glitch := 8.0 * (1.0 - clampf((t - 0.28) / 0.3, 0.0, 1.0))
	if fmod(time, 0.9) < 0.07:
		glitch = 10.0
	draw_set_transform(at, 0.0, Vector2(scale_now, scale_now))
	var off := Vector2(randf_range(-glitch, glitch), 0.0)
	draw_string_outline(pf, Vector2(-w * 0.5, 0.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 10, Color(0, 0, 0, 0.9 * alpha))
	draw_string(pf, Vector2(-w * 0.5, 0.0) + off + Vector2(5, 4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.2, 0.9, 1.0, 0.75 * alpha))
	draw_string(pf, Vector2(-w * 0.5, 0.0) - off, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1.3, 0.35, 0.9, alpha))
	draw_set_transform(Vector2.ZERO)
	if t > 0.35:
		var a2 := alpha * clampf((t - 0.35) / 0.25, 0.0, 1.0)
		var half := 300.0 * a2
		draw_line(at + Vector2(-half, 18.0), at + Vector2(half, 18.0), Color(0.3, 1.1, 1.4, a2), 2.0)
		_center_text(vs, at.y + 52.0, "PRZEBIJ SIĘ DO SERCA MIASTA", 24, Color(0.3, 0.95, 1.0, a2))


## Okienko samouczka w górnej części pola, statek na dole zostaje odsłonięty.
func _draw_tutorial(vs: Vector2) -> void:
	var a := tut_appear
	var ease_a := 1.0 - pow(1.0 - a, 3.0)
	var body := Style.font()
	var page: Array = TUTORIAL[tut_page]
	var w := 600.0
	var page_text := GameState.keys_text(page[1])
	var th := body.get_multiline_string_size(page_text, HORIZONTAL_ALIGNMENT_LEFT, w - 40, 15).y
	var h := 62.0 + th + 62.0
	var r := Rect2(Vector2(vs.x * 0.5 - w * 0.5, vs.y * 0.13 - (1.0 - ease_a) * 24.0), Vector2(w, h))
	var gold := Color(Style.GOLD.r, Style.GOLD.g, Style.GOLD.b, a)
	draw_rect(r.grow(10), Color(0, 0, 0, 0.45 * a))
	Style.panel(self, r, gold, Color(0.06, 0.03, 0.1, 0.97 * a))
	draw_string(body, r.position + Vector2(20, 24), "PIERWSZA WALKA %d/%d" % [tut_page + 1, TUTORIAL.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Style.PINK.r, Style.PINK.g, Style.PINK.b, 0.9 * a))
	draw_string(font, r.position + Vector2(20, 48), page[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, gold)
	draw_line(r.position + Vector2(20, 58), r.position + Vector2(w - 20, 58), Color(gold.r, gold.g, gold.b, 0.35 * a), 1.0)
	draw_multiline_string(body, r.position + Vector2(20, 82), page_text, HORIZONTAL_ALIGNMENT_LEFT, w - 40, 15, -1, Color(0.92, 0.88, 1.0, a))
	tut_ok = Rect2(r.end.x - 170, r.end.y - 44, 150, 30)
	var hover_ok := tut_ok.has_point(get_local_mouse_position())
	Style.panel(self, tut_ok, gold, Color(0.25, 0.18, 0.03, 0.95 * a) if hover_ok else Color(0.12, 0.08, 0.02, 0.95 * a))
	var ok_t := "START  [ENTER]" if tut_page == TUTORIAL.size() - 1 else "DALEJ  [ENTER]"
	var ow := font.get_string_size(ok_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, Vector2(tut_ok.get_center().x - ow * 0.5, tut_ok.position.y + 20), ok_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, gold)
	var sk_t := "Pomiń samouczek"
	var sw := body.get_string_size(sk_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	tut_skip = Rect2(r.position.x + 14, r.end.y - 40, sw + 12, 24)
	var hover_sk := tut_skip.has_point(get_local_mouse_position())
	draw_string(body, tut_skip.position + Vector2(6, 16), sk_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.65, 0.9, a) if hover_sk else Color(0.5, 0.42, 0.62, a))


func _draw_messages(vs: Vector2) -> void:
	match state:
		"intro":
			_draw_intro_title(vs)
		"tutorial":
			_draw_tutorial(vs)
		"warning":
			if int(time * 5.0) % 2 == 0:
				_center_text(vs, vs.y * 0.42, "UWAGA: " + boss_title, 40, Color(1.4, 0.25, 0.25))
		"win":
			var win_msg := "STRAŻNICZKA POKONANA" if sector == 2 else (boss_title + " — ZNISZCZONY")
			_center_text(vs, vs.y * 0.42, win_msg, 48, Style.GOLD)
			_center_text(vs, vs.y * 0.42 + 44.0, "+1 PUNKT CHWAŁY IMPERIUM" if reward else "NAGRODA ZOSTAŁA JUŻ ODEBRANA", 24, Style.PINK)
		"lose":
			_center_text(vs, vs.y * 0.42, "STATEK ZNISZCZONY", 48, Color(1.4, 0.25, 0.25))
			_center_text(vs, vs.y * 0.42 + 44.0, "WRÓĆ PRZEZ RÓŻOWY PUNKT W MIEŚCIE", 24, Style.PINK)
