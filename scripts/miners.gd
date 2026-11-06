extends Node2D
## Statki Wydobywcze (Imperium): sojusznicze statki, które same szukają wybranego surowca w okolicy
## Statku Matki, wycinają go i dowożą do magazynu. Pracują, gdy gracz jest w locie.

const MAX_SHIPS := 6
const RANGE := 3600.0         # jak daleko od Statku Matki szukają złóż (piksele)
const CARGO := 24
const HOVER := 70.0
const HIT_RADIUS := 20.0
## W locie statki trzymają się tak daleko od wieżyczek (zasięg wieżyczki + zapas).
const SAFE := 560.0

signal lost
## Surowce, które można przydzielić statkom (kolejność wyboru w Imperium).
## Złom i metal pochodzą tylko z miast, a statki trzymają się od miast z daleka.
const RESOURCES := ["wood", "stone", "biomass", "water", "saltwater", "sand", "copper", "iron", "gold", "uranium", "neonite"]

var world: Node2D
var ship: Node2D
var mothership: Node2D
var fx: Node2D
var miners: Array = []        # {pos, vel, rot, state, target, cargo, t}
var time := 0.0


func _ready() -> void:
	z_index = 6


func count() -> int:
	return mini(int(GameState.stat("miner_count")), MAX_SHIPS)


func _process(delta: float) -> void:
	time += delta
	if ship == null or ship.docked:
		return
	var n := count()
	while miners.size() < n:
		miners.append(_fresh())
	while miners.size() > n:
		miners.pop_back()
	var taken := {}
	for m in miners:
		if m["target"] >= 0 and not m["dead"]:
			taken[m["target"]] = true
	for k in miners.size():
		if not GameState.miner_res[k] in RESOURCES:
			GameState.miner_res[k] = "wood"
		var m: Dictionary = miners[k]
		if m["dead"]:
			continue
		m["flash"] = maxf(0.0, m["flash"] - delta)
		_update(m, String(GameState.miner_res[k]), taken, delta)
	if visible:
		queue_redraw()


func _fresh() -> Dictionary:
	var hp := GameState.stat("miner_hp")
	return {"pos": mothership.position + Vector2.from_angle(randf() * TAU) * 60.0, "vel": Vector2.ZERO, "rot": 0.0,
		"state": "seek", "target": -1, "cargo": 0, "t": 0.0, "hp": hp, "max_hp": hp, "flash": 0.0, "dead": false}


## Po dokowaniu zniszczone statki wracają z hangaru, a uszkodzone są naprawione.
func revive() -> void:
	for k in miners.size():
		if miners[k]["dead"]:
			miners[k] = _fresh()
		else:
			miners[k]["max_hp"] = GameState.stat("miner_hp")
			miners[k]["hp"] = miners[k]["max_hp"]


## Sprawne statki (cele dla wrogów).
func alive() -> Array:
	return miners.filter(func(m): return not m["dead"])


## Trafienie od wroga. Zniszczony statek traci ładunek.
func hurt(m: Dictionary, amount: float) -> void:
	if m["dead"]:
		return
	m["hp"] -= amount
	m["flash"] = 0.15
	if m["hp"] > 0.0:
		return
	m["dead"] = true
	m["cargo"] = 0
	m["target"] = -1
	if fx:
		fx.explosion(m["pos"], Color(1.3, 0.8, 0.3), true)
	Audio.play("explosion", 0.1)
	lost.emit()


func _update(m: Dictionary, res: String, taken: Dictionary, delta: float) -> void:
	var speed := GameState.stat("miner_speed")
	var mother: Vector2 = mothership.position
	var goal: Vector2 = mother
	match m["state"]:
		"seek":
			taken.erase(m["target"])
			m["target"] = world.find_resource_tile(res, m["pos"], mother, RANGE, taken)
			if m["target"] < 0:
				m["state"] = "idle"
				m["t"] = 3.0
			else:
				taken[m["target"]] = true
				m["state"] = "fly"
		"idle":
			goal = mother + Vector2.from_angle(time * 0.6 + m["rot"]) * 160.0
			m["t"] -= delta
			if m["t"] <= 0.0:
				m["state"] = "return" if m["cargo"] > 0 else "seek"
		"fly", "mine":
			var tgt: int = m["target"]
			if not world.miner_match(tgt, res):
				m["state"] = "seek"
				return
			goal = world.idx_center(tgt)
			if m["state"] == "fly" and m["pos"].distance_to(goal) < HOVER + 20.0:
				m["state"] = "mine"
			if m["state"] == "mine":
				var drops: Dictionary = world.miner_hit(tgt, GameState.stat("miner_dps") * delta)
				if not drops.is_empty():
					var got := int(round(float(drops.get(res, 0)) * GameState.stat("miner_yield")))
					if got > 0:
						m["cargo"] += got
						if fx:
							fx.pickup(world.idx_center(tgt), GameState.RES_COLORS[res], mini(got, 3))
					# odsłonięte złoże tego samego surowca kopie dalej, inaczej szuka nowego celu
					if m["cargo"] >= CARGO:
						m["state"] = "return"
					elif not world.miner_match(tgt, res):
						m["state"] = "seek"
		"return":
			if m["pos"].distance_to(mother) < 150.0:
				_deliver(m, res)
				m["state"] = "seek"
	# lot: przy celu zwalnia i zawisa obok kafelka
	var to: Vector2 = goal - m["pos"]
	var stop := HOVER if m["state"] in ["fly", "mine"] else 0.0
	var want := Vector2.ZERO
	if to.length() > stop:
		want = to.normalized() * speed * clampf((to.length() - stop) / 160.0, 0.25, 1.0)
	# omija strefy wieżyczek: każda w pobliżu odpycha statek
	var push := Vector2.ZERO
	for ti in world.turrets_in_rect(Rect2(m["pos"], Vector2.ZERO).grow(SAFE)):
		var away: Vector2 = m["pos"] - world.idx_center(ti)
		var l := away.length()
		if l < SAFE:
			push += away / maxf(l, 1.0) * (SAFE - l) / SAFE
	if push != Vector2.ZERO:
		want = (want + push.normalized() * speed * 1.3).limit_length(speed)
	m["vel"] = m["vel"].lerp(want, 1.0 - exp(-4.0 * delta))
	m["pos"] += m["vel"] * delta
	var face: Vector2 = to if m["state"] == "mine" else m["vel"]
	if face.length() > 1.0:
		m["rot"] = lerp_angle(m["rot"], face.angle(), 1.0 - exp(-8.0 * delta))


func _deliver(m: Dictionary, res: String) -> void:
	var n: int = m["cargo"]
	m["cargo"] = 0
	if n <= 0:
		return
	GameState.bank[res] = int(GameState.bank.get(res, 0)) + n
	GameState.collected[res] = int(GameState.collected.get(res, 0)) + n
	GameState.bank_changed.emit()
	GameState.refresh_quests()
	if fx:
		fx.float_text(mothership.position + Vector2(0, -40), "+%d %s" % [n, GameState.RES_NAMES[res]], GameState.RES_COLORS[res])
		fx.ring(mothership.position, Color(1.0, 0.8, 0.3, 0.7), 60.0, 0.35)


func _draw() -> void:
	if ship == null or ship.docked:
		return
	for k in miners.size():
		var m: Dictionary = miners[k]
		if m["dead"]:
			continue
		var res := String(GameState.miner_res[k])
		var rc: Color = GameState.RES_COLORS[res]
		var p: Vector2 = m["pos"]
		if m["state"] == "mine" and m["target"] >= 0:
			var tp: Vector2 = world.idx_center(m["target"])
			var flick := 0.8 + 0.2 * sin(time * 40.0 + k)
			draw_line(p, tp, Color(1.3, 0.85, 0.3, 0.2 * flick), 6.0, true)
			draw_line(p, tp, Color(1.4, 1.0, 0.5, 0.9 * flick), 1.6, true)
			draw_circle(tp, 4.0, Color(1.4, 0.9, 0.4, 0.6))
		var xf := Transform2D(m["rot"], p)
		var hull := PackedVector2Array([Vector2(16, 0), Vector2(6, -10), Vector2(-12, -10), Vector2(-16, 0), Vector2(-12, 10), Vector2(6, 10)])
		var pts := xf * hull
		draw_colored_polygon(pts, Color(0.16, 0.1, 0.02, 0.95))
		pts.append(pts[0])
		draw_polyline(pts, Color(1.5, 1.4, 1.2) if m["flash"] > 0.0 else Color(1.3, 0.85, 0.3), 1.8, true)
		var hf: float = m["hp"] / m["max_hp"]
		if hf < 1.0:
			draw_rect(Rect2(p + Vector2(-16, -32), Vector2(32, 4)), Color(0, 0, 0, 0.75))
			draw_rect(Rect2(p + Vector2(-16, -32), Vector2(32 * hf, 4)), Color(1.3, 0.85, 0.3))
		draw_circle(xf * Vector2(2, 0), 3.5, rc)
		if m["vel"].length() > 40.0:
			draw_line(xf * Vector2(-16, 0), xf * Vector2(-24 - randf() * 5.0, 0), Color(1.0, 0.6, 0.25), 2.0, true)
		# ładunek: łuk wokół statku
		var fr := float(m["cargo"]) / CARGO
		if fr > 0.0:
			draw_arc(p, 22.0, -PI * 0.5, -PI * 0.5 + TAU * fr, 24, Color(rc.r, rc.g, rc.b, 0.85), 2.0, true)
