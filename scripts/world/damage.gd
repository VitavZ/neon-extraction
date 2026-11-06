extends "res://scripts/world/art.gd"
## Mapa świata, część 3/5: niszczenie kafelków (laser, rakiety, statki wydobywcze), odbudowa, ekspansja Imperium,
## odświeżanie kawałków mapy.


## Obrażenia od statku wydobywczego; zwraca łup, gdy kafelek pękł.
func miner_hit(i: int, amount: float) -> Dictionary:
	if not is_minable(i):
		return {}
	if layer[i] == L_DEPOSIT:
		amount *= GameState.stat("deposit_damage_mult")
	hp[i] -= amount
	var acc: Array = dmg_acc.get(i, [0.0, 0.0, "miner"])
	acc[0] += amount
	acc[2] = "miner"
	dmg_acc[i] = acc
	if hp[i] <= 0.0:
		_flush_damage(i, true)
		return _destroy(i, true)
	return {}


## W odbudowanym mieście może stanąć wieżyczka Imperium.
func _maybe_ally(i: int, chance_mult := 1.0) -> void:
	if randf() < GameState.stat("ally_turret_chance") * chance_mult:
		ally_turrets[i] = {"cd": randf_range(0.2, 1.0), "angle": randf() * TAU}


## Odbudowuje kafelek za surowce z magazynu. Zwraca false, gdy nie stać.
func rebuild(i: int) -> bool:
	if not can_rebuild(i) or not GameState.pay(rebuild_cost(i)):
		return false
	layer[i] = L_IMPERIAL
	imperial_count += 1
	devastated_count -= 1
	imperial_list.append(i)
	_maybe_ally(i)
	_update_minimap_pixel(i)
	_mark_dirty(i)
	tile_rebuilt.emit(i)
	return true


## Rozrost Imperium (badanie w laboratorium): kafelek Imperium przejmuje sąsiada.
## Najpierw zabudowuje sąsiednie kratery, a gdy ich brak - nienaruszone kafelki powierzchni.
func _imperial_spread_once() -> bool:
	if imperial_list.is_empty():
		return false
	var dirs := [1, -1, N, -N]
	for pass_ in 2:
		for attempt in 24:
			var base: int = imperial_list[randi() % imperial_list.size()]
			var j: int = base + dirs[randi() % 4]
			if j < 0 or j >= TOTAL or absi((j % N) - (base % N)) > 1:
				continue
			var ok := false
			if pass_ == 0:
				ok = layer[j] == L_CRATER and _is_city(j)
			else:
				ok = layer[j] == L_SURFACE and not turrets.has(j) and _is_city(j)
			if not ok:
				continue
			if layer[j] == L_CRATER:
				devastated_count -= 1
			var metro_gone: bool = layer[j] == L_SURFACE and surface[j] == METRO
			var lm_gone: bool = layer[j] == L_SURFACE and (surface[j] == CAPITOL or surface[j] == PENTAGON)
			layer[j] = L_IMPERIAL
			if metro_gone:
				_metro_tile_gone(j)
			if lm_gone:
				_landmark_tile_gone(j)
			imperial_count += 1
			imperial_list.append(j)
			_maybe_ally(j, 0.5)
			recent_hits.erase(j)
			_update_minimap_pixel(j)
			_mark_dirty(j)
			tile_imperial_spread.emit(j)
			return true
	return false


## Uderzenie wiązki w punkt. Zwraca indeks trafionego kafelka (lub -1).
func laser_hit(p: Vector2, amount: float, splash_out: Array = []) -> int:
	var i := pos_to_idx(p)
	if not is_minable(i):
		return -1
	target_idx = i
	target_timer = 0.15
	hit_glow = 1.0
	_damage(i, amount, "laser")
	# rozprysk: okrąg wokół punktu trafienia (promień w kafelkach, liczony do środków kafelków)
	var splash := GameState.stat("laser_splash")
	if splash > 0.0:
		var r_px: float = splash * T
		var ri := int(ceil(splash))
		var x := i % N
		var y := i / N
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				if dx == 0 and dy == 0:
					continue
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= N or ny >= H:
					continue
				var j := ny * N + nx
				if is_minable(j) and idx_center(j).distance_to(p) <= r_px:
					splash_out.append(idx_center(j))
					_damage(j, amount * 0.5, "splash")
	return i


## Publiczne obrażenia kafelka (rakiety, drony, karabiny).
func damage_tile(i: int, amount: float, src := "rocket") -> void:
	if not is_minable(i):
		return
	_damage(i, amount, src)


func _damage(i: int, amount: float, src := "laser") -> void:
	if layer[i] == L_DEPOSIT:
		amount *= GameState.stat("deposit_damage_mult")
	amount = minf(amount, maxf(hp[i], 0.0))
	hp[i] -= amount
	# zbieranie obrażeń w czytelne liczby (zamiast liczby co klatkę)
	var acc: Array = dmg_acc.get(i, [0.0, 0.0, src])
	acc[0] += amount
	acc[2] = src
	dmg_acc[i] = acc
	recent_hits[i] = 1.6
	if not tile_flash.has(i) or tile_flash[i] <= 0.0:
		tile_flash[i] = 0.07
	if hp[i] <= 0.0:
		_flush_damage(i, true)
		_destroy(i)
		tile_broken.emit(i, src)


func _flush_damage(i: int, big := false) -> void:
	if not dmg_acc.has(i):
		return
	var acc: Array = dmg_acc[i]
	dmg_acc.erase(i)
	if fx and acc[0] >= 0.5:
		fx.damage_number(idx_center(i) + Vector2(0, -10), acc[0], DMG_COLORS.get(acc[2], Color(1, 1, 1)), big)


func _destroy(i: int, quiet := false) -> Dictionary:
	var drops := {}
	var info := ""
	var src: Dictionary
	var mult := GameState.stat("yield_mult")
	if layer[i] == L_SURFACE:
		src = TILE_DEFS[surface[i]]["drops"]
	else:
		src = DEP_DEFS[deposit[i]]["drops"]
		mult *= GameState.stat("deposit_yield_mult")
	for k in src:
		var v: float = float(src[k]) * mult
		var n := int(floor(v))
		if randf() < v - n:
			n += 1
		if n > 0:
			drops[k] = n

	var d := danger(i % N, i / N)
	var was_city := layer[i] == L_SURFACE and surface[i] >= CITY
	var metro_gone: bool = layer[i] == L_SURFACE and surface[i] == METRO
	var lm_gone: bool = layer[i] == L_SURFACE and (surface[i] == CAPITOL or surface[i] == PENTAGON)
	if layer[i] == L_SURFACE:
		devastated_count += 1
	if layer[i] == L_SURFACE and deposit[i] != 0:
		layer[i] = L_DEPOSIT
		max_hp[i] = DEP_DEFS[deposit[i]]["hp"] * (1.0 + d / 90.0)
		hp[i] = max_hp[i]
		info = "Odkryto: " + String(DEP_DEFS[deposit[i]]["name"]) + "!"
	else:
		layer[i] = L_CRATER
		hp[i] = 0.0
	if turrets.has(i):
		turrets.erase(i)
		drops["weapon_scrap"] = randi_range(3, 5)
		info = "Wieżyczka obronna zniszczona!"
	GameState.tiles_destroyed += 1
	_update_minimap_pixel(i)
	_mark_dirty(i)
	# statek wydobywczy sam zabiera łup, więc gracz go nie dostaje
	if not quiet:
		tile_destroyed.emit(i, idx_center(i), drops, info)
	elif fx:
		fx.explosion(idx_center(i), Color(1.0, 0.75, 0.3))
	if metro_gone:
		_metro_tile_gone(i)
	if lm_gone:
		_landmark_tile_gone(i)
	# kopanie miast przez statki wydobywcze nie ściąga myśliwców
	if was_city and not quiet:
		# metropolia i obiekty specjalne drażnią Ziemian bardziej niż zwykłe miasto
		GameState.cities_destroyed += 1 if surface[i] == CITY else (3 if surface[i] == METRO else 5)
		city_destroyed.emit(idx_center(i))
	return drops


func _mark_dirty(i: int) -> void:
	var k := ((i / N) / CHUNK) * CHUNK_COLS + (i % N) / CHUNK
	if chunk_ready[k] == 1:
		dirty_chunks[k] = true
		# unieważnij tylko ten kafelek; sąsiednie zostają w pamięci i nie są liczone od nowa
		if tile_meshes.has(k):
			tile_meshes[k][((i / N) % CHUNK) * CHUNK + (i % N) % CHUNK] = null


func _redraw_all() -> void:
	tile_meshes.clear()
	for k in built_chunks:
		dirty_chunks[k] = true


## Buduje siatki fragmentów wokół kamery (najbliższe najpierw) i zwalnia te daleko za nią.
func _update_chunks(delta: float) -> void:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var tl: Vector2 = inv * Vector2.ZERO
	var view := Rect2(tl, (inv * get_viewport_rect().size) - tl)
	var size := float(CHUNK * T)
	var near := view.grow(size * 1.5)
	var center := view.get_center()
	var missing: Array = []
	for cy in range(maxi(0, int(near.position.y / size)), mini(CHUNK_ROWS, int(near.end.y / size) + 1)):
		for cx in range(maxi(0, int(near.position.x / size)), mini(CHUNK_COLS, int(near.end.x / size) + 1)):
			if chunk_ready[cy * CHUNK_COLS + cx] == 0:
				missing.append(cy * CHUNK_COLS + cx)
	if missing.size() > CHUNKS_PER_FRAME:
		missing.sort_custom(func(a, b): return _chunk_center(a).distance_squared_to(center) < _chunk_center(b).distance_squared_to(center))
		missing.resize(CHUNKS_PER_FRAME)
	for k in missing:
		chunk_ready[k] = 1
		built_chunks[k] = true
		chunks[k].queue_redraw()
	chunk_free_timer -= delta
	if chunk_free_timer > 0.0:
		return
	chunk_free_timer = 1.0
	var keep := view.grow(size * 6.0)
	for k in built_chunks.keys():
		if not keep.has_point(_chunk_center(k)):
			chunk_ready[k] = 0
			built_chunks.erase(k)
			dirty_chunks.erase(k)
			tile_meshes.erase(k)
			RenderingServer.canvas_item_clear(chunks[k].get_canvas_item())
			chunks[k].remove_meta("mesh")


## Przerysowanie zmienionych fragmentów - najwyżej raz na klatkę na fragment.
func _flush_dirty_chunks() -> void:
	if dirty_chunks.is_empty():
		return
	# najwyżej kilka fragmentów na klatkę, żeby nie było szarpnięć
	var done := 0
	for k in dirty_chunks.keys():
		chunks[k].queue_redraw()
		dirty_chunks.erase(k)
		done += 1
		if done >= 6:
			break


# =====================================================================
# WIEŻYCZKI I POCISKI
# =====================================================================

# =====================================================================
# PORYWANIE
# =====================================================================


func mark_abducted(i: int) -> void:
	abducted[i] = 1
	_mark_dirty(i)


func _bio_process(delta: float) -> void:
	# Potęga Imperium: każdy odbudowany kafelek generuje walutę w czasie rzeczywistym
	if imperial_count > 0:
		power_acc += power_rate() * delta
		if power_acc >= 0.9999:
			var n := int(floor(power_acc + 0.0001))
			power_acc -= n
			GameState.bank["power"] = int(GameState.bank.get("power", 0)) + n
			GameState.bank_changed.emit()
	# rozrost kafelków Imperium (co 10 s, ulepszenia skracają do 5 s)
	if GameState.stat("imp_spread") > 0.0 and imperial_count > 0:
		imp_spread_timer += delta
		var cd := maxf(5.0, GameState.stat("imp_spread_cd"))
		if imp_spread_timer >= cd:
			imp_spread_timer -= cd
			_imperial_spread_once()
