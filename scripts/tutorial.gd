extends Control
## Prosty samouczek dla nowego gracza: kolejne okienka (pop-upy) pojawiają się,
## gdy gracz dochodzi do danej mechaniki. Okienko zamyka ENTER lub przycisk OK;
## "Pomiń samouczek" wyłącza go na stałe. Postęp zapisuje się w GameState.tutorial_step.
## Okienko rozwija się z jasnej kreski, tekst wpisuje się jak na terminalu,
## a po zamknięciu panel pęka i rozsypuje się na odłamki.

const Style = preload("res://scripts/style.gd")
const DONE := 999
const W := 620.0
const BODY := 15                 # rozmiar tekstu
const LINE_H := 24.0
const KEY_FS := 13               # napis na klawiszu
const KEY_COL := 170.0           # gdzie zaczyna się opis w liście sterowania
const TYPE_SPEED := 110.0        # znaków na sekundę
const OPEN_TIME := 0.42          # rozwinięcie panelu
const SHARD_LIFE := 0.9

var ship: Node2D
var enemies: Node2D
var font: Font
var font_b: Font
var pf: Font

var showing := false
var wait := 0.8          # krótka przerwa między okienkami
var open_t := 0.0        # czas od pojawienia się okienka
var typed := 0.0         # ile znaków tekstu już widać
var time := 0.0
var ok_rect := Rect2()
var skip_rect := Rect2()
var hover := ""          # "ok" / "skip" - do dźwięku najechania
var press_t := 0.0       # wciśnięcie przycisku OK (krótki błysk)
var shards: Array = []   # odłamki rozbitego okienka: {pos, vel, rot, spin, size, life, max, col, fill}
var sparks: Array = []
var flash_rect := Rect2()
var flash_t := 0.0
var last_rect := Rect2()
var tick_acc := 0
var layout: Array = []   # połamany tekst bieżącego okienka (pamięć podręczna _lines)
var layout_src := ""

## [tytuł, tekst, cel podświetlenia, ikona]
const STEPS := [
	["CZOŁEM, KAPITANIE!",
		"Jesteś dowódcą elitarnej jednostki ekstrakcyjnej Imperium Vex. Twoja baza wypadowa to Statek Matka - tu rozładowujesz łup i ulepszasz swój okręt.\n\nNaciśnij WYLOT [{dock}], żeby wyruszyć na Ziemię.", "", "crown"],
	["STEROWANIE",
		"Twój statek zawsze obraca się dziobem w kierunku kursora.\n\n[PPM] lub [{thrust}] :: silniki, lecisz do przodu\n[{brake}] :: hamulec\n[{stop}] :: pełny stop\n[{left}] [{right}] :: ruch w bok\n[{drift}] :: drift: przytrzymaj, by ślizgać się bokiem, a następnie puść, by wybić się do przodu. Generuje to wystrzał plazmy, który rani wszystko, czego dotknie.\n[KÓŁKO MYSZY] :: przybliżanie i oddalanie mapy", "", "rotate"],
	["LASER",
		"Przytrzymaj [LPM], celując w kafelek, żeby go wydobyć. Z lasów pozyskasz drewno, z gór kamień, miasta to głównie złom i metal. W przypadku tych ostatnich bądź ostrożny - strzegą ich wieżyczki i ziemskie myśliwce.\n\nPod niektórymi kafelkami kryją się cenne ZŁOŻA (miedź, żelazo, złoto...).", "", "bolt"],
	["ŁADOWNIA",
		"Wydobyte surowce trafiają do ładowni - pasek po lewej u góry i łuk wokół statku obrazują, ile wolnego miejsca jeszcze zostało.\n\nGdy ładownia jest pełna, nic więcej nie zbierzesz. Wtedy wracaj do bazy wypadowej.", "cargo", "crate"],
	["PALIWO",
		"Lot zużywa paliwo - widać to na pasku na samym dole ekranu. Bez paliwa statek traci moc, laser gaśnie, a kadłub się rozpada. Lepiej nie sprawdzaj co się stanie, kiedy stracisz je całe.\n\nZłota strzałka z podpisem \"MATKA\" zawsze wskazuje drogę do domu.", "fuel", "fuel"],
	["CZAS WRACAĆ",
		"Leć do statku matki i naciśnij [{dock}], żeby zadokować. Ładunek zostanie przeniesiony do magazynu, a paliwo uzupełnione.", "", "warp"],
	["ULEPSZENIA",
		"Kliknij kafelek ulepszeń na siatce, żeby je wykupić za zebrane surowce.\n\nSiatkę przesuwasz myszką, kółkiem przybliżasz i oddalasz.", "", "wrench"],
	["UWAGA - ZIEMIA KONTRATAKUJE!",
		"Miast bronią wieżyczki, a niszczenie miast ściąga ziemskie myśliwce. Możesz je zestrzelić laserem.\n\nZniszczenie statku oznacza utratę całego ładunku - pilnuj kadłuba!", "", "shield"],
]


func _ready() -> void:
	font = Style.font()
	font_b = Style.font_bold()
	pf = Style.font_pixel()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# okienko w locie pauzuje grę, a samouczek musi dalej działać i odbierać klawisze
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	get_tree().paused = false


func _cond(step: int) -> bool:
	var docked: bool = ship.docked
	var mf := maxf(1.0, GameState.stat("max_fuel"))
	var cfr := float(GameState.cargo_total()) / maxf(1.0, GameState.cargo_cap())
	match step:
		0: return docked
		1, 2: return not docked
		3: return not docked and GameState.cargo_total() > 0
		4: return not docked and ship.fuel < mf * 0.75
		5: return not docked and (cfr >= 0.5 or ship.fuel < mf * 0.4)
		6: return docked and GameState.sorties >= 1
		7: return not docked and (ship.hull < GameState.stat("max_hull") - 0.5 or (enemies != null and enemies.alive_count() > 0))
	return false


func _process(delta: float) -> void:
	time += delta
	_update_shards(delta)
	if GameState.in_boss or GameState.pause_menu:
		return
	var step := GameState.tutorial_step
	if step >= STEPS.size():
		showing = false
		visible = not shards.is_empty() or not sparks.is_empty() or flash_t > 0.0
		if visible:
			queue_redraw()
		return
	visible = true
	# gracz wyleciał, zanim zamknął (lub zobaczył) powitanie - zostało wykonane
	if step == 0 and not ship.docked:
		if showing:
			_dismiss()
		else:
			GameState.tutorial_step += 1
		queue_redraw()
		return
	# okienko nieaktualne (np. "Ulepszenia" po wylocie) - znika i wróci, gdy warunek znów będzie spełniony
	if showing and not _cond(step):
		showing = false
		wait = 0.8
	if showing:
		var was := open_t
		open_t += delta
		if was < OPEN_TIME and open_t >= OPEN_TIME:
			Audio.play("ui_click", 0.05, -4.0)
		if open_t > OPEN_TIME:
			var before := int(typed)
			typed += delta * TYPE_SPEED
			# ciche tykanie terminala co kilka znaków
			tick_acc += int(typed) - before
			if tick_acc >= 5 and typed < _text_len():
				tick_acc = 0
				Audio.play("hit_tick", 0.15, -20.0)
		press_t = maxf(0.0, press_t - delta)
	else:
		# gracz zadokował, zanim zobaczył "Czas wracać" - przejdź od razu do ulepszeń
		if step == 5 and ship.docked and GameState.sorties >= 1:
			GameState.tutorial_step = 6
			step = 6
		wait -= delta
		if wait <= 0.0 and not ship.dead and _cond(step):
			Audio.play("popup", 0.0)
			showing = true
			open_t = 0.0
			typed = 0.0
			tick_acc = 0
			if not ship.docked:
				Audio.stop_loops()
				get_tree().paused = true
	queue_redraw()


func _text_len() -> int:
	var n := 0
	for l in _lines():
		for s in l["segs"]:
			n += String(s[0]).length()
	return n


func _typing() -> bool:
	return typed < _text_len()


## Zamknięcie okienka: panel rozpada się na odłamki, a samouczek idzie dalej.
func _dismiss() -> void:
	_shatter()
	showing = false
	get_tree().paused = false
	GameState.tutorial_step += 1
	wait = 0.8


func _skip() -> void:
	_shatter()
	showing = false
	get_tree().paused = false
	GameState.tutorial_step = DONE


func _input(event: InputEvent) -> void:
	if not showing or open_t < OPEN_TIME * 0.7 or GameState.pause_menu:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER:
			_confirm()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var h := "ok" if ok_rect.has_point(event.position) else ("skip" if skip_rect.has_point(event.position) else "")
		if h != hover and h != "":
			Audio.play("ui_hover", 0.05)
		hover = h
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if ok_rect.has_point(event.position):
			_confirm()
			get_viewport().set_input_as_handled()
		elif skip_rect.has_point(event.position):
			Audio.play("ui_click", 0.0)
			_skip()
			get_viewport().set_input_as_handled()


## ENTER / OK: najpierw dopisuje resztę tekstu, drugie wciśnięcie zamyka okienko.
func _confirm() -> void:
	Audio.play("ui_click", 0.0)
	if _typing():
		typed = float(_text_len())
		press_t = 0.12
		return
	_dismiss()


func _target_rect(key: String, vs: Vector2) -> Rect2:
	match key:
		"cargo": return Rect2(12, 86, 314, 46)
		"fuel": return Rect2(4, vs.y - 48, vs.x - 8, 44)
	return Rect2()


# ---------------- tekst ----------------

## Szerokość ramki klawisza [X].
func _key_w(k: String) -> float:
	return maxf(font_b.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_FS).x + 16.0, 26.0)


## Słowa akapitu jako segmenty: [tekst, czy klawisz]. Klawisz to fragment w nawiasach [ ].
func _words(para: String) -> Array:
	var out: Array = []
	var rx := RegEx.create_from_string("\\[([^\\]]+)\\]|[^\\s\\[]+")
	for m in rx.search_all(para):
		if m.get_string(1) != "":
			out.append([m.get_string(1), true])
		else:
			out.append([m.get_string(0), false])
	return out


## Łamie słowa na linie od pozycji x0 do szerokości maxw. Każda linia: tablica [tekst, klawisz, x].
func _wrap(words: Array, x0: float, maxw: float) -> Array:
	var lines: Array = []
	var cur: Array = []
	var x := x0
	var space := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, BODY).x
	var prev_key := false
	for wd in words:
		# znak interpunkcyjny tuż po klawiszu ("[E],") przykleja się do niego bez spacji
		if not wd[1] and not cur.is_empty() and String(wd[0]).left(1) in [",", ".", ";", ":", "!", "?", ")"]:
			x -= space + (2.0 if prev_key else 0.0)
		prev_key = wd[1]
		var w: float = _key_w(wd[0]) if wd[1] else font.get_string_size(wd[0], HORIZONTAL_ALIGNMENT_LEFT, -1, BODY).x
		if not cur.is_empty() and x + w > x0 + maxw:
			lines.append(cur)
			cur = []
			x = x0
		cur.append([wd[0], wd[1], x])
		x += w + space + (4.0 if wd[1] else 0.0)
	if not cur.is_empty():
		lines.append(cur)
	return lines


## Układ tekstu bieżącego okienka: linie {segs, h}, łamane raz, więc wpisywanie litera po literze
## nie przeskakuje między wierszami. Akapit "[klawisze] :: opis" to wiersz listy sterowania:
## klawisze w lewej kolumnie, opis wyrównany obok.
func _lines() -> Array:
	var step := GameState.tutorial_step
	if step >= STEPS.size():
		return []
	var text: String = GameState.keys_text(STEPS[step][1])
	if text == layout_src:
		return layout
	var maxw := W - 64.0
	var out: Array = []
	layout_src = text
	layout = out
	for para in text.split("\n"):
		if para.strip_edges() == "":
			out.append({"segs": [], "h": 10.0})
			continue
		if " :: " in para:
			var parts := para.split(" :: ", true, 1)
			var keys: Array = []
			var x := 0.0
			for wd in _words(parts[0]):
				keys.append([wd[0], wd[1], x])
				x += (_key_w(wd[0]) + 6.0) if wd[1] else font.get_string_size(wd[0] + " ", HORIZONTAL_ALIGNMENT_LEFT, -1, BODY).x
			var desc := _wrap(_words(parts[1]), KEY_COL, maxw - KEY_COL)
			for i in desc.size():
				var segs: Array = (keys + desc[i]) if i == 0 else desc[i]
				out.append({"segs": segs, "h": LINE_H + (8.0 if i == desc.size() - 1 else 0.0)})
			continue
		for l in _wrap(_words(para), 0.0, maxw):
			out.append({"segs": l, "h": LINE_H})
	return out


func _panel_rect(vs: Vector2, lines: Array) -> Rect2:
	var th := 0.0
	for l in lines:
		th += float(l["h"])
	var h := 104.0 + th + 70.0
	var pos := Vector2(vs.x * 0.5 - W * 0.5, vs.y - 120 - h)
	if STEPS[GameState.tutorial_step][2] == "fuel":
		pos.y -= 20
	return Rect2(pos, Vector2(W, h))


# ---------------- rozpad ----------------

func _shatter() -> void:
	var r := last_rect
	if r.size == Vector2.ZERO:
		return
	Audio.play("blast_shatter", 0.1, -6.0)
	flash_rect = r
	flash_t = 0.18
	var cols := 14
	var rows := maxi(4, int(r.size.y / 42.0))
	var cw := r.size.x / cols
	var ch := r.size.y / rows
	var c := r.get_center()
	for y in rows:
		for x in cols:
			var p := r.position + Vector2((x + 0.5) * cw, (y + 0.5) * ch) + Vector2(randf_range(-6, 6), randf_range(-6, 6))
			var out := (p - c) / (r.size * 0.5)
			var edge: bool = x == 0 or y == 0 or x == cols - 1 or y == rows - 1
			var life := SHARD_LIFE * randf_range(0.65, 1.0)
			shards.append({"pos": p, "vel": Vector2(out.x * randf_range(140, 320), out.y * randf_range(80, 220) - randf_range(60, 200)),
				"rot": randf_range(-0.2, 0.2), "spin": randf_range(-7.0, 7.0), "size": Vector2(cw, ch) * randf_range(0.7, 1.05),
				"life": life, "max": life, "col": Style.GOLD if edge else Style.PINK, "edge": edge})
	for k in 40:
		var p := r.position + Vector2(randf() * r.size.x, randf() * r.size.y)
		var life := randf_range(0.3, 0.7)
		sparks.append({"pos": p, "vel": (p - c).normalized() * randf_range(250, 600), "life": life, "max": life,
			"col": Style.GOLD if randf() < 0.5 else Style.CYAN})


func _update_shards(delta: float) -> void:
	flash_t = maxf(0.0, flash_t - delta)
	var k := shards.size() - 1
	while k >= 0:
		var s: Dictionary = shards[k]
		s["life"] -= delta
		if s["life"] <= 0.0:
			shards.remove_at(k)
		else:
			s["vel"] += Vector2(0, 900.0) * delta
			s["pos"] += s["vel"] * delta
			s["rot"] += s["spin"] * delta
		k -= 1
	k = sparks.size() - 1
	while k >= 0:
		var p: Dictionary = sparks[k]
		p["life"] -= delta
		if p["life"] <= 0.0:
			sparks.remove_at(k)
		else:
			p["vel"] *= exp(-4.0 * delta)
			p["pos"] += p["vel"] * delta
		k -= 1
	if not showing and (not shards.is_empty() or not sparks.is_empty() or flash_t > 0.0):
		queue_redraw()


func _draw_shards() -> void:
	if flash_t > 0.0:
		var f := flash_t / 0.18
		draw_rect(flash_rect.grow(6.0 * (1.0 - f)), Color(1.4, 1.2, 1.3, 0.35 * f))
	for s in shards:
		var a: float = s["life"] / s["max"]
		var sz: Vector2 = s["size"] * (0.6 + 0.4 * a)
		var c: Color = s["col"]
		draw_set_transform(s["pos"], s["rot"], Vector2.ONE)
		var poly := PackedVector2Array([Vector2(-sz.x * 0.5, -sz.y * 0.5), Vector2(sz.x * 0.5, -sz.y * 0.35),
			Vector2(sz.x * 0.4, sz.y * 0.5), Vector2(-sz.x * 0.45, sz.y * 0.4)])
		var fc := Color(0.1, 0.03, 0.13, 0.95 * a)
		draw_primitive(poly, PackedColorArray([fc, fc, fc, fc]), PackedVector2Array())
		poly.append(poly[0])
		draw_polyline(poly, Color(c.r * 1.2, c.g * 1.2, c.b * 1.2, a), 2.0 if s["edge"] else 1.2, true)
	draw_set_transform(Vector2.ZERO)
	for p in sparks:
		var a: float = p["life"] / p["max"]
		var c: Color = p["col"]
		draw_line(p["pos"], p["pos"] - p["vel"] * 0.03, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, a), 2.0)


# ---------------- rysowanie ----------------

func _draw() -> void:
	if showing:
		_draw_popup()
	_draw_shards()


func _draw_popup() -> void:
	var vs := get_viewport_rect().size
	var step := GameState.tutorial_step
	var st: Array = STEPS[step]
	var lines := _lines()
	var full := _panel_rect(vs, lines)
	last_rect = full
	var k := clampf(open_t / OPEN_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var pulse := 0.5 + 0.5 * sin(time * 4.0)
	# przyciemnienie tła, żeby okienko było czytelne
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.0, 0.02, 0.35 * e))

	# podświetlenie elementu HUD, którego dotyczy okienko
	var hl := _target_rect(st[2], vs)
	if hl.size != Vector2.ZERO and k >= 1.0:
		var hp := 0.5 + 0.5 * sin(time * 6.0)
		draw_rect(hl.grow(4.0 + hp * 4.0), Color(Style.GOLD.r, Style.GOLD.g, Style.GOLD.b, 0.5 + 0.5 * hp), false, 2.5)

	# rozwinięcie: najpierw jasna kreska rośnie wszerz, potem panel otwiera się w pionie
	var wk := clampf(k / 0.45, 0.0, 1.0)
	var hk := clampf((k - 0.35) / 0.65, 0.0, 1.0)
	var hk_e := 1.0 - pow(1.0 - hk, 3.0)
	var cw := full.size.x * (1.0 - pow(1.0 - wk, 3.0))
	var chh := maxf(4.0, full.size.y * hk_e)
	var r := Rect2(full.get_center() - Vector2(cw, chh) * 0.5, Vector2(cw, chh))
	if hk <= 0.0:
		draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), Color(1.4, 1.2, 1.3, 0.9), 3.0)
		draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), Color(1.0, 0.35, 0.8, 0.4), 10.0)
		return
	# migotanie przy otwieraniu
	var flick := 1.0 if hk >= 1.0 or fmod(time * 40.0, 1.0) > 0.25 else 0.6
	var gold := Style.GOLD
	var pink := Style.PINK
	# poświata
	for g in 4:
		var halo := Style.chamfer_pts(r.grow(4.0 + g * 4.0), 16.0 + g * 3.0)
		draw_polyline(Style.closed(halo), Color(pink.r, pink.g, pink.b, (0.22 - g * 0.05) * (0.7 + 0.3 * pulse) * flick), 3.0, true)
	# przy otwieraniu panel bywa niski - ścięcie rogów nie może być większe niż on sam
	var plate := Style.chamfer_pts(r, minf(16.0, r.size.y * 0.3))
	draw_colored_polygon(plate, Color(0.05, 0.01, 0.08, 0.97))
	# delikatne linie skanowania i przesuwający się pas światła
	var y := r.position.y + 2.0
	while y < r.end.y - 2.0:
		draw_line(Vector2(r.position.x + 4, y), Vector2(r.end.x - 4, y), Color(1.0, 0.4, 0.9, 0.025), 1.0)
		y += 4.0
	var sweep := r.position.y + fmod(time * 0.35, 1.0) * r.size.y
	draw_rect(Rect2(r.position.x + 2, sweep, r.size.x - 4, 14), Color(1.0, 0.5, 0.9, 0.04))
	draw_polyline(Style.closed(plate), Color(pink.r * 1.2, pink.g * 1.2, pink.b * 1.2, flick), 2.4, true)
	draw_polyline(Style.closed(Style.chamfer_pts(r.grow(-6), 12.0)), Color(gold.r, gold.g, gold.b, 0.35 * flick), 1.0, true)
	# narożne klamry
	var bl := 22.0
	for corner in [[Vector2(r.end.x + 5, r.position.y - 5), Vector2(-1, 0), Vector2(0, 1)],
			[Vector2(r.position.x - 5, r.end.y + 5), Vector2(1, 0), Vector2(0, -1)]]:
		var p0: Vector2 = corner[0]
		draw_line(p0, p0 + corner[1] * bl, gold, 2.4, true)
		draw_line(p0, p0 + corner[2] * bl, gold, 2.4, true)
	if hk < 1.0:
		return

	# ---- nagłówek: ikona kroku, licznik, kropki postępu, tytuł
	var ic := r.position + Vector2(52, 54)
	var hex := PackedVector2Array()
	for i in 6:
		hex.append(ic + Vector2.from_angle(PI / 6.0 + i * TAU / 6.0) * 30.0)
	draw_colored_polygon(hex, Color(0.18, 0.1, 0.02))
	for t in 10:
		var a := time * 0.8 + t * TAU / 10.0
		draw_line(ic + Vector2.from_angle(a) * 34.0, ic + Vector2.from_angle(a) * 38.0, Color(gold.r, gold.g, gold.b, 0.6), 1.5, true)
	draw_polyline(Style.closed(hex), Color(gold.r * 1.25, gold.g * 1.25, gold.b * 1.25), 2.2, true)
	Style.draw_icon(self, st[3], ic, 14.0, Color(1.3, 1.05, 0.5), 2.0)
	var tx := r.position.x + 98
	draw_string(font_b, Vector2(tx, r.position.y + 30), "SAMOUCZEK  %d / %d" % [step + 1, STEPS.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(pink.r, pink.g, pink.b, 0.95))
	for i in STEPS.size():
		var dp := Vector2(r.end.x - 34 - (STEPS.size() - 1 - i) * 16, r.position.y + 26)
		var dq := PackedVector2Array([dp + Vector2(0, -4), dp + Vector2(4, 0), dp + Vector2(0, 4), dp + Vector2(-4, 0)])
		if i < step:
			draw_colored_polygon(dq, Color(gold.r, gold.g, gold.b, 0.7))
		elif i == step:
			draw_colored_polygon(dq, Color(1.3, 1.1, 0.6))
			draw_polyline(Style.closed(PackedVector2Array([dp + Vector2(0, -7), dp + Vector2(7, 0), dp + Vector2(0, 7), dp + Vector2(-7, 0)])), Color(gold.r, gold.g, gold.b, 0.4 + 0.6 * pulse), 1.2, true)
		else:
			draw_polyline(Style.closed(dq), Color(0.5, 0.42, 0.6), 1.0, true)
	var title: String = st[0]
	var tfs := 28
	while tfs > 16 and pf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x > r.end.x - tx - 20:
		tfs -= 2
	draw_string(pf, Vector2(tx + 2, r.position.y + 68 + 2), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(0.2, 0.9, 1.0, 0.5))
	draw_string(pf, Vector2(tx, r.position.y + 68), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(1.3, 1.0, 0.45))
	draw_line(Vector2(r.position.x + 24, r.position.y + 92), Vector2(r.end.x - 24, r.position.y + 92), Color(gold.r, gold.g, gold.b, 0.4), 1.0)

	# ---- treść: wpisywana litera po literze, z migającym kursorem
	var left := int(typed)
	var ty := r.position.y + 120
	var x0 := r.position.x + 32
	var cur := Vector2(x0, ty)
	for l in lines:
		if left <= 0:
			break
		for s in l["segs"]:
			if left <= 0:
				break
			var txt: String = s[0]
			var sx: float = x0 + float(s[2])
			if s[1]:
				# klawisz: pogrubiony napis w złotej ramce, pojawia się w całości
				var kw := _key_w(txt)
				var kr := Rect2(sx, ty - 16, kw, 22)
				var kp := Style.chamfer_pts(kr, 4.0)
				draw_colored_polygon(kp, Color(0.22, 0.14, 0.03))
				draw_polyline(Style.closed(kp), Color(gold.r * 1.2, gold.g * 1.2, gold.b * 1.2), 1.6, true)
				draw_line(Vector2(kr.position.x + 4, kr.end.y + 1), Vector2(kr.end.x - 1, kr.end.y + 1), Color(gold.r, gold.g, gold.b, 0.45), 2.0)
				var tw := font_b.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_FS).x
				draw_string(font_b, Vector2(kr.get_center().x - tw * 0.5, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_FS, Color(1.35, 1.15, 0.6))
				cur = Vector2(kr.end.x + 4, ty)
			else:
				var shown := txt.substr(0, mini(left, txt.length()))
				draw_string(font, Vector2(sx, ty), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY, Color(0.95, 0.9, 1.0))
				cur = Vector2(sx + font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY).x + 2, ty)
			left -= txt.length()
		ty += float(l["h"])
	if _typing() or fmod(time, 1.0) < 0.5:
		draw_rect(Rect2(cur + Vector2(0, -13), Vector2(8, 15)), Color(pink.r, pink.g, pink.b, 0.85))

	# ---- przyciski
	ok_rect = Rect2(r.end.x - 184, r.end.y - 54, 160, 36)
	var hov_ok := hover == "ok"
	var ok_c := gold if not _typing() else Color(0.6, 0.55, 0.7)
	var obr := ok_rect.grow(2.0 if hov_ok else 0.0)
	var okp := Style.chamfer_pts(obr, 8.0)
	draw_colored_polygon(okp, Color(0.32, 0.22, 0.04) if hov_ok or press_t > 0.0 else Color(0.14, 0.09, 0.02))
	draw_polyline(Style.closed(okp), Color(ok_c.r * 1.2, ok_c.g * 1.2, ok_c.b * 1.2) if hov_ok else ok_c, 2.0, true)
	if not _typing():
		# biegnące szewrony zachęcają do kliknięcia
		for j in 2:
			var cx := obr.end.x - 22.0 - j * 9.0
			var aa := 0.25 + 0.75 * fmod(time * 1.8 + j * 0.5, 1.0)
			draw_polyline(PackedVector2Array([Vector2(cx - 3, obr.get_center().y - 6), Vector2(cx + 3, obr.get_center().y), Vector2(cx - 3, obr.get_center().y + 6)]), Color(gold.r, gold.g, gold.b, aa), 1.8, true)
	var ok_t := "OK  [ENTER]" if not _typing() else "DALEJ  [ENTER]"
	draw_string(font_b, Vector2(obr.position.x + 18, obr.position.y + 23), ok_t, HORIZONTAL_ALIGNMENT_LEFT, obr.size.x - 40, 14, Color(1.3, 1.1, 0.6) if hov_ok else ok_c)
	var sk_t := "Pomiń samouczek"
	var sw := font.get_string_size(sk_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	skip_rect = Rect2(r.position.x + 22, r.end.y - 48, sw + 16, 26)
	var hov_sk := hover == "skip"
	if hov_sk:
		draw_line(Vector2(skip_rect.position.x + 8, skip_rect.end.y - 4), Vector2(skip_rect.end.x - 8, skip_rect.end.y - 4), Color(0.75, 0.65, 0.9, 0.7), 1.0)
	draw_string(font, skip_rect.position + Vector2(8, 17), sk_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.7, 0.95) if hov_sk else Color(0.5, 0.42, 0.62))
