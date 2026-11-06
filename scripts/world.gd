extends Node2D
## Mapa USA: 6 sektorów po 160x160 kafelków połączonych w jeden świat (patrz sectors.gd).
## Teren z us_map_data.gd, rysowanie wektorowe (w chunkach), niszczenie kafelków,
## złoża pod powierzchnią, wieżyczki obronne Ziemian i ich pociski.

signal tile_destroyed(idx: int, world_pos: Vector2, drops: Dictionary, info: String)
## Kafelek rozbity obrażeniami (src: laser, splash, chain, blast, rocket...) - do efektów typu detonacja.
signal tile_broken(idx: int, src: String)
signal city_destroyed(world_pos: Vector2)
signal tile_rebuilt(idx: int)
signal tile_imperial_spread(idx: int)
signal missile_launched
signal metro_tile_destroyed(sector: int)
signal landmark_tile_destroyed(landmark: int)

const Sectors = preload("res://scripts/sectors.gd")
const MapData = preload("res://scripts/us_map_data.gd")
const Style = preload("res://scripts/style.gd")
const MeshPainter = preload("res://scripts/mesh_painter.gd")
const T := 48
const N: int = Sectors.W      # szerokość świata w kafelkach (i krok indeksu y * N + x)
const H: int = Sectors.H      # wysokość świata w kafelkach
const TOTAL: int = N * H
const CHUNK := 8
const CHUNK_COLS: int = N / CHUNK
const CHUNK_ROWS: int = H / CHUNK
const CHUNKS_PER_FRAME := 10
const TURRET_BUCKET := 16
const BORDER_FADE := 620.0
const BOSS_PORTAL_RADIUS := 130.0
const BORDER_DASH := 96.0

enum { DEEP, OCEAN, RIVER, SAND, PLAINS, FOREST, MOUNTAIN, SNOW, CITY, METRO, CAPITOL, PENTAGON }
enum { L_SURFACE, L_DEPOSIT, L_CRATER, L_IMPERIAL }

const TILE_DEFS := [
	{"name": "Głęboki ocean", "hp": 60.0, "fill": Color(0.02, 0.03, 0.16), "line": Color(0.14, 0.26, 1.25), "drops": {"saltwater": 7}},
	{"name": "Ocean", "hp": 35.0, "fill": Color(0.03, 0.06, 0.24), "line": Color(0.11, 0.57, 1.25), "drops": {"saltwater": 4}},
	{"name": "Rzeka / jezioro", "hp": 25.0, "fill": Color(0.03, 0.12, 0.27), "line": Color(0.16, 0.99, 1.25), "drops": {"water": 4}},
	{"name": "Plaża", "hp": 20.0, "fill": Color(0.19, 0.11, 0.16), "line": Color(1.25, 0.85, 0.34), "drops": {"sand": 3}},
	{"name": "Równina", "hp": 20.0, "fill": Color(0.07, 0.09, 0.13), "line": Color(0.66, 1.25, 0.44), "drops": {"biomass": 3}},
	{"name": "Las", "hp": 30.0, "fill": Color(0.03, 0.13, 0.1), "line": Color(0.17, 1.25, 0.45), "drops": {"wood": 4}},
	{"name": "Góry", "hp": 70.0, "fill": Color(0.13, 0.05, 0.19), "line": Color(0.83, 0.31, 1.25), "drops": {"stone": 5}},
	{"name": "Szczyt", "hp": 90.0, "fill": Color(0.17, 0.11, 0.25), "line": Color(0.91, 0.91, 1.25), "drops": {"stone": 3, "water": 3}},
	{"name": "Miasto", "hp": 80.0, "fill": Color(0.15, 0.03, 0.15), "line": Color(1.25, 0.19, 0.82), "drops": {"scrap": 5, "metal": 2, "electronics": 0.35}},
	{"name": "Metropolia", "hp": 130.0, "fill": Color(0.2, 0.03, 0.2), "line": Color(1.25, 0.3, 1.0), "drops": {"scrap": 8, "metal": 4, "electronics": 0.8}},
	{"name": "Kapitol", "hp": 260.0, "fill": Color(0.18, 0.12, 0.05), "line": Color(1.25, 0.95, 0.5), "drops": {"scrap": 10, "metal": 6, "electronics": 2, "gold": 0.3}},
	{"name": "Pentagon", "hp": 320.0, "fill": Color(0.12, 0.08, 0.18), "line": Color(1.25, 0.35, 0.3), "drops": {"metal": 8, "electronics": 3, "weapon_scrap": 1.5}},
]

const DEP_DEFS := [
	{},
	{"name": "Złoże miedzi", "hp": 120.0, "color": Color(1.25, 0.47, 0.18), "drops": {"copper": 4}},
	{"name": "Złoże żelaza", "hp": 150.0, "color": Color(1.25, 1.1, 1.25), "drops": {"iron": 5}},
	{"name": "Złoże złota", "hp": 220.0, "color": Color(1.25, 0.94, 0.13), "drops": {"gold": 2}},
	{"name": "Złoże uranu", "hp": 300.0, "color": Color(0.27, 1.25, 0.18), "drops": {"uranium": 2}},
	{"name": "Kryształy neonitu", "hp": 400.0, "color": Color(1.16, 0.18, 1.25), "drops": {"neonite": 1}},
]

const TURRET_RANGE := 430.0
const BULLET_SPEED := 300.0
const MISSILE_TURRET_CHANCE := 0.12   # udział wieżyczek rakietowych w miastach
const MISSILE_TURRET_MIN_DANGER := 25.0
const MISSILE_RANGE := 720.0
## Dodatkowe złoża miedzi: próg szansy na złoże mnożony przez ten współczynnik (nadwyżka to sama miedź).
const COPPER_BONUS := 1.15
## Ile najbliższych okręgów zasięgu wieżyczek rysuje się w pełnej jakości (reszta: sama linia).
const RING_FULL_DETAIL := 6
## Najwięcej okręgów naraz (najbliższe statkowi); w gęstych miastach dalsze i tak zlewają się w jedno.
const RING_MAX := 12
const HEX_UNIT := [Vector2(1, 0), Vector2(0.5, 0.866025), Vector2(-0.5, 0.866025), Vector2(-1, 0), Vector2(-0.5, -0.866025), Vector2(0.5, -0.866025), Vector2(1, 0)]
const MISSILE_MAX := 6
const MISSILE_SPEED_MIN := 410.0
const MISSILE_ACCEL := 420.0
const MISSILE_TURN := 3.2
const MISSILE_LIFE := 7.5
const MISSILE_HP := 14.0
const MISSILE_HIT := 24.0
const MISSILE_LASER_RADIUS := 30.0

var surface := PackedByteArray()
var deposit := PackedByteArray()
var _ring_q: Array = []          # okręgi zasięgu do narysowania w tej klatce
var _ring_view := Rect2()
var show_ranges := true
var _idx_cache := PackedInt32Array()
var layer := PackedByteArray()
var hp := PackedFloat32Array()
var max_hp := PackedFloat32Array()
var turrets: Dictionary = {}   # idx -> {"cd": float, "angle": float}
var turret_buckets: Dictionary = {}   # kratka 16x16 kafelków -> indeksy wieżyczek (szybkie szukanie w pobliżu)
var bullets: Array = []        # {"pos","vel","life","dmg"}
var missiles: Array = []       # {"pos","rot","speed","life","hp","dmg"} - rakiety samonaprowadzające
var missile_beep := 0.0
var metro_total: Array = []    # liczba kafelków metropolii w każdym sektorze
var metro_left: Array = []     # ile jeszcze stoi
var metro_last: Array = []     # ostatnie 5%: kafelki podświetlone w każdym sektorze
var chunks: Array = []        # malarze (Node2D) rysujący kafelki fragmentu mapy
var dirty_chunks: Dictionary = {}
var chunk_ready := PackedByteArray()   # 1 = fragment ma zbudowaną siatkę
var built_chunks: Dictionary = {}
var tile_meshes: Dictionary = {}       # fragment -> trójkąty każdego z jego kafelków
var scan_center := -1                  # skaner: środek ostatniego przeszukania
var scan_tiles: Array = []             # złoża w zasięgu skanera
var chunk_free_timer := 0.0
var dock_cells: Array = []     # miejsce postoju Matki w każdym sektorze
var landmark_cells: Array = []  # środek obiektu specjalnego (Sectors.LANDMARKS)
var landmark_total: Array = []
var landmark_left: Array = []
var ally_turrets: Dictionary = {}   # idx -> {cd, angle} - wieżyczki Imperium w odbudowanych miastach
var ally_shots: Array = []          # {a, b, life}
var city_cells: Array = []     # środek metropolii w każdym sektorze
var city_near := PackedByteArray()   # 1 = kafelek blisko miasta (statki wydobywcze tam nie latają)
var playable := TOTAL                # kafelki poza sektorami oceanu (do procentów zniszczenia)
var escorts: Node2D                  # myśliwce towarzyszące gracza
var wingmen: Node2D                  # sojusznicy, w których celują wieżyczki i trafiają pociski
var miners: Node2D
var transit: Node2D
var mothership_ref: Node2D           # Statek Matka - trafiany pociskami tylko w czasie oblężenia
var combat_k := 0.0                  # przyciemnienie mapy w czasie walki (0..1)
var speed_k := 0.0                   # przyciemnienie mapy przy szybkim locie (0..1)
var overlay: Node2D            # wieżyczki, pociski, cel lasera
var scan_layer: Node2D         # podgląd złóż ze skanera
var minimap_img: Image
var minimap_tex: ImageTexture
var _minimap_dirty := false
var minimap_cd := 0.0
var target_idx := -1
var target_timer := 0.0
var ship: Node2D
var enemies: Node2D
var time := 0.0
var hit_glow := 0.0
var fx: Node2D                       # efekty (liczby obrażeń)
var dmg_acc: Dictionary = {}         # idx -> [suma, czas, źródło] - zbieranie obrażeń w liczby
var recent_hits: Dictionary = {}     # idx -> czas pokazywania paska HP pod kafelkiem
var tile_flash: Dictionary = {}      # idx -> błysk po trafieniu

const DMG_COLORS := {
	"laser": Color(1.0, 0.85, 0.35), "splash": Color(0.85, 0.55, 1.0), "rocket": Color(1.0, 0.55, 0.2),
	"drone": Color(0.4, 1.0, 0.9), "miner": Color(1.0, 0.8, 0.35), "gun": Color(1.0, 0.95, 0.6), "chain": Color(0.55, 0.85, 1.0), "blast": Color(1.3, 0.6, 0.25),
}

# --- warstwy biologiczne (laboratorium) ---
var abducted := PackedByteArray()   # 1 = z kafelka porwano już istoty
var imperial_count := 0
var devastated_count := 0         # kafelki zniszczone i jeszcze nieodbudowane (kratery i odkryte złoża)
var imperial_list: Array = []     # indeksy kafelków Imperium (do rozrostu)
var imp_spread_timer := 0.0
var power_acc := 0.0
## Ile sekund potrzebuje jeden kafelek Imperium, by wytworzyć 1 Potęgę (przy mnożniku 100%).
const POWER_SECONDS_PER_TILE := 120.0

const CREATURE_OF := {CITY: "humans", METRO: "humans", CAPITOL: "humans", PENTAGON: "humans", PLAINS: "cows", FOREST: "deer"}


func _ready() -> void:
	# OPTYMALIZACJA: mapa jest podzielona na fragmenty 8x8 kafelków (osobne węzły).
	# Godot zapamiętuje polecenia rysowania każdego węzła, więc fragment jest
	# przerysowywany tylko gdy zmieni się któryś z jego kafelków, a fragmenty
	# poza ekranem są automatycznie pomijane przy renderowaniu. Świat jest duży,
	# więc siatki powstają dopiero w pobliżu kamery i są zwalniane, gdy się oddali.
	chunk_ready.resize(CHUNK_COLS * CHUNK_ROWS)
	chunk_ready.fill(0)
	for cy in CHUNK_ROWS:
		for cx in CHUNK_COLS:
			var painter := Node2D.new()
			painter.name = "Chunk_%d_%d" % [cx, cy]
			add_child(painter)
			painter.draw.connect(_draw_chunk.bind(painter, cx, cy))
			chunks.append(painter)
	scan_layer = Node2D.new()
	scan_layer.z_index = 1
	add_child(scan_layer)
	scan_layer.draw.connect(_draw_scan)
	overlay = Node2D.new()
	overlay.z_index = 3
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)


# =====================================================================
# GENEROWANIE
# =====================================================================

func generate(seed_value: int) -> void:
	var total := TOTAL
	# teren jest stały (prawdziwa mapa USA), losowe są tylko złoża i wieżyczki
	surface = MapData.surface(total)
	city_near.clear()
	playable = TOTAL
	for s in Sectors.LIST.size():
		if Sectors.is_void(s):
			playable -= Sectors.SIZE * Sectors.SIZE
	deposit.resize(total)
	layer.resize(total)
	hp.resize(total)
	max_hp.resize(total)
	turrets.clear()
	ally_turrets.clear()
	turret_buckets.clear()
	bullets.clear()
	missiles.clear()
	abducted.resize(total)
	abducted.fill(0)

	dock_cells.clear()
	city_cells.clear()
	for s in Sectors.LIST:
		dock_cells.append(Sectors.cell_of(s["dock_lonlat"]))
		city_cells.append(Sectors.cell_of(s["city_lonlat"]))
	landmark_cells.clear()
	for lm in Sectors.LANDMARKS:
		landmark_cells.append(Sectors.cell_of(lm["lonlat"]))
	_stamp_metros()
	_stamp_landmarks()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 3
	# osobny generator: główny musi dawać te same złoża co w istniejących zapisach
	var kind_rng := RandomNumberGenerator.new()
	kind_rng.seed = seed_value * 13 + 5

	for y in H:
		for x in N:
			var i := y * N + x
			var t: int = surface[i]
			layer[i] = L_SURFACE
			var d := danger(x, y)
			hp[i] = TILE_DEFS[t]["hp"] * (1.0 + d / 90.0)
			max_hp[i] = hp[i]

			# złoża pod powierzchnią
			var chance := 0.05
			match t:
				MOUNTAIN: chance = 0.24
				SNOW: chance = 0.3
				DEEP: chance = 0.08
				SAND: chance = 0.08
				CITY, METRO: chance = 0.04
				CAPITOL, PENTAGON: chance = 0.08
			deposit[i] = 0
			# ten sam rzut co dawniej (bez zmiany kolejności losowania), a tuż nad progiem: dodatkowa miedź
			var dr := rng.randf()
			if dr < chance:
				deposit[i] = _roll_deposit(rng, d)
			elif dr < chance * COPPER_BONUS:
				deposit[i] = 1

			# wieżyczki obronne: wokół miejsc postoju Matki w każdym sektorze jest bezpiecznie
			var guard := _landmark_guard(x, y)
			if _dock_distance(x, y) / Sectors.SCALE > 13.0 or guard > 0.0:
				var tc := 0.0
				if t == CITY:
					tc = 0.06 + clampf((d - 13.0) / 50.0, 0.0, 1.0) * 0.3
				elif t == METRO:
					tc = 0.14 + clampf((d - 13.0) / 50.0, 0.0, 1.0) * 0.3
				elif (t == MOUNTAIN or t == SNOW) and d > 30.0:
					tc = 0.03
				# obiekty specjalne: gęsty pierścień wieżyczek, w samym kompleksie prawie co druga
				if t == CAPITOL or t == PENTAGON:
					tc = 0.45
				elif guard > 0.0 and t > RIVER:
					tc = maxf(tc, 0.12 + 0.2 * guard)
				if rng.randf() < tc:
					turrets[i] = {"cd": rng.randf_range(0.5, 2.0), "angle": rng.randf() * TAU}
					var missile_chance := 0.4 if guard > 0.0 else MISSILE_TURRET_CHANCE
					if (t == CITY or t == METRO or guard > 0.0) and (d > MISSILE_TURRET_MIN_DANGER or guard > 0.0) and kind_rng.randf() < missile_chance:
						turrets[i]["kind"] = "missile"
						turrets[i]["cd"] = kind_rng.randf_range(1.0, 5.0)
					var key := _bucket_key(x, y)
					if not turret_buckets.has(key):
						turret_buckets[key] = []
					turret_buckets[key].append(i)

	_count_metros()
	_build_minimap()
	_redraw_all()


## Liczy, ile kafelków metropolii stoi (start gry i po wczytaniu zapisu).
func _count_metros() -> void:
	var n: int = Sectors.LIST.size()
	metro_total.resize(n)
	metro_left.resize(n)
	metro_last.resize(n)
	metro_total.fill(0)
	metro_left.fill(0)
	for i in TOTAL:
		if surface[i] == METRO:
			var s := Sectors.sector_at(i % N, i / N)
			metro_total[s] += 1
			if layer[i] == L_SURFACE:
				metro_left[s] += 1
	for s in n:
		metro_last[s] = []
		_refresh_metro_last(s)
	landmark_total.resize(Sectors.LANDMARKS.size())
	landmark_left.resize(Sectors.LANDMARKS.size())
	landmark_total.fill(0)
	landmark_left.fill(0)
	for i in TOTAL:
		if surface[i] == CAPITOL or surface[i] == PENTAGON:
			var k := _landmark_of(i)
			landmark_total[k] += 1
			if layer[i] == L_SURFACE:
				landmark_left[k] += 1


## Na ostatnich 5% zbiera pozostałe kafelki, żeby gracz mógł je znaleźć.
func _refresh_metro_last(s: int) -> void:
	if metro_left[s] <= 0 or metro_left[s] > ceili(metro_total[s] * 0.05):
		metro_last[s] = []
		return
	var out: Array = []
	var r: Rect2i = Sectors.sector_rect(s)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i: int = y * N + x
			if surface[i] == METRO and layer[i] == L_SURFACE:
				out.append(i)
	metro_last[s] = out


## Następny punkt patrolu: zwykle kafelek miasta w okolicy, czasem dowolny punkt w regionie.
func patrol_point(from: Vector2) -> Vector2:
	if randf() < 0.7:
		for attempt in 24:
			var p := from + Vector2.from_angle(randf() * TAU) * randf_range(300.0, 1800.0)
			var i := pos_to_idx(p)
			if i >= 0 and _is_city(i):
				return idx_center(i)
	var q := from + Vector2.from_angle(randf() * TAU) * randf_range(600.0, 2200.0)
	q = q.clamp(Vector2(T, T), Vector2(N * T - T, H * T - T))
	if blocked_at(q):
		q = _exit_point(q)
	return q


## Czy pojazd naziemny może tu jechać: ląd (nie woda), w granicach mapy i w otwartym sektorze.
func ground_at(p: Vector2) -> bool:
	if p.x < T or p.y < T or p.x > N * T - T or p.y > H * T - T:
		return false
	var s := surface[pos_to_idx(p)]
	return s != DEEP and s != OCEAN and s != RIVER and not blocked_at(p)


## Punkt na lądzie, najczęściej w mieście: cel przejazdu czołgu.
func tank_point(from: Vector2) -> Vector2:
	for attempt in 30:
		var p := from + Vector2.from_angle(randf() * TAU) * randf_range(250.0, 1100.0)
		if not ground_at(p):
			continue
		if attempt < 20 and not _is_city(pos_to_idx(p)):
			continue
		return p
	return from


## Zamknięty sektor (Dystrykt Federalny przed zniszczeniem metropolii).
func blocked_at(p: Vector2) -> bool:
	return not GameState.sector_open(sector_at_pos(p))


## Najbliższe wyjście z zamkniętego sektora: [kierunek, odległość do krawędzi w pikselach].
## Krawędzie przy brzegu świata się nie liczą.
func _exit_of(p: Vector2) -> Array:
	var r: Rect2i = Sectors.sector_rect(sector_at_pos(p))
	var rp := Rect2(Vector2(r.position) * T, Vector2(r.size) * T)
	var best := [Vector2.ZERO, INF]
	var opts := [
		[Vector2.UP, p.y - rp.position.y, rp.position.y > 0.0],
		[Vector2.LEFT, p.x - rp.position.x, rp.position.x > 0.0],
		[Vector2.DOWN, rp.end.y - p.y, rp.end.y < H * T],
		[Vector2.RIGHT, rp.end.x - p.x, rp.end.x < N * T],
	]
	for o in opts:
		if o[2] and o[1] < best[1]:
			best = [o[0], o[1]]
	return best


func _exit_point(p: Vector2) -> Vector2:
	var e := _exit_of(p)
	return p + e[0] * (e[1] + T)


## Pole siłowe: w którą stronę wypchnąć statek z zamkniętego sektora (ZERO, gdy nie trzeba).
func barrier_push(p: Vector2) -> Vector2:
	if not blocked_at(p):
		return Vector2.ZERO
	return _exit_of(p)[0]


## Twarda ściana pola siłowego: statek tuż za granicą wraca na jej krawędź.
func barrier_clamp(p: Vector2) -> Vector2:
	if not blocked_at(p):
		return p
	var e := _exit_of(p)
	if e[1] < 240.0:
		return p + e[0] * (e[1] + 4.0)
	return p

# ---------------- statki wydobywcze ----------------

const MINER_SOURCES := {"wood": [FOREST], "stone": [MOUNTAIN, SNOW], "biomass": [PLAINS], "water": [RIVER], "saltwater": [OCEAN, DEEP],
	"sand": [SAND]}
## Tyle kafelków odstępu od miast trzymają statki wydobywcze: więcej niż zasięg wieżyczki (430 px = 9 kafelków).
const MINER_CITY_GAP := 12
## Złoże musi leżeć tak daleko od każdej wieżyczki (także górskiej).
const MINER_SAFE := TURRET_RANGE + 140.0
const MINER_DEPOSITS := {"copper": 1, "iron": 2, "gold": 3, "uranium": 4, "neonite": 5}


## Czy statek wydobywczy szukający danego surowca może kopać ten kafelek.
func miner_match(i: int, res: String) -> bool:
	if i < 0 or i >= TOTAL or turrets.has(i) or surface[i] >= CITY:
		return false
	if not GameState.sector_open(Sectors.sector_at(i % N, i / N)):
		return false
	if MINER_DEPOSITS.has(res):
		# bez Skanera planetarnego statki widzą tylko odsłonięte złoża, ze skanerem także ukryte pod ziemią
		if deposit[i] != MINER_DEPOSITS[res]:
			return false
		return layer[i] == L_DEPOSIT or (layer[i] == L_SURFACE and GameState.stat("miner_scan") > 0.0)
	return layer[i] == L_SURFACE and surface[i] in MINER_SOURCES.get(res, [])


## Najbliższy pasujący kafelek: szuka pierścieniami wokół statku, ale tylko w zasięgu Statku Matki.
func find_resource_tile(res: String, from: Vector2, center: Vector2, max_r: float, taken: Dictionary) -> int:
	var cx := clampi(int(from.x / T), 0, N - 1)
	var cy := clampi(int(from.y / T), 0, H - 1)
	var max_sq := max_r * max_r
	for r in range(0, 90):
		for dy in range(-r, r + 1):
			var row := absi(dy) == r
			var dx := -r
			while dx <= r:
				var x := cx + dx
				var y := cy + dy
				if x >= 0 and y >= 0 and x < N and y < H:
					var i := y * N + x
					if not taken.has(i) and miner_match(i, res) and idx_center(i).distance_squared_to(center) <= max_sq and miner_safe(i):
						return i
				dx += 1 if row else 2 * r
				if r == 0:
					break
	return -1


## Kafelek poza zasięgiem miast i wieżyczek: tam statki wydobywcze mogą bezpiecznie pracować.
func miner_safe(i: int) -> bool:
	if city_near.is_empty():
		_build_city_near()
	if city_near[i] == 1:
		return false
	var p := idx_center(i)
	for t in turrets_in_rect(Rect2(p, Vector2.ZERO).grow(MINER_SAFE)):
		if idx_center(t).distance_to(p) < MINER_SAFE:
			return false
	return true


## Mapa "blisko miasta" (kwadrat MINER_CITY_GAP wokół każdego kafelka miejskiego), liczona raz:
## dwa przebiegi z sumami prefiksowymi, wiersze, a potem kolumny.
func _build_city_near() -> void:
	var r := MINER_CITY_GAP
	var rows := PackedByteArray()
	rows.resize(TOTAL)
	var pre := PackedInt32Array()
	pre.resize(maxi(N, H) + 1)
	for y in H:
		var o := y * N
		pre[0] = 0
		for x in N:
			pre[x + 1] = pre[x] + (1 if surface[o + x] >= CITY else 0)
		if pre[N] == 0:
			continue
		for x in N:
			if pre[mini(x + r + 1, N)] - pre[maxi(x - r, 0)] > 0:
				rows[o + x] = 1
	city_near.resize(TOTAL)
	city_near.fill(0)
	for x in N:
		pre[0] = 0
		for y in H:
			pre[y + 1] = pre[y] + rows[y * N + x]
		if pre[H] == 0:
			continue
		for y in H:
			if pre[mini(y + r + 1, H)] - pre[maxi(y - r, 0)] > 0:
				city_near[y * N + x] = 1


## Czy w promieniu r kafelków stoi (albo stało) miasto.
func _near_city(x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and ny >= 0 and nx < N and ny < H and surface[ny * N + nx] >= CITY:
				return true
	return false


## Obrażenia od statku wydobywczego; zwraca łup, gdy kafelek pękł.
func miner_hit(i: int, amount: float) -> Dictionary:
	if not is_minable(i):
		return {}
	if layer[i] == L_DEPOSIT:
		amount *= GameState.stat("deposit_damage_mult")
	hp[i] -= amount
	var acc: Array = dmg_acc.get(i, [0.0, 0.0, "miner"])
	acc[0] += amount
	acc[2] = "miner"
	dmg_acc[i] = acc
	if hp[i] <= 0.0:
		_flush_damage(i, true)
		return _destroy(i, true)
	return {}


func landmark_destroyed_fraction(k: int) -> float:
	return 1.0 - float(landmark_left[k]) / maxf(1.0, float(landmark_total[k]))


## Który obiekt specjalny (indeks w Sectors.LANDMARKS) jest najbliżej kafelka.
func _landmark_of(i: int) -> int:
	var p := Vector2(i % N, i / N)
	var best := 0
	for k in landmark_cells.size():
		if p.distance_to(Vector2(landmark_cells[k])) < p.distance_to(Vector2(landmark_cells[best])):
			best = k
	return best


func landmark_pos(k: int) -> Vector2:
	var c: Vector2i = landmark_cells[k]
	return Vector2(c.x * T + T * 0.5, c.y * T + T * 0.5)


func landmarks_in_sector(s: int) -> Array:
	var out: Array = []
	for k in landmark_cells.size():
		var c: Vector2i = landmark_cells[k]
		if Sectors.sector_at(c.x, c.y) == s:
			out.append(k)
	return out


## 1 tuż przy obiekcie specjalnym, 0 poza jego pasem obrony.
func _landmark_guard(x: int, y: int) -> float:
	var g := 0.0
	for k in landmark_cells.size():
		var r: float = Sectors.LANDMARKS[k]["r"]
		var d := Vector2(x, y).distance_to(Vector2(landmark_cells[k]))
		g = maxf(g, 1.0 - clampf((d - r) / Sectors.LANDMARK_GUARD, 0.0, 1.0) if d <= r + Sectors.LANDMARK_GUARD else 0.0)
	return g


func _landmark_tile_gone(i: int) -> void:
	var k := _landmark_of(i)
	landmark_left[k] -= 1
	landmark_tile_destroyed.emit(k)


func metro_destroyed_fraction(s: int) -> float:
	return 1.0 - float(metro_left[s]) / maxf(1.0, float(metro_total[s]))


func _metro_tile_gone(i: int) -> void:
	var s := Sectors.sector_at(i % N, i / N)
	metro_left[s] -= 1
	_refresh_metro_last(s)
	metro_tile_destroyed.emit(s)


## Sektor, którego punkt bossa jest przy pozycji (lub -1).
func boss_portal_at(p: Vector2) -> int:
	for s in Sectors.LIST.size():
		if GameState.boss_state(s) != "" and p.distance_to(city_pos(s)) < BOSS_PORTAL_RADIUS:
			return s
	return -1


## Metropolie: nieregularna plama wokół środka miasta, tylko na lądzie.
func _stamp_metros() -> void:
	var edge := FastNoiseLite.new()
	edge.seed = 91
	edge.frequency = 0.2
	for s in Sectors.LIST.size():
		if not Sectors.has_city(s):
			continue
		var c: Vector2i = city_cells[s]
		var r: float = float(Sectors.LIST[s]["city_r"]) * Sectors.SCALE
		var ri := int(ceil(r)) + 2
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var x := c.x + dx
				var y := c.y + dy
				if x < 0 or y < 0 or x >= N or y >= H or surface[y * N + x] <= RIVER:
					continue
				if Vector2(dx, dy).length() <= r + edge.get_noise_2d(x, y) * 2.5 * Sectors.SCALE:
					surface[y * N + x] = METRO


## Obiekty specjalne: Kapitol to plama wokół środka, Pentagon to pięciokąt z dziedzińcem.
func _stamp_landmarks() -> void:
	var edge := FastNoiseLite.new()
	edge.seed = 57
	edge.frequency = 0.3
	for k in Sectors.LANDMARKS.size():
		var lm: Dictionary = Sectors.LANDMARKS[k]
		var c: Vector2i = landmark_cells[k]
		var r: float = lm["r"]
		var ri := int(ceil(r)) + 1
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		for v in 5:
			var a := -PI * 0.5 + v / 5.0 * TAU
			outer.append(Vector2.from_angle(a) * (r + 0.5))
			inner.append(Vector2.from_angle(a) * r * 0.42)
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var x := c.x + dx
				var y := c.y + dy
				if x < 0 or y < 0 or x >= N or y >= H:
					continue
				var p := Vector2(dx, dy)
				if lm["shape"] == "pentagon":
					if Geometry2D.is_point_in_polygon(p, outer) and not Geometry2D.is_point_in_polygon(p, inner):
						surface[y * N + x] = PENTAGON
				elif p.length() <= r + edge.get_noise_2d(x, y) * 0.8 and surface[y * N + x] > RIVER:
					surface[y * N + x] = CAPITOL


func _bucket_key(x: int, y: int) -> int:
	return (y / TURRET_BUCKET) * 1000 + x / TURRET_BUCKET


func _dock_distance(x: int, y: int) -> float:
	return Vector2(x, y).distance_to(Vector2(dock_cells[Sectors.sector_at(x, y)]))


## Poziom zagrożenia kafelka: odległość od postoju Matki w sektorze (w kafelkach sprzed powiększenia mapy)
## + 40 za każdy sektor od startu + premia sektora (Dystrykt Federalny) + do 90 przy obiektach specjalnych.
func danger(x: int, y: int) -> float:
	var g := _landmark_guard(x, y) if not landmark_cells.is_empty() else 0.0
	var s := Sectors.sector_at(x, y)
	return _dock_distance(x, y) / Sectors.SCALE + 40.0 * Sectors.steps(s, Sectors.START) + float(Sectors.LIST[s].get("danger", 0.0)) + 90.0 * g


func danger_at(p: Vector2) -> float:
	return danger(clampi(int(p.x / T), 0, N - 1), clampi(int(p.y / T), 0, H - 1))


func sector_at_pos(p: Vector2) -> int:
	return Sectors.sector_at(clampi(int(p.x / T), 0, N - 1), clampi(int(p.y / T), 0, H - 1))


## Pozycja postoju Statku Matki w sektorze.
func dock_pos(s: int) -> Vector2:
	var c: Vector2i = dock_cells[s]
	return Vector2(c.x * T + T * 0.5, c.y * T + T * 0.5)


func city_pos(s: int) -> Vector2:
	var c: Vector2i = city_cells[s]
	return Vector2(c.x * T + T * 0.5, c.y * T + T * 0.5)


## Wieżyczki w prostokącie (w pikselach świata) - bez przeglądania całej mapy.
func turrets_in_rect(r: Rect2) -> Array:
	var out: Array = []
	var bs := float(TURRET_BUCKET * T)
	for by in range(maxi(0, int(floor(r.position.y / bs))), mini(H / TURRET_BUCKET, int(floor(r.end.y / bs)) + 1)):
		for bx in range(maxi(0, int(floor(r.position.x / bs))), mini(N / TURRET_BUCKET, int(floor(r.end.x / bs)) + 1)):
			for i in turret_buckets.get(by * 1000 + bx, []):
				if turrets.has(i):
					out.append(i)
	return out


func _roll_deposit(rng: RandomNumberGenerator, d: float) -> int:
	var far := clampf((d - 15.0) / 50.0, 0.0, 1.0)
	var w := [0.0, 40.0, 35.0, 2.0 + 14.0 * far, 8.0 * far, 5.0 * far * far]
	var sum := 0.0
	for v in w:
		sum += v
	var roll := rng.randf() * sum
	for k in range(1, w.size()):
		roll -= w[k]
		if roll <= 0.0:
			return k
	return 1


# =====================================================================
# ZAPIS / ODCZYT
# =====================================================================

func _pack(raw: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))


func _unpack(data: Dictionary, key: String, size: int) -> PackedByteArray:
	return Marshalls.base64_to_raw(String(data.get(key, ""))).decompress(size, FileAccess.COMPRESSION_DEFLATE)


func export_save() -> Dictionary:
	return {
		"format": 3, "w": N, "h": H, "geo": 3,
		"layer": _pack(layer),
		"hp": _pack(hp.to_byte_array()),
		"abducted": _pack(abducted),
		"allies": ally_turrets.keys(),
	}


func apply_save(data: Dictionary) -> void:
	# zapisy sprzed mapy USA nie pasują do nowego świata
	var fmt := int(data.get("format", 1))
	if fmt != 2 and fmt != 3:
		return
	# format 2 to mapa 384x256 sprzed powiększenia sektorów
	var ow := int(data.get("w", 384))
	var oh := int(data.get("h", 256))
	var l := _unpack(data, "layer", ow * oh)
	var h := _unpack(data, "hp", ow * oh * 4).to_float32_array()
	if l.size() != ow * oh or h.size() != ow * oh:
		return
	var a := _unpack(data, "abducted", ow * oh)
	if int(data.get("geo", 1)) >= 3 and ow == N and oh == H:
		layer = l
		hp = h
		if a.size() == TOTAL:
			abducted = a
		for k in data.get("allies", []):
			var ai := int(k)
			if ai >= 0 and ai < TOTAL and layer[ai] == L_IMPERIAL:
				ally_turrets[ai] = {"cd": randf(), "angle": randf() * TAU}
	else:
		_geo_resample(l, h, a, ow, oh, data.get("allies", []))
	_count_metros()
	imperial_count = 0
	devastated_count = 0
	imperial_list.clear()
	for i in TOTAL:
		if layer[i] == L_IMPERIAL:
			imperial_count += 1
			imperial_list.append(i)
		elif layer[i] != L_SURFACE:
			devastated_count += 1
		if layer[i] == L_DEPOSIT:
			max_hp[i] = DEP_DEFS[deposit[i]]["hp"] * (1.0 + danger(i % N, i / N) / 90.0)
		if layer[i] != L_SURFACE:
			turrets.erase(i)
	_build_minimap()
	_redraw_all()

## Zapis sprzed mapy 3x3 (siatka 3x2: 24,5°-49,5° N, w formacie 2 mniejsza): każdy kafelek nowej mapy
## bierze stan z tego samego punktu na Ziemi. Złoża są losowane od nowa, więc odkryte złoże bez złoża
## w nowym miejscu staje się kraterem. Południe poza starą mapą (Meksyk, Kuba) jest nietknięte.
func _geo_resample(l: PackedByteArray, h: PackedFloat32Array, a: PackedByteArray, ow: int, oh: int, allies: Array) -> void:
	var geo_h := mini(oh, ow * 2 / 3)    # stara mapa 3x2 (wiersze dopisane w wersji z wyspą pomijamy)
	var old_allies := {}
	for k in allies:
		old_allies[int(k)] = true
	for y in H:
		for x in N:
			var ll := Sectors.lonlat_of(x + 0.5, y + 0.5)
			var oy := int((Sectors.OLD_LAT_MAX - ll.y) / (Sectors.OLD_LAT_MAX - Sectors.OLD_LAT_MIN) * geo_h)
			if oy < 0 or oy >= geo_h:
				continue
			var ox := mini(int((ll.x - Sectors.LON_MIN) / (Sectors.LON_MAX - Sectors.LON_MIN) * ow), ow - 1)
			var o := oy * ow + ox
			var i := y * N + x
			var st := l[o]
			if st == L_DEPOSIT and deposit[i] == 0:
				st = L_CRATER
			layer[i] = st
			match st:
				L_SURFACE:
					hp[i] = minf(h[o], max_hp[i]) if h[o] > 0.0 else max_hp[i]
				L_DEPOSIT:
					max_hp[i] = DEP_DEFS[deposit[i]]["hp"] * (1.0 + danger(x, y) / 90.0)
					hp[i] = max_hp[i]
				_:
					hp[i] = 0.0
			if a.size() == ow * oh:
				abducted[i] = a[o]
			if st == L_IMPERIAL and old_allies.has(o):
				ally_turrets[i] = {"cd": randf(), "angle": randf() * TAU}
	# metropolie zrównane z ziemią na starej mapie zostają zrównane, mimo innego obrysu
	for i in TOTAL:
		if surface[i] == METRO and layer[i] == L_SURFACE and GameState.metros_done.has(str(Sectors.sector_at(i % N, i / N))):
			layer[i] = L_CRATER
			hp[i] = 0.0

# =====================================================================
# POMOCNICZE
# =====================================================================


func pos_to_idx(p: Vector2) -> int:
	var x := int(floor(p.x / T))
	var y := int(floor(p.y / T))
	if x < 0 or y < 0 or x >= N or y >= H:
		return -1
	return y * N + x


func idx_center(i: int) -> Vector2:
	return Vector2((i % N) * T + T * 0.5, (i / N) * T + T * 0.5)


func tile_name(i: int) -> String:
	match layer[i]:
		L_SURFACE: return TILE_DEFS[surface[i]]["name"]
		L_DEPOSIT: return DEP_DEFS[deposit[i]]["name"]
		L_IMPERIAL: return String(TILE_DEFS[surface[i]]["name"]) + " Imperium"
	return "Krater"


## Co może wypaść z kafelka (z obecnymi mnożnikami wydobycia): [[surowiec, tekst ilości], ...].
## Ułamkowe łupy pokazane jako szansa, wieżyczka dorzuca resztki broni.
func tile_drops_preview(i: int) -> Array:
	var out: Array = []
	var src: Dictionary
	var mult := GameState.stat("yield_mult")
	if layer[i] == L_SURFACE:
		src = TILE_DEFS[surface[i]]["drops"]
	elif layer[i] == L_DEPOSIT:
		src = DEP_DEFS[deposit[i]]["drops"]
		mult *= GameState.stat("deposit_yield_mult")
	else:
		return out
	for k in src:
		var v: float = float(src[k]) * mult
		var lo := int(floor(v))
		var txt: String
		if v < 1.0:
			txt = "%d%%" % maxi(1, int(round(v * 100.0)))
		elif v - lo > 0.04:
			txt = "%d-%d" % [lo, lo + 1]
		else:
			txt = str(lo)
		out.append([k, txt])
	if turrets.has(i):
		out.append(["weapon_scrap", "3-5"])
	return out


## Złoże pod kafelkiem powierzchni, jeśli gracz o nim wie (skaner): nazwa albo "".
func hidden_deposit_name(i: int) -> String:
	if layer[i] != L_SURFACE or deposit[i] == 0 or not scan_tiles.has(i):
		return ""
	return DEP_DEFS[deposit[i]]["name"]


## Czy kafelek można niszczyć (powierzchnia albo odsłonięte złoże). Kafelki Imperium są niezniszczalne.
func is_minable(i: int) -> bool:
	return i >= 0 and i < TOTAL and (layer[i] == L_SURFACE or layer[i] == L_DEPOSIT)


## Odbudowa: zniszczony kafelek staje się kafelkiem Imperium tego samego typu terenu.
func can_rebuild(i: int) -> bool:
	return i >= 0 and i < TOTAL and layer[i] == L_CRATER and _is_city(i)


func _is_city(i: int) -> bool:
	return surface[i] == CITY or surface[i] == METRO


## W odbudowanym mieście może stanąć wieżyczka Imperium.
func _maybe_ally(i: int, chance_mult := 1.0) -> void:
	if randf() < GameState.stat("ally_turret_chance") * chance_mult:
		ally_turrets[i] = {"cd": randf_range(0.2, 1.0), "angle": randf() * TAU}


## Koszt odbudowy: tyle, ile kafelek daje bazowo (bez mnożników). Ułamkowe drobne łupy się nie liczą.
func rebuild_cost(i: int) -> Dictionary:
	var out := {}
	var src: Dictionary = TILE_DEFS[surface[i]]["drops"]
	for k in src:
		var n := int(src[k])
		if n > 0:
			out[k] = n
	return out


## Odbudowuje kafelek za surowce z magazynu. Zwraca false, gdy nie stać.
func rebuild(i: int) -> bool:
	if not can_rebuild(i) or not GameState.pay(rebuild_cost(i)):
		return false
	layer[i] = L_IMPERIAL
	imperial_count += 1
	devastated_count -= 1
	imperial_list.append(i)
	_maybe_ally(i)
	_update_minimap_pixel(i)
	_mark_dirty(i)
	tile_rebuilt.emit(i)
	return true


## Rozrost Imperium (badanie w laboratorium): kafelek Imperium przejmuje sąsiada.
## Najpierw zabudowuje sąsiednie kratery, a gdy ich brak - nienaruszone kafelki powierzchni.
func _imperial_spread_once() -> bool:
	if imperial_list.is_empty():
		return false
	var dirs := [1, -1, N, -N]
	for pass_ in 2:
		for attempt in 24:
			var base: int = imperial_list[randi() % imperial_list.size()]
			var j: int = base + dirs[randi() % 4]
			if j < 0 or j >= TOTAL or absi((j % N) - (base % N)) > 1:
				continue
			var ok := false
			if pass_ == 0:
				ok = layer[j] == L_CRATER and _is_city(j)
			else:
				ok = layer[j] == L_SURFACE and not turrets.has(j) and _is_city(j)
			if not ok:
				continue
			if layer[j] == L_CRATER:
				devastated_count -= 1
			var metro_gone: bool = layer[j] == L_SURFACE and surface[j] == METRO
			var lm_gone: bool = layer[j] == L_SURFACE and (surface[j] == CAPITOL or surface[j] == PENTAGON)
			layer[j] = L_IMPERIAL
			if metro_gone:
				_metro_tile_gone(j)
			if lm_gone:
				_landmark_tile_gone(j)
			imperial_count += 1
			imperial_list.append(j)
			_maybe_ally(j, 0.5)
			recent_hits.erase(j)
			_update_minimap_pixel(j)
			_mark_dirty(j)
			tile_imperial_spread.emit(j)
			return true
	return false


func _hash(x: int, y: int) -> int:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h


# =====================================================================
# LASER / NISZCZENIE
# =====================================================================

## Uderzenie wiązki w punkt. Zwraca indeks trafionego kafelka (lub -1).
func laser_hit(p: Vector2, amount: float, splash_out: Array = []) -> int:
	var i := pos_to_idx(p)
	if not is_minable(i):
		return -1
	target_idx = i
	target_timer = 0.15
	hit_glow = 1.0
	_damage(i, amount, "laser")
	# rozprysk: okrąg wokół punktu trafienia (promień w kafelkach, liczony do środków kafelków)
	var splash := GameState.stat("laser_splash")
	if splash > 0.0:
		var r_px: float = splash * T
		var ri := int(ceil(splash))
		var x := i % N
		var y := i / N
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				if dx == 0 and dy == 0:
					continue
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= N or ny >= H:
					continue
				var j := ny * N + nx
				if is_minable(j) and idx_center(j).distance_to(p) <= r_px:
					splash_out.append(idx_center(j))
					_damage(j, amount * 0.5, "splash")
	return i


## Publiczne obrażenia kafelka (rakiety, drony, karabiny).
func damage_tile(i: int, amount: float, src := "rocket") -> void:
	if not is_minable(i):
		return
	_damage(i, amount, src)


func _damage(i: int, amount: float, src := "laser") -> void:
	if layer[i] == L_DEPOSIT:
		amount *= GameState.stat("deposit_damage_mult")
	amount = minf(amount, maxf(hp[i], 0.0))
	hp[i] -= amount
	# zbieranie obrażeń w czytelne liczby (zamiast liczby co klatkę)
	var acc: Array = dmg_acc.get(i, [0.0, 0.0, src])
	acc[0] += amount
	acc[2] = src
	dmg_acc[i] = acc
	recent_hits[i] = 1.6
	if not tile_flash.has(i) or tile_flash[i] <= 0.0:
		tile_flash[i] = 0.07
	if hp[i] <= 0.0:
		_flush_damage(i, true)
		_destroy(i)
		tile_broken.emit(i, src)


func _flush_damage(i: int, big := false) -> void:
	if not dmg_acc.has(i):
		return
	var acc: Array = dmg_acc[i]
	dmg_acc.erase(i)
	if fx and acc[0] >= 0.5:
		fx.damage_number(idx_center(i) + Vector2(0, -10), acc[0], DMG_COLORS.get(acc[2], Color(1, 1, 1)), big)


func _destroy(i: int, quiet := false) -> Dictionary:
	var drops := {}
	var info := ""
	var src: Dictionary
	var mult := GameState.stat("yield_mult")
	if layer[i] == L_SURFACE:
		src = TILE_DEFS[surface[i]]["drops"]
	else:
		src = DEP_DEFS[deposit[i]]["drops"]
		mult *= GameState.stat("deposit_yield_mult")
	for k in src:
		var v: float = float(src[k]) * mult
		var n := int(floor(v))
		if randf() < v - n:
			n += 1
		if n > 0:
			drops[k] = n

	var d := danger(i % N, i / N)
	var was_city := layer[i] == L_SURFACE and surface[i] >= CITY
	var metro_gone: bool = layer[i] == L_SURFACE and surface[i] == METRO
	var lm_gone: bool = layer[i] == L_SURFACE and (surface[i] == CAPITOL or surface[i] == PENTAGON)
	if layer[i] == L_SURFACE:
		devastated_count += 1
	if layer[i] == L_SURFACE and deposit[i] != 0:
		layer[i] = L_DEPOSIT
		max_hp[i] = DEP_DEFS[deposit[i]]["hp"] * (1.0 + d / 90.0)
		hp[i] = max_hp[i]
		info = "Odkryto: " + String(DEP_DEFS[deposit[i]]["name"]) + "!"
	else:
		layer[i] = L_CRATER
		hp[i] = 0.0
	if turrets.has(i):
		turrets.erase(i)
		drops["weapon_scrap"] = randi_range(3, 5)
		info = "Wieżyczka obronna zniszczona!"
	GameState.tiles_destroyed += 1
	_update_minimap_pixel(i)
	_mark_dirty(i)
	# statek wydobywczy sam zabiera łup, więc gracz go nie dostaje
	if not quiet:
		tile_destroyed.emit(i, idx_center(i), drops, info)
	elif fx:
		fx.explosion(idx_center(i), Color(1.0, 0.75, 0.3))
	if metro_gone:
		_metro_tile_gone(i)
	if lm_gone:
		_landmark_tile_gone(i)
	# kopanie miast przez statki wydobywcze nie ściąga myśliwców
	if was_city and not quiet:
		# metropolia i obiekty specjalne drażnią Ziemian bardziej niż zwykłe miasto
		GameState.cities_destroyed += 1 if surface[i] == CITY else (3 if surface[i] == METRO else 5)
		city_destroyed.emit(idx_center(i))
	return drops


func _mark_dirty(i: int) -> void:
	var k := ((i / N) / CHUNK) * CHUNK_COLS + (i % N) / CHUNK
	if chunk_ready[k] == 1:
		dirty_chunks[k] = true
		# unieważnij tylko ten kafelek; sąsiednie zostają w pamięci i nie są liczone od nowa
		if tile_meshes.has(k):
			tile_meshes[k][((i / N) % CHUNK) * CHUNK + (i % N) % CHUNK] = null


func _redraw_all() -> void:
	tile_meshes.clear()
	for k in built_chunks:
		dirty_chunks[k] = true


## Buduje siatki fragmentów wokół kamery (najbliższe najpierw) i zwalnia te daleko za nią.
func _update_chunks(delta: float) -> void:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var tl: Vector2 = inv * Vector2.ZERO
	var view := Rect2(tl, (inv * get_viewport_rect().size) - tl)
	var size := float(CHUNK * T)
	var near := view.grow(size * 1.5)
	var center := view.get_center()
	var missing: Array = []
	for cy in range(maxi(0, int(near.position.y / size)), mini(CHUNK_ROWS, int(near.end.y / size) + 1)):
		for cx in range(maxi(0, int(near.position.x / size)), mini(CHUNK_COLS, int(near.end.x / size) + 1)):
			if chunk_ready[cy * CHUNK_COLS + cx] == 0:
				missing.append(cy * CHUNK_COLS + cx)
	if missing.size() > CHUNKS_PER_FRAME:
		missing.sort_custom(func(a, b): return _chunk_center(a).distance_squared_to(center) < _chunk_center(b).distance_squared_to(center))
		missing.resize(CHUNKS_PER_FRAME)
	for k in missing:
		chunk_ready[k] = 1
		built_chunks[k] = true
		chunks[k].queue_redraw()
	chunk_free_timer -= delta
	if chunk_free_timer > 0.0:
		return
	chunk_free_timer = 1.0
	var keep := view.grow(size * 6.0)
	for k in built_chunks.keys():
		if not keep.has_point(_chunk_center(k)):
			chunk_ready[k] = 0
			built_chunks.erase(k)
			dirty_chunks.erase(k)
			tile_meshes.erase(k)
			RenderingServer.canvas_item_clear(chunks[k].get_canvas_item())
			chunks[k].remove_meta("mesh")


func _chunk_center(k: int) -> Vector2:
	return (Vector2(k % CHUNK_COLS, k / CHUNK_COLS) + Vector2(0.5, 0.5)) * float(CHUNK * T)


## Przerysowanie zmienionych fragmentów - najwyżej raz na klatkę na fragment.
func _flush_dirty_chunks() -> void:
	if dirty_chunks.is_empty():
		return
	# najwyżej kilka fragmentów na klatkę, żeby nie było szarpnięć
	var done := 0
	for k in dirty_chunks.keys():
		chunks[k].queue_redraw()
		dirty_chunks.erase(k)
		done += 1
		if done >= 6:
			break


# =====================================================================
# WIEŻYCZKI I POCISKI
# =====================================================================

# =====================================================================
# PORYWANIE
# =====================================================================

## Jaki rodzaj istot można porwać z kafelka ("" = nic).
func abduct_source(i: int) -> String:
	if i < 0 or layer[i] != L_SURFACE or abducted[i] == 1:
		return ""
	return String(CREATURE_OF.get(surface[i], ""))


func mark_abducted(i: int) -> void:
	abducted[i] = 1
	_mark_dirty(i)


## Procent całego świata (wszystkie sektory): zniszczone teraz i zabudowane przez Imperium.
func devastated_percent() -> float:
	return devastated_count * 100.0 / playable


func imperial_percent() -> float:
	return imperial_count * 100.0 / playable


## Przyrost Potęgi Imperium na sekundę.
func power_rate() -> float:
	return imperial_count * GameState.stat("power_mult") / POWER_SECONDS_PER_TILE


func _bio_process(delta: float) -> void:
	# Potęga Imperium: każdy odbudowany kafelek generuje walutę w czasie rzeczywistym
	if imperial_count > 0:
		power_acc += power_rate() * delta
		if power_acc >= 0.9999:
			var n := int(floor(power_acc + 0.0001))
			power_acc -= n
			GameState.bank["power"] = int(GameState.bank.get("power", 0)) + n
			GameState.bank_changed.emit()
	# rozrost kafelków Imperium (co 10 s, ulepszenia skracają do 5 s)
	if GameState.stat("imp_spread") > 0.0 and imperial_count > 0:
		imp_spread_timer += delta
		var cd := maxf(5.0, GameState.stat("imp_spread_cd"))
		if imp_spread_timer >= cd:
			imp_spread_timer -= cd
			_imperial_spread_once()


func _process(delta: float) -> void:
	time += delta
	_bio_process(delta)
	_update_chunks(delta)
	_flush_dirty_chunks()
	for i in dmg_acc.keys():
		dmg_acc[i][1] += delta
		if dmg_acc[i][1] >= 0.14:
			_flush_damage(i)
	for i in recent_hits.keys():
		recent_hits[i] -= delta
		if recent_hits[i] <= 0.0 or not is_minable(i):
			recent_hits.erase(i)
	for i in tile_flash.keys():
		tile_flash[i] -= delta
		if tile_flash[i] <= -0.05:
			tile_flash.erase(i)
	target_timer -= delta
	if target_timer <= 0.0:
		target_idx = -1
	var active: bool = ship != null and not ship.docked and not ship.dead
	# w czasie walki mapa lekko gaśnie, a wrogowie i pociski wybijają się na pierwszy plan
	var hot: bool = active and (not missiles.is_empty() or (enemies != null and enemies.hostile_count() > 0))
	combat_k = move_toward(combat_k, 1.0 if hot else 0.0, delta * (2.0 if hot else 0.8))
	# szybki lot: od ok. połowy prędkości maksymalnej mapa zaczyna przygasać
	var sf: float = ship.vel.length() / maxf(1.0, GameState.stat("max_speed")) if active else 0.0
	speed_k = move_toward(speed_k, clampf((sf - 0.5) / 0.5, 0.0, 1.0), delta * 1.5)
	if ship != null:
		var sp: Vector2 = ship.global_position
		var friends := _friendlies() if active else []
		for i in turrets_in_rect(Rect2(sp, Vector2.ZERO).grow(MISSILE_RANGE + T)):
			var t: Dictionary = turrets[i]
			var tp := idx_center(i)
			var to := sp - tp
			if t.get("kind", "") == "missile":
				_process_missile_turret(i, t, tp, to, active, delta)
				continue
			# cel: gracz, a gdy jest poza zasięgiem - najbliższy sojusznik
			var aim := Vector2.INF
			var aim_vel := Vector2.ZERO
			if active and to.length() < TURRET_RANGE:
				aim = sp
				aim_vel = ship.vel
			elif active:
				var bd := TURRET_RANGE
				for fr in friends:
					var dd: float = fr[2]["pos"].distance_to(tp)
					if dd < bd:
						bd = dd
						aim = fr[2]["pos"]
						aim_vel = fr[2].get("vel", Vector2.ZERO)
			if aim != Vector2.INF:
				var ta := aim - tp
				t["angle"] = lerp_angle(t["angle"], ta.angle(), 5.0 * delta)
				t["cd"] -= delta
				if t["cd"] <= 0.0:
					var d := danger(i % N, i / N)
					t["cd"] = 1.7
					# lekkie wyprzedzanie celu
					var lead: Vector2 = aim + aim_vel * (ta.length() / BULLET_SPEED) * 0.5
					var dir := (lead - tp).normalized()
					bullets.append({"pos": tp + dir * 18.0, "vel": dir * BULLET_SPEED, "life": 3.0,
						"dmg": 8.0 * (1.0 + d / 70.0)})
			else:
				t["angle"] += delta * 0.4
		for b in bullets:
			b["pos"] += b["vel"] * delta
			b["life"] -= delta
			if not active:
				continue
			if b["pos"].distance_to(sp) < 16.0:
				ship.take_damage(b["dmg"])
				b["life"] = 0.0
				continue
			for fr in friends:
				if b["pos"].distance_to(fr[2]["pos"]) < fr[0]:
					fr[1].hurt(fr[2], b["dmg"])
					b["life"] = 0.0
					break
		bullets = bullets.filter(func(b): return b["life"] > 0.0)
	if not active and bullets.size() > 0 and ship != null and ship.docked:
		bullets.clear()
	_process_missiles(delta, active)
	_process_allies(delta, active)

	# wysyłanie całego obrazu do karty graficznej 5 razy na sekundę w zupełności wystarcza
	minimap_cd -= delta
	if _minimap_dirty and minimap_cd <= 0.0:
		minimap_cd = 0.2
		minimap_tex.update(minimap_img)
		_minimap_dirty = false
	# w doku mapa jest schowana pod ekranem ulepszeń
	if overlay.visible:
		overlay.queue_redraw()
		scan_layer.queue_redraw()


# =====================================================================
# RAKIETY SAMONAPROWADZAJĄCE
# =====================================================================

## Sojusznicy, w których mogą trafić pociski Ziemian: [promień trafienia, właściciel z hurt(), stan].
func _friendlies() -> Array:
	var out: Array = []
	if escorts:
		for e in escorts.alive():
			out.append([escorts.HIT_RADIUS, escorts, e])
	if wingmen and wingmen.called:
		for w in wingmen.wings:
			out.append([wingmen.HIT_RADIUS, wingmen, w])
	if miners:
		for m in miners.alive():
			out.append([miners.HIT_RADIUS, miners, m])
	if transit:
		for t in transit.alive():
			out.append([transit.HIT_RADIUS, transit, t])
	if mothership_ref and mothership_ref.siege and not mothership_ref.wrecked:
		out.append([mothership_ref.HIT_RADIUS, mothership_ref, mothership_ref.body])
	return out


## Wieżyczki Imperium strzelają w najbliższą rakietę albo myśliwiec w zasięgu.
func _process_allies(delta: float, active: bool) -> void:
	for sh in ally_shots:
		sh["life"] -= delta
	if not ally_shots.is_empty():
		ally_shots = ally_shots.filter(func(sh): return sh["life"] > 0.0)
	if not active or ally_turrets.is_empty() or enemies == null:
		return
	var rng := GameState.stat("ally_range")
	var sp: Vector2 = ship.global_position
	for i in ally_turrets:
		var p := idx_center(i)
		# wieżyczki daleko od akcji nie mają do kogo strzelać
		if p.distance_squared_to(sp) > 9000000.0:
			continue
		var at: Dictionary = ally_turrets[i]
		at["cd"] -= delta
		if at["cd"] > 0.0:
			continue
		var target := Vector2.INF
		var ms: Dictionary = nearest_missile(p, rng)
		var f: Dictionary = {} if not ms.is_empty() else enemies.nearest(p, rng)
		if not ms.is_empty():
			target = ms["pos"]
			damage_missile(ms, GameState.stat("ally_damage"))
		elif not f.is_empty():
			target = f["pos"]
			enemies.damage_fighter(f, GameState.stat("ally_damage"))
		if target == Vector2.INF:
			at["cd"] = 0.4
			continue
		at["cd"] = 0.9
		at["angle"] = (target - p).angle()
		ally_shots.append({"a": p, "b": target, "life": 0.14})
		Audio.play("gun_shot", 0.15, -8.0)


func _process_missile_turret(i: int, t: Dictionary, tp: Vector2, to: Vector2, active: bool, delta: float) -> void:
	if not active or to.length() > MISSILE_RANGE:
		return
	t["angle"] = lerp_angle(t["angle"], to.angle(), 4.0 * delta)
	t["cd"] -= delta
	if t["cd"] > 0.0 or missiles.size() >= MISSILE_MAX:
		return
	t["cd"] = randf_range(7.0, 10.0)
	missiles.append({"pos": tp, "rot": to.angle(), "speed": 140.0, "life": MISSILE_LIFE, "hp": MISSILE_HP,
		"dmg": 28.0 * (1.0 + danger(i % N, i / N) / 70.0)})
	Audio.play("rocket_launch", 0.05, 2.0)
	missile_launched.emit()


func _process_missiles(delta: float, active: bool) -> void:
	if missiles.is_empty():
		missile_beep = 0.0
		return
	if not active:
		for m in missiles:
			_explode_missile(m)
		missiles.clear()
		return
	var sp: Vector2 = ship.global_position
	var closest := INF
	for m in missiles:
		m["rot"] = rotate_toward(m["rot"], (sp - m["pos"]).angle(), MISSILE_TURN * delta)
		# rakieta nadąża też za ulepszonym statkiem: ucieczka udaje się tylko przy pełnej prędkości po prostej
		m["speed"] = minf(m["speed"] + MISSILE_ACCEL * delta, maxf(MISSILE_SPEED_MIN, GameState.stat("max_speed") * 0.97))
		m["pos"] += Vector2.from_angle(m["rot"]) * m["speed"] * delta
		m["life"] -= delta
		if fx and randf() < 0.5:
			fx.sparks(m["pos"] - Vector2.from_angle(m["rot"]) * 12.0, Color(1.0, 0.5, 0.2), 1, 40.0)
		var d: float = m["pos"].distance_to(sp)
		closest = minf(closest, d)
		if d < MISSILE_HIT:
			ship.take_damage(m["dmg"])
			if fx:
				fx.explosion(m["pos"], Color(1.2, 0.3, 0.15), true)
			Audio.play("explosion_big", 0.1)
			m["life"] = 0.0
		elif m["life"] <= 0.0:
			_explode_missile(m)
	missiles = missiles.filter(func(m): return m["life"] > 0.0)
	# sygnał: im bliżej rakieta, tym szybciej pika
	missile_beep -= delta
	if missile_beep <= 0.0 and not missiles.is_empty():
		missile_beep = lerpf(0.13, 0.6, clampf(closest / 900.0, 0.0, 1.0))
		Audio.play("missile_warning", 0.0)


func _explode_missile(m: Dictionary) -> void:
	m["life"] = 0.0
	if fx:
		fx.explosion(m["pos"], Color(1.0, 0.45, 0.2))
	Audio.play("explosion", 0.12)


## Zestrzelić rakietę mogą tylko laser i drony.
func damage_missile(m: Dictionary, amount: float) -> void:
	if m["life"] <= 0.0:
		return
	m["hp"] -= amount
	if m["hp"] <= 0.0:
		_explode_missile(m)


## Wiązka od a do b: trafia pierwszą rakietę na swojej drodze. Zwraca punkt trafienia lub Vector2.INF.
func missile_laser_hit(a: Vector2, b: Vector2, amount: float) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	var hit: Dictionary = {}
	for m in missiles:
		if m["life"] <= 0.0:
			continue
		var cp := Geometry2D.get_closest_point_to_segment(m["pos"], a, b)
		if cp.distance_to(m["pos"]) < MISSILE_LASER_RADIUS and a.distance_to(cp) < bd:
			bd = a.distance_to(cp)
			best = cp
			hit = m
	if not hit.is_empty():
		damage_missile(hit, amount)
	return best


func nearest_missile(p: Vector2, max_d: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_d
	for m in missiles:
		var d: float = m["pos"].distance_to(p)
		if m["life"] > 0.0 and d < bd:
			bd = d
			best = m
	return best


# =====================================================================
# MINIMAPA
# =====================================================================

## Minimapa w kolorach gry: ciemne granaty i fiolety, a miasta świecą różem.
const MINI_COLORS := {
	DEEP: Color(0.02, 0.04, 0.18), OCEAN: Color(0.03, 0.08, 0.28), RIVER: Color(0.12, 0.55, 0.85),
	SAND: Color(0.52, 0.4, 0.5), PLAINS: Color(0.2, 0.2, 0.42), FOREST: Color(0.08, 0.36, 0.44),
	MOUNTAIN: Color(0.4, 0.2, 0.62), SNOW: Color(0.66, 0.58, 0.88), CITY: Color(0.8, 0.16, 0.62), METRO: Color(1.0, 0.32, 0.88),
	CAPITOL: Color(1.0, 0.85, 0.4), PENTAGON: Color(1.0, 0.3, 0.25),
}


func _mini_color(i: int) -> Color:
	if turrets.has(i) and turrets[i].get("kind", "") == "missile":
		return Color(1.0, 0.0, 0.0)
	match layer[i]:
		L_CRATER:
			var base: Color = MINI_COLORS[surface[i]]
			var g := 0.2 + base.get_luminance() * 0.22
			return Color(g, g, g * 1.08)
		L_IMPERIAL:
			return Color(0.95, 0.72, 0.25)
		L_DEPOSIT:
			# złoża przygaszone, żeby nie zamieniały mapy w konfetti
			var c: Color = DEP_DEFS[deposit[i]]["color"]
			return Color(minf(c.r, 1.0) * 0.72, minf(c.g, 1.0) * 0.72, minf(c.b, 1.0) * 0.72)
	return MINI_COLORS[surface[i]]


func _build_minimap() -> void:
	# cały obraz naraz: tysiące set_pixel wyraźnie wydłużały wczytywanie
	var data := PackedByteArray()
	data.resize(TOTAL * 4)
	for i in TOTAL:
		var c := _mini_color(i)
		var o := i * 4
		data[o] = c.r8
		data[o + 1] = c.g8
		data[o + 2] = c.b8
		data[o + 3] = 255
	minimap_img = Image.create_from_data(N, H, false, Image.FORMAT_RGBA8, data)
	if minimap_tex == null:
		minimap_tex = ImageTexture.create_from_image(minimap_img)
	else:
		minimap_tex.set_image(minimap_img)


func _update_minimap_pixel(i: int) -> void:
	minimap_img.set_pixel(i % N, i / N, _mini_color(i))
	_minimap_dirty = true


# =====================================================================
# RYSOWANIE
# =====================================================================

func _draw_chunk(ci: Node2D, cx: int, cy: int) -> void:
	# fragmenty daleko od kamery nie mają siatki (Godot rysuje każdy węzeł raz po wejściu do drzewa)
	if chunk_ready[cy * CHUNK_COLS + cx] == 0:
		return
	# wszystkie kształty fragmentu -> jedna siatka trójkątów -> jedno wywołanie rysowania
	var k := cy * CHUNK_COLS + cx
	if not tile_meshes.has(k):
		var empty: Array = []
		empty.resize(CHUNK * CHUNK)
		tile_meshes[k] = empty
	var cache: Array = tile_meshes[k]
	var mp = MeshPainter.new()
	for ly in CHUNK:
		for lx in CHUNK:
			var entry = cache[ly * CHUNK + lx]
			if entry == null:
				# każdy kafelek pamięta swoje trójkąty, więc po zniszczeniu liczony jest tylko on
				var one = MeshPainter.new()
				_draw_tile(one, cx * CHUNK + lx, cy * CHUNK + ly)
				entry = [one.verts, one.cols]
				cache[ly * CHUNK + lx] = entry
			mp.verts.append_array(entry[0])
			mp.cols.append_array(entry[1])
	var m: ArrayMesh = mp.build_mesh()
	# siatkę trzeba trzymać w pamięci, inaczej zniknie po wyjściu z funkcji
	ci.set_meta("mesh", m)
	if m:
		ci.draw_mesh(m, null)


func _draw_tile(ci, x: int, y: int) -> void:
	var i := y * N + x
	var r := Rect2(x * T, y * T, T, T)
	var h := _hash(x, y)
	var o := r.position
	var l := layer[i]

	if l == L_DEPOSIT:
		var dc: Color = DEP_DEFS[deposit[i]]["color"]
		ci.draw_rect(r, Color(0.06, 0.02, 0.07))
		ci.draw_rect(r, Color(dc.r, dc.g, dc.b, 0.12))
		_draw_crystals(ci, r, dc, h)
		ci.draw_rect(r.grow(-1.5), Color(dc.r * 0.6, dc.g * 0.6, dc.b * 0.6, 0.9), false, 1.5)
		return

	paint_terrain(ci, r, surface[i], h, _hash(x * 31, y * 17), l == L_IMPERIAL, l == L_CRATER)
	if l != L_SURFACE:
		return
	if abducted[i] == 1:
		# pole, z którego już porwano istoty
		ci.draw_arc(o + Vector2(8, 8), 4.0, 0.0, TAU, 10, Color(0.6, 0.9, 0.7, 0.55), 1.2, true)
		ci.draw_line(o + Vector2(5, 11), o + Vector2(11, 5), Color(0.6, 0.9, 0.7, 0.55), 1.2, true)


## Sam wygląd kafelka: tło, źdźbła, ikona i rama. Bez stanu świata, więc korzysta z tego też menu główne.
static func paint_terrain(ci, r: Rect2, t: int, h: int, hh: int, imp: bool, dead: bool) -> void:
	var o := r.position
	var def: Dictionary = TILE_DEFS[t]
	var lc: Color = def["line"]
	lc = Color(lc.r * 0.62, lc.g * 0.62, lc.b * 0.62)
	# zniszczony kafelek to ten sam teren, tylko wyszarzony i nieaktywny
	if dead:
		lc = _greyed(lc, 0.8)
	# ciemne, przygaszone tło terenu - na nim jedna wyraźna, świecąca ikona (styl Agrivore)
	var fl: Color = def["fill"]
	var base_fill := Color(fl.r * 0.38, fl.g * 0.38, fl.b * 0.38)
	if dead:
		var v := 0.095 + fl.get_luminance() * 0.25
		base_fill = Color(v, v, v * 1.05)
	ci.draw_rect(r, IMP_FILL if imp else base_fill)
	# drobne "źdźbła" w tle, żeby teren nie był płaski
	var dc2 := Color(lc.r, lc.g, lc.b, 0.18) if not imp else Color(IMP_PINK.r, IMP_PINK.g, IMP_PINK.b, 0.3)
	for k in 2:
		var dp := o + Vector2(5 + (hh >> (k * 5)) % 38, 6 + (hh >> (k * 5 + 3)) % 36)
		ci.draw_line(dp, dp + Vector2(2, -3), dc2, 1.0)
	var c := r.get_center() + Vector2(((h >> 2) % 5) - 2, ((h >> 5) % 5) - 2)
	_draw_terrain_icon(ci, t, c, h, imp, dead)
	if imp:
		_draw_imperial_frame(ci, r)
		return
	# siatka
	ci.draw_rect(r, Color(lc.r * 0.4, lc.g * 0.4, lc.b * 0.4, 0.3), false, 1.0)


# =====================================================================
# KAFELKI IMPERIUM (odbudowane) - osobny, geometryczny styl: złoto + fiolet + cyjan
# =====================================================================

const IMP_GOLD := Color(1.0, 0.78, 0.3)
const IMP_CYAN := Color(0.4, 0.95, 1.0)
const IMP_FILL := Color(0.11, 0.02, 0.17)
const IMP_PINK := Color(1.15, 0.2, 0.85)


static func _draw_imperial_frame(ci, r: Rect2) -> void:
	# neonowa rama ze ściętymi narożnikami: szeroka poświata i ostra linia
	var rr := r.grow(-2.5)
	var cut := 6.0
	var frame := PackedVector2Array([
		rr.position + Vector2(cut, 0), Vector2(rr.end.x - cut, rr.position.y), Vector2(rr.end.x, rr.position.y + cut),
		Vector2(rr.end.x, rr.end.y - cut), Vector2(rr.end.x - cut, rr.end.y), Vector2(rr.position.x + cut, rr.end.y),
		Vector2(rr.position.x, rr.end.y - cut), rr.position + Vector2(0, cut), rr.position + Vector2(cut, 0)])
	ci.draw_polyline(frame, Color(IMP_PINK.r, IMP_PINK.g, IMP_PINK.b, 0.22), 4.0, true)
	ci.draw_polyline(frame, IMP_PINK, 1.3, true)

# =====================================================================
# IKONY TERENU (styl Agrivore: wypełniony kształt + neonowy obrys + odblask)
# =====================================================================

## Kolory ikon: [wypełnienie, obrys, akcent]
const ICON_COLS := {
	DEEP: [Color(0.08, 0.2, 0.65), Color(0.3, 0.55, 1.0), Color(0.7, 0.85, 1.0)],
	OCEAN: [Color(0.1, 0.38, 0.9), Color(0.35, 0.8, 1.0), Color(0.85, 0.95, 1.0)],
	RIVER: [Color(0.15, 0.6, 0.95), Color(0.45, 0.95, 1.0), Color(1.0, 1.0, 1.0)],
	SAND: [Color(0.75, 0.55, 0.28), Color(1.0, 0.82, 0.5), Color(1.0, 0.95, 0.75)],
	PLAINS: [Color(0.4, 0.7, 0.18), Color(0.7, 1.0, 0.4), Color(1.0, 0.9, 0.4)],
	FOREST: [Color(0.1, 0.55, 0.28), Color(0.4, 1.0, 0.55), Color(0.6, 0.35, 0.18)],
	MOUNTAIN: [Color(0.4, 0.28, 0.55), Color(0.8, 0.6, 1.0), Color(0.25, 0.16, 0.36)],
	SNOW: [Color(0.45, 0.38, 0.6), Color(0.85, 0.8, 1.0), Color(1.0, 1.0, 1.0)],
	CITY: [Color(0.45, 0.1, 0.4), Color(1.0, 0.4, 0.85), Color(1.0, 0.85, 0.35)],
	METRO: [Color(0.7, 0.12, 0.6), Color(1.0, 0.6, 1.0), Color(1.0, 1.0, 0.6)],
	CAPITOL: [Color(0.55, 0.42, 0.15), Color(1.0, 0.88, 0.5), Color(1.0, 1.0, 0.85)],
	PENTAGON: [Color(0.4, 0.1, 0.12), Color(1.0, 0.4, 0.35), Color(1.0, 0.85, 0.3)],
}


static func _poly(ci, pts: PackedVector2Array, fill: Color, line: Color, w := 1.5) -> void:
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, line, w, true)


## Szara wersja koloru, przyciemniona o podany mnożnik.
static func _greyed(col: Color, k: float) -> Color:
	var v := minf(col.get_luminance(), 1.0) * k
	return Color(v, v, v * 1.05, col.a)


static func _draw_terrain_icon(ci, t: int, c: Vector2, h: int, imp: bool, dead := false) -> void:
	var cols: Array = ICON_COLS[t]
	var fill: Color = cols[0]
	var line: Color = cols[1]
	var acc: Color = cols[2]
	var shine := Color(1, 1, 1, 0.5)
	if imp:
		fill = Color(0.3, 0.03, 0.3)
		line = IMP_PINK
		acc = IMP_CYAN
		shine = Color(IMP_CYAN.r, IMP_CYAN.g, IMP_CYAN.b, 0.6)
	elif dead:
		fill = _greyed(fill, 0.55)
		line = _greyed(line, 0.68)
		acc = _greyed(acc, 0.6)
		shine = Color(0.5, 0.5, 0.52, 0.25)
	var s := 14.0
	match t:
		FOREST:
			# choinka (czasem dwie mniejsze)
			var trees := [Vector2.ZERO] if h % 4 != 0 else [Vector2(-7, 2), Vector2(7, -1)]
			var sc := 1.0 if trees.size() == 1 else 0.72
			for tp in trees:
				var b: Vector2 = c + tp
				var k := s * sc
				ci.draw_rect(Rect2(b + Vector2(-0.14, 0.55) * k, Vector2(0.28, 0.4) * k), acc if not imp else line)
				_poly(ci, PackedVector2Array([b + Vector2(0, -0.2) * k, b + Vector2(0.85, 0.62) * k, b + Vector2(-0.85, 0.62) * k]), fill, line)
				_poly(ci, PackedVector2Array([b + Vector2(0, -1.0) * k, b + Vector2(0.62, -0.05) * k, b + Vector2(-0.62, -0.05) * k]), fill, line)
				ci.draw_line(b + Vector2(-0.15, -0.6) * k, b + Vector2(-0.4, -0.2) * k, shine, 1.2)
		PLAINS:
			# kępka trawy z kłosem
			for k in 5:
				var x := (k - 2) * 0.32
				var hgt := 0.55 + 0.35 * float((h >> k) & 1)
				_poly(ci, PackedVector2Array([c + Vector2(x - 0.12, 0.7) * s, c + Vector2(x + 0.12, 0.7) * s, c + Vector2(x + x * 0.4, 0.7 - hgt * 1.6) * s]), fill, line, 1.1)
			if h % 3 == 0:
				ci.draw_circle(c + Vector2(0.1, -0.75) * s, 2.6, acc)
		SAND:
			# wydma z kamyczkami
			var dune := PackedVector2Array()
			for k in 11:
				var a := PI + k / 10.0 * PI
				dune.append(c + Vector2(cos(a) * 0.95, sin(a) * 0.6 + 0.45) * s)
			_poly(ci, dune, fill, line)
			ci.draw_circle(c + Vector2(-0.3, 0.2) * s, 1.6, acc)
			ci.draw_circle(c + Vector2(0.35, 0.3) * s, 1.3, acc)
			ci.draw_line(c + Vector2(-0.5, -0.05) * s, c + Vector2(-0.15, -0.12) * s, shine, 1.2)
		RIVER:
			# kropla wody
			var drop := PackedVector2Array([c + Vector2(0, -1.0) * s])
			for k in 13:
				var a := -0.25 * PI + k / 12.0 * 1.5 * PI
				drop.append(c + Vector2(cos(a), sin(a)) * 0.62 * s + Vector2(0, 0.25) * s)
			_poly(ci, drop, fill, line)
			ci.draw_arc(c + Vector2(-0.15, 0.3) * s, 0.32 * s, PI * 0.6, PI * 1.1, 6, acc, 1.6, true)
		OCEAN, DEEP:
			# fala (głęboki ocean: dwie ciemniejsze)
			var rows := 1 if t == OCEAN else 2
			for k in rows:
				var oy := (0.0 if rows == 1 else (k - 0.5) * 0.75) * s
				var wv := PackedVector2Array()
				for j in 9:
					var xx := -1.0 + j * 0.25
					wv.append(c + Vector2(xx * s, oy + sin(j * 0.8) * 0.28 * s))
				for j in range(8, -1, -1):
					var xx := -1.0 + j * 0.25
					wv.append(c + Vector2(xx * s, oy + sin(j * 0.8) * 0.28 * s + 0.32 * s))
				_poly(ci, wv, fill, line, 1.2)
				ci.draw_circle(c + Vector2(0.55 * s, oy - 0.05 * s), 1.6, acc)
		MOUNTAIN, SNOW:
			# góra z cienistą stroną (+ śnieżna czapa)
			var top := c + Vector2(0, -1.0) * s
			var lft := c + Vector2(-1.0, 0.75) * s
			var rgt := c + Vector2(1.0, 0.75) * s
			_poly(ci, PackedVector2Array([top, rgt, lft]), fill, line)
			ci.draw_colored_polygon(PackedVector2Array([top, rgt, c + Vector2(0.1, 0.75) * s]), Color(acc.r, acc.g, acc.b, 0.55) if t == MOUNTAIN else Color(0.2, 0.15, 0.3, 0.45))
			if t == SNOW or imp:
				var cap_c := acc if imp or dead else Color(1, 1, 1)
				_poly(ci, PackedVector2Array([top, c + Vector2(0.38, -0.42) * s, c + Vector2(0.1, -0.3) * s, c + Vector2(-0.12, -0.45) * s, c + Vector2(-0.38, -0.42) * s]), cap_c, line, 1.0)
			ci.draw_polyline(PackedVector2Array([top, lft, rgt, top]), line, 1.6, true)
		CAPITOL:
			# kopuła Kapitolu na kolumnadzie
			_poly(ci, PackedVector2Array([c + Vector2(-0.95, 0.85) * s, c + Vector2(0.95, 0.85) * s, c + Vector2(0.95, 0.55) * s, c + Vector2(-0.95, 0.55) * s]), fill, line, 1.2)
			for k in 4:
				var cx := -0.65 + k * 0.43
				ci.draw_line(c + Vector2(cx, 0.55) * s, c + Vector2(cx, 0.0) * s, line, 1.4)
			_poly(ci, PackedVector2Array([c + Vector2(-0.85, 0.0) * s, c + Vector2(0.85, 0.0) * s, c + Vector2(0.7, -0.15) * s, c + Vector2(-0.7, -0.15) * s]), fill, line, 1.2)
			var dome := PackedVector2Array()
			for k in 9:
				dome.append(c + Vector2(cos(PI + k / 8.0 * PI) * 0.5, -0.15 + sin(PI + k / 8.0 * PI) * 0.55) * s)
			_poly(ci, dome, fill, line, 1.3)
			ci.draw_line(c + Vector2(0, -0.7) * s, c + Vector2(0, -0.95) * s, acc, 1.6)
		PENTAGON:
			# pięciokąt z dziedzińcem
			var outer := PackedVector2Array()
			var inner := PackedVector2Array()
			for k in 5:
				var a := -PI * 0.5 + k / 5.0 * TAU
				outer.append(c + Vector2.from_angle(a) * 0.9 * s)
				inner.append(c + Vector2.from_angle(a) * 0.4 * s)
			_poly(ci, outer, fill, line, 1.5)
			_poly(ci, inner, Color(fill.r * 0.4, fill.g * 0.4, fill.b * 0.4), line, 1.2)
			ci.draw_circle(c, 1.8, acc)
		CITY, METRO:
			# trzy wieżowce z oknami
			var bx := [-0.85, -0.25, 0.35]
			var bw := [0.5, 0.55, 0.5]
			var bh := [1.1 + 0.3 * float(h & 1), 1.65, 0.9 + 0.3 * float((h >> 1) & 1)]
			for k in 3:
				var br := Rect2(c + Vector2(bx[k], 0.85 - bh[k]) * s, Vector2(bw[k], bh[k]) * s)
				ci.draw_rect(br, fill)
				ci.draw_rect(br, line, false, 1.4)
				var wy := br.position.y + 3.0
				var row := 0
				while wy < br.end.y - 3.0:
					if ((h >> (row + k * 3)) & 1) == 1:
						ci.draw_rect(Rect2(br.position.x + 2.0, wy, 2.0, 2.0), acc)
					if ((h >> (row + k * 3 + 1)) & 1) == 1:
						ci.draw_rect(Rect2(br.end.x - 4.0, wy, 2.0, 2.0), acc)
					wy += 4.5
					row += 1


func _draw_crystals(ci, r: Rect2, c: Color, h: int) -> void:
	# kryształy rudy: wypełnione klejnoty z odblaskiem
	var center := r.get_center() + Vector2(0, 2)
	var cc := Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0))
	var offs := [Vector2(-8, 3), Vector2(7, 4), Vector2(0, -4)]
	var sizes := [6.0, 6.5, 8.5]
	for k in 3:
		var p: Vector2 = center + offs[k] + Vector2(((h >> (k * 2)) % 3) - 1, 0)
		var sz: float = sizes[k]
		var gem := PackedVector2Array([p + Vector2(0, -sz * 1.3), p + Vector2(sz * 0.7, -sz * 0.2), p + Vector2(sz * 0.45, sz * 0.8), p + Vector2(-sz * 0.45, sz * 0.8), p + Vector2(-sz * 0.7, -sz * 0.2)])
		_poly(ci, gem, Color(cc.r * 0.55, cc.g * 0.55, cc.b * 0.55), c, 1.5)
		ci.draw_line(p + Vector2(0, -sz * 1.3), p + Vector2(0, sz * 0.8), Color(cc.r, cc.g, cc.b, 0.6), 1.0)
		ci.draw_line(p + Vector2(-sz * 0.35, -sz * 0.6), p + Vector2(-sz * 0.15, -sz * 0.95), Color(1, 1, 1, 0.8), 1.4)


func _draw_scan() -> void:
	var rad := int(GameState.stat("scanner"))
	if rad <= 0 or ship == null or ship.docked:
		return
	var ctr := pos_to_idx(ship.global_position)
	if ctr < 0:
		return
	# przeszukanie tylko po zmianie kafelka pod statkiem
	if ctr != scan_center:
		scan_center = ctr
		scan_tiles.clear()
		var cx := ctr % N
		var cy := ctr / N
		for y in range(maxi(0, cy - rad), mini(H, cy + rad + 1)):
			for x in range(maxi(0, cx - rad), mini(N, cx + rad + 1)):
				if (x - cx) * (x - cx) + (y - cy) * (y - cy) > rad * rad:
					continue
				var i := y * N + x
				if deposit[i] != 0:
					scan_tiles.append(i)
	var pulse := 0.5 + 0.5 * sin(time * 4.0)
	for i in scan_tiles:
		if layer[i] != L_SURFACE:
			continue
		var c: Color = DEP_DEFS[deposit[i]]["color"]
		var p := idx_center(i)
		var s := 7.0
		var poly := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0), p + Vector2(0, -s)])
		scan_layer.draw_polyline(poly, Color(c.r, c.g, c.b, 0.5 + 0.5 * pulse), 1.5, true)
	var sp: Vector2 = ship.global_position
	scan_layer.draw_arc(sp, rad * T + T * 0.5, 0.0, TAU, 64, Color(0.5, 0.17, 1.25, 0.25), 1.0, true)


func _draw_overlay() -> void:
	# przygaszenie mapy: lekkie przy szybkim locie, mocniejsze w walce, najmocniejsze w obu naraz
	var dim := minf(0.3 * speed_k + 0.38 * combat_k, 0.55)
	if dim > 0.004:
		var ivt := get_viewport().get_canvas_transform().affine_inverse()
		var tl0: Vector2 = ivt * Vector2.ZERO
		overlay.draw_rect(Rect2(tl0, (ivt * get_viewport_rect().size) - tl0).grow(60), Color(0.0, 0.0, 0.02, dim))
	# kafelki niedawno trafione: błysk + mały czerwony pasek HP pod spodem (jak w Agrivore)
	for i in recent_hits:
		var r := Rect2(Vector2((i % N) * T, (i / N) * T), Vector2(T, T))
		if tile_flash.get(i, 0.0) > 0.0:
			overlay.draw_rect(r, Color(1.0, 1.0, 1.0, 0.22))
		var frac := clampf(hp[i] / max(1.0, max_hp[i]), 0.0, 1.0)
		var a := clampf(recent_hits[i] / 0.4, 0.0, 1.0)
		var bar := Rect2(r.position + Vector2(7, T - 8), Vector2(T - 14, 4))
		overlay.draw_rect(bar.grow(1), Color(0.0, 0.0, 0.0, 0.8 * a))
		overlay.draw_rect(bar, Color(0.35, 0.02, 0.06, a))
		overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(1.0, 0.22, 0.32, a))
	# cel lasera: ramka w narożnikach
	if target_idx >= 0 and is_minable(target_idx):
		var r := Rect2(Vector2((target_idx % N) * T, (target_idx / N) * T), Vector2(T, T)).grow(2)
		var cl := Color(1.0, 1.0, 1.0, 0.9)
		var k := 10.0
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var sx: float = 1.0 if c.x == r.position.x else -1.0
			var sy: float = 1.0 if c.y == r.position.y else -1.0
			overlay.draw_line(c, c + Vector2(k * sx, 0), cl, 2.0)
			overlay.draw_line(c, c + Vector2(0, k * sy), cl, 2.0)

	# wieżyczki
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var vsz := get_viewport_rect().size
	var tl: Vector2 = inv * Vector2.ZERO
	var cam_rect := Rect2(tl, (inv * vsz) - tl).grow(40)
	_draw_sector_borders(cam_rect)
	_draw_metro_last(cam_rect)
	# szerszy obszar: okrąg zasięgu wieżyczki spoza ekranu też musi być widoczny
	_ring_view = cam_rect
	_ring_q.clear()
	# zwykłe wieżyczki rysowane hurtem: trzy wywołania na wszystkie zamiast pięciu na każdą
	var body_pts := PackedVector2Array()
	var body_col := PackedColorArray()
	var top_pts := PackedVector2Array()
	var top_col := PackedColorArray()
	var outline := PackedVector2Array()
	for i in turrets_in_rect(cam_rect.grow(MISSILE_RANGE)):
		var tp := idx_center(i)
		if not cam_rect.has_point(tp):
			_range_ring(tp, MISSILE_RANGE if turrets[i].get("kind", "") == "missile" else TURRET_RANGE,
				Color(1.45, 0.1, 0.35) if turrets[i].get("kind", "") == "missile" else Color(1.3, 0.2, 0.15), i)
			continue
		if turrets[i].get("kind", "") == "missile":
			_draw_missile_turret(tp, turrets[i], i)
			continue
		var t: Dictionary = turrets[i]
		var fill := Color(0.3, 0.02, 0.02, 0.9)
		for k in 6:
			var h0: Vector2 = tp + HEX_UNIT[k] * 11.0
			var h1: Vector2 = tp + HEX_UNIT[k + 1] * 11.0
			body_pts.append_array([tp, h0, h1])
			body_col.append_array([fill, fill, fill])
			outline.append_array([h0, h1])
		# lufa jako wąski prostokąt
		var dir := Vector2.from_angle(t["angle"])
		var nrm := dir.orthogonal() * 1.5
		var tip := tp + dir * 17.0
		var bc := Color(1.25, 0.45, 0.13)
		top_pts.append_array([tp + nrm, tip + nrm, tip - nrm, tp + nrm, tip - nrm, tp - nrm])
		top_col.append_array([bc, bc, bc, bc, bc, bc])
		# migająca kropka ostrzegawcza
		var warn := 0.3 + 0.3 * sin(time * 6.0 + i)
		var dc := Color(1.25, 0.09, 0.09, 0.6 + warn)
		for k in 6:
			top_pts.append_array([tp, tp + HEX_UNIT[k] * 3.2, tp + HEX_UNIT[k + 1] * 3.2])
			top_col.append_array([dc, dc, dc])
		# zasięg tylko tych wieżyczek, które właśnie mogą trafić statek (mniej linii w gęstych miastach)
		_range_ring(tp, TURRET_RANGE, Color(1.3, 0.2, 0.15), i)
	if not body_pts.is_empty():
		var ci := overlay.get_canvas_item()
		RenderingServer.canvas_item_add_triangle_array(ci, _seq_indices(body_pts.size()), body_pts, body_col)
		overlay.draw_multiline(outline, Color(1.25, 0.22, 0.09), 1.8)
		RenderingServer.canvas_item_add_triangle_array(ci, _seq_indices(top_pts.size()), top_pts, top_col)
	_flush_rings()

	# wieżyczki Imperium i ich strzały
	for i in ally_turrets:
		var ap := idx_center(i)
		if not cam_rect.has_point(ap):
			continue
		var at: Dictionary = ally_turrets[i]
		var hx := PackedVector2Array()
		for k in 7:
			hx.append(ap + Vector2.from_angle(k / 6.0 * TAU + PI / 6.0) * 10.0)
		overlay.draw_colored_polygon(hx, Color(0.2, 0.12, 0.02, 0.95))
		overlay.draw_polyline(hx, Color(1.3, 0.9, 0.35), 1.8, true)
		overlay.draw_line(ap, ap + Vector2.from_angle(at["angle"]) * 16.0, Color(0.4, 1.1, 1.3), 3.0, true)
		overlay.draw_circle(ap, 3.0, Color(0.5, 1.2, 1.4))
	for sh in ally_shots:
		var sa: float = sh["life"] / 0.14
		overlay.draw_line(sh["a"], sh["b"], Color(0.4, 1.0, 1.3, 0.35 * sa), 5.0, true)
		overlay.draw_line(sh["a"], sh["b"], Color(1.2, 1.3, 1.4, sa), 1.6, true)

	# pociski: ciemna obwódka, czerwony żar i białe jądro - widać je na każdym kafelku
	for b in bullets:
		var p: Vector2 = b["pos"]
		var v: Vector2 = b["vel"].normalized()
		overlay.draw_circle(p, 8.0, Color(0.0, 0.0, 0.0, 0.6))
		overlay.draw_line(p - v * 16.0, p, Color(1.35, 0.2, 0.08, 0.75), 4.0, true)
		overlay.draw_circle(p, 5.0, Color(1.4, 0.3, 0.1))
		overlay.draw_circle(p, 2.2, Color(1.5, 1.4, 1.2))
	for m in missiles:
		_draw_missile(m)
	_draw_city_labels(cam_rect)


## Granice sektorów: delikatny, sunący pas świateł widoczny tylko, gdy statek jest blisko.
func _draw_sector_borders(_view: Rect2) -> void:
	if ship == null or ship.docked:
		return
	var sp: Vector2 = ship.global_position
	for k in range(1, Sectors.COLS):
		var x := float(k * Sectors.SIZE * T)
		var near := 1.0 - absf(sp.x - x) / BORDER_FADE
		if near > 0.0:
			_border_strip(Vector2(x, sp.y), Vector2(0, 1), near)
	for k in range(1, Sectors.ROWS):
		var y := float(k * Sectors.SIZE * T)
		var near := 1.0 - absf(sp.y - y) / BORDER_FADE
		if near > 0.0:
			_border_strip(Vector2(sp.x, y), Vector2(1, 0), near)
	# pole siłowe zamkniętych sektorów: pas wzdłuż każdej krawędzi graniczącej z resztą mapy
	for s in Sectors.LIST.size():
		if GameState.sector_open(s):
			continue
		var r: Rect2i = Sectors.sector_rect(s)
		var rp := Rect2(Vector2(r.position) * T, Vector2(r.size) * T)
		var fade := BORDER_FADE * 1.6
		var cx := clampf(sp.x, rp.position.x + 40.0, rp.end.x - 40.0)
		var cy := clampf(sp.y, rp.position.y + 40.0, rp.end.y - 40.0)
		if rp.position.y > 0.0:
			_barrier_strip(Vector2(cx, rp.position.y), Vector2(1, 0), 1.0 - absf(sp.y - rp.position.y) / fade, rp.position.x, rp.end.x)
		if rp.end.y < H * T:
			_barrier_strip(Vector2(cx, rp.end.y), Vector2(1, 0), 1.0 - absf(sp.y - rp.end.y) / fade, rp.position.x, rp.end.x)
		if rp.position.x > 0.0:
			_barrier_strip(Vector2(rp.position.x, cy), Vector2(0, 1), 1.0 - absf(sp.x - rp.position.x) / fade, rp.position.y, rp.end.y)
		if rp.end.x < N * T:
			_barrier_strip(Vector2(rp.end.x, cy), Vector2(0, 1), 1.0 - absf(sp.x - rp.end.x) / fade, rp.position.y, rp.end.y)


## Pole siłowe: czerwone, gęste pasy z poprzecznymi żebrami (lo/hi - granice krawędzi wzdłuż dir).
func _barrier_strip(center: Vector2, dir: Vector2, near: float, lo: float, hi: float) -> void:
	if near <= 0.0:
		return
	var a := near * near
	var span := BORDER_DASH * 10.0
	var along := center.dot(dir)
	var p0 := center + dir * (maxf(along - span, lo) - along)
	var p1 := center + dir * (minf(along + span, hi) - along)
	overlay.draw_line(p0, p1, Color(1.4, 0.1, 0.15, 0.12 * a), 40.0)
	overlay.draw_line(p0, p1, Color(1.5, 0.3, 0.3, 0.85 * a), 3.0)
	var n := dir.orthogonal()
	var scroll := fposmod(center.dot(dir) + time * 90.0, 48.0)
	for k in range(-20, 21):
		var q := center + dir * (k * 48.0 - scroll)
		var qa := q.dot(dir)
		if qa < lo or qa > hi:
			continue
		var f := clampf(1.0 - absf(k * 48.0) / span, 0.0, 1.0)
		overlay.draw_line(q - n * 14.0, q + n * 14.0, Color(1.4, 0.2, 0.2, 0.6 * a * f), 2.0)


func _border_strip(center: Vector2, dir: Vector2, near: float) -> void:
	var world_rect := Rect2(0.0, 0.0, N * T, H * T)
	var along := center.dot(dir)
	var scroll := fposmod(along + time * 60.0, BORDER_DASH)
	for n in range(-9, 10):
		var o := n * BORDER_DASH - scroll + BORDER_DASH * 0.5
		var f := clampf(1.0 - absf(o) / (BORDER_DASH * 8.5), 0.0, 1.0)
		var a := center + dir * o
		var b := a + dir * BORDER_DASH * 0.55
		if f <= 0.0 or not world_rect.has_point(a) or not world_rect.has_point(b):
			continue
		var alpha := near * near * f
		overlay.draw_line(a, b, Color(0.3, 0.9, 1.2, 0.14 * alpha), 14.0)
		overlay.draw_line(a, b, Color(0.5, 1.0, 1.3, 0.7 * alpha), 2.5)

## Wieżyczka rakietowa: duży, jaskrawoczerwony znak, pulsuje szybciej tuż przed strzałem.
func _draw_missile_turret(tp: Vector2, t: Dictionary, i: int) -> void:
	var soon: bool = t["cd"] < 1.2
	var pulse := 0.5 + 0.5 * sin(time * (14.0 if soon else 5.0) + i)
	var r := 19.0 + pulse * 2.5
	var dia := PackedVector2Array([tp + Vector2(0, -r), tp + Vector2(r, 0), tp + Vector2(0, r), tp + Vector2(-r, 0)])
	overlay.draw_colored_polygon(dia, Color(1.1 + pulse * 0.3, 0.03, 0.03))
	dia.append(dia[0])
	overlay.draw_polyline(dia, Color(1.5, 0.9, 0.8), 2.5, true)
	overlay.draw_arc(tp, 27.0 + pulse * 7.0, 0.0, TAU, 28, Color(1.4, 0.1, 0.1, 0.9 - pulse * 0.5), 2.5, true)
	# biała rakieta skierowana w stronę gracza
	var d := Vector2.from_angle(t["angle"])
	var n := d.orthogonal()
	overlay.draw_colored_polygon(PackedVector2Array([tp + d * 12.0, tp + n * 4.5, tp - d * 7.0 + n * 4.5, tp - d * 7.0 - n * 4.5, tp - n * 4.5]), Color(1.4, 1.4, 1.4))
	overlay.draw_line(tp - d * 7.0 + n * 7.0, tp - d * 7.0 - n * 7.0, Color(1.4, 1.4, 1.4), 2.0)
	_range_ring(tp, MISSILE_RANGE, Color(1.45, 0.1, 0.35), i)


## Zasięg wrogiej wieżyczki: wyraźna linia z poświatą i sunącymi kreskami na zewnątrz.
## Pojawia się już na 300 px przed granicą (widać strefę, zanim się w nią wleci), w środku świeci pełną mocą.
## Okręgi trafiają najpierw do kolejki (_ring_q), a rysuje je _flush_rings: pełny wygląd mają tylko
## najbliższe statkowi, reszta to sama cienka linia. Okręgi całkiem poza ekranem są pomijane.
func _range_ring(tp: Vector2, r: float, c: Color, i: int) -> void:
	if ship == null or ship.docked or not show_ranges:
		return
	var d: float = tp.distance_to(ship.global_position)
	var k := clampf((r + 300.0 - d) / 300.0, 0.0, 1.0)
	if k <= 0.0:
		return
	if not _ring_view.intersects(Rect2(tp - Vector2(r + 8.0, r + 8.0), Vector2(r + 8.0, r + 8.0) * 2.0)):
		return
	_ring_q.append([d, tp, r, c, i, k * (1.0 if d < r else 0.7)])


## Indeksy 0..n-1 dla tablic trójkątów (pamiętane, żeby nie budować ich co klatkę).
func _seq_indices(n: int) -> PackedInt32Array:
	if _idx_cache.size() < n:
		var old := _idx_cache.size()
		_idx_cache.resize(maxi(n, old * 2))
		for k in range(old, _idx_cache.size()):
			_idx_cache[k] = k
	return _idx_cache.slice(0, n)


func _flush_rings() -> void:
	if _ring_q.is_empty():
		return
	_ring_q.sort_custom(func(x, y): return x[0] < y[0])
	for q in mini(_ring_q.size(), RING_MAX):
		var e: Array = _ring_q[q]
		var tp: Vector2 = e[1]
		var r: float = e[2]
		var c: Color = e[3]
		var i: int = e[4]
		var a: float = e[5]
		var pulse := 0.5 + 0.5 * sin(time * 3.0 + i)
		if q >= RING_FULL_DETAIL:
			overlay.draw_arc(tp, r, 0.0, TAU, 48, Color(c.r, c.g, c.b, (0.4 + 0.15 * pulse) * a), 2.0)
			continue
		overlay.draw_arc(tp, r - 7.0, 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.07 * a), 14.0)
		overlay.draw_arc(tp, r, 0.0, TAU, 72, Color(c.r, c.g, c.b, (0.45 + 0.2 * pulse) * a), 2.5, true)
		# kreski sunące po obwodzie - jedno wywołanie na cały okrąg
		var n := int(r / 34.0)
		var rot := time * 0.2 * (1.0 if i % 2 == 0 else -1.0)
		var seg := PackedVector2Array()
		var rr := r + 6.0
		for s in n:
			var s0 := rot + s * TAU / n
			var s1 := s0 + TAU / n * 0.4
			var sm := (s0 + s1) * 0.5
			var pm := tp + Vector2.from_angle(sm) * rr
			seg.append(tp + Vector2.from_angle(s0) * rr)
			seg.append(pm)
			seg.append(pm)
			seg.append(tp + Vector2.from_angle(s1) * rr)
		overlay.draw_multiline(seg, Color(c.r, c.g, c.b, 0.35 * a), 2.0)
	_ring_q.clear()


func _draw_missile(m: Dictionary) -> void:
	var p: Vector2 = m["pos"]
	var d := Vector2.from_angle(m["rot"])
	var n := d.orthogonal()
	var blink := 0.6 + 0.4 * sin(time * 24.0)
	overlay.draw_arc(p, 20.0, 0.0, TAU, 20, Color(1.4, 0.15, 0.1, 0.6 * blink), 2.0, true)
	overlay.draw_line(p - d * 12.0, p - d * (30.0 + randf() * 12.0), Color(1.4, 0.7, 0.2, 0.9), 4.0, true)
	overlay.draw_colored_polygon(PackedVector2Array([p + d * 15.0, p + n * 4.5, p - d * 11.0 + n * 4.5, p - d * 11.0 - n * 4.5, p - n * 4.5]), Color(1.3, 0.12, 0.1))
	overlay.draw_circle(p + d * 7.0, 2.5, Color(1.5, 1.4, 1.2))


## Ostatnie kafelki metropolii pulsują i drżą.
func _draw_metro_last(view: Rect2) -> void:
	for tiles in metro_last:
		for i in tiles:
			var p := idx_center(i)
			if not view.has_point(p):
				continue
			var pulse := 0.5 + 0.5 * sin(time * 9.0 + i)
			var r := Rect2(p - Vector2(T, T) * 0.5, Vector2(T, T))
			r.position += Vector2(sin(time * 33.0 + i), cos(time * 41.0 + i)) * 2.5
			overlay.draw_rect(r, Color(1.4, 0.2, 1.1, 0.14 + 0.3 * pulse))
			overlay.draw_rect(r.grow(2.0 + pulse * 3.0), Color(1.5, 0.5, 1.3, 0.5 + 0.5 * pulse), false, 2.5)


## Różowy punkt powrotu do walki z bossem.
func _draw_boss_portal(p: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(time * 4.0)
	var c := Color(1.5, 0.3, 1.2)
	overlay.draw_circle(p, BOSS_PORTAL_RADIUS * 0.8, Color(0.5, 0.02, 0.4, 0.45))
	for k in 3:
		var a := time * (1.3 + k * 0.5) * (1.0 if k % 2 == 0 else -1.0)
		var rad := BOSS_PORTAL_RADIUS * (0.5 + k * 0.25)
		for seg in 3:
			var s0 := a + seg * TAU / 3.0
			overlay.draw_arc(p, rad, s0, s0 + 1.4, 16, Color(c.r, c.g, c.b, 0.6 + 0.4 * pulse), 3.0, true)
	overlay.draw_circle(p, 12.0 + pulse * 6.0, Color(1.5, 1.2, 1.5))


## Podpisy metropolii na mapie.
func _draw_city_labels(view: Rect2) -> void:
	var font := Style.font_pixel()
	var fsize := 72
	for s in Sectors.LIST.size():
		var p := city_pos(s)
		if not view.grow(600.0).has_point(p):
			continue
		if GameState.boss_state(s) != "":
			_draw_boss_portal(p)
		var txt: String = Sectors.LIST[s]["city"]
		if txt == "":
			continue
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var at := p + Vector2(-w * 0.5, 24.0)
		overlay.draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 14, Color(0.02, 0.0, 0.06, 0.92))
		overlay.draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1.3, 0.75, 1.2))
	# obiekty specjalne: mniejszy, złoto-czerwony podpis
	for k in landmark_cells.size():
		var p := landmark_pos(k)
		if not view.grow(600.0).has_point(p):
			continue
		var txt: String = Sectors.LANDMARKS[k]["name"]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x
		var at := p + Vector2(-w * 0.5, 16.0)
		overlay.draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 48, 12, Color(0.02, 0.0, 0.06, 0.92))
		overlay.draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(1.3, 0.85, 0.4))
