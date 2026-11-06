extends Node2D
## Mapa świata, część 1/5: sygnały, stałe, cały stan i zapytania (pozycje, sektory, zagrożenie, metropolie, landmarki,
## łup z kafelków, zapis). Łańcuch: base -> art -> damage -> defense -> overlay -> scripts/world.gd.
## Każda część widzi tylko funkcje z części wcześniejszych.


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
var metro_imperial: Array = [] # ile kafelków metropolii stało się kafelkami Imperium (odbudowa, rozrost)
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


const MINER_SOURCES := {"wood": [FOREST], "stone": [MOUNTAIN, SNOW], "biomass": [PLAINS], "water": [RIVER], "saltwater": [OCEAN, DEEP],
	"sand": [SAND]}
## Tyle kafelków odstępu od miast trzymają statki wydobywcze: więcej niż zasięg wieżyczki (430 px = 9 kafelków).
const MINER_CITY_GAP := 12
## Złoże musi leżeć tak daleko od każdej wieżyczki (także górskiej).
const MINER_SAFE := TURRET_RANGE + 140.0
const MINER_DEPOSITS := {"copper": 1, "iron": 2, "gold": 3, "uranium": 4, "neonite": 5}


## Minimapa w kolorach gry: ciemne granaty i fiolety, a miasta świecą różem.
const MINI_COLORS := {
	DEEP: Color(0.02, 0.04, 0.18), OCEAN: Color(0.03, 0.08, 0.28), RIVER: Color(0.12, 0.55, 0.85),
	SAND: Color(0.52, 0.4, 0.5), PLAINS: Color(0.2, 0.2, 0.42), FOREST: Color(0.08, 0.36, 0.44),
	MOUNTAIN: Color(0.4, 0.2, 0.62), SNOW: Color(0.66, 0.58, 0.88), CITY: Color(0.8, 0.16, 0.62), METRO: Color(1.0, 0.32, 0.88),
	CAPITOL: Color(1.0, 0.85, 0.4), PENTAGON: Color(1.0, 0.3, 0.25),
}


const IMP_CYAN := Color(0.4, 0.95, 1.0)
const IMP_FILL := Color(0.11, 0.02, 0.17)
const IMP_PINK := Color(1.15, 0.2, 0.85)


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


## Liczy, ile kafelków metropolii stoi (start gry i po wczytaniu zapisu).
func _count_metros() -> void:
	var n: int = Sectors.LIST.size()
	metro_total.resize(n)
	metro_left.resize(n)
	metro_last.resize(n)
	metro_total.fill(0)
	metro_left.fill(0)
	metro_imperial.resize(n)
	metro_imperial.fill(0)
	for i in TOTAL:
		if surface[i] == METRO:
			var s := Sectors.sector_at(i % N, i / N)
			metro_total[s] += 1
			if layer[i] == L_SURFACE:
				metro_left[s] += 1
			elif layer[i] == L_IMPERIAL:
				metro_imperial[s] += 1
	for s in n:
		metro_last[s] = []
		_refresh_metro_last(s)
		_report_metro_rebuilt(s)
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


## Kafelek stał się kafelkiem Imperium: jeśli to metropolia, rośnie postęp jej odbudowy (rozkaz "Odbuduj ...").
func _metro_tile_imperial(i: int) -> void:
	if surface[i] != METRO:
		return
	var s := Sectors.sector_at(i % N, i / N)
	metro_imperial[s] += 1
	_report_metro_rebuilt(s)


func _report_metro_rebuilt(s: int) -> void:
	GameState.set_metro_rebuilt(s, float(metro_imperial[s]) / maxf(1.0, float(metro_total[s])))


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


## Koszt odbudowy: tyle, ile kafelek daje bazowo (bez mnożników). Ułamkowe drobne łupy się nie liczą.
func rebuild_cost(i: int) -> Dictionary:
	var out := {}
	var src: Dictionary = TILE_DEFS[surface[i]]["drops"]
	for k in src:
		var n := int(src[k])
		if n > 0:
			out[k] = n
	return out


func _hash(x: int, y: int) -> int:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h


# =====================================================================
# LASER / NISZCZENIE
# =====================================================================


func _chunk_center(k: int) -> Vector2:
	return (Vector2(k % CHUNK_COLS, k / CHUNK_COLS) + Vector2(0.5, 0.5)) * float(CHUNK * T)


## Jaki rodzaj istot można porwać z kafelka ("" = nic).
func abduct_source(i: int) -> String:
	if i < 0 or layer[i] != L_SURFACE or abducted[i] == 1:
		return ""
	return String(CREATURE_OF.get(surface[i], ""))


## Procent całego świata (wszystkie sektory): zniszczone teraz i zabudowane przez Imperium.
func devastated_percent() -> float:
	return devastated_count * 100.0 / playable


func imperial_percent() -> float:
	return imperial_count * 100.0 / playable


## Przyrost Potęgi Imperium na sekundę.
func power_rate() -> float:
	return imperial_count * GameState.stat("power_mult") / POWER_SECONDS_PER_TILE


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
