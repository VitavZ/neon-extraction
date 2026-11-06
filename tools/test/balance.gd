extends SceneTree
## Kontrola balansu (uruchamiać przez run_test.ps1 -Script res://tools/test/balance.gd):
## 1) każda baza i wkład każdego węzła na każdym poziomie jest wielokrotnością kroku statystyki (GameState.stat_step),
##    więc statystyki po każdym zakupie są okrągłe,
## 2) tabela: baza -> maksimum (wszystkie węzły wykupione),
## 3) statystyki slotu 4 (kopia slotu 1) i mnożniki siły wrogów.

const Upgrades = preload("res://scripts/upgrades.gd")


func _initialize() -> void:
	_run.call_deferred()


func _on_step(v: float, step: float) -> bool:
	var k := v / step
	return absf(k - round(k)) < 0.001


func _run() -> void:
	var gs = root.get_node("GameState")
	var bad := 0
	for k in gs.BASE_STATS:
		if not _on_step(float(gs.BASE_STATS[k]), gs.stat_step(k)):
			print("[BAL] BAZA %s = %s (krok %s)" % [k, gs.BASE_STATS[k], gs.stat_step(k)])
			bad += 1
	var best: Dictionary = gs.BASE_STATS.duplicate()
	for u in Upgrades.all_items():
		for k in u["effects"]:
			for lv in range(1, int(u["max"]) + 1):
				var c: float = gs.contribution(u, k, lv)
				if not _on_step(c, gs.stat_step(k)):
					print("[BAL] %s poz. %d: %s = %s (krok %s)" % [u["id"], lv, k, c, gs.stat_step(k)])
					bad += 1
			best[k] = float(best.get(k, 0.0)) + gs.contribution(u, k, int(u["max"]))
	print("[BAL] niezaokrąglonych wartości: %d" % bad)
	for k in gs.STAT_NAMES:
		if gs.BASE_STATS.has(k) and float(best[k]) != float(gs.BASE_STATS[k]):
			print("[BAL] %-28s %8s -> %s" % [k, gs.format_stat(k, gs.BASE_STATS[k]), gs.format_stat(k, best[k])])
	# slot 4 = kopia slotu 1 (run_test.ps1)
	gs.slot = 4
	if gs.load_game():
		print("[BAL] --- slot 1 (kopia) po zmianach ---")
		for k in ["laser_dps", "max_hull", "max_shield", "armor", "shield_regen", "hull_regen", "max_fuel", "fuel_efficiency", "fuel_siphon",
				"rocket_damage", "rocket_cooldown", "rocket_radius", "drone_damage", "drone_interval", "drone_count", "gun_damage", "gun_interval", "cargo", "cargo_mult"]:
			print("[BAL]   %-20s %s" % [k, gs.format_stat(k, gs.stat(k))])
		print("[BAL]   ładownia             %d" % gs.cargo_cap())
		var en = load("res://scripts/enemies.gd").new()
		var ps: Vector2 = en.power_scale()
		print("[BAL]   wrogowie: kadłub x%.2f, obrażenia x%.2f" % [ps.x, ps.y])
		en.free()
	quit()
