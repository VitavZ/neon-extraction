extends SceneTree
## Test dymny: menu, dok (wszystkie zakładki), lot, pauza z opcjami. Zrzuty do katalogu z argumentu.
## Uruchamiać tylko przez tools/test/run_test.ps1 (pilnuje slotu 4 i kopii ustawień).

var out := ""


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
	_log("zrzut " + name + "  fps=%d" % Engine.get_frames_per_second())


func _run() -> void:
	var gs = root.get_node("GameState")
	gs.slot = 4
	change_scene_to_file("res://menu.tscn")
	await _wait(1.5)
	await _shot("01_menu")
	var menu = current_scene
	menu._go("options", 0)
	await _wait(0.6)
	await _shot("02_menu_options")

	gs.slot = 4
	change_scene_to_file("res://main.tscn")
	await _wait(2.5)
	var main = current_scene
	await _shot("03_dock_grid")
	var us = main.upgrade_screen
	for t in us._tabs():
		if t == "grid":
			continue
		us.tab = t
		await _wait(0.5)
		await _shot("04_dock_" + t)
	us.tab = "grid"
	us._toggle_overlay("stats")
	await _wait(0.6)
	await _shot("05_dock_stats")
	us._toggle_overlay("stats")

	main.launch()
	await _wait(3.0)
	await _shot("06_flight")
	main.pause_menu.open(true)
	await _wait(0.4)
	await _shot("07_pause")
	main.pause_menu._go("options", 0)
	await _wait(0.4)
	await _shot("08_pause_options")
	main.pause_menu._go("controls", 0)
	await _wait(0.4)
	await _shot("09_pause_controls")
	main.pause_menu.close()
	await _wait(1.0)
	_log("koniec")
	quit()
