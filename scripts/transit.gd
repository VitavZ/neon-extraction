extends Node2D
## Statki tranzytowe Imperium (najwyżej 3): co jakiś czas wyskakują z nadprzestrzeni obok gracza,
## przejmują część ładowni i skaczą z nią prosto do magazynu Statku Matki. Wrogowie mogą je zestrzelić -
## wtedy przewożony ładunek przepada. Zestrzelone wracają do służby po dokowaniu.

signal delivered(amount: int)
signal lost

const MAX_SHIPS := 3
const HIT_RADIUS := 24.0
const MIN_LOAD := 0.15         # nie przylatują po okruchy: ładownia musi być zapełniona choć w 15%
const DOCK_TIME := 0.9         # tyle trwa przeładunek przy statku gracza
const JUMP_DIST := 1100.0      # z tej odległości wyskakują i na tę odlatują

var world: Node2D
var ship: Node2D
var fx: Node2D
var ships: Array = []          # {pos, vel, rot, state, t, hp, max_hp, flash, load}
var down := 0                  # zestrzelone w tym locie
var timer := 20.0
var time := 0.0


func _ready() -> void:
	z_index = 7


func count() -> int:
	return mini(int(GameState.stat("transit_count")), MAX_SHIPS)


func ready_count() -> int:
	return maxi(0, count() - down - ships.size())


## Dokowanie: zestrzelone statki wracają, a lecące przepadają razem z niczym (ładunek już w magazynie).
func reset() -> void:
	ships.clear()
	down = 0
	timer = _interval()


func _interval() -> float:
	return maxf(12.0, GameState.stat("transit_interval")) / maxf(1.0, float(count()))


func alive() -> Array:
	return ships


func hurt(s: Dictionary, amount: float) -> void:
	if s.get("gone", false):
		return
	s["hp"] -= amount
	s["flash"] = 0.15
	if s["hp"] > 0.0:
		return
	s["gone"] = true
	ships.erase(s)
	down += 1
	if fx:
		fx.explosion(s["pos"], Color(1.3, 0.8, 0.3), true)
	Audio.play("explosion", 0.1)
	lost.emit()


func _process(delta: float) -> void:
	time += delta
	if ship == null or ship.docked or ship.dead or count() <= 0:
		if visible:
			queue_redraw()
		return
	timer -= delta
	var load := float(GameState.cargo_total()) / maxf(1.0, float(GameState.cargo_cap()))
	if timer <= 0.0:
		timer = _interval()
		if ready_count() > 0 and load >= MIN_LOAD:
			_spawn()
	var speed := GameState.stat("transit_speed")
	var sp: Vector2 = ship.global_position
	for s in ships.duplicate():
		s["flash"] = maxf(0.0, s["flash"] - delta)
		var goal: Vector2 = sp
		match s["state"]:
			"in":
				goal = sp + Vector2.from_angle(ship.rotation + PI * 0.75) * 60.0
				if s["pos"].distance_to(goal) < 40.0:
					s["state"] = "dock"
					s["t"] = DOCK_TIME
			"dock":
				goal = sp + Vector2.from_angle(ship.rotation + PI * 0.75) * 60.0
				s["t"] -= delta
				if s["t"] <= 0.0:
					_take(s)
					s["state"] = "out"
					s["dir"] = Vector2.from_angle(randf() * TAU)
			"out":
				goal = s["pos"] + s["dir"] * 400.0
				if s["pos"].distance_to(sp) > JUMP_DIST:
					_jump_home(s)
					continue
		var to: Vector2 = goal - s["pos"]
		var want: Vector2 = to.normalized() * minf(speed, to.length() * 5.0) if s["state"] != "dock" else to * 8.0 + ship.vel
		s["vel"] = s["vel"].lerp(want, 1.0 - exp(-6.0 * delta))
		s["pos"] += s["vel"] * delta
		if s["vel"].length() > 20.0:
			s["rot"] = lerp_angle(s["rot"], s["vel"].angle(), 1.0 - exp(-8.0 * delta))
	if visible:
		queue_redraw()


func _spawn() -> void:
	var a := randf() * TAU
	var p: Vector2 = ship.global_position + Vector2.from_angle(a) * JUMP_DIST * 0.8
	var hp := GameState.stat("transit_hp")
	ships.append({"pos": p, "vel": Vector2.from_angle(a + PI) * GameState.stat("transit_speed"), "rot": a + PI,
		"state": "in", "t": 0.0, "hp": hp, "max_hp": hp, "flash": 0.0, "load": {}})
	if fx:
		fx.ring(p, Color(1.3, 0.9, 0.3, 0.8), 60.0, 0.35)
	Audio.play("launch", 0.05, -8.0)


## Przeładunek: statek zabiera część każdego surowca z ładowni gracza.
func _take(s: Dictionary) -> void:
	var share := clampf(GameState.stat("transit_share"), 0.0, 1.0)
	var got := 0
	for k in GameState.cargo.keys():
		var n := int(floor(int(GameState.cargo[k]) * share))
		if n <= 0:
			continue
		GameState.cargo[k] = int(GameState.cargo[k]) - n
		s["load"][k] = n
		got += n
	GameState.cargo_changed.emit()
	if fx and got > 0:
		fx.float_text(s["pos"] + Vector2(0, -30), "-%d DO TRANZYTU" % got, Color(1.0, 0.8, 0.3))
		fx.ring(s["pos"], Color(1.3, 0.9, 0.3, 0.7), 40.0, 0.3)
	Audio.play("pickup", 0.05, 2.0)


## Skok do Statku Matki: ładunek trafia od razu do magazynu.
func _jump_home(s: Dictionary) -> void:
	ships.erase(s)
	var load: Dictionary = s["load"]
	var n := 0
	for k in load:
		GameState.bank[k] = int(GameState.bank.get(k, 0)) + int(load[k])
		GameState.collected[k] = int(GameState.collected.get(k, 0)) + int(load[k])
		n += int(load[k])
	if fx:
		fx.ring(s["pos"], Color(1.3, 0.9, 0.3, 0.8), 70.0, 0.35)
	if n > 0:
		GameState.bank_changed.emit()
		GameState.refresh_quests()
		delivered.emit(n)


func _draw() -> void:
	if ship == null or ship.docked:
		return
	var view: Rect2 = ship.world._cam_rect(260.0) if ship.world else Rect2(-1e7, -1e7, 2e7, 2e7)
	for s in ships:
		if not view.has_point(s["pos"]) and s["state"] != "dock":
			continue
		var xf := Transform2D(s["rot"], s["pos"])
		draw_arc(s["pos"], 28.0, 0.0, TAU, 28, Color(1.3, 0.9, 0.3, 0.3), 1.5, true)
		# szeroki, kanciasty frachtowiec z kontenerem pośrodku
		var hull := PackedVector2Array([Vector2(22, 0), Vector2(12, -11), Vector2(-16, -11), Vector2(-22, -6), Vector2(-22, 6), Vector2(-16, 11), Vector2(12, 11)])
		var pts := xf * hull
		draw_colored_polygon(pts, Color(0.16, 0.1, 0.02, 0.95))
		pts.append(pts[0])
		draw_polyline(pts, Color(1.5, 1.4, 1.2) if s["flash"] > 0.0 else Color(1.3, 0.85, 0.3), 2.0, true)
		var box := xf * PackedVector2Array([Vector2(8, -6), Vector2(8, 6), Vector2(-12, 6), Vector2(-12, -6), Vector2(8, -6)])
		draw_polyline(box, Color(0.4, 1.1, 1.3) if not s["load"].is_empty() else Color(0.5, 0.45, 0.4), 1.5, true)
		if s["vel"].length() > 60.0:
			draw_line(xf * Vector2(-22, -3), xf * Vector2(-32 - randf() * 6.0, -3), Color(1.2, 0.6, 0.25), 2.0, true)
			draw_line(xf * Vector2(-22, 3), xf * Vector2(-32 - randf() * 6.0, 3), Color(1.2, 0.6, 0.25), 2.0, true)
		if s["state"] == "dock":
			# promień przeładunku między statkami
			var k: float = 1.0 - s["t"] / DOCK_TIME
			draw_line(s["pos"], ship.global_position, Color(1.3, 0.9, 0.3, 0.6), 3.0, true)
			draw_arc(s["pos"], 16.0, -PI * 0.5, -PI * 0.5 + TAU * k, 24, Color(0.5, 1.1, 1.3), 2.5, true)
		var frac: float = s["hp"] / s["max_hp"]
		if frac < 1.0:
			draw_rect(Rect2(s["pos"] + Vector2(-18, -36), Vector2(36, 4)), Color(0, 0, 0, 0.75))
			draw_rect(Rect2(s["pos"] + Vector2(-18, -36), Vector2(36 * frac, 4)), Color(1.3, 0.85, 0.3))
