extends Node2D
## Myśliwce towarzyszące (Zbrojownia): lecą w szyku tuż przy statku gracza i celują tam, gdzie kursor.
## Gdy gracz strzela laserem, strzelają razem z nim własną wiązką o części mocy lasera (escort_power).
## Nie mają paliwa ani własnych silników - po prostu trzymają się statku. Wrogie pociski mogą je zestrzelić;
## zestrzelony wraca do służby po dokowaniu.

signal lost

const MAX_SHIPS := 2
const SLOTS := [Vector2(-34, -52), Vector2(-34, 52)]
const HIT_RADIUS := 15.0
const FOLLOW := 9.0

var world: Node2D
var ship: Node2D
var enemies: Node2D
var fx: Node2D
var escorts: Array = []      # {pos, rot, hp, max_hp, flash, slot, beam, hit}
var down := 0
var time := 0.0


func _ready() -> void:
	z_index = 7
	# po statku gracza: wiązki celują w jego punkt trafienia z tej samej klatki
	process_priority = 10


func count() -> int:
	return mini(int(GameState.stat("escort_count")), MAX_SHIPS)


func max_hp() -> float:
	return GameState.stat("max_hull") * GameState.stat("escort_hp")


func alive() -> Array:
	return escorts


## Wylot: wszystkie myśliwce sprawne i w szyku.
func reset() -> void:
	escorts.clear()
	down = 0


func _spawn() -> void:
	var used := {}
	for e in escorts:
		used[e["slot"]] = true
	for k in count():
		if escorts.size() + down >= count():
			return
		if used.has(k):
			continue
		var hp := max_hp()
		var p: Vector2 = ship.global_position + (SLOTS[k] as Vector2).rotated(ship.rotation)
		escorts.append({"pos": p, "rot": ship.rotation, "hp": hp, "max_hp": hp, "flash": 0.0, "slot": k,
			"beam": Vector2.INF, "hit": false})
		used[k] = true


## Trafienie od wroga (pocisk wieżyczki lub myśliwca).
func hurt(e: Dictionary, amount: float) -> void:
	if e.get("gone", false):
		return
	e["hp"] -= amount * (1.0 - clampf(GameState.stat("armor"), 0.0, 0.8))
	e["flash"] = 0.15
	if e["hp"] > 0.0:
		return
	e["gone"] = true
	escorts.erase(e)
	down += 1
	if fx:
		fx.explosion(e["pos"], Color(1.0, 0.4, 0.9), true)
	Audio.play("explosion", 0.1)
	lost.emit()


func _process(delta: float) -> void:
	time += delta
	if ship == null or ship.docked or ship.dead:
		if not escorts.is_empty() and ship != null and ship.dead:
			escorts.clear()
		queue_redraw()
		return
	_spawn()
	var sp: Vector2 = ship.global_position
	var mouse := get_global_mouse_position()
	var power := GameState.stat("laser_dps") * GameState.stat("escort_power")
	for e in escorts:
		e["flash"] = maxf(0.0, e["flash"] - delta)
		# szyk: miejsce przy boku statku, obrócone razem z nim
		var goal: Vector2 = sp + (SLOTS[int(e["slot"])] as Vector2).rotated(ship.rotation)
		e["pos"] = e["pos"].lerp(goal, 1.0 - exp(-FOLLOW * delta))
		var nose: Vector2 = e["pos"] + Vector2.from_angle(e["rot"]) * 12.0
		var aim: Vector2 = mouse - e["pos"]
		if aim.length() > 4.0:
			e["rot"] = lerp_angle(e["rot"], aim.angle(), 1.0 - exp(-14.0 * delta))
		e["beam"] = Vector2.INF
		e["hit"] = false
		if ship.firing:
			# wiązka zawsze kończy się tam, gdzie wiązka gracza (jej długość dopasowuje się do niej),
			# a obrażenia zadaje w tym samym punkcie
			var tgt: Vector2 = ship.beam_target
			var dmg := power * delta
			var dir := (tgt - nose).normalized()
			var stop: Vector2 = world.missile_laser_hit(tgt - dir * 6.0, tgt + dir * 6.0, dmg)
			if stop == Vector2.INF and enemies:
				stop = enemies.laser_hit(tgt - dir * 6.0, tgt + dir * 6.0, dmg * GameState.stat("fighter_damage"))
			if stop != Vector2.INF:
				e["hit"] = true
			else:
				e["hit"] = world.laser_hit(tgt, dmg) >= 0
			e["beam"] = tgt
	queue_redraw()


func _draw() -> void:
	if ship == null or ship.docked or ship.dead:
		return
	for e in escorts:
		var xf := Transform2D(e["rot"], e["pos"])
		var b: Vector2 = e["beam"]
		if b != Vector2.INF:
			var a: Vector2 = xf * Vector2(12, 0)
			var flick := 0.9 + 0.1 * sin(time * 40.0 + e["slot"])
			draw_line(a, b, Color(1.0, 0.3, 0.8, 0.12 * flick), 5.0, true)
			draw_line(a, b, Color(1.0, 0.55, 0.9, 0.7), 1.4, true)
			draw_circle(b, 3.0, Color(1.0, 0.45, 0.85, 0.45) if e["hit"] else Color(0.8, 0.3, 0.7, 0.2))
		# mniejszy, smuklejszy kuzyn statku gracza
		var body := PackedVector2Array([Vector2(13, 0), Vector2(-3, -9), Vector2(-9, -7), Vector2(-5, 0), Vector2(-9, 7), Vector2(-3, 9)])
		var pts := xf * body
		draw_colored_polygon(pts, Color(0.12, 0.02, 0.16, 0.95))
		pts.append(pts[0])
		var line := Color(1.5, 1.3, 1.4) if e["flash"] > 0.0 else Color(1.1, 0.4, 1.2)
		draw_polyline(pts, line, 1.8, true)
		draw_circle(xf * Vector2(3, 0), 2.2, Color(0.4, 1.2, 1.4))
		draw_line(xf * Vector2(-6, 0), xf * Vector2(-12 - randf() * 5.0, 0), Color(0.4, 1.0, 1.4, 0.8), 1.6, true)
		var frac: float = e["hp"] / maxf(1.0, e["max_hp"])
		if frac < 1.0:
			var p: Vector2 = e["pos"] + Vector2(-13, -22)
			draw_rect(Rect2(p, Vector2(26, 4)), Color(0, 0, 0, 0.75))
			draw_rect(Rect2(p, Vector2(26 * frac, 4)), Color(1.1, 0.4, 1.2))
