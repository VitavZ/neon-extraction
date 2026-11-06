extends Node2D
## Myśliwce Imperium (najwyżej 3): czekają w hangarze. Klawisz wezwania (domyślnie 4) ściąga je z nadprzestrzeni
## tuż obok gracza, gdzie lecą w szyku i strzelają do rakiet i myśliwców w pobliżu. Drugie wciśnięcie odsyła je do hangaru.
## Wrogowie mogą je zestrzelić; zestrzelone wracają do służby po dokowaniu.

signal lost

const MAX_SHIPS := 3
const ENGAGE := 650.0           # jak daleko od gracza szukają wrogów
const ESCORT := [Vector2(-70, -60), Vector2(-70, 60), Vector2(-120, 0)]
const HIT_RADIUS := 18.0

var world: Node2D
var ship: Node2D
var mothership: Node2D
var enemies: Node2D
var fx: Node2D
var wings: Array = []           # {pos, vel, rot, cd, orbit, hp, max_hp, flash}
var called := false
var returning := false
var down := 0                   # zestrzelone w tym locie
var tracers: Array = []         # {a, b, life}
var time := 0.0


func _ready() -> void:
	z_index = 7


func count() -> int:
	return mini(int(GameState.stat("wing_count")), MAX_SHIPS)


## Ile myśliwców jest jeszcze sprawnych w tym locie.
func ready_count() -> int:
	return maxi(0, count() - down)


## Wezwanie albo odesłanie. Zwraca komunikat dla gracza.
func toggle() -> String:
	if count() <= 0:
		return ""
	if called and not returning:
		returning = true
		return "Myśliwce Imperium wracają do hangaru."
	if ready_count() <= 0:
		return "Wszystkie myśliwce Imperium zestrzelone. Naprawa w hangarze po dokowaniu."
	called = true
	returning = false
	if wings.is_empty():
		# wyskakują z nadprzestrzeni tuż za graczem
		var back := Vector2.from_angle(ship.rotation + PI)
		var hp := GameState.stat("wing_hp")
		for k in ready_count():
			var p: Vector2 = ship.global_position + back.rotated((k - 1) * 0.35) * 520.0
			var v := -back * GameState.stat("wing_speed")
			wings.append({"pos": p, "vel": v, "rot": v.angle(), "cd": randf(), "orbit": 1.0 if k % 2 == 0 else -1.0,
				"hp": hp, "max_hp": hp, "flash": 0.0})
			if fx:
				fx.ring(p, Color(1.3, 0.9, 0.3, 0.8), 50.0, 0.35)
	return "Myśliwce Imperium w drodze! (%d)" % wings.size()


func reset() -> void:
	called = false
	returning = false
	down = 0
	wings.clear()
	tracers.clear()


## Trafienie od wroga (pocisk, wieżyczka).
func hurt(w: Dictionary, amount: float) -> void:
	if w.get("gone", false):
		return
	w["hp"] -= amount
	w["flash"] = 0.15
	if w["hp"] > 0.0:
		return
	w["gone"] = true
	wings.erase(w)
	down += 1
	if fx:
		fx.explosion(w["pos"], Color(1.3, 0.8, 0.3), true)
	Audio.play("explosion", 0.1)
	lost.emit()
	if wings.is_empty():
		called = false
		returning = false


func _process(delta: float) -> void:
	time += delta
	for tr in tracers:
		tr["life"] -= delta
	if not tracers.is_empty():
		tracers = tracers.filter(func(tr): return tr["life"] > 0.0)
	if not called or ship == null or ship.docked:
		if visible:
			queue_redraw()
		return
	var speed := GameState.stat("wing_speed")
	var sp: Vector2 = ship.global_position
	var home := true
	for k in wings.size():
		var w: Dictionary = wings[k]
		w["flash"] = maxf(0.0, w["flash"] - delta)
		var goal: Vector2
		var target: Dictionary = {}
		var missile: Dictionary = {}
		if returning:
			# odlatują od gracza i skaczą do hangaru poza ekranem
			goal = w["pos"] + (w["pos"] - sp).normalized() * 400.0
			if w["pos"].distance_to(sp) < 1100.0:
				home = false
		else:
			home = false
			missile = world.nearest_missile(sp, ENGAGE)
			if missile.is_empty():
				target = enemies.nearest(sp, ENGAGE)
			if not missile.is_empty():
				goal = missile["pos"]
			elif not target.is_empty():
				# krążą wokół celu, każdy w swoją stronę
				var off: Vector2 = (w["pos"] - target["pos"]).normalized().rotated(0.9 * w["orbit"]) * 170.0
				goal = target["pos"] + off
			else:
				goal = sp + ESCORT[k % ESCORT.size()].rotated(ship.rotation)
		var to: Vector2 = goal - w["pos"]
		var want := to.limit_length(speed) if to.length() > 12.0 else Vector2.ZERO
		if target.is_empty() and missile.is_empty() and not returning:
			want = to.normalized() * minf(speed, to.length() * 4.0)
		w["vel"] = w["vel"].lerp(want, 1.0 - exp(-5.0 * delta))
		w["pos"] += w["vel"] * delta
		var aim: Vector2 = w["vel"]
		var tpos := Vector2.INF
		if not missile.is_empty():
			tpos = missile["pos"]
		elif not target.is_empty():
			tpos = target["pos"]
		if tpos != Vector2.INF:
			aim = tpos - w["pos"]
		if aim.length() > 1.0:
			w["rot"] = lerp_angle(w["rot"], aim.angle(), 1.0 - exp(-10.0 * delta))
		# ogień
		w["cd"] -= delta
		if tpos != Vector2.INF and w["cd"] <= 0.0 and w["pos"].distance_to(tpos) < 520.0:
			w["cd"] = maxf(0.15, GameState.stat("wing_interval"))
			var dmg := GameState.stat("wing_damage")
			if not missile.is_empty():
				world.damage_missile(missile, dmg)
			else:
				enemies.damage_fighter(target, dmg)
			tracers.append({"a": w["pos"] + Vector2.from_angle(w["rot"]) * 14.0, "b": tpos, "life": 0.1})
			Audio.play("drone_shot", 0.15, -6.0)
	if returning and home:
		var lost_now := down
		reset()
		down = lost_now
	if visible:
		queue_redraw()


func _draw() -> void:
	for tr in tracers:
		var f: float = tr["life"] / 0.1
		draw_line(tr["a"], tr["b"], Color(1.3, 0.9, 0.35, 0.35 * f), 4.0, true)
		draw_line(tr["a"], tr["b"], Color(1.4, 1.3, 1.0, f), 1.4, true)
	if not called or ship == null or ship.docked:
		return
	for w in wings:
		var xf := Transform2D(w["rot"], w["pos"])
		# złoty pierścień: od razu widać, że to sojusznik
		draw_arc(w["pos"], 22.0, 0.0, TAU, 24, Color(1.3, 0.9, 0.3, 0.3), 1.5, true)
		var body := PackedVector2Array([Vector2(18, 0), Vector2(0, -6), Vector2(-8, -15), Vector2(-12, -12), Vector2(-7, 0), Vector2(-12, 12), Vector2(-8, 15), Vector2(0, 6)])
		var pts := xf * body
		draw_colored_polygon(pts, Color(0.18, 0.11, 0.02, 0.95))
		pts.append(pts[0])
		draw_polyline(pts, Color(1.5, 1.4, 1.2) if w["flash"] > 0.0 else Color(1.35, 0.9, 0.3), 2.0, true)
		draw_circle(xf * Vector2(6, 0), 2.5, Color(0.4, 1.1, 1.3))
		if w["vel"].length() > 60.0:
			draw_line(xf * Vector2(-8, 0), xf * Vector2(-18 - randf() * 6.0, 0), Color(1.2, 0.6, 0.25), 2.0, true)
		var frac: float = w["hp"] / w["max_hp"]
		if frac < 1.0:
			var p: Vector2 = w["pos"] + Vector2(-16, -28)
			draw_rect(Rect2(p, Vector2(32, 4)), Color(0, 0, 0, 0.75))
			draw_rect(Rect2(p, Vector2(32 * frac, 4)), Color(1.3, 0.85, 0.3))
