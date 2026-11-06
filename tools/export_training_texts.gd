extends SceneTree
## Generuje teksty_szkolenia.txt (wszystkie teksty szkolenia w Roswell do poprawienia przez autora).
## Okienka i cele ćwiczeń są czytane wprost ze stałych training.gd; pozostałe napisy są tu przepisane z kodu.
## Uruchomienie: run_test.ps1 -Script res://tools/export_training_texts.gd

const Tr = preload("res://scripts/training.gd")

## Kiedy pokazuje się każde okienko (indeks = STEPS).
const WHEN := [
	"na start szkolenia, w doku Statku Matki.",
	"w locie, ćwiczenie sterowania 1/8 (zalicza: pełny obrót statku kursorem).",
	"w locie, ćwiczenie 2/8 (zalicza: 2 s lotu z włączonym ciągiem).",
	"w locie, ćwiczenie 3/8 (zalicza: hamowanie hamulcem lub pełnym stopem z rozpędu).",
	"w locie, ćwiczenie 4/8 (zalicza: 1 s lotu w bok).",
	"w locie, ćwiczenie 5/8 (zalicza: puszczenie naładowanego driftu).",
	"w locie, ćwiczenie 6/8 (zalicza: przybliżenie lub oddalenie kółkiem).",
	"w locie, ćwiczenie 7/8 (zalicza: 3 rozbite kafelki).",
	"w locie, ćwiczenie 8/8 (zalicza: odpalenie rakiety).",
	"w locie, po ćwiczeniach sterowania. Podświetla pasek ładowni.",
	"w doku, gdy w magazynie są surowce na ulepszenie lasera.",
	"po kupieniu ostatniego poziomu Mocy lasera (tarcza Roswell gaśnie).",
	"po zniszczeniu całego Roswell.",
	"w locie, po odblokowaniu Odbudowy.",
	"w locie, gdy myśliwce atakują Statek Matkę (po odbudowie 80% Roswell).",
]

## [gdzie / kiedy, tekst]
const OTHER := [
	["Menu główne - przycisk", "TUTORIAL"],
	["Nagłówek okienek", "SZKOLENIE"],
	["Raport w doku na start", "Szkolenie: Roswell. Powodzenia, Kadecie."],
	["Nagłówek doku (sektor)", "ROSWELL (SZKOLENIE)"],
	["Napis na mapie nad miastem", "ROSWELL"],
	["Panel pod minimapą - tytuł", "OBSZAR SZKOLENIA"],
	["Panel pod minimapą - paski", "ZNISZCZENIE ROSWELL / ODBUDOWA ROSWELL"],
	["Strzałka przy krawędzi ekranu", "ROSWELL"],
	["Napis nad statkiem po ćwiczeniu", "ZALICZONE!"],
	["Komunikat po ćwiczeniu (dalej cel ćwiczenia)", "Zaliczone: ..."],
	["Cel na dole ekranu - ćwiczenia", "STEROWANIE 1/8: <cel ćwiczenia>  —  45%"],
	["Cel na dole ekranu - zbieranie", "CEL: zbierz 0/40 biomasy i 0/30 kamienia, potem wróć do Statku Matki"],
	["Cel na dole ekranu - ulepszenie (w locie)", "CEL: zadokuj [{dock}] i kup ostatni poziom MOCY LASERA"],
	["Cel na dole ekranu - niszczenie", "CEL: zniszcz Roswell  —  40%"],
	["Cel na dole ekranu - odblokowanie", "CEL: wróć na Statek Matkę i odblokuj ODBUDOWĘ"],
	["Cel na dole ekranu - odbudowa", "CEL: odbuduj Roswell narzędziem [{tool3}]  —  35% / 80%"],
	["Cel na dole ekranu - obrona", "CEL: obroń Statek Matkę  —  myśliwce: 5"],
	["Duży napis po ćwiczeniach", "STEROWANIE OPANOWANE / Czas na prawdziwe zadanie"],
	["Duży napis po zgaśnięciu tarczy (w locie)", "TARCZA ROSWELL ZGASŁA / Zniszcz miasto"],
	["Raport w doku po zakupie lasera", "Laser przebije tarczę Roswell. Leć zniszczyć miasto!"],
	["Duży napis po zniszczeniu", "ROSWELL ZNISZCZONE / Wróć na Statek Matkę i odblokuj Odbudowę"],
	["Raport w doku, gdy łup przepadł", "Imperium przysłało surowce na Odbudowę."],
	["Duży napis - atak na Matkę", "ZIEMIA KONTRATAKUJE! / Statek Matka pod ostrzałem — leć jej bronić!"],
	["Duży napis - atak odparty", "ATAK ODPARTY / Statek Matka ocalał"],
	["Próba dokowania od ataku do końca", "HANGAR ZABLOKOWANY — nie ma odwrotu!"],
	["Pauza -> powrót na Matkę od ataku do końca", "Nie ma odwrotu — walcz!"],
	["Pusty bak (cała gra) - duży napis", "BRAK PALIWA! / Reaktor wybuchnie za 5 s"],
	["Pusty bak (cała gra) - pasek paliwa", "PALIWO — PUSTO! WYBUCH ZA 5 s"],
	["Ostrzeżenie - wielki napis", "DANGER!"],
	["Ostrzeżenie - podpis", "NIEZIDENTYFIKOWANY OBIEKT NA KURSIE KOLIZYJNYM"],
	["Boss - nazwa (duży napis i pasek)", "OBIEKT-51"],
	["Boss - podpis przy wejściu", "Ziemska broń z hangarów Strefy 51"],
	["Boss - pod paskiem, gdy pancerz się łata", "PANCERZ REGENERUJE SIĘ"],
	["Boss - działo główne (duży napis)", "DZIAŁO GŁÓWNE / OBIEKT-51 ładuje rdzeń — nie ma ucieczki"],
	["Transmisja - nagłówek", "TRANSMISJA PRIORYTETOWA  //  KANAŁ DOWÓDZTWA"],
	["Transmisja - tytuł", "IMPERIUM VEX"],
	["Transmisja - przyciski", "DALEJ  [ENTER]  /  ODCZYTANO  [ENTER]"],
	["Koniec - tytuł", "SZKOLENIE UKOŃCZONE"],
	["Koniec - treść", "Poznałeś wydobycie, ulepszenia, niszczenie i odbudowę miast. Prawdziwa inwazja czeka - START w menu głównym."],
	["Koniec - osiągnięcie", "OSIĄGNIĘCIE: ABSOLWENT ROSWELL"],
	["Koniec - przycisk", "MENU GŁÓWNE  [ENTER]"],
	["Osiągnięcie - nazwa", "Absolwent Roswell"],
	["Osiągnięcie - opis", "Ukończ szkolenie w Roswell (TUTORIAL w menu)."],
]


func _initialize() -> void:
	var s := "TEKSTY SZKOLENIA W ROSWELL (TUTORIAL w menu) - scripts/training.gd\n"
	s += "=====================================================================\n\n"
	s += "Jak edytować:\n"
	s += "- Zmieniaj tylko TYTUŁ, TREŚĆ i teksty w częściach 2-4. Nagłówki \"=== ... ===\" i linie \"Kiedy się pokazuje\" zostaw.\n"
	s += "- Pusta linia w treści = nowy akapit w okienku.\n"
	s += "- W nawiasach klamrowych są klawisze - gra sama wstawia klawisz ustawiony w opcjach, np. {dock} -> E.\n"
	s += "  Dostępne: {thrust} ciąg, {brake} hamulec, {stop} pełny stop, {left} / {right} manewr w bok, {drift} drift,\n"
	s += "  {dock} dokowanie/wylot, {rocket} rakieta, {tool3} odbudowa, {pause} pauza.\n"
	s += "- Tekst w nawiasach kwadratowych, np. [{dock}] albo [LPM], rysuje się jako klawisz w ramce.\n"
	s += "- Linia \"[klawisze] :: opis\" to wiersz listy sterowania: klawisze po lewej, opis obok.\n"
	s += "- Okienko ma ok. 620 px szerokości - długi tekst po prostu urośnie w górę.\n"
	s += "- Napisy \"TYTUŁ / podpis\" w części 3 to duży napis na środku ekranu i mniejszy pod nim.\n\n\n"
	s += "########## CZĘŚĆ 1: OKIENKA (pop-upy) ##########\n\n"
	var n: int = Tr.STEPS.size()
	for i in n:
		var st: Array = Tr.STEPS[i]
		s += "=== OKIENKO %d/%d ===\n" % [i + 1, n]
		s += "Kiedy się pokazuje: %s\n" % (WHEN[i] if i < WHEN.size() else "?")
		s += "TYTUŁ: %s\n" % st[0]
		s += "TREŚĆ:\n%s\n\n\n" % st[1]
	s += "########## CZĘŚĆ 2: CELE ĆWICZEŃ STEROWANIA (pasek na dole ekranu) ##########\n\n"
	for i in Tr.DRILLS.size():
		s += "ĆWICZENIE %d: %s\n" % [i + 1, Tr.DRILLS[i][1]]
	s += "\n\n########## CZĘŚĆ 3: POZOSTAŁE NAPISY W SZKOLENIU ##########\n\n"
	for o in OTHER:
		s += "%s:\n%s\n\n" % [o[0], o[1]]
	s += "\n########## CZĘŚĆ 4: TRANSMISJA OD IMPERIUM VEX (po przegranej z bossem) ##########\n\n"
	s += Tr.VEX_TEXT + "\n"
	var f := FileAccess.open("res://teksty_szkolenia.txt", FileAccess.WRITE)
	f.store_string(s)
	f.close()
	print("[TEST] zapisano teksty_szkolenia.txt (%d okienek)" % n)
	quit()
