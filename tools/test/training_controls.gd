extends SceneTree
## Szkolenie: ćwiczenia sterowania. Symuluje prawdziwe wejście (mysz, klawisze, kółko, LPM) i sprawdza,
## że każde ćwiczenie zalicza się dopiero po wykonaniu czynności. Uruchamiać przez run_test.ps1 -Script ...

var out := ""
var gs
var main
var tr
var tut
var bad := 0


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


func _key(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.pressed = down
	ev.physical_keycode = code
	ev.keycode = code
	Input.parse_input_event(ev)


func _mouse_button(idx: int, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = idx
	ev.pressed = down
	ev.position = root.get_viewport().get_mouse_position()
	Input.parse_input_event(ev)


func _screen_of(world_pos: Vector2) -> Vector2:
	return root.get_viewport().get_canvas_transform() * world_pos


## Czeka na okienko ćwiczenia d, sprawdza, że ćwiczenie jeszcze nie jest zaliczone, i zamyka okienko.
func _open_drill(d: int) -> void:
	var w0 := Time.get_ticks_msec()
	for k in 60:
		if tut.showing and tut.cstep == d + 1:
			break
		await _wait(0.1)
	_log("  okienko po %.1f s" % ((Time.get_ticks_msec() - w0) / 1000.0))
	_expect("okienko ćwiczenia %d (%s)" % [d + 1, tr.DRILLS[d][0]], tut.showing and tut.cstep == d + 1)
	if d == 0:
		await _shot("c01_popup_aim")
	tut._dismiss()
	await _wait(0.6)
	_expect("  bez działania: nie zaliczone", tr.drill == d)


func _expect(what: String, ok: bool) -> void:
	_log(("OK   " if ok else "BŁĄD ") + what + "  [ćwiczenie %d, okienko %d]" % [tr.drill, tut.cstep])
	if not ok:
		bad += 1


func _run() -> void:
	gs = root.get_node("GameState")
	gs.start_training()
	change_scene_to_file("res://main.tscn")
	await _wait(3.0)
	main = current_scene
	tr = main.training_ctl
	tut = main.tutorial
	tut._dismiss()
	main.launch()
	await _wait(1.0)
	var vs: Vector2 = root.get_viewport().get_visible_rect().size
	# 1. obrót: kursor krąży wokół statku
	await _open_drill(0)
	for k in 48:
		var c := _screen_of(main.ship.global_position)
		Input.warp_mouse(c + Vector2.from_angle(k * TAU / 16.0) * 200.0)
		await _wait(0.06)
	_expect("obrót zaliczony", tr.drill == 1)
	# 2. ciąg
	await _open_drill(1)
	_key(KEY_W, true)
	await _wait(2.6)
	_key(KEY_W, false)
	_expect("ciąg zaliczony", tr.drill == 2)
	# 3. hamowanie
	await _open_drill(2)
	_key(KEY_W, true)
	await _wait(1.0)
	_key(KEY_W, false)
	_key(KEY_S, true)
	await _wait(1.2)
	_key(KEY_S, false)
	_expect("hamowanie zaliczone", tr.drill == 3)
	# 4. manewr w bok
	await _open_drill(3)
	_key(KEY_A, true)
	await _wait(1.5)
	_key(KEY_A, false)
	_expect("manewr zaliczony", tr.drill == 4)
	# 5. drift
	await _open_drill(4)
	_key(KEY_SPACE, true)
	await _wait(1.2)
	_key(KEY_SPACE, false)
	await _wait(0.5)
	_expect("drift zaliczony", tr.drill == 5)
	# 6. zoom
	await _open_drill(5)
	_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, false)
	await _wait(0.5)
	_expect("zoom zaliczony", tr.drill == 6)
	# 7. laser: kursor tuż przed statkiem, LPM trzymany
	await _open_drill(6)
	main.ship.vel = Vector2.ZERO
	var t0 := Time.get_ticks_msec()
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	while tr.drill == 6 and Time.get_ticks_msec() - t0 < 15000:
		var c := _screen_of(main.ship.global_position)
		Input.warp_mouse(c + Vector2.from_angle((Time.get_ticks_msec() - t0) / 900.0) * 110.0)
		await _wait(0.1)
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	_expect("laser zaliczony (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0), tr.drill == 7)
	# 8. rakieta
	await _open_drill(7)
	await _shot("c02_objective_rocket")
	_key(KEY_Q, true)
	await _wait(0.2)
	_key(KEY_Q, false)
	await _wait(0.8)
	_expect("rakieta zaliczona, faza zbierania", tr.drill == 8 and tr.phase == tr.GATHER)
	var w1 := Time.get_ticks_msec()
	var big_seen := false
	while not tut.showing and Time.get_ticks_msec() - w1 < 9000:
		if main.hud.big_t >= 0.0:
			big_seen = true
		await _wait(0.1)
	_expect("okienko 'ZADANIE: SUROWCE' po dużym napisie (%.1f s)" % ((Time.get_ticks_msec() - w1) / 1000.0), tut.showing and tut.cstep == tr.MAIN_STEP and big_seen and main.hud.big_t < 0.0)
	var f0: float = main.ship.fuel
	tut._dismiss()
	await _wait(3.0)
	_log("paliwo w szkoleniu: -%.2f / s (bez ruchu)" % ((f0 - main.ship.fuel) / 3.0))
	main.ship.fuel = 0.0
	var w2 := Time.get_ticks_msec()
	while not main.ship.dead and Time.get_ticks_msec() - w2 < 9000:
		await _wait(0.1)
	_expect("pusty bak: wybuch po %.1f s" % ((Time.get_ticks_msec() - w2) / 1000.0), main.ship.dead)
	await _shot("c03_gather_popup")
	_log("błędów: %d" % bad)
	quit()
