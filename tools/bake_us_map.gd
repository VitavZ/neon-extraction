extends SceneTree
## Narzędzie deweloperskie: zamienia dane geograficzne na mapę gry (scripts/us_map_data.gd).
## Dane: wysokości AWS Terrain Tiles (terrarium, zoom 5) i jeziora/rzeki Natural Earth (50m).
## Uruchomienie:
##   godot --headless --path . --script tools/bake_us_map.gd -- <folder_z_danymi>
## W folderze: tiles/5_X_Y.png, ne_50m_lakes.geojson, ne_50m_rivers_lake_centerlines.geojson.
## Obok danych powstaje podgląd preview.png.

const Sectors = preload("res://scripts/sectors.gd")
const OUT := "res://scripts/us_map_data.gd"

enum { DEEP, OCEAN, RIVER, SAND, PLAINS, FOREST, MOUNTAIN, SNOW, CITY }

const PREVIEW := [Color(0.05, 0.1, 0.4), Color(0.1, 0.3, 0.7), Color(0.2, 0.7, 0.95), Color(0.9, 0.75, 0.4),
	Color(0.55, 0.8, 0.3), Color(0.1, 0.5, 0.2), Color(0.5, 0.35, 0.6), Color(0.95, 0.95, 1.0), Color(1.0, 0.2, 0.7)]

## Mniejsze miasta: [nazwa, długość, szerokość, promień w kafelkach].
const TOWNS := [
	["Portland", -122.7, 45.5, 3.0], ["San Francisco", -122.2, 37.7, 3.5], ["Sacramento", -121.5, 38.6, 2.0],
	["San Diego", -117.1, 32.8, 3.0], ["Las Vegas", -115.1, 36.2, 2.5], ["Phoenix", -112.0, 33.5, 3.5],
	["Tucson", -110.9, 32.2, 2.0], ["Salt Lake City", -111.9, 40.7, 2.5], ["Denver", -104.9, 39.7, 3.0],
	["Albuquerque", -106.6, 35.1, 2.0], ["Boise", -116.2, 43.6, 1.5], ["Spokane", -117.4, 47.7, 1.5],
	["Billings", -108.5, 45.8, 1.5], ["El Paso", -106.4, 31.8, 2.0], ["Minneapolis", -93.2, 45.0, 3.0],
	["Milwaukee", -87.95, 43.0, 2.0], ["Detroit", -83.1, 42.4, 3.0], ["St. Louis", -90.2, 38.6, 2.5],
	["Kansas City", -94.6, 39.1, 2.5], ["Omaha", -96.0, 41.3, 1.5], ["Indianapolis", -86.2, 39.8, 2.0],
	["Louisville", -85.8, 38.2, 1.5], ["Cincinnati", -84.5, 39.1, 2.0], ["Columbus", -83.0, 40.0, 2.0],
	["Cleveland", -81.7, 41.4, 2.0], ["Pittsburgh", -80.0, 40.4, 2.0], ["Buffalo", -78.8, 42.8, 1.5],
	["Toronto", -79.5, 43.8, 2.5], ["Montreal", -73.6, 45.5, 2.5], ["Boston", -71.2, 42.3, 3.0],
	["Hartford", -72.7, 41.8, 1.5], ["Philadelphia", -75.2, 40.0, 3.0], ["Baltimore", -76.7, 39.3, 2.0],
	["Washington", -77.1, 38.9, 2.5], ["Richmond", -77.5, 37.5, 1.5], ["Norfolk", -76.4, 36.9, 1.5],
	["Raleigh", -78.7, 35.8, 1.5], ["Charlotte", -80.8, 35.2, 2.0], ["Atlanta", -84.4, 33.8, 3.0],
	["Nashville", -86.8, 36.2, 2.0], ["Memphis", -90.0, 35.1, 2.0], ["Birmingham", -86.8, 33.5, 1.5],
	["New Orleans", -90.2, 30.1, 2.0], ["Jacksonville", -81.7, 30.3, 2.0], ["Orlando", -81.4, 28.5, 2.0],
	["Tampa", -82.4, 28.0, 2.0], ["Houston", -95.4, 29.8, 3.5], ["San Antonio", -98.5, 29.5, 2.0],
	["Austin", -97.7, 30.3, 2.0], ["Oklahoma City", -97.5, 35.5, 2.0], ["Monterrey", -100.3, 25.7, 2.5],
	["Wichita", -97.3, 37.7, 1.5], ["Little Rock", -92.3, 34.7, 1.5], ["Calgary", -114.0, 49.0, 1.5],
	# południowy pas mapy 3x3: Meksyk i Kuba
	["Tijuana", -117.0, 32.5, 2.0], ["Mexicali", -115.5, 32.6, 1.5], ["Ciudad Juarez", -106.45, 31.7, 2.0],
	["Chihuahua", -106.1, 28.6, 2.0], ["Culiacan", -107.4, 24.8, 1.5], ["Torreon", -103.4, 25.5, 1.5],
	["Saltillo", -101.0, 25.4, 1.5], ["Nuevo Laredo", -99.5, 27.5, 1.0], ["Corpus Christi", -97.4, 27.8, 1.5],
	["Havana", -82.4, 23.1, 2.0], ["Nassau", -77.35, 25.05, 1.0], ["Mobile", -88.1, 30.7, 1.0],
]

var images := {}
var data_dir := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Podaj folder z danymi po --")
		quit(1)
		return
	data_dir = args[0]
	var w := Sectors.W
	var h := Sectors.GEO_H
	var total := w * h

	# --- wysokości: średnia i maksimum z 5x5 próbek na kafelek ---
	var avg := PackedFloat32Array()
	var peak := PackedFloat32Array()
	avg.resize(total)
	peak.resize(total)
	for y in h:
		for x in w:
			var s := 0.0
			var m := -99999.0
			for sy in 5:
				for sx in 5:
					var ll: Vector2 = Sectors.lonlat_of(x + (sx + 0.5) / 5.0, y + (sy + 0.5) / 5.0)
					var e := _elevation(ll)
					s += e
					m = maxf(m, e)
			avg[y * w + x] = s / 25.0
			peak[y * w + x] = m

	# --- ocean: tylko to, co poniżej zera i połączone z krawędzią mapy (Dolina Śmierci zostaje lądem) ---
	var sea := PackedByteArray()
	sea.resize(total)
	var stack: Array[int] = []
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if sea[i] == 1 or avg[i] > 0.0:
			continue
		sea[i] = 1
		var cx := i % w
		if cx > 0:
			stack.append(i - 1)
		if cx < w - 1:
			stack.append(i + 1)
		if i >= w:
			stack.append(i - w)
		if i < total - w:
			stack.append(i + w)

	# --- jeziora i rzeki ---
	var lake := PackedByteArray()
	lake.resize(total)
	_rasterize_lakes(lake)
	var river := PackedByteArray()
	river.resize(total)
	_rasterize_rivers(river)

	# --- ukształtowanie: rozpiętość wysokości w otoczeniu kafelka ---
	var relief := PackedFloat32Array()
	relief.resize(total)
	for y in h:
		for x in w:
			var lo := 99999.0
			var hi := -99999.0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var j := ny * w + nx
					if sea[j] == 1:
						continue
					lo = minf(lo, avg[j])
					hi = maxf(hi, avg[j])
			relief[y * w + x] = maxf(0.0, hi - lo)

	var patch := FastNoiseLite.new()
	patch.seed = 77
	patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# szumy w jednostkach kafelków: przy większej siatce rzadsze, żeby plamy miały tę samą wielkość na mapie
	var k := 1.0 / Sectors.SCALE
	patch.frequency = 0.09 * k
	patch.fractal_octaves = 3
	var urban := FastNoiseLite.new()
	urban.seed = 311
	urban.frequency = 0.11 * k
	urban.fractal_octaves = 2
	var warp := FastNoiseLite.new()
	warp.seed = 512
	warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp.frequency = 0.035 * k
	warp.fractal_octaves = 3

	# --- klasyfikacja terenu ---
	var surface := PackedByteArray()
	surface.resize(total)
	for y in h:
		for x in w:
			var i := y * w + x
			if sea[i] == 1:
				surface[i] = DEEP if avg[i] < -200.0 else OCEAN
				continue
			if lake[i] == 1 or river[i] == 1:
				surface[i] = RIVER
				continue
			var ll: Vector2 = Sectors.lonlat_of(x + 0.5, y + 0.5)
			# zniekształcone współrzędne, żeby granice stref klimatu nie były prostymi liniami
			var warped := ll + Vector2(warp.get_noise_2d(x, y) * 9.0, warp.get_noise_2d(x + 500.0, y + 500.0) * 7.0)
			surface[i] = _land_type(warped, avg[i], peak[i], relief[i], (patch.get_noise_2d(x, y) + 1.0) * 0.5)

	# --- wybrzeża: piasek przy morzu i dużych jeziorach ---
	var shore := surface.duplicate()
	for y in h:
		for x in w:
			var i := y * w + x
			if surface[i] != PLAINS and surface[i] != FOREST:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j := ny * w + nx
				if sea[j] == 1 or lake[j] == 1:
					shore[i] = SAND
					break
	surface = shore

	# --- miasta i miasteczka ---
	for y in h:
		for x in w:
			var i := y * w + x
			if surface[i] != PLAINS and surface[i] != FOREST:
				continue
			var ll: Vector2 = Sectors.lonlat_of(x + 0.5, y + 0.5)
			var thr := 0.55 if ll.x > -100.0 else 0.72
			if urban.get_noise_2d(x, y) > thr:
				surface[i] = CITY
	for t in TOWNS:
		var c: Vector2i = Sectors.cell_of(Vector2(t[1], t[2]))
		var r: float = t[3] * Sectors.SCALE
		var ri := int(ceil(r)) + 1
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var nx := c.x + dx
				var ny := c.y + dy
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j := ny * w + nx
				if surface[j] <= RIVER:
					continue
				if Vector2(dx, dy).length() <= r + patch.get_noise_2d(nx * 3.0, ny * 3.0) * 1.2:
					surface[j] = CITY

	_write(surface)
	_preview(surface)
	var counts := {}
	for v in surface:
		counts[v] = int(counts.get(v, 0)) + 1
	print("counts ", counts)
	quit()


## Teren lądu na podstawie wysokości, położenia i klimatu regionu.
func _land_type(ll: Vector2, e: float, top: float, rel: float, n: float) -> int:
	var lon := ll.x
	var lat := ll.y
	var east := lon > -96.0
	if top > 3300.0 or (lon > -90.0 and top > 1500.0):
		return SNOW
	if e > 2400.0 or (rel > 800.0 and e > 500.0) or (east and rel > 400.0 and e > 220.0):
		return MOUNTAIN
	# pustynie: Wielka Kotlina, Mojave, Sonora, zachodni Teksas
	var west_dry := lon < -103.0 and lat < 42.5 and not (lon < -120.5 and lat > 36.0)
	if west_dry and e < 2100.0:
		return SAND if n < 0.72 else PLAINS
	if lon > -104.5 and lon < -100.0 and lat < 33.0:
		return SAND if n < 0.45 else PLAINS
	# ile lasu ma region (0-1)
	var f := 0.08
	if lon < -120.0 and lat > 39.5:
		f = 0.92
	elif lon < -119.5:
		f = 0.25
	elif lat > 43.0 and lon < -110.0 and e > 800.0:
		f = 0.68
	elif e > 1800.0:
		f = 0.62
	elif lon < -97.0:
		f = 0.14
	elif lat > 45.0:
		f = 0.75
	elif lat > 38.0 and lon < -84.0:
		f = 0.28
	elif lon > -84.0 or lat < 37.5:
		f = 0.68
	return FOREST if n < f else PLAINS


## Wysokość w metrach z kafla terrarium (Web Mercator).
func _elevation(ll: Vector2) -> float:
	var world := 32.0 * 256.0
	var px := (ll.x + 180.0) / 360.0 * world
	var lat := deg_to_rad(ll.y)
	var py := (1.0 - log(tan(lat) + 1.0 / cos(lat)) / PI) * 0.5 * world
	var tx := int(px / 256.0)
	var ty := int(py / 256.0)
	var key := "%d_%d" % [tx, ty]
	if not images.has(key):
		var img := Image.load_from_file(data_dir.path_join("tiles/5_%s.png" % key))
		if img == null:
			push_error("Brak kafla " + key)
			images[key] = null
		else:
			img.convert(Image.FORMAT_RGB8)
			images[key] = img
	var im: Image = images[key]
	if im == null:
		return 0.0
	var c := im.get_pixel(clampi(int(px) - tx * 256, 0, 255), clampi(int(py) - ty * 256, 0, 255))
	return (c.r8 * 256.0 + c.g8 + c.b8 / 256.0) - 32768.0


func _geojson(file_name: String) -> Array:
	var txt := FileAccess.get_file_as_string(data_dir.path_join(file_name))
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		push_error("Zły plik " + file_name)
		return []
	return d["features"]


func _rasterize_lakes(out: PackedByteArray) -> void:
	var count := 0
	for feat in _geojson("ne_50m_lakes.geojson"):
		var g: Dictionary = feat["geometry"]
		var polys: Array = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
		for poly in polys:
			var ring := PackedVector2Array()
			for p in poly[0]:
				ring.append(Vector2(p[0], p[1]))
			if _fill_polygon(ring, out):
				count += 1
	print("lakes ", count)


func _fill_polygon(ring: PackedVector2Array, out: PackedByteArray) -> bool:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in ring:
		lo = lo.min(p)
		hi = hi.max(p)
	if hi.x < Sectors.LON_MIN or lo.x > Sectors.LON_MAX or hi.y < Sectors.LAT_MIN or lo.y > Sectors.LAT_MAX:
		return false
	var a: Vector2i = Sectors.cell_of(Vector2(lo.x, hi.y))
	var b: Vector2i = Sectors.cell_of(Vector2(hi.x, lo.y))
	for y in range(maxi(a.y, 0), mini(b.y + 1, Sectors.GEO_H)):
		for x in range(maxi(a.x, 0), mini(b.x + 1, Sectors.W)):
			if Geometry2D.is_point_in_polygon(Sectors.lonlat_of(x + 0.5, y + 0.5), ring):
				out[y * Sectors.W + x] = 1
	return true


func _rasterize_rivers(out: PackedByteArray) -> void:
	for feat in _geojson("ne_50m_rivers_lake_centerlines.geojson"):
		if feat["properties"].get("featurecla", "") == "Lake Centerline":
			continue
		var g: Dictionary = feat["geometry"]
		if g == null:
			continue
		var lines: Array = g["coordinates"] if g["type"] == "MultiLineString" else [g["coordinates"]]
		for line in lines:
			for k in range(line.size() - 1):
				var a := Vector2(line[k][0], line[k][1])
				var b := Vector2(line[k + 1][0], line[k + 1][1])
				var steps := int(a.distance_to(b) / 0.05) + 1
				for st in steps + 1:
					var c: Vector2i = Sectors.cell_of(a.lerp(b, float(st) / steps))
					if c.x >= 0 and c.y >= 0 and c.x < Sectors.W and c.y < Sectors.GEO_H:
						out[c.y * Sectors.W + c.x] = 1


func _write(surface: PackedByteArray) -> void:
	var packed := surface.compress(FileAccess.COMPRESSION_DEFLATE)
	var b64 := Marshalls.raw_to_base64(packed)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("extends RefCounted\n## PLIK GENEROWANY przez tools/bake_us_map.gd - nie edytuj ręcznie.\n## Typy terenu mapy USA z danych AWS Terrain Tiles (Mapzen) i Natural Earth.\n\nconst DATA := \"%s\"\n\n\nstatic func surface(size: int) -> PackedByteArray:\n\treturn Marshalls.base64_to_raw(DATA).decompress(size, FileAccess.COMPRESSION_DEFLATE)\n" % b64)
	print("written base64 chars ", b64.length())


func _preview(surface: PackedByteArray) -> void:
	var w := Sectors.W
	var h := Sectors.GEO_H
	var img := Image.create(w * 3, h * 3, false, Image.FORMAT_RGB8)
	for y in h * 3:
		for x in w * 3:
			var c: Color = PREVIEW[surface[(y / 3) * w + x / 3]]
			if x % (Sectors.SIZE * 3) == 0 or y % (Sectors.SIZE * 3) == 0:
				c = Color(1, 1, 1)
			img.set_pixel(x, y, c)
	for s in Sectors.LIST:
		for key in ["city_lonlat", "dock_lonlat"]:
			if not s.has(key):
				continue
			var cell: Vector2i = Sectors.cell_of(s[key])
			var col := Color(1, 0, 0) if key == "city_lonlat" else Color(1, 1, 0)
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					img.set_pixel(cell.x * 3 + dx, cell.y * 3 + dy, col)
	img.save_png(data_dir.path_join("preview.png"))
