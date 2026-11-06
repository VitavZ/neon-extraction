extends SceneTree
## Test szkolenia w Roswell: przechodzi cały scenariusz (zbieranie i niszczenie "na skróty"), robi zrzuty
## kluczowych chwil i sprawdza fazy, przegraną z bossem, ekrany końcowe i osiągnięcie.
## Uruchamiać przez run_test.ps1 -Script res://tools/test/training_flow.gd (pilnuje zapisów i achievements.cfg).

const Upgrades = preload("res://scripts/upgrades.gd")
var out := ""
var gs
var main
var tr


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_run.call_deferred()


func _log(s: String) -> void:
	print("[TEST] " + s)


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	_log("zrzut %s  (faza %d)" % [name, tr.phase if tr else -1])


func _phase_name() -> String:
	return ["CONTROLS", "GATHER", "UPGRADE", "DESTROY", "UNLOCK", "REBUILD", "SIEGE", "CALM", "DANGER", "BOSS", "DEFEAT", "VEX", "DONE"][tr.phase]


func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.physical_keycode = code
	ev.keycode = code
	Input.parse_input_event(ev)
	await process_frame
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func _run() -> void:
	gs = root.get_node("GameState")
	gs.start_training()
	change_scene_to_file("res://main.tscn")
	await _wait(3.0)
	main = current_scene
	tr = main.training_ctl
	if tr == null:
		_log("BŁĄD: brak kontrolera szkolenia")
		quit(1)
		return
	var w = main.world
	# co jest do zebrania w obszarze szkolenia
	var counts := {}
	for y in range(tr.AREA.position.y, tr.AREA.end.y):
		for x in range(tr.AREA.position.x, tr.AREA.end.x):
			var s: int = w.surface[y * w.N + x]
			counts[s] = int(counts.get(s, 0)) + 1
	_log("teren obszaru (typ: kafelki): %s" % str(counts))
	_log("Roswell: %d kafelków, wieżyczek w pobliżu: %d, laser %d" % [tr.town.size(), w.turrets_in_rect(Rect2(tr.town_center - Vector2(400, 400), Vector2(800, 800))).size(), gs.stat("laser_dps")])
	await _shot("t01_dock_popup")
	main.tutorial._dismiss()
	# od teraz okienka nie pauzują testu
	main.tutorial.custom_cond = func(_s): return false
	main.launch()
	if tr.phase == tr.CONTROLS:
		tr.skip_controls()   # ćwiczenia sterowania sprawdza training_controls.gd
	await _wait(2.0)
	await _shot("t02_flight_area")
	main.ship.position = tr.town_center + Vector2(300, 250)
	main.ship.vel = Vector2.ZERO
	await _wait(1.5)
	await _shot("t03_roswell_shield")
	# zbieranie na skróty
	gs.add_cargo("biomass", 40)
	gs.add_cargo("stone", 30)
	main.dock("test", true, true)
	await _wait(1.0)
	_log("po dokowaniu z surowcami: %s" % _phase_name())
	gs.buy(Upgrades.by_id("laser_dmg"))
	await _wait(0.5)
	_log("po zakupie lasera (%d): %s" % [gs.stat("laser_dps"), _phase_name()])
	main.launch()
	if tr.phase == tr.CONTROLS:
		tr.skip_controls()   # ćwiczenia sterowania sprawdza training_controls.gd
	await _wait(0.5)
	main.ship.position = tr.town_center + Vector2(300, 250)
	await _wait(1.0)
	await _shot("t04_shield_down")
	for i in tr.town:
		if w.is_minable(i):
			w._destroy(i)
	await _wait(1.0)
	_log("po zniszczeniu: %s (zniszczone %d%%)" % [_phase_name(), int(tr.destroyed_frac() * 100)])
	await _shot("t05_destroyed")
	main.dock("test", true, true)
	await _wait(1.0)
	var ok: bool = gs.buy(Upgrades.by_id("rebuild"))
	await _wait(0.5)
	_log("zakup odbudowy: %s, faza %s" % [ok, _phase_name()])
	main.launch()
	if tr.phase == tr.CONTROLS:
		tr.skip_controls()   # ćwiczenia sterowania sprawdza training_controls.gd
	await _wait(0.5)
	main.ship.position = tr.town_center + Vector2(300, 250)
	main.ship.tool = 3
	for i in tr.town:
		if tr.rebuilt_frac() >= 0.8:
			break
		w.rebuild(i)
	await _wait(1.0)
	_log("po odbudowie %d%%: %s" % [int(tr.rebuilt_frac() * 100), _phase_name()])
	main.ship.position = main.mothership.position + Vector2(250, 0)
	await _wait(2.0)
	await _shot("t06_siege")
	main.ship.hull = 99999.0
	for f in main.enemies.fighters:
		main.enemies.damage_fighter(f, 1e7)
	await _wait(1.5)
	_log("po zestrzeleniu: %s" % _phase_name())
	await _wait(6.2)
	_log("po ciszy: %s" % _phase_name())
	await _wait(0.6)
	await _shot("t07_danger_a")
	await _wait(1.3)
	await _shot("t08_danger_b")
	await _wait(2.5)
	_log("po ostrzeżeniu: %s" % _phase_name())
	main.ship.hull = gs.stat("max_hull")
	main.ship.shield = gs.stat("max_shield")
	await _wait(4.0)
	await _shot("t09_boss")
	var t0 := Time.get_ticks_msec()
	var laser_shot := false
	var final_shot := false
	var wave_shot := false
	var low_at := -1.0
	while not main.ship.dead and Time.get_ticks_msec() - t0 < 90000:
		await _wait(0.1)
		# kadłub podtrzymywany do fali działa głównego, żeby zobaczyć cały przebieg walki
		if main.ship.hull < gs.stat("max_hull") * 0.25 and tr.final_r < 0.0:
			if low_at < 0.0:
				low_at = (Time.get_ticks_msec() - t0) / 1000.0
				_log("kadłub < 25%% po %.1f s walki (tu zwykle gracz już ginie)" % low_at)
			main.ship.hull = gs.stat("max_hull")
		# prosty pilot: krąży wokół bossa z pełną prędkością (gracz, który robi uniki)
		var away: Vector2 = main.ship.position - tr.boss["pos"]
		main.ship.vel = (away.orthogonal().normalized() + away.normalized() * (550.0 - away.length()) / 400.0).normalized() * gs.stat("max_speed")
		if not laser_shot and tr.laser_state == "fire":
			laser_shot = true
			await _shot("t10_boss_lasers")
		if tr.final_t > 1.6 and tr.final_r < 0.0 and not final_shot:
			final_shot = true
			await _shot("t10b_final_charge")
		if tr.final_r > 250.0 and not wave_shot:
			wave_shot = true
			await _shot("t10c_final_wave")
	_log("gracz zginął po %.1f s walki (pilot robi uniki), faza %s" % [(Time.get_ticks_msec() - t0) / 1000.0, _phase_name()])
	await _wait(4.5)
	_log("po przegranej: %s, paused=%s" % [_phase_name(), paused])
	await _shot("t11_vex")
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	await _wait(1.0)
	await _shot("t12_done")
	_log("faza %s, osiągnięcie training: %s" % [_phase_name(), root.get_node("Achievements").unlocked.has("training")])
	await _key(KEY_ENTER)
	await _wait(1.5)
	_log("scena po zakończeniu: %s, training=%s" % [current_scene.scene_file_path if current_scene else "?", gs.training])
	_log("koniec")
	quit()
