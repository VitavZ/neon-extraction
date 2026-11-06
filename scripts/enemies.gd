extends Node2D
## Ziemskie myśliwce. Pojawiają się po niszczeniu miast, gonią gracza i strzelają.
## Dwa typy (można je zestrzelić laserem):
## - "fighter": krąży blisko gracza i strzela pociskami,
## - "laser": trzyma dystans, ucieka przed graczem, ładuje wiązkę (widać celownik), a potem
##   powoli wodzi nią za statkiem. Kruchy, ale trzeba go gonić albo uciekać z linii strzału,
## - "gunner": krąży dalej i co kilka sekund strzela salwą 5 pocisków jak z karabinu.
## - "tank": czołg - jeździ po lądzie (najczęściej między miastami), obraca wieżę za graczem i strzela pociskami
##   artyleryjskimi po łuku. Miejsce upadku widać na ziemi jako celownik, więc da się uskoczyć.

signal fighter_destroyed(pos: Vector2, kind: String, looted: bool)

const SPEED := 320.0
const ACCEL := 420.0
const FIRE_RANGE := 460.0
const HIT_RADIUS := 20.0
const PATROL_SPEED := 190.0
const AGGRO_RANGE := 620.0
const PATROL_DESPAWN := 5200.0

const BURST_SHOTS := 5
const BURST_GAP := 0.11

const LASER_SPEED := 260.0
const LASER_STANDOFF := 430.0
const LASER_RANGE := 640.0
const LASER_CHARGE := 1.2
const LASER_FIRE := 1.1
const LASER_WIDTH := 16.0
const LASER_TURN_CHARGE := 1.6
const LASER_TURN_FIRE := 0.9

const TANK_SPEED := 85.0
const TANK_TURN := 1.7          # obrót kadłuba (rad/s) - czołg skręca w miejscu
const TANK_TURRET_TURN := 2.4
const TANK_AGGRO := 720.0
const TANK_RANGE := 640.0
const TANK_STANDOFF := 400.0
const SHELL_BLAST := 58.0
const TREAD_LIFE := 9.0
const TREAD_MAX := 500
const TANK_SCALE := 1.3

var fighters: Array = []   # {kind, pos, vel, rot, hp, max_hp, cd, orbit, flash, dmg} + dla lasera: state, state_t
var world: Node2D
var ship: Node2D
var fx: Node2D
var wingmen: Node2D             # sojusznicy gracza: też bywają celem
var miners: Node2D
var transit: Node2D
var mothership: Node2D          # cel ataku Ziemian (oblężenie po upadku Nowego Jorku)
var time := 0.0
var shells: Array = []          # pociski czołgów w locie: {from, to, t, max, dmg, arc}
var treads: Array = []          # ślady gąsienic: [a, b, life]


func _ready() -> void:
	z_index = 6


func spawn_near(target: Vector2, count: int, kind := "fighter") -> void:
	var d: float = world.danger_at(target)
	var laser := kind == "laser"
	var far := offscreen_dist()
	for k in count:
		var ang := randf() * TAU
		var p := target + Vector2.from_angle(ang) * randf_range(far, far + 200.0)
		var gunner := kind == "gunner"
		var hp := (28.0 if laser else (38.0 if gunner else 45.0)) * (1.0 + d / 60.0)
		# dla lasera: obrażenia na sekundę wiązki (działa ok. 25% czasu), dla pozostałych: za pocisk
		var dmg := (13.0 if laser else (4.5 if gunner else 7.0)) * (1.0 + d / 70.0)
		fighters.append({"kind": kind, "pos": p, "vel": Vector2.from_angle(ang + PI) * 200.0, "rot": ang + PI,
			"hp": hp, "max_hp": hp, "cd": randf_range(1.0, 2.0), "orbit": (1.0 if randf() < 0.5 else -1.0),
			"flash": 0.0, "dmg": dmg, "state": "idle", "state_t": 0.0, "burst_left": 0, "burst_t": 0.0})


## Odległość od środka ekranu, z której myśliwiec nadlatuje spoza kadru (z zapasem na szerokie ekrany i oddalenie kamery).
func offscreen_dist() -> float:
	var vs := get_viewport_rect().size
	var cam := get_viewport().get_camera_2d()
	if cam:
		vs /= cam.zoom
	return maxf(1000.0, vs.length() * 0.5 + 160.0)


## Łowcy: losowa pogoń za graczem. Na początku gry słabsi, wolniejsi od statku gracza
## i po pewnym czasie odpuszczają, więc da się przed nimi uciec.
func spawn_hunters(target: Vector2, count: int, kind := "fighter") -> void:
	var start := fighters.size()
	spawn_near(target, count, kind)
	var k := clampf((GameState.sorties - 5) / 30.0, 0.0, 1.0)
	var mul := lerpf(0.5, 1.0, k)
	var speed := minf(SPEED, GameState.stat("max_speed") * lerpf(0.75, 0.95, k))
	for i in range(start, fighters.size()):
		var f: Dictionary = fighters[i]
		f["hp"] *= mul
		f["max_hp"] = f["hp"]
		f["dmg"] *= mul
		f["speed"] = speed
		f["hunt_t"] = lerpf(25.0, 50.0, k)


## Patrol: lata od punktu do punktu (najczęściej przy miastach) i atakuje dopiero, gdy zauważy gracza.
func spawn_patrol(at: Vector2, count: int, kind := "fighter") -> void:
	var start := fighters.size()
	spawn_near(at, count, kind)
	for k in range(start, fighters.size()):
		var f: Dictionary = fighters[k]
		f["pos"] = at + Vector2.from_angle(randf() * TAU) * randf_range(20.0, 120.0)
		f["vel"] = Vector2.ZERO
		f["patrol"] = true
		f["wp"] = world.patrol_point(at)


## Czołgi: grupa rusza z okolicy miasta i jeździ od miasta do miasta, dopóki nie zobaczy gracza.
func spawn_tanks(at: Vector2, count: int) -> void:
	var d: float = world.danger_at(at)
	for k in count:
		var p := at
		for attempt in 12:
			var q := at + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 140.0)
			if world.ground_at(q):
				p = q
				break
		var hp := 140.0 * (1.0 + d / 60.0)
		var rot := randf() * TAU
		fighters.append({"kind": "tank", "pos": p, "vel": Vector2.ZERO, "rot": rot, "turret": rot, "hp": hp, "max_hp": hp,
			"cd": randf_range(1.5, 3.0), "orbit": (1.0 if randf() < 0.5 else -1.0), "flash": 0.0,
			"dmg": 14.0 * (1.0 + d / 70.0), "state": "idle", "state_t": 0.0, "burst_left": 0, "burst_t": 0.0,
			"wp": world.tank_point(p), "tread": 0.0, "recoil": 0.0, "mark": p, "alert": false})


func tank_count() -> int:
	var n := 0
	for f in fighters:
		if f["kind"] == "tank" and not f.get("dead", false):
			n += 1
	return n


func patrol_count() -> int:
	var n := 0
	for f in fighters:
		if f.get("patrol", false) and not f.get("dead", false):
			n += 1
	return n


## Myśliwce, które już polują na gracza (bez spokojnych patroli).
func hostile_count() -> int:
	var n := 0
	for f in fighters:
		if not f.get("patrol", false) and not f.get("dead", false) and f["kind"] != "tank":
			n += 1
	return n


## Myśliwce, które właśnie ścigają gracza: bez spokojnych patroli, łowców, którzy odpuścili,
## i oblężników zajętych Statkiem Matką.
func chasers() -> Array:
	var out: Array = []
	for f in fighters:
		if f.get("dead", false) or f.get("patrol", false) or f.get("gave_up", false) or f["kind"] == "tank":
			continue
		if f.get("siege", false) and mothership and not mothership.wrecked:
			continue
		out.append(f)
	return out


func clear_all() -> void:
	fighters.clear()
	shells.clear()


func alive_count() -> int:
	var n := 0
	for f in fighters:
		if not f.get("dead", false):
			n += 1
	return n


## Czy jakiś myśliwiec jest w promieniu (np. blokada hangaru).
func any_within(p: Vector2, r: float) -> bool:
	for f in fighters:
		if not f.get("dead", false) and f["kind"] != "tank" and f["pos"].distance_to(p) < r:
			return true
	return false


func nearest(p: Vector2, max_d: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_d
	for f in fighters:
		if f.get("dead", false):
			continue
		var d: float = f["pos"].distance_to(p)
		if d < bd:
			bd = d
			best = f
	return best


func damage_fighter(f: Dictionary, amount: float, looted := true) -> void:
	if f.get("dead", false):
		return
	f["hp"] -= amount
	f["flash"] = 0.15
	f["acc"] = float(f.get("acc", 0.0)) + amount
	if f["hp"] <= 0.0:
		_kill(f, looted)


## looted = false: zabójstwo bez łupu (np. rakiety Statku Matki).
func damage_in_radius(p: Vector2, r: float, amount: float, looted := true) -> void:
	for f in fighters:
		if not f.get("dead", false) and f["pos"].distance_to(p) <= r + HIT_RADIUS:
			damage_fighter(f, amount, looted)


## Wiązka gracza od a do b: trafia pierwszy myśliwiec na swojej drodze. Zwraca punkt trafienia lub Vector2.INF.
func laser_hit(a: Vector2, b: Vector2, amount: float) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	var hit: Dictionary = {}
	for f in fighters:
		if f.get("dead", false):
			continue
		var cp := Geometry2D.get_closest_point_to_segment(f["pos"], a, b)
		var hr := HIT_RADIUS * (1.4 if f["kind"] == "tank" else 1.0)
		if cp.distance_to(f["pos"]) < hr and a.distance_to(cp) < bd:
			bd = a.distance_to(cp)
			best = cp
			hit = f
	if not hit.is_empty():
		damage_fighter(hit, amount)
	return best


func _kill(f: Dictionary, looted := true) -> void:
	f["dead"] = true
	_flush(f)
	if fx:
		fx.explosion(f["pos"], Color(1.0, 0.5, 0.3), true)
	fighter_destroyed.emit(f["pos"], f["kind"], looted)


func _flush(f: Dictionary) -> void:
	var a: float = f.get("acc", 0.0)
	if a >= 0.5 and fx:
		fx.damage_number(f["pos"] + Vector2(0, -18), a, Color(1.0, 0.35, 0.35))
	f["acc"] = 0.0


func _process(delta: float) -> void:
	time += delta
	fighters = fighters.filter(func(f): return not f.get("dead", false))
	if ship == null:
		return
	var active: bool = not ship.docked and not ship.dead
	for f in fighters:
		f["flash"] = maxf(0.0, f["flash"] - delta)
		f["acc_t"] = float(f.get("acc_t", 0.0)) + delta
		if f["acc_t"] >= 0.15:
			f["acc_t"] = 0.0
			_flush(f)
		if f["kind"] == "tank":
			_process_tank(f, delta, active)
			continue
		if f.get("patrol", false) and _process_patrol(f, delta, active):
			continue
		if f["kind"] == "laser":
			_process_laser(f, delta, active)
			continue
		var hunting := active
		if f.has("hunt_t"):
			# łowca odpuszcza po czasie, jeśli gracz trzyma się z daleka
			f["hunt_t"] -= delta
			if f["hunt_t"] <= 0.0 and f["pos"].distance_to(ship.global_position) > 500.0:
				f["gave_up"] = true
			if f.get("gave_up", false):
				hunting = false
		var spd: float = f.get("speed", SPEED)
		var sp: Vector2 = _aim_pos(f, delta, hunting)
		var to: Vector2 = sp - f["pos"]
		var dist := to.length()
		var desired: Vector2
		if not hunting:
			# gracz zadokował / zginął / łowca odpuścił - myśliwce odlatują
			desired = -to.normalized() * spd
		elif dist > 320.0:
			desired = to.normalized() * spd
		else:
			# krążenie wokół gracza
			var tangent := to.normalized().rotated(PI * 0.5 * f["orbit"])
			var orbit_r := 290.0 if f["kind"] == "gunner" else 220.0
			desired = (tangent * 0.85 + to.normalized() * (dist - orbit_r) / 220.0).normalized() * spd
		var steer: Vector2 = (desired - f["vel"]).limit_length(ACCEL * delta)
		f["vel"] += steer
		f["pos"] += f["vel"] * delta
		var aim: float = to.angle() if hunting else f["vel"].angle()
		f["rot"] = lerp_angle(f["rot"], aim, (2.5 if f["burst_left"] > 0 else 6.0) * delta)
		if f["kind"] == "gunner":
			if hunting:
				_process_burst(f, delta, dist)
		elif hunting and dist < FIRE_RANGE:
			f["cd"] -= delta
			if f["cd"] <= 0.0:
				f["cd"] = randf_range(0.9, 1.4)
				var dir := Vector2.from_angle(f["rot"])
				Audio.play("enemy_shot", 0.1, -4.0)
				world.bullets.append({"pos": f["pos"] + dir * 16.0, "vel": dir * 420.0, "life": 2.0, "dmg": f["dmg"]})
		if not hunting and dist > 1600.0:
			f["dead"] = true
	_process_shells(delta, active)
	for tr in treads:
		tr[2] -= delta
	if not treads.is_empty() and treads[0][2] <= 0.0:
		treads = treads.filter(func(tr): return tr[2] > 0.0)
	if visible:
		queue_redraw()


# ---------------- CZOŁGI ----------------

func _process_tank(f: Dictionary, delta: float, active: bool) -> void:
	var sp: Vector2 = ship.global_position
	var to_ship: Vector2 = sp - f["pos"]
	var dist := to_ship.length()
	f["recoil"] = maxf(0.0, f["recoil"] - delta * 3.5)
	var engaged: bool = active and (dist < TANK_AGGRO or (f["alert"] and dist < TANK_AGGRO * 1.6) or (f["hp"] < f["max_hp"] and dist < TANK_AGGRO * 1.8))
	if engaged and not f["alert"]:
		Audio.play("alarm", 0.0, -10.0)
	f["alert"] = engaged
	# cel jazdy: dystans ostrzału albo spokojny przejazd do kolejnego miasta
	var goal: Vector2 = f["wp"]
	if engaged:
		if dist > TANK_STANDOFF + 90.0:
			goal = sp
		elif dist < TANK_STANDOFF - 90.0:
			goal = f["pos"] - to_ship
		else:
			goal = f["pos"] + to_ship.orthogonal() * f["orbit"]
	elif f["pos"].distance_to(goal) < 70.0:
		f["wp"] = world.tank_point(f["pos"])
	var want: float = (goal - f["pos"]).angle()
	var diff := angle_difference(f["rot"], want)
	f["rot"] = rotate_toward(f["rot"], want, TANK_TURN * delta)
	var speed := TANK_SPEED * (1.0 if engaged else 0.65) * clampf(1.0 - absf(diff) / 1.3, 0.0, 1.0)
	var step := Vector2.from_angle(f["rot"]) * speed * delta
	var next: Vector2 = f["pos"] + step
	if world.ground_at(next + Vector2.from_angle(f["rot"]) * 22.0):
		f["pos"] = next
		f["vel"] = step / maxf(delta, 0.0001)
		f["tread"] += step.length()
	else:
		# woda albo granica: skręt w miejscu i nowy cel
		f["vel"] = Vector2.ZERO
		f["rot"] += TANK_TURN * delta * f["orbit"]
		if not engaged and randf() < delta * 2.0:
			f["wp"] = world.tank_point(f["pos"])
	# ślady gąsienic co kilkanaście pikseli
	if f["pos"].distance_to(f["mark"]) > 12.0:
		var side := Vector2.from_angle(f["rot"]).orthogonal() * 12.5 * TANK_SCALE
		treads.append([f["mark"] + side, f["pos"] + side, TREAD_LIFE])
		treads.append([f["mark"] - side, f["pos"] - side, TREAD_LIFE])
		f["mark"] = f["pos"]
		if treads.size() > TREAD_MAX:
			treads = treads.slice(treads.size() - TREAD_MAX)
		if fx and randf() < 0.35:
			fx.streak(f["pos"] - Vector2.from_angle(f["rot"]) * 20.0 + Vector2(randf_range(-6, 6), randf_range(-6, 6)),
				-Vector2.from_angle(f["rot"]) * randf_range(10.0, 30.0), Color(0.55, 0.45, 0.4, 0.5), 0.6)
	# wieża: za graczem (z wyprzedzeniem), w spokoju wzdłuż kadłuba
	var aim: Vector2 = sp + ship.vel * 0.55
	var aim_ang: float = (aim - f["pos"]).angle() if engaged else f["rot"]
	f["turret"] = rotate_toward(f["turret"], aim_ang, TANK_TURRET_TURN * delta)
	if engaged and dist < TANK_RANGE:
		f["cd"] -= delta
		if f["cd"] <= 0.0 and absf(angle_difference(f["turret"], aim_ang)) < 0.12:
			_tank_fire(f, aim)
	elif f["cd"] < 1.0:
		f["cd"] = 1.0
	if dist > PATROL_DESPAWN:
		f["dead"] = true


func _tank_fire(f: Dictionary, aim: Vector2) -> void:
	f["cd"] = randf_range(3.0, 4.2)
	f["recoil"] = 1.0
	var dir := Vector2.from_angle(f["turret"])
	var muzzle: Vector2 = f["pos"] + dir * 32.0 * TANK_SCALE
	var to := aim + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 26.0)
	if to.distance_to(f["pos"]) > TANK_RANGE:
		to = f["pos"] + (to - f["pos"]).normalized() * TANK_RANGE
	var dist := muzzle.distance_to(to)
	shells.append({"from": muzzle, "to": to, "t": 0.0, "max": 0.75 + dist / 900.0, "dmg": f["dmg"], "arc": 40.0 + dist * 0.28})
	Audio.play("enemy_shot", 0.1, 2.0)
	if fx:
		fx.sparks(muzzle, Color(1.3, 0.8, 0.4), 6, 140.0)


func _process_shells(delta: float, active: bool) -> void:
	var k := shells.size() - 1
	while k >= 0:
		var s: Dictionary = shells[k]
		s["t"] += delta
		if s["t"] >= s["max"]:
			var p: Vector2 = s["to"]
			if fx:
				fx.explosion(p, Color(1.3, 0.55, 0.2), false)
				fx.ring(p, Color(1.4, 0.4, 0.2, 0.9), SHELL_BLAST, 0.35)
				fx.sparks(p, Color(1.2, 0.7, 0.35), 10, 220.0)
			Audio.play("blast_pop", 0.1, -2.0)
			if active and ship.global_position.distance_to(p) < SHELL_BLAST + 14.0:
				ship.take_damage(s["dmg"])
				if fx:
					fx.shake(5.0)
			shells.remove_at(k)
		k -= 1


func _shell_point(s: Dictionary, t: float) -> Vector2:
	var q := clampf(t / s["max"], 0.0, 1.0)
	return (s["from"] as Vector2).lerp(s["to"], q) - Vector2(0, sin(q * PI) * s["arc"])


## Wypukły wielokąt (albo gwiazda z punktem środkowym na początku) jako wachlarz trójkątów - bez triangulacji,
## która przy dużych współrzędnych mapy potrafi zawieść dla małych kształtów.
func _fill(pts: PackedVector2Array, c: Color) -> void:
	var n := pts.size()
	if n < 3:
		return
	var idx := PackedInt32Array()
	for i in range(1, n - 1):
		idx.append_array([0, i, i + 1])
	var cols := PackedColorArray()
	cols.resize(n)
	cols.fill(c)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)

func _draw_tank(f: Dictionary) -> void:
	var p: Vector2 = f["pos"]
	var xf := Transform2D(f["rot"], Vector2(TANK_SCALE, TANK_SCALE), 0.0, p)
	var calm: bool = not f["alert"]
	# cień i pierścień zagrożenia
	var shadow := PackedVector2Array([Vector2(-25, -17), Vector2(23, -17), Vector2(27, -11), Vector2(27, 11), Vector2(23, 17), Vector2(-25, 17)])
	_fill(Transform2D(f["rot"], Vector2(TANK_SCALE, TANK_SCALE), 0.0, p + Vector2(5, 7)) * shadow, Color(0, 0, 0, 0.6))
	var pulse := 0.5 + 0.5 * sin(time * 5.0 + p.x * 0.01)
	draw_arc(p, 33.0 * TANK_SCALE, 0.0, TAU, 32, Color(1.2, 0.7, 0.2, 0.3) if calm else Color(1.4, 0.15, 0.15, 0.4 + 0.35 * pulse), 1.6 if calm else 2.2, true)
	# gąsienice z przesuwającymi się ogniwami
	var line := Color(0.95, 0.95, 1.0) if f["flash"] <= 0.0 else Color(1.3, 0.6, 0.4)
	for sgn in [-1.0, 1.0]:
		var tr := PackedVector2Array([Vector2(-23, 9.5 * sgn), Vector2(21, 9.5 * sgn), Vector2(24, 12.5 * sgn), Vector2(21, 16 * sgn), Vector2(-23, 16 * sgn), Vector2(-25, 12.5 * sgn)])
		var tp := xf * tr
		_fill(tp, Color(0.06, 0.06, 0.08, 1.0))
		tp.append(tp[0])
		draw_polyline(tp, Color(0.55, 0.55, 0.65), 1.2, true)
		var cleats := PackedVector2Array()
		var off: float = fmod(f["tread"], 5.0)
		var x := -22.0 + off
		while x < 21.0:
			cleats.append(xf * Vector2(x, 10.5 * sgn))
			cleats.append(xf * Vector2(x, 15.0 * sgn))
			x += 5.0
		draw_multiline(cleats, Color(0.35, 0.35, 0.42), 1.0)
	# kadłub: ścięty przód, płyta silnika z tyłu
	var hull := xf * PackedVector2Array([Vector2(-20, -9.5), Vector2(14, -9.5), Vector2(20, -5), Vector2(20, 5), Vector2(14, 9.5), Vector2(-20, 9.5)])
	_fill(hull, Color(0.13, 0.14, 0.2, 0.98))
	# jaśniejsza płyta górna i pomarańczowe pasy ostrzegawcze Ziemian na przodzie
	_fill(xf * PackedVector2Array([Vector2(-15, -6.5), Vector2(11, -6.5), Vector2(11, 6.5), Vector2(-15, 6.5)]), Color(0.19, 0.2, 0.28))
	for sy in [-1.0, 1.0]:
		_fill(xf * PackedVector2Array([Vector2(15, -8.5 * sy), Vector2(18.5, -5 * sy), Vector2(18.5, -2.5 * sy), Vector2(15, -6 * sy)]), Color(1.3, 0.55, 0.15))
	hull.append(hull[0])
	draw_polyline(hull, Color(line.r, line.g, line.b, 0.25), 4.0, true)
	draw_polyline(hull, line, 1.8, true)
	draw_line(xf * Vector2(14, -9.5), xf * Vector2(14, 9.5), Color(line.r, line.g, line.b, 0.35), 1.0, true)
	for gx in [-17.0, -14.0, -11.0]:
		draw_line(xf * Vector2(gx, -6), xf * Vector2(gx, 6), Color(0.5, 0.5, 0.6, 0.7), 1.0, true)
	var blink := int(time * 4.0 + p.y * 0.01) % 2 == 0
	draw_circle(xf * Vector2(-19, -8), 1.8, Color(1.2, 0.2, 0.2) if blink else Color(0.5, 0.1, 0.1))
	draw_circle(xf * Vector2(-19, 8), 1.8, Color(1.2, 0.2, 0.2) if not blink else Color(0.5, 0.1, 0.1))
	# wieża z lufą (odrzut cofa lufę)
	var tx := Transform2D(f["turret"], Vector2(TANK_SCALE, TANK_SCALE), 0.0, p + Vector2.from_angle(f["rot"]) * -2.0 * TANK_SCALE)
	var rec: float = f["recoil"] * 6.0
	var barrel := tx * PackedVector2Array([Vector2(7, -2.2), Vector2(29 - rec, -2.2), Vector2(29 - rec, 2.2), Vector2(7, 2.2)])
	_fill(barrel, Color(0.18, 0.19, 0.26))
	barrel.append(barrel[0])
	draw_polyline(barrel, line, 1.4, true)
	var brake := tx * PackedVector2Array([Vector2(28 - rec, -3.6), Vector2(33 - rec, -3.6), Vector2(33 - rec, 3.6), Vector2(28 - rec, 3.6)])
	_fill(brake, Color(0.22, 0.23, 0.3))
	brake.append(brake[0])
	draw_polyline(brake, line, 1.2, true)
	var dome := PackedVector2Array()
	for k in 8:
		dome.append(tx * (Vector2.from_angle(k / 8.0 * TAU + PI / 8.0) * 10.5 + Vector2(-1, 0)))
	_fill(dome, Color(0.16, 0.17, 0.24))
	dome.append(dome[0])
	draw_polyline(dome, line, 1.6, true)
	draw_circle(tx * Vector2(-4, -3), 2.6 * TANK_SCALE, Color(0.3, 0.32, 0.4))
	# antena z migającą końcówką
	var ant_tip: Vector2 = tx * Vector2(-14, 6)
	draw_line(tx * Vector2(-5, 5), ant_tip, Color(0.6, 0.6, 0.7), 1.0, true)
	draw_circle(ant_tip, 1.6, Color(1.3, 0.25, 0.2) if int(time * 3.0) % 2 == 0 else Color(0.4, 0.1, 0.1))
	if f["alert"]:
		draw_arc(tx * Vector2(-1, 0), 13.5 * TANK_SCALE, 0.0, TAU, 24, Color(1.4, 0.3, 0.2, 0.25 + 0.25 * pulse), 2.0, true)
	# ładowanie strzału: czerwony żar u wylotu lufy
	var muzzle: Vector2 = tx * Vector2(34 - rec, 0)
	if f["alert"] and f["cd"] < 0.9:
		var g: float = 1.0 - f["cd"] / 0.9
		draw_circle(muzzle, 2.0 + g * 5.0, Color(1.4, 0.3, 0.2, 0.35 + 0.5 * g))
	draw_circle(tx * Vector2(2, 0), 2.4 * TANK_SCALE, Color(1.3, 0.25, 0.2) if f["alert"] else Color(0.6, 0.4, 0.2))
	if f["recoil"] > 0.55:
		# błysk wystrzału: kolczasta gwiazda w kierunku lufy
		var fl: float = (f["recoil"] - 0.55) / 0.45
		var fd := Vector2.from_angle(f["turret"])
		var star := PackedVector2Array([muzzle + fd * 5.0 * fl])
		for k in 11:
			var a: float = f["turret"] + k / 10.0 * TAU
			var r := (16.0 if k % 2 == 0 else 6.0) * fl
			star.append(muzzle + fd * 5.0 * fl + Vector2.from_angle(a) * r)
		_fill(star, Color(1.5, 0.9, 0.4, 0.85 * fl))
		draw_circle(muzzle, 5.0 * fl, Color(1.6, 1.5, 1.3, fl))
	var frac: float = f["hp"] / f["max_hp"]
	if frac < 1.0:
		draw_rect(Rect2(p + Vector2(-21, -46), Vector2(42, 6)), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(p + Vector2(-20, -45), Vector2(40 * frac, 4)), Color(1.3, 0.25, 0.25))


## Celownik na ziemi w miejscu upadku pocisku: im bliżej uderzenia, tym jaśniej.
func _draw_shell_marks() -> void:
	for s in shells:
		var to: Vector2 = s["to"]
		var q: float = s["t"] / s["max"]
		draw_circle(to, SHELL_BLAST * q, Color(1.4, 0.2, 0.1, 0.04 + 0.1 * q))
		draw_arc(to, SHELL_BLAST, 0.0, TAU, 40, Color(1.4, 0.25, 0.15, 0.35 + 0.5 * q), 1.8, true)
		var rot := time * 2.0
		for k in 4:
			var a := rot + k * TAU / 4.0
			draw_line(to + Vector2.from_angle(a) * (SHELL_BLAST - 10.0), to + Vector2.from_angle(a) * (SHELL_BLAST + 6.0), Color(1.4, 0.4, 0.2, 0.5 + 0.5 * q), 2.0, true)
		draw_circle(to, 2.5, Color(1.4, 0.5, 0.3, 0.6 + 0.4 * q))


## Pociski w powietrzu: cień na ziemi, smuga po łuku i rozżarzony rdzeń.
func _draw_shells() -> void:
	for s in shells:
		var q: float = s["t"] / s["max"]
		var ground: Vector2 = (s["from"] as Vector2).lerp(s["to"], q)
		var h := sin(q * PI)
		draw_circle(ground, 4.0 - h * 1.5, Color(0, 0, 0, 0.45))
		var trail := PackedVector2Array()
		var tcol := PackedColorArray()
		for j in 6:
			trail.append(_shell_point(s, maxf(0.0, s["t"] - j * 0.018)))
			tcol.append(Color(1.3, 0.55, 0.2, 0.55 * (1.0 - j / 6.0)))
		draw_polyline_colors(trail, tcol, 3.0, true)
		var head := _shell_point(s, s["t"])
		draw_circle(head, 7.0 + h * 3.0, Color(1.3, 0.5, 0.2, 0.25))
		draw_circle(head, 3.5 + h * 1.5, Color(1.5, 1.1, 0.6))


## Cel myśliwca: zwykle gracz, czasem myśliwiec Imperium albo statek wydobywczy w pobliżu.
func _aim_pos(f: Dictionary, delta: float, active: bool) -> Vector2:
	if not active:
		f["tgt"] = null
		return ship.global_position
	# oblężenie: myśliwiec trzyma się Statku Matki, dopóki ten stoi (gracz w pobliżu też obrywa)
	if f.get("siege", false) and mothership and not mothership.wrecked:
		if ship.global_position.distance_to(f["pos"]) < 260.0 and randf() < 0.5:
			return ship.global_position
		return mothership.global_position
	f["retarget"] = float(f.get("retarget", randf() * 2.0)) - delta
	if f["retarget"] <= 0.0:
		f["retarget"] = randf_range(2.0, 3.5)
		var prey: Dictionary = _friend_near(f["pos"], 560.0)
		f["tgt"] = prey if not prey.is_empty() and randf() < 0.45 else f.get("tgt")
	var t = f.get("tgt")
	if t is Dictionary and t.get("hp", 0.0) > 0.0 and not t.get("gone", false) and not t.get("dead", false):
		return t["pos"]
	f["tgt"] = null
	return ship.global_position


## Najbliższy sojusznik gracza (myśliwiec Imperium lub statek wydobywczy) w promieniu.
func _friend_near(p: Vector2, r: float, miners_only := false) -> Dictionary:
	var best: Dictionary = {}
	var bd := r
	if wingmen and wingmen.called and not miners_only:
		for w in wingmen.wings:
			var d: float = w["pos"].distance_to(p)
			if d < bd:
				bd = d
				best = w
	if miners:
		for m in miners.alive():
			var d: float = m["pos"].distance_to(p)
			if d < bd:
				bd = d
				best = m
	if transit and not miners_only:
		for t in transit.alive():
			var d: float = t["pos"].distance_to(p)
			if d < bd:
				bd = d
				best = t
	return best


## Spokojny lot patrolu. Zwraca false, gdy patrol właśnie zauważył gracza (albo statek wydobywczy) i atakuje.
func _process_patrol(f: Dictionary, delta: float, active: bool) -> bool:
	var sp: Vector2 = ship.global_position
	var dist: float = f["pos"].distance_to(sp)
	var prey: Dictionary = _friend_near(f["pos"], AGGRO_RANGE * 0.8, true) if active else {}
	if active and (dist < AGGRO_RANGE or f["hp"] < f["max_hp"] or not prey.is_empty()):
		# cała grupa w pobliżu rusza razem
		for o in fighters:
			if o.get("patrol", false) and o["pos"].distance_to(f["pos"]) < 400.0:
				o["patrol"] = false
				if not prey.is_empty():
					o["tgt"] = prey
					o["retarget"] = 6.0
		Audio.play("alarm", 0.0, -6.0)
		return false
	var wp: Vector2 = f["wp"]
	if f["pos"].distance_to(wp) < 90.0:
		f["wp"] = world.patrol_point(f["pos"])
	var desired: Vector2 = (wp - f["pos"]).normalized() * PATROL_SPEED
	f["vel"] += (desired - f["vel"]).limit_length(ACCEL * 0.5 * delta)
	f["pos"] += f["vel"] * delta
	f["rot"] = lerp_angle(f["rot"], f["vel"].angle(), 4.0 * delta)
	if dist > PATROL_DESPAWN:
		f["dead"] = true
	return true


## Salwa: odliczanie, a potem 5 szybkich pocisków. W czasie salwy myśliwiec wolniej celuje, więc można uskoczyć.
func _process_burst(f: Dictionary, delta: float, dist: float) -> void:
	if f["burst_left"] > 0:
		f["burst_t"] -= delta
		if f["burst_t"] <= 0.0:
			f["burst_t"] = BURST_GAP
			f["burst_left"] -= 1
			var dir := Vector2.from_angle(f["rot"] + randf_range(-0.04, 0.04))
			Audio.play("gun_shot", 0.1, -2.0)
			world.bullets.append({"pos": f["pos"] + dir * 18.0, "vel": dir * 480.0, "life": 1.6, "dmg": f["dmg"]})
			if f["burst_left"] == 0:
				f["cd"] = randf_range(3.2, 4.4)
		return
	f["cd"] -= delta
	if f["cd"] <= 0.0 and dist < FIRE_RANGE * 1.1:
		f["burst_left"] = BURST_SHOTS
		f["burst_t"] = 0.0


func _process_laser(f: Dictionary, delta: float, active: bool) -> void:
	var sp: Vector2 = ship.global_position
	var to: Vector2 = sp - f["pos"]
	var dist := to.length()
	var dirn := to.normalized()
	# ruch: trzyma dystans i ucieka, gdy gracz się zbliża; przy strzelaniu prawie stoi
	var desired: Vector2
	if not active:
		desired = -dirn * LASER_SPEED
	elif dist < LASER_STANDOFF - 90.0:
		desired = -dirn * LASER_SPEED
	elif dist > LASER_STANDOFF + 90.0:
		desired = dirn * LASER_SPEED
	else:
		desired = dirn.rotated(PI * 0.5 * f["orbit"]) * LASER_SPEED * 0.45
	if f["state"] != "idle":
		desired *= 0.3
	f["vel"] += (desired - f["vel"]).limit_length(ACCEL * delta)
	f["pos"] += f["vel"] * delta
	if not active:
		f["state"] = "idle"
		f["rot"] = lerp_angle(f["rot"], f["vel"].angle(), 6.0 * delta)
		if dist > 1600.0:
			f["dead"] = true
		return
	match f["state"]:
		"idle":
			f["rot"] = lerp_angle(f["rot"], to.angle(), 6.0 * delta)
			f["cd"] -= delta
			if f["cd"] <= 0.0 and dist < LASER_RANGE:
				f["state"] = "charge"
				f["state_t"] = LASER_CHARGE
		"charge":
			f["rot"] = rotate_toward(f["rot"], to.angle(), LASER_TURN_CHARGE * delta)
			f["state_t"] -= delta
			if f["state_t"] <= 0.0:
				f["state"] = "fire"
				f["state_t"] = LASER_FIRE
				Audio.play("enemy_shot", 0.05, 3.0)
		"fire":
			f["rot"] = rotate_toward(f["rot"], to.angle(), LASER_TURN_FIRE * delta)
			f["state_t"] -= delta
			var a: Vector2 = f["pos"]
			var b: Vector2 = a + Vector2.from_angle(f["rot"]) * LASER_RANGE
			if Geometry2D.get_closest_point_to_segment(sp, a, b).distance_to(sp) < LASER_WIDTH:
				ship.take_damage(f["dmg"] * delta)
			if f["state_t"] <= 0.0:
				f["state"] = "idle"
				f["cd"] = randf_range(2.6, 3.4)


func _draw() -> void:
	# ziemia: ślady gąsienic, celowniki pocisków, czołgi - pod myśliwcami
	if not treads.is_empty():
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for tr in treads:
			pts.append(tr[0])
			pts.append(tr[1])
			cols.append(Color(0.55, 0.5, 0.7, 0.22 * clampf(tr[2] / TREAD_LIFE, 0.0, 1.0)))
		draw_multiline_colors(pts, cols, 3.0)
	_draw_shell_marks()
	for f in fighters:
		if f["kind"] == "tank":
			_draw_tank(f)
	for f in fighters:
		if f["kind"] == "tank":
			continue
		var p: Vector2 = f["pos"]
		var r: float = f["rot"]
		var t := Transform2D(r, p)
		# cień i pierścień zagrożenia: wróg odcina się od kolorowych kafelków
		var calm: bool = f.get("patrol", false)
		draw_circle(p, 24.0, Color(0.0, 0.0, 0.0, 0.5))
		var pulse := 0.5 + 0.5 * sin(time * 6.0 + p.x * 0.01)
		var rc := Color(1.2, 0.7, 0.2, 0.35) if calm else Color(1.4, 0.15, 0.15, 0.45 + 0.35 * pulse)
		draw_arc(p, 25.0, 0.0, TAU, 28, rc, 1.6 if calm else 2.2, true)
		if f["kind"] == "laser":
			_draw_laser_fighter(f, t)
		elif f["kind"] == "gunner":
			_draw_gunner(f, t)
		else:
			var body := PackedVector2Array([Vector2(18, 0), Vector2(-6, -6), Vector2(-12, -16), Vector2(-14, -16),
				Vector2(-10, 0), Vector2(-14, 16), Vector2(-12, 16), Vector2(-6, 6), Vector2(18, 0)])
			var pts := t * body
			var line := Color(0.95, 0.95, 1.0)
			if f["flash"] > 0.0:
				line = Color(1.3, 0.6, 0.4)
			draw_colored_polygon(pts, Color(0.12, 0.13, 0.2, 0.95))
			draw_polyline(pts, line, 1.8, true)
			# czerwone światła pozycyjne Ziemian
			draw_circle(t * Vector2(-13, -16), 2.0, Color(1.2, 0.2, 0.2) if int(time * 4.0) % 2 == 0 else Color(0.5, 0.1, 0.1))
			draw_circle(t * Vector2(-13, 16), 2.0, Color(1.2, 0.2, 0.2) if int(time * 4.0) % 2 == 1 else Color(0.5, 0.1, 0.1))
			draw_line(t * Vector2(-10, 0), t * Vector2(-18 - randf() * 6.0, 0), Color(1.0, 0.6, 0.2), 2.0, true)
		# pasek HP
		var frac: float = f["hp"] / f["max_hp"]
		if frac < 1.0:
			draw_rect(Rect2(p + Vector2(-17, -33), Vector2(34, 6)), Color(0, 0, 0, 0.8))
			draw_rect(Rect2(p + Vector2(-16, -32), Vector2(32 * frac, 4)), Color(1.3, 0.25, 0.25))
	_draw_shells()


func _draw_gunner(f: Dictionary, t: Transform2D) -> void:
	var body := PackedVector2Array([Vector2(12, -7), Vector2(12, 7), Vector2(-4, 13), Vector2(-14, 10), Vector2(-14, -10), Vector2(-4, -13), Vector2(12, -7)])
	var pts := t * body
	var line := Color(1.3, 0.85, 0.25)
	if f["flash"] > 0.0:
		line = Color(1.4, 1.3, 1.1)
	draw_colored_polygon(pts, Color(0.2, 0.13, 0.03, 0.95))
	draw_polyline(pts, line, 2.0, true)
	# dwie lufy
	draw_line(t * Vector2(10, -5), t * Vector2(24, -5), line, 2.5, true)
	draw_line(t * Vector2(10, 5), t * Vector2(24, 5), line, 2.5, true)
	draw_line(t * Vector2(-14, 0), t * Vector2(-20 - randf() * 5.0, 0), Color(1.0, 0.6, 0.2), 2.0, true)
	if f["burst_left"] > 0:
		var side := -5.0 if f["burst_left"] % 2 == 0 else 5.0
		draw_circle(t * Vector2(26, side), 4.0, Color(1.5, 1.2, 0.5))


func _draw_laser_fighter(f: Dictionary, t: Transform2D) -> void:
	var body := PackedVector2Array([Vector2(22, 0), Vector2(2, -9), Vector2(-12, -6), Vector2(-16, 0), Vector2(-12, 6), Vector2(2, 9), Vector2(22, 0)])
	var pts := t * body
	var line := Color(1.25, 0.35, 0.3)
	if f["flash"] > 0.0:
		line = Color(1.4, 1.2, 1.0)
	draw_colored_polygon(pts, Color(0.2, 0.04, 0.08, 0.95))
	draw_polyline(pts, line, 2.0, true)
	draw_circle(t * Vector2(14, 0), 3.0, Color(1.4, 0.3, 0.2))
	draw_line(t * Vector2(-14, 0), t * Vector2(-20 - randf() * 5.0, 0), Color(1.0, 0.4, 0.3), 2.0, true)
	var a: Vector2 = t * Vector2(22, 0)
	var b: Vector2 = t * Vector2(22 + LASER_RANGE, 0)
	if f["state"] == "charge":
		# celownik: im bliżej strzału, tym wyraźniejszy - czas na ucieczkę z linii
		var k: float = 1.0 - f["state_t"] / LASER_CHARGE
		draw_line(a, b, Color(1.3, 0.2, 0.2, 0.2 + 0.5 * k), 1.0 + k, true)
		draw_circle(a, 2.0 + k * 5.0, Color(1.4, 0.4, 0.3, 0.8))
	elif f["state"] == "fire":
		var flick := 0.85 + 0.15 * sin(time * 50.0)
		draw_line(a, b, Color(1.2, 0.15, 0.1, 0.28 * flick), LASER_WIDTH * 1.5, true)
		draw_line(a, b, Color(1.4, 0.35, 0.2, 0.9 * flick), 5.0, true)
		draw_line(a, b, Color(1.5, 1.2, 1.1, flick), 1.6, true)
