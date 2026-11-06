extends SceneTree
## Zasięgi wieżyczek w gęstym mieście: FPS i zrzut (kopia slotu 1, statek nieśmiertelny na czas pomiaru).
## Uruchamiać przez run_test.ps1 -Script res://tools/test/turret_rings.gd

var out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_run.call_deferred()


func _run() -> void:
	var gs = root.get_node("GameState")
	gs.slot = 4
	change_scene_to_file("res://main.tscn")
	await create_timer(2.5).timeout
	var main = current_scene
	main.launch()
	await create_timer(0.5).timeout
	var w = main.world
	# miasto z największą liczbą wieżyczek w pobliżu środka
	var best := -1
	var best_n := -1
	for s in w.Sectors.LIST.size():
		var n: int = w.turrets_in_rect(Rect2(w.city_pos(s) - Vector2(900, 900), Vector2(1800, 1800))).size()
		if n > best_n:
			best_n = n
			best = s
	var at: Vector2 = w.city_pos(best) + Vector2(0, 500)
	print("[TEST] miasto %s, wieżyczek w pobliżu: %d" % [w.Sectors.LIST[best]["city"], best_n])
	if OS.get_environment("NEON_NO_RINGS") == "1":
		w.show_ranges = false
	var frames := 0
	var t0 := Time.get_ticks_msec()
	var worst := 0.0
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() - t0 < 4000:
		main.ship.position = at
		main.ship.vel = Vector2(120, 0).rotated(frames * 0.02)
		main.ship.hull = gs.stat("max_hull")
		main.ship.shield = gs.stat("max_shield")
		main.zoom_target = 0.6
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
	print("[TEST] średnio %.1f FPS, najgorsza klatka %.1f ms" % [frames / 4.0, worst])
	print("[TEST] skrypty (_process) %.1f ms/klatkę, wywołania rysowania %d, prymitywy %d, obiekty %d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	root.get_viewport().get_texture().get_image().save_png(out.path_join("rings.png"))
	quit()
