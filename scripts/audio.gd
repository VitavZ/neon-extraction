extends Node
## Autoload "Audio": muzyka (menu + playlista w grze) i efekty dźwiękowe.
## Efekty (audio/sfx/*.wav) zostały zsyntezowane specjalnie dla gry - są w pełni wolne od opłat.

const MENU_TRACK := "res://audio/music/system_standby.mp3"
const GAME_PLAYLIST := [
	"res://audio/music/neon_pursuit.mp3",
	"res://audio/music/neon_horizon.mp3",
	"res://audio/music/neon_laser.mp3",
	"res://audio/music/neon_heist.mp3",
	"res://audio/music/neon_wave.mp3",
]
const SFX_DIR := "res://audio/sfx/"
const LOOPS := ["laser_loop", "abduct_loop", "rebuild_loop", "engine_loop"]
## Minimalny odstęp między kolejnymi odtworzeniami tego samego efektu (s) - żeby nie było kakofonii.
const MIN_GAP := {"tile_break": 0.05, "pickup": 0.045, "gun_shot": 0.06, "drone_shot": 0.05,
	"explosion": 0.08, "enemy_shot": 0.06, "ship_hit": 0.1, "shield_hit": 0.1, "ui_hover": 0.03, "imperial": 0.15, "hit_tick": 0.05, "blast_pop": 0.04, "blast_shatter": 0.05, "blast_mid": 0.07}
const SFX_VOLUME_DB := {"laser_loop": -10.0, "abduct_loop": -9.0, "rebuild_loop": -10.0, "pickup": -8.0,
	"tile_break": -5.0, "ui_hover": -8.0, "gun_shot": -6.0, "drone_shot": -6.0, "missile_warning": -3.0, "hit_tick": -15.0, "blast_pop": -5.0, "blast_shatter": -5.0, "blast_mid": -2.0}

var music: AudioStreamPlayer
var music_mode := ""          # "menu" / "game"
var playlist_idx := 0
var sfx_cache: Dictionary = {}
var music_cache: Dictionary = {}
var pool: Array = []
var last_played: Dictionary = {}
var loops: Dictionary = {}    # nazwa pętli -> AudioStreamPlayer
var fade_tween: Tween
var spectrum: AudioEffectSpectrumAnalyzerInstance
var bass_avg := 0.0
var beat_pulse := 0.0         # 0..1: siła uderzeń basu w grającym utworze


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	add_child(music)
	music.finished.connect(_on_music_finished)
	for k in 16:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		pool.append(p)
	for n in LOOPS:
		var lp := AudioStreamPlayer.new()
		lp.bus = "SFX"
		lp.volume_db = SFX_VOLUME_DB.get(n, 0.0)
		add_child(lp)
		loops[n] = lp
	apply_volumes()
	# analiza widma muzyki (rytm dla neonów); włączana tylko na czas walki z bossem
	var mi := AudioServer.get_bus_index("Music")
	AudioServer.add_bus_effect(mi, AudioEffectSpectrumAnalyzer.new())
	spectrum = AudioServer.get_bus_effect_instance(mi, 0) as AudioEffectSpectrumAnalyzerInstance
	AudioServer.set_bus_effect_enabled(mi, 0, false)


## Śledzi bas względem jego własnej średniej, więc działa przy każdej głośności i w każdym utworze.
func _process(delta: float) -> void:
	if music_mode != "boss" or spectrum == null:
		beat_pulse = 0.0
		return
	var m := spectrum.get_magnitude_for_frequency_range(30.0, 160.0)
	var bass := (m.x + m.y) * 0.5
	bass_avg = lerpf(bass_avg, bass, 1.0 - exp(-1.2 * delta))
	var hit := clampf((bass / maxf(bass_avg, 0.0001) - 1.0) / 0.9, 0.0, 1.0)
	beat_pulse = maxf(hit, beat_pulse * exp(-5.0 * delta))


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")


func _db(v: float) -> float:
	return linear_to_db(maxf(clampf(v, 0.0, 1.0), 0.0001))


## Głośności z ustawień (0-100): ogólna, muzyka, efekty.
func apply_volumes() -> void:
	var st := GameState.settings
	var pairs := [["Master", st.get("volume", 80)], ["Music", st.get("music", 70)], ["SFX", st.get("sfx", 80)]]
	for pr in pairs:
		var i := AudioServer.get_bus_index(pr[0])
		if i < 0:
			continue
		var v := float(pr[1]) / 100.0
		AudioServer.set_bus_mute(i, v <= 0.001)
		AudioServer.set_bus_volume_db(i, _db(v))


# ---------------- ładowanie ----------------
# Pliki działają zarówno zaimportowane przez edytor, jak i "surowe" (wczytywane z dysku).

func _load_mp3(path: String) -> AudioStream:
	if music_cache.has(path):
		return music_cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	if s == null and FileAccess.file_exists(path):
		var mp3 := AudioStreamMP3.new()
		mp3.data = FileAccess.get_file_as_bytes(path)
		s = mp3
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = false
	music_cache[path] = s
	return s


func _load_sfx(sfx_name: String) -> AudioStream:
	if sfx_cache.has(sfx_name):
		return sfx_cache[sfx_name]
	var path := SFX_DIR + sfx_name + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	if s == null and FileAccess.file_exists(path):
		s = AudioStreamWAV.load_from_file(path)
	if s is AudioStreamWAV and sfx_name in LOOPS:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	sfx_cache[sfx_name] = s
	return s


# ---------------- muzyka ----------------

func play_menu_music() -> void:
	if music_mode == "menu" and music.playing:
		return
	music_mode = "menu"
	_start_track(MENU_TRACK)


func play_game_music() -> void:
	if music_mode == "game" and music.playing:
		return
	music_mode = "game"
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Music"), 0, false)
	_start_track(GAME_PLAYLIST[playlist_idx])


func stop_music() -> void:
	music_mode = ""
	music.stop()


func play_boss_music(path: String) -> void:
	music_mode = "boss"
	bass_avg = 0.0
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Music"), 0, true)
	_start_track(path)


func _start_track(path: String) -> void:
	var s := _load_mp3(path)
	if s == null:
		return
	if fade_tween:
		fade_tween.kill()
	music.stream = s
	music.volume_db = -30.0
	music.play()
	fade_tween = create_tween()
	fade_tween.tween_property(music, "volume_db", 0.0, 1.2)


func _on_music_finished() -> void:
	if music_mode == "menu" or music_mode == "boss":
		music.play()       # muzyka menu i bossa w pętli
	elif music_mode == "game":
		# kolejny utwór z playlisty, po ostatnim wraca do pierwszego
		playlist_idx = (playlist_idx + 1) % GAME_PLAYLIST.size()
		_start_track(GAME_PLAYLIST[playlist_idx])


# ---------------- efekty ----------------

## Odtwarza efekt. pitch_var - losowe odchylenie wysokości (urozmaicenie powtarzalnych dźwięków).
func play(sfx_name: String, pitch_var := 0.08, volume_db := 0.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var gap: float = MIN_GAP.get(sfx_name, 0.02)
	if now - float(last_played.get(sfx_name, -10.0)) < gap:
		return
	last_played[sfx_name] = now
	var s := _load_sfx(sfx_name)
	if s == null:
		return
	var p: AudioStreamPlayer = null
	for q in pool:
		if not q.playing:
			p = q
			break
	if p == null:
		p = pool[randi() % pool.size()]
	p.stream = s
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.volume_db = volume_db + SFX_VOLUME_DB.get(sfx_name, 0.0)
	p.play()


## Włącza/wyłącza dźwięk zapętlony (laser, porywanie, odbudowa).
func set_loop(loop_name: String, on: bool) -> void:
	var lp: AudioStreamPlayer = loops.get(loop_name)
	if lp == null:
		return
	if on and not lp.playing:
		lp.stream = _load_sfx(loop_name)
		lp.play()
	elif not on and lp.playing:
		lp.stop()


## Silnik statku: wysokość i głośność idą za prędkością i ciągiem.
func set_engine(on: bool, thrust: float, speed_frac: float) -> void:
	set_loop("engine_loop", on)
	if not on:
		return
	var lp: AudioStreamPlayer = loops["engine_loop"]
	lp.pitch_scale = lerpf(lp.pitch_scale, 0.72 + 0.5 * minf(speed_frac, 1.4) + 0.16 * thrust, 0.14)
	lp.volume_db = lerpf(lp.volume_db, lerpf(-27.0, -13.0, clampf(thrust * 0.75 + speed_frac * 0.35, 0.0, 1.0)), 0.14)


func stop_loops() -> void:
	for n in loops:
		loops[n].stop()
