extends Node2D
## Statek zwiadowczo-wydobywczy. Sterowanie w stylu Nova Drift:
## statek obraca się w stronę kursora, ciąg nadaje pęd, który się utrzymuje (dryf).

signal died
signal abducted(kind: String, amount: int, pos: Vector2)
signal abduct_blocked(reason: String)
signal rebuild_blocked(reason: String)
signal drift_released(charge: float)

var vel := Vector2.ZERO
var hull := 100.0
var shield := 0.0
var since_hit := 10.0
var docked := true
var dead := false
var thrusting := false
var stopping := false           # wciśnięty pełny stop
var strafing := 0.0
var firing := false
var beam_target := Vector2.ZERO
var beam_hit := false
var beam_in_range := true
var splash_points: Array = []
var fuel := 60.0
var drifting := false
var drift_charge := 0.0
var drift_flash := 0.0
var fuel_warned := false
var tool := 1                 # 1 = laser górniczy, 2 = promień porywania, 3 = odbudowa
var rebuilding := false
var rebuild_idx := -1
var rebuild_progress := 0.0
var rebuild_valid := false
var abducting := false
var abduct_idx := -1
var abduct_progress := 0.0
var abduct_valid := false
var abduct_block_cd := 0.0
var abduct_lost_t := 0.0     # jak długo kursor jest poza namierzonym celem
var hit_flash := 0.0
var ang_vel := 0.0           # prędkość obrotu: dzięki niej statek zaczyna i kończy skręt płynnie
var thrust_level := 0.0      # silnik rozpędza się i gaśnie, zamiast działać zero-jedynkowo
var boost_t := 0.0           # świeży zryw z driftu (pęd dłużej zostaje ponad limitem)
var charge_pinged := false
var exhaust_t := 0.0
var trail_last := Vector2.INF
var world: Node2D
var fx: Node2D
var trail: Line2D
var time := 0.0

const EMPTY_DRAIN := 15.0        # ubytek kadłuba na sekundę bez paliwa
const TRAINING_BURN := 0.4       # szkolenie: paliwo schodzi wolniej
var empty_t := 0.0
const SIPHON_FUEL_PER_S := 1.0   # najwięcej paliwa na sekundę z Syfonu energetycznego
const SIPHON_HULL_PER_S := 10.0  # najwięcej kadłuba na sekundę z Rekonstrukcji z materii
var siphon_fuel_left := SIPHON_FUEL_PER_S
var siphon_hull_left := SIPHON_HULL_PER_S
const TURN_GAIN := 11.0      # im większe, tym ostrzej statek dochodzi do kąta kursora
const TURN_RESPONSE := 24.0   # jak szybko obrót nadąża za sterowaniem
const AIM_DEADZONE := 26.0    # kursor na samym statku nie kręci nim w kółko
const SPOOL_RATE := 14.0
const CARVE_RATE := 2.3       # z włączonym ciągiem pęd skręca za dziobem, nie tracąc prędkości
const CARVE_MAX_ANGLE := 2.0  # powyżej tego kąta to już hamowanie, a nie skręt
const REVERSE_ASSIST := 0.8   # dodatkowy ciąg przy zawracaniu pod prąd
const BOUNDS_MARGIN := 300.0
const BOUNDS_PUSH := 1400.0
const STOP_DAMP := 6.0          # pełny stop: tłumienie pędu (od pełnej prędkości do zera w ok. 0,6 s)
const STOP_DECEL := 260.0       # i stały spadek, żeby statek stanął w miejscu, a nie pełzał
const BOOST_TIME := 0.9
const TRAIL_STEP := 13.0

const HULL_SHAPE := [
	Vector2(22, 0), Vector2(4, -7), Vector2(-6, -18), Vector2(-14, -16), Vector2(-9, -6),
	Vector2(-13, 0), Vector2(-9, 6), Vector2(-14, 16), Vector2(-6, 18), Vector2(4, 7), Vector2(22, 0),
]


func _ready() -> void:
	z_index = 6
	trail = Line2D.new()
	trail.top_level = true
	trail.width = 6.0
	trail.z_index = 5
	var g := Gradient.new()
	g.set_color(0, Color(0.11, 0.84, 1.4, 0.0))
	g.set_color(1, Color(1.4, 0.22, 1.12, 0.8))
	trail.gradient = g
	trail.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(trail)


func reset_for_launch() -> void:
	hull = GameState.stat("max_hull")
	shield = GameState.stat("max_shield")
	fuel = GameState.stat("max_fuel")
	fuel_warned = false
	empty_t = 0.0
	drifting = false
	drift_charge = 0.0
	since_hit = 10.0
	dead = false
	ang_vel = 0.0
	thrust_level = 0.0
	boost_t = 0.0
	trail_last = Vector2.INF
	trail.clear_points()


func nose() -> Vector2:
	return global_position + Vector2.RIGHT.rotated(rotation) * 22.0


func _process(delta: float) -> void:
	time += delta
	hit_flash = maxf(0.0, hit_flash - delta * 4.0)
	if docked or dead:
		thrusting = false
		firing = false
		trail.clear_points()
		visible = not dead and not docked
		return
	visible = true

	var mouse := get_global_mouse_position()
	var aim_off := mouse - global_position
	var to_mouse := aim_off.normalized()
	var no_fuel := fuel <= 0.0
	var power := 0.25 if no_fuel else 1.0   # bez paliwa silniki pracują na rezerwie

	# --- DRIFT (spacja): pęd zostaje, statek obraca się szybciej, ładuje się zryw ---
	var space := GameState.key_down("drift")
	if space and not drifting:
		drifting = true
		drift_charge = 0.0
		charge_pinged = false
	elif not space and drifting:
		drifting = false
		_drift_release(to_mouse, power)
	_steer(aim_off, delta)
	var dir := Vector2.RIGHT.rotated(rotation)
	if drifting:
		drift_charge = minf(drift_charge + delta, 1.0)
		if randf() < 0.5 and fx:
			fx.sparks(global_position - dir * 12.0, Color(0.4, 0.9, 1.0), 1, 60.0)
		if drift_charge >= 1.0 and not charge_pinged:
			# pełne naładowanie: wyraźny sygnał, że można puszczać
			charge_pinged = true
			Audio.play("ui_click", 0.0, -3.0)
			if fx:
				fx.ring(global_position, Color(0.5, 1.1, 1.3, 0.9), 44.0, 0.25)

	# pełny stop: silniki hamujące wygaszają cały pęd, ciąg jest w tym czasie odcięty
	stopping = GameState.key_down("stop") and not drifting
	thrusting = (GameState.key_down("thrust") or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) and not drifting and not stopping
	thrust_level = lerpf(thrust_level, 1.0 if thrusting else 0.0, 1.0 - exp(-SPOOL_RATE * delta))
	var maxs := GameState.stat("max_speed")
	if thrust_level > 0.01:
		var boost := 1.0
		var along := vel.dot(dir)
		if along < 0.0:
			boost += REVERSE_ASSIST * minf(1.0, -along / maxs)
		vel += dir * GameState.stat("thrust") * power * thrust_level * boost * delta
	# ciąg zagina tor lotu w stronę dziobu, więc statek bierze zakręty łukiem
	if thrusting and vel.length_squared() > 1600.0:
		var off := vel.angle_to(dir)
		if absf(off) < CARVE_MAX_ANGLE:
			vel = vel.rotated(off * (1.0 - exp(-CARVE_RATE * power * delta)))
	strafing = 0.0
	if not drifting:
		if GameState.key_down("left"):
			strafing -= 1.0
		if GameState.key_down("right"):
			strafing += 1.0
	if strafing != 0.0:
		vel += dir.rotated(PI * 0.5) * strafing * GameState.stat("thrust") * GameState.stat("strafe") * power * delta

	var damp := 0.3
	if drifting:
		damp = 0.04
	elif GameState.key_down("brake"):
		damp = GameState.stat("brake")
	# podczas porywania statek wyhamowuje, żeby łatwo utrzymać promień na celu
	if tool == 2 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not no_fuel and not drifting:
		damp = maxf(damp, 3.5)
	if stopping:
		damp = maxf(damp, STOP_DAMP)
	vel *= exp(-damp * delta)
	if stopping:
		# końcówka bez pełzania: stały spadek prędkości aż do zera
		vel = vel.move_toward(Vector2.ZERO, STOP_DECEL * delta)
	var spd := vel.length()
	if spd > maxs:
		# po zrywie z driftu prędkość wraca do normy łagodniej
		vel = vel.normalized() * lerpf(spd, maxs, 1.0 - exp(-(1.2 if boost_t > 0.0 else 4.0) * delta))
	boost_t = maxf(0.0, boost_t - delta)
	drift_flash = maxf(0.0, drift_flash - delta)

	position += vel * delta
	_soft_bounds(delta)
	_flight_fx(dir, delta)
	# regeneracja
	since_hit += delta
	if since_hit > 2.0:
		shield = minf(shield + GameState.stat("shield_regen") * delta, GameState.stat("max_shield"))
	# bez paliwa nanoboty stają - inaczej w późnej grze naprawa wyprzedzała ubytek i paliwo nie miało znaczenia
	if not no_fuel:
		hull = minf(hull + GameState.stat("hull_regen") * delta, GameState.stat("max_hull"))
	siphon_fuel_left = minf(siphon_fuel_left + SIPHON_FUEL_PER_S * delta, SIPHON_FUEL_PER_S)
	siphon_hull_left = minf(siphon_hull_left + SIPHON_HULL_PER_S * delta, SIPHON_HULL_PER_S)

	# laser górniczy / promień porywania (bez paliwa nie działają)
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not no_fuel
	firing = lmb and tool == 1
	abducting = lmb and tool == 2
	rebuilding = lmb and tool == 3
	beam_hit = false
	splash_points.clear()
	abduct_block_cd = maxf(0.0, abduct_block_cd - delta)
	if firing:
		var to := mouse - nose()
		var rng := GameState.stat("laser_range")
		beam_in_range = to.length() <= rng
		if not beam_in_range:
			to = to.normalized() * rng
		beam_target = nose() + to
		var dmg := GameState.stat("laser_dps") * delta
		# rakiety i myśliwce zatrzymują wiązkę w miejscu, gdzie ją przetną
		var stop: Vector2 = world.missile_laser_hit(nose(), beam_target, dmg)
		if stop == Vector2.INF and world.enemies:
			stop = world.enemies.laser_hit(nose(), beam_target, dmg * GameState.stat("fighter_damage"))
		if stop != Vector2.INF:
			beam_target = stop
			beam_hit = true
		else:
			beam_hit = world.laser_hit(beam_target, dmg, splash_points) >= 0
	if rebuilding:
		_rebuild(mouse, delta)
	else:
		rebuild_progress = maxf(0.0, rebuild_progress - delta * 0.5)
	if abducting:
		_abduct(mouse, delta)
	else:
		# krótkie puszczenie przycisku nie kasuje postępu od razu
		abduct_progress = maxf(0.0, abduct_progress - delta * 0.5)
		if abduct_progress <= 0.0:
			abduct_idx = -1

	# --- PALIWO ---
	var burn := 0.6
	if thrusting or strafing != 0.0:
		burn += 1.4
	if firing or abducting or rebuilding:
		burn += 0.8
	burn *= maxf(0.2, 1.0 - GameState.stat("fuel_efficiency"))
	if GameState.training:
		burn *= TRAINING_BURN
	fuel = maxf(0.0, fuel - burn * delta)
	if no_fuel:
		# pusty bak: systemy podtrzymania życia zżerają kadłub (EMPTY_DRAIN na sekundę) - trzeba wracać
		empty_t += delta
		hull -= EMPTY_DRAIN * delta
		if hull <= 0.0:
			shield = 0.0
			take_damage(1.0)
	else:
		empty_t = 0.0

	queue_redraw()


## Obrót do kursora z rozpędem: start i koniec skrętu są miękkie, a pełna szybkość zostaje taka sama.
func _steer(aim_off: Vector2, delta: float) -> void:
	var turn := GameState.stat("turn_rate") * (1.8 if drifting else 1.0)
	var want_w := 0.0
	if aim_off.length() > AIM_DEADZONE:
		want_w = clampf(wrapf(aim_off.angle() - rotation, -PI, PI) * TURN_GAIN, -turn, turn)
	ang_vel = lerpf(ang_vel, want_w, 1.0 - exp(-TURN_RESPONSE * delta))
	rotation += ang_vel * delta


## Poza mapą statek jest łagodnie zawracany, zamiast odbijać się od niewidzialnej ściany.
func _soft_bounds(delta: float) -> void:
	var lim := Vector2(world.N * world.T, world.H * world.T)
	if position.x < -BOUNDS_MARGIN:
		vel.x += BOUNDS_PUSH * delta
	elif position.x > lim.x + BOUNDS_MARGIN:
		vel.x -= BOUNDS_PUSH * delta
	if position.y < -BOUNDS_MARGIN:
		vel.y += BOUNDS_PUSH * delta
	elif position.y > lim.y + BOUNDS_MARGIN:
		vel.y -= BOUNDS_PUSH * delta
	# szkolenie: obszar wokół Roswell to twarda granica
	var pr: Rect2 = world.play_rect
	if pr.has_area():
		var inside := Vector2(clampf(position.x, pr.position.x, pr.end.x), clampf(position.y, pr.position.y, pr.end.y))
		if inside != position:
			var n := (inside - position).normalized()
			var along_n := vel.dot(n)
			if along_n < 0.0:
				vel -= n * along_n * 1.6
			position = inside
	# pole siłowe zamkniętych sektorów: twarda ściana, bez marginesu
	var push: Vector2 = world.barrier_push(position)
	if push != Vector2.ZERO:
		var along := vel.dot(push)
		if along < 0.0:
			vel -= push * along
		vel += push * BOUNDS_PUSH * 2.0 * delta
		position = world.barrier_clamp(position)


## Smuga, spaliny i smugi prędkości. Długość smugi zależy od prędkości, a nie od liczby klatek.
func _flight_fx(dir: Vector2, delta: float) -> void:
	var sf := clampf(vel.length() / maxf(1.0, GameState.stat("max_speed")), 0.0, 1.6)
	var back := global_position - dir * 12.0
	if trail_last == Vector2.INF or back.distance_to(trail_last) >= TRAIL_STEP:
		trail.add_point(back)
		trail_last = back
	var keep := 6 + int(sf * 26.0)
	var drop := 0
	while trail.get_point_count() > keep and drop < 2:
		trail.remove_point(0)
		drop += 1
	trail.width = 3.0 + minf(sf, 1.2) * 4.0 + thrust_level * 1.5
	if fx == null:
		return
	exhaust_t -= delta
	if thrust_level > 0.3 and exhaust_t <= 0.0:
		exhaust_t = 0.045
		fx.streak(back + Vector2(randf_range(-3, 3), randf_range(-3, 3)), vel * 0.35 - dir * randf_range(120.0, 240.0), Color(1.2, 0.6, 0.25), 0.28)
	# przy dużej prędkości obok statku przelatują smugi
	if sf > 0.75:
		var n := int((sf - 0.75) * 2.0 + randf())
		for k in n:
			var side := vel.normalized().orthogonal() * randf_range(-420.0, 420.0)
			fx.streak(global_position + vel.normalized() * randf_range(120.0, 620.0) + side, vel * 0.8, Color(0.55, 0.8, 1.2, 0.35), 0.2)
		# opływ: krótkie smugi ciągnięte przy samym kadłubie
		if randf() < (sf - 0.75):
			var nrm := vel.normalized().orthogonal() * randf_range(-22.0, 22.0)
			fx.streak(global_position + nrm, -vel * 0.25, Color(0.9, 0.5, 1.3, 0.6), 0.16)


func _drift_release(to_mouse: Vector2, power: float) -> void:
	if drift_charge < 0.12:
		return
	# zryw w kierunku kursora: część pędu zostaje przekierowana + delikatny boost
	var spd := vel.length()
	var newdir := vel.normalized().lerp(to_mouse, 0.75).normalized() if spd > 1.0 else to_mouse
	var charge := drift_charge
	vel = newdir * spd + to_mouse * GameState.stat("drift_boost") * charge * power
	drift_flash = 0.6
	boost_t = BOOST_TIME * charge
	drift_charge = 0.0
	drift_released.emit(charge)
	Audio.play("drift_boost", 0.06, -6.0 + charge * 5.0)
	Audio.play("plasma_burst", 0.05, -4.0 + charge * 4.0)
	if fx:
		var back := -vel.normalized()
		fx.plasma_burst(global_position + back * 16.0, back, charge, vel)
		fx.ring(global_position, Color(0.4, 0.9, 1.0, 0.8), 40.0 + 40.0 * charge, 0.3)
		fx.shake(2.0 + 5.0 * charge)
		fx.sparks(global_position - to_mouse * 14.0, Color(0.5, 1.0, 1.2), int(4.0 + 10.0 * charge), 260.0)


## Kafelki w obszarze porywania (okrąg wokół celu), z których można jeszcze porwać istoty.
func abduct_tiles(center: int) -> Array:
	var out: Array = []
	if center < 0:
		return out
	var r := GameState.stat("abduct_area")
	var ri := int(floor(r))
	var cx: int = center % world.N
	var cy: int = center / world.N
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dy * dy > r * r + 0.01:
				continue
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= world.N or y >= world.H:
				continue
			var j: int = y * world.N + x
			if world.abduct_source(j) != "":
				out.append(j)
	return out


func _abduct(mouse: Vector2, delta: float) -> void:
	var rng := GameState.stat("abduct_range")
	var to := mouse - global_position
	beam_in_range = to.length() <= rng
	if not beam_in_range:
		to = to.normalized() * rng
	var aim := global_position + to
	var t: float = world.T
	var tol := t * (1.5 + GameState.stat("abduct_area"))
	# namierzony kafelek trzyma się, dopóki kursor jest w pobliżu (tolerancja ~1.5 kafelka)
	if abduct_idx >= 0:
		var lc: Vector2 = world.idx_center(abduct_idx)
		var locked := abduct_tiles(abduct_idx)
		if locked.size() > 0 and global_position.distance_to(lc) <= rng + t * 1.5:
			if aim.distance_to(lc) <= tol:
				abduct_lost_t = 0.0
			else:
				abduct_lost_t += delta
			# krótka karencja: chwilowe zejście kursora nie przerywa porwania
			if abduct_lost_t < 0.4:
				beam_target = lc
				beam_in_range = true
				_abduct_step(abduct_idx, locked, delta)
				return
	beam_target = aim
	var i: int = world.pos_to_idx(aim)
	var tiles := abduct_tiles(i)
	abduct_valid = tiles.size() > 0
	if not abduct_valid:
		# chwilowa utrata celu: postęp powoli maleje zamiast znikać
		abduct_progress = maxf(0.0, abduct_progress - delta * 0.5)
		return
	if i != abduct_idx:
		abduct_idx = i
		abduct_progress = 0.0
		abduct_lost_t = 0.0
	_abduct_step(i, tiles, delta)


func _abduct_step(i: int, tiles: Array, delta: float) -> void:
	abduct_valid = true
	if GameState.bio_free() <= 0:
		abduct_valid = false
		if abduct_block_cd <= 0.0:
			abduct_block_cd = 3.0
			abduct_blocked.emit("KOMORY BIO PEŁNE — wracaj do statku matki!")
		return
	# czas porwania: 2.5 s przy szybkości 100% (niezależnie od wielkości obszaru)
	abduct_progress += delta * GameState.stat("abduct_speed") / 2.5
	if abduct_progress < 1.0:
		return
	abduct_progress = 0.0
	abduct_idx = -1
	var c: Vector2 = world.idx_center(i)
	tiles.sort_custom(func(a, b): return world.idx_center(a).distance_squared_to(c) < world.idx_center(b).distance_squared_to(c))
	var per_kind := {}
	for j in tiles:
		if GameState.bio_free() <= 0:
			break
		var kind: String = world.abduct_source(j)
		world.mark_abducted(j)
		var got := GameState.add_bio(kind, int(GameState.stat("abduct_amount")))
		per_kind[kind] = int(per_kind.get(kind, 0)) + got
	var k := 0
	for kind in per_kind:
		abducted.emit(kind, per_kind[kind], c + Vector2(0, -k * 16))
		k += 1


## Zniszczone kafelki w obszarze odbudowy (okrąg wokół celu).
func rebuild_tiles(center: int) -> Array:
	var out: Array = []
	if center < 0:
		return out
	var r := GameState.stat("rebuild_area")
	var ri := int(floor(r))
	var cx: int = center % world.N
	var cy: int = center / world.N
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dy * dy > r * r + 0.01:
				continue
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= world.N or y >= world.H:
				continue
			var j: int = y * world.N + x
			if world.can_rebuild(j):
				out.append(j)
	return out


func _rebuild(mouse: Vector2, delta: float) -> void:
	var rng := GameState.stat("rebuild_range")
	var to := mouse - global_position
	beam_in_range = to.length() <= rng
	if not beam_in_range:
		to = to.normalized() * rng
	var aim := global_position + to
	var t: float = world.T
	var tol := t * (1.2 + GameState.stat("rebuild_area") - 0.5)
	# namierzony obszar trzyma się przy drobnych ruchach kursora
	if rebuild_idx >= 0:
		var lc: Vector2 = world.idx_center(rebuild_idx)
		if rebuild_tiles(rebuild_idx).size() > 0 and aim.distance_to(lc) <= tol and global_position.distance_to(lc) <= rng + t:
			beam_target = lc
			_rebuild_step(delta)
			return
	beam_target = aim
	var i: int = world.pos_to_idx(aim)
	rebuild_valid = rebuild_tiles(i).size() > 0
	if not rebuild_valid:
		rebuild_progress = maxf(0.0, rebuild_progress - delta * 0.5)
		return
	if i != rebuild_idx:
		rebuild_idx = i
		rebuild_progress = 0.0
	beam_target = world.idx_center(i)
	_rebuild_step(delta)


func _rebuild_step(delta: float) -> void:
	var tiles := rebuild_tiles(rebuild_idx)
	var affordable := false
	for j in tiles:
		if GameState.can_afford(world.rebuild_cost(j)):
			affordable = true
			break
	if not affordable:
		rebuild_valid = false
		if abduct_block_cd <= 0.0 and tiles.size() > 0:
			abduct_block_cd = 3.0
			rebuild_blocked.emit("ZA MAŁO W MAGAZYNIE: " + GameState.cost_text(world.rebuild_cost(tiles[0])))
		return
	rebuild_valid = true
	# odbudowa: 2 s przy szybkości 100% (niezależnie od wielkości obszaru)
	rebuild_progress += delta * GameState.stat("rebuild_speed") / 2.0
	if rebuild_progress >= 1.0:
		rebuild_progress = 0.0
		var missing := 0
		for j in tiles:
			if not world.rebuild(j):
				missing += 1
		if missing > 0:
			rebuild_blocked.emit("Surowce skończyły się przed końcem odbudowy (pominięto: %d)" % missing)
		rebuild_idx = -1


func add_fuel(amount: float) -> void:
	fuel = minf(fuel + amount, GameState.stat("max_fuel"))


## Syfony z rozbitych kafelków (paliwo, kadłub) mają limit na sekundę: masowe niszczenie
## rozpryskiem i detonacją nie może dawać nieskończonego paliwa ani nieśmiertelności.
func siphon(fuel_amount: float, hull_amount: float) -> void:
	if dead:
		return
	var f := minf(fuel_amount, siphon_fuel_left)
	if f > 0.0:
		siphon_fuel_left -= f
		add_fuel(f)
	var h := minf(hull_amount, siphon_hull_left)
	if h > 0.0:
		siphon_hull_left -= h
		hull = minf(GameState.stat("max_hull"), hull + h)


func take_damage(amount: float) -> void:
	if dead or docked:
		return
	since_hit = 0.0
	hit_flash = 1.0
	if shield > 0.0:
		var absorbed := minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
		if fx:
			fx.ring(global_position, Color(0.14, 0.7, 1.4), 30.0)
			fx.shake(minf(1.0 + absorbed * 0.12, 4.0))
		Audio.play("shield_hit")
	if amount > 0.0:
		amount *= 1.0 - clampf(GameState.stat("armor"), 0.0, 0.8)
		hull -= amount
		Audio.play("ship_hit")
		if fx:
			fx.sparks(global_position, Color(1.4, 0.37, 0.14), 8)
			fx.shake(minf(2.0 + amount * 0.2, 7.0))
	if hull <= 0.0:
		hull = 0.0
		dead = true
		vel = Vector2.ZERO
		trail.clear_points()
		died.emit()


func _draw() -> void:
	if dead:
		return
	var lv: Vector2 = vel.rotated(-rotation)    # prędkość w układzie statku
	var sk := clampf((vel.length() / maxf(1.0, GameState.stat("max_speed")) - 0.7) / 0.5, 0.0, 1.0) if not docked else 0.0
	if sk > 0.0:
		# powidoki kadłuba zostają za statkiem jak przy przejściu w nadprzestrzeń
		var ghost := PackedVector2Array(HULL_SHAPE)
		ghost.append(ghost[0])
		for g in 3:
			draw_set_transform(-lv * 0.02 * (g + 1), 0.0, Vector2.ONE)
			draw_polyline(ghost, Color(1.4, 0.3, 1.3, 0.16 * sk * (1.0 - g / 3.0)), 1.5, true)
		draw_set_transform(Vector2.ZERO)
		# fala uderzeniowa przed statkiem, w kierunku lotu
		var la := lv.angle()
		var wob := sin(time * 30.0) * 1.5
		draw_arc(Vector2.ZERO, 30.0 + wob, la - 0.85, la + 0.85, 18, Color(0.5, 0.95, 1.4, 0.3 * sk), 1.6, true)
		draw_arc(Vector2.ZERO, 38.0 + wob, la - 0.6, la + 0.6, 14, Color(0.5, 0.95, 1.4, 0.12 * sk), 1.2, true)
	if stopping and lv.length() > 8.0 and not docked:
		# silniki hamujące: krótkie płomienie skierowane w stronę lotu
		var fd := lv.normalized()
		var side := fd.orthogonal() * 9.0
		var fl := 10.0 + randf() * 6.0 + minf(lv.length() / 40.0, 10.0)
		for sgn in [-1.0, 1.0]:
			var base: Vector2 = side * sgn + fd * 6.0
			draw_line(base, base + fd * fl, Color(0.4, 1.0, 1.4, 0.9), 2.5, true)
			draw_line(base, base + fd * fl * 0.5, Color(1.3, 1.4, 1.4), 1.2, true)
	# przechył: przy ostrym skręcie kadłub zwęża się i przesuwa w bok
	var bank := clampf(ang_vel / maxf(1.0, GameState.stat("turn_rate")), -1.0, 1.0)
	draw_set_transform(Vector2(0.0, bank * 1.5), 0.0, Vector2(1.0, 1.0 - absf(bank) * 0.24))
	var pts := PackedVector2Array(HULL_SHAPE)
	var body := Color(1.4, 0.23, 1.28)
	var accent := Color(0.16, 1.08, 1.4)
	if hit_flash > 0.0:
		body = body.lerp(Color(1.4, 1.4, 1.4), hit_flash)
	draw_colored_polygon(pts, Color(0.12, 0.0, 0.18, 0.95))
	draw_polyline(pts, body, 2.2, true)
	# kokpit
	draw_polyline(PackedVector2Array([Vector2(12, 0), Vector2(2, -4), Vector2(-3, 0), Vector2(2, 4), Vector2(12, 0)]), accent, 1.6, true)
	draw_line(Vector2(-6, -12), Vector2(4, -6), accent, 1.2, true)
	draw_line(Vector2(-6, 12), Vector2(4, 6), accent, 1.2, true)
	# płomień silnika
	if thrust_level > 0.03 and not docked:
		var fl := (14.0 + sin(time * 50.0) * 4.0 + randf() * 4.0) * thrust_level * (1.0 + minf(boost_t, 0.5))
		draw_polyline(PackedVector2Array([Vector2(-11, -4), Vector2(-11 - fl, 0), Vector2(-11, 4)]), Color(1.4, 0.75, 0.19), 2.5, true)
		draw_polyline(PackedVector2Array([Vector2(-11, -2), Vector2(-11 - fl * 0.5, 0), Vector2(-11, 2)]), Color(1.4, 1.4, 1.17), 1.5, true)
	if strafing != 0.0 and not docked:
		var sy := -16.0 * strafing
		draw_line(Vector2(-4, sy), Vector2(-4, sy - 8.0 * strafing), Color(0.23, 1.17, 1.4), 2.0, true)
	draw_set_transform(Vector2.ZERO)
	# tarcza
	var ms := GameState.stat("max_shield")
	if ms > 0.0 and shield > 0.0:
		var a := 0.15 + 0.35 * (shield / ms) + since_hit_glow()
		draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 40, Color(0.14, 0.65, 1.4, a), 1.5, true)
	# drift: łuk ładowania zrywu (obraca się razem ze statkiem, więc rysujemy z tyłu)
	if drifting:
		var c := Color(0.4, 0.9, 1.0, 0.4 + 0.5 * drift_charge)
		draw_arc(Vector2.ZERO, 24.0, PI - drift_charge * 2.4, PI + drift_charge * 2.4, 24, c, 2.5, true)
	if drift_flash > 0.0:
		draw_polyline(PackedVector2Array([Vector2(-12, -8), Vector2(-30 - drift_flash * 30.0, 0), Vector2(-12, 8)]), Color(0.4, 0.9, 1.0, drift_flash), 2.0, true)


func since_hit_glow() -> float:
	return clampf(1.0 - since_hit * 2.0, 0.0, 1.0) * 0.6
