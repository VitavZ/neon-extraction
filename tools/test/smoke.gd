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
	change_scene_to_file("res://splash.tscn")
	await _wait(1.2)
	await _shot("00_splash")
	# logika opcji (settings.cfg przywraca run_test.ps1)
	var opt = load("res://scripts/options.gd")
	var shake: bool = gs.settings["shake"]
	opt.change("shake", 1, null, null)
	var flipped: bool = gs.settings["shake"] != shake
	opt.change("shake", 1, null, null)
	_log("opcje: przełączanie %s, wartość głośności '%s'" % ["OK" if flipped and gs.settings["shake"] == shake else "BŁĄD", opt.value_text("volume")])
	change_scene_to_file("res://menu.tscn")
	await _wait(1.5)
	await _shot("01_menu")
	var menu = current_scene
	if menu == null:
		_log("BŁĄD: menu się nie załadowało")
		quit(1)
		return
	menu._go("options", 0)
	await _wait(0.6)
	await _shot("02_menu_options")
	menu._go("achievements", 0)
	await _wait(0.6)
	await _shot("02_menu_achievements")
	menu._go("slots", 0)
	await _wait(0.6)
	await _shot("02_menu_slots")

	gs.slot = 4
	change_scene_to_file("res://main.tscn")
	await _wait(2.5)
	var main = current_scene
	if main == null or main.get("upgrade_screen") == null:
		_log("BŁĄD: scena gry się nie załadowała")
		quit(1)
		return
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
