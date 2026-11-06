extends SceneTree
## Profil gęstego miasta: ile ms/klatkę zjada każdy moduł (wyłączany po kolei na 1,5 s).
## Uruchamiać przez run_test.ps1 -Script res://tools/test/profile_city.gd

func _initialize() -> void:
	_run.call_deferred()


func _avg_ms(main, at: Vector2, sec: float) -> float:
	var sum := 0.0
	var n := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		main.ship.position = at
		main.ship.vel = Vector2.ZERO
		main.ship.hull = 99999.0
		main.patrol_timer = 999.0
		main.enemies.clear_all()
		main.world.bullets.clear()
		main.world.missiles.clear()
		await process_frame
		sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		n += 1
	return sum / maxf(1.0, n)


func _run() -> void:
	var gs = root.get_node("GameState")
	gs.slot = 4
	change_scene_to_file("res://main.tscn")
	await create_timer(2.5).timeout
	var main = current_scene
	main.launch()
	await create_timer(0.5).timeout
	var w = main.world
	var at: Vector2 = w.city_pos(4) + Vector2(0, 500)
	main.zoom_target = 0.6
	await _avg_ms(main, at, 2.0)
	var base: float = await _avg_ms(main, at, 1.5)
	print("[TEST] wszystko: %.1f ms" % base)
	var parts := {"world (_process)": w, "enemies": main.enemies, "hud": main.hud, "fx": main.fx, "weapons": main.weapons,
		"escorts": main.escorts, "miners": main.miners, "wingmen": main.wingmen, "transit": main.transit, "ship": main.ship}
	for name in parts:
		var node: Node = parts[name]
		node.process_mode = Node.PROCESS_MODE_DISABLED
		var ms: float = await _avg_ms(main, at, 1.5)
		node.process_mode = Node.PROCESS_MODE_INHERIT
		print("[TEST]   bez %-18s %.1f ms  (moduł ~%.1f ms)" % [name, ms, base - ms])
	w.overlay.visible = false
	var ms2: float = await _avg_ms(main, at, 1.5)
	w.overlay.visible = true
	print("[TEST]   bez rysowania nakładki     %.1f ms  (nakładka ~%.1f ms)" % [ms2, base - ms2])
	w.show_ranges = false
	var ms3: float = await _avg_ms(main, at, 1.5)
	w.show_ranges = true
	print("[TEST]   bez zasięgów               %.1f ms  (zasięgi ~%.1f ms)" % [ms3, base - ms3])
	print("[TEST] wszystko (ponownie): %.1f ms" % (await _avg_ms(main, at, 1.5)))
	quit()
