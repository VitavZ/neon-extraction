extends RefCounted
## Rozkazy z Imperium Vex. Na starcie jest tylko "Pierwsza ekspedycja"; reszta pojawia się sama:
## kolejny rozkaz fabularny po poprzednim, a rozkazy wydobycia po pierwszym dostarczeniu danego surowca.
## Postęp wydobycia to suma rozładowana w Statku Matce od wprowadzenia rozkazów. Nagroda: Punkty Lojalności.

const STORY := [
	{"id": "first_expedition", "title": "Pierwsza ekspedycja", "desc": "Wróć z wyprawy do Statku Matki i rozładuj łup.",
		"reward": 10, "kind": "event", "event": "dock"},
	{"id": "destroy_ny", "title": "Zniszcz Nowy Jork", "desc": "Zrównaj z ziemią całą metropolię Nowego Jorku.",
		"reward": 100, "kind": "metro", "sector": 2, "after": "first_expedition"},
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
