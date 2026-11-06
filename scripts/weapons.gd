extends Node2D
## Bronie automatyczne statku (odblokowywane w Zbrojowni):
## - Rakiety: gracz odpala je klawiszem w stronę kursora; ładują się co X sekund (najwyżej ROCKET_MAG w zapasie),
##   wybuchają obszarowo (okrąg o promieniu N kafelków).
## - Drony: krążą wokół statku i strzelają; priorytet: myśliwce, potem pobliskie kafelki.
## - Karabiny: strzelają wyłącznie w wieżyczki obronne.
## - Łańcuch błyskawic (węzeł lasera): podczas strzału z celu lasera przeskakuje błyskawica.
## - Detonacja (węzeł lasera): kafelek rozbity laserem może po chwili wybuchnąć; kafelki rozbite
##   wybuchem też mogą wybuchnąć (reakcja łańcuchowa, szansa słabnie z każdym pokoleniem).

const CHAIN_FALLOFF := 0.85
const DET_FUSE := 0.4          # s od rozbicia do wybuchu
const DET_GEN_FALLOFF := 0.6   # szansa kolejnego pokolenia reakcji
const DET_MAX_GEN := 5
const DET_MAX_PENDING := 24
const DET_SOURCES := ["laser", "splash", "chain", "blast"]
const ROCKET_SPEED := 520.0
const ROCKET_RANGE := 650.0
const ROCKET_MAG := 3
const ROCKET_LOCK := 120.0      # myśliwiec tak blisko kursora staje się celem rakiety
const DRONE_ORBIT := 52.0
const DRONE_FIGHTER_RANGE := 380.0
const DRONE_TILE_RANGE := 230.0

var world: Node2D
var enemies: Node2D
var ship: Node2D
var fx: Node2D

var rocket_timer := 0.0
var rocket_ammo := 0
var rockets: Array = []     # {pos, vel, target, life}
var drone_timers: Array = []
var gun_timer := 0.0
var tracers: Array = []     # {a, b, life, max, color, w}
var chain_timer := 0.0
var arcs: Array = []        # {pts, life, max} - widoczne przeskoki błyskawicy
var dets: Array = []        # {pos, t, gen} - kafelki tuż przed wybuchem
var _blast_gen := -1        # pokolenie trwającego wybuchu (dla kafelków rozbitych przez niego)
var time := 0.0


func _ready() -> void:
	z_index = 7
	if world:
		world.tile_broken.connect(_on_tile_broken)


func reset() -> void:
	rocket_timer = rocket_cooldown()
	rocket_ammo = ROCKET_MAG
	rockets.clear()
	tracers.clear()
	drone_timers.clear()
	gun_timer = 0.0
	chain_timer = 0.0
	arcs.clear()
	dets.clear()


func rocket_cooldown() -> float:
	return maxf(2.0, GameState.stat("rocket_cooldown"))


func drone_count() -> int:
	return int(GameState.stat("drone_count"))


func _drone_pos(k: int) -> Vector2:
	var n := maxi(1, drone_count())
	var a := time * 1.6 + float(k) / n * TAU
	return ship.global_position + Vector2(cos(a), sin(a)) * DRONE_ORBIT


func _process(delta: float) -> void:
	time += delta
	for t in tracers:
		t["life"] -= delta
	tracers = tracers.filter(func(t): return t["life"] > 0.0)
	for arc in arcs:
		arc["life"] -= delta
	arcs = arcs.filter(func(arc): return arc["life"] > 0.0)

	if ship == null or ship.docked or ship.dead:
		rockets.clear()
		dets.clear()
		queue_redraw()
		return
	var sp: Vector2 = ship.global_position
	# w trakcie porywania bronie wstrzymują ogień (rakiety już w powietrzu dolatują)
	var hold_fire: bool = ship.abducting

	# ---------- RAKIETY ----------
	if GameState.stat("rocket_unlocked") > 0.0 and rocket_ammo < ROCKET_MAG:
		rocket_timer -= delta
		if rocket_timer <= 0.0:
			rocket_timer = rocket_cooldown()
			rocket_ammo += 1
			if rocket_ammo == 1:
				Audio.play("ui_click", 0.05, -8.0)
	for r in rockets:
		var to: Vector2 = r["target"] - r["pos"]
		var step: float = ROCKET_SPEED * delta
		r["life"] -= delta
		if to.length() <= step or r["life"] <= 0.0:
			_explode(r["target"])
			r["done"] = true
		else:
			r["vel"] = r["vel"].lerp(to.normalized() * ROCKET_SPEED, 1.0 - exp(-6.0 * delta))
			r["pos"] += r["vel"] * delta
			if fx and randf() < 0.5:
				fx.sparks(r["pos"], Color(1.0, 0.6, 0.2), 1, 40.0)
	rockets = rockets.filter(func(r): return not r.get("done", false))

	# ---------- DRONY ----------
	var dc := drone_count()
	while drone_timers.size() < dc:
		drone_timers.append(randf_range(0.2, 1.0))
	for k in dc:
		if hold_fire:
			continue
		drone_timers[k] -= delta
		if drone_timers[k] <= 0.0:
			drone_timers[k] = maxf(0.35, GameState.stat("drone_interval"))
			_drone_shoot(_drone_pos(k))

	# ---------- KARABINY ----------
	if GameState.stat("gun_unlocked") > 0.0 and not hold_fire:
		gun_timer -= delta
		if gun_timer <= 0.0:
			var ti := _nearest_turret(sp, GameState.stat("gun_range"))
			if ti >= 0:
				gun_timer = maxf(0.12, GameState.stat("gun_interval"))
				Audio.play("gun_shot", 0.15)
				var tp: Vector2 = world.idx_center(ti) + Vector2(randf_range(-6, 6), randf_range(-6, 6))
				tracers.append({"a": sp, "b": tp, "life": 0.08, "max": 0.08, "color": Color(1.0, 0.9, 0.5), "w": 1.5})
				world.damage_tile(ti, GameState.stat("gun_damage"), "gun")
				if fx and randf() < 0.5:
					fx.sparks(tp, Color(1.0, 0.85, 0.4), 2, 80.0)
			else:
				gun_timer = 0.2

	# ---------- DETONACJA ----------
	var dk := dets.size() - 1
	while dk >= 0:
		var dt: Dictionary = dets[dk]
		dt["t"] -= delta
		if dt["t"] <= 0.0:
			dets.remove_at(dk)
			_detonate(dt["pos"], dt["gen"])
		dk = mini(dk - 1, dets.size() - 1)

	# ---------- ŁAŃCUCH BŁYSKAWIC ----------
	if GameState.stat("chain_jumps") > 0.0:
		chain_timer -= delta
		if chain_timer <= 0.0 and ship.firing and ship.beam_hit:
			chain_timer = maxf(0.3, GameState.stat("chain_interval"))
			_chain_pulse(ship.beam_target)
	if visible:
		queue_redraw()


## Błyskawica: przeskakuje z punktu trafienia po celach, każdy cel najwyżej raz, a moc słabnie co przeskok.
func _chain_pulse(start: Vector2) -> void:
	var dmg := GameState.stat("laser_dps") * GameState.stat("chain_power")
	var from := start
	var hit_tiles := {world.pos_to_idx(start): true}
	var hit_fighters: Array = []
	var beam_fighter: Dictionary = enemies.nearest(start, enemies.HIT_RADIUS + 2.0) if enemies else {}
	if not beam_fighter.is_empty():
		hit_fighters.append(beam_fighter)
	for jump in int(GameState.stat("chain_jumps")):
		var to := _chain_step(from, dmg, hit_tiles, hit_fighters)
		if to == Vector2.INF:
			break
		arcs.append({"pts": _jagged(from, to), "life": 0.2, "max": 0.2})
		if fx:
			fx.sparks(to, Color(0.6, 0.9, 1.0), 3, 110.0)
		from = to
		dmg *= CHAIN_FALLOFF
	if arcs.size() > 0:
		Audio.play("drone_shot", 0.25)


## Zadaje obrażenia kolejnemu celowi (myśliwiec > wieżyczka > kafelek) i zwraca jego pozycję lub Vector2.INF.
func _chain_step(from: Vector2, dmg: float, hit_tiles: Dictionary, hit_fighters: Array) -> Vector2:
	var rng := GameState.stat("chain_range")
	if enemies:
		var best: Dictionary = {}
		var bd := rng
		for f in enemies.fighters:
			var d: float = f["pos"].distance_to(from)
			if d < bd and not f.get("dead", false) and not f in hit_fighters:
				bd = d
				best = f
		if not best.is_empty():
			hit_fighters.append(best)
			enemies.damage_fighter(best, dmg)
			return best["pos"]
	var turret := -1
	var far: Array = []
	var near: Array = []
	var ri := int(ceil(rng / world.T))
	var cx := int(floor(from.x / world.T))
	var cy := int(floor(from.y / world.T))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= world.N or y >= world.H:
				continue
			var i: int = y * world.N + x
			if hit_tiles.has(i) or not world.is_minable(i):
				continue
			var d: float = world.idx_center(i).distance_to(from)
			if d > rng:
				continue
			if world.turrets.has(i):
				turret = i
			# dalsze kafelki mają pierwszeństwo, żeby błyskawica nie dreptała po sąsiadach
			if d >= rng * 0.5:
				far.append(i)
			else:
				near.append(i)
	var target := turret
	if target < 0:
		var pool: Array = far if far.size() > 0 else near
		if pool.is_empty():
			return Vector2.INF
		target = pool[randi() % pool.size()]
	hit_tiles[target] = true
	world.damage_tile(target, dmg, "chain")
	return world.idx_center(target)


## Rozbity kafelek: rzut na detonację. Wybuch rozbijający kolejne kafelki daje im szansę na następne pokolenie.
func _on_tile_broken(i: int, src: String) -> void:
	var chance := GameState.stat("det_chance")
	if chance <= 0.0 or not src in DET_SOURCES or ship == null or ship.docked or ship.dead:
		return
	var gen := 0
	if src == "blast":
		gen = _blast_gen + 1
		if gen > DET_MAX_GEN:
			return
	if dets.size() >= DET_MAX_PENDING or randf() >= chance * pow(DET_GEN_FALLOFF, gen):
		return
	dets.append({"pos": world.idx_center(i), "t": DET_FUSE * randf_range(0.8, 1.2), "gen": gen, "max": DET_FUSE * 1.2})


func _detonate(p: Vector2, gen: int) -> void:
	var r_tiles := GameState.stat("det_radius")
	var r_px: float = r_tiles * world.T
	var dmg := GameState.stat("laser_dps") * GameState.stat("det_power")
	Audio.play("blast_pop", 0.15, -2.0)
	if fx:
		fx.ring(p, Color(1.4, 0.65, 0.2, 0.9), r_px, 0.35)
		fx.ring(p, Color(1.5, 1.2, 0.8, 0.7), r_px * 0.45, 0.22)
		fx.sparks(p, Color(1.3, 0.6, 0.25), 10, 200.0)
		if gen >= 2:
			fx.shake(2.0 + gen)
	if enemies:
		enemies.damage_in_radius(p, r_px, dmg)
	var prev := _blast_gen
	_blast_gen = gen
	var ri := int(ceil(r_tiles))
	var cx := int(floor(p.x / world.T))
	var cy := int(floor(p.y / world.T))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= world.N or y >= world.H:
				continue
			var i: int = y * world.N + x
			if world.idx_center(i).distance_to(p) <= r_px + 1.0:
				world.damage_tile(i, dmg, "blast")
	_blast_gen = prev


## Poszarpana linia błyskawicy od a do b.
func _jagged(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array([a])
	var n := (b - a).orthogonal().normalized()
	var segs := 4 + int(a.distance_to(b) / 40.0)
	for k in range(1, segs):
		pts.append(a.lerp(b, float(k) / segs) + n * randf_range(-11.0, 11.0))
	pts.append(b)
	return pts


## Odpalenie przez gracza. Zwraca komunikat, gdy się nie da ("" = poleciała).
func fire_rocket() -> String:
	if GameState.stat("rocket_unlocked") <= 0.0:
		return "Rakiety odblokujesz w Zbrojowni na Statku Matce."
	if ship == null or ship.docked or ship.dead:
		return ""
	if rocket_ammo <= 0:
		return "Rakieta się ładuje (%.1f s)" % rocket_timer
	rocket_ammo -= 1
	_fire_rocket(ship.global_position)
	return ""


func _fire_rocket(sp: Vector2) -> void:
	var m := get_global_mouse_position()
	var to := m - sp
	if to.length() > ROCKET_RANGE:
		to = to.normalized() * ROCKET_RANGE
	var target := sp + to
	# myśliwiec przy kursorze: rakieta leci w niego
	var f: Dictionary = enemies.nearest(m, ROCKET_LOCK) if enemies else {}
	if not f.is_empty() and f["pos"].distance_to(sp) <= ROCKET_RANGE * 1.2:
		target = f["pos"]
	var dir := Vector2.RIGHT.rotated(ship.rotation)
	Audio.play("rocket_launch", 0.1)
	rockets.append({"pos": sp + dir * 10.0, "vel": dir * 200.0 + ship.vel, "target": target, "life": 3.0})


func _explode(p: Vector2) -> void:
	var r_tiles := GameState.stat("rocket_radius")
	var r_px: float = r_tiles * world.T
	var dmg := GameState.stat("rocket_damage")
	Audio.play("explosion", 0.12)
	if fx:
		fx.ring(p, Color(1.0, 0.55, 0.2, 0.9), r_px, 0.45)
		fx.ring(p, Color(1.0, 0.9, 0.6, 0.6), r_px * 0.5, 0.3)
		fx.sparks(p, Color(1.0, 0.6, 0.25), 18, 260.0)
	if enemies:
		enemies.damage_in_radius(p, r_px, dmg)
	var ri := int(ceil(r_tiles))
	var cx := int(floor(p.x / world.T))
	var cy := int(floor(p.y / world.T))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= world.N or y >= world.H:
				continue
			var i: int = y * world.N + x
			if world.idx_center(i).distance_to(p) <= r_px:
				world.damage_tile(i, dmg, "rocket")


func _drone_shoot(dp: Vector2) -> void:
	var dmg := GameState.stat("drone_damage")
	Audio.play("drone_shot", 0.15)
	# rakiety wroga mają pierwszeństwo przed wszystkim innym
	var ms: Dictionary = world.nearest_missile(dp, DRONE_FIGHTER_RANGE)
	if not ms.is_empty():
		tracers.append({"a": dp, "b": ms["pos"], "life": 0.12, "max": 0.12, "color": Color(0.4, 1.0, 0.9), "w": 2.0})
		world.damage_missile(ms, dmg)
		return
	var f: Dictionary = enemies.nearest(dp, DRONE_FIGHTER_RANGE) if enemies else {}
	if not f.is_empty():
		tracers.append({"a": dp, "b": f["pos"], "life": 0.12, "max": 0.12, "color": Color(0.4, 1.0, 0.9), "w": 2.0})
		enemies.damage_fighter(f, dmg)
		return
	# losowy pobliski, nienaruszony kafelek
	for attempt in 8:
		var p := dp + Vector2.from_angle(randf() * TAU) * randf_range(40.0, DRONE_TILE_RANGE)
		var i: int = world.pos_to_idx(p)
		if world.is_minable(i):
			var tp: Vector2 = world.idx_center(i)
			tracers.append({"a": dp, "b": tp, "life": 0.12, "max": 0.12, "color": Color(0.4, 1.0, 0.9), "w": 1.5})
			world.damage_tile(i, dmg, "drone")
			return


func _nearest_turret(p: Vector2, rng: float) -> int:
	var best := -1
	var bd := rng
	for i in world.turrets_in_rect(Rect2(p, Vector2.ZERO).grow(rng)):
		var d: float = world.idx_center(i).distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _draw() -> void:
	if ship == null or ship.dead or ship.docked:
		return
	# drony
	for k in drone_count():
		var dp := _drone_pos(k)
		var tri := PackedVector2Array()
		for j in 4:
			var a := time * 4.0 + j / 3.0 * TAU
			tri.append(dp + Vector2(cos(a), sin(a)) * 6.0)
		draw_colored_polygon(tri, Color(0.05, 0.2, 0.2, 0.9))
		draw_polyline(tri, Color(0.4, 1.0, 0.9), 1.5, true)
	# rakiety
	for r in rockets:
		var p: Vector2 = r["pos"]
		var v: Vector2 = r["vel"].normalized()
		draw_line(p - v * 26.0, p, Color(1.0, 0.55, 0.2, 0.35), 5.0, true)
		draw_line(p - v * 18.0, p + v * 6.0, Color(1.0, 0.95, 0.85), 2.0, true)
		draw_circle(p, 3.0, Color(1.0, 1.0, 1.0))
		draw_circle(p - v * 10.0, 3.0, Color(1.2, 0.6, 0.2))
		# znacznik celu
		draw_arc(r["target"], 10.0, 0.0, TAU, 16, Color(1.0, 0.5, 0.2, 0.6), 1.5, true)
	# kafelki tuż przed detonacją: pulsujący, rosnący żar
	for dt in dets:
		var q: float = 1.0 - clampf(dt["t"] / dt["max"], 0.0, 1.0)
		var fl := 0.6 + 0.4 * sin(time * 40.0)
		draw_circle(dt["pos"], 6.0 + q * 12.0, Color(1.4, 0.55, 0.15, (0.25 + 0.35 * q) * fl))
		draw_circle(dt["pos"], 3.0 + q * 5.0, Color(1.5, 1.2, 0.8, 0.6 + 0.4 * q))
	# błyskawice
	for arc in arcs:
		var f: float = arc["life"] / arc["max"]
		draw_polyline(arc["pts"], Color(0.3, 0.75, 1.3, f * 0.45), 5.0, true)
		draw_polyline(arc["pts"], Color(1.1, 1.25, 1.4, f), 1.6, true)
	# smugi pocisków dronów i karabinów
	for t in tracers:
		var f: float = t["life"] / t["max"]
		var c: Color = t["color"]
		draw_line(t["a"], t["b"], Color(c.r, c.g, c.b, f * 0.6), t["w"] + 2.5, true)
		draw_line(t["a"].lerp(t["b"], 0.35), t["b"], Color(1.0, 1.0, 1.0, f), t["w"] * 0.7, true)
