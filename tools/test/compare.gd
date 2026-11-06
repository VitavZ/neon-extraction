extends SceneTree
## Porównuje zrzuty z dwóch katalogów (np. przed i po zmianie): odsetek pikseli, które różnią się wyraźnie.
## Animacje dają kilka procent szumu; dziesiątki procent oznaczają, że ekran wygląda inaczej.
## Użycie: Godot_console.exe --headless --path . --script res://tools/test/compare.gd -- <katalog_A> <katalog_B>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("[CMP] podaj dwa katalogi")
		quit(1)
		return
	var a_dir: String = args[0]
	var b_dir: String = args[1]
	for f in DirAccess.get_files_at(a_dir):
		if not f.ends_with(".png"):
			continue
		var bp := b_dir.path_join(f)
		if not FileAccess.file_exists(bp):
			print("[CMP] %-24s brak w B" % f)
			continue
		var a := Image.load_from_file(a_dir.path_join(f))
		var b := Image.load_from_file(bp)
		if a.get_size() != b.get_size():
			print("[CMP] %-24s inny rozmiar" % f)
			continue
		# porównanie na pomniejszonych obrazach: szybkie i odporne na drobne przesunięcia
		a.resize(a.get_width() / 4, a.get_height() / 4, Image.INTERPOLATE_BILINEAR)
		b.resize(b.get_width() / 4, b.get_height() / 4, Image.INTERPOLATE_BILINEAR)
		var diff := 0
		var total := a.get_width() * a.get_height()
		for y in a.get_height():
			for x in a.get_width():
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.25:
					diff += 1
		print("[CMP] %-24s %5.1f%%" % [f, 100.0 * diff / total])
	quit()
