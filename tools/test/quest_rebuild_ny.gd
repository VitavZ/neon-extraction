extends SceneTree
## Test rozkazu "Odbuduj Nowy Jork" na kopii slotu 1 (uruchamiać przez run_test.ps1 -Script ...).
## Odbudowuje kafelki metropolii NY aż do progu, sprawdza zaliczenie, nową nazwę i robi zrzut napisu na mapie.

var out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_run.call_deferred()


func _log(s: String) -> void:
	print("[TEST] " + s)


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _run() -> void:
	var gs = root.get_node("GameState")
	gs.slot = 4
	change_scene_to_file("res://main.tscn")
	await _wait(2.5)
	var main = current_scene
	var world = main.world
	var s := 2
	_log("rozkaz rebuild_ny: '%s', odbudowa %d%%, nazwa %s" % [gs.quests.get("rebuild_ny", ""), int(gs.metro_rebuilt(s) * 100), gs.city_name(s)])
	main.launch()
	await _wait(1.0)
	# odbudowa kraterów metropolii (z dosypaniem surowców, to tylko kopia zapisu)
	var n := 0
	for i in world.TOTAL:
		if gs.metro_rebuilt(s) >= 0.8:
			break
		if world.surface[i] == world.METRO and world.can_rebuild(i):
			for k in world.rebuild_cost(i):
				gs.bank[k] = int(gs.bank.get(k, 0)) + int(world.rebuild_cost(i)[k])
			if world.rebuild(i):
				n += 1
			if n == 1 or n % 200 == 0:
				_log("  odbudowano %d, postęp %d%%, rozkaz '%s'" % [n, int(gs.metro_rebuilt(s) * 100), gs.quests.get("rebuild_ny", "")])
	_log("po odbudowie %d kafelków: %d%%, rozkaz '%s', nazwa %s" % [n, int(gs.metro_rebuilt(s) * 100), gs.quests.get("rebuild_ny", ""), gs.city_name(s)])
	var before: int = int(gs.bank.get("loyalty", 0))
	var got: int = gs.claim_quest("rebuild_ny")
	_log("nagroda: +%d PL (%d -> %d)" % [got, before, int(gs.bank.get("loyalty", 0))])
	main.ship.position = world.city_pos(s) + Vector2(0, 300)
	main.ship.vel = Vector2.ZERO
	await _wait(1.5)
	root.get_viewport().get_texture().get_image().save_png(out.path_join("nowszy_jork.png"))
	_log("koniec")
	quit()
