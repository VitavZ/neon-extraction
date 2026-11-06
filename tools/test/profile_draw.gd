extends SceneTree
## Koszt rysowania warstw w gęstym mieście: v-sync wyłączony, prawdziwy czas między klatkami,
## pomiary naprzemienne (z warstwą / bez) w kilku rundach. Statek strzela laserem, wrogowie aktywni.
## Uruchamiać przez run_test.ps1 -Script res://tools/test/profile_draw.gd

var main
var gs
var at := Vector2.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _frames_ms(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for k in n:
		main.ship.position = at
		main.ship.vel = Vector2.ZERO
		main.ship.hull = 99999.0
		main.ship.shield = 99999.0
		main.ship.fuel = 999.0
		main.patrol_timer = 999.0
		await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / n


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	gs = root.get_node("GameState")
	gs.slot = 4
	change_scene_to_file("res://main.tscn")
	await create_timer(2.5).timeout
	main = current_scene
	main.launch()
	await create_timer(0.3).timeout
	var w = main.world
	at = w.city_pos(4) + Vector2(0, 500)
	main.zoom_target = float(OS.get_environment("NEON_ZOOM")) if OS.get_environment("NEON_ZOOM") != "" else 0.6
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	var vs: Vector2 = root.get_viewport().get_visible_rect().size
	Input.warp_mouse(vs * 0.5 + Vector2(0, -120))
	await _frames_ms(200)
	var base := await _frames_ms(150)
	print("[TEST] klatka: %.2f ms (%.0f FPS bez v-sync), wrogów %d, wieżyczek w kadrze ~%d" % [base, 1000.0 / base, main.enemies.alive_count(),
		w.turrets_in_rect(Rect2(at - vs / main.camera.zoom, vs / main.camera.zoom * 2.0)).size()])
	var layers := {"kafelki mapy": "chunks", "nakładka świata": w.overlay, "skaner": w.scan_layer, "fx": main.fx, "wrogowie": main.enemies,
		"hud": main.hud, "bronie": main.weapons, "statek matka": main.mothership, "statek": main.ship, "eskorta": main.escorts,
		"filtr CRT": "crt", "wypełnienie stref": "fill", "zasięgi (całość)": "ranges"}
	for name in layers:
		var on := 0.0
		var off := 0.0
		for r in 3:
			on += await _frames_ms(60)
			_vis(layers[name], false)
			off += await _frames_ms(60)
			_vis(layers[name], true)
		print("[TEST]   %-16s %.2f ms" % [name, (on - off) / 3.0])
	quit()


func _vis(what, v: bool) -> void:
	if what is String and what == "chunks":
		for c in main.world.chunks:
			c.visible = v
	elif what is String and what == "fill":
		for gr in main.world._fill_groups:
			gr.self_modulate.a = 0.1 if v else 0.0
			gr.get_child(0).visible = v
	elif what is String and what == "ranges":
		main.world.show_ranges = v
	elif what is String and what == "crt":
		for n in main.get_children():
			if n is CanvasLayer and n.get_script() != null and String(n.get_script().resource_path).ends_with("crt.gd"):
				n.visible = v
	else:
		what.visible = v
