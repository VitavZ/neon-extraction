extends "res://scripts/world/damage.gd"
## Mapa świata, część 4/5: sojusznicze wieżyczki i rakiety wieżyczek rakietowych.


## Wieżyczki Imperium strzelają w najbliższą rakietę albo myśliwiec w zasięgu.
func _process_allies(delta: float, active: bool) -> void:
	for sh in ally_shots:
		sh["life"] -= delta
	if not ally_shots.is_empty():
		ally_shots = ally_shots.filter(func(sh): return sh["life"] > 0.0)
	if not active or ally_turrets.is_empty() or enemies == null:
		return
	var rng := GameState.stat("ally_range")
	var sp: Vector2 = ship.global_position
	for i in ally_turrets:
		var p := idx_center(i)
		# wieżyczki daleko od akcji nie mają do kogo strzelać
		if p.distance_squared_to(sp) > 9000000.0:
			continue
		var at: Dictionary = ally_turrets[i]
		at["cd"] -= delta
		if at["cd"] > 0.0:
			continue
		var target := Vector2.INF
		var ms: Dictionary = nearest_missile(p, rng)
		var f: Dictionary = {} if not ms.is_empty() else enemies.nearest(p, rng)
		if not ms.is_empty():
			target = ms["pos"]
			damage_missile(ms, GameState.stat("ally_damage"))
		elif not f.is_empty():
			target = f["pos"]
			enemies.damage_fighter(f, GameState.stat("ally_damage"))
		if target == Vector2.INF:
			at["cd"] = 0.4
			continue
		at["cd"] = 0.9
		at["angle"] = (target - p).angle()
		ally_shots.append({"a": p, "b": target, "life": 0.14})
		Audio.play("gun_shot", 0.15, -8.0)


func _process_missile_turret(i: int, t: Dictionary, tp: Vector2, to: Vector2, active: bool, delta: float) -> void:
	if not active or to.length() > MISSILE_RANGE:
		return
	t["angle"] = lerp_angle(t["angle"], to.angle(), 4.0 * delta)
	t["cd"] -= delta
	if t["cd"] > 0.0 or missiles.size() >= MISSILE_MAX:
		return
	t["cd"] = randf_range(7.0, 10.0)
	missiles.append({"pos": tp, "rot": to.angle(), "speed": 140.0, "life": MISSILE_LIFE, "hp": MISSILE_HP,
		"dmg": 28.0 * (1.0 + danger(i % N, i / N) / 70.0)})
	Audio.play("rocket_launch", 0.05, 2.0)
	missile_launched.emit()


func _process_missiles(delta: float, active: bool) -> void:
	if missiles.is_empty():
		missile_beep = 0.0
		return
	if not active:
		for m in missiles:
			_explode_missile(m)
		missiles.clear()
		return
	var sp: Vector2 = ship.global_position
	var closest := INF
	for m in missiles:
		m["rot"] = rotate_toward(m["rot"], (sp - m["pos"]).angle(), MISSILE_TURN * delta)
		# rakieta nadąża też za ulepszonym statkiem: ucieczka udaje się tylko przy pełnej prędkości po prostej
		m["speed"] = minf(m["speed"] + MISSILE_ACCEL * delta, maxf(MISSILE_SPEED_MIN, GameState.stat("max_speed") * 0.97))
		m["pos"] += Vector2.from_angle(m["rot"]) * m["speed"] * delta
		m["life"] -= delta
		if fx and randf() < 0.5:
			fx.sparks(m["pos"] - Vector2.from_angle(m["rot"]) * 12.0, Color(1.0, 0.5, 0.2), 1, 40.0)
		var d: float = m["pos"].distance_to(sp)
		closest = minf(closest, d)
		if d < MISSILE_HIT:
			ship.take_damage(m["dmg"])
			if fx:
				fx.explosion(m["pos"], Color(1.2, 0.3, 0.15), true)
			Audio.play("explosion_big", 0.1)
			m["life"] = 0.0
		elif m["life"] <= 0.0:
			_explode_missile(m)
	missiles = missiles.filter(func(m): return m["life"] > 0.0)
	# sygnał: im bliżej rakieta, tym szybciej pika
	missile_beep -= delta
	if missile_beep <= 0.0 and not missiles.is_empty():
		missile_beep = lerpf(0.13, 0.6, clampf(closest / 900.0, 0.0, 1.0))
		Audio.play("missile_warning", 0.0)


func _explode_missile(m: Dictionary) -> void:
	m["life"] = 0.0
	if fx:
		fx.explosion(m["pos"], Color(1.0, 0.45, 0.2))
	Audio.play("explosion", 0.12)


## Zestrzelić rakietę mogą tylko laser i drony.
func damage_missile(m: Dictionary, amount: float) -> void:
	if m["life"] <= 0.0:
		return
	m["hp"] -= amount
	if m["hp"] <= 0.0:
		_explode_missile(m)


## Wiązka od a do b: trafia pierwszą rakietę na swojej drodze. Zwraca punkt trafienia lub Vector2.INF.
func missile_laser_hit(a: Vector2, b: Vector2, amount: float) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	var hit: Dictionary = {}
	for m in missiles:
		if m["life"] <= 0.0:
			continue
		var cp := Geometry2D.get_closest_point_to_segment(m["pos"], a, b)
		if cp.distance_to(m["pos"]) < MISSILE_LASER_RADIUS and a.distance_to(cp) < bd:
			bd = a.distance_to(cp)
			best = cp
			hit = m
	if not hit.is_empty():
		damage_missile(hit, amount)
	return best
