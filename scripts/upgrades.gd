extends RefCounted
## Definicja siatki ulepszeń statku.
## Każdy węzeł leży na pozycji w siatce (pos). Węzeł można kupić, gdy
## jego rodzic (TREE) ma już co najmniej 1 poziom. Jak w drzewkach z Path of Exile, Grim Dawn czy Nova Drift:
## każdy węzeł ma jednego rodzica, przewody biegną tylko wzdłuż gałęzi, a sąsiednie gałęzie się nie łączą.
## effects: przyrost statystyki NA POZIOM. cost: koszt poziomu 1 przed mnożnikiem pierścienia
## (zob. RING_MULT i growth). Badania w laboratorium drożeją o COST_GROWTH na poziom.

const COST_GROWTH := 1.6

const CAT_COLORS := {
	"core": Color(0.95, 0.95, 1.0),
	"laser": Color(1.0, 0.4, 0.8),
	"defense": Color(0.4, 0.8, 1.0),
	"engine": Color(1.0, 0.85, 0.35),
	"mining": Color(1.0, 0.6, 0.25),
	"weapons": Color(1.0, 0.4, 0.3),
	"lab": Color(0.55, 1.0, 0.45),
	"empire": Color(1.0, 0.78, 0.3),
}

const CAT_NAMES := {
	"core": "RDZEŃ",
	"laser": "LASER",
	"defense": "OBRONA",
	"engine": "NAPĘD",
	"mining": "WYDOBYCIE",
	"weapons": "ZBROJOWNIA",
	"lab": "LABORATORIUM",
	"empire": "IMPERIUM",
}

## Układ siatki: rdzeń w środku, LASER w górę, OBRONA w lewo, NAPĘD w dół (paliwo w dół i w prawo),
## WYDOBYCIE w prawo, LABORATORIUM w prawo i w górę, IMPERIUM w prawo i w dół. Sąsiedzi pasują do siebie tematem.
const LIST := [
	{"id": "core", "label": "Rdzeń", "name": "Rdzeń statku", "icon": "◆", "cat": "core", "pos": Vector2i(0, 0), "max": 1,
		"desc": "Serce Twojego statku zwiadowczego. Wszystkie ulepszenia wyrastają stąd.",
		"effects": {}, "cost": {}},

	# --- LASER (góra): moc w kolumnie środkowej, rozprysk i błyskawice w lewo, złoża i zbrojownia w prawo ---
	{"id": "laser_dmg", "label": "Moc lasera", "name": "Ogniskowanie lasera", "cat": "laser", "pos": Vector2i(0, -1), "max": 4,
		"desc": "Węższa wiązka = więcej energii na kafelek.",
		"effects": {"laser_dps": 8.0}, "cost": {"wood": 10, "biomass": 10}},
	{"id": "laser_range", "label": "Zasięg", "name": "Soczewka dalekiego zasięgu", "cat": "laser", "pos": Vector2i(0, -2), "max": 4,
		"desc": "Wydobywaj z bezpiecznej odległości.",
		"effects": {"laser_range": 60.0}, "cost": {"stone": 25, "sand": 15}},
	{"id": "laser_splash", "label": "Rozprysk", "name": "Rozpraszacz wiązki", "cat": "laser", "pos": Vector2i(-1, -2), "max": 3,
		"desc": "Wiązka rani też kafelki w okręgu wokół celu (50% mocy). Każdy poziom to +1 kafelek promienia.",
		"effects": {"laser_splash": 1.0}, "cost": {"metal": 15, "copper": 6}},
	{"id": "laser_drill", "label": "Wiertło", "name": "Wiertło plazmowe", "cat": "laser", "pos": Vector2i(1, -2), "max": 3,
		"desc": "Większe obrażenia zadawane złożom pod powierzchnią.",
		"effects": {"deposit_damage_mult": 0.5}, "cost": {"iron": 10, "scrap": 20}},
	{"id": "laser_resonator", "label": "Rezonator", "name": "Rezonator wiązki", "cat": "laser", "pos": Vector2i(0, -3), "max": 3,
		"desc": "Wiązka odbija się w komorze rezonansowej i wraca silniejsza.",
		"effects": {"laser_dps": 12.0}, "cost": {"metal": 15, "copper": 8}},
	{"id": "laser_overdrive", "label": "Przeciążenie", "name": "Przeciążenie fotonowe", "cat": "laser", "pos": Vector2i(0, -4), "max": 3,
		"desc": "Zakazana technologia Imperium. Laser pali wszystko.",
		"effects": {"laser_dps": 25.0}, "cost": {"gold": 5, "neonite": 2, "electronics": 4}},
	{"id": "armory", "label": "Zbrojownia", "name": "Zbrojownia", "cat": "weapons", "pos": Vector2i(1, -3), "max": 1,
		"desc": "Otwiera zakładkę Zbrojownia: rakiety, drony i karabiny.",
		"effects": {"armory": 1.0}, "cost": {"metal": 15, "scrap": 20}},
	# --- ŁAŃCUCH BŁYSKAWIC (dalsze węzły wymagają odblokowania) ---
	{"id": "chain", "label": "Błyskawica", "name": "Łańcuch błyskawic", "cat": "laser", "pos": Vector2i(-1, -3), "max": 1,
		"desc": "Co chwilę z celu lasera wyskakuje błyskawica i przeskakuje między celami: myśliwce, wieżyczki, kafelki. Każdy przeskok słabnie o 15%.",
		"effects": {"chain_jumps": 3.0}, "cost": {"electronics": 6, "copper": 10, "scrap": 20}},
	{"id": "chain_jumps", "label": "Przeskoki", "name": "Przewodnik plazmowy", "cat": "laser", "pos": Vector2i(-1, -4), "max": 5, "requires": "chain",
		"desc": "Błyskawica przeskakuje na więcej celów.",
		"effects": {"chain_jumps": 1.0}, "cost": {"electronics": 4, "copper": 12}},
	{"id": "chain_power", "label": "Moc wyład.", "name": "Kondensator wyładowań", "cat": "laser", "pos": Vector2i(-2, -4), "max": 4, "requires": "chain",
		"desc": "Błyskawica zadaje większy procent mocy lasera.",
		"effects": {"chain_power": 0.25}, "cost": {"metal": 20, "iron": 8}},
	{"id": "chain_rate", "label": "Częstość", "name": "Szybkie rozładowanie", "cat": "laser", "pos": Vector2i(-2, -5), "max": 4, "requires": "chain",
		"desc": "Błyskawice pojawiają się częściej.",
		"effects": {"chain_interval": -0.1}, "cost": {"gold": 2, "electronics": 4}},
	{"id": "chain_range", "label": "Zasięg skoku", "name": "Zjonizowany szlak", "cat": "laser", "pos": Vector2i(-1, -5), "max": 3, "requires": "chain",
		"desc": "Błyskawica sięga dalej przy każdym przeskoku.",
		"effects": {"chain_range": 45.0}, "cost": {"sand": 30, "copper": 8}},
	# --- DETONACJA (reakcja łańcuchowa: kafelek rozbity laserem może wybuchnąć i rozbić sąsiadów) ---
	{"id": "detonate", "label": "Detonacja", "name": "Destabilizator materii", "cat": "laser", "pos": Vector2i(1, -4), "max": 1,
		"desc": "Kafelek rozbity laserem (także rozpryskiem i błyskawicą) może się zdestabilizować i po chwili wybuchnąć, raniąc kafelki i myśliwce wokół. Kafelki rozbite wybuchem też mogą wybuchnąć - reakcja łańcuchowa!",
		"effects": {"det_chance": 0.12}, "cost": {"electronics": 6, "iron": 8, "scrap": 15}},
	{"id": "det_chance", "label": "Niestabilność", "name": "Katalizator rozpadu", "cat": "laser", "pos": Vector2i(2, -4), "max": 4, "requires": "detonate",
		"desc": "Większa szansa, że rozbity kafelek wybuchnie.",
		"effects": {"det_chance": 0.05}, "cost": {"electronics": 3, "copper": 6}},
	{"id": "det_power", "label": "Moc wybuchu", "name": "Ładunek antymaterii", "cat": "laser", "pos": Vector2i(1, -5), "max": 4, "requires": "detonate",
		"desc": "Wybuch zadaje większy procent mocy lasera.",
		"effects": {"det_power": 0.3}, "cost": {"metal": 12, "iron": 5}},
	{"id": "det_radius", "label": "Fala uderz.", "name": "Fala uderzeniowa", "cat": "laser", "pos": Vector2i(2, -5), "max": 3, "requires": "detonate",
		"desc": "Większy promień wybuchu.",
		"effects": {"det_radius": 0.5}, "cost": {"gold": 2, "sand": 10}},

	# --- OBRONA (lewo): tarcze w rzędzie wyżej, kadłub w rzędzie rdzenia, pancerz niżej ---
	{"id": "shield", "label": "Tarcza", "name": "Generator tarczy", "cat": "defense", "pos": Vector2i(-1, -1), "max": 5,
		"desc": "Odnawialna tarcza energetyczna pochłaniająca pociski.",
		"effects": {"max_shield": 35.0, "shield_regen": 2.0}, "cost": {"water": 25, "scrap": 10}},
	{"id": "shield_regen", "label": "Regen. tarczy", "name": "Kondensator tarczy", "cat": "defense", "pos": Vector2i(-2, -1), "max": 4,
		"desc": "Szybsze odnawianie tarczy.",
		"effects": {"shield_regen": 4.0}, "cost": {"saltwater": 30, "copper": 8}},
	{"id": "shield_phase", "label": "Tarcza fazowa", "name": "Tarcza fazowa", "cat": "defense", "pos": Vector2i(-3, -1), "max": 2,
		"desc": "Potężne wzmocnienie pojemności tarczy.",
		"effects": {"max_shield": 90.0}, "cost": {"uranium": 3, "neonite": 2}},
	{"id": "hull", "label": "Kadłub", "name": "Wzmocniony kadłub", "cat": "defense", "pos": Vector2i(-1, 0), "max": 4,
		"desc": "Więcej punktów wytrzymałości kadłuba.",
		"effects": {"max_hull": 40.0}, "cost": {"wood": 12, "scrap": 6}},
	{"id": "hull_plating", "label": "Nanowłókna", "name": "Kadłub z nanowłókien", "cat": "defense", "pos": Vector2i(-2, 0), "max": 3,
		"desc": "Lekki, a znacznie mocniejszy kadłub.",
		"effects": {"max_hull": 70.0}, "cost": {"metal": 12, "scrap": 15}},
	{"id": "repair", "label": "Nanoboty", "name": "Nanoboty naprawcze", "cat": "defense", "pos": Vector2i(-3, 0), "max": 3,
		"desc": "Kadłub powoli naprawia się w locie.",
		"effects": {"hull_regen": 1.5}, "cost": {"electronics": 3, "biomass": 30}},
	{"id": "armor", "label": "Pancerz", "name": "Pancerz ablacyjny", "cat": "defense", "pos": Vector2i(-1, 1), "max": 4,
		"desc": "Redukuje obrażenia otrzymywane przez kadłub.",
		"effects": {"armor": 0.08}, "cost": {"metal": 12, "iron": 6}},

	# --- NAPĘD (dół): ciąg i prędkość w kolumnie, sterowność w lewo, hamowanie i drift w prawo ---
	{"id": "thrust", "label": "Ciąg", "name": "Silniki jonowe", "cat": "engine", "pos": Vector2i(0, 1), "max": 5,
		"desc": "Mocniejszy ciąg = szybsze przyspieszanie.",
		"effects": {"thrust": 150.0}, "cost": {"biomass": 12, "wood": 6}},
	{"id": "max_speed", "label": "Prędkość", "name": "Optymalizacja dysz", "cat": "engine", "pos": Vector2i(0, 2), "max": 4,
		"desc": "Wyższa prędkość maksymalna.",
		"effects": {"max_speed": 70.0}, "cost": {"metal": 10, "saltwater": 20}},
	{"id": "warp", "label": "Warp", "name": "Napęd warp", "cat": "engine", "pos": Vector2i(0, 3), "max": 2,
		"desc": "Eksperymentalny napęd. Ogromna prędkość.",
		"effects": {"max_speed": 140.0, "thrust": 250.0}, "cost": {"uranium": 4, "gold": 3}},
	{"id": "bridge", "label": "Sterownia", "name": "Sterownia", "cat": "engine", "pos": Vector2i(0, 4), "max": 1,
		"desc": "Otwiera zakładkę Sterownia: przenoszenie Statku Matki między sektorami USA (to bardzo drogie).",
		"effects": {"bridge": 1.0}, "cost": {"metal": 60, "electronics": 12, "gold": 4, "iron": 15}},
	{"id": "turn", "label": "Obrót", "name": "Stabilizatory żyroskopowe", "cat": "engine", "pos": Vector2i(-1, 2), "max": 3,
		"desc": "Szybsze obracanie statku.",
		"effects": {"turn_rate": 2.0}, "cost": {"biomass": 20, "sand": 15}},
	{"id": "maneuver", "label": "Manewry", "name": "Silniki manewrowe", "cat": "engine", "pos": Vector2i(-1, 3), "max": 3,
		"desc": "Mocniejszy lot w bok ({left}/{right}).",
		"effects": {"strafe": 0.15}, "cost": {"copper": 6, "sand": 15}},
	{"id": "brake", "label": "Hamulec", "name": "Kompensator dryfu", "cat": "engine", "pos": Vector2i(1, 2), "max": 3,
		"desc": "Mocniejsze hamowanie ({brake}).",
		"effects": {"brake": 1.5}, "cost": {"copper": 6, "scrap": 15}},
	{"id": "drift_boost", "label": "Turbo drift", "name": "Turbo drift", "cat": "engine", "pos": Vector2i(1, 3), "max": 3,
		"desc": "Mocniejszy zryw po puszczeniu driftu ({drift}).",
		"effects": {"drift_boost": 90.0}, "cost": {"sand": 15, "scrap": 10}},
	# --- PALIWO (dół, w prawo) ---
	{"id": "fuel_tank", "label": "Zbiornik", "name": "Powiększony zbiornik", "cat": "engine", "pos": Vector2i(1, 1), "max": 4,
		"desc": "Więcej paliwa = dłuższe wyprawy.",
		"effects": {"max_fuel": 25.0}, "cost": {"biomass": 10, "wood": 10}},
	{"id": "fuel_tank2", "label": "Zbiornik pom.", "name": "Zbiornik pomocniczy", "cat": "engine", "pos": Vector2i(2, 1), "max": 3,
		"desc": "Dodatkowe zbiorniki pod kadłubem.",
		"effects": {"max_fuel": 40.0}, "cost": {"metal": 10, "water": 20}},
	{"id": "fuel_eff", "label": "Ekonomizer", "name": "Ekonomizer reaktora", "cat": "engine", "pos": Vector2i(2, 2), "max": 6,
		"desc": "Wszystkie systemy spalają mniej paliwa.",
		"effects": {"fuel_efficiency": 0.1}, "cost": {"metal": 8, "copper": 5}},
	{"id": "fuel_siphon", "label": "Syfon", "name": "Syfon energetyczny", "cat": "engine", "pos": Vector2i(2, 3), "max": 3,
		"desc": "Każdy zniszczony kafelek uzupełnia odrobinę paliwa.",
		"effects": {"fuel_siphon": 0.15}, "cost": {"water": 20, "scrap": 15}},

	# --- WYDOBYCIE (prawo): pojemność w rzędzie rdzenia, wydajność i złoża wyżej ---
	{"id": "cargo", "label": "Ładownia", "name": "Rozszerzona ładownia", "cat": "mining", "pos": Vector2i(1, 0), "max": 5,
		"desc": "Więcej miejsca na surowce w jednym locie.",
		"effects": {"cargo": 40.0}, "cost": {"biomass": 15, "wood": 8}},
	{"id": "cargo_b", "label": "Ładownia mod.", "name": "Ładownia modułowa", "cat": "mining", "pos": Vector2i(2, 0), "max": 5,
		"desc": "Dokręcane moduły ładowni.",
		"effects": {"cargo": 60.0}, "cost": {"stone": 20, "wood": 15}},
	{"id": "cargo_pocket", "label": "Kieszenie", "name": "Kieszenie próżniowe", "cat": "mining", "pos": Vector2i(3, 0), "max": 6,
		"desc": "Dodatkowe schowki na surowce.",
		"effects": {"cargo": 60.0}, "cost": {"wood": 30, "stone": 20}},
	{"id": "cargo_dim", "label": "Wymiarowa", "name": "Ładownia wymiarowa", "cat": "mining", "pos": Vector2i(5, 0), "max": 3,
		"desc": "Kieszeń w innym wymiarze. Gigantyczna pojemność.",
		"effects": {"cargo": 300.0}, "cost": {"neonite": 2, "uranium": 2, "gold": 4}},
	{"id": "cargo_hull", "label": "Ładownia kadł.", "name": "Ładownia kadłubowa", "cat": "mining", "pos": Vector2i(6, 0), "max": 5,
		"desc": "Cały kadłub zamieniony w przestrzeń ładunkową.",
		"effects": {"cargo": 220.0}, "cost": {"scrap": 60, "iron": 20}},
	{"id": "cargo_lattice", "label": "Krata ładunkowa", "name": "Krystaliczna krata ładunkowa", "cat": "mining", "pos": Vector2i(7, 0), "max": 5,
		"desc": "Surowce układają się w krystaliczną kratę - procentowo więcej miejsca w ładowni.",
		"effects": {"cargo_mult": 0.15}, "cost": {"metal": 40, "gold": 4}},
	{"id": "cargo_sing", "label": "Osobliwość", "name": "Osobliwość ładunkowa", "cat": "mining", "pos": Vector2i(8, 0), "max": 3,
		"desc": "Miniaturowa czarna dziura trzyma ładunek poza przestrzenią. Ogromna pojemność.",
		"effects": {"cargo": 650.0}, "cost": {"neonite": 3, "uranium": 3, "electronics": 10}},
	{"id": "yield", "label": "Wydobycie", "name": "Ekstraktor molekularny", "cat": "mining", "pos": Vector2i(1, -1), "max": 5,
		"desc": "Więcej surowca z każdego kafelka i odrobinę ciaśniejsze pakowanie ładowni.",
		"effects": {"yield_mult": 0.2, "cargo_mult": 0.08}, "cost": {"biomass": 20, "stone": 20, "water": 10}},
	{"id": "cargo2", "label": "Kompresja", "name": "Kompresja materii", "cat": "mining", "pos": Vector2i(2, -1), "max": 5,
		"desc": "Ogromne zwiększenie ładowni.",
		"effects": {"cargo": 100.0}, "cost": {"metal": 20, "copper": 10}},
	{"id": "cargo_mult", "label": "Mikrokompresja", "name": "Mikrokompresja", "cat": "mining", "pos": Vector2i(3, -1), "max": 5,
		"desc": "Procentowo zwiększa całą pojemność ładowni.",
		"effects": {"cargo_mult": 0.2}, "cost": {"copper": 10, "iron": 10}},
	{"id": "magnet", "label": "Teleport", "name": "Promień ściągający", "cat": "mining", "pos": Vector2i(4, -1), "max": 3,
		"desc": "Część surowców z przepełnionej ładowni trafia od razu do statku matki.",
		"effects": {"teleport": 0.15}, "cost": {"electronics": 4, "gold": 2, "metal": 15}},
	{"id": "dep_yield", "label": "Rafinacja", "name": "Rafinacja złóż", "cat": "mining", "pos": Vector2i(2, -2), "max": 3,
		"desc": "Więcej rudy ze złóż podziemnych.",
		"effects": {"deposit_yield_mult": 0.5}, "cost": {"iron": 12, "copper": 12}},
	{"id": "scanner", "label": "Skaner", "name": "Skaner głębinowy", "cat": "mining", "pos": Vector2i(4, 0), "max": 4,
		"desc": "Pokazuje złoża ukryte pod kafelkami wokół statku.",
		"effects": {"scanner": 4.0}, "cost": {"sand": 25, "electronics": 2}},

	# --- LABORATORIUM (prawo, w górę) ---
	{"id": "bio_probe", "label": "Sonda bio", "name": "Sonda biologiczna", "cat": "lab", "pos": Vector2i(4, -2), "max": 1,
		"desc": "Skaner wykrywający życie. Prowadzi do Laboratorium.",
		"effects": {"scanner": 1.0}, "cost": {"electronics": 3, "copper": 8, "biomass": 25}},
	{"id": "lab", "label": "Laboratorium", "name": "Laboratorium genetyczne", "cat": "lab", "pos": Vector2i(5, -2), "max": 1,
		"desc": "Otwiera Laboratorium i promień porywania istot (klawisz {tool2}).",
		"effects": {"lab": 1.0}, "cost": {"electronics": 6, "gold": 3, "metal": 25}},
	{"id": "abduct_speed", "label": "Porywanie", "name": "Wzmocniony promień", "cat": "lab", "pos": Vector2i(5, -3), "max": 4,
		"desc": "Promień porywania działa szybciej.",
		"effects": {"abduct_speed": 0.4}, "cost": {"biomass": 30, "electronics": 2}},
	{"id": "abduct_amount", "label": "Masowe", "name": "Szeroki promień", "cat": "lab", "pos": Vector2i(6, -3), "max": 3,
		"desc": "Więcej istot z jednego porwania.",
		"effects": {"abduct_amount": 1.0}, "cost": {"electronics": 4, "copper": 10}},
	{"id": "bio_capacity", "label": "Komory bio", "name": "Komory biologiczne", "cat": "lab", "pos": Vector2i(5, -1), "max": 5,
		"desc": "Więcej miejsca na porwane istoty w jednym locie.",
		"effects": {"bio_capacity": 3.0}, "cost": {"metal": 15, "water": 20}},
	{"id": "abduct_range", "label": "Zasięg por.", "name": "Długi promień", "cat": "lab", "pos": Vector2i(6, -1), "max": 3,
		"desc": "Porywaj z większej odległości.",
		"effects": {"abduct_range": 60.0}, "cost": {"sand": 30, "copper": 6}},
	{"id": "abduct_area", "label": "Obszar por.", "name": "Szeroka wiązka grawitonowa", "cat": "lab", "pos": Vector2i(7, -1), "max": 3,
		"desc": "Promień porywa istoty z kilku kafelków naraz: 5 / 9 / 13 pól na kolejnych poziomach.",
		"effects": {"abduct_area": 0.5}, "cost": {"electronics": 6, "copper": 12, "biomass": 40}},
	{"id": "research_speed", "label": "Badania", "name": "Sekwenatory genów", "cat": "lab", "pos": Vector2i(6, -2), "max": 4,
		"desc": "Badania w laboratorium trwają krócej.",
		"effects": {"research_speed": 0.35}, "cost": {"electronics": 5, "gold": 2}},
	{"id": "research_speed2", "label": "Kwantowy", "name": "Komputer kwantowy", "cat": "lab", "pos": Vector2i(7, -2), "max": 2,
		"desc": "Ogromne przyspieszenie badań.",
		"effects": {"research_speed": 0.75}, "cost": {"neonite": 2, "uranium": 2, "electronics": 8}},

	# --- IMPERIUM (prawo, w dół): kolejne węzły płaci się też Potęgą Imperium ---
	{"id": "rebuild", "label": "Odbudowa", "name": "Odbudowa imperialna", "cat": "empire", "pos": Vector2i(3, 1), "max": 1,
		"desc": "Nowe narzędzie [{tool3}]: odbudowuje zniszczone MIASTA w stylu Imperium. W odbudowanych miastach mogą powstać wieżyczki Imperium, które strzelają do Ziemian. Są niezniszczalne i generują Potęgę Imperium (1 na 2 minuty z każdego kafelka). Każdy kafelek kosztuje tyle surowców z magazynu, ile bazowo dawał.",
		"effects": {"rebuild": 1.0}, "cost": {"metal": 30, "electronics": 5, "stone": 40}},
	{"id": "rebuild_speed", "label": "Szybkość odb.", "name": "Nanokonstruktory", "cat": "empire", "pos": Vector2i(4, 1), "max": 4,
		"desc": "Odbudowa kafelka trwa krócej.",
		"effects": {"rebuild_speed": 0.5}, "cost": {"metal": 20, "copper": 8, "power": 40}},
	{"id": "rebuild_range", "label": "Zasięg odb.", "name": "Projektor budowlany", "cat": "empire", "pos": Vector2i(4, 2), "max": 3,
		"desc": "Odbudowuj z większej odległości.",
		"effects": {"rebuild_range": 70.0}, "cost": {"stone": 40, "iron": 8, "power": 40}},
	{"id": "rebuild_area", "label": "Obszar odb.", "name": "Matryca konstrukcyjna", "cat": "empire", "pos": Vector2i(5, 1), "max": 3,
		"desc": "Odbudowa obejmuje kilka zniszczonych kafelków naraz: 5 / 9 / 13 pól na kolejnych poziomach.",
		"effects": {"rebuild_area": 0.5}, "cost": {"stone": 50, "metal": 20, "electronics": 4, "power": 60}},
	{"id": "power_mult", "label": "Propaganda", "name": "Propaganda Imperium", "cat": "empire", "pos": Vector2i(5, 2), "max": 3,
		"desc": "Kafelki Imperium generują więcej Potęgi Imperium.",
		"effects": {"power_mult": 0.5}, "cost": {"electronics": 6, "gold": 3, "power": 60}},
	{"id": "ally_turrets", "label": "Wieżyczki", "name": "Garnizony Imperium", "cat": "empire", "pos": Vector2i(6, 1), "max": 3,
		"desc": "Większa szansa, że w odbudowanym mieście stanie wieżyczka Imperium.",
		"effects": {"ally_turret_chance": 0.15}, "cost": {"metal": 15, "scrap": 20, "power": 50}},
	{"id": "ally_dmg", "label": "Moc wieżyczek", "name": "Działa plazmowe garnizonu", "cat": "empire", "pos": Vector2i(6, 2), "max": 4,
		"desc": "Wieżyczki Imperium zadają większe obrażenia.",
		"effects": {"ally_damage": 8.0}, "cost": {"metal": 15, "electronics": 3, "power": 50}},
	{"id": "ally_range", "label": "Zasięg wieżyczek", "name": "Radary garnizonu", "cat": "empire", "pos": Vector2i(5, 3), "max": 3,
		"desc": "Wieżyczki Imperium sięgają dalej.",
		"effects": {"ally_range": 80.0}, "cost": {"sand": 30, "copper": 8, "power": 50}},

	# --- NOWE WĘZŁY (pos tu tylko do kosztu: pierścień = |x|+|y|; miejsce na ekranie w TREE) ---
	{"id": "laser_combat", "label": "Namiernik", "name": "Namiernik bojowy", "cat": "laser", "pos": Vector2i(-2, 1), "max": 4,
		"desc": "Laser zadaje więcej obrażeń myśliwcom (także wiązki myśliwców towarzyszących).",
		"effects": {"fighter_damage": 0.2}, "cost": {"metal": 12, "iron": 5}},
	{"id": "drill2", "label": "Wiertło kw.", "name": "Wiertło kwantowe", "cat": "laser", "pos": Vector2i(-4, 0), "max": 3,
		"desc": "Jeszcze większe obrażenia zadawane złożom.",
		"effects": {"deposit_damage_mult": 0.6}, "cost": {"iron": 10, "gold": 1}},
	{"id": "laser_focus", "label": "Soczewka plazm.", "name": "Soczewka plazmowa", "cat": "laser", "pos": Vector2i(0, -7), "max": 3,
		"desc": "Ostatni stopień ogniskowania: ogromny przyrost mocy lasera.",
		"effects": {"laser_dps": 35.0}, "cost": {"uranium": 2, "neonite": 1, "electronics": 5}},
	{"id": "hull_siphon", "label": "Rekonstrukcja", "name": "Rekonstrukcja z materii", "cat": "defense", "pos": Vector2i(-2, 2), "max": 4,
		"desc": "Każdy rozbity kafelek łata kadłub.",
		"effects": {"hull_siphon": 0.5}, "cost": {"biomass": 15, "scrap": 8}},
	{"id": "armor2", "label": "Pancerz reakt.", "name": "Pancerz reaktywny", "cat": "defense", "pos": Vector2i(-3, 2), "max": 3,
		"desc": "Druga warstwa pancerza - jeszcze mniej obrażeń kadłuba.",
		"effects": {"armor": 0.05}, "cost": {"iron": 8, "metal": 10}},
	{"id": "shield_cap", "label": "Matryca tarczy", "name": "Matryca tarczy", "cat": "defense", "pos": Vector2i(-4, -1), "max": 3,
		"desc": "Większa i szybciej odnawiana tarcza.",
		"effects": {"max_shield": 50.0, "shield_regen": 3.0}, "cost": {"electronics": 3, "water": 15}},
	{"id": "fuel_cell", "label": "Ogniwo", "name": "Ogniwo paliwowe", "cat": "engine", "pos": Vector2i(-2, -2), "max": 4,
		"desc": "Duży zapas paliwa na długie wyprawy.",
		"effects": {"max_fuel": 35.0}, "cost": {"water": 15, "metal": 6}},
	{"id": "strafe2", "label": "Wektorowe", "name": "Silniki wektorowe", "cat": "engine", "pos": Vector2i(-2, 3), "max": 3,
		"desc": "Mocniejszy lot w bok i szybszy obrót.",
		"effects": {"strafe": 0.1, "turn_rate": 1.0}, "cost": {"copper": 5, "biomass": 10}},
	{"id": "salvage", "label": "Szperacz", "name": "Szperacz molekularny", "cat": "mining", "pos": Vector2i(3, -2), "max": 4,
		"desc": "Rozbity kafelek ma szansę dać dodatkowo 1 rzadszy surowiec: miedź, żelazo, elektronikę albo złoto.",
		"effects": {"salvage": 0.04}, "cost": {"electronics": 3, "copper": 6}},
	{"id": "yield2", "label": "Ekstraktor kw.", "name": "Ekstraktor kwantowy", "cat": "mining", "pos": Vector2i(9, 0), "max": 3,
		"desc": "Więcej surowca z każdego kafelka.",
		"effects": {"yield_mult": 0.15}, "cost": {"neonite": 2, "uranium": 2, "gold": 3}},
	{"id": "power_mult2", "label": "Kult Imperium", "name": "Kult Imperium", "cat": "empire", "pos": Vector2i(6, 3), "max": 3,
		"desc": "Kafelki Imperium generują jeszcze więcej Potęgi Imperium.",
		"effects": {"power_mult": 0.4}, "cost": {"gold": 2, "electronics": 5, "power": 80}},
]

## Imperium: Statek Wydobywczy kupuje się za Punkt Chwały, a rozwija za Punkty Lojalności i surowce.
const EMPIRE := [
	{"id": "miner", "group": "miners", "unlock": true, "label": "Statek wydobywczy", "name": "Statek Wydobywczy", "cat": "empire", "max": 1, "ring": 1,
		"desc": "Sojuszniczy statek, który sam lata po okolicy Statku Matki, wyszukuje wybrany surowiec, wydobywa go i dowozi do magazynu.",
		"effects": {"miner_count": 1.0}, "cost": {"glory": 1}},
	{"id": "miner_fleet", "group": "miners", "requires": "miner", "label": "Kolejny statek", "name": "Rozbudowa floty", "cat": "empire", "max": 5, "ring": 1, "no_mastery": true,
		"desc": "Jeszcze jeden statek wydobywczy (najwyżej 6). Każdemu ustawisz osobny surowiec.",
		"effects": {"miner_count": 1.0}, "cost": {"loyalty": 30, "metal": 40, "electronics": 4}},
	{"id": "miner_drill", "group": "miners", "requires": "miner", "label": "Szybsze wydobycie", "name": "Wiertła floty", "cat": "empire", "max": 5, "ring": 1,
		"desc": "Statki wydobywcze szybciej rozbijają kafelki.",
		"effects": {"miner_dps": 8.0}, "cost": {"loyalty": 15, "iron": 20}},
	{"id": "miner_hold", "group": "miners", "requires": "miner", "label": "Więcej surowca", "name": "Separatory floty", "cat": "empire", "max": 5, "ring": 1,
		"desc": "Statki wydobywcze zbierają więcej surowca z jednego kafelka.",
		"effects": {"miner_yield": 0.3}, "cost": {"loyalty": 15, "copper": 20}},
	{"id": "miner_engine", "group": "miners", "requires": "miner", "label": "Szybszy lot", "name": "Silniki floty", "cat": "empire", "max": 4, "ring": 1,
		"desc": "Statki wydobywcze latają szybciej.",
		"effects": {"miner_speed": 60.0}, "cost": {"loyalty": 10, "biomass": 40}},
	{"id": "miner_armor", "group": "miners", "requires": "miner", "label": "Pancerz floty", "name": "Pancerz floty", "cat": "empire", "max": 5, "ring": 1,
		"desc": "Statki wydobywcze wytrzymują więcej trafień. Zniszczony statek wraca do pracy po dokowaniu, ale traci ładunek.",
		"effects": {"miner_hp": 40.0}, "cost": {"loyalty": 12, "iron": 40}},
	{"id": "miner_scan", "group": "miners", "requires": "miner", "label": "Skaner planetarny", "name": "Skaner planetarny", "cat": "empire", "max": 1, "ring": 1, "no_mastery": true,
		"desc": "Statki wydobywcze widzą wszystkie złoża ukryte pod ziemią i mogą wykopać każde z nich, także uran i neonit. Bez skanera kopią tylko złoża już odsłonięte.",
		"effects": {"miner_scan": 1.0}, "cost": {"glory": 1, "loyalty": 100, "wood": 20, "biomass": 20, "stone": 20, "copper": 20, "iron": 20, "electronics": 20, "weapon_scrap": 20}},
	{"id": "wing", "group": "wings", "unlock": true, "label": "Myśliwiec Imperium", "name": "Myśliwiec Imperium", "cat": "empire", "max": 1, "ring": 1,
		"desc": "Sojuszniczy myśliwiec czeka w hangarze Statku Matki. W locie wezwiesz go klawiszem [{wing}]: przyleci do Ciebie i będzie strzelał do wrogów.",
		"effects": {"wing_count": 1.0}, "cost": {"glory": 1}},
	{"id": "wing_more", "group": "wings", "requires": "wing", "label": "Kolejny myśliwiec", "name": "Eskadra Imperium", "cat": "empire", "max": 2, "ring": 1, "no_mastery": true,
		"desc": "Jeszcze jeden myśliwiec Imperium (najwyżej 3).",
		"effects": {"wing_count": 1.0}, "cost": {"loyalty": 40, "metal": 60, "electronics": 8}},
	{"id": "wing_dmg", "group": "wings", "requires": "wing", "label": "Cięższe działka", "name": "Działka eskadry", "cat": "empire", "max": 5, "ring": 1,
		"desc": "Myśliwce Imperium zadają większe obrażenia.",
		"effects": {"wing_damage": 6.0}, "cost": {"loyalty": 15, "weapon_scrap": 15}},
	{"id": "wing_rate", "group": "wings", "requires": "wing", "label": "Szybszy ogień", "name": "Chłodzenie eskadry", "cat": "empire", "max": 4, "ring": 1,
		"desc": "Myśliwce Imperium strzelają częściej.",
		"effects": {"wing_interval": -0.08}, "cost": {"loyalty": 15, "electronics": 4}},
	{"id": "wing_speed", "group": "wings", "requires": "wing", "label": "Dopalacze", "name": "Dopalacze eskadry", "cat": "empire", "max": 3, "ring": 1,
		"desc": "Myśliwce Imperium latają szybciej.",
		"effects": {"wing_speed": 80.0}, "cost": {"loyalty": 10, "biomass": 40}},
	{"id": "wing_armor", "group": "wings", "requires": "wing", "label": "Pancerz eskadry", "name": "Pancerz eskadry", "cat": "empire", "max": 5, "ring": 1,
		"desc": "Myśliwce Imperium wytrzymują więcej trafień. Zestrzelone wracają do hangaru po dokowaniu.",
		"effects": {"wing_hp": 30.0}, "cost": {"loyalty": 15, "metal": 50}},
	{"id": "transit", "group": "transit", "unlock": true, "label": "Statek tranzytowy", "name": "Statek tranzytowy", "cat": "empire", "max": 1, "ring": 1,
		"desc": "Frachtowiec Imperium co jakiś czas wyskakuje z nadprzestrzeni obok Ciebie, zabiera część ładowni i zawozi ją prosto do magazynu Statku Matki.",
		"effects": {"transit_count": 1.0}, "cost": {"glory": 1}},
	{"id": "transit_more", "group": "transit", "requires": "transit", "label": "Kolejny frachtowiec", "name": "Linia tranzytowa", "cat": "empire", "max": 2, "ring": 1, "no_mastery": true,
		"desc": "Jeszcze jeden statek tranzytowy (najwyżej 3) - kursy co krótszy czas.",
		"effects": {"transit_count": 1.0}, "cost": {"loyalty": 40, "metal": 80, "electronics": 10}},
	{"id": "transit_rate", "group": "transit", "requires": "transit", "label": "Częstsze kursy", "name": "Rozkład kursów", "cat": "empire", "max": 4, "ring": 1,
		"desc": "Statki tranzytowe przylatują częściej.",
		"effects": {"transit_interval": -6.0}, "cost": {"loyalty": 15, "copper": 30}},
	{"id": "transit_hold", "group": "transit", "requires": "transit", "label": "Większe kontenery", "name": "Kontenery tranzytowe", "cat": "empire", "max": 4, "ring": 1,
		"desc": "Każdy kurs zabiera większą część ładowni.",
		"effects": {"transit_share": 0.1}, "cost": {"loyalty": 15, "iron": 40}},
	{"id": "transit_armor", "group": "transit", "requires": "transit", "label": "Pancerz frachtowców", "name": "Pancerz frachtowców", "cat": "empire", "max": 4, "ring": 1,
		"desc": "Statki tranzytowe wytrzymują więcej trafień. Zestrzelony traci przewożony ładunek.",
		"effects": {"transit_hp": 60.0}, "cost": {"loyalty": 12, "metal": 50}},
]

## Rzadkie surowce drożeją wolniej: to one hamują postęp, a zwykłe mają być głównym kosztem.
const RARE := ["electronics", "gold", "uranium", "neonite"]
const RARE_GROWTH := 1.3
const POWER_GROWTH := 1.5
## Mnożnik zwykłych surowców według odległości węzła od rdzenia (pierścienia).
const RING_MULT := [1.0, 1.0, 2.0, 4.0, 8.0, 14.0, 22.0, 30.0]
const ARMORY_RING := 3
## Węzeł wykupiony do końca daje dodatkowe +25% swojego efektu (tylko węzły z kilkoma poziomami).
const MASTERY_BONUS := 0.25


## Wzrost kosztu na poziom: krótkie ścieżki strome, długie łagodniejsze.
static func growth(mx: int) -> float:
	if mx <= 3:
		return 1.9
	if mx <= 5:
		return 1.7
	if mx <= 6:
		return 1.55
	return 1.38


static func ring_mult(u: Dictionary) -> float:
	var ring: int = u.get("ring", ARMORY_RING)
	if u.has("pos"):
		ring = absi(u["pos"].x) + absi(u["pos"].y)
	return RING_MULT[mini(ring, RING_MULT.size() - 1)]


## Zbrojownia: każda broń ma węzeł odblokowania (weapon_unlock) i ulepszenia wymagające odblokowania.
const WEAPONS := [
	{"key": "rockets", "name": "RAKIETY", "desc": "Odpalasz je sam w stronę kursora (klawisz z opcji, domyślnie Q). Ładują się same, do 3 w zapasie. Wybuch rani wszystko w okręgu.",
		"stats": ["rocket_cooldown", "rocket_radius", "rocket_damage"]},
	{"key": "drones", "name": "DRONY", "desc": "Krążą wokół statku i strzelają. Najpierw w myśliwce, potem w kafelki.",
		"stats": ["drone_count", "drone_damage", "drone_interval"]},
	{"key": "guns", "name": "KARABINY", "desc": "Automatycznie ostrzeliwują wyłącznie wieżyczki obronne.",
		"stats": ["gun_damage", "gun_interval", "gun_range"]},
	{"key": "escort", "name": "MYŚLIWIEC", "desc": "Leci w szyku przy Twoim statku i strzela laserem tam, gdzie kursor, razem z Tobą.",
		"stats": ["escort_count", "escort_power", "escort_hp"]},
]

const ARMORY := [
	# --- rakiety ---
	{"id": "rockets", "weapon": "rockets", "unlock": true, "label": "Odblokuj", "name": "Wyrzutnia rakiet", "cat": "weapons", "max": 1,
		"desc": "Rakieta leci tam, gdzie kursor, po wciśnięciu [{rocket}]. Ładuje się 10 s, w zapasie najwyżej 3. Wybuch o promieniu 4 kafelków. Na start słabe - rozwijaj je!",
		"effects": {"rocket_unlocked": 1.0}, "cost": {"weapon_scrap": 8, "metal": 10}},
	{"id": "rocket_reload", "weapon": "rockets", "requires": "rockets", "label": "Szybsze przeładowanie", "name": "Automat ładujący", "cat": "weapons", "max": 5,
		"desc": "Rakiety ładują się szybciej.",
		"effects": {"rocket_cooldown": -1.4}, "cost": {"weapon_scrap": 6, "iron": 6}},
	{"id": "rocket_radius", "weapon": "rockets", "requires": "rockets", "label": "Większy wybuch", "name": "Głowica termobaryczna", "cat": "weapons", "max": 4,
		"desc": "Większy promień eksplozji.",
		"effects": {"rocket_radius": 0.75}, "cost": {"weapon_scrap": 8, "copper": 6}},
	{"id": "rocket_dmg", "weapon": "rockets", "requires": "rockets", "label": "Silniejsze głowice", "name": "Ładunek plazmowy", "cat": "weapons", "max": 6,
		"desc": "Znacznie większe obrażenia rakiet.",
		"effects": {"rocket_damage": 17.0}, "cost": {"weapon_scrap": 6, "metal": 12}},
	# --- drony ---
	{"id": "drones", "weapon": "drones", "unlock": true, "label": "Odblokuj", "name": "Hangar dronów", "cat": "weapons", "max": 1,
		"desc": "Jeden dron bojowy krążący wokół statku.",
		"effects": {"drone_count": 1.0}, "cost": {"weapon_scrap": 10, "electronics": 3}},
	{"id": "drone_more", "weapon": "drones", "requires": "drones", "label": "Więcej dronów", "name": "Rozbudowa roju", "cat": "weapons", "max": 3,
		"desc": "Dodatkowy dron.",
		"effects": {"drone_count": 1.0}, "cost": {"weapon_scrap": 12, "electronics": 4}},
	{"id": "drone_dmg", "weapon": "drones", "requires": "drones", "label": "Mocniejsze działka", "name": "Działka pulsacyjne", "cat": "weapons", "max": 5,
		"desc": "Większe obrażenia pojedynczego strzału drona.",
		"effects": {"drone_damage": 5.0}, "cost": {"weapon_scrap": 6, "copper": 5}},
	{"id": "drone_rate", "weapon": "drones", "requires": "drones", "label": "Szybszy ogień", "name": "Chłodzenie dronów", "cat": "weapons", "max": 4,
		"desc": "Drony strzelają częściej.",
		"effects": {"drone_interval": -0.25}, "cost": {"weapon_scrap": 6, "water": 15}},
	# --- karabiny ---
	{"id": "guns", "weapon": "guns", "unlock": true, "label": "Odblokuj", "name": "Karabiny przeciwwieżowe", "cat": "weapons", "max": 1,
		"desc": "Automatycznie strzelają do wieżyczek w zasięgu.",
		"effects": {"gun_unlocked": 1.0}, "cost": {"weapon_scrap": 6, "scrap": 15}},
	{"id": "gun_dmg", "weapon": "guns", "requires": "guns", "label": "Cięższa amunicja", "name": "Amunicja przeciwpancerna", "cat": "weapons", "max": 5,
		"desc": "Większe obrażenia pocisków.",
		"effects": {"gun_damage": 7.0}, "cost": {"weapon_scrap": 5, "iron": 5}},
	{"id": "gun_rate", "weapon": "guns", "requires": "guns", "label": "Szybkostrzelność", "name": "Obrotowe lufy", "cat": "weapons", "max": 4,
		"desc": "Karabiny strzelają częściej.",
		"effects": {"gun_interval": -0.08}, "cost": {"weapon_scrap": 5, "metal": 8}},
	{"id": "gun_range", "weapon": "guns", "requires": "guns", "label": "Zasięg", "name": "Celownik optyczny", "cat": "weapons", "max": 4,
		"desc": "Karabiny sięgają dalej.",
		"effects": {"gun_range": 90.0}, "cost": {"weapon_scrap": 4, "sand": 15}},
	# --- myśliwiec towarzyszący (odblokowanie od razu daje 1. poziom liczby myśliwców; moc i kadłub z Mistrzostwem do 50%) ---
	{"id": "escort", "weapon": "escort", "unlock": true, "label": "Odblokuj", "name": "Myśliwiec towarzyszący", "cat": "weapons", "max": 1,
		"desc": "Myśliwiec lecący przy Twoim statku. Strzela razem z Tobą z 25% mocy lasera i ma 25% Twojego kadłuba.",
		"effects": {}, "grants": {"escort_more": 1}, "cost": {"weapon_scrap": 15, "metal": 20, "electronics": 4}},
	{"id": "escort_more", "weapon": "escort", "requires": "escort", "label": "Liczba myśliwców", "name": "Para skrzydłowa", "cat": "weapons", "max": 2, "no_mastery": true,
		"desc": "Poziom 1: jeden myśliwiec (od razu po odblokowaniu). Poziom 2: drugi, po drugiej stronie statku.",
		"effects": {"escort_count": 1.0}, "cost": {"weapon_scrap": 20, "electronics": 6}},
	{"id": "escort_dmg", "weapon": "escort", "requires": "escort", "label": "Mocniejszy laser", "name": "Sprzężenie wiązek", "cat": "weapons", "max": 4,
		"desc": "Myśliwce strzelają większym procentem mocy Twojego lasera (do 50% z Mistrzostwem).",
		"effects": {"escort_power": 0.05}, "cost": {"weapon_scrap": 6, "copper": 8}},
	{"id": "escort_hp", "weapon": "escort", "requires": "escort", "label": "Mocniejszy kadłub", "name": "Pancerz skrzydłowych", "cat": "weapons", "max": 4,
		"desc": "Myśliwce mają większy procent Twojego kadłuba (do 50% z Mistrzostwem).",
		"effects": {"escort_hp": 0.05}, "cost": {"weapon_scrap": 6, "iron": 6}},
]


## Laboratorium: badania trwają w czasie rzeczywistym ("time" w sekundach przy szybkości 100%).
## Odkrywają się dopiero, gdy spełnione są wymagania ("requires").
const LAB := [
	{"id": "genome_cows", "label": "Genom bydła", "name": "Genom bydła", "cat": "lab", "max": 1, "time": 45.0,
		"desc": "Pierwsze badanie ziemskiej fauny. Bio-tkanka wzmacnia kadłub.",
		"effects": {"hull_regen": 0.5}, "cost": {"cows": 2}},
	{"id": "genome_humans", "label": "Genom ludzi", "name": "Genom człowieka", "cat": "lab", "max": 1, "time": 60.0,
		"desc": "Zrozumienie Ziemian. Lepiej wiemy, gdzie szukać surowców.",
		"effects": {"yield_mult": 0.1}, "cost": {"humans": 2}},
	{"id": "genome_deer", "label": "Genom jeleni", "name": "Genom jeleniowatych", "cat": "lab", "max": 1, "time": 45.0,
		"desc": "Zwinność jeleni - lepsza zwrotność statku.",
		"effects": {"turn_rate": 1.0}, "cost": {"deer": 2}},
	{"id": "imp_growth", "label": "Rozrost Imperium", "name": "Samoodbudowa Imperium", "cat": "lab", "max": 1, "time": 90.0,
		"requires": "rebuild",
		"desc": "Miasta Imperium same się rozrastają: co 10 s przejmują sąsiedni kafelek miasta (najpierw zniszczone).",
		"effects": {"imp_spread": 1.0}, "cost": {"power": 120, "humans": 2}},
	{"id": "imp_growth_speed", "label": "Szybszy rozrost", "name": "Nanofabryki Imperium", "cat": "lab", "max": 5, "time": 60.0,
		"requires": "imp_growth",
		"desc": "Rozrost Imperium o 1 s szybciej (do 5 s).",
		"effects": {"imp_spread_cd": -1.0}, "cost": {"power": 150}},
]


## Drzewko ulepszeń jak w Path of Exile / Grim Dawn / Nova Drift: każdy węzeł ma jednego rodzica i otwiera
## zwykle 2-3 kolejne, gałęzie rozchodzą się od rdzenia w cztery strony z wolnym pasem między nimi.
## TREE: id -> [rodzic, pozycja na ekranie w polach siatki]. Pozycja tylko do rysowania - koszt (pierścień)
## liczy się dalej z "pos" w LIST, więc przestawianie drzewka nie zmienia cen.
const TREE := {
	"core": ["", Vector2(0, 0)],
	# LASER (góra): moc -> zasięg (wiertło, złoża) / rezonator (przeciążenie, detonacja, zbrojownia) / rozprysk (błyskawice)
	"laser_dmg": ["core", Vector2(0, -2)],
	"laser_range": ["laser_dmg", Vector2(-2, -3.5)],
	"laser_resonator": ["laser_dmg", Vector2(0, -4)],
	"laser_splash": ["laser_dmg", Vector2(2, -3.5)],
	"laser_drill": ["laser_range", Vector2(-3, -5)],
	"dep_yield": ["laser_drill", Vector2(-4.4, -5.8)],
	"laser_overdrive": ["laser_resonator", Vector2(0, -6)],
	"armory": ["laser_resonator", Vector2(-1.4, -5.4)],
	"detonate": ["laser_overdrive", Vector2(0, -7.6)],
	"det_chance": ["detonate", Vector2(-1.4, -8.6)],
	"det_power": ["detonate", Vector2(0, -9.3)],
	"det_radius": ["detonate", Vector2(1.4, -8.6)],
	"chain": ["laser_splash", Vector2(3, -5)],
	"chain_jumps": ["chain", Vector2(2.6, -6.6)],
	"chain_power": ["chain", Vector2(4.4, -5.6)],
	"chain_range": ["chain_jumps", Vector2(2.9, -8.2)],
	"chain_rate": ["chain_power", Vector2(5, -7)],
	# OBRONA (lewo): kadłub -> tarcza / nanowłókna / pancerz
	"hull": ["core", Vector2(-2, 0)],
	"shield": ["hull", Vector2(-3.4, -1.4)],
	"hull_plating": ["hull", Vector2(-3.8, 0)],
	"armor": ["hull", Vector2(-3.4, 1.4)],
	"shield_regen": ["shield", Vector2(-4.6, -2.6)],
	"shield_phase": ["shield", Vector2(-5.3, -1.3)],
	"repair": ["hull_plating", Vector2(-5.4, 0.4)],
	# NAPĘD (dół): ciąg -> prędkość / obrót / zbiornik
	"thrust": ["core", Vector2(0, 2)],
	"max_speed": ["thrust", Vector2(0, 3.6)],
	"turn": ["thrust", Vector2(-1.6, 3.1)],
	"fuel_tank": ["thrust", Vector2(1.6, 3.1)],
	"warp": ["max_speed", Vector2(0, 5.2)],
	"bridge": ["warp", Vector2(0, 6.8)],
	"maneuver": ["turn", Vector2(-3.1, 3.8)],
	"brake": ["turn", Vector2(-1.7, 4.8)],
	"drift_boost": ["brake", Vector2(-2.3, 6.3)],
	"fuel_tank2": ["fuel_tank", Vector2(3.1, 3.8)],
	"fuel_eff": ["fuel_tank", Vector2(1.7, 4.8)],
	"fuel_siphon": ["fuel_eff", Vector2(2.3, 6.3)],
	# WYDOBYCIE (prawo): ładownia -> wydobycie (teleport -> LABORATORIUM) / ładownie / kompresja (-> IMPERIUM)
	"cargo": ["core", Vector2(2, 0)],
	"yield": ["cargo", Vector2(3.3, -1.5)],
	"cargo_b": ["cargo", Vector2(3.7, 0)],
	"cargo2": ["cargo", Vector2(3.3, 1.5)],
	"cargo_mult": ["yield", Vector2(4.9, -1.6)],
	"magnet": ["yield", Vector2(4, -3)],
	"cargo_pocket": ["cargo_b", Vector2(5.3, 0)],
	"scanner": ["cargo_pocket", Vector2(6.7, -0.9)],
	"cargo_hull": ["cargo_pocket", Vector2(6.7, 0.9)],
	"cargo_dim": ["scanner", Vector2(8.2, -1)],
	"cargo_sing": ["cargo_dim", Vector2(9.7, -1)],
	"cargo_lattice": ["cargo_hull", Vector2(8.2, 1)],
	# LABORATORIUM (prawo, w górę)
	"bio_probe": ["magnet", Vector2(5.3, -3.6)],
	"lab": ["bio_probe", Vector2(6.6, -4.3)],
	"abduct_speed": ["lab", Vector2(7.4, -5.7)],
	"research_speed": ["lab", Vector2(8.1, -4.3)],
	"bio_capacity": ["lab", Vector2(7.4, -2.9)],
	"abduct_amount": ["abduct_speed", Vector2(8.9, -6.1)],
	"research_speed2": ["research_speed", Vector2(9.6, -4.3)],
	"abduct_range": ["bio_capacity", Vector2(8.9, -2.6)],
	"abduct_area": ["abduct_range", Vector2(10.4, -2.6)],
	# IMPERIUM (prawo, w dół)
	"rebuild": ["cargo2", Vector2(4.6, 2.9)],
	"rebuild_speed": ["rebuild", Vector2(6.1, 2.6)],
	"rebuild_range": ["rebuild", Vector2(4.5, 4.5)],
	"ally_turrets": ["rebuild", Vector2(5.9, 4.1)],
	"rebuild_area": ["rebuild_speed", Vector2(7.6, 2.6)],
	"power_mult": ["rebuild_area", Vector2(9.1, 2.6)],
	"ally_dmg": ["ally_turrets", Vector2(7.3, 4.7)],
	"ally_range": ["ally_turrets", Vector2(5.9, 5.7)],
	# nowe węzły
	"laser_combat": ["laser_range", Vector2(-3.4, -3.2)],
	"drill2": ["laser_drill", Vector2(-4.2, -4.4)],
	"laser_focus": ["laser_overdrive", Vector2(-1.4, -7)],
	"hull_siphon": ["armor", Vector2(-4.8, 2.2)],
	"armor2": ["hull_siphon", Vector2(-6.2, 2.6)],
	"shield_cap": ["shield_phase", Vector2(-6.7, -1.8)],
	"fuel_cell": ["fuel_tank2", Vector2(3.4, 5.2)],
	"strafe2": ["maneuver", Vector2(-4.4, 4.6)],
	"salvage": ["cargo_mult", Vector2(6.2, -2.2)],
	"yield2": ["cargo_sing", Vector2(11.1, -1)],
	"power_mult2": ["power_mult", Vector2(10.6, 2.6)],
}


static func parent_of(id: String) -> String:
	return String(TREE[id][0]) if TREE.has(id) else ""


static func display_pos(u: Dictionary) -> Vector2:
	var id: String = u["id"]
	return TREE[id][1] if TREE.has(id) else Vector2(u["pos"])

static var _all: Array = []
static var _ids: Dictionary = {}
static var _positions: Dictionary = {}


## Spis budowany raz: te funkcje są wołane setki razy na klatkę przy rysowaniu siatki.
static func _index() -> void:
	_all = LIST + ARMORY + LAB + EMPIRE
	for u in _all:
		_ids[u["id"]] = u
	for u in LIST:
		_positions[u["pos"]] = u


static func all_items() -> Array:
	if _all.is_empty():
		_index()
	return _all


static func by_id(id: String) -> Dictionary:
	if _all.is_empty():
		_index()
	return _ids.get(id, {})


static func by_pos(p: Vector2i) -> Dictionary:
	if _all.is_empty():
		_index()
	return _positions.get(p, {})
