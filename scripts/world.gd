extends "res://scripts/world/overlay.gd"
## Mapa USA: 9 sektorów (3x3) po 160x160 kafelków połączonych w jeden świat (patrz sectors.gd).
## Teren z us_map_data.gd, rysowanie wektorowe (w chunkach), niszczenie kafelków,
## złoża pod powierzchnią, wieżyczki obronne Ziemian i ich pociski.
## Ten plik: generowanie, wczytanie/zapis i główna pętla (_process: wieżyczki, pociski, odbudowa).
## Reszta w scripts/world/ (łańcuch extends: base -> art -> damage -> defense -> overlay -> ten plik).


func _ready() -> void:
	# OPTYMALIZACJA: mapa jest podzielona na fragmenty 8x8 kafelków (osobne węzły).
	# Godot zapamiętuje polecenia rysowania każdego węzła, więc fragment jest
	# przerysowywany tylko gdy zmieni się któryś z jego kafelków, a fragmenty
	# poza ekranem są automatycznie pomijane przy renderowaniu. Świat jest duży,
	# więc siatki powstają dopiero w pobliżu kamery i są zwalniane, gdy się oddali.
	chunk_ready.resize(CHUNK_COLS * CHUNK_ROWS)
	chunk_ready.fill(0)
	for cy in CHUNK_ROWS:
		for cx in CHUNK_COLS:
			var painter := Node2D.new()
			painter.name = "Chunk_%d_%d" % [cx, cy]
			add_child(painter)
			painter.draw.connect(_draw_chunk.bind(painter, cx, cy))
			chunks.append(painter)
	scan_layer = Node2D.new()
	scan_layer.z_index = 1
	add_child(scan_layer)
	scan_layer.draw.connect(_draw_scan)
	overlay = Node2D.new()
	overlay.z_index = 3
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)


# =====================================================================
# GENEROWANIE
# =====================================================================


func generate(seed_value: int) -> void:
	var total := TOTAL
	# teren jest stały (prawdziwa mapa USA), losowe są tylko złoża i wieżyczki
	surface = MapData.surface(total)
	city_near.clear()
	playable = TOTAL
	for s in Sectors.LIST.size():
		if Sectors.is_void(s):
			playable -= Sectors.SIZE * Sectors.SIZE
	deposit.resize(total)
	layer.resize(total)
	hp.resize(total)
	max_hp.resize(total)
	turrets.clear()
	ally_turrets.clear()
	turret_buckets.clear()
	bullets.clear()
	missiles.clear()
	abducted.resize(total)
	abducted.fill(0)

	dock_cells.clear()
	city_cells.clear()
	for s in Sectors.LIST:
		dock_cells.append(Sectors.cell_of(s["dock_lonlat"]))
		city_cells.append(Sectors.cell_of(s["city_lonlat"]))
	landmark_cells.clear()
	for lm in Sectors.LANDMARKS:
		landmark_cells.append(Sectors.cell_of(lm["lonlat"]))
	_stamp_metros()
	_stamp_landmarks()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 3
	# osobny generator: główny musi dawać te same złoża co w istniejących zapisach
	var kind_rng := RandomNumberGenerator.new()
	kind_rng.seed = seed_value * 13 + 5

	for y in H:
		for x in N:
			var i := y * N + x
			var t: int = surface[i]
			layer[i] = L_SURFACE
			var d := danger(x, y)
			hp[i] = TILE_DEFS[t]["hp"] * (1.0 + d / 90.0)
			max_hp[i] = hp[i]

			# złoża pod powierzchnią
			var chance := 0.05
			match t:
				MOUNTAIN: chance = 0.24
				SNOW: chance = 0.3
				DEEP: chance = 0.08
				SAND: chance = 0.08
				CITY, METRO: chance = 0.04
				CAPITOL, PENTAGON: chance = 0.08
			deposit[i] = 0
			# ten sam rzut co dawniej (bez zmiany kolejności losowania), a tuż nad progiem: dodatkowa miedź
			var dr := rng.randf()
			if dr < chance:
				deposit[i] = _roll_deposit(rng, d)
			elif dr < chance * COPPER_BONUS:
				deposit[i] = 1

			# wieżyczki obronne: wokół miejsc postoju Matki w każdym sektorze jest bezpiecznie
			var guard := _landmark_guard(x, y)
			if _dock_distance(x, y) / Sectors.SCALE > 13.0 or guard > 0.0:
				var tc := 0.0
				if t == CITY:
					tc = 0.06 + clampf((d - 13.0) / 50.0, 0.0, 1.0) * 0.3
				elif t == METRO:
					tc = 0.14 + clampf((d - 13.0) / 50.0, 0.0, 1.0) * 0.3
				elif (t == MOUNTAIN or t == SNOW) and d > 30.0:
					tc = 0.03
				# obiekty specjalne: gęsty pierścień wieżyczek, w samym kompleksie prawie co druga
				if t == CAPITOL or t == PENTAGON:
					tc = 0.45
				elif guard > 0.0 and t > RIVER:
					tc = maxf(tc, 0.12 + 0.2 * guard)
				if rng.randf() < tc:
					turrets[i] = {"cd": rng.randf_range(0.5, 2.0), "angle": rng.randf() * TAU}
					var missile_chance := 0.4 if guard > 0.0 else MISSILE_TURRET_CHANCE
					if (t == CITY or t == METRO or guard > 0.0) and (d > MISSILE_TURRET_MIN_DANGER or guard > 0.0) and kind_rng.randf() < missile_chance:
						turrets[i]["kind"] = "missile"
						turrets[i]["cd"] = kind_rng.randf_range(1.0, 5.0)
					var key := _bucket_key(x, y)
					if not turret_buckets.has(key):
						turret_buckets[key] = []
					turret_buckets[key].append(i)

	_count_metros()
	_build_minimap()
	_redraw_all()


func export_save() -> Dictionary:
	return {
		"format": 3, "w": N, "h": H, "geo": 3,
		"layer": _pack(layer),
		"hp": _pack(hp.to_byte_array()),
		"abducted": _pack(abducted),
		"allies": ally_turrets.keys(),
	}


func apply_save(data: Dictionary) -> void:
	# zapisy sprzed mapy USA nie pasują do nowego świata
	var fmt := int(data.get("format", 1))
	if fmt != 2 and fmt != 3:
		return
	# format 2 to mapa 384x256 sprzed powiększenia sektorów
	var ow := int(data.get("w", 384))
	var oh := int(data.get("h", 256))
	var l := _unpack(data, "layer", ow * oh)
	var h := _unpack(data, "hp", ow * oh * 4).to_float32_array()
	if l.size() != ow * oh or h.size() != ow * oh:
		return
	var a := _unpack(data, "abducted", ow * oh)
	if int(data.get("geo", 1)) >= 3 and ow == N and oh == H:
		layer = l
		hp = h
		if a.size() == TOTAL:
			abducted = a
		for k in data.get("allies", []):
			var ai := int(k)
			if ai >= 0 and ai < TOTAL and layer[ai] == L_IMPERIAL:
				ally_turrets[ai] = {"cd": randf(), "angle": randf() * TAU}
	else:
		_geo_resample(l, h, a, ow, oh, data.get("allies", []))
	_count_metros()
	imperial_count = 0
	devastated_count = 0
	imperial_list.clear()
	for i in TOTAL:
		if layer[i] == L_IMPERIAL:
			imperial_count += 1
			imperial_list.append(i)
		elif layer[i] != L_SURFACE:
			devastated_count += 1
		if layer[i] == L_DEPOSIT:
			max_hp[i] = DEP_DEFS[deposit[i]]["hp"] * (1.0 + danger(i % N, i / N) / 90.0)
		if layer[i] != L_SURFACE:
			turrets.erase(i)
	_build_minimap()
	_redraw_all()


func _process(delta: float) -> void:
	time += delta
	_bio_process(delta)
	_update_chunks(delta)
	_flush_dirty_chunks()
	for i in dmg_acc.keys():
		dmg_acc[i][1] += delta
		if dmg_acc[i][1] >= 0.14:
			_flush_damage(i)
	for i in recent_hits.keys():
		recent_hits[i] -= delta
		if recent_hits[i] <= 0.0 or not is_minable(i):
			recent_hits.erase(i)
	for i in tile_flash.keys():
		tile_flash[i] -= delta
		if tile_flash[i] <= -0.05:
			tile_flash.erase(i)
	target_timer -= delta
	if target_timer <= 0.0:
		target_idx = -1
	var active: bool = ship != null and not ship.docked and not ship.dead
	# w czasie walki mapa lekko gaśnie, a wrogowie i pociski wybijają się na pierwszy plan
	var hot: bool = active and (not missiles.is_empty() or (enemies != null and enemies.hostile_count() > 0))
	combat_k = move_toward(combat_k, 1.0 if hot else 0.0, delta * (2.0 if hot else 0.8))
	# szybki lot: od ok. połowy prędkości maksymalnej mapa zaczyna przygasać
	var sf: float = ship.vel.length() / maxf(1.0, GameState.stat("max_speed")) if active else 0.0
	speed_k = move_toward(speed_k, clampf((sf - 0.5) / 0.5, 0.0, 1.0), delta * 1.5)
	if ship != null:
		var sp: Vector2 = ship.global_position
		var friends := _friendlies() if active else []
		for i in turrets_in_rect(Rect2(sp, Vector2.ZERO).grow(MISSILE_RANGE + T)):
			var t: Dictionary = turrets[i]
			var tp := idx_center(i)
			var to := sp - tp
			if t.get("kind", "") == "missile":
				_process_missile_turret(i, t, tp, to, active, delta)
				continue
			# cel: gracz, a gdy jest poza zasięgiem - najbliższy sojusznik
			var aim := Vector2.INF
			var aim_vel := Vector2.ZERO
			if active and to.length() < TURRET_RANGE:
				aim = sp
				aim_vel = ship.vel
			elif active:
				var bd := TURRET_RANGE
				for fr in friends:
					var dd: float = fr[2]["pos"].distance_to(tp)
					if dd < bd:
						bd = dd
						aim = fr[2]["pos"]
						aim_vel = fr[2].get("vel", Vector2.ZERO)
			if aim != Vector2.INF:
				var ta := aim - tp
				t["angle"] = lerp_angle(t["angle"], ta.angle(), 5.0 * delta)
				t["cd"] -= delta
				if t["cd"] <= 0.0:
					var d := danger(i % N, i / N)
					t["cd"] = 1.7
					# lekkie wyprzedzanie celu
					var lead: Vector2 = aim + aim_vel * (ta.length() / BULLET_SPEED) * 0.5
					var dir := (lead - tp).normalized()
					bullets.append({"pos": tp + dir * 18.0, "vel": dir * BULLET_SPEED, "life": 3.0,
						"dmg": 8.0 * (1.0 + d / 70.0)})
			else:
				t["angle"] += delta * 0.4
		for b in bullets:
			b["pos"] += b["vel"] * delta
			b["life"] -= delta
			if not active:
				continue
			if b["pos"].distance_to(sp) < 16.0:
				ship.take_damage(b["dmg"])
				b["life"] = 0.0
				continue
			for fr in friends:
				if b["pos"].distance_to(fr[2]["pos"]) < fr[0]:
					fr[1].hurt(fr[2], b["dmg"])
					b["life"] = 0.0
					break
		bullets = bullets.filter(func(b): return b["life"] > 0.0)
	if not active and bullets.size() > 0 and ship != null and ship.docked:
		bullets.clear()
	_process_missiles(delta, active)
	_process_allies(delta, active)

	# wysyłanie całego obrazu do karty graficznej 5 razy na sekundę w zupełności wystarcza
	minimap_cd -= delta
	if _minimap_dirty and minimap_cd <= 0.0:
		minimap_cd = 0.2
		minimap_tex.update(minimap_img)
		_minimap_dirty = false
	# w doku mapa jest schowana pod ekranem ulepszeń
	if overlay.visible:
		overlay.queue_redraw()
		scan_layer.queue_redraw()


# =====================================================================
# RAKIETY SAMONAPROWADZAJĄCE
# =====================================================================
