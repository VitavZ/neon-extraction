extends SceneTree
## Szkolenie: okienka nie mogą wyprzedzać postępu (błąd: dokowanie bez surowców "zaliczało" laser i zniszczenie Roswell).
## Uruchamiać przez run_test.ps1 -Script res://tools/test/training_popups.gd

const Upgrades = preload("res://scripts/upgrades.gd")
var gs
var main
var tr
var tut
var bad := 0


func _initialize() -> void:
	_run.call_deferred()


func _log(s: String) -> void:
	print("[TEST] " + s)


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _state() -> String:
	return "faza %d, okienko %d (%s)" % [tr.phase, tut.cstep, "widoczne" if tut.showing else "ukryte"]


## Zamyka bieżące okienko, jeśli jest; zwraca jego numer albo -1.
func _close() -> int:
	if not tut.showing:
		return -1
	var k: int = tut.cstep
	tut._dismiss()
	await _wait(0.1)
	return k


func _expect(what: String, ok: bool) -> void:
	_log(("OK   " if ok else "BŁĄD ") + what + "  [" + _state() + "]")
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
	_expect("powitanie w doku", tut.showing and tut.cstep == 0)
	await _close()
	main.launch()
	if tr.phase == tr.CONTROLS:
		tr.skip_controls()   # ćwiczenia sterowania sprawdza training_controls.gd
	await _wait(2.0)
	_expect("zadanie surowców w locie", tut.showing and tut.cstep == tr.MAIN_STEP)
	await _close()
	# za mało surowców: 10 biomasy, 5 kamienia
	gs.add_cargo("biomass", 10)
	gs.add_cargo("stone", 5)
	main.dock("test", true, true)
	await _wait(2.5)
	_expect("dok bez surowców: faza GATHER, brak okienka o ulepszeniu", tr.phase == tr.GATHER and not tut.showing)
	main.launch()
	if tr.phase == tr.CONTROLS:
		tr.skip_controls()   # ćwiczenia sterowania sprawdza training_controls.gd
	await _wait(2.5)
	_expect("ponowny lot: nadal bez okienek o tarczy i odbudowie", tr.phase == tr.GATHER and not tut.showing)
	_expect("tarcza Roswell nadal stoi", not main.world.protected.is_empty())
	# komplet surowców
	gs.add_cargo("biomass", 30)
	gs.add_cargo("stone", 25)
	main.dock("test", true, true)
	await _wait(2.0)
	_expect("dok z surowcami: faza UPGRADE i okienko 'ulepsz laser'", tr.phase == tr.UPGRADE and tut.showing and tut.cstep == tr.MAIN_STEP + 1)
	await _close()
	gs.buy(Upgrades.by_id("laser_dmg"))
	await _wait(2.0)
	_expect("po zakupie: faza DESTROY i okienko o tarczy", tr.phase == tr.DESTROY and tut.showing and tut.cstep == tr.MAIN_STEP + 2)
	await _close()
	await _wait(2.0)
	_expect("Roswell stoi: brak okienka o odbudowie", tr.phase == tr.DESTROY and not tut.showing)
	_log("błędów: %d" % bad)
	quit()
