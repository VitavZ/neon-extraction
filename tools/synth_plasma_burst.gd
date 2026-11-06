extends SceneTree
## Narzędzie deweloperskie: syntezuje audio/sfx/plasma_burst.wav (wyrzut plazmy przy zrywie z driftu).
## Warstwy: opadający sub-bas (uderzenie), piłowy "zap" w dół, szum odrzutu z zamykanym filtrem,
## trzaski plazmy i cichy syk na końcu. Całość przez miękkie przesterowanie.
## Uruchomienie: godot --headless --path . --script tools/synth_plasma_burst.gd

const RATE := 44100
const LEN := 0.95
const OUT := "res://audio/sfx/plasma_burst.wav"


func _initialize() -> void:
	var n := int(RATE * LEN)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph_sub := 0.0
	var ph_saw := 0.0
	var lp := 0.0
	var lp2 := 0.0
	var crack := 0.0
	for i in n:
		var t := float(i) / RATE
		# sub-bas: 130 Hz spada do 38 Hz, szybki atak
		var f_sub := 38.0 + 92.0 * exp(-t * 9.0)
		ph_sub += TAU * f_sub / RATE
		var sub := sin(ph_sub) * exp(-t * 5.5) * minf(1.0, t * 400.0)
		# zap: piła 1100 Hz -> 110 Hz
		var f_saw := 110.0 + 990.0 * exp(-t * 11.0)
		ph_saw = fmod(ph_saw + f_saw / RATE, 1.0)
		var saw := (ph_saw * 2.0 - 1.0) * exp(-t * 7.0)
		# szum odrzutu: filtr dolnoprzepustowy zamyka się z czasem
		var white := rng.randf_range(-1.0, 1.0)
		var cut := clampf(0.55 * exp(-t * 4.0) + 0.03, 0.0, 1.0)
		lp += (white - lp) * cut
		var hiss := lp * exp(-t * 6.0) * 1.4
		# długi syk na wybrzmienie
		lp2 += (white - lp2) * 0.08
		var tail := lp2 * exp(-t * 3.0) * 0.5
		# trzaski plazmy
		if rng.randf() < 0.004 * exp(-t * 3.0) * 60.0 / 60.0:
			crack = rng.randf_range(0.4, 0.9) * (1.0 if rng.randf() < 0.5 else -1.0)
		crack *= 0.86
		var s := sub * 0.95 + saw * 0.32 + hiss * 0.55 + tail * 0.3 + crack * 0.35
		buf[i] = tanh(s * 1.7)
	# normalizacja do -1 dBFS i łagodne wyciszenie końcówki
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	var gain := 0.89 / maxf(peak, 0.001)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var fade := clampf((n - i) / (RATE * 0.05), 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(buf[i] * gain * fade, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	var err := w.save_to_wav(ProjectSettings.globalize_path(OUT))
	print("zapisano ", OUT, " err=", err, " próbek=", n)
	quit()
