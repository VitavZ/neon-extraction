# Neon Extraction – instrukcje dla Claude

Godot 4.7.2, GDScript, 2D. Wszystko rysowane wektorowo w `_draw()` (kolory HDR, neon/synthwave), brak sprite'ów i scen UI.
Teksty w grze i komentarze w kodzie po polsku. Autoloady: `GameState`, `Audio`, `Achievements`.
Historia zmian i otwarte sprawy: `PODSUMOWANIE_PRAC.md` (czytać tylko w razie potrzeby).

## Zasady (ważne)
- **Zapisy gracza:** sloty 1–3 to prawdziwy postęp – nigdy ich nie zapisywać ani nie usuwać. Grę uruchamiać tylko przez
  `tools/test/run_test.ps1` (sam robi slot 4 = kopia slotu 1, kopie `settings.cfg`/`achievements.cfg`, sprząta i sprawdza hashe).
  Dane: `%APPDATA%\Godot\app_userdata\Neon Extraction`.
- **Nie czytać** `scripts/us_map_data.gd` (35 KB danych w jednej linii, generuje go `tools/bake_us_map.gd`).
- Pliki: UTF-8 bez BOM, LF. W PowerShell 5.1 zapisywać przez `[IO.File]::WriteAllText(..., (New-Object Text.UTF8Encoding $false))`;
  nie nazywać funkcji `R`/`Rp` (aliasy). Python jest dostępny jako `py -I`.
- Styl: wspólne kolory/czcionki/ikony/pomocniki w `scripts/style.gd` (`const Style = preload(...)`, m.in. `Style.ease_out`,
  `Style.chamfer_pts`, `Style.closed`, `Style.chamfer_panel`, `Style.draw_icon`). Nie dublować ich lokalnie.

## Testy
```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test\run_test.ps1 [-Out <katalog>] [-Script res://tools/test/smoke.gd]
```
- `tools/test/smoke.gd`: splash, menu (opcje, osiągnięcia, sloty), dok (wszystkie zakładki, PARAMETRY), lot, pauza (opcje, sterowanie).
  Wypisuje `[TEST] ...`, zrzuty PNG do `-Out` (domyślnie `%TEMP%\neon_test_shots`). Raport błędów skryptów na końcu.
- Własny test: skopiować `smoke.gd` do `tools/test/` pod inną nazwą (`extends SceneTree`), uruchomić z `-Script`.
- Porównanie zrzutów przed/po: `Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test/compare.gd -- <A> <B>`
  (ekrany doku powinny dać 0,0%; menu/lot/pauza mają kilka–30% szumu z animacji i losowości).
- Sama składnia: `--headless --check-only --script res://scripts/X.gd` (błąd „Identifier not found: GameState” jest tam normalny).
- Godot: `C:\Users\Kamil\Desktop\Godot\Godot_v4.7.2-stable_win64_console.exe`.

## Git i wydania
- Prywatne repo `https://github.com/VitavZ/neon-extraction`, gałąź `main`. Wersja: `menu.gd: VERSION` + `export_presets.cfg` (oba presety).
- `git` z GitHub Desktop: `$env:PATH = "C:\Users\Kamil\AppData\Local\GitHubDesktop\app-3.6.10\resources\app\git\cmd;$env:PATH"`;
  push: `git -c credential.helper= -c "credential.helper=!gh auth git-credential" push`.
- Eksport: `... --headless --path . --export-release "Windows Desktop" <plik.exe>` oraz `"macOS" <plik.zip>`;
  buildy do `..\builds\vX.Y.Z\`, publikacja przez `gh release create` (nie do repo).

## Mapa kodu (`scripts/`)
Duże ekrany są podzielone na **łańcuchy `extends`**: każda część dziedziczy po poprzedniej, więc widzi tylko jej funkcje.
Cały stan (zmienne, stałe, sygnały) leży w pierwszym pliku łańcucha. Nowa funkcja trafia do części, której dotyczy,
ale nie może wołać funkcji z części późniejszych (Godot zgłosi „Function not found in base self”).

| Plik | Zawartość |
|---|---|
| `main.gd` | Główna scena: składa świat, statek, HUD, dok; spawn patroli/fal (`_update_patrols`, `_spawn_wave`), oblężenie, boss, dokowanie/wylot, sygnały świata. |
| `game_state.gd` | Autoload: surowce, ładownia, `BASE_STATS`/`STAT_NAMES`/`PERCENT_STATS`, `recalc_stats`, poziomy ulepszeń, sloty, zapis/wczytanie, ustawienia, klawisze `KEY_ACTIONS`. |
| `upgrades.gd` | Dane ulepszeń: `LIST` (siatka), `ARMORY`, `LAB`, `EMPIRE`, drzewko `TREE`, koszty (`RING_MULT`, growth). |
| `world.gd` → `world/` | Mapa USA. Łańcuch: `world/base.gd` (stan, stałe `TILE_DEFS`/`DEP_DEFS`/wieżyczki, zapytania, sektory, łup, zapis) → `art.gd` (rysowanie kafelków, statyczne `paint_terrain`, minimapa) → `damage.gd` (niszczenie, odbudowa, ekspansja Imperium) → `defense.gd` (wieżyczki sojusznicze, rakiety) → `overlay.gd` (skaner, wieżyczki, okręgi zasięgu, granice) → `world.gd` (`generate`, zapis, `_process`). |
| `upgrade_screen.gd` → `dock/` | Ekran Statku Matki. Łańcuch: `dock/base.gd` (stan, układ, pomocniki tekstu/kosztów/paneli, nakładki) → `grid.gd` (siatka ulepszeń, dymek) → `panels.gd` (oprawa, magazyn, WYLOT, PARAMETRY, ROZKAZY, toasty) → `armory.gd` → `bridge.gd` (Sterownia) → `empire.gd` → `lab.gd` → `upgrade_screen.gd` (`open`, `_process`, wejście, `_draw`). |
| `ship.gd` | Statek gracza: sterowanie (dryf, drift), laser górniczy, paliwo, kadłub/tarcza. |
| `enemies.gd` | Myśliwce (`fighter`/`laser`/`gunner`) i czołgi (`tank`), pociski i pociski artyleryjskie; stałe AI na górze pliku. |
| `weapons.gd` | Rakiety (Q), drony, karabiny, łańcuch błyskawic, detonacja. |
| `escorts.gd`, `wingmen.gd`, `transit.gd`, `miners.gd` | Sojusznicy: myśliwiec towarzyszący (Zbrojownia), myśliwce Imperium (klawisz 4), statki tranzytowe, statki wydobywcze. |
| `mothership.gd` | Statek Matka: strefa dokowania, obrona rakietami. |
| `hud.gd` | HUD w locie: paski, ładownia, minimapa, statystyki, znaczniki wrogów, NAMIERZONY, podgląd łupu. |
| `fx.gd` | Efekty: liczby obrażeń, wybuchy, iskry, pierścienie, wstrząs, promienie. |
| `boss_game.gd` | Osobna minigra-strzelanka z bossem (główna gra w pauzie). |
| `menu.gd` | Menu główne z żywą mapą w tle, sloty, opcje, sterowanie, osiągnięcia. |
| `pause_menu.gd` | Pauza (ESC): wznów / powrót na Matkę / opcje / sterowanie / osiągnięcia. |
| `options.gd` | Wspólna logika OPCJI dla menu i pauzy (`ITEMS`, `NAMES`, `change`, `value_text`, suwaki). |
| `tutorial.gd`, `quests.gd`, `achievements.gd` | Samouczek (pop-upy), rozkazy Imperium Vex (rodzaje: event/metro/rebuild/collect; logika w `game_state.gd` `refresh_quests`), osiągnięcia (autoload, `user://achievements.cfg`). Nazwy miast wyświetlać przez `GameState.city_name(s)`. |
| `training.gd` | Szkolenie w Roswell (TUTORIAL w menu): `GameState.training` = bez zapisu, gotowy statek (`LEVELS`), własne ceny (`COSTS`), obszar `AREA`, tarcza miasta (`world.protected`), fazy scenariusza, okienka (tutorial.gd w trybie `custom`), boss OBIEKT-51 (wpis `"ext"` w `enemies.fighters`), DANGER!, transmisja Vex (`VEX_TEXT` - do podmiany), osiągnięcie `training`. Test: `tools/test/training_flow.gd`. |
| `sectors.gd` | 9 sektorów 3×3 po 160×160 kafelków, metropolie, Dystrykt Federalny. |
| `style.gd`, `mesh_painter.gd`, `crt.gd`, `audio.gd`, `splash.gd` | Styl i pomocniki rysowania, wsadowe rysowanie kafelków do jednej siatki, filtr CRT/jaskrawość, dźwięk, ekran startowy. |

## Balans: okrągłe statystyki (życzenie gracza)
- Każda statystyka ma krok (`GameState.STAT_STEPS` / `stat_step`: 10 dla dużych, 5% dla procentów itp.). Bazy w `BASE_STATS`
  i przyrosty `effects` w `upgrades.gd` muszą być jego wielokrotnościami. Mistrzostwo (`mastery_extra`) to ok. +25% efektu,
  zaokrąglone do kroku; `"no_mastery": true` wyłącza je dla węzła. Koszty nie muszą być okrągłe.
- Po każdej zmianie liczb: `run_test.ps1 -Script res://tools/test/balance.gd` → musi pokazać „niezaokrąglonych wartości: 0”;
  wypisuje też tabelę baza → maksimum i statystyki slotu 1.
- Wrogowie rosną z siłą gracza: `enemies.gd` `power_scale()` (stałe `SCALE_*`). Syfony paliwa/kadłuba mają limit na sekundę (`ship.gd` `SIPHON_*`).

## Gdzie co zmieniać (skróty)
- Balans statku/ulepszeń: `upgrades.gd` (effects/cost), `game_state.gd` `BASE_STATS` + `STAT_STEPS`.
- Wrogowie: stałe w `enemies.gd`, liczba i tempo spawnu w `main.gd` (`MAX_PATROLS`, `MAX_ENEMIES`, `_update_patrols`, `_spawn_wave`).
- Wieżyczki miast/rakiety: stałe w `world/base.gd` (`TURRET_RANGE`, `MISSILE_*`), logika w `world.gd` `_process` i `world/defense.gd`.
- Wydajność rysowania mapy: `world/art.gd` + `mesh_painter.gd`; okręgi zasięgu: `world/overlay.gd` (`RING_FULL_DETAIL`, `RING_MAX`).
- Szukanie funkcji: `Grep "^func nazwa"` po `scripts/` zamiast czytania całych plików.
