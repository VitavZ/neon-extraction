extends Node2D
## Szkolenie w Roswell (TUTORIAL w menu głównym). Osobna rozgrywka bez zapisu (GameState.training) na obszarze
## mniejszym od sektora, wokół Roswell w Nowym Meksyku. Scenariusz:
##   surowce -> ostatni poziom Mocy lasera -> tarcza Roswell pada -> zniszcz miasto -> odblokuj Odbudowę ->
##   odbuduj 80% miasta -> myśliwce atakują Statek Matkę -> 6 s ciszy -> DANGER! -> OBIEKT-51 (walka nie do wygrania)
##   -> transmisja od Imperium Vex -> koniec szkolenia i osiągnięcie "training".
## main.gd tworzy węzeł, gdy GameState.training, woła setup() i pyta can_dock() / handle_death().
## Okienka z poleceniami to tutorial.gd w trybie custom (kroki STEPS niżej).

const Style = preload("res://scripts/style.gd")
const Sectors = preload("res://scripts/sectors.gd")

const SECTOR := 4                                   # Wielkie Równiny (tu jest Roswell i postój Matki)
const ROSWELL_LONLAT := Vector2(-104.52, 33.39)
const TOWN_R := 4.5                                 # promień miasta w kafelkach
const TOWN_TURRETS := 7
const AREA := Rect2i(120, 236, 100, 96)             # obszar szkolenia w kafelkach (sektor ma 160x160)
const LASER_GATE := 80.0                            # moc lasera, która przebija tarczę Roswell
const REBUILD_GOAL := 0.8

## Statek na start: na tyle mocny, żeby poczuć siłę, ale laser jeszcze nie przebije tarczy miasta.
const LEVELS := {
	"laser_dmg": 3, "laser_resonator": 1, "laser_range": 2, "laser_splash": 1, "armory": 1,
	"rockets": 1, "rocket_dmg": 2, "rocket_reload": 2, "drones": 1, "drone_more": 1, "drone_dmg": 2,
	"hull": 4, "shield": 3, "armor": 2, "thrust": 3, "max_speed": 2, "turn": 1, "fuel_tank": 2,
	"cargo": 5, "cargo2": 1, "yield": 1,
}
const BANK := {}
## Ceny w szkoleniu (zamiast zwykłych): mało, żeby zebrać je w jednym locie.
const COSTS := {
	"laser_dmg": {"biomass": 40, "stone": 30},
	"rebuild": {"scrap": 30, "metal": 15},
}

enum { GATHER, UPGRADE, DESTROY, UNLOCK, REBUILD, SIEGE, CALM, DANGER, BOSS, DEFEAT, VEX, DONE }
## Pierwsze okienko każdej fazy (gdy gracz wyprzedzi okienka, samouczek przeskakuje do bieżącego).
const PHASE_STEP := {GATHER: 0, UPGRADE: 2, DESTROY: 3, UNLOCK: 4, REBUILD: 5, SIEGE: 6}

## [tytuł, tekst, podświetlenie, ikona] - format tutorial.gd
const STEPS := [
	["SZKOLENIE: ROSWELL",
		"Witaj w ośrodku szkoleniowym Imperium Vex, Kadecie. Dostajesz okręt, który już przeszedł kilka modernizacji: mocny kadłub, tarcza, rakiety [{rocket}] i drony.\n\nTwój cel to Roswell - małe ziemskie miasto na zachód od Statku Matki. Naciśnij WYLOT [{dock}].", "", "crown"],
	["ZADANIE: SUROWCE",
		"Roswell osłania tarcza energetyczna. Przebije ją dopiero laser o mocy co najmniej 80, a Twój ma 60.\n\nZbierz 40 biomasy (równiny) i 30 kamienia (góry), wróć do Statku Matki [{dock}] i dokup ostatni poziom MOCY LASERA. Cel widzisz na dole ekranu.", "cargo", "crate"],
	["ULEPSZ LASER",
		"Masz surowce. Na siatce ulepszeń kliknij węzeł MOC LASERA (nad rdzeniem) i kup ostatni poziom.\n\nOstatni poziom każdego węzła daje premię MISTRZOSTWA - moc lasera skoczy do 80.", "", "wrench"],
	["TARCZA ROSWELL PADŁA",
		"Laser jest wystarczająco silny - tarcza miasta zgasła.\n\nZniszcz całe Roswell. Uważaj na wieżyczki: czerwone okręgi to ich zasięg, a wieżyczki rakietowe wystrzeliwują pociski namierzające. Pomagaj sobie rakietami [{rocket}].", "", "bolt"],
	["ODBUDOWA",
		"Roswell leży w gruzach. Imperium nie niszczy jednak bez celu - z ruin budujemy własne miasta.\n\nWróć na Statek Matkę [{dock}] i odblokuj ODBUDOWĘ: siatka ulepszeń, gałąź ŁADOWNIA -> KOMPRESJA -> ODBUDOWA. Surowce z miasta wystarczą.", "", "crown"],
	["ODBUDUJ ROSWELL",
		"Wybierz narzędzie odbudowy [{tool3}] i przytrzymaj [LPM] na gruzach miasta. Każdy odbudowany kafelek staje się kafelkiem Imperium.\n\nOdbuduj 80% Roswell. Zwykle każdy kafelek kosztuje surowce - w szkoleniu odbudowę funduje Imperium.", "", "wrench"],
	["ZIEMIA KONTRATAKUJE",
		"Ziemianie nie odpuszczą utraty miasta - eskadra myśliwców atakuje Statek Matkę!\n\nLeć jej bronić i zestrzel wszystkie myśliwce. Do końca walki hangar pozostaje zamknięty.", "", "shield"],
]

const VEX_TEXT := "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.\n\nDuis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

const BOSS_NAME := "OBIEKT-51"
const BOSS_HP := 60000.0
const BOSS_SPEED := 330.0
const BOSS_ORBIT := 430.0
const BOSS_SCALE := 0.8               # ok. 5x większy od statku gracza
const BOSS_HR := 75.0                 # promień trafienia (statek gracza ma ok. 20)
const BOSS_HULL := [Vector2(95, 0), Vector2(40, -30), Vector2(10, -95), Vector2(-30, -105), Vector2(-55, -70), Vector2(-40, -25),
	Vector2(-70, 0), Vector2(-40, 25), Vector2(-55, 70), Vector2(-30, 105), Vector2(10, 95), Vector2(40, 30)]
const EMITTERS := [Vector2(14, -92), Vector2(14, 92)]
const GUNS := [Vector2(52, -22), Vector2(52, 22)]
const PODS := [Vector2(-24, -52), Vector2(-24, 52)]
const DANGER_TIME := 3.8
const FINAL_AT := 45.0                 # po tylu sekundach walki: działo główne (fala, przed którą nie ma ucieczki)
const FINAL_CHARGE := 2.6
const FINAL_SPEED := 1400.0
const CALM_TIME := 6.0

var main: Node2D
var world: Node2D
var ship: Node2D
var tutorial: Control
var phase := GATHER
var t := 0.0                          # czas fazy
var time := 0.0
var town: Array = []                  # kafelki Roswell
var town_center := Vector2.ZERO
var shield_drop := -1.0               # animacja gaśnięcia tarczy
var ui: Control
var ui_layer: CanvasLayer
var boss_view: Node2D
var boss: Dictionary = {}
var gun_cd := 3.0
var gun_burst := 0
var gun_side := 0
var rocket_cd := 4.5
var laser_state := "idle"
var laser_t := 0.0
var laser_cd := 6.0
var laser_ang: Array = [0.0, 0.0]
var vex_typed := 0.0
var end_t := 0.0
var btn_rect := Rect2()
var btn_hover := false
var alarm_cd := 0.0
var final_t := -1.0                  # czas od rozpoczęcia ładowania działa głównego
var final_r := -1.0                  # promień fali (< 0 = brak)


func setup() -> void:
	world = main.world
	ship = main.ship
	z_index = 4
	var c := Sectors.cell_of(ROSWELL_LONLAT)
	town = world.stamp_town(c, TOWN_R, TOWN_TURRETS, GameState.world_seed)
	town_center = Vector2(c.x * world.T + world.T * 0.5, c.y * world.T + world.T * 0.5)
	for i in town:
		world.protected[i] = true
	world.play_rect = Rect2(Vector2(AREA.position) * world.T, Vector2(AREA.size) * world.T)
	boss_view = Node2D.new()
	boss_view.z_index = 7
	main.add_child(boss_view)
	boss_view.draw.connect(_draw_boss)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 18
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(ui_layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	ui_layer.add_child(ui)
	ui.draw.connect(_draw_ui)
	# ekrany końcowe działają w pauzie, a scenariusz stoi, gdy pauzują go okienka lub menu pauzy
	process_mode = Node.PROCESS_MODE_ALWAYS
	tutorial = main.tutorial
	tutorial.custom = true
	tutorial.steps = STEPS
	tutorial.header = "SZKOLENIE"
	tutorial.cstep = 0
	tutorial.custom_cond = _popup_cond


# =====================================================================
# SCENARIUSZ
# =====================================================================

func can_dock() -> bool:
	return phase < SIEGE


## Śmierć statku: przy bossie to koniec szkolenia (true = main nie odsyła wraku do doku).
func handle_death() -> bool:
	if phase == BOSS:
		_go(DEFEAT)
		return true
	if phase >= SIEGE and phase < BOSS:
		# atak na Matkę zacznie się od nowa po kolejnym wylocie
		main.mothership.siege = false
		_go(REBUILD)
	return false


func _go(p: int) -> void:
	phase = p
	t = 0.0


## Faza, od której wolno pokazać dane okienko (okienko nie może wyprzedzać prawdziwego postępu).
const STEP_PHASE := [GATHER, GATHER, UPGRADE, DESTROY, UNLOCK, REBUILD, SIEGE]


func _popup_cond(step: int) -> bool:
	if step >= STEP_PHASE.size() or phase < STEP_PHASE[step]:
		return false
	var docked: bool = ship.docked
	match step:
		0: return docked
		1: return not docked
		2: return docked
		3, 4: return true
		5, 6: return not docked
	return false


func destroyed_frac() -> float:
	var n := 0
	for i in town:
		if world.layer[i] != world.L_SURFACE:
			n += 1
	return float(n) / maxf(1.0, town.size())


func rebuilt_frac() -> float:
	var n := 0
	for i in town:
		if world.layer[i] == world.L_IMPERIAL:
			n += 1
	return float(n) / maxf(1.0, town.size())


func _have(res: String) -> int:
	return int(GameState.bank.get(res, 0)) + int(GameState.cargo.get(res, 0))


func _process(delta: float) -> void:
	ui.queue_redraw()
	if phase == VEX or phase == DONE:
		time += delta
		if phase == VEX:
			vex_typed = minf(vex_typed + delta * 70.0, VEX_TEXT.length())
		else:
			end_t += delta
		return
	if get_tree().paused:
		return
	time += delta
	t += delta
	shield_drop = maxf(-1.0, shield_drop - delta) if shield_drop > 0.0 else shield_drop
	# okienka nie mogą utknąć na fazie, którą gracz już przeszedł
	if PHASE_STEP.has(phase) and not tutorial.showing and tutorial.cstep < PHASE_STEP[phase]:
		tutorial.cstep = PHASE_STEP[phase]
	match phase:
		GATHER:
			if GameState.stat("laser_dps") >= LASER_GATE:
				_drop_shield()
			elif ship.docked and GameState.can_afford(COSTS["laser_dmg"]):
				_go(UPGRADE)
		UPGRADE:
			if GameState.stat("laser_dps") >= LASER_GATE:
				_drop_shield()
		DESTROY:
			if destroyed_frac() >= 1.0:
				_go(UNLOCK)
				main.hud.show_big("ROSWELL ZNISZCZONE", "Wróć na Statek Matkę i odblokuj Odbudowę")
				main.fx.shake(10.0)
				Audio.play("explosion_big", 0.0, 3.0)
		UNLOCK:
			if GameState.stat("rebuild") > 0.0:
				_go(REBUILD)
			elif ship.docked and not GameState.can_afford(COSTS["rebuild"]):
				# łup z miasta przepadł (np. zestrzelenie) - Imperium dosyła brakujące surowce
				for k in COSTS["rebuild"]:
					GameState.bank[k] = maxi(int(GameState.bank.get(k, 0)), int(COSTS["rebuild"][k]))
				GameState.bank_changed.emit()
				main.upgrade_screen.status_text = "Imperium przysłało surowce na Odbudowę."
		REBUILD:
			if rebuilt_frac() >= REBUILD_GOAL - 0.0001 and not ship.docked and not ship.dead:
				_start_siege()
		SIEGE:
			if t > 1.0 and _siege_left() == 0:
				_go(CALM)
				main.mothership.siege = false
				main.hud.show_big("ATAK ODPARTY", "Statek Matka ocalał")
				Audio.play("research_done", 0.0)
		CALM:
			if t >= CALM_TIME:
				_go(DANGER)
				Audio.play("boss_enter", 0.0, 2.0)
		DANGER:
			alarm_cd -= delta
			if alarm_cd <= 0.0:
				alarm_cd = 0.95
				Audio.play("alarm", 0.0, 2.0)
			if t >= DANGER_TIME:
				_spawn_boss()
		BOSS:
			_update_boss(delta)
		DEFEAT:
			_update_boss(delta)
			if t >= 2.6:
				_go(VEX)
				vex_typed = 0.0
				Audio.stop_loops()
				Audio.play("popup", 0.0)
				get_tree().paused = true
	queue_redraw()
	boss_view.queue_redraw()


func _drop_shield() -> void:
	_go(DESTROY)
	world.protected.clear()
	shield_drop = 1.2
	main.fx.ring(town_center, Color(0.4, 1.2, 1.4), 320.0, 0.9)
	Audio.play("research_done", 0.0)
	if not ship.docked:
		main.hud.show_big("TARCZA ROSWELL ZGASŁA", "Zniszcz miasto")
	else:
		main.upgrade_screen.status_text = "Laser przebije tarczę Roswell. Leć zniszczyć miasto!"


func _start_siege() -> void:
	_go(SIEGE)
	var mp: Vector2 = main.mothership.global_position
	var enemies = main.enemies
	var start: int = enemies.fighters.size()
	enemies.spawn_near(mp, 4)
	enemies.spawn_near(mp, 1, "gunner")
	for k in range(start, enemies.fighters.size()):
		enemies.fighters[k]["siege"] = true
	main.mothership.siege = true
	Audio.play("alarm", 0.0)
	main.hud.show_big("ZIEMIA KONTRATAKUJE!", "Statek Matka pod ostrzałem — leć jej bronić!")


func _siege_left() -> int:
	var n := 0
	for f in main.enemies.fighters:
		if f.get("siege", false) and not f.get("dead", false):
			n += 1
	return n


# =====================================================================
# OBIEKT-51
# =====================================================================

func _spawn_boss() -> void:
	_go(BOSS)
	var from: Vector2 = ship.global_position + Vector2.from_angle(randf() * TAU) * 1500.0
	boss = {"kind": "obiekt", "ext": true, "pos": from, "vel": Vector2.ZERO, "rot": (ship.global_position - from).angle(),
		"hp": BOSS_HP, "max_hp": BOSS_HP, "flash": 0.0, "dmg": 0.0, "hr": BOSS_HR, "cd": 0.0, "orbit": 1.0}
	main.enemies.fighters.append(boss)
	gun_cd = 3.0
	rocket_cd = 4.5
	laser_cd = 6.5
	laser_state = "idle"
	final_t = -1.0
	final_r = -1.0
	main.fx.shake(16.0)
	Audio.play("explosion_big", 0.0, 4.0)
	main.hud.show_big(BOSS_NAME, "Ziemska broń z hangarów Strefy 51")


## Działo główne: po FINAL_AT sekundach boss ładuje rdzeń, a potem wypuszcza falę plazmy przez cały obszar.
## Gwarantuje porażkę także graczowi, który świetnie robi uniki.
func _update_final(delta: float) -> void:
	if phase != BOSS:
		if final_r >= 0.0:
			final_r += FINAL_SPEED * delta
		return
	if final_t < 0.0:
		if t >= FINAL_AT and not ship.dead:
			final_t = 0.0
			laser_state = "idle"
			laser_cd = 99.0
			gun_cd = 99.0
			rocket_cd = 99.0
			main.hud.show_big("DZIAŁO GŁÓWNE", "OBIEKT-51 ładuje rdzeń — nie ma ucieczki")
			Audio.play("boss_enter", 0.0, 4.0)
			Audio.play("alarm", 0.0, 2.0)
		return
	final_t += delta
	if final_t < FINAL_CHARGE:
		main.fx.shake(2.0 + final_t * 2.0)
		return
	if final_r < 0.0:
		final_r = 0.0
		main.fx.shake(20.0)
		Audio.play("explosion_big", 0.0, 6.0)
		Audio.play("plasma_burst", 0.0, 4.0)
	final_r += FINAL_SPEED * delta
	if not ship.dead and final_r >= ship.global_position.distance_to(boss["pos"]):
		ship.shield = 0.0
		ship.take_damage(1000000.0)


## Złość rośnie z czasem walki: walka ma się skończyć porażką, ale nie od razu.
func _rage() -> float:
	return 0.7 + t / 12.0


func _update_boss(delta: float) -> void:
	if boss.is_empty():
		return
	var p: Vector2 = boss["pos"]
	var sp: Vector2 = ship.global_position
	var to := sp - p
	var dist := to.length()
	boss["flash"] = maxf(0.0, float(boss["flash"]) - delta)
	# tarcza pancerza: poniżej połowy kadłub sam się łata (nie da się go zestrzelić)
	boss["hp"] = maxf(float(boss["hp"]), BOSS_HP * 0.5)
	var desired: Vector2
	if phase == DEFEAT or ship.dead:
		desired = Vector2.ZERO
	elif t < 2.5:
		desired = to.normalized() * BOSS_SPEED * 2.2       # wejście: szarża w stronę gracza
	elif dist > BOSS_ORBIT + 60.0:
		desired = to.normalized() * BOSS_SPEED
	else:
		var tangent := to.normalized().rotated(PI * 0.5)
		desired = (tangent * 0.6 + to.normalized() * (dist - BOSS_ORBIT) / 200.0).normalized() * BOSS_SPEED * 0.6
	boss["vel"] = (boss["vel"] as Vector2).move_toward(desired, 520.0 * delta)
	boss["pos"] = p + boss["vel"] * delta
	boss["rot"] = lerp_angle(float(boss["rot"]), to.angle(), 1.6 * delta)
	_update_final(delta)
	if phase != BOSS or ship.dead or t < 2.5:
		return
	var rage := _rage()
	var xf := Transform2D(float(boss["rot"]), Vector2.ONE * BOSS_SCALE, 0.0, boss["pos"])
	# karabiny: serie na zmianę z obu dział
	gun_cd -= delta
	if gun_cd <= 0.0:
		if gun_burst <= 0:
			gun_burst = 12
		var muzzle: Vector2 = xf * GUNS[gun_side]
		gun_side = 1 - gun_side
		# celowanie z wyprzedzeniem: unik po okręgu nie wystarcza
		var lead: Vector2 = sp + ship.vel * (muzzle.distance_to(sp) / 620.0) * 0.85
		var dir := (lead - muzzle).normalized().rotated(randf_range(-0.08, 0.08))
		world.bullets.append({"pos": muzzle, "vel": dir * 620.0, "life": 2.2, "dmg": 7.0 * rage})
		Audio.play("gun_shot", 0.1, -4.0)
		gun_burst -= 1
		gun_cd = 0.08 if gun_burst > 0 else 1.2
	# rakiety: salwa pocisków namierzających (można je zestrzelić laserem)
	rocket_cd -= delta
	if rocket_cd <= 0.0:
		rocket_cd = maxf(2.5, 5.0 - t * 0.04)
		for k in 4:
			var pod: Vector2 = xf * PODS[k % 2]
			world.missiles.append({"pos": pod, "rot": float(boss["rot"]) + (k - 1.5) * 0.5, "speed": 220.0,
				"life": world.MISSILE_LIFE, "hp": world.MISSILE_HP * 2.0, "dmg": 28.0 * rage})
		Audio.play("rocket_launch", 0.05, 4.0)
		world.missile_launched.emit()
	# lasery: ładowanie z celownikiem, potem dwie wiązki powoli wodzą za statkiem
	match laser_state:
		"idle":
			laser_cd -= delta
			if laser_cd <= 0.0:
				laser_state = "charge"
				laser_t = 0.0
				for k in 2:
					laser_ang[k] = (sp - xf * EMITTERS[k]).angle()
				Audio.play("missile_warning", 0.0, 4.0)
		"charge":
			laser_t += delta
			for k in 2:
				laser_ang[k] = rotate_toward(laser_ang[k], (sp - xf * EMITTERS[k]).angle(), 2.5 * delta)
			if laser_t >= 1.3:
				laser_state = "fire"
				laser_t = 0.0
				Audio.play("plasma_burst", 0.0, 2.0)
		"fire":
			laser_t += delta
			for k in 2:
				var e: Vector2 = xf * EMITTERS[k]
				laser_ang[k] = rotate_toward(laser_ang[k], (sp - e).angle(), (0.9 + t * 0.02) * delta)
				var end := e + Vector2.from_angle(laser_ang[k]) * 1500.0
				var cp := Geometry2D.get_closest_point_to_segment(sp, e, end)
				if cp.distance_to(sp) < 20.0:
					ship.take_damage(70.0 * rage * delta)
			if laser_t >= 2.2:
				laser_state = "idle"
				laser_cd = maxf(3.5, 6.5 - t * 0.05)


# =====================================================================
# RYSOWANIE W ŚWIECIE: obszar, tarcza i podpis Roswell
# =====================================================================

func _draw() -> void:
	var pr: Rect2 = world.play_rect
	var big := Rect2(-4000, -4000, world.N * world.T + 8000, world.H * world.T + 8000)
	var dark := Color(0.0, 0.0, 0.02, 0.62)
	draw_rect(Rect2(big.position, Vector2(big.size.x, pr.position.y - big.position.y)), dark)
	draw_rect(Rect2(Vector2(big.position.x, pr.end.y), Vector2(big.size.x, big.end.y - pr.end.y)), dark)
	draw_rect(Rect2(Vector2(big.position.x, pr.position.y), Vector2(pr.position.x - big.position.x, pr.size.y)), dark)
	draw_rect(Rect2(Vector2(pr.end.x, pr.position.y), Vector2(big.end.x - pr.end.x, pr.size.y)), dark)
	var pulse := 0.5 + 0.5 * sin(time * 2.0)
	draw_rect(pr, Color(1.3, 0.3, 1.0, 0.25 + 0.2 * pulse), false, 10.0)
	draw_rect(pr, Color(1.4, 0.6, 1.3, 0.8), false, 3.0)
	# podpis miasta
	var pf := Style.font_pixel()
	var label_txt := "ROSWELL"
	var w := pf.get_string_size(label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	var at := town_center + Vector2(-w * 0.5, -TOWN_R * world.T - 40.0)
	draw_string_outline(pf, at, label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, 12, Color(0.02, 0.0, 0.06, 0.92))
	draw_string(pf, at, label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(1.3, 0.75, 1.2))
	# kopuła tarczy: heksagonalna siatka, migotanie, przy gaśnięciu rozpada się
	var r: float = (TOWN_R + 1.2) * world.T
	if not world.protected.is_empty():
		_draw_dome(r, 1.0)
	elif shield_drop > 0.0:
		_draw_dome(r * (1.0 + (1.2 - shield_drop) * 0.4), shield_drop / 1.2)


func _draw_dome(r: float, a: float) -> void:
	var c := town_center
	draw_circle(c, r, Color(0.2, 0.7, 1.0, 0.07 * a))
	for k in 3:
		var rr := r * (0.55 + k * 0.22)
		draw_arc(c, rr, time * (0.3 + k * 0.15), time * (0.3 + k * 0.15) + TAU * 0.8, 48, Color(0.4, 1.1, 1.4, 0.18 * a), 2.0, true)
	var flick := 0.75 + 0.25 * sin(time * 13.0)
	draw_arc(c, r, 0.0, TAU, 96, Color(0.5, 1.2, 1.5, 0.85 * a * flick), 4.0, true)
	draw_arc(c, r + 8.0, 0.0, TAU, 96, Color(0.3, 0.9, 1.4, 0.3 * a), 10.0, true)
	for k in 12:
		var ang := time * 0.25 + k * TAU / 12.0
		draw_line(c + Vector2.from_angle(ang) * (r - 14.0), c + Vector2.from_angle(ang) * (r + 14.0), Color(0.6, 1.3, 1.5, 0.6 * a), 2.0, true)


# =====================================================================
# RYSOWANIE BOSSA
# =====================================================================

func _draw_boss() -> void:
	if boss.is_empty():
		return
	var cv := boss_view
	var xf := Transform2D(float(boss["rot"]), Vector2.ONE * BOSS_SCALE, 0.0, boss["pos"])
	var p: Vector2 = boss["pos"]
	var hit: bool = float(boss["flash"]) > 0.0
	var pulse := 0.5 + 0.5 * sin(time * 5.0)
	# cień i pierścień zagrożenia
	cv.draw_circle(p, 120.0 * BOSS_SCALE, Color(0.0, 0.0, 0.0, 0.45))
	cv.draw_arc(p, 128.0 * BOSS_SCALE, 0.0, TAU, 72, Color(1.4, 0.15, 0.2, 0.35 + 0.35 * pulse), 3.0, true)
	# silniki
	for s in [-1.0, 1.0]:
		var e := xf * Vector2(-62, 38 * s)
		var flame := xf * Vector2(-62 - 30 - randf() * 25.0, 38 * s)
		cv.draw_line(e, flame, Color(1.3, 0.45, 0.15, 0.9), 12.0, true)
		cv.draw_line(e, flame.lerp(e, 0.4), Color(1.5, 1.2, 0.8), 5.0, true)
	# kadłub
	var hull := xf * PackedVector2Array(BOSS_HULL)
	cv.draw_colored_polygon(hull, Color(0.28, 0.08, 0.1) if hit else Color(0.07, 0.03, 0.09, 0.98))
	var line := Color(1.6, 1.4, 1.4) if hit else Color(1.4, 0.22, 0.3)
	cv.draw_polyline(Style.closed(hull), Color(line.r, line.g, line.b, 0.35), 9.0, true)
	cv.draw_polyline(Style.closed(hull), line, 3.0, true)
	# płyty pancerza
	var inner := PackedVector2Array([Vector2(60, 0), Vector2(20, -24), Vector2(-4, -70), Vector2(-30, -78), Vector2(-28, -20),
		Vector2(-46, 0), Vector2(-28, 20), Vector2(-30, 78), Vector2(-4, 70), Vector2(20, 24)])
	cv.draw_polyline(Style.closed(xf * inner), Color(1.0, 0.3, 0.45, 0.45), 1.5, true)
	for s in [-1.0, 1.0]:
		cv.draw_line(xf * Vector2(30, 14 * s), xf * Vector2(-20, 60 * s), Color(1.0, 0.3, 0.45, 0.35), 1.2)
	# wyrzutnie rakiet
	for pod in PODS:
		var pr := PackedVector2Array([pod + Vector2(-10, -7), pod + Vector2(10, -7), pod + Vector2(10, 7), pod + Vector2(-10, 7)])
		cv.draw_colored_polygon(xf * pr, Color(0.2, 0.05, 0.05))
		cv.draw_polyline(Style.closed(xf * pr), Color(1.3, 0.55, 0.2), 1.6, true)
		for k in 3:
			cv.draw_circle(xf * (pod + Vector2(-6 + k * 6, 0)), 2.0, Color(1.4, 0.7, 0.3) if rocket_cd < 1.0 and fmod(time * 8.0, 1.0) < 0.5 else Color(0.6, 0.2, 0.1))
	# działa: lufy celują w gracza
	for g in GUNS:
		var gp: Vector2 = xf * g
		var gd: Vector2 = (ship.global_position - gp).normalized()
		cv.draw_circle(gp, 10.0, Color(0.15, 0.05, 0.08))
		cv.draw_arc(gp, 10.0, 0.0, TAU, 20, Color(1.3, 0.85, 0.3), 1.8, true)
		cv.draw_line(gp + gd * 6.0, gp + gd * 26.0, Color(1.3, 0.85, 0.3), 4.0, true)
	# emitery laserów i wiązki
	for k in 2:
		var e: Vector2 = xf * EMITTERS[k]
		var charge := laser_t / 1.3 if laser_state == "charge" else (1.0 if laser_state == "fire" else 0.0)
		cv.draw_circle(e, 9.0 + 6.0 * charge, Color(1.4, 0.15, 0.25, 0.35 + 0.5 * charge))
		cv.draw_circle(e, 5.0, Color(1.6, 0.8, 0.9))
		var end := e + Vector2.from_angle(laser_ang[k]) * 1500.0
		if laser_state == "charge":
			var fl := 0.4 + 0.6 * float(fmod(time * 20.0, 1.0) > 0.5)
			cv.draw_line(e, end, Color(1.4, 0.2, 0.25, 0.35 * fl), 1.5, true)
		elif laser_state == "fire":
			var wob := 1.0 + 0.15 * sin(time * 40.0)
			cv.draw_line(e, end, Color(1.4, 0.1, 0.2, 0.35), 34.0 * wob, true)
			cv.draw_line(e, end, Color(1.5, 0.35, 0.4, 0.8), 16.0 * wob, true)
			cv.draw_line(e, end, Color(1.8, 1.5, 1.6), 5.0, true)
	# działo główne: rdzeń puchnie, wsysa iskry, potem rozchodzi się fala
	var core := xf * Vector2(4, 0)
	if final_t >= 0.0 and final_r < 0.0:
		var ck := clampf(final_t / FINAL_CHARGE, 0.0, 1.0)
		cv.draw_circle(core, 40.0 + 90.0 * ck, Color(1.5, 0.2, 0.3, 0.12 + 0.2 * ck))
		cv.draw_arc(core, 220.0 * (1.0 - fmod(final_t * 1.8, 1.0)), 0.0, TAU, 64, Color(1.6, 0.5, 0.6, 0.6 * ck), 3.0, true)
		for k in 10:
			var a := k * TAU / 10.0 + final_t * 3.0
			var rr := 260.0 * (1.0 - fmod(final_t * 1.3 + k * 0.1, 1.0))
			cv.draw_line(core + Vector2.from_angle(a) * rr, core + Vector2.from_angle(a) * (rr + 24.0), Color(1.7, 0.8, 0.85, ck), 2.5, true)
	if final_r >= 0.0:
		cv.draw_arc(boss["pos"], final_r, 0.0, TAU, 160, Color(1.5, 0.15, 0.25, 0.35), 60.0, true)
		cv.draw_arc(boss["pos"], final_r, 0.0, TAU, 160, Color(1.8, 0.7, 0.8, 0.9), 16.0, true)
		cv.draw_arc(boss["pos"], final_r * 0.92, 0.0, TAU, 160, Color(1.4, 0.2, 0.3, 0.3), 6.0, true)
	cv.draw_circle(core, 26.0 + 4.0 * pulse, Color(1.4, 0.1, 0.2, 0.3))
	cv.draw_circle(core, 16.0, Color(0.25, 0.02, 0.05))
	cv.draw_arc(core, 16.0, 0.0, TAU, 32, Color(1.5, 0.3, 0.35), 2.5, true)
	cv.draw_circle(core, 7.0 + 3.0 * pulse, Color(1.7, 0.9, 0.9))
	for k in 6:
		var a := time * 1.5 + k * TAU / 6.0
		cv.draw_line(core + Vector2.from_angle(a) * 20.0, core + Vector2.from_angle(a) * 30.0, Color(1.4, 0.3, 0.35, 0.8), 2.0, true)


# =====================================================================
# EKRAN: cel, DANGER!, pasek bossa, transmisja Vex, koniec szkolenia
# =====================================================================

func _input(event: InputEvent) -> void:
	if phase != VEX and phase != DONE:
		return
	var confirm := false
	if event is InputEventKey and event.pressed and not event.echo:
		confirm = event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	elif event is InputEventMouseMotion:
		var h := btn_rect.has_point(event.position)
		if h and not btn_hover:
			Audio.play("ui_hover", 0.0)
		btn_hover = h
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		confirm = btn_rect.has_point(event.position)
	if not confirm:
		return
	get_viewport().set_input_as_handled()
	Audio.play("ui_click", 0.0)
	if phase == VEX:
		if vex_typed < VEX_TEXT.length():
			vex_typed = VEX_TEXT.length()
			return
		_go(DONE)
		end_t = 0.0
		Achievements.unlock("training")
		Audio.play("research_done", 0.0)
	elif end_t > 0.6:
		get_tree().paused = false
		Audio.stop_loops()
		get_tree().change_scene_to_file("res://menu.tscn")


func _draw_ui() -> void:
	var vs := ui.get_viewport_rect().size
	if phase == VEX:
		_draw_vex(vs)
		return
	if phase == DONE:
		_draw_done(vs)
		return
	if not ship.docked and not ship.dead:
		_draw_objective(vs)
		_draw_town_arrow(vs)
	if phase == DANGER:
		_draw_danger(vs)
	if (phase == BOSS or phase == DEFEAT) and not boss.is_empty():
		_draw_boss_bar(vs)


func _objective() -> String:
	match phase:
		GATHER:
			var need: Dictionary = COSTS["laser_dmg"]
			return "CEL: zbierz %d/%d biomasy i %d/%d kamienia, potem wróć do Statku Matki" % [
				mini(_have("biomass"), need["biomass"]), need["biomass"], mini(_have("stone"), need["stone"]), need["stone"]]
		UPGRADE:
			return GameState.keys_text("CEL: zadokuj [{dock}] i kup ostatni poziom MOCY LASERA")
		DESTROY:
			return "CEL: zniszcz Roswell  —  %d%%" % int(destroyed_frac() * 100.0)
		UNLOCK:
			return "CEL: wróć na Statek Matkę i odblokuj ODBUDOWĘ"
		REBUILD:
			return GameState.keys_text("CEL: odbuduj Roswell narzędziem [{tool3}]  —  %d%% / %d%%") % [int(rebuilt_frac() * 100.0), int(REBUILD_GOAL * 100.0)]
		SIEGE:
			return "CEL: obroń Statek Matkę  —  myśliwce: %d" % _siege_left()
	return ""


func _draw_objective(vs: Vector2) -> void:
	var txt := _objective()
	if txt == "":
		return
	var font := Style.font_bold()
	var fs := 15
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 48.0
	var r := Rect2(vs.x * 0.5 - w * 0.5, vs.y - 128.0, w, 34.0)
	Style.chamfer_panel(ui, r, Style.GOLD, Color(0.06, 0.03, 0.0, 0.88), 8.0)
	var pulse := 0.5 + 0.5 * sin(time * 3.0)
	ui.draw_rect(Rect2(r.position.x + 8, r.position.y + 9, 4, 16), Color(1.3, 1.0, 0.4, 0.5 + 0.5 * pulse))
	ui.draw_string(font, Vector2(r.position.x + 24, r.position.y + 23), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.3, 1.05, 0.55))


## Strzałka przy krawędzi ekranu do Roswell, gdy miasto jest poza kadrem.
func _draw_town_arrow(vs: Vector2) -> void:
	if not (phase in [GATHER, UPGRADE, DESTROY, REBUILD]):
		return
	var sp: Vector2 = get_viewport().get_canvas_transform() * town_center
	var screen := Rect2(Vector2.ZERO, vs).grow(-60.0)
	if screen.has_point(sp):
		return
	var c := vs * 0.5
	var dir := (sp - c).normalized()
	var k := minf(absf((vs.x * 0.5 - 60.0) / maxf(0.001, absf(dir.x))), absf((vs.y * 0.5 - 60.0) / maxf(0.001, absf(dir.y))))
	var at := c + dir * k
	var col := Color(1.3, 0.6, 1.2)
	var tip := at + dir * 14.0
	var side := dir.orthogonal() * 10.0
	ui.draw_colored_polygon(PackedVector2Array([tip, at - dir * 8.0 + side, at - dir * 8.0 - side]), col)
	var font := Style.font_bold()
	var lbl := "ROSWELL"
	var lw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	ui.draw_string(font, at - dir * 30.0 + Vector2(-lw * 0.5, 4), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


## Ostrzeżenie DANGER!: czerwona winieta, taśmy ostrzegawcze wjeżdżające z boków i wielki migający napis.
func _draw_danger(vs: Vector2) -> void:
	var fade := clampf(t / 0.25, 0.0, 1.0) * clampf((DANGER_TIME - t) / 0.35, 0.0, 1.0)
	var beat := 0.5 + 0.5 * cos(t * TAU / 0.95)
	# czerwona winieta pulsująca w rytm alarmu
	var edge := Color(0.9, 0.0, 0.05, (0.35 + 0.3 * beat) * fade)
	var clear := Color(0.9, 0.0, 0.05, 0.0)
	var bw := vs.x * 0.22
	ui.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(bw, 0), Vector2(bw, vs.y), Vector2(0, vs.y)]), PackedColorArray([edge, clear, clear, edge]))
	ui.draw_polygon(PackedVector2Array([Vector2(vs.x - bw, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y), Vector2(vs.x - bw, vs.y)]), PackedColorArray([clear, edge, edge, clear]))
	ui.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.25, 0.0, 0.02, 0.25 * fade))
	# taśmy ostrzegawcze (żółto-czarne pasy), przesuwają się w przeciwne strony
	var cy := vs.y * 0.5
	var slide := 1.0 - pow(1.0 - clampf(t / 0.45, 0.0, 1.0), 3.0)
	for band in [[-150.0, 1.0], [150.0, -1.0]]:
		var by: float = cy + float(band[0]) - 26.0
		var off: float = (1.0 - slide) * vs.x * float(band[1])
		var r := Rect2(off, by, vs.x, 52.0)
		ui.draw_rect(r, Color(0.05, 0.03, 0.0, 0.92 * fade))
		var step := 56.0
		var scroll := fmod(time * 160.0 * float(band[1]), step * 2.0)
		var x := -step * 2.0 + scroll + off
		while x < vs.x + step * 2.0 + absf(off):
			ui.draw_colored_polygon(PackedVector2Array([Vector2(x, by), Vector2(x + step, by), Vector2(x + step - 26.0, by + 52.0), Vector2(x - 26.0, by + 52.0)]), Color(1.35, 1.0, 0.05, 0.95 * fade))
			x += step * 2.0
		ui.draw_line(Vector2(0, by), Vector2(vs.x, by), Color(1.4, 1.1, 0.2, fade), 2.0)
		ui.draw_line(Vector2(0, by + 52.0), Vector2(vs.x, by + 52.0), Color(1.4, 1.1, 0.2, fade), 2.0)
	# napis DANGER! z rozszczepieniem kolorów, uderzeniem skali i migotaniem
	var pf := Style.font_pixel()
	var punch := 1.0 + 0.35 * maxf(0.0, 1.0 - t / 0.3) + 0.04 * beat
	var fs := int(144 * punch)
	var txt := "DANGER!"
	var tw := pf.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2(vs.x * 0.5 - tw * 0.5, cy + fs * 0.36)
	var flick := 1.0 if fmod(time * 9.0, 1.0) > 0.18 else 0.35
	var a := fade * flick
	ui.draw_string_outline(pf, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 18, Color(0.08, 0.0, 0.0, 0.85 * fade))
	ui.draw_string(pf, tp + Vector2(-6, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.2, 0.9, 1.3, 0.55 * a))
	ui.draw_string(pf, tp + Vector2(6, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.4, 0.0, 0.1, 0.7 * a))
	ui.draw_string(pf, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.9, 0.45 + 0.6 * beat, 0.35, a))
	# trójkąty ostrzegawcze po bokach
	for s in [-1.0, 1.0]:
		var c := Vector2(vs.x * 0.5 + s * (tw * 0.5 + 90.0), cy - 6.0)
		var tri := PackedVector2Array([c + Vector2(0, -44), c + Vector2(40, 30), c + Vector2(-40, 30)])
		ui.draw_colored_polygon(tri, Color(1.35, 1.0, 0.05, (0.6 + 0.4 * beat) * fade))
		ui.draw_polyline(Style.closed(tri), Color(0.1, 0.05, 0.0, fade), 3.0, true)
		ui.draw_rect(Rect2(c + Vector2(-4, -20), Vector2(8, 28)), Color(0.08, 0.03, 0.0, fade))
		ui.draw_rect(Rect2(c + Vector2(-4, 14), Vector2(8, 8)), Color(0.08, 0.03, 0.0, fade))
	var sub := "NIEZIDENTYFIKOWANY OBIEKT NA KURSIE KOLIZYJNYM"
	var sf := Style.font_bold()
	var sw := sf.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	if fmod(time * 2.0, 1.0) < 0.75:
		ui.draw_string(sf, Vector2(vs.x * 0.5 - sw * 0.5, cy + 228.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.4, 0.35, 0.3, fade))
	# linie skanowania na całym ekranie
	var y := 0.0
	while y < vs.y:
		ui.draw_line(Vector2(0, y), Vector2(vs.x, y), Color(0.0, 0.0, 0.0, 0.12 * fade), 1.0)
		y += 4.0


func _draw_boss_bar(vs: Vector2) -> void:
	var w := minf(760.0, vs.x - 200.0)
	# na dole ekranu: góra jest zajęta przez komunikaty HUD
	var r := Rect2(vs.x * 0.5 - w * 0.5, vs.y - 112.0, w, 18.0)
	var pf := Style.font_pixel()
	var name_w := pf.get_string_size(BOSS_NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	ui.draw_string_outline(pf, Vector2(vs.x * 0.5 - name_w * 0.5, r.position.y - 8.0), BOSS_NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 8, Color(0.05, 0.0, 0.02, 0.9))
	ui.draw_string(pf, Vector2(vs.x * 0.5 - name_w * 0.5, r.position.y - 8.0), BOSS_NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.4, 0.25, 0.3))
	Style.chamfer_panel(ui, r.grow(4.0), Color(1.4, 0.25, 0.3), Color(0.05, 0.0, 0.02, 0.92), 6.0)
	var frac := clampf(float(boss["hp"]) / float(boss["max_hp"]), 0.0, 1.0)
	ui.draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), Color(1.3, 0.15, 0.25))
	ui.draw_rect(Rect2(r.position, Vector2(r.size.x * frac, 4.0)), Color(1.6, 0.7, 0.75, 0.6))
	# segmenty
	for k in range(1, 20):
		var x := r.position.x + r.size.x * k / 20.0
		ui.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0.05, 0.0, 0.02, 0.8), 2.0)
	if frac <= 0.5 + 0.001 and fmod(time * 2.0, 1.0) < 0.6:
		var s := "PANCERZ REGENERUJE SIĘ"
		var f := Style.font_bold()
		var sw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		ui.draw_string(f, Vector2(vs.x * 0.5 - sw * 0.5, r.end.y + 22.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.4, 0.6, 0.4))


## Transmisja od Imperium Vex po przegranej walce (tekst do podmiany: VEX_TEXT).
func _draw_vex(vs: Vector2) -> void:
	ui.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.0, 0.03, 0.82))
	var w := minf(820.0, vs.x - 80.0)
	var font := Style.font()
	var lines := _wrap(VEX_TEXT, font, 16, w - 80.0)
	var h := 200.0 + lines.size() * 26.0 + 90.0
	var r := Rect2(vs * 0.5 - Vector2(w, h) * 0.5, Vector2(w, h))
	Style.chamfer_panel(ui, r, Style.PINK, Color(0.03, 0.0, 0.06, 0.97), 18.0)
	for g in 3:
		ui.draw_polyline(Style.closed(Style.chamfer_pts(r.grow(5.0 + g * 5.0), 20.0 + g * 3.0)), Color(1.0, 0.35, 0.8, 0.2 - g * 0.06), 3.0, true)
	# emblemat Imperium Vex: oko w trójkącie i korona
	var ec := Vector2(r.position.x + 74, r.position.y + 78)
	var tri := PackedVector2Array([ec + Vector2(0, -38), ec + Vector2(36, 26), ec + Vector2(-36, 26)])
	ui.draw_colored_polygon(tri, Color(0.15, 0.02, 0.15))
	ui.draw_polyline(Style.closed(tri), Color(1.3, 0.35, 1.0), 2.5, true)
	ui.draw_arc(ec + Vector2(0, 6), 11.0, 0.0, TAU, 24, Color(0.4, 1.2, 1.4), 2.2, true)
	ui.draw_circle(ec + Vector2(0, 6), 4.0 + sin(time * 3.0), Color(0.5, 1.3, 1.5))
	var crown := PackedVector2Array([ec + Vector2(-18, -46), ec + Vector2(-18, -60), ec + Vector2(-9, -52), ec + Vector2(0, -64), ec + Vector2(9, -52), ec + Vector2(18, -60), ec + Vector2(18, -46)])
	ui.draw_polyline(crown, Style.GOLD, 2.2, true)
	var pf := Style.font_pixel()
	var fb := Style.font_bold()
	ui.draw_string(fb, Vector2(r.position.x + 140, r.position.y + 50), "TRANSMISJA PRIORYTETOWA  //  KANAŁ DOWÓDZTWA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.45, 0.85))
	ui.draw_string(pf, Vector2(r.position.x + 140, r.position.y + 96), "IMPERIUM VEX", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1.3, 1.0, 0.45))
	ui.draw_line(Vector2(r.position.x + 30, r.position.y + 140), Vector2(r.end.x - 30, r.position.y + 140), Color(1.0, 0.8, 0.3, 0.4), 1.0)
	# tekst wpisywany jak na terminalu
	var left := int(vex_typed)
	var y := r.position.y + 180.0
	var cur := Vector2(r.position.x + 40, y)
	for l in lines:
		if left <= 0:
			break
		var shown: String = l.substr(0, mini(left, l.length()))
		ui.draw_string(font, Vector2(r.position.x + 40, y), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.95, 0.9, 1.0))
		cur = Vector2(r.position.x + 40 + font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 3, y)
		left -= l.length() + 1
		y += 26.0
	if fmod(time, 1.0) < 0.5 or vex_typed < VEX_TEXT.length():
		ui.draw_rect(Rect2(cur + Vector2(0, -14), Vector2(9, 16)), Color(1.0, 0.35, 0.8, 0.85))
	var done := vex_typed >= VEX_TEXT.length()
	_draw_button(Rect2(r.end.x - 250, r.end.y - 64, 220, 42), "ODCZYTANO  [ENTER]" if done else "DALEJ  [ENTER]")


## Koniec szkolenia: podsumowanie i powrót do menu (osiągnięcie przyznaje się przy wejściu na ten ekran).
func _draw_done(vs: Vector2) -> void:
	var e := 1.0 - pow(1.0 - clampf(end_t / 0.5, 0.0, 1.0), 3.0)
	ui.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.0, 0.03, 0.9))
	var w := 760.0
	var h := 330.0
	var r := Rect2(vs * 0.5 - Vector2(w, h) * 0.5 + Vector2(0, (1.0 - e) * 40.0), Vector2(w, h))
	Style.chamfer_panel(ui, r, Style.GREEN, Color(0.02, 0.05, 0.03, 0.97), 18.0)
	var pf := Style.font_pixel()
	var title := "SZKOLENIE UKOŃCZONE"
	var tw := pf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x
	ui.draw_string(pf, Vector2(vs.x * 0.5 - tw * 0.5 + 3, r.position.y + 92 + 3), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(0.2, 0.9, 1.0, 0.5))
	ui.draw_string(pf, Vector2(vs.x * 0.5 - tw * 0.5, r.position.y + 92), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(0.6, 1.4, 0.7))
	var font := Style.font()
	var txt := "Poznałeś wydobycie, ulepszenia, niszczenie i odbudowę miast. Prawdziwa inwazja czeka - START w menu głównym."
	var lines := _wrap(txt, font, 16, w - 100.0)
	var y := r.position.y + 150.0
	for l in lines:
		var lw := font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		ui.draw_string(font, Vector2(vs.x * 0.5 - lw * 0.5, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.95, 0.9))
		y += 26.0
	var fb := Style.font_bold()
	var ach := "OSIĄGNIĘCIE: ABSOLWENT ROSWELL"
	var aw := fb.get_string_size(ach, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	ui.draw_string(fb, Vector2(vs.x * 0.5 - aw * 0.5, y + 14.0), ach, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Style.GOLD)
	_draw_button(Rect2(vs.x * 0.5 - 130, r.end.y - 66, 260, 44), "MENU GŁÓWNE  [ENTER]")


func _draw_button(br: Rect2, label: String) -> void:
	btn_rect = br
	var c := Style.GOLD
	var p := Style.chamfer_pts(br.grow(2.0 if btn_hover else 0.0), 8.0)
	ui.draw_colored_polygon(p, Color(0.32, 0.22, 0.04) if btn_hover else Color(0.14, 0.09, 0.02))
	ui.draw_polyline(Style.closed(p), Color(c.r * 1.2, c.g * 1.2, c.b * 1.2) if btn_hover else c, 2.0, true)
	var fb := Style.font_bold()
	var lw := fb.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	ui.draw_string(fb, Vector2(br.get_center().x - lw * 0.5, br.get_center().y + 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.3, 1.1, 0.6))


## Łamanie tekstu na linie (akapity rozdziela "\n"; pusta linia = odstęp).
func _wrap(txt: String, font: Font, fs: int, width: float) -> Array:
	var out: Array = []
	for para in txt.split("\n"):
		var cur := ""
		for word in para.split(" ", false):
			var next := word if cur == "" else cur + " " + word
			if font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width and cur != "":
				out.append(cur)
				cur = word
			else:
				cur = next
		out.append(cur)
	return out
