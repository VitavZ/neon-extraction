extends RefCounted
## "Malarz" zbierający wektorowe kształty do jednej siatki trójkątów.
## Ma te same nazwy metod co CanvasItem (draw_rect, draw_line, ...), więc kod
## rysujący kafelki działa bez zmian - ale cały fragment mapy staje się
## JEDNYM wywołaniem rysowania zamiast tysięcy osobnych wielokątów.

var verts := PackedVector2Array()
var cols := PackedColorArray()


func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	verts.append(a)
	verts.append(b)
	verts.append(c)
	cols.append(col)
	cols.append(col)
	cols.append(col)


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	_tri(a, b, c, col)
	_tri(a, c, d, col)


func _seg(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	var n := d.normalized()
	var o := Vector2(-n.y, n.x) * (maxf(w, 1.0) * 0.5)
	# lekkie wydłużenie, żeby łączenia odcinków nie miały szczelin
	var e := n * (maxf(w, 1.0) * 0.35)
	_quad(a - e + o, b + e + o, b + e - o, a - e - o, col)


func draw_rect(r: Rect2, col: Color, filled := true, width := -1.0, _aa := false) -> void:
	var p0 := r.position
	var p1 := Vector2(r.end.x, r.position.y)
	var p2 := r.end
	var p3 := Vector2(r.position.x, r.end.y)
	if filled:
		_quad(p0, p1, p2, p3, col)
		return
	var w := maxf(width, 1.0)
	var h := w * 0.5
	_quad(p0 + Vector2(-h, -h), p1 + Vector2(h, -h), p1 + Vector2(h, h), p0 + Vector2(-h, h), col)
	_quad(p3 + Vector2(-h, -h), p2 + Vector2(h, -h), p2 + Vector2(h, h), p3 + Vector2(-h, h), col)
	_quad(p0 + Vector2(-h, h), p0 + Vector2(h, h), p3 + Vector2(h, -h), p3 + Vector2(-h, -h), col)
	_quad(p1 + Vector2(-h, h), p1 + Vector2(h, h), p2 + Vector2(h, -h), p2 + Vector2(-h, -h), col)


func draw_line(a: Vector2, b: Vector2, col: Color, width := -1.0, _aa := false) -> void:
	_seg(a, b, col, width)


func draw_polyline(pts: PackedVector2Array, col: Color, width := -1.0, _aa := false) -> void:
	for k in range(pts.size() - 1):
		_seg(pts[k], pts[k + 1], col, width)


func draw_colored_polygon(pts: PackedVector2Array, col: Color, _uvs := PackedVector2Array(), _tex: Texture2D = null) -> void:
	if pts.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		# zdegenerowany kształt - wachlarz
		for k in range(1, pts.size() - 1):
			_tri(pts[0], pts[k], pts[k + 1], col)
		return
	for k in range(0, idx.size(), 3):
		_tri(pts[idx[k]], pts[idx[k + 1]], pts[idx[k + 2]], col)


## Wielokąt wypukły z osobnym kolorem w każdym wierzchołku (gradient).
func draw_polygon(pts: PackedVector2Array, pcols: PackedColorArray, _uvs := PackedVector2Array(), _tex: Texture2D = null) -> void:
	for k in range(1, pts.size() - 1):
		verts.append(pts[0])
		verts.append(pts[k])
		verts.append(pts[k + 1])
		cols.append(pcols[0])
		cols.append(pcols[k])
		cols.append(pcols[k + 1])


func draw_circle(c: Vector2, r: float, col: Color, filled := true, width := -1.0, _aa := false) -> void:
	var segs := 10 if r < 4.0 else 16
	if filled:
		var prev := c + Vector2(r, 0)
		for k in range(1, segs + 1):
			var p := c + Vector2.from_angle(TAU * k / segs) * r
			_tri(c, prev, p, col)
			prev = p
	else:
		draw_arc(c, r, 0.0, TAU, segs, col, width)


func draw_arc(c: Vector2, r: float, a0: float, a1: float, segs: int, col: Color, width := -1.0, _aa := false) -> void:
	var prev := c + Vector2.from_angle(a0) * r
	for k in range(1, segs + 1):
		var p := c + Vector2.from_angle(lerpf(a0, a1, float(k) / segs)) * r
		_seg(prev, p, col, width)
		prev = p


func build_mesh() -> ArrayMesh:
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
