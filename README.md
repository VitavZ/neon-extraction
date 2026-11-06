# Neon Extraction — prototyp (Godot 4.7)

Otwórz folder `neon-extraction` w Godocie i naciśnij F5.

## Sterowanie
- Mysz: statek obraca się w stronę kursora
- PPM lub W: ciąg (statek zachowuje pęd, jak w Nova Drift)
- S: hamulec, A / D: manewry boczne
- Spacja: drift (przytrzymaj, by naładować; puść, by wystrzelić się w stronę kursora)
- LPM: laser górniczy (niszczy kafelek pod kursorem, w zasięgu lasera)
- Kółko myszy: zoom
- E: dokowanie przy statku matce / wylot / wejście do walki z bossem
- P: parametry statku (w doku)

## Pętla gry
Wylatujesz ze statku matki, niszczysz kafelki laserem, surowce trafiają
do ładowni. Pod częścią kafelków są złoża (miedź, żelazo, złoto, uran, neonit). Wracasz [E],
rozładowujesz i kupujesz ulepszenia w siatce (węzeł odblokowuje sąsiadów).
Miasta i góry dalej od postoju Matki bronią wieżyczki. Zniszczenie statku = utrata ładunku.
Postęp zapisuje się przy każdym dokowaniu (user://neon_extraction_save_N.json, gdzie N to slot). Obok leży kopia poprzedniego zapisu (.bak), wczytywana, gdy główny plik jest uszkodzony.

## Mapa USA
Świat to 6 sektorów po 128x128 kafelków (scripts/sectors.gd), każdy z metropolią; między sąsiednimi
sektorami lata się swobodnie. Węzeł Sterownia pozwala przenosić Statek Matkę.
Teren w scripts/us_map_data.gd generuje tools/bake_us_map.gd z danych: AWS Terrain Tiles (Mapzen, m.in.
3DEP/USGS, SRTM, GMTED, ETOPO1) oraz Natural Earth (domena publiczna).

## Metropolie i bossowie
Zniszczenie 75% Nowego Jorku uruchamia minigrę scripts/boss_game.gd (strzelanka z bossem, +1 Punkt Chwały).
Różowy punkt w mieście (wejście klawiszem E) pozwala powtórzyć walkę po porażce i po zwycięstwie (nagroda tylko za pierwsze). Zniszczenie 100% dowolnej metropolii też daje +1 Punkt Chwały.

## Pliki
- scripts/game_state.gd — surowce, ładownia, statystyki, zapis (autoload GameState)
- scripts/upgrades.gd — definicja siatki ulepszeń (łatwo dodać nowe węzły)
- scripts/world.gd — generowanie mapy, kafelki, złoża, wieżyczki, minimapa
- scripts/ship.gd — sterowanie i laser
- scripts/mothership.gd, fx.gd, hud.gd, upgrade_screen.gd, main.gd
