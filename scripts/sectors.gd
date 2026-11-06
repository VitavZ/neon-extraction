extends RefCounted
## Sektory USA: świat to siatka 3x3 map po 160x160 kafelków, wycięta z prostokąta długości i szerokości
## geograficznej (cały teren to prawdziwa mapa, łącznie z pasem Meksyku na południu). Każdy sektor ma
## metropolię (podpisaną w grze i na minimapie) oraz miejsce postoju Statku Matki. Wyjątek to Dystrykt
## Federalny z Waszyngtonem i Pentagonem: zamknięty polem siłowym do zniszczenia wszystkich metropolii.
##
## Wiersze mają po 8,9° szerokości geograficznej, granica północ/środek biegnie po 39,85° N - między
## Nowym Jorkiem a Waszyngtonem, żeby stolica dostała własny sektor.

const COLS := 3
const ROWS := 3
const SIZE := 160
## Ile razy sektory są większe niż pierwotne 128 kafelków (odległości w kafelkach skalują się o tyle).
const SCALE := SIZE / 128.0
const W := COLS * SIZE
const H := ROWS * SIZE
const GEO_H := H              # cała mapa jest geograficzna (stała zostaje dla narzędzia do wypiekania)

const LON_MIN := -125.5
const LON_MAX := -66.5
const LAT_MAX := 48.75
const LAT_MIN := 22.05
## Rzut sprzed mapy 3x3 (dwa wiersze, 24,5°-49,5°) - do przeniesienia starych zapisów.
const OLD_LAT_MAX := 49.5
const OLD_LAT_MIN := 24.5

const START := 2   # gra zaczyna się w Appalachach: blisko są wszystkie surowce podstawowe

const LIST := [
	{"name": "PÓŁNOCNY ZACHÓD", "city": "SEATTLE", "destroyed": "SEATTLE ZNISZCZONE", "city_lonlat": Vector2(-122.3, 47.6), "dock_lonlat": Vector2(-116.5, 45.5), "city_r": 8.5},
	{"name": "ŚRODKOWY ZACHÓD", "city": "CHICAGO", "destroyed": "CHICAGO ZNISZCZONE", "city_lonlat": Vector2(-87.9, 41.9), "dock_lonlat": Vector2(-93.0, 42.5), "city_r": 9.5},
	{"name": "PÓŁNOCNY WSCHÓD", "city": "NOWY JORK", "destroyed": "NOWY JORK ZNISZCZONY", "boss": true, "boss_music": "res://audio/music/liberty_down.mp3", "city_lonlat": Vector2(-74.2, 40.8), "dock_lonlat": Vector2(-79.5, 41.2), "city_r": 10.0},
	{"name": "ZACHÓD", "city": "LOS ANGELES", "destroyed": "LOS ANGELES ZNISZCZONE", "city_lonlat": Vector2(-118.1, 34.1), "dock_lonlat": Vector2(-113.0, 36.0), "city_r": 9.5},
	{"name": "WIELKIE RÓWNINY", "city": "DALLAS", "destroyed": "DALLAS ZNISZCZONE", "city_lonlat": Vector2(-96.8, 32.8), "dock_lonlat": Vector2(-101.0, 33.0), "city_r": 9.0},
	{"name": "DYSTRYKT FEDERALNY", "city": "", "sub": "WASZYNGTON  •  PENTAGON", "federal": true, "danger": 60.0,
		"city_lonlat": Vector2(-77.3, 38.7), "dock_lonlat": Vector2(-81.5, 37.6), "city_r": 0.0},
	{"name": "SONORA", "city": "HERMOSILLO", "destroyed": "HERMOSILLO ZNISZCZONE", "city_lonlat": Vector2(-110.95, 29.08), "dock_lonlat": Vector2(-108.6, 27.6), "city_r": 7.0},
	{"name": "WYBRZEŻE ZATOKI", "city": "HOUSTON", "destroyed": "HOUSTON ZNISZCZONY", "city_lonlat": Vector2(-95.4, 29.8), "dock_lonlat": Vector2(-99.6, 29.0), "city_r": 9.0},
	{"name": "POŁUDNIOWY WSCHÓD", "city": "MIAMI", "destroyed": "MIAMI ZNISZCZONE", "city_lonlat": Vector2(-80.4, 25.9), "dock_lonlat": Vector2(-82.2, 29.4), "city_r": 7.0},
]
## Stara numeracja sektorów (siatka 3x2) -> nowa (3x3). Do przeniesienia zapisów.
const OLD_SECTOR := {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 8}


## Obiekty specjalne: super strzeżone, z własnym bossem (na razie bez walki, "boss" pusty).
## r - promień w kafelkach; shape - kształt kompleksu.
const LANDMARKS := [
	{"id": "washington", "name": "WASZYNGTON", "destroyed": "WASZYNGTON ZNISZCZONY", "lonlat": Vector2(-77.04, 38.9), "r": 3.3, "shape": "capitol", "boss": ""},
	{"id": "pentagon", "name": "PENTAGON", "destroyed": "PENTAGON ZNISZCZONY", "lonlat": Vector2(-77.6, 38.45), "r": 3.4, "shape": "pentagon", "boss": ""},
]
## Pas obrony wokół obiektu specjalnego (kafelki poza jego promieniem).
const LANDMARK_GUARD := 7.0


## Zamiana długości i szerokości geograficznej na współrzędne kafelka.
static func cell_of(lonlat: Vector2) -> Vector2i:
	return Vector2i(
		int((lonlat.x - LON_MIN) / (LON_MAX - LON_MIN) * W),
		int((LAT_MAX - lonlat.y) / (LAT_MAX - LAT_MIN) * H))


static func lonlat_of(x: float, y: float) -> Vector2:
	return Vector2(LON_MIN + x / W * (LON_MAX - LON_MIN), LAT_MAX - y / H * (LAT_MAX - LAT_MIN))


## Sektor bez lądu (w mapie 3x3 nie ma takich, zostaje dla porządku).
static func is_void(s: int) -> bool:
	return bool(LIST[s].get("void", false))


static func has_city(s: int) -> bool:
	return String(LIST[s]["city"]) != ""


## Co jest w sektorze do zniszczenia (podpisy w Sterowni i przy wlocie).
static func label(s: int) -> String:
	return String(LIST[s]["city"]) if has_city(s) else String(LIST[s].get("sub", "OCEAN"))


static func sector_at(x: int, y: int) -> int:
	return clampi(x / SIZE, 0, COLS - 1) + clampi(y / SIZE, 0, ROWS - 1) * COLS


static func sector_rect(s: int) -> Rect2i:
	return Rect2i((s % COLS) * SIZE, (s / COLS) * SIZE, SIZE, SIZE)


## Odległość sektorów w krokach siatki (także koszt przeniesienia Matki).
static func steps(a: int, b: int) -> int:
	return absi(a % COLS - b % COLS) + absi(a / COLS - b / COLS)
