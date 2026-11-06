extends Node2D
## Statek matka obcej rasy - unosi się nad środkiem mapy. Strefa dokowania.

const DOCK_RADIUS := 170.0
## Obrona: Statek Matka co kilka sekund wypuszcza samonaprowadzającą rakietę w najbliższy myśliwiec.
const DEFENSE_RANGE := 700.0
const ROCKET_INTERVAL := 2.6
const ROCKET_SPEED := 640.0
const ROCKET_TURN := 3.2
const ROCKET_LIFE := 4.5
const ROCKET_BLAST := 46.0

## Kadłub: po zniszczeniu Nowego Jorku Ziemia od czasu do czasu atakuje Statek Matkę.
## Przy zerze wrak przez chwilę leży w gruzach (bez dokowania i obrony), potem drony go odbudowują.
const HIT_RADIUS := 120.0
const WRECK_TIME := 30.0
const REGEN := 0.01            # część kadłuba na sekundę, gdy nikt nie atakuje

signal destroyed
signal rebuilt

var time := 0.0
var highlight := false
var enemies: Node2D
var fx: Node2D
var fire_t := 1.5
var arm_k := 0
var rockets: Array = []        # {pos, vel, target, life, trail}
var hp := -1.0
var siege := false             # trwa atak Ziemian
var defense_slow := 1.0        # mnożnik odstępu rakiet obrony (szkolenie: obronę musi wesprzeć gracz)
var min_hp_frac := 0.0         # kadłub nie spada poniżej tej części (szkolenie: Matki nie da się zniszczyć)
var wrecked := false
var wreck_t := 0.0
var flash := 0.0
var body := {"pos": Vector2.ZERO, "hp": 1.0}   # cel dla wrogów i pocisków (jak inni sojusznicy)
var debris: Array = []         # odłamki wraku: {pos, vel, rot, spin, size}


func _ready() -> void:
	z_index = 4


func max_hp() -> float:
	return GameState.stat("mother_hp")


func _process(delta: float) -> void:
	time += delta
	if hp < 0.0:
		hp = max_hp()
	flash = maxf(0.0, flash - delta)
	if wrecked:
		wreck_t -= delta
		for d in debris:
			d["pos"] += d["vel"] * delta
			d["vel"] *= exp(-1.5 * delta)
			d["rot"] += d["spin"] * delta
		if fx and randf() < delta * 3.0:
			fx.explosion(global_position + Vector2.from_angle(randf() * TAU) * randf_range(20, 130), Color(1.2, 0.4, 0.9), false)
		if wreck_t <= 0.0:
			_rebuild()
	else:
		if not siege:
			hp = minf(max_hp(), hp + max_hp() * REGEN * delta)
		_defense(delta)
	body["pos"] = global_position
	body["hp"] = 0.0 if wrecked else hp
	if visible or not rockets.is_empty():
		queue_redraw()


## Trafienie od Ziemian (pociski myśliwców).
func hurt(_d: Dictionary, amount: float) -> void:
	if wrecked:
		return
	hp = maxf(hp - amount, max_hp() * min_hp_frac)
	flash = 0.12
	if hp <= 0.0:
		_wreck()


## Dokowanie: załoga od razu łata kadłub.
func repair() -> void:
	if not wrecked:
		hp = max_hp()


func _wreck() -> void:
	wrecked = true
	siege = false
	hp = 0.0
	wreck_t = WRECK_TIME
	rockets.clear()
	debris.clear()
	for k in 14:
		var a := randf() * TAU
		debris.append({"pos": Vector2.from_angle(a) * randf_range(20, 90), "vel": Vector2.from_angle(a) * randf_range(40, 160),
			"rot": randf() * TAU, "spin": randf_range(-1.5, 1.5), "size": randf_range(14, 34)})
	if fx:
		for k in 6:
			fx.explosion(global_position + Vector2.from_angle(randf() * TAU) * randf_range(0, 120), Color(1.3, 0.4, 1.0), true)
		fx.ring(global_position, Color(1.3, 0.5, 1.1, 0.9), 420.0, 0.8)
		fx.shake(22.0)
	Audio.play("explosion_big", 0.0, 4.0)
	destroyed.emit()


func _rebuild() -> void:
	wrecked = false
	hp = max_hp()
	debris.clear()
	if fx:
		fx.ring(global_position, Color(0.4, 1.2, 1.3, 0.9), 260.0, 0.6)
	Audio.play("research_done", 0.0)
	rebuilt.emit()


## Obrażenia rakiety rosną z mocą lasera gracza, żeby obrona nie traciła sensu w późniejszej grze.
func _rocket_damage() -> float:
	return maxf(70.0, GameState.stat("laser_dps") * 0.9)


func _defense(delta: float) -> void:
	if enemies == null:
		return
	fire_t -= delta
	if fire_t <= 0.0:
		var tgt: Dictionary = enemies.nearest(global_position, DEFENSE_RANGE)
		if tgt.is_empty():
			fire_t = 0.4
		else:
			fire_t = ROCKET_INTERVAL * defense_slow
			_launch(tgt)
	var k := rockets.size() - 1
	while k >= 0:
		var r: Dictionary = rockets[k]
		r["life"] -= delta
		var tgt: Dictionary = r["target"]
		if tgt.is_empty() or tgt.get("dead", false):
			# cel zniknął: rakieta szuka nowego w pobliżu
			tgt = enemies.nearest(r["pos"], 350.0)
			r["target"] = tgt
		var v: Vector2 = r["vel"]
		var speed := minf(ROCKET_SPEED, v.length() + 900.0 * delta)
		var dir := v.normalized()
		if not tgt.is_empty():
			var want: Vector2 = (tgt["pos"] - r["pos"]).normalized()
			var ang := dir.angle_to(want)
			dir = dir.rotated(clampf(ang, -ROCKET_TURN * delta, ROCKET_TURN * delta))
		r["vel"] = dir * speed
		r["pos"] += r["vel"] * delta
		var trail: Array = r["trail"]
		trail.append(r["pos"])
		if trail.size() > 14:
			trail.pop_front()
		var hit: bool = not tgt.is_empty() and r["pos"].distance_to(tgt["pos"]) < 26.0
		if hit or r["life"] <= 0.0:
			_explode(r["pos"])
			rockets.remove_at(k)
		k -= 1


func _launch(tgt: Dictionary) -> void:
	# rakiety wylatują po kolei z końców ramion
	var a := time * 0.15 + arm_k / 4.0 * TAU + PI / 8.0
	arm_k = (arm_k + 1) % 4
	var p := global_position + Vector2.from_angle(a) * 162.0
	rockets.append({"pos": p, "vel": Vector2.from_angle(a) * 180.0, "target": tgt, "life": ROCKET_LIFE, "trail": []})
	if fx:
		fx.ring(p, Color(1.3, 0.4, 1.1, 0.8), 30.0, 0.25)
	Audio.play("rocket_launch", 0.1, -8.0)


func _explode(p: Vector2) -> void:
	enemies.damage_in_radius(p, ROCKET_BLAST, _rocket_damage(), false)
	if fx:
		fx.explosion(p, Color(1.3, 0.35, 1.1), false)
		fx.ring(p, Color(1.3, 0.6, 1.2, 0.8), ROCKET_BLAST * 1.6, 0.3)
	Audio.play("blast_pop", 0.1, -6.0)


func _draw_rockets() -> void:
	for r in rockets:
		var trail: Array = r["trail"]
		for i in range(1, trail.size()):
			var t := float(i) / trail.size()
			draw_line(trail[i - 1] - global_position, trail[i] - global_position, Color(1.2, 0.35, 1.1, 0.6 * t), 1.0 + 3.0 * t, true)
		var p: Vector2 = r["pos"] - global_position
		var d: Vector2 = r["vel"].normalized()
		var n := d.orthogonal()
		var body := PackedVector2Array([p + d * 9.0, p - d * 6.0 + n * 4.0, p - d * 4.0, p - d * 6.0 - n * 4.0])
		draw_colored_polygon(body, Color(0.25, 0.05, 0.3))
		body.append(body[0])
		draw_polyline(body, Color(1.4, 0.6, 1.3), 1.6, true)
		draw_circle(p - d * 6.0, 2.5 + randf() * 1.5, Color(1.4, 1.1, 1.3))


func _draw() -> void:
	if wrecked:
		_draw_wreck()
		return
	_draw_ship()
	var frac := hp / maxf(1.0, max_hp())
	if frac < 0.999 or siege:
		# pasek kadłuba nad statkiem
		var br := Rect2(-110, -205, 220, 8)
		draw_rect(br.grow(2.0), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(br.position, Vector2(br.size.x * frac, br.size.y)), Color(1.3, 0.25, 0.4) if frac < 0.35 else Color(1.2, 0.4, 1.1))
		draw_rect(br.grow(2.0), Color(1.2, 0.4, 1.1, 0.8), false, 1.2)
	if flash > 0.0:
		draw_circle(Vector2.ZERO, 125.0, Color(1.4, 1.2, 1.4, flash * 1.5))


func _draw_wreck() -> void:
	draw_circle(Vector2.ZERO, 150.0, Color(0.05, 0.0, 0.08, 0.6))
	for d in debris:
		var xf := Transform2D(d["rot"], d["pos"])
		var s: float = d["size"]
		var p := PackedVector2Array([xf * Vector2(-s, -s * 0.4), xf * Vector2(s * 0.7, -s * 0.6), xf * Vector2(s, s * 0.3), xf * Vector2(-s * 0.4, s * 0.5)])
		draw_colored_polygon(p, Color(0.1, 0.0, 0.14, 0.95))
		p.append(p[0])
		draw_polyline(p, Color(0.8, 0.2, 0.6, 0.7 + 0.3 * sin(time * 9.0 + s)), 1.6, true)
	# odliczanie odbudowy
	var k := 1.0 - wreck_t / WRECK_TIME
	draw_arc(Vector2.ZERO, 60.0, -PI * 0.5, -PI * 0.5 + TAU * k, 48, Color(0.4, 1.2, 1.3, 0.8), 3.0, true)
	_draw_rockets()


func _draw_ship() -> void:
	var rot := time * 0.15
	# cień/projekcja na ziemię
	draw_circle(Vector2.ZERO, 150.0, Color(0.08, 0.0, 0.12, 0.55))
	# strefa dokowania
	var pulse := 0.5 + 0.5 * sin(time * 3.0)
	var dc := Color(0.15, 1.1, 1.3, 0.25 + 0.25 * pulse)
	if highlight:
		dc = Color(0.17, 1.21, 1.3, 0.6 + 0.4 * pulse)
	draw_arc(Vector2.ZERO, DOCK_RADIUS, 0.0, TAU, 96, dc, 2.0, true)
	for k in 12:
		var a := rot * -2.0 + k / 12.0 * TAU
		draw_arc(Vector2.ZERO, DOCK_RADIUS + 8.0, a, a + 0.25, 6, dc, 2.0, true)

	# zewnętrzny pierścień (ośmiokąt)
	var outer := PackedVector2Array()
	for k in 9:
		var a := rot + k / 8.0 * TAU
		outer.append(Vector2(cos(a), sin(a)) * 120.0)
	draw_colored_polygon(outer, Color(0.1, 0.0, 0.16, 0.92))
	draw_polyline(outer, Color(1.3, 0.2, 1.0), 3.0, true)
	# ramiona
	for k in 4:
		var a := rot + k / 4.0 * TAU + PI / 8.0
		var d := Vector2(cos(a), sin(a))
		var n := d.orthogonal()
		var arm := PackedVector2Array([d * 50.0 + n * 14.0, d * 150.0 + n * 6.0, d * 162.0, d * 150.0 - n * 6.0, d * 50.0 - n * 14.0])
		draw_colored_polygon(arm, Color(0.12, 0.0, 0.2, 0.95))
		draw_polyline(arm, Color(0.19, 0.93, 1.3), 2.0, true)
		draw_circle(d * 162.0, 5.0, Color(1.3, 0.43, 1.13) if int(time * 2.0 + k) % 2 == 0 else Color(1.0, 0.3, 0.9))
	# środek
	var inner := PackedVector2Array()
	for k in 7:
		var a := -rot * 1.5 + k / 6.0 * TAU
		inner.append(Vector2(cos(a), sin(a)) * 62.0)
	draw_colored_polygon(inner, Color(0.18, 0.02, 0.25, 0.95))
	draw_polyline(inner, Color(1.3, 0.84, 0.23), 2.5, true)
	draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 48, Color(1.3, 0.25, 1.1), 2.0, true)
	draw_circle(Vector2.ZERO, 14.0 + pulse * 3.0, Color(0.8 + 0.3 * pulse, 0.3, 1.2))
	draw_circle(Vector2.ZERO, 6.0, Color(1.3, 1.3, 1.3))
	_draw_rockets()
