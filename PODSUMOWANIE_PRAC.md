# Neon Extraction – podsumowanie prac z Claude (stan na 2026-11-06)

Godot 4.7.2, GDScript, wszystko rysowane w `_draw()` (kolory HDR, styl neon/synthwave). Autoloady: `GameState`, `Audio`, `Achievements`. Teksty w grze po polsku.

## Zasady testowania (WAŻNE)
- Prawdziwy postęp gracza jest w **slocie 1** (sloty 2 i 3 też istnieją) – nigdy ich nie nadpisywać.
- Testy tylko na **slocie 4** (kopia slotu 1), potem usunąć pliki slotu 4: `""`, `.bak`, `.tmp`, `.v1_backup`.
- Przed testem zrobić kopię `settings.cfg` i `achievements.cfg`, po teście przywrócić; sprawdzić hash slotu 1.
- Dane: `%APPDATA%\Godot\app_userdata\Neon Extraction`.
- Uruchamianie testu: `C:\Users\Kamil\Desktop\Godot\Godot_v4.7.2-stable_win64_console.exe --path . --script res://test.gd -- <katalog_na_zrzuty>` (test.gd kopiowany do katalogu projektu i usuwany po teście; `extends SceneTree`, zrzuty przez `get_viewport().get_texture().get_image().save_png`).
- Sprawdzenie składni: `--headless --check-only --script res://scripts/X.gd` (błąd „Identifier not found: GameState” jest tam normalny).
- PowerShell: edycje plików UTF-8 bez BOM; nie nazywać funkcji `R`/`Rp` (aliasy).

## Repozytorium i wydania
- Prywatne repo: https://github.com/VitavZ/neon-extraction (gałąź `main`). Aktualna wersja: **v0.3.0** (`menu.gd: VERSION`, wersje w `export_presets.cfg`).
- `git` nie jest w PATH – używać tego z GitHub Desktop: `$env:PATH = "C:\Users\Kamil\AppData\Local\GitHubDesktop\app-3.6.10\resources\app\git\cmd;$env:PATH"`; push przez `git -c credential.helper= -c "credential.helper=!gh auth git-credential" push`.
- Eksport: `Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" <ścieżka.exe>` (i `"macOS" <ścieżka.zip>`). Buildy w `..\builds\vX.Y.Z\`, wrzucane jako GitHub Release (`gh release create`), nie do repo.

## Zrobione funkcje (w kolejności)
1. **Podgląd łupu przy kopaniu** – panel nad kafelkiem (`hud._draw_mine_info`, `world.tile_drops_preview`, `world.hidden_deposit_name`).
2. **Znacznik „NAMIERZONY”** – czerwona ramka ekranu i licznik pościgu (`hud._draw_tracking`, `enemies.chasers()`).
3. **Strzałki krawędziowe do dalekich myśliwców** (`hud._draw_enemy_markers`, `_edge_arrow`).
4. **Okręgi zasięgu wieżyczek** – wyraźniejsze, a potem zoptymalizowane: kolejka `_ring_q`, pełny wygląd 6 najbliższych, max 12 (`RING_FULL_DETAIL`, `RING_MAX`).
5. **Mac/Retina**: `window/dpi/allow_hidpi.macos=false` w project.godot.
6. **Opcja JAKOŚĆ OBRAZU** (WYSOKA/ŚREDNIA/NISKA: MSAA 4x/2x/brak, NISKA = render 1600×900) – `GameState.apply_quality()`, menu i pauza.
7. **Statek Matka**: zestrzelone przez nią myśliwce nie dają łupu (`looted=false` w `damage_in_radius`), zasięg obrony 700.
8. **Myśliwce pojawiają się poza ekranem** (`enemies.offscreen_dist()`).
9. **Miedź**: +15% progu na złoże tylko z miedzią (`COPPER_BONUS`, bez zmiany kolejności losowania świata).
10. **Mniej resztek broni z myśliwców** (1–2, laserowy +1).
11. **Detonacja** (gałąź lasera): rozbity kafelek może wybuchnąć, reakcja łańcuchowa do 5 pokoleń (`weapons.gd`: `_on_tile_broken`, `_detonate`; sygnał `world.tile_broken`). Węzły: detonate, det_chance, det_power, det_radius.
12. **Myśliwiec towarzyszący** (Zbrojownia, karta MYŚLIWIEC) – `scripts/escorts.gd`. Odblokowanie daje od razu poziom 1/2 „Liczba myśliwców” (pole `grants`). Leci w szyku, strzela z gracza, wiązka kończy się w punkcie trafienia gracza (`process_priority = 10`). 25%→50% mocy lasera i kadłuba (z Mistrzostwem).
13. **Optymalizacja gęstych miast** (33→~55 FPS): wieżyczki rysowane hurtem przez `canvas_item_add_triangle_array`, iskry hurtem w `fx.gd`, max 50 liczb obrażeń.
14. **Rakiety ręczne**: klawisz Q (akcja `rocket`), zapas 3, ładują się same; mniejsze obrażenia (baza 10, +17/poziom). `weapons.fire_rocket()`.
15. **Koszty w Zbrojowni mieszczą się w ramkach** (`_cost_inline` z `max_w`/`wrap`).
16. **Drzewko ulepszeń jak w PoE/Nova Drift**: tabela `Upgrades.TREE` (id → [rodzic, pozycja na ekranie]). Węzeł dostępny, gdy kupiony rodzic. Przewody tylko rodzic→dziecko, gałęzie z odstępami. Koszt (pierścień) nadal z pola `pos` w `LIST`, więc ceny się nie zmieniły.
17. **11 nowych ulepszeń**: laser_combat (`fighter_damage`), drill2, laser_focus, hull_siphon (leczenie za kafelek), armor2, shield_cap, fuel_cell, strafe2, salvage (szansa na rzadki surowiec), yield2, power_mult2. Skaner przeniesiony przed Wymiarową ładownię.
18. **Czołgi** (`kind: "tank"` w `enemies.fighters`): jeżdżą po lądzie (`world.ground_at`, `world.tank_point`), wieża za graczem, pociski artyleryjskie po łuku z celownikiem na ziemi (`enemies.shells`), ślady gąsienic, łup, osobny licznik w HUD. Spawn w `main._update_patrols` od 3. wyprawy.

## Ważne miejsca w kodzie
- `scripts/upgrades.gd` – LIST, ARMORY (bronie: rockets, drones, guns, escort), LAB, EMPIRE, `TREE`, `parent_of`, `display_pos`.
- `scripts/game_state.gd` – BASE_STATS, STAT_NAMES, PERCENT_STATS, `is_reachable`, `requires_met`, `recalc_stats` (obsługa `grants`), klawisze `KEY_ACTIONS`.
- `scripts/world.gd` – teren, wieżyczki, okręgi zasięgu, pociski wieżyczek, `_friendlies()` (cele pocisków wroga, w tym eskorta).
- `scripts/enemies.gd` – myśliwce (fighter/laser/gunner) i czołgi.
- `scripts/weapons.gd` – rakiety, drony, karabiny, błyskawica, detonacja.
- `scripts/hud.gd`, `scripts/upgrade_screen.gd`, `scripts/fx.gd`, `scripts/main.gd`.

## Otwarte / do obserwacji
- Nic nie testowane na Macu.
- Namiernik bojowy na maksimum daje +100% obrażeń vs myśliwce – może być za mocny.
- Czołgi i nowe ulepszenia (Szperacz, Rekonstrukcja) nie były jeszcze sprawdzone w normalnej grze przez gracza.
