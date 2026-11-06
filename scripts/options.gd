extends RefCounted
## Wspólna logika ekranu OPCJE dla menu głównego i pauzy: lista pozycji, zmiana i zastosowanie ustawień,
## tekst wartości, suwaki głośności. Rysowanie zostaje w menu.gd / pause_menu.gd (różny wygląd).
## Użycie: const Options = preload("res://scripts/options.gd")

const CrtScript = preload("res://scripts/crt.gd")

const ITEMS := ["resolution", "fullscreen", "vsync", "volume", "music", "sfx", "quality", "comfort", "crt", "glow", "shake", "controls", "back"]
const NAMES := {
	"resolution": "ROZDZIELCZOŚĆ", "fullscreen": "TRYB EKRANU", "vsync": "V-SYNC", "volume": "GŁOŚNOŚĆ OGÓLNA", "music": "MUZYKA", "sfx": "EFEKTY DŹWIĘKOWE",
	"quality": "JAKOŚĆ OBRAZU", "comfort": "JASKRAWOŚĆ", "crt": "FILTR CRT", "glow": "POŚWIATA NEONÓW", "shake": "WSTRZĄSY EKRANU", "controls": "STEROWANIE", "back": "< WRÓĆ",
}
const VOLUME_KEYS := ["volume", "music", "sfx"]


## Zmienia ustawienie o krok d (+1/-1), zapisuje i od razu stosuje (crt/env mogą być null).
## Zwraca false dla pozycji bez wartości ("controls", "back") - nimi zajmuje się wywołujący.
static func change(key: String, d: int, crt: CanvasLayer, env: Environment) -> bool:
	var st := GameState.settings
	match key:
		"resolution":
			st["resolution"] = posmod(int(st["resolution"]) + d, GameState.RESOLUTIONS.size())
		"volume", "music", "sfx":
			st[key] = clampi(int(st[key]) + d * 10, 0, 100)
		"fullscreen", "vsync", "crt", "glow", "shake":
			st[key] = not bool(st[key])
		"quality":
			st["quality"] = posmod(int(st.get("quality", 0)) + d, GameState.QUALITY_LEVELS.size())
		"comfort":
			st["comfort"] = posmod(int(st.get("comfort", 1)) + d, CrtScript.COMFORT_LEVELS.size())
		_:
			return false
	GameState.save_settings()
	Audio.play("ui_click", 0.0)
	if key in ["resolution", "fullscreen", "vsync"]:
		GameState.apply_settings()
	if key in VOLUME_KEYS:
		Audio.apply_volumes()
	if key == "crt" and crt:
		crt.rect.visible = bool(st["crt"])
	if key == "glow" and env:
		env.glow_enabled = bool(st["glow"])
	if key == "comfort" and crt:
		crt.apply_comfort()
	if key == "quality":
		GameState.apply_quality()
	return true


static func value_text(key: String) -> String:
	var st := GameState.settings
	match key:
		"resolution":
			var r: Vector2i = GameState.RESOLUTIONS[int(st["resolution"])]
			return "%d × %d" % [r.x, r.y]
		"fullscreen":
			return "PEŁNY EKRAN" if st["fullscreen"] else "OKNO"
		"volume", "music", "sfx":
			return "%d%%" % int(st[key])
		"vsync", "crt", "glow", "shake":
			return "WŁ." if st[key] else "WYŁ."
		"controls":
			return "PRZYPISZ"
		"comfort":
			return CrtScript.comfort_name()
		"quality":
			return GameState.quality_name()
	return ""


## Obszar kliknięcia suwaka głośności: akcja "vol:<klucz>:<wartość>".
static func volume_action(key: String, value: int) -> String:
	return "vol:%s:%d" % [key, value]


## Obsługa akcji "vol:..." (klik lub przeciąganie po suwaku).
static func set_volume_from(action: String) -> void:
	var parts: PackedStringArray = action.split(":")
	if int(GameState.settings[parts[1]]) != int(parts[2]):
		GameState.settings[parts[1]] = int(parts[2])
		GameState.save_settings()
		Audio.apply_volumes()
		Audio.play("ui_hover", 0.0)
