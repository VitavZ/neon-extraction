extends RefCounted
## Rozkazy z Imperium Vex. Na starcie jest tylko "Pierwsza ekspedycja"; reszta pojawia się sama:
## kolejny rozkaz fabularny po poprzednim, a rozkazy wydobycia po pierwszym dostarczeniu danego surowca.
## Postęp wydobycia to suma rozładowana w Statku Matce od wprowadzenia rozkazów. Nagroda: Punkty Lojalności.

const STORY := [
	{"id": "first_expedition", "title": "Pierwsza ekspedycja", "desc": "Wróć z wyprawy do Statku Matki i rozładuj łup.",
		"reward": 10, "kind": "event", "event": "dock"},
	{"id": "destroy_ny", "title": "Zniszcz Nowy Jork", "desc": "Zrównaj z ziemią całą metropolię Nowego Jorku.",
		"reward": 100, "kind": "metro", "sector": 2, "after": "first_expedition"},
	# "rebuild": zalicza się, gdy taki odsetek kafelków metropolii jest kafelkami Imperium (odbudowa i rozrost);
	# "new_name": od wykonania rozkazu miasto nosi nową nazwę (GameState.city_name)
	{"id": "rebuild_ny", "title": "Odbuduj Nowy Jork", "desc": "Odbuduj w stylu Imperium 80% kafelków metropolii Nowego Jorku.",
		"reward": 50, "kind": "rebuild", "sector": 2, "fraction": 0.8, "new_name": "NOWSZY JORK", "after": "destroy_ny"},
	{"id": "destroy_chicago", "title": "Zniszcz Chicago", "desc": "Zrównaj z ziemią całą metropolię Chicago w Środkowym Zachodzie.",
		"reward": 100, "kind": "metro", "sector": 1, "after": "rebuild_ny"},
	{"id": "rebuild_chicago", "title": "Odbuduj Chicago", "desc": "Odbuduj w stylu Imperium 80% kafelków metropolii Chicago.",
		"reward": 50, "kind": "rebuild", "sector": 1, "fraction": 0.8, "new_name": "VEXAGO", "after": "destroy_chicago"},
	{"id": "destroy_miami", "title": "Zniszcz Miami", "desc": "Zrównaj z ziemią całą metropolię Miami na Południowym Wschodzie.",
		"reward": 100, "kind": "metro", "sector": 8, "after": "rebuild_ny"},
	{"id": "rebuild_miami", "title": "Odbuduj Miami", "desc": "Odbuduj w stylu Imperium 80% kafelków metropolii Miami.",
		"reward": 50, "kind": "rebuild", "sector": 8, "fraction": 0.8, "new_name": "NEONOWE MIAMI", "after": "destroy_miami"},
	{"id": "destroy_dallas", "title": "Zniszcz Dallas", "desc": "Zrównaj z ziemią całą metropolię Dallas na Wielkich Równinach.",
		"reward": 100, "kind": "metro", "sector": 4, "after": "rebuild_ny"},
	{"id": "rebuild_dallas", "title": "Odbuduj Dallas", "desc": "Odbuduj w stylu Imperium 80% kafelków metropolii Dallas.",
		"reward": 50, "kind": "rebuild", "sector": 4, "fraction": 0.8, "new_name": "GWIEZDNY DALLAS", "after": "destroy_dallas"},
	{"id": "destroy_houston", "title": "Zniszcz Houston", "desc": "Zrównaj z ziemią całą metropolię Houston nad Zatoką.",
		"reward": 100, "kind": "metro", "sector": 7, "after": "rebuild_ny"},
	{"id": "rebuild_houston", "title": "Odbuduj Houston", "desc": "Odbuduj w stylu Imperium 80% kafelków metropolii Houston.",
		"reward": 50, "kind": "rebuild", "sector": 7, "fraction": 0.8, "new_name": "KOSMOPORT VEX", "after": "destroy_houston"},
	{"id": "destroy_seattle", "title": "Zniszcz Seattle", "desc": "Zrównaj z ziemią całą metropolię Seattle na Północnym Zachodzie.",
		"reward": 100, "kind": "metro", "sector": 0, "after": "rebuild_ny"},
	{"id": "rebuild_seattle", "title": "Odbuduj Seattle", "desc": "Odbuduj w stylu Imperium 80% kafelków metropolii Seattle.",
		"reward": 50, "kind": "rebuild", "sector": 0, "fraction": 0.8, "new_name": "IGLICA VEX", "after": "destroy_seattle"},
	{"id": "destroy_la", "title": "Zniszcz Los Angeles", "desc": "Zrównaj z ziemią całą metropolię Los Angeles na Zachodzie.",
		"reward": 100, "kind": "metro", "sector": 3, "after": "rebuild_ny"},
	{"id": "rebuild_la", "title": "Odbuduj Los Angeles", "desc": "Odbuduj w stylu Imperium 80% kafelków metropolii Los Angeles.",
		"reward": 50, "kind": "rebuild", "sector": 3, "fraction": 0.8, "new_name": "NOWY EDEN", "after": "destroy_la"},
	{"id": "destroy_hermosillo", "title": "Zniszcz Hermosillo", "desc": "Zrównaj z ziemią całą metropolię Hermosillo w Sonorze.",
		"reward": 100, "kind": "metro", "sector": 6, "after": "rebuild_ny"},
	{"id": "rebuild_hermosillo", "title": "Odbuduj Hermosillo", "desc": "Odbuduj w stylu Imperium 80% kafelków metropolii Hermosillo.",
		"reward": 50, "kind": "rebuild", "sector": 6, "fraction": 0.8, "new_name": "SŁONECZNY BASTION", "after": "destroy_hermosillo"},
	{"id": "conquer_federal", "title": "Upadek Stolicy", "desc": "Pokonaj strażników Waszyngtonu i Pentagonu w Dystrykcie Federalnym.",
		"reward": 250, "kind": "federal"},
]

## [surowiec, dopełniacz do tytułu, dopełniacz do opisu, próg I, próg II]
const EXTRACTION := [
	["wood", "Drewna", "drewna", 100, 1000],
	["stone", "Kamienia", "kamienia", 100, 1000],
	["biomass", "Biomasy", "biomasy", 100, 1000],
	["water", "Wody", "wody", 100, 1000],
	["saltwater", "Słonej Wody", "słonej wody", 100, 1000],
	["sand", "Piasku", "piasku", 100, 1000],
	["scrap", "Złomu", "złomu", 100, 1000],
	["metal", "Metalu", "metalu", 50, 500],
	["copper", "Miedzi", "miedzi", 50, 500],
	["iron", "Żelaza", "żelaza", 50, 500],
	["weapon_scrap", "Resztek Broni", "resztek broni", 30, 300],
	["electronics", "Elektroniki", "elektroniki", 20, 200],
	["gold", "Złota", "złota", 10, 100],
	["uranium", "Uranu", "uranu", 10, 100],
	["neonite", "Neonitu", "neonitu", 5, 50],
]

## Porywanie idzie wolniej, więc progi są niskie: [istota, dopełniacz, próg I, próg II]
const ABDUCTION := [
	["cows", "Krów", "krów", 5, 25],
	["deer", "Jeleni", "jeleni", 5, 25],
	["humans", "Ludzi", "ludzi", 5, 25],
]

const SIMPLE_REWARD := 10

static var _all: Array = []


static func all() -> Array:
	if not _all.is_empty():
		return _all
	_all = STORY.duplicate()
	for e in EXTRACTION:
		_all.append({"id": "res_%s_1" % e[0], "title": "Ekstrakcja %s I" % e[1], "desc": "Dostarcz do Statku Matki %d jedn. %s." % [e[3], e[2]],
			"reward": SIMPLE_REWARD, "kind": "collect", "res": e[0], "target": e[3]})
		_all.append({"id": "res_%s_2" % e[0], "title": "Ekstrakcja %s II" % e[1], "desc": "Dostarcz do Statku Matki %d jedn. %s." % [e[4], e[2]],
			"reward": SIMPLE_REWARD, "kind": "collect", "res": e[0], "target": e[4], "after": "res_%s_1" % e[0]})
	for e in ABDUCTION:
		_all.append({"id": "bio_%s_1" % e[0], "title": "Porwanie %s I" % e[1], "desc": "Dostarcz do Statku Matki %d porwanych %s." % [e[3], e[2]],
			"reward": SIMPLE_REWARD, "kind": "collect", "res": e[0], "target": e[3]})
		_all.append({"id": "bio_%s_2" % e[0], "title": "Porwanie %s II" % e[1], "desc": "Dostarcz do Statku Matki %d porwanych %s." % [e[4], e[2]],
			"reward": SIMPLE_REWARD, "kind": "collect", "res": e[0], "target": e[4], "after": "bio_%s_1" % e[0]})
	return _all
