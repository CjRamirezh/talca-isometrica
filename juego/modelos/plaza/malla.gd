# Un constructor de mallas para los modelos de la plaza: triángulos con normal, color por vértice y UV, en el espacio
# de Godot (X al oriente, Y arriba, Z = -y de grilla). Cada pieza (un árbol, el quiosco) arma una o varias de estas y
# las cierra con `malla()`. Las caras se orientan solas: `tri()` recibe la normal que debe mirar y ordena los vértices
# como Godot espera el frente (horario visto desde afuera).
extends RefCounted

var v = PackedVector3Array()
var n = PackedVector3Array()
var c = PackedColorArray()
var uv = PackedVector2Array()


static func G(x: float, y: float, h: float) -> Vector3:  # metros de grilla (x, y) y altura -> Godot
	return Vector3(x, h, -y)


func vacia() -> bool:
	return v.is_empty()


# un triángulo con normal plana (nn: la que debe mirar; si es cero, la geométrica tal como vienen los vértices)
func tri(a: Vector3, b: Vector3, d: Vector3, col: Color, nn := Vector3.ZERO, ua := Vector2.ZERO, ub := Vector2.ZERO, ud := Vector2.ZERO) -> void:
	var g = (d - a).cross(b - a)
	if nn == Vector3.ZERO:
		nn = g.normalized()
	elif g.dot(nn) < 0:
		var t = b; b = d; d = t
		var tu = ub; ub = ud; ud = tu
	v.append_array([a, b, d])
	n.append_array([nn, nn, nn])
	c.append_array([col, col, col])
	uv.append_array([ua, ub, ud])


# un triángulo con una normal por vértice (superficies suaves); el orden lo decide la suma de las normales
func tri_n(a: Vector3, b: Vector3, d: Vector3, na: Vector3, nb: Vector3, nd: Vector3, ca: Color, cb: Color, cd: Color,
		ua := Vector2.ZERO, ub := Vector2.ZERO, ud := Vector2.ZERO) -> void:
	if (d - a).cross(b - a).dot(na + nb + nd) < 0:
		var t = b; b = d; d = t
		var tn = nb; nb = nd; nd = tn
		var tc = cb; cb = cd; cd = tc
		var tu = ub; ub = ud; ud = tu
	v.append_array([a, b, d])
	n.append_array([na, nb, nd])
	c.append_array([ca, cb, cd])
	uv.append_array([ua, ub, ud])


func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, col: Color, nn := Vector3.ZERO, uvs := []) -> void:
	if nn == Vector3.ZERO:
		nn = (d - a).cross(b - a).normalized()
		if nn == Vector3.ZERO:
			return
	var u: Array = uvs if uvs.size() == 4 else [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	tri(a, b, d, col, nn, u[0], u[1], u[2])
	tri(a, d, e, col, nn, u[0], u[2], u[3])


# un polígono horizontal (puntos de grilla) a la altura h, mirando arriba (o abajo); triangula de verdad (cóncavos)
func plano(pol: PackedVector2Array, h: float, col: Color, arriba := true) -> void:
	var t = Geometry2D.triangulate_polygon(pol)
	var nn = Vector3.UP if arriba else Vector3.DOWN
	for i in range(0, t.size(), 3):
		var a = pol[t[i]]; var b = pol[t[i + 1]]; var d = pol[t[i + 2]]
		tri(G(a.x, a.y, h), G(b.x, b.y, h), G(d.x, d.y, h), col, nn, a, b, d)


# los muros de un polígono de grilla entre h0 y h1, mirando hacia afuera (o adentro)
func muros(pol: PackedVector2Array, h0: float, h1: float, col: Color, afuera := true) -> void:
	var s = 1.0 if area(pol) > 0 else -1.0
	if not afuera:
		s = -s
	var largo = 0.0
	for i in pol.size():
		var a = pol[i]; var b = pol[(i + 1) % pol.size()]
		var d = b - a
		if d.length() < 1e-4:
			continue
		var nn = Vector3(d.y * s, 0, d.x * s).normalized()  # (dy, -dx) en grilla -> Godot (dy, 0, dx)
		var l = d.length()
		quad(G(a.x, a.y, h0), G(b.x, b.y, h0), G(b.x, b.y, h1), G(a.x, a.y, h1), col, nn,
			[Vector2(largo, h0), Vector2(largo + l, h0), Vector2(largo + l, h1), Vector2(largo, h1)])
		largo += l


func prisma(pol: PackedVector2Array, h0: float, h1: float, col_muro: Color, col_tapa: Color, tapa := true) -> void:
	muros(pol, h0, h1, col_muro)
	if tapa:
		plano(pol, h1, col_tapa)


# una caja de lado s centrada en p (Godot), girada `giro` radianes en torno al eje vertical
func caja(p: Vector3, s: Vector3, col: Color, giro := 0.0, col_tapa := Color(0, 0, 0, 0), base := false) -> void:
	var bs = Basis(Vector3.UP, giro)
	var h = s / 2
	var P = func(x: float, y: float, z: float) -> Vector3: return p + bs * Vector3(x * h.x, y * h.y, z * h.z)
	var ct = col if col_tapa.a == 0 else col_tapa
	quad(P.call(-1, -1, 1), P.call(1, -1, 1), P.call(1, 1, 1), P.call(-1, 1, 1), col, bs * Vector3.BACK)
	quad(P.call(1, -1, -1), P.call(-1, -1, -1), P.call(-1, 1, -1), P.call(1, 1, -1), col, bs * Vector3.FORWARD)
	quad(P.call(1, -1, 1), P.call(1, -1, -1), P.call(1, 1, -1), P.call(1, 1, 1), col, bs * Vector3.RIGHT)
	quad(P.call(-1, -1, -1), P.call(-1, -1, 1), P.call(-1, 1, 1), P.call(-1, 1, -1), col, bs * Vector3.LEFT)
	quad(P.call(-1, 1, 1), P.call(1, 1, 1), P.call(1, 1, -1), P.call(-1, 1, -1), ct, Vector3.UP)
	if base:
		quad(P.call(-1, -1, -1), P.call(1, -1, -1), P.call(1, -1, 1), P.call(-1, -1, 1), col, Vector3.DOWN)


# un sólido de revolución en torno al eje vertical por p: perfil [Vector2(radio, altura), ...] de abajo arriba,
# k lados, normales suaves; uv: (vuelta, largo del perfil). col puede ser un Color o un Callable(i_perfil) -> Color
func torno(p: Vector3, perfil: Array, k: int, col, a0 := 0.0, suave := true) -> void:
	var largo = [0.0]
	for i in range(1, perfil.size()):
		largo.append(largo[i - 1] + (perfil[i] - perfil[i - 1]).length())
	for i in perfil.size() - 1:
		var p0: Vector2 = perfil[i]; var p1: Vector2 = perfil[i + 1]
		var dr = p1 - p0
		var c0: Color = col.call(i) if col is Callable else col
		var c1: Color = col.call(i + 1) if col is Callable else col
		if not suave:
			c1 = c0
		for j in k:
			var t0 = a0 + TAU * j / k; var t1 = a0 + TAU * (j + 1) / k
			var e0 = Vector3(cos(t0), 0, sin(t0)); var e1 = Vector3(cos(t1), 0, sin(t1))
			var a = p + e0 * p0.x + Vector3.UP * p0.y
			var b = p + e1 * p0.x + Vector3.UP * p0.y
			var d = p + e1 * p1.x + Vector3.UP * p1.y
			var e = p + e0 * p1.x + Vector3.UP * p1.y
			var tm = (t0 + t1) / 2
			# (radial, vertical): el perfil se recorre con el sólido a su izquierda (afuera subiendo, adentro de un
			# tazón bajando), así un anillo que se abre mira abajo y uno que se cierra, arriba
			var nr = Vector2(dr.y, -dr.x).normalized()
			var n0 = (e0 * nr.x + Vector3.UP * nr.y).normalized()
			var n1 = (e1 * nr.x + Vector3.UP * nr.y).normalized()
			if not suave:
				var em = Vector3(cos(tm), 0, sin(tm))
				n0 = (em * nr.x + Vector3.UP * nr.y).normalized(); n1 = n0
			var u0 = float(j) / k; var u1 = float(j + 1) / k
			if (a - e).length() > 1e-5 or (b - d).length() > 1e-5:
				if (a - b).length() > 1e-6:
					tri_n(a, b, d, n0, n1, n1, c0, c0, c1, Vector2(u0, largo[i]), Vector2(u1, largo[i]), Vector2(u1, largo[i + 1]))
				if (d - e).length() > 1e-6:
					tri_n(a, d, e, n0, n1, n0, c0, c1, c1, Vector2(u0, largo[i]), Vector2(u1, largo[i + 1]), Vector2(u0, largo[i + 1]))


# un cilindro (o tronco de cono) entre dos puntos cualesquiera, k lados, sin tapas: ramas, columnas inclinadas
func tubo(a: Vector3, b: Vector3, ra: float, rb: float, k: int, col_a: Color, col_b: Color, va := 0.0, vb := 1.0) -> void:
	var eje = b - a
	if eje.length() < 1e-4:
		return
	var w = eje.normalized()
	var u = w.cross(Vector3.UP if abs(w.y) < 0.95 else Vector3.RIGHT).normalized()
	var q = w.cross(u)
	var pend = (ra - rb) / eje.length()
	for j in k:
		var t0 = TAU * j / k; var t1 = TAU * (j + 1) / k
		var d0 = u * cos(t0) + q * sin(t0); var d1 = u * cos(t1) + q * sin(t1)
		var n0 = (d0 + w * pend).normalized(); var n1 = (d1 + w * pend).normalized()
		var u0 = float(j) / k; var u1 = float(j + 1) / k
		tri_n(a + d0 * ra, a + d1 * ra, b + d1 * rb, n0, n1, n1, col_a, col_a, col_b, Vector2(u0, va), Vector2(u1, va), Vector2(u1, vb))
		tri_n(a + d0 * ra, b + d1 * rb, b + d0 * rb, n0, n1, n0, col_a, col_b, col_b, Vector2(u0, va), Vector2(u1, vb), Vector2(u0, vb))


static func area(pol: PackedVector2Array) -> float:
	var a = 0.0
	for i in pol.size():
		var p = pol[i]; var r = pol[(i + 1) % pol.size()]
		a += p.x * r.y - r.x * p.y
	return a / 2


# el polígono corrido d hacia adentro (d < 0: afuera), con el mismo número de vértices (inglete acotado), como `inset`
# del hito de la página
static func adentro(pol: PackedVector2Array, d: float) -> PackedVector2Array:
	var s = 1.0 if area(pol) > 0 else -1.0
	var k = pol.size()
	var out = PackedVector2Array()
	for i in k:
		var p = pol[i]; var a = pol[(i + k - 1) % k]; var b = pol[(i + 1) % k]
		var l1: float = max((p - a).length(), 1e-6); var l2: float = max((b - p).length(), 1e-6)
		var n1 = Vector2(-(p.y - a.y) / l1 * s, (p.x - a.x) / l1 * s)
		var n2 = Vector2(-(b.y - p.y) / l2 * s, (b.x - p.x) / l2 * s)
		var f: float = max(0.35, 1 + n1.dot(n2))
		out.append(p + (n1 + n2) * d / f)
	return out


# una lista plana [x0, y0, x1, y1, ...] como polígono
static func pol(a: Array) -> PackedVector2Array:
	var out = PackedVector2Array()
	for i in range(0, a.size(), 2):
		out.append(Vector2(a[i], a[i + 1]))
	return out


func malla(mat: Material = null, previa: ArrayMesh = null) -> ArrayMesh:
	var m = previa if previa else ArrayMesh.new()
	if v.is_empty():
		return m
	var a = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = n
	a[Mesh.ARRAY_COLOR] = c
	a[Mesh.ARRAY_TEX_UV] = uv
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	if mat:
		m.surface_set_material(m.get_surface_count() - 1, mat)
	return m


# las caras como lista para una forma de colisión cóncava (ConcavePolygonShape3D)
func caras() -> PackedVector3Array:
	return v
