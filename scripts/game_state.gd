extends Node
## Globalny stan gry (autoload "GameState"): surowce, ładownia, ulepszenia, zapis.

signal bank_changed
signal cargo_changed
signal stats_changed
signal research_done(u: Dictionary)
signal quest_completed(q: Dictionary)

const Upgrades = preload("res://scripts/upgrades.gd")
const Quests = preload("res://scripts/quests.gd")

const Sectors = preload("res://scripts/sectors.gd")

const TILE := 48
## Koszt przeniesienia Statku Matki o jeden sektor (mnożony przez liczbę kroków).
const MOVE_COST := {"metal": 220, "electronics": 45, "gold": 14, "uranium": 6}
const OLD_SAVE_PATH := "user://neon_extraction_save.json"   # zapis sprzed slotów
const SAVE_SLOTS := 3
const SETTINGS_PATH := "user://settings.cfg"
## Sterowanie do przypisania w opcjach: [akcja, opis, domyślny klawisz]. Mysz (LPM, PPM, kółko) zostaje stała.
const KEY_ACTIONS := [
	["thrust", "Ciąg / lot w górę", KEY_W],
	["brake", "Hamulec / lot w dół", KEY_S],
	["stop", "Pełny stop (do zera)", KEY_CTRL],
	["left", "Manewr w lewo", KEY_A],
	["right", "Manewr w prawo", KEY_D],
	["drift", "Drift / bomba", KEY_SPACE],
	["focus", "Precyzja (boss)", KEY_SHIFT],
	["dock", "Dokowanie / wylot", KEY_E],
	["tool1", "Laser górniczy", KEY_1],
	["tool2", "Promień porywania", KEY_2],
	["tool3", "Odbudowa", KEY_3],
	["wing", "Wezwij myśliwce Imperium", KEY_4],
	["rocket", "Odpal rakietę", KEY_Q],
	["params", "Parametry statku", KEY_P],
	["center", "Wyśrodkuj siatkę", KEY_R],
	["pause", "Pauza", KEY_ESCAPE],
	["crt", "Filtr CRT", KEY_F2],
	["fps", "Licznik FPS", KEY_F3],
]
const KEY_NAMES := {"Space": "SPACJA", "Escape": "ESC", "Shift": "SHIFT", "Ctrl": "CTRL", "Alt": "ALT", "Tab": "TAB",
	"Enter": "ENTER", "Backspace": "BACKSPACE", "Up": "STRZAŁKA W GÓRĘ", "Down": "STRZAŁKA W DÓŁ", "Left": "STRZAŁKA W LEWO", "Right": "STRZAŁKA W PRAWO"}
const RESOLUTIONS :=[Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

var slot := 1   # aktywny plik zapisu (1..3)
var keys: Dictionary = {}   # akcja -> klawisz fizyczny (ustawienia)
## Ustawienia (menu OPCJE), zapisywane w user://settings.cfg
var settings := {
	"resolution": 2, "fullscreen": false, "vsync": true, "volume": 80, "music": 70, "sfx": 80,
	"crt": true, "glow": true, "shake": true, "comfort": 1, "quality": 0,
}

const RES_ORDER := ["wood", "stone", "water", "saltwater", "sand", "biomass", "scrap", "metal",
	"electronics", "weapon_scrap", "copper", "iron", "gold", "uranium", "neonite", "power", "glory", "loyalty", "humans", "cows", "deer"]

## Statystyki liczone w sztukach (zaokrąglane po Mistrzostwie).
const INT_STATS := ["drone_count", "escort_count", "chain_jumps", "abduct_amount", "bio_capacity", "scanner", "miner_count", "wing_count", "transit_count"]

## Waluty Imperium: nie są surowcami, więc w magazynie mają osobne miejsce.
const CURRENCIES := ["power", "glory", "loyalty"]
const CURRENCY_ICONS := {"power": "crown", "glory": "star", "loyalty": "core"}
const CURRENCY_SHORT := {"power": "POTĘGA", "glory": "CHWAŁA", "loyalty": "LOJALNOŚĆ"}

## Istoty do porywania (trzymane w osobnych komorach bio) i z jakiego terenu pochodzą.
const CREATURES := ["humans", "cows", "deer"]

const RES_NAMES := {
	"wood": "Drewno", "stone": "Kamień", "water": "Woda", "saltwater": "Słona woda",
	"sand": "Piasek", "biomass": "Biomasa", "scrap": "Złom", "metal": "Metal",
	"electronics": "Elektronika", "copper": "Miedź", "iron": "Żelazo", "gold": "Złoto",
	"uranium": "Uran", "neonite": "Neonit", "weapon_scrap": "Resztki broni",
	"humans": "Ludzie", "cows": "Krowy", "deer": "Jelenie", "power": "Potęga Imperium", "glory": "Punkty Chwały", "loyalty": "Punkty Lojalności",
}

const RES_COLORS := {
	"wood": Color(0.35, 1.0, 0.45), "stone": Color(0.75, 0.6, 1.0), "water": Color(0.35, 0.95, 1.0),
	"saltwater": Color(0.3, 0.55, 1.0), "sand": Color(1.0, 0.82, 0.45), "biomass": Color(0.7, 1.0, 0.35),
	"scrap": Color(1.0, 0.35, 0.75), "metal": Color(0.8, 0.85, 0.95), "electronics": Color(0.3, 1.0, 0.8),
	"copper": Color(1.0, 0.55, 0.25), "iron": Color(0.85, 0.75, 0.8), "gold": Color(1.0, 0.85, 0.2),
	"uranium": Color(0.45, 1.0, 0.3), "neonite": Color(1.0, 0.3, 1.0), "weapon_scrap": Color(1.0, 0.3, 0.25),
	"power": Color(1.0, 0.78, 0.3), "glory": Color(1.0, 0.4, 0.9), "loyalty": Color(0.45, 0.9, 1.0), "humans": Color(1.0, 0.8, 0.65), "cows": Color(0.95, 0.95, 0.85), "deer": Color(0.85, 0.6, 0.35),
}

const BASE_STATS := {
	"laser_dps": 15.0, "laser_range": 260.0, "laser_splash": 0.0, "deposit_damage_mult": 1.0,
	"max_hull": 100.0, "armor": 0.0, "max_shield": 0.0, "shield_regen": 0.0, "hull_regen": 0.0,
	"thrust": 700.0, "max_speed": 430.0, "turn_rate": 6.0, "brake": 2.5, "strafe": 0.45,
	"chain_jumps": 0.0, "chain_power": 0.5, "chain_interval": 0.8, "chain_range": 170.0,
	"det_chance": 0.0, "det_power": 0.8, "det_radius": 1.5,
	"escort_count": 0.0, "escort_power": 0.25, "escort_hp": 0.25,
	"fighter_damage": 1.0, "hull_siphon": 0.0, "salvage": 0.0,
	"cargo": 30.0, "cargo_mult": 1.0, "yield_mult": 1.0, "deposit_yield_mult": 1.0, "scanner": 0.0, "teleport": 0.0,
	"max_fuel": 30.0, "fuel_efficiency": 0.0, "fuel_siphon": 0.0, "drift_boost": 160.0,
	"rocket_unlocked": 0.0, "rocket_cooldown": 10.0, "rocket_radius": 4.0, "rocket_damage": 10.0,
	"drone_count": 0.0, "drone_damage": 6.0, "drone_interval": 1.5,
	"gun_unlocked": 0.0, "gun_damage": 8.0, "gun_interval": 0.5, "gun_range": 380.0,
	"armory": 0.0, "bridge": 0.0, "lab": 0.0, "abduct_speed": 1.0, "abduct_range": 220.0, "abduct_amount": 1.0, "abduct_area": 0.5,
	"rebuild": 0.0, "rebuild_area": 0.5, "rebuild_speed": 1.0, "rebuild_range": 260.0, "power_mult": 1.0,
	"bio_capacity": 5.0, "research_speed": 1.0,
	"imp_spread": 0.0, "imp_spread_cd": 10.0,
	"ally_turret_chance": 0.2, "ally_damage": 10.0, "ally_range": 380.0,
	"miner_count": 0.0, "miner_dps": 22.0, "miner_yield": 1.0, "miner_speed": 240.0,
	"wing_count": 0.0, "wing_damage": 10.0, "wing_interval": 0.55, "wing_speed": 760.0, "wing_hp": 60.0, "miner_hp": 80.0, "miner_scan": 0.0, "mother_hp": 1500.0,
	"transit_count": 0.0, "transit_interval": 45.0, "transit_share": 0.35, "transit_hp": 120.0, "transit_speed": 900.0,
}

const STAT_NAMES := {
	"laser_dps": "Moc lasera (DPS)", "laser_range": "Zasięg lasera", "laser_splash": "Promień rozprysku",
	"deposit_damage_mult": "Obrażenia vs złoża", "chain_jumps": "Przeskoki błyskawicy",
	"chain_power": "Moc błyskawicy (% DPS)", "chain_interval": "Odstęp błyskawic (s)", "chain_range": "Zasięg przeskoku",
	"det_chance": "Szansa na detonację", "det_power": "Moc detonacji (% DPS)", "det_radius": "Promień detonacji (kafelki)",
	"fighter_damage": "Obrażenia lasera vs myśliwce", "hull_siphon": "Naprawa kadłuba z kafelka", "salvage": "Szansa na rzadki surowiec",
	"escort_count": "Myśliwce towarzyszące", "escort_power": "Moc myśliwca (% lasera)", "escort_hp": "Kadłub myśliwca (% kadłuba)",
	"max_hull": "Kadłub", "armor": "Pancerz",
	"max_shield": "Tarcza", "shield_regen": "Regeneracja tarczy /s", "hull_regen": "Naprawa kadłuba /s",
	"thrust": "Ciąg", "max_speed": "Prędkość maks.", "turn_rate": "Szybkość obrotu", "brake": "Hamowanie",
	"strafe": "Manewry boczne", "cargo": "Ładownia", "cargo_mult": "Mnożnik ładowni", "yield_mult": "Wydobycie z kafelka",
	"deposit_yield_mult": "Wydobycie ze złóż", "scanner": "Zasięg skanera (kafelki)",
	"teleport": "Teleport nadmiaru",
	"max_fuel": "Paliwo", "fuel_efficiency": "Oszczędność paliwa", "fuel_siphon": "Paliwo z kafelka",
	"drift_boost": "Zryw po drifcie",
	"rocket_unlocked": "Rakiety", "rocket_cooldown": "Przeładowanie rakiet (s)", "rocket_radius": "Promień wybuchu (kafelki)",
	"rocket_damage": "Obrażenia rakiet", "drone_count": "Liczba dronów", "drone_damage": "Obrażenia dronów",
	"drone_interval": "Odstęp strzałów dronów (s)", "gun_unlocked": "Karabiny", "gun_damage": "Obrażenia karabinów",
	"gun_interval": "Odstęp strzałów karabinów (s)", "gun_range": "Zasięg karabinów",
	"armory": "Zbrojownia", "bridge": "Sterownia", "lab": "Laboratorium", "abduct_speed": "Szybkość porywania",
	"rebuild": "Odbudowa", "rebuild_area": "Obszar odbudowy (promień w kafelkach)", "rebuild_speed": "Szybkość odbudowy", "rebuild_range": "Zasięg odbudowy",
	"power_mult": "Produkcja Potęgi Imperium",
	"abduct_range": "Zasięg promienia porywania", "abduct_area": "Obszar porywania (promień w kafelkach)", "abduct_amount": "Istoty z jednego porwania",
	"bio_capacity": "Komory bio (istoty)", "research_speed": "Szybkość badań",
	"imp_spread": "Rozrost Imperium", "imp_spread_cd": "s odnowienia rozrostu",
	"ally_turret_chance": "Szansa na wieżyczkę w mieście", "ally_damage": "Obrażenia wieżyczek Imperium", "ally_range": "Zasięg wieżyczek Imperium",
	"miner_count": "Statki wydobywcze", "miner_dps": "Moc wydobycia statków", "miner_yield": "Surowiec z kafelka (statki)", "miner_speed": "Prędkość statków wydobywczych",
	"wing_count": "Myśliwce Imperium", "wing_damage": "Obrażenia myśliwców Imperium", "wing_interval": "Odstęp strzałów myśliwców (s)", "wing_speed": "Prędkość myśliwców Imperium",
	"wing_hp": "Wytrzymałość myśliwców Imperium", "miner_hp": "Wytrzymałość statków wydobywczych", "miner_scan": "Skaner planetarny floty", "mother_hp": "Kadłub Statku Matki",
	"transit_count": "Statki tranzytowe", "transit_interval": "Odstęp kursów tranzytu (s)", "transit_share": "Część ładowni na kurs",
	"transit_hp": "Wytrzymałość statków tranzytowych", "transit_speed": "Prędkość statków tranzytowych",
}

const PERCENT_STATS := ["ally_turret_chance", "miner_yield", "chain_power", "det_chance", "det_power", "escort_power", "escort_hp", "fighter_damage", "salvage", "rebuild_speed", "power_mult", "cargo_mult", "abduct_speed", "research_speed", "fuel_efficiency", "armor", "yield_mult", "deposit_yield_mult", "deposit_damage_mult", "teleport", "strafe", "transit_share"]

var bank: Dictionary = {}
var cargo: Dictionary = {}
var levels: Dictionary = {}
var stats: Dictionary = {}
var world_seed: int = 0
var sorties: int = 0
var tiles_destroyed: int = 0
var saved_map: Dictionary = {}
var bio_cargo: Dictionary = {}     # istoty w komorach statku (tracone przy zniszczeniu)
var research: Dictionary = {}      # {"id", "progress", "duration"} - aktualne badanie
var mother_sector: int = Sectors.START
var cities_destroyed: int = 0      # zniszczone kafelki miast: im więcej, tym więcej myśliwców
var boss_states: Dictionary = {}   # sektor (tekst) -> "pending" (czeka na walkę) / "beaten"
var metros_done: Dictionary = {}   # sektor (tekst) -> true, gdy metropolia zniszczona w 100%
var in_boss := false
var pause_menu := false              # otwarta pauza (ESC)
const GRID_VERSION := 2               # trwa minigra z bossem (główna gra w pauzie)


func _ready() -> void:
	randomize()
	_migrate_old_save()
	load_settings()
	apply_settings()
	new_game()


# ---------------- Sloty zapisu ----------------

func save_path(n: int = -1) -> String:
	return "user://neon_extraction_save_%d.json" % (slot if n < 0 else n)


## Stary pojedynczy zapis trafia do slotu 1.
func _migrate_old_save() -> void:
	if FileAccess.file_exists(OLD_SAVE_PATH) and not FileAccess.file_exists(save_path(1)):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(OLD_SAVE_PATH), ProjectSettings.globalize_path(save_path(1)))


## Skrócone informacje o slocie (do ekranu wyboru zapisu).
func slot_info(n: int) -> Dictionary:
	var p := save_path(n)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var lv: Dictionary = data.get("levels", {})
	var bought := 0
	for k in lv:
		bought += int(lv[k])
	var b: Dictionary = data.get("bank", {})
	var res := 0
	for k in b:
		if k != "power" and k != "glory":
			res += int(b[k])
	return {
		"sorties": int(data.get("sorties", 0)), "tiles": int(data.get("tiles_destroyed", 0)),
		"upgrades": bought, "resources": res, "power": int(b.get("power", 0)),
		"time": FileAccess.get_modified_time(p),
	}


func delete_slot(n: int) -> void:
	var p := save_path(n)
	for path in [p, p + ".bak", p + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------- Ustawienia ----------------

func load_settings() -> void:
	reset_keys()
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings:
		settings[k] = cf.get_value("settings", k, settings[k])
	for a in KEY_ACTIONS:
		keys[a[0]] = int(cf.get_value("keys", a[0], keys[a[0]]))


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	for k in keys:
		cf.set_value("keys", k, keys[k])
	cf.save(SETTINGS_PATH)


# ---------------- Sterowanie ----------------

func reset_keys() -> void:
	keys = {}
	for a in KEY_ACTIONS:
		keys[a[0]] = a[2]


func key_down(action: String) -> bool:
	return Input.is_physical_key_pressed(keys.get(action, KEY_NONE))


## Czy zdarzenie to świeże wciśnięcie klawisza przypisanego do akcji.
func key_hit(event: InputEvent, action: String) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == keys.get(action, KEY_NONE)


func key_name(action: String) -> String:
	var n := OS.get_keycode_string(keys.get(action, KEY_NONE))
	return String(KEY_NAMES.get(n, n)).to_upper()


## Przypisuje klawisz; akcja, która go miała, dostaje w zamian poprzedni klawisz tej akcji.
func bind_key(action: String, code: int) -> void:
	var old: int = keys.get(action, KEY_NONE)
	for k in keys:
		if k != action and keys[k] == code:
			keys[k] = old
	keys[action] = code
	save_settings()


## Wstawia nazwy klawiszy w tekst: {thrust}, {dock}... oraz {move} = cztery klawisze lotu.
func keys_text(s: String) -> String:
	if not "{" in s:
		return s
	var d := {"move": "%s/%s/%s/%s" % [key_name("thrust"), key_name("left"), key_name("brake"), key_name("right")]}
	for a in KEY_ACTIONS:
		d[a[0]] = key_name(a[0])
	return s.format(d)


## Jakość obrazu dla słabszych komputerów (i ekranów 4K / Retina):
## WYSOKA - wygładzanie 4x, ŚREDNIA - wygładzanie 2x,
## NISKA - bez wygładzania i obraz liczony w rozdzielczości bazowej gry (1600x900), potem skalowany na ekran.
const QUALITY_LEVELS := ["WYSOKA", "ŚREDNIA", "NISKA"]


func quality_name() -> String:
	return QUALITY_LEVELS[clampi(int(settings.get("quality", 0)), 0, QUALITY_LEVELS.size() - 1)]


func apply_quality() -> void:
	var q := clampi(int(settings.get("quality", 0)), 0, QUALITY_LEVELS.size() - 1)
	var root := get_tree().root
	root.msaa_2d = [Viewport.MSAA_4X, Viewport.MSAA_2X, Viewport.MSAA_DISABLED][q]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if q == 2 else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS


func apply_settings() -> void:
	apply_quality()
	if DisplayServer.get_name() == "headless":
		return
	var res: Vector2i = RESOLUTIONS[clampi(int(settings["resolution"]), 0, RESOLUTIONS.size() - 1)]
	if settings["fullscreen"]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(res)
		var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		DisplayServer.window_set_position(screen.position + (screen.size - res) / 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings["vsync"] else DisplayServer.VSYNC_DISABLED)
	if has_node("/root/Audio"):
		get_node("/root/Audio").apply_volumes()


var tutorial_step := 0   # postęp samouczka (999 = ukończony / pominięty)
var boss_tutorial := false   # samouczek pierwszej walki z bossem już pokazany
var quests: Dictionary = {}      # rozkaz -> "active" / "ready" (nagroda do odebrania) / "done"
var collected: Dictionary = {}   # surowiec -> ile łącznie rozładowano w Statku Matce
var quests_new := 0              # zmiany w rozkazach, których gracz jeszcze nie widział
var empire_seen := false         # gracz otworzył już zakładkę Imperium
const MINER_DEFAULTS := ["wood", "stone", "biomass", "sand", "water", "copper"]
var miner_res: Array = MINER_DEFAULTS.duplicate()   # surowiec przydzielony każdemu statkowi wydobywczemu

func new_game() -> void:
	bank = {}
	cargo = {}
	levels = {"core": 1}
	world_seed = randi() % 1000000
	sorties = 0
	tiles_destroyed = 0
	saved_map = {}
	bio_cargo = {}
	research = {}
	mother_sector = Sectors.START
	cities_destroyed = 0
	boss_states = {}
	metros_done = {}
	tutorial_step = 0
	boss_tutorial = false
	quests = {}
	collected = {}
	quests_new = 0
	empire_seen = false
	miner_res = MINER_DEFAULTS.duplicate()
	recalc_stats()
	refresh_quests()


func stat(key: String) -> float:
	return float(stats.get(key, 0.0))


func recalc_stats() -> void:
	# odblokowanie może od razu dać poziom innego węzła (np. myśliwiec: liczba myśliwców startuje od 1/2)
	for g in Upgrades.all_items():
		if g.has("grants") and get_level(g["id"]) > 0:
			for gid in g["grants"]:
				if get_level(gid) < int(g["grants"][gid]):
					levels[gid] = int(g["grants"][gid])
	stats = BASE_STATS.duplicate()
	for u in Upgrades.all_items():
		var lv: int = get_level(u["id"])
		if lv <= 0:
			continue
		var m := mastery_mult(u, lv)
		for k in u["effects"]:
			var add := float(u["effects"][k]) * lv * m
			# drony, przeskoki czy istoty liczy się w sztukach: bonus Mistrzostwa zaokrąglamy
			if k in INT_STATS:
				add = round(add)
			stats[k] = float(stats.get(k, 0.0)) + add
	stats_changed.emit()


## Mistrzostwo: węzeł wykupiony do końca (z kilku poziomów) daje swój efekt x1.25.
func mastery_mult(u: Dictionary, lv: int) -> float:
	var mx := int(u["max"])
	return 1.0 + Upgrades.MASTERY_BONUS if mx > 1 and lv >= mx and not u.get("no_mastery", false) else 1.0


## O ile wzrośnie statystyka po kupnie kolejnego poziomu (z Mistrzostwem przy ostatnim).
func gain(u: Dictionary, key: String) -> float:
	var lv := get_level(u["id"])
	var e := float(u["effects"].get(key, 0.0))
	return e * (lv + 1) * mastery_mult(u, lv + 1) - e * lv * mastery_mult(u, lv)


# ---------------- Ładownia ----------------

func cargo_total() -> int:
	var t := 0
	for k in cargo:
		t += int(cargo[k])
	return t


## Pojemność ładowni: suma ulepszeń x mnożnik (Mikrokompresja).
func cargo_cap() -> int:
	return int(stat("cargo") * stat("cargo_mult"))


func cargo_free() -> int:
	return max(0, cargo_cap() - cargo_total())


## Dodaje surowiec do ładowni. Zwraca ile faktycznie przyjęto (do ładowni + teleport).
func add_cargo(res: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var accepted: int = min(amount, cargo_free())
	if accepted > 0:
		cargo[res] = int(cargo.get(res, 0)) + accepted
		if res == "neonite":
			Achievements.unlock("neonite")
	var overflow := amount - accepted
	var tele := 0
	if overflow > 0 and stat("teleport") > 0.0:
		tele = int(floor(overflow * stat("teleport") + randf()))
		if tele > 0:
			bank[res] = int(bank.get(res, 0)) + tele
			bank_changed.emit()
	cargo_changed.emit()
	return accepted + tele


# ---------------- Komory bio ----------------

func bio_total() -> int:
	var t := 0
	for k in bio_cargo:
		t += int(bio_cargo[k])
	return t


func bio_free() -> int:
	return max(0, int(stat("bio_capacity")) - bio_total())


func add_bio(kind: String, amount: int) -> int:
	var got: int = min(amount, bio_free())
	if got > 0:
		bio_cargo[kind] = int(bio_cargo.get(kind, 0)) + got
		cargo_changed.emit()
	return got


# ---------------- Badania (czas rzeczywisty) ----------------

func research_duration(u: Dictionary) -> float:
	var lv := get_level(u["id"])
	return float(u.get("time", 60.0)) * pow(1.35, lv)


func research_time_left() -> float:
	if research.is_empty():
		return 0.0
	return (float(research["duration"]) - float(research["progress"])) / maxf(0.1, stat("research_speed"))


func start_research(u: Dictionary) -> bool:
	if not research.is_empty() or not can_buy(u):
		return false
	var cost := cost_of(u)
	for k in cost:
		bank[k] = int(bank.get(k, 0)) - int(cost[k])
	research = {"id": u["id"], "progress": 0.0, "duration": research_duration(u)}
	bank_changed.emit()
	return true


func _process(delta: float) -> void:
	if research.is_empty():
		return
	research["progress"] = float(research["progress"]) + delta * stat("research_speed")
	if float(research["progress"]) >= float(research["duration"]):
		var u: Dictionary = Upgrades.by_id(String(research["id"]))
		research = {}
		if not u.is_empty():
			levels[u["id"]] = get_level(u["id"]) + 1
			recalc_stats()
			research_done.emit(u)


func unload_cargo() -> Dictionary:
	var unloaded := cargo.duplicate()
	for k in cargo:
		bank[k] = int(bank.get(k, 0)) + int(cargo[k])
	for k in bio_cargo:
		bank[k] = int(bank.get(k, 0)) + int(bio_cargo[k])
		unloaded[k] = int(unloaded.get(k, 0)) + int(bio_cargo[k])
	bio_cargo = {}
	cargo = {}
	for k in unloaded:
		collected[k] = int(collected.get(k, 0)) + int(unloaded[k])
	cargo_changed.emit()
	bank_changed.emit()
	refresh_quests()
	return unloaded


func lose_cargo() -> void:
	cargo = {}
	bio_cargo = {}
	cargo_changed.emit()


# ---------------- Rozkazy ----------------

## Odblokowuje nowe rozkazy i zalicza wykonane; powtarza, bo jeden rozkaz może odsłonić następny.
func refresh_quests() -> void:
	var changed := true
	while changed:
		changed = false
		for q in Quests.all():
			var st: String = quests.get(q["id"], "")
			if st == "" and _quest_unlocked(q):
				quests[q["id"]] = "active"
				quests_new += 1
				changed = true
			elif st == "active" and _quest_met(q):
				_complete_quest(q)
				changed = true


func _quest_unlocked(q: Dictionary) -> bool:
	if q.has("after"):
		return quests.get(q["after"], "") in ["ready", "done"]
	if q["kind"] == "collect":
		return int(collected.get(q["res"], 0)) > 0
	return true


func _quest_met(q: Dictionary) -> bool:
	match q["kind"]:
		"metro":
			return metros_done.has(str(q["sector"]))
		"collect":
			return int(collected.get(q["res"], 0)) >= int(q["target"])
	return false


## Rozkaz wykonany: nagroda czeka na odebranie w panelu Rozkazów.
func _complete_quest(q: Dictionary) -> void:
	quests[q["id"]] = "ready"
	quests_new += 1
	quest_completed.emit(q)


## Odbiór nagrody; zwraca liczbę Punktów Lojalności (0, gdy nie było czego odebrać).
func claim_quest(id: String) -> int:
	if quests.get(id, "") != "ready":
		return 0
	for q in Quests.all():
		if q["id"] == id:
			quests[id] = "done"
			bank["loyalty"] = int(bank.get("loyalty", 0)) + int(q["reward"])
			bank_changed.emit()
			return int(q["reward"])
	return 0


## Zdarzenie z gry (np. udany powrót do Statku Matki) zalicza rozkazy, które na nie czekają.
func quest_event(event_name: String) -> void:
	for q in Quests.all():
		if q["kind"] == "event" and q["event"] == event_name and quests.get(q["id"], "") == "active":
			_complete_quest(q)
	refresh_quests()


## Postęp rozkazu: [ile jest, ile trzeba].
func quest_progress(q: Dictionary) -> Array:
	match q["kind"]:
		"collect":
			return [mini(int(collected.get(q["res"], 0)), int(q["target"])), int(q["target"])]
		"metro":
			var key := str(q["sector"])
			return [1 if metros_done.has(key) else 0, 1]
	return [0, 1]


## Zakładka Imperium: po zniszczeniu Nowego Jorku i pokonaniu jego bossa.
func empire_unlocked() -> bool:
	return metros_done.has(str(Sectors.START)) and boss_state(Sectors.START) == "beaten"


func boss_state(s: int) -> String:
	return String(boss_states.get(str(s), ""))


## Klucze sektorów ze starej siatki 3x2 na nową 3x3 (inne klucze, np. "washington", bez zmian).
func _remap_sectors(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var key := String(k)
		if key.is_valid_int() and Sectors.OLD_SECTOR.has(int(key)):
			out[str(Sectors.OLD_SECTOR[int(key)])] = d[k]
		elif not key.is_valid_int():
			out[key] = d[k]
	return out


## Ile metropolii zostało zrównanych z ziemią (i ile ich jest).
func metros_progress() -> Vector2i:
	var done := 0
	var total := 0
	for s in Sectors.LIST.size():
		if Sectors.has_city(s):
			total += 1
			if metros_done.has(str(s)):
				done += 1
	return Vector2i(done, total)


## Dystrykt Federalny otwiera się po zniszczeniu wszystkich metropolii.
func federal_unlocked() -> bool:
	var p := metros_progress()
	return p.x >= p.y


## Czy można wlecieć do sektora i przenieść tam Matkę.
func sector_open(s: int) -> bool:
	if Sectors.is_void(s):
		return false
	if bool(Sectors.LIST[s].get("federal", false)):
		return federal_unlocked()
	return true


func add_glory(n: int) -> void:
	bank["glory"] = int(bank.get("glory", 0)) + n
	bank_changed.emit()


# ---------------- Sterownia ----------------

func move_cost(to: int) -> Dictionary:
	var n := Sectors.steps(mother_sector, to)
	var out := {}
	for k in MOVE_COST:
		out[k] = int(MOVE_COST[k]) * n
	return out


## Płaci za przenosiny Statku Matki. Zwraca false, gdy nie stać.
func pay_move(to: int) -> bool:
	if to == mother_sector:
		return false
	var cost := move_cost(to)
	if not can_afford(cost):
		return false
	for k in cost:
		bank[k] = int(bank.get(k, 0)) - int(cost[k])
	mother_sector = to
	bank_changed.emit()
	return true


# ---------------- Ulepszenia ----------------

func get_level(id: String) -> int:
	return int(levels.get(id, 0))


func requires_met(u: Dictionary) -> bool:
	if not u.has("requires"):
		return true
	var req = u["requires"]
	if req is Array:
		for r in req:
			if get_level(r) <= 0:
				return false
		return true
	return get_level(req) > 0


func is_reachable(u: Dictionary) -> bool:
	if u["id"] == "core" or u.get("unlock", false):
		return true
	if not requires_met(u):
		return false
	# węzeł siatki: musi być kupiony jego rodzic w drzewku
	if not u.has("pos"):
		return true
	var parent := Upgrades.parent_of(u["id"])
	return parent != "" and get_level(parent) > 0


## Siatka v2: część węzłów rozbito na dwa. Nadmiarowe poziomy przechodzą do nowego węzła,
## a za kupiony dawniej "Hamulec" (hamowanie + manewry) gracz dostaje też "Manewry".
func _migrate_grid() -> void:
	for pair in [["laser_dmg", "laser_resonator"], ["cargo", "cargo_b"], ["hull", "hull_plating"], ["fuel_tank", "fuel_tank2"]]:
		var u: Dictionary = Upgrades.by_id(pair[0])
		var extra := get_level(pair[0]) - int(u["max"])
		if extra > 0:
			levels[pair[0]] = int(u["max"])
			var n: Dictionary = Upgrades.by_id(pair[1])
			levels[pair[1]] = mini(get_level(pair[1]) + extra, int(n["max"]))
	if get_level("brake") > 0:
		levels["maneuver"] = maxi(get_level("maneuver"), get_level("brake"))
	# poziomy ponad nowe maksimum (np. Syfon) zostają przycięte
	for id in levels.keys():
		var u: Dictionary = Upgrades.by_id(id)
		if not u.is_empty():
			levels[id] = mini(int(levels[id]), int(u["max"]))


func cost_of(u: Dictionary) -> Dictionary:
	var lv := get_level(u["id"])
	var out := {}
	if u.has("time"):
		for k in u["cost"]:
			out[k] = int(ceil(float(u["cost"][k]) * pow(Upgrades.COST_GROWTH, lv)))
		return out
	# zwykłe surowce: pierścień x wzrost zależny od długości ścieżki; rzadkie i Potęga rosną wolniej
	var ring := Upgrades.ring_mult(u)
	var g := Upgrades.growth(int(u["max"]))
	for k in u["cost"]:
		var base := float(u["cost"][k])
		if k in Upgrades.RARE:
			out[k] = int(ceil(base * pow(Upgrades.RARE_GROWTH, lv)))
		elif k in ["power", "loyalty", "glory"]:
			out[k] = int(ceil(base * pow(Upgrades.POWER_GROWTH, lv)))
		else:
			out[k] = int(ceil(base * ring * pow(g, lv)))
	return out


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if int(bank.get(k, 0)) < int(cost[k]):
			return false
	return true


func can_buy(u: Dictionary) -> bool:
	return get_level(u["id"]) < int(u["max"]) and is_reachable(u) and can_afford(cost_of(u))


## Płaci z magazynu. Zwraca false (i nic nie zabiera), gdy nie stać.
func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		bank[k] = int(bank.get(k, 0)) - int(cost[k])
	bank_changed.emit()
	return true


func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), RES_NAMES[k]])
	return ", ".join(parts)


func buy(u: Dictionary) -> bool:
	if not can_buy(u):
		return false
	var cost := cost_of(u)
	for k in cost:
		bank[k] = int(bank.get(k, 0)) - int(cost[k])
	levels[u["id"]] = get_level(u["id"]) + 1
	recalc_stats()
	bank_changed.emit()
	return true


func format_stat(key: String, value: float, signed := false) -> String:
	var s := ""
	if key in PERCENT_STATS:
		s = "%d%%" % int(round(value * 100.0))
	elif absf(value - round(value)) < 0.01:
		s = str(int(round(value)))
	else:
		s = "%.1f" % value
	if signed and value > 0:
		s = "+" + s
	return s


# ---------------- Zapis ----------------

func save_game(map_data: Dictionary) -> void:
	saved_map = map_data
	var data := {
		"version": 2, "sectors_v": 3, "seed": world_seed, "mother_sector": mother_sector, "cities_destroyed": cities_destroyed, "boss_states": boss_states, "metros_done": metros_done, "bank": bank, "levels": levels,
		"sorties": sorties, "tiles_destroyed": tiles_destroyed, "map": map_data,
		"research": research, "tutorial": tutorial_step, "boss_tutorial": boss_tutorial, "grid": GRID_VERSION,
		"quests": quests, "collected": collected, "quests_new": quests_new, "empire_seen": empire_seen, "miner_res": miner_res,
	}
	# najpierw plik tymczasowy: awaria w trakcie zapisu nie może zniszczyć postępu
	var path := save_path()
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Nie udało się zapisać gry: %s" % tmp)
		return
	f.store_string(JSON.stringify(data))
	var failed := f.get_error() != OK
	f.close()
	if failed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		push_warning("Nie udało się zapisać gry: %s" % tmp)
		return
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(abs_path, abs_path + ".bak")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_path)


## Treść zapisu; gdy główny plik jest uszkodzony, sięga po poprzednią kopię.
func _read_save() -> Dictionary:
	for p in [save_path(), save_path() + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
		push_warning("Uszkodzony zapis: %s" % p)
	return {}


func load_game() -> bool:
	var data := _read_save()
	if data.is_empty():
		return false
	# zapis sprzed mapy USA: ulepszenia i magazyn zostają, stara mapa nie pasuje do nowego świata
	if int(data.get("version", 1)) < 2:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path()), ProjectSettings.globalize_path(save_path() + ".v1_backup"))
		data["map"] = {}
	mother_sector = clampi(int(data.get("mother_sector", Sectors.START)), 0, Sectors.LIST.size() - 1)
	cities_destroyed = int(data.get("cities_destroyed", 0))
	boss_states = data.get("boss_states", {})
	metros_done = data.get("metros_done", {})
	# zapis sprzed mapy 3x3: numery sektorów z siatki 3x2 (Miami było piątką)
	if int(data.get("sectors_v", 1)) < 3:
		mother_sector = int(Sectors.OLD_SECTOR.get(int(data.get("mother_sector", Sectors.START)), Sectors.START))
		boss_states = _remap_sectors(boss_states)
		metros_done = _remap_sectors(metros_done)
	world_seed = int(data.get("seed", world_seed))
	bank = {}
	var b: Dictionary = data.get("bank", {})
	for k in b:
		bank[k] = int(b[k])
	levels = {}
	var l: Dictionary = data.get("levels", {})
	for k in l:
		levels[k] = int(l[k])
	levels["core"] = 1
	sorties = int(data.get("sorties", 0))
	tiles_destroyed = int(data.get("tiles_destroyed", 0))
	saved_map = data.get("map", {})
	research = data.get("research", {})
	# badanie usunięte z gry (np. koloniści) nie może blokować laboratorium
	if not research.is_empty() and Upgrades.by_id(String(research.get("id", ""))).is_empty():
		research = {}
	# starsze zapisy (sprzed samouczka) - samouczek uznajemy za ukończony
	tutorial_step = int(data.get("tutorial", 999))
	boss_tutorial = bool(data.get("boss_tutorial", false))
	quests = {}
	var qd: Dictionary = data.get("quests", {})
	for k in qd:
		quests[k] = String(qd[k])
	collected = {}
	var cd: Dictionary = data.get("collected", {})
	for k in cd:
		collected[k] = int(cd[k])
	quests_new = int(data.get("quests_new", 0))
	empire_seen = bool(data.get("empire_seen", false))
	miner_res = MINER_DEFAULTS.duplicate()
	var mr: Array = data.get("miner_res", [])
	for k in mini(mr.size(), miner_res.size()):
		miner_res[k] = String(mr[k])
	cargo = {}
	bio_cargo = {}
	# migracja starszych zapisów: kupione bronie => zbrojownia odblokowana
	for id in ["rockets", "drones", "guns"]:
		if get_level(id) > 0:
			levels["armory"] = 1
	if int(data.get("grid", 1)) < GRID_VERSION:
		_migrate_grid()
	recalc_stats()
	refresh_quests()
	recalc_stats()
	return true


func delete_save() -> void:
	if FileAccess.file_exists(save_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path()))
	new_game()
