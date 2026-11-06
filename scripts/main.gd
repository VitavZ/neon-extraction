extends Node2D
## Główna scena: składa świat, statek, statek matkę, efekty, HUD i ekran ulepszeń.

const WorldScript = preload("res://scripts/world.gd")
const ShipScript = preload("res://scripts/ship.gd")
const MothershipScript = preload("res://scripts/mothership.gd")
const FxScript = preload("res://scripts/fx.gd")
const HudScript = preload("res://scripts/hud.gd")
const UpgradeScreenScript = preload("res://scripts/upgrade_screen.gd")
const EnemiesScript = preload("res://scripts/enemies.gd")
const WeaponsScript = preload("res://scripts/weapons.gd")
const CrtScript = preload("res://scripts/crt.gd")
const TutorialScript = preload("res://scripts/tutorial.gd")
const Sectors = preload("res://scripts/sectors.gd")
const BossGameScript = preload("res://scripts/boss_game.gd")
const PauseScript = preload("res://scripts/pause_menu.gd")
const MinersScript = preload("res://scripts/miners.gd")
const WingmenScript = preload("res://scripts/wingmen.gd")
const EscortsScript = preload("res://scripts/escorts.gd")
const TransitScript = preload("res://scripts/transit.gd")
const TrainingScript = preload("res://scripts/training.gd")
const MAX_PATROLS := 14
const BOSS_TRIGGER := 0.75
const MAX_ENEMIES := 18
const HANGAR_LOCK_RADIUS := 900.0

var world: Node2D
var ship: Node2D
var mothership: Node2D
var fx: Node2D
var hud: Control
var upgrade_screen: Control
var camera: Camera2D
var zoom_target := 1.0
var respawn_timer := -1.0
var full_warned := false
var enemies: Node2D
var cities_since_fighter := 0
var next_fighter_at := 14
var fuel_low_warned := false
var fuel_empty_warned := false
var weapons: Node2D
var pending_fighters := 0       # myśliwce, które czekają na kolejny wylot
var fighter_return_timer := -1.0
var hangar_warn_cd := 0.0
var missile_msg_cd := 0.0
var boss_layer: CanvasLayer
var pause_menu: Control
var miners: Node2D
var wingmen: Node2D
var escorts: Node2D
var transit: Node2D
var tutorial: Control
var training_ctl: Node2D       # szkolenie w Roswell (tylko gdy GameState.training)
var patrol_timer := 12.0
var barrier_msg_cd := 0.0
var boss_sector := -1
var zoom_speed := 1.0           # kamera lekko oddala się przy dużej prędkości
var zoom_kick := 0.0            # krótkie uderzenie zoomu przy zrywie z driftu
## Oblężenie Statku Matki: po upadku Nowego Jorku Ziemia co jakiś czas (czas lotu) uderza w bazę.
const SIEGE_MIN := 300.0
const SIEGE_MAX := 600.0
const SIEGE_LOSS := 0.3          # część zapasów z magazynu tracona przy zniszczeniu Statku Matki
var siege_timer := randf_range(SIEGE_MIN, SIEGE_MAX)


func _ready() -> void:
	# szkolenie ma gotowy stan z GameState.start_training() i niczego nie wczytuje
	var loaded := false if GameState.training else GameState.load_game()

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS
	e.glow_enabled = bool(GameState.settings["glow"])
	e.glow_intensity = 0.35
	e.glow_strength = 1.0
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.set_glow_level(0, 0.0)
	e.set_glow_level(1, 1.0)
	e.set_glow_level(2, 1.0)
	e.set_glow_level(3, 0.0)
	e.set_glow_level(4, 0.0)
	env.environment = e
	add_child(env)

	world = WorldScript.new()
	add_child(world)
	world.generate(GameState.world_seed)
	if loaded:
		world.apply_save(GameState.saved_map)
	world.tile_destroyed.connect(_on_tile_destroyed)

	mothership = MothershipScript.new()
	mothership.position = world.dock_pos(GameState.mother_sector)
	add_child(mothership)

	fx = FxScript.new()
	add_child(fx)
	world.fx = fx

	ship = ShipScript.new()
	ship.world = world
	ship.fx = fx
	ship.position = mothership.position
	add_child(ship)
	ship.died.connect(_on_ship_died)
	ship.abducted.connect(_on_abducted)
	ship.abduct_blocked.connect(func(r): hud.message(r, Color(1.0, 0.5, 0.3)))
	ship.rebuild_blocked.connect(func(r): hud.message(r, Color(1.0, 0.5, 0.3)))
	ship.drift_released.connect(func(charge): zoom_kick = 0.05 * charge)
	world.ship = ship
	enemies = EnemiesScript.new()
	enemies.world = world
	enemies.ship = ship
	enemies.fx = fx
	add_child(enemies)
	world.enemies = enemies
	mothership.enemies = enemies
	mothership.fx = fx
	enemies.mothership = mothership
	world.mothership_ref = mothership
	mothership.destroyed.connect(_on_mother_destroyed)
	mothership.rebuilt.connect(func(): hud.message("Drony odbudowały Statek Matkę — hangar znów otwarty.", Color(0.4, 1.0, 1.0)))
	fx.enemies = enemies
	fx.world = world
	miners = MinersScript.new()
	miners.world = world
	miners.ship = ship
	miners.mothership = mothership
	miners.fx = fx
	add_child(miners)
	wingmen = WingmenScript.new()
	wingmen.world = world
	wingmen.ship = ship
	wingmen.mothership = mothership
	wingmen.enemies = enemies
	wingmen.fx = fx
	add_child(wingmen)
	enemies.wingmen = wingmen
	enemies.miners = miners
	world.wingmen = wingmen
	world.miners = miners
	transit = TransitScript.new()
	transit.world = world
	transit.ship = ship
	transit.fx = fx
	add_child(transit)
	world.transit = transit
	enemies.transit = transit
	transit.delivered.connect(func(n): hud.message("Statek tranzytowy dostarczył %d jedn. do Statku Matki" % n, Color(1.0, 0.8, 0.3)))
	transit.lost.connect(func(): hud.message("Statek tranzytowy zestrzelony! Ładunek stracony.", Color(1.0, 0.55, 0.3)))
	wingmen.lost.connect(func(): hud.message("Myśliwiec Imperium zestrzelony!", Color(1.0, 0.55, 0.3)))
	miners.lost.connect(func(): hud.message("Statek wydobywczy zniszczony! Ładunek stracony.", Color(1.0, 0.55, 0.3)))
	escorts = EscortsScript.new()
	escorts.world = world
	escorts.ship = ship
	escorts.enemies = enemies
	escorts.fx = fx
	add_child(escorts)
	world.escorts = escorts
	escorts.lost.connect(func(): hud.message("Myśliwiec towarzyszący zestrzelony! Wróci po dokowaniu.", Color(1.0, 0.55, 0.3)))
	weapons = WeaponsScript.new()
	weapons.world = world
	weapons.enemies = enemies
	weapons.ship = ship
	weapons.fx = fx
	add_child(weapons)
	world.city_destroyed.connect(_on_city_destroyed)
	world.tile_rebuilt.connect(_on_tile_rebuilt)
	world.tile_imperial_spread.connect(_on_imperial_spread)
	world.missile_launched.connect(_on_missile_launched)
	world.metro_tile_destroyed.connect(_on_metro_tile_destroyed)
	world.landmark_tile_destroyed.connect(_on_landmark_tile_destroyed)
	GameState.research_done.connect(_on_research_done)
	GameState.quest_completed.connect(_on_quest_completed)
	enemies.fighter_destroyed.connect(_on_fighter_destroyed)
	next_fighter_at = randi_range(20, 30)
	fx.ship = ship

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	camera.position = ship.position
	camera.make_current()

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = HudScript.new()
	hud.ship = ship
	hud.world = world
	hud.mothership = mothership
	hud.weapons = weapons
	hud.wingmen = wingmen
	hud.transit = transit
	hud_layer.add_child(hud)

	var up_layer := CanvasLayer.new()
	up_layer.layer = 10
	add_child(up_layer)
	upgrade_screen = UpgradeScreenScript.new()
	up_layer.add_child(upgrade_screen)
	upgrade_screen.launch_requested.connect(launch)
	upgrade_screen.mother_move_requested.connect(move_mother)
	var tut_layer := CanvasLayer.new()
	tut_layer.layer = 20
	add_child(tut_layer)
	tutorial = TutorialScript.new()
	tutorial.ship = ship
	tutorial.enemies = enemies
	tut_layer.add_child(tutorial)
	var pause_layer := CanvasLayer.new()
	pause_layer.layer = 25
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_layer)
	pause_menu = PauseScript.new()
	pause_layer.add_child(pause_menu)
	pause_menu.quit_requested.connect(_quit_from_pause)
	pause_menu.return_requested.connect(_abort_expedition)
	var crt := CrtScript.new()
	add_child(crt)
	pause_menu.crt = crt
	pause_menu.env = e
	upgrade_screen.world = world
	if GameState.training:
		training_ctl = TrainingScript.new()
		training_ctl.main = self
		add_child(training_ctl)
		training_ctl.setup()

	if GameState.training:
		dock("Szkolenie: Roswell. Powodzenia, Kadecie.", true)
	else:
		dock("Witaj na pokładzie, Kapitanie." if not loaded else "Zapis wczytany. Witaj ponownie.", true)
	Audio.play_game_music()


func _process(delta: float) -> void:
	# zapętlone dźwięki narzędzi
	var active: bool = not ship.docked and not ship.dead
	Audio.set_loop("laser_loop", active and ship.firing)
	Audio.set_loop("abduct_loop", active and ship.abducting)
	Audio.set_loop("rebuild_loop", active and ship.rebuilding)
	var speed_frac: float = ship.vel.length() / maxf(1.0, GameState.stat("max_speed"))
	Audio.set_engine(active, ship.thrust_level, speed_frac)
	_update_camera(speed_frac, delta)

	mothership.highlight = not ship.docked and not ship.dead and ship.position.distance_to(mothership.position) < mothership.DOCK_RADIUS

	if GameState.cargo_free() > 0:
		full_warned = false

	if not ship.docked and not ship.dead:
		var mf := GameState.stat("max_fuel")
		if ship.fuel < mf * 0.25 and not fuel_low_warned:
			fuel_low_warned = true
			hud.message("Niski poziom paliwa — pora wracać!", Color(1.00, 0.60, 0.20))
		if ship.fuel <= 0.0 and not fuel_empty_warned:
			fuel_empty_warned = true
			hud.show_big("BRAK PALIWA!", "Reaktor wybuchnie za %d s" % int(ship.EMPTY_FUSE))
			Audio.play("warning", 0.0)

	_update_patrols(delta)
	_update_siege(delta)
	barrier_msg_cd -= delta
	var probe: Vector2 = ship.position + ship.vel.limit_length(1.0) * 200.0
	if active and barrier_msg_cd <= 0.0 and world.barrier_push(probe) != Vector2.ZERO:
		barrier_msg_cd = 5.0
		var p: Vector2i = GameState.metros_progress()
		hud.message("DYSTRYKT FEDERALNY ZAMKNIĘTY — zniszcz wszystkie metropolie (%d/%d)" % [p.x, p.y], Color(1.0, 0.3, 0.3))
	hangar_warn_cd -= delta
	missile_msg_cd -= delta
	if fighter_return_timer > 0.0 and not ship.docked:
		fighter_return_timer -= delta
		if fighter_return_timer <= 0.0 and pending_fighters > 0:
			enemies.spawn_near(ship.global_position, pending_fighters)
			Audio.play("alarm", 0.0)
			hud.message("Myśliwce czekały na Ciebie! (%d)" % pending_fighters, Color(1.0, 0.35, 0.3))
			pending_fighters = 0
	if not ship.docked and not ship.dead and hangar_warn_cd <= 0.0 \
			and ship.position.distance_to(mothership.position) < mothership.DOCK_RADIUS \
			and enemies.any_within(ship.position, HANGAR_LOCK_RADIUS):
		hangar_warn_cd = 3.0
		hud.message("HANGAR ZAMKNIĘTY — myśliwce w pobliżu!", Color(1.0, 0.3, 0.3))

	if respawn_timer > 0.0:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			respawn_timer = -1.0
			dock("Statek zniszczony! Ładunek utracony. Drony odholowały wrak.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if GameState.key_hit(event, "dock"):
			if ship.docked:
				launch()
			elif not ship.dead and ship.position.distance_to(mothership.position) < mothership.DOCK_RADIUS:
				if training_ctl != null and not training_ctl.can_dock():
					hud.message("HANGAR ZABLOKOWANY — nie ma odwrotu!", Color(1.0, 0.3, 0.3))
				elif mothership.wrecked:
					hud.message("STATEK MATKA W GRUZACH — odbudowa za %ds" % int(ceil(mothership.wreck_t)), Color(1.0, 0.3, 0.3))
				elif enemies.any_within(ship.position, HANGAR_LOCK_RADIUS):
					hud.message("HANGAR ZAMKNIĘTY — zgub lub zestrzel myśliwce!", Color(1.0, 0.3, 0.3))
				else:
					dock("Powrót z wyprawy zakończony sukcesem.", false, true)
			elif not ship.dead and world.boss_portal_at(ship.position) >= 0:
				# wejście do walki tylko na życzenie gracza
				start_boss(world.boss_portal_at(ship.position))
		elif GameState.key_hit(event, "tool1"):
			ship.tool = 1
			hud.message(GameState.keys_text("[{tool1}] Laser górniczy"), Color(1.0, 0.5, 0.85))
		elif GameState.key_hit(event, "tool2"):
			if GameState.stat("lab") > 0.0:
				ship.tool = 2
				hud.message(GameState.keys_text("[{tool2}] Promień porywania: miasta = ludzie, pola = krowy, lasy = jelenie"), Color(0.5, 1.0, 0.6))
			else:
				hud.message("Promień porywania wymaga Laboratorium (drzewko ulepszeń).", Color(0.7, 0.7, 0.75))
		elif GameState.key_hit(event, "tool3"):
			if GameState.stat("rebuild") > 0.0:
				ship.tool = 3
				hud.message(GameState.keys_text("[{tool3}] Odbudowa: celuj w zniszczone miasta"), Color(1.0, 0.78, 0.3))
			else:
				hud.message("Odbudowa wymaga ulepszenia w drzewku (gałąź od Kieszeni).", Color(0.7, 0.7, 0.75))
		elif GameState.key_hit(event, "wing") and not ship.docked and not ship.dead:
			var msg: String = wingmen.toggle()
			if msg == "":
				hud.message("Myśliwce Imperium kupisz w zakładce Imperium na Statku Matce.", Color(0.7, 0.7, 0.75))
			else:
				hud.message(msg, Color(1.0, 0.8, 0.35))
				Audio.play("launch", 0.05, -6.0)
		elif GameState.key_hit(event, "rocket") and not ship.docked and not ship.dead:
			var rmsg: String = weapons.fire_rocket()
			if rmsg != "":
				hud.message(rmsg, Color(1.0, 0.6, 0.3))
		elif GameState.key_hit(event, "pause"):
			pause_menu.open(not ship.docked and not ship.dead)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not ship.docked:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_target = clampf(zoom_target * 1.12, 0.35, 2.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_target = clampf(zoom_target / 1.12, 0.35, 2.2)


## Kamera wyprzedza lot i zerka w stronę kursora, a przy dużej prędkości lekko się oddala.
func _update_camera(speed_frac: float, delta: float) -> void:
	if ship.docked:
		camera.position = mothership.position
	else:
		var vs := get_viewport_rect().size
		var look: Vector2 = (get_viewport().get_mouse_position() - vs * 0.5) / camera.zoom.x * 0.14
		camera.position = ship.position + ship.vel * 0.22 + look.limit_length(130.0)
	camera.offset = fx.shake_offset()
	zoom_speed = lerpf(zoom_speed, 1.0 - 0.13 * clampf(speed_frac, 0.0, 1.3), 1.0 - exp(-2.5 * delta))
	zoom_kick = lerpf(zoom_kick, 0.0, 1.0 - exp(-7.0 * delta))
	var want := zoom_target * zoom_speed * (1.0 - zoom_kick)
	var z := lerpf(camera.zoom.x, want, 1.0 - exp(-8.0 * delta))
	camera.zoom = Vector2(z, z)


## Mapa i wszystko, co po niej lata, jest niewidoczne pod ekranem Statku Matki.
func _show_world(on: bool) -> void:
	# fragmentów mapy nie chowamy: odsłonięcie kazałoby przerysować je wszystkie naraz przy wylocie
	for n in [world.overlay, world.scan_layer, mothership, ship, enemies, weapons, fx, miners, wingmen, transit, escorts]:
		n.visible = on


## Wyjście z pauzy do menu: w locie ładunek przepada, mapa i magazyn zostają zapisane.
func _quit_from_pause() -> void:
	if boss_layer != null:
		boss_layer.queue_free()
		boss_layer = null
		GameState.in_boss = false
	if not ship.docked:
		GameState.lose_cargo()
	go_to_menu()


## Przerwanie wyprawy z pauzy: statek wraca na Statek Matkę bez ładunku (surowce z wyprawy przepadają).
func _abort_expedition() -> void:
	if boss_layer != null:
		boss_layer.queue_free()
		boss_layer = null
		GameState.in_boss = false
		Audio.play_game_music()
	if ship.docked:
		return
	if training_ctl != null and not training_ctl.can_dock():
		hud.message("Nie ma odwrotu — walcz!", Color(1.0, 0.3, 0.3))
		return
	GameState.lose_cargo()
	dock("Wyprawa przerwana. Ładunek z wyprawy przepadł.")


## Powrót do menu głównego (tylko z doku - zapis jest wtedy aktualny).
func go_to_menu() -> void:
	Audio.stop_loops()
	Audio.play("ui_click", 0.0)
	GameState.save_game(world.export_save())
	get_tree().change_scene_to_file("res://menu.tscn")


func dock(status: String, silent := false, returned := false) -> void:
	if not silent:
		Audio.play("dock", 0.0)
	Audio.stop_loops()
	ship.docked = true
	ship.dead = false
	ship.vel = Vector2.ZERO
	ship.position = mothership.position
	world.bullets.clear()
	world.missiles.clear()
	mothership.siege = false
	mothership.repair()
	# myśliwce nie odpuszczają - wrócą przy następnym wylocie
	# patrole nie gonią do hangaru; wracają tylko te, które już polowały
	pending_fighters = mini(pending_fighters + enemies.hostile_count(), 6)
	enemies.clear_all()
	weapons.reset()
	wingmen.reset()
	escorts.reset()
	miners.revive()
	transit.reset()
	var unloaded := GameState.unload_cargo()
	if returned:
		GameState.quest_event("dock")
	GameState.save_game(world.export_save())
	hud.get_parent().visible = false
	_show_world(false)
	upgrade_screen.open(unloaded, status)


func launch() -> void:
	if not ship.docked:
		return
	upgrade_screen.visible = false
	hud.get_parent().visible = true
	_show_world(true)
	GameState.sorties += 1
	if not GameState.training:
		Achievements.unlock("first_launch")
	ship.reset_for_launch()
	if (ship.tool == 2 and GameState.stat("lab") <= 0.0) or (ship.tool == 3 and GameState.stat("rebuild") <= 0.0):
		ship.tool = 1
	fuel_low_warned = false
	fuel_empty_warned = false
	ship.docked = false
	ship.rotation = -PI * 0.5
	ship.position = mothership.position + Vector2(0, -60)
	ship.vel = Vector2(0, -260)
	weapons.reset()
	if pending_fighters > 0:
		fighter_return_timer = 6.0
	fx.ring(ship.position, Color(0.10, 0.80, 1.00), 90.0, 0.5)
	Audio.play("launch", 0.0)
	hud.message("Wyprawa nr %d — powodzenia, Kapitanie!" % GameState.sorties, Color(0.14, 0.86, 1.00))


## Sterownia: przeniesienie Statku Matki do innego sektora (działa tylko w doku).
func move_mother(to: int) -> void:
	if not ship.docked or not GameState.pay_move(to):
		Audio.play("error", 0.0)
		return
	mothership.position = world.dock_pos(to)
	ship.position = mothership.position
	camera.position = mothership.position
	camera.reset_smoothing()
	pending_fighters = 0
	GameState.save_game(world.export_save())
	Audio.play("launch", 0.0)
	var info: Dictionary = Sectors.LIST[to]
	upgrade_screen.status_text = "Statek Matka przeniesiony: %s (%s)." % [info["name"], Sectors.label(to)]


func _on_tile_destroyed(_idx: int, pos: Vector2, drops: Dictionary, info: String) -> void:
	fx.explosion(pos, Color(0.90, 0.40, 0.80))
	Audio.play("tile_break", 0.15)
	# Szperacz: szansa na dodatkowy rzadszy surowiec
	if randf() < GameState.stat("salvage"):
		var roll := randf()
		var bonus := "copper" if roll < 0.45 else ("iron" if roll < 0.8 else ("electronics" if roll < 0.95 else "gold"))
		drops[bonus] = int(drops.get(bonus, 0)) + 1
	ship.siphon(GameState.stat("fuel_siphon"), GameState.stat("hull_siphon"))
	for res in drops:
		var got := GameState.add_cargo(res, int(drops[res]))
		var c: Color = GameState.RES_COLORS[res]
		if got > 0:
			fx.pickup(pos, c, got)
		if got < int(drops[res]) and not full_warned:
			full_warned = true
			Audio.play("warning", 0.0)
			hud.message("ŁADOWNIA PEŁNA — wracaj do statku matki!", Color(1.00, 0.17, 0.13))
	if info != "":
		hud.message(info, Color(1.00, 0.80, 0.30))


func _on_city_destroyed(_pos: Vector2) -> void:
	if GameState.training:
		return
	cities_since_fighter += 1
	if cities_since_fighter >= next_fighter_at:
		cities_since_fighter = 0
		_spawn_wave()


## Patrole: co jakiś czas poza ekranem pojawia się samotny myśliwiec albo grupa, najczęściej przy miastach.
func _update_patrols(delta: float) -> void:
	if GameState.training:
		return
	if ship.docked or ship.dead or GameState.sorties < 2:
		return
	patrol_timer -= delta
	if patrol_timer > 0.0:
		return
	var c: int = GameState.cities_destroyed
	# im dalej w grze, tym gęściej na niebie
	patrol_timer = randf_range(9.0, 20.0) * clampf(1.0 - c / 1500.0, 0.6, 1.0)
	if enemies.alive_count() >= MAX_ENEMIES:
		return
	# czołgi: wyjeżdżają z miast poza ekranem i krążą między nimi
	if GameState.sorties >= 3 and enemies.tank_count() < mini(2 + c / 150, 6) and randf() < 0.35:
		for attempt in 24:
			var tp: Vector2 = ship.position + Vector2.from_angle(randf() * TAU) * randf_range(1300.0, 2300.0)
			if not world.ground_at(tp) or tp.distance_to(mothership.position) < 1500.0:
				continue
			if attempt < 18 and not world._is_city(world.pos_to_idx(tp)):
				continue
			var tn := 1 if randf() < 0.5 else randi_range(2, 3)
			enemies.spawn_tanks(tp, mini(tn, MAX_ENEMIES - enemies.alive_count()))
			return
	# łowcy: grupa, która od razu wie, gdzie jest gracz
	if GameState.sorties >= 5 and enemies.hostile_count() == 0 and randf() < 0.15:
		var hn := mini(1 + c / 120, 4)
		enemies.spawn_hunters(ship.global_position, hn, "gunner" if c > 80 and randf() < 0.4 else "fighter")
		Audio.play("alarm", 0.0)
		hud.message("ŁOWCY NA TWOIM TROPIE! (%d)" % hn, Color(1.0, 0.35, 0.3))
		return
	if enemies.patrol_count() >= MAX_PATROLS:
		return
	var lim := Vector2(world.N * world.T, world.H * world.T)
	for attempt in 16:
		var p: Vector2 = ship.position + Vector2.from_angle(randf() * TAU) * randf_range(1500.0, 2600.0)
		if p.x < 0.0 or p.y < 0.0 or p.x > lim.x or p.y > lim.y or p.distance_to(mothership.position) < 1500.0 or world.blocked_at(p):
			continue
		p = world.patrol_point(p)
		var roll := randf()
		var size := 1 if roll < 0.35 else (randi_range(2, 3) if roll < 0.8 else randi_range(4, 5))
		size = mini(size, MAX_ENEMIES - enemies.alive_count())
		var kind := "fighter"
		var kr := randf()
		if c > 80 and kr < 0.15:
			kind = "laser"
		elif c > 15 and kr < 0.45:
			kind = "gunner"
		enemies.spawn_patrol(p, size, kind)
		return


## Fala myśliwców rośnie z liczbą zniszczonych miast; po 60 kafelkach dołączają myśliwce laserowe.
func _spawn_wave() -> void:
	var c: int = GameState.cities_destroyed
	next_fighter_at = randi_range(maxi(7, 14 - c / 60), maxi(11, 22 - c / 40))
	var room: int = MAX_ENEMIES - enemies.alive_count()
	if room <= 0:
		return
	var lasers: int = 0 if c < 50 else mini(1 + (c - 50) / 100, 3)
	lasers = mini(lasers, room)
	var gunners: int = 0 if c < 15 else mini(mini(1 + (c - 15) / 55, 5), room - lasers)
	var n: int = mini(mini(2 + c / 30 + GameState.sorties / 20, 8), room - lasers - gunners)
	enemies.spawn_near(ship.global_position, n)
	enemies.spawn_near(ship.global_position, gunners, "gunner")
	enemies.spawn_near(ship.global_position, lasers, "laser")
	Audio.play("alarm", 0.0)
	if lasers > 0:
		hud.message("UWAGA: MYŚLIWCE LASEROWE! Uciekaj z linii celownika!", Color(1.00, 0.25, 0.25))
	elif n == 1:
		hud.message("UWAGA: ziemski myśliwiec nadlatuje!", Color(1.00, 0.35, 0.30))
	else:
		hud.message("UWAGA: eskadra ziemskich myśliwców! (%d)" % (n + gunners), Color(1.00, 0.35, 0.30))


# ---------------- Oblężenie Statku Matki ----------------

func _update_siege(delta: float) -> void:
	if GameState.training:
		return   # w szkoleniu atak na Matkę uruchamia scenariusz
	if ship.docked or ship.dead or GameState.in_boss or mothership.wrecked:
		return
	if mothership.siege:
		# atak trwa, dopóki żyje choć jeden myśliwiec oblężenia
		for f in enemies.fighters:
			if f.get("siege", false) and not f.get("dead", false):
				return
		mothership.siege = false
		hud.show_big("ATAK ODPARTY", "Statek Matka ocalał")
		Audio.play("research_done", 0.0)
		return
	if not GameState.metros_done.has(str(Sectors.START)):
		return
	siege_timer -= delta
	if siege_timer <= 0.0:
		siege_timer = randf_range(SIEGE_MIN, SIEGE_MAX)
		start_siege()


## Fala Ziemian leci prosto na Statek Matkę. Rośnie z liczbą zniszczonych miast.
func start_siege() -> void:
	var c: int = GameState.cities_destroyed
	var n := mini(4 + c / 3000, 8)
	var gunners := mini(1 + c / 6000, 3)
	var mp: Vector2 = mothership.global_position
	var start: int = enemies.fighters.size()
	enemies.spawn_near(mp, n)
	enemies.spawn_near(mp, gunners, "gunner")
	for k in range(start, enemies.fighters.size()):
		var f: Dictionary = enemies.fighters[k]
		f["siege"] = true
		f["hp"] *= 1.6
		f["max_hp"] = f["hp"]
	mothership.siege = true
	Audio.play("alarm", 0.0)
	Audio.play("boss_enter", 0.0, -4.0)
	hud.show_big("ZIEMIA KONTRATAKUJE!", "Statek Matka pod ostrzałem — leć jej bronić!")


## Statek Matka zniszczony: część zapasów z magazynu przepada, wrak czeka na odbudowę.
func _on_mother_destroyed() -> void:
	var lost := 0
	for k in GameState.bank.keys():
		if k in ["glory", "loyalty", "power"]:
			continue
		var n := int(floor(int(GameState.bank[k]) * SIEGE_LOSS))
		if n > 0:
			GameState.bank[k] = int(GameState.bank[k]) - n
			lost += n
	GameState.bank_changed.emit()
	for f in enemies.fighters:
		f["siege"] = false
	hud.show_big("STATEK MATKA ZNISZCZONY", "Przepadło %d%% zapasów z magazynu (%d szt.). Odbudowa za %ds" % [int(SIEGE_LOSS * 100), lost, int(mothership.WRECK_TIME)])
	Audio.play("warning", 0.0)


# ---------------- Metropolie i boss ----------------

func _on_metro_tile_destroyed(s: int) -> void:
	var frac: float = world.metro_destroyed_fraction(s)
	var key := str(s)
	if frac >= 1.0 and not GameState.metros_done.has(key):
		GameState.metros_done[key] = true
		if s == Sectors.START:
			Achievements.unlock("new_york")
		GameState.refresh_quests()
		GameState.add_glory(1)
		hud.show_big(String(Sectors.LIST[s]["destroyed"]), "+1 PUNKT CHWAŁY IMPERIUM")
		fx.shake(14.0)
		Audio.play("explosion_big", 0.0, 3.0)
		Audio.play("research_done", 0.0)
		if GameState.federal_unlocked():
			hud.message("POLE SIŁOWE OPADŁO — DYSTRYKT FEDERALNY OTWARTY (wschód, pod Nowym Jorkiem)", Color(1.0, 0.8, 0.3))
	if frac >= BOSS_TRIGGER and Sectors.LIST[s].get("boss", false) and GameState.boss_state(s) == "":
		GameState.boss_states[key] = "pending"
		if not ship.docked and not ship.dead:
			start_boss.call_deferred(s)


## Waszyngton i Pentagon: zniszczenie w 100% daje Punkt Chwały. Specjalny boss podepnie się tutaj,
## gdy obiekt w Sectors.LANDMARKS dostanie "boss" (próg jak przy metropoliach).
func _on_landmark_tile_destroyed(k: int) -> void:
	var lm: Dictionary = Sectors.LANDMARKS[k]
	var id: String = lm["id"]
	var frac: float = world.landmark_destroyed_fraction(k)
	if frac >= 1.0 and not GameState.metros_done.has(id):
		GameState.metros_done[id] = true
		GameState.add_glory(1)
		hud.show_big(String(lm["destroyed"]), "+1 PUNKT CHWAŁY IMPERIUM")
		fx.shake(14.0)
		Audio.play("explosion_big", 0.0, 3.0)
		Audio.play("research_done", 0.0)
		GameState.refresh_quests()
	if frac >= BOSS_TRIGGER and String(lm.get("boss", "")) != "" and GameState.boss_states.get(id, "") == "":
		GameState.boss_states[id] = "pending"


## Minigra działa na wierzchu, a cały świat stoi w pauzie.
func start_boss(s: int) -> void:
	if boss_layer != null or ship.docked or ship.dead:
		return
	boss_sector = s
	Audio.stop_loops()
	GameState.in_boss = true
	get_tree().paused = true
	boss_layer = CanvasLayer.new()
	boss_layer.layer = 15
	boss_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(boss_layer)
	var game = BossGameScript.new()
	game.setup(s)
	game.finished.connect(_on_boss_finished)
	boss_layer.add_child(game)


func _on_boss_finished(won: bool) -> void:
	boss_layer.queue_free()
	boss_layer = null
	GameState.in_boss = false
	get_tree().paused = false
	Audio.play_game_music()
	if won:
		# nagroda tylko za pierwsze zwycięstwo, kolejne walki są dla przyjemności
		if GameState.boss_state(boss_sector) != "beaten":
			GameState.boss_states[str(boss_sector)] = "beaten"
			GameState.add_glory(1)
			hud.message("Strażniczka pokonana! +1 Punkt Chwały Imperium", Color(1.0, 0.45, 0.9))
		else:
			hud.message("Strażniczka znów pokonana!", Color(1.0, 0.45, 0.9))
		GameState.save_game(world.export_save())
	else:
		# jak przy zwykłym zniszczeniu: wrak wraca do Matki, ładunek przepada
		GameState.lose_cargo()
		dock("Statek zniszczony w walce o %s. Wróć przez różowy punkt w mieście." % GameState.city_name(boss_sector))


func _on_missile_launched() -> void:
	if missile_msg_cd <= 0.0:
		missile_msg_cd = 5.0
		hud.message("RAKIETA NAMIERZA STATEK! Zestrzel ją laserem lub uciekaj!", Color(1.0, 0.2, 0.2))


func _on_abducted(kind: String, amount: int, pos: Vector2) -> void:
	fx.ring(pos, Color(0.4, 1.0, 0.5, 0.8), 30.0, 0.4)
	if amount > 0:
		Audio.play("abduct_done", 0.05)
		fx.float_text(pos, "+%d %s" % [amount, GameState.RES_NAMES[kind]], GameState.RES_COLORS[kind])


func _on_tile_rebuilt(idx: int) -> void:
	var p: Vector2 = world.idx_center(idx)
	fx.ring(p, Color(1.0, 0.78, 0.3, 0.9), 34.0, 0.4)
	fx.sparks(p, Color(1.0, 0.8, 0.35), 10, 120.0)
	fx.float_text(p, "Kafelek Imperium", Color(1.0, 0.78, 0.3))
	Audio.play("imperial", 0.1)


func _on_imperial_spread(idx: int) -> void:
	var p: Vector2 = world.idx_center(idx)
	fx.ring(p, Color(1.0, 0.78, 0.3, 0.7), 26.0, 0.35)
	fx.sparks(p, Color(1.0, 0.8, 0.35), 5, 80.0)
	if not ship.docked:
		Audio.play("imperial", 0.15, -12.0)


## Wykonany rozkaz: w doku plakietka na ekranie Statku Matki, w locie komunikat. Nagrodę odbiera się w Rozkazach.
func _on_quest_completed(q: Dictionary) -> void:
	Audio.play("research_done", 0.0)
	if q.has("new_name") and not ship.docked:
		# odbudowana metropolia dostaje nową nazwę na mapie
		hud.show_big(String(q["new_name"]), "%s ODBUDOWANY PRZEZ IMPERIUM" % String(Sectors.LIST[int(q["sector"])]["city"]))
	if ship.docked:
		upgrade_screen.toast(String(q["title"]), int(q["reward"]))
	else:
		# nowszy komunikat wyświetla się wyżej, więc nazwa rozkazu idzie na końcu
		hud.message("Do odebrania na Statku Matce (+%d PL)" % int(q["reward"]), Color(0.45, 0.9, 1.0))
		hud.message("%s - Wykonano!" % q["title"], Color(1.0, 0.8, 0.3))


func _on_research_done(u: Dictionary) -> void:
	hud.message("Badanie zakończone: " + String(u["name"]), Color(0.5, 1.0, 0.6))
	Audio.play("research_done", 0.0)
	upgrade_screen.flash[u["id"]] = 0.6


func _on_fighter_destroyed(pos: Vector2, kind: String, looted: bool) -> void:
	Audio.play("explosion_big", 0.1)
	if not looted:
		# zestrzelony przez obronę Statku Matki: bez łupu
		hud.message("Statek Matka zestrzelił myśliwiec", Color(0.85, 0.55, 1.0))
		return
	var loot := {"weapon_scrap": randi_range(1, 2), "scrap": randi_range(3, 6), "metal": randi_range(2, 4), "electronics": randi_range(0, 1)}
	if kind == "tank":
		hud.message("Czołg zniszczony!", Color(1.00, 0.80, 0.30))
		loot = {"weapon_scrap": randi_range(1, 2), "scrap": randi_range(4, 8), "metal": randi_range(4, 7), "iron": randi_range(2, 4)}
		if fx:
			fx.shake(4.0)
	else:
		hud.message("Myśliwiec zestrzelony!", Color(1.00, 0.80, 0.30))
	if kind == "laser":
		loot["electronics"] += randi_range(1, 2)
		loot["weapon_scrap"] += 1
	for res in loot:
		var got := GameState.add_cargo(res, loot[res])
		if got > 0:
			fx.pickup(pos, GameState.RES_COLORS[res], got)


func _on_ship_died() -> void:
	fx.explosion(ship.position, Color(1.00, 0.27, 0.10), true)
	fx.explosion(ship.position, Color(1.00, 0.15, 0.92), true)
	Audio.stop_loops()
	Audio.play("explosion_big", 0.0, 2.0)
	GameState.lose_cargo()
	# po zestrzeleniu gracza myśliwce wracają do bazy
	enemies.clear_all()
	pending_fighters = 0
	hud.message("KADŁUB ZNISZCZONY", Color(1.00, 0.10, 0.10))
	# szkolenie: przegrana z bossem kończy scenariusz zamiast powrotu do doku
	if training_ctl != null and training_ctl.handle_death():
		return
	respawn_timer = 2.5
