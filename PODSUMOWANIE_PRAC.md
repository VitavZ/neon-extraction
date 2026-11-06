# Neon Extraction – historia prac z Claude (stan na 2026-11-06)

Zasady pracy, testy, git i mapa kodu są w **CLAUDE.md** (wczytywany automatycznie). Tu tylko historia i otwarte sprawy.
Aktualna wersja: **v0.3.1**.

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
19. **Porządki w kodzie (2026-11-06)**: `upgrade_screen.gd` podzielony na `scripts/dock/` (łańcuch extends), `world.gd` na `scripts/world/`; wspólne opcje w `options.gd`; pomocniki `ease_out`/`chamfer_pts`/`closed` w `Style`; usunięty martwy kod; zestaw testowy `tools/test/` (bezpieczne uruchamianie, test dymny, porównanie zrzutów); `CLAUDE.md` z mapą kodu. Wygląd i działanie bez zmian (zrzuty doku identyczne co do piksela).
20. **Balans (2026-11-06, łagodnie)**: wszystkie statystyki okrągłe po każdym zakupie (krok na statystykę + zaokrąglana premia Mistrzostwa, kontrola `tools/test/balance.gd`); wrogowie dostają do x1,8 kadłuba i x1,5 obrażeń zależnie od mocy lasera i wytrzymałości gracza (`enemies.power_scale`); paliwo ma znaczenie: oszczędność maks. 40% (było 75%), syfon paliwa maks. 1/s, kadłub z kafelków maks. 10/s, bez paliwa nie działa naprawa, a ubytek kadłuba to 1%/s; rakiety: przeładowanie min. 4 s (było 1,25 s), drony 0,3 s; laser maks. 300 (było 325), baza 20. Rozprysk lasera działa też przy celowaniu w zniszczony kafelek.
21. **Rozkaz „Odbuduj Nowy Jork”** (`quests.gd`, rodzaj `rebuild`): pojawia się po „Zniszcz Nowy Jork”, zalicza się przy 80% kafelków metropolii będących kafelkami Imperium (odbudowa i rozrost; liczy `world/base.gd` `metro_imperial` → `GameState.set_metro_rebuilt`), nagroda 50 PL. Potem miasto nazywa się „NOWSZY JORK” wszędzie (`GameState.city_name`). Test: `tools/test/quest_rebuild_ny.gd`.
22. **Szkolenie w Roswell** (TUTORIAL w menu, `scripts/training.gd`): osobna gra bez zapisu na obszarze 100x96 kafelków; zbierz 40 biomasy + 30 kamienia -> ostatni poziom Mocy lasera (80) gasi tarczę Roswell -> zniszcz miasto -> odblokuj Odbudowę -> odbuduj 80% -> myśliwce atakują Matkę -> 6 s -> DANGER! -> OBIEKT-51 (lasery, rakiety, karabiny; pancerz nie schodzi poniżej 50%, po 45 s działo główne) -> transmisja Imperium Vex (lorem ipsum w `VEX_TEXT`) -> „Szkolenie ukończone” + osiągnięcie „Absolwent Roswell”. W teście gracz robiący uniki traci kadłub po ok. 23 s.
23. **Szkolenie - poprawki**: okienka nie wyprzedzają postępu (błąd z dokowaniem bez surowców); jeden obszar (minimapa, panel i mapa tylko z Roswell, miasta i wieżyczki wokół usunięte); 8 ćwiczeń sterowania z okienkami, zaliczanych dopiero po wykonaniu (obrót, ciąg, hamowanie, manewr, drift, zoom, laser, rakieta). Wszystkie teksty szkolenia: `teksty_szkolenia.txt`.

## Otwarte / do obserwacji
- Szkolenie: tekst transmisji Vex (`training.gd` `VEX_TEXT`) czeka na historyjkę; scenariusz nie był grany ręcznie.
- Balans z punktu 20 nie był jeszcze sprawdzony w normalnej grze – do dostrojenia stałe `SCALE_*` w enemies.gd i limity syfonów w ship.gd.
- Nic nie testowane na Macu.
- Namiernik bojowy na maksimum daje +100% obrażeń vs myśliwce – może być za mocny.
- Czołgi i nowe ulepszenia (Szperacz, Rekonstrukcja) nie były jeszcze sprawdzone w normalnej grze przez gracza.
