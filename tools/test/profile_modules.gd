extends SceneTree
## Dokładny profil gęstego miasta: _process każdego modułu wywoływany ręcznie i mierzony w mikrosekundach,
## rysowanie mierzone przez chowanie warstw. Statek strzela laserem w miasto, wrogowie są aktywni.
## Uruchamiać przez run_test.ps1 -Script res://tools/test/profile_modules.gd

var main
var gs
var at := Vector2.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _keep(frames: int) -> void:
	for k in frames:
		main.ship.position = at
		main.ship.vel = Vector2.ZERO
		main.ship.hull = 99999.0
		main.ship.shield = 99999.0
		main.ship.fuel = 999.0
		await process_frame


func _run() -> void:
	gs = root.get_node("GameState")
	gs.slot = 4
	change_scene_to_file("res://main.tscn")
	await create_timer(2.5).timeout
	main = current_scene
	main.launch()
	await create_timer(0.3).timeout
	var w = main.world
	at = w.city_pos(4) + Vector2(0, 500)
	main.zoom_target = 0.6
	# strzelanie laserem w miasto (LPM wciśnięty, kursor przed statkiem)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	await _keep(150)
	var vs: Vector2 = root.get_viewport().get_visible_rect().size
	Input.warp_mouse(vs * 0.5 + Vector2(0, -120))
	var mods := {"world": w, "enemies": main.enemies, "hud": main.hud, "fx": main.fx, "weapons": main.weapons,
		"escorts": main.escorts, "miners": main.miners, "wingmen": main.wingmen, "transit": main.transit,
		"ship": main.ship, "mothership": main.mothership, "main": main}
	var cost := {}
	for name in mods:
		cost[name] = 0
		mods[name].process_mode = Node.PROCESS_MODE_DISABLED
	var frames := 180
	var total_proc := 0.0
	for k in frames:
		main.ship.position = at
		main.ship.vel = Vector2.ZERO
		main.ship.hull = 99999.0
		main.ship.shield = 99999.0
		main.ship.fuel = 999.0
		for name in mods:
			var t0 := Time.get_ticks_usec()
			mods[name]._process(1.0 / 60.0)
			cost[name] += Time.get_ticks_usec() - t0
		await process_frame
		total_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	for name in mods:
		mods[name].process_mode = Node.PROCESS_MODE_INHERIT
	print("[TEST] wrogów: %d, pocisków: %d, iskier: %d" % [main.enemies.alive_count(), w.bullets.size(), main.fx.sparks_list.size()])
	var names: Array = cost.keys()
	names.sort_custom(func(a, b): return cost[a] > cost[b])
	var sum := 0.0
	for name in names:
		var ms: float = cost[name] / 1000.0 / frames
		sum += ms
		print("[TEST]   _process %-12s %.2f ms" % [name, ms])
	print("[TEST]   razem logika %.2f ms; reszta klatki (rysowanie i silnik) %.2f ms" % [sum, total_proc / frames])
	# rysowanie: chowanie warstw po kolei
	await _keep(30)
	var base := await _avg(90)
	print("[TEST] rysowanie - pełna klatka %.2f ms" % base)
	var layers := {"nakładka świata": w.overlay, "skaner": w.scan_layer, "fx": main.fx, "wrogowie": main.enemies, "hud": main.hud,
		"bronie": main.weapons, "statek matka": main.mothership, "eskorta": main.escorts}
	for name in layers:
		layers[name].visible = false
		var ms := await _avg(90)
		layers[name].visible = true
		print("[TEST]   bez warstwy %-16s %.2f ms  (~%.2f)" % [name, ms, base - ms])
	var chunks_hidden := 0
	for c in w.chunks:
		c.visible = false
	var ms2 := await _avg(90)
	for c in w.chunks:
		c.visible = true
	print("[TEST]   bez kafelków mapy          %.2f ms  (~%.2f)" % [ms2, base - ms2])
	print("[TEST] pełna klatka ponownie %.2f ms, FPS %d" % [await _avg(90), Engine.get_frames_per_second()])
	quit()


func _avg(frames: int) -> float:
	var s := 0.0
	for k in frames:
		main.ship.position = at
		main.ship.vel = Vector2.ZERO
		main.ship.hull = 99999.0
		main.ship.shield = 99999.0
		main.ship.fuel = 999.0
		await process_frame
		s += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	return s / frames
