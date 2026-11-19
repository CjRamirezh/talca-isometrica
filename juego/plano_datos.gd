# El plano de la comuna para los mapas del juego (plano.gd: el mapa en miniatura y el mapa grande) y para el camino
# a un marcador (ruta.gd), leído una vez de datos/plano.json (pipeline/plano.py, que corre `make juego`). Todo en
# metros de grilla (x al oriente, y al norte; en Godot X = x, Z = -y).
#
#   const Datos := preload("res://plano_datos.gd")
#   var d := Datos.uno()                 # null si falta datos/plano.json (con un aviso)
#   d.calles_en(rect)                    # los índices de las calles cuya caja toca el rectángulo
#   d.relleno                            # ArrayMesh 2D: tierra de la comuna, agua, islas y manzanas, ya triangulados
#   d.camino(desde, hasta)               # PackedVector2Array por la red de calles (A*), o vacío (ver camino())
extends RefCounted

const RUTA := "res://datos/plano.json"
const CELDA := 400.0  # m: la grilla de las calles para dibujar solo lo que se ve
const CELDA_RED := 100.0  # m: la de los tramos de la red, para buscar la calle más cercana
const BUSCAR := 800.0  # m: hasta dónde busca una calle alrededor del personaje
const RECTO := 80.0  # m: un marcador más cerca que esto va en línea recta, sin calles (en la plaza, 280 m dando la vuelta)
const BUSCAR_DESTINO := 5000.0  # m, alrededor del marcador (en el campo, la calle más cercana puede estar lejos)
const ANCHO := [16.0, 13.0, 11.0, 9.5, 7.0, 5.0, 3.5, 3.5]  # m, el ancho de cada clase de calle (SW de la página)

# los colores del plano (un mapa oscuro, como el de un videojuego)
const C_FONDO := Color(0.09, 0.10, 0.12)  # fuera de la comuna
const C_TIERRA := Color(0.17, 0.20, 0.17)
const C_MANZANA := Color(0.25, 0.27, 0.29)
const C_AGUA := Color(0.20, 0.38, 0.55)
const C_CALLE := [Color(0.98, 0.80, 0.36), Color(0.96, 0.84, 0.50), Color(0.93, 0.93, 0.90), Color(0.90, 0.90, 0.88),
	Color(0.74, 0.75, 0.76), Color(0.62, 0.63, 0.65), Color(0.50, 0.52, 0.52), Color(0.46, 0.48, 0.50)]
const C_RUTA5 := Color(1.0, 0.62, 0.25)
const C_VIA := Color(0.62, 0.50, 0.42)
const C_LIMITE := Color(0.85, 0.85, 0.80, 0.55)

static var _uno: RefCounted = null
static var _probado := false

var calles := []  # [PackedVector2Array]
var clase := PackedInt32Array()
var nombre := PackedInt32Array()
var cajas: Array[Rect2] = []
var nombres := PackedStringArray()
var celdas := {}  # Vector2i -> PackedInt32Array de calles
var rios := []  # [[ancho, PackedVector2Array]]
var via := []  # [PackedVector2Array]
var ruta5 := []  # las calzadas y los ramales: [PackedVector2Array]
var limite := PackedVector2Array()
# lo mismo como pares de puntos (draw_multiline: un dibujo por capa, no uno por línea)
var rios_seg := {}  # ancho -> PackedVector2Array
var via_seg := PackedVector2Array()
var ruta5_seg := PackedVector2Array()
var relleno := ArrayMesh.new()
var caja := Rect2()  # la de la comuna
var lugares := []  # [{nombre, x, y, cat}], de mapa/indice.json

# la red (pipeline/plano.py): nodos, aristas y A*
var nodos := PackedVector2Array()
var tramos := PackedInt32Array()  # a, b, dirigido (0 o 1), por tramo
var celdas_red := {}  # Vector2i -> PackedInt32Array de tramos
var comp := PackedInt32Array()  # la componente de cada nodo (sin sentido)
var astar: AStar2D = null
var ms := {}  # lo que tardó cada parte, para el informe


static func uno() -> RefCounted:
	if not _probado:
		_probado = true
		if FileAccess.file_exists(RUTA):
			var d = load("res://plano_datos.gd").new()
			if d.leer():
				_uno = d
		else:
			push_warning("plano_datos.gd: falta juego/datos/plano.json (python pipeline/plano.py o make juego): sin mapas ni camino")
	return _uno


# suelta lo leído (plano.gd, al salir del juego): si no, Godot avisa de lo que queda vivo en la variable estática
static func soltar() -> void:
	_uno = null


func leer() -> bool:
	var t0 := Time.get_ticks_usec()
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(RUTA))
	if not (j is Dictionary):
		push_warning("plano_datos.gd: no pude leer %s" % RUTA)
		return false
	ms["json"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	nombres = PackedStringArray(j.get("nombres", []))
	for c in j.get("calles", []):
		var p := puntos(c[2])
		calles.append(p)
		clase.append(int(c[0]))
		nombre.append(int(c[1]))
		var r := caja_de(p)
		cajas.append(r)
		var i := calles.size() - 1
		for cy in range(floori(r.position.y / CELDA), floori(r.end.y / CELDA) + 1):
			for cx in range(floori(r.position.x / CELDA), floori(r.end.x / CELDA) + 1):
				var k := Vector2i(cx, cy)
				if not celdas.has(k):
					celdas[k] = PackedInt32Array()
				celdas[k].append(i)
	for r in j.get("rios", []):
		rios.append([float(r[0]), puntos(r[1])])
	for v in j.get("via", []):
		via.append(puntos(v))
	for v in j.get("ruta5", []) + j.get("ramales", []):
		ruta5.append(puntos(v))
	for r in rios:
		if not rios_seg.has(r[0]):
			rios_seg[r[0]] = PackedVector2Array()
		rios_seg[r[0]] = pares(r[1], rios_seg[r[0]])
	for v in via:
		via_seg = pares(v, via_seg)
	for v in ruta5:
		ruta5_seg = pares(v, ruta5_seg)
	limite = puntos(j.get("limite", []))
	caja = caja_de(limite)
	ms["calles"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	rellenar(j)
	ms["relleno"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	red(j.get("red", {}))
	ms["red"] = (Time.get_ticks_usec() - t0) / 1000.0
	for l in preload("res://glb.gd").info().get("lugares", []):
		lugares.append({"nombre": String(l.get("nombre", l.get("id", "?"))), "x": float(l["x"]), "y": float(l["y"]), "cat": String(l.get("cat", ""))})
	print("plano_datos.gd: %d calles, %d nodos, %d tramos (ms: %s)" % [calles.size(), nodos.size(), tramos.size() / 3, ms])
	return true


static func puntos(a: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.resize(a.size() / 2)
	for i in p.size():
		p[i] = Vector2(a[2 * i], a[2 * i + 1])
	return p


static func pares(p: PackedVector2Array, a: PackedVector2Array) -> PackedVector2Array:
	for k in range(p.size() - 1):
		a.append(p[k])
		a.append(p[k + 1])
	return a


static func caja_de(p: PackedVector2Array) -> Rect2:
	if p.is_empty():
		return Rect2()
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


# Los polígonos rellenos en una sola malla 2D (un solo dibujo, sin triangular en cada cuadro): la comuna, el agua de los
# ríos, sus islas (del color de la tierra, encima del agua) y las manzanas. Un anillo que Godot no sabe triangular (se
# cruza a sí mismo) no va, con un aviso.
func rellenar(j: Dictionary) -> void:
	var v := PackedVector2Array()
	var col := PackedColorArray()
	var fallas := 0
	var capas := [[[j.get("limite", [])], C_TIERRA], [j.get("agua", []), C_AGUA], [j.get("islas", []), C_TIERRA],
		[j.get("manzanas", []), C_MANZANA]]
	for capa in capas:
		var c: Color = capa[1]
		for a in capa[0]:
			var p := puntos(a)
			if p.size() > 2 and p[0] == p[p.size() - 1]:
				p.remove_at(p.size() - 1)
			if p.size() < 3:
				continue
			var t := Geometry2D.triangulate_polygon(p)
			if t.is_empty():
				fallas += 1
				continue
			for i in t:
				v.append(p[i])
				col.append(c)
	if fallas > 0:
		push_warning("plano_datos.gd: %d anillos sin triangular (se cruzan): no se rellenan" % fallas)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = col
	relleno.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


func calles_en(r: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var visto := {}
	for cy in range(floori(r.position.y / CELDA), floori(r.end.y / CELDA) + 1):
		for cx in range(floori(r.position.x / CELDA), floori(r.end.x / CELDA) + 1):
			var k := Vector2i(cx, cy)
			if not celdas.has(k):
				continue
			for i in celdas[k]:
				if not visto.has(i) and cajas[i].intersects(r, true):
					visto[i] = true
					out.append(i)
	return out


# ---------- la red y el camino ----------

func red(r: Dictionary) -> void:
	nodos = puntos(r.get("p", []))
	var a: Array = r.get("a", [])
	var d: Array = r.get("d", [])
	tramos.resize((a.size() + d.size()) / 2 * 3)
	var k := 0
	for lista in [[a, 0], [d, 1]]:
		var l: Array = lista[0]
		for i in range(0, l.size(), 2):
			tramos[k] = int(l[i])
			tramos[k + 1] = int(l[i + 1])
			tramos[k + 2] = lista[1]
			k += 3
	for t in range(tramos.size() / 3):
		var A := nodos[tramos[3 * t]]
		var B := nodos[tramos[3 * t + 1]]
		for cy in range(floori(minf(A.y, B.y) / CELDA_RED), floori(maxf(A.y, B.y) / CELDA_RED) + 1):
			for cx in range(floori(minf(A.x, B.x) / CELDA_RED), floori(maxf(A.x, B.x) / CELDA_RED) + 1):
				var c := Vector2i(cx, cy)
				if not celdas_red.has(c):
					celdas_red[c] = PackedInt32Array()
				celdas_red[c].append(t)
	# las componentes, sin sentido: el camino busca la calle del destino en la misma que la del origen
	var adj := []
	adj.resize(nodos.size())
	for i in nodos.size():
		adj[i] = PackedInt32Array()
	for t in range(tramos.size() / 3):
		adj[tramos[3 * t]].append(tramos[3 * t + 1])
		adj[tramos[3 * t + 1]].append(tramos[3 * t])
	comp.resize(nodos.size())
	comp.fill(-1)
	var n := 0
	for s in nodos.size():
		if comp[s] >= 0:
			continue
		comp[s] = n
		var pila := PackedInt32Array([s])
		while not pila.is_empty():
			var u := pila[pila.size() - 1]
			pila.remove_at(pila.size() - 1)
			for w in adj[u]:
				if comp[w] < 0:
					comp[w] = n
					pila.append(w)
		n += 1


# A* de Godot sobre la red, armado la primera vez que se pide un camino (~25 mil nodos)
func armar_astar() -> void:
	var t0 := Time.get_ticks_usec()
	astar = AStar2D.new()
	astar.reserve_space(nodos.size() + 2)
	for i in nodos.size():
		astar.add_point(i, nodos[i])
	for t in range(tramos.size() / 3):
		astar.connect_points(tramos[3 * t], tramos[3 * t + 1], tramos[3 * t + 2] == 0)
	ms["astar"] = (Time.get_ticks_usec() - t0) / 1000.0


# el tramo de la red más cercano a p (en la componente c, si c >= 0): [tramo, punto sobre él, distancia], o [] si no
# hay uno a menos de `hasta` m
func cercano(p: Vector2, c := -1, hasta := BUSCAR) -> Array:
	var best := []
	var bd := INF
	var r := 0
	var c0 := Vector2i(floori(p.x / CELDA_RED), floori(p.y / CELDA_RED))
	while r * CELDA_RED <= hasta + CELDA_RED:
		for cy in range(c0.y - r, c0.y + r + 1):
			for cx in range(c0.x - r, c0.x + r + 1):
				if maxi(absi(cx - c0.x), absi(cy - c0.y)) != r:
					continue  # solo el anillo r
				var k := Vector2i(cx, cy)
				if not celdas_red.has(k):
					continue
				for t in celdas_red[k]:
					if c >= 0 and comp[tramos[3 * t]] != c:
						continue
					var q := Geometry2D.get_closest_point_to_segment(p, nodos[tramos[3 * t]], nodos[tramos[3 * t + 1]])
					var d := p.distance_to(q)
					if d < bd:
						bd = d
						best = [t, q, d]
		# lo que está en el anillo r está a más de (r - 1) celdas: si ya hay algo más cerca, no hace falta seguir
		if bd <= (r) * CELDA_RED:
			break
		r += 1
	return best if bd <= hasta else []


# El camino de desde a hasta por la red: desde el punto de la calle más cercana a `desde` hasta el de la calle más
# cercana a `hasta` en la misma componente, con los dos tramos rectos de las puntas. Vacío si no hay calle cerca del
# origen o A* no encuentra camino (una calzada de la Ruta 5 al revés): quien llama dibuja entonces una línea recta.
func camino(desde: Vector2, hasta: Vector2) -> PackedVector2Array:
	if desde.distance_to(hasta) < RECTO:
		return PackedVector2Array([desde, hasta])
	if astar == null:
		armar_astar()
	var a := cercano(desde)
	if a.is_empty():
		return PackedVector2Array()
	var b := cercano(hasta, comp[tramos[3 * a[0]]], BUSCAR_DESTINO)
	if b.is_empty():
		return PackedVector2Array()
	var n := nodos.size()
	var ini := n
	var fin := n + 1
	astar.add_point(ini, a[1])
	astar.add_point(fin, b[1])
	var ta: int = a[0]
	var tb: int = b[0]
	# de la punta al tramo: hacia sus dos nodos, o solo hacia adelante si es de un sentido
	astar.connect_points(ini, tramos[3 * ta + 1], false)
	if tramos[3 * ta + 2] == 0:
		astar.connect_points(ini, tramos[3 * ta], false)
	astar.connect_points(tramos[3 * tb], fin, false)
	if tramos[3 * tb + 2] == 0:
		astar.connect_points(tramos[3 * tb + 1], fin, false)
	var out := PackedVector2Array()
	if ta == tb:  # los dos sobre el mismo tramo
		var A := nodos[tramos[3 * ta]]
		var adelante: bool = (b[1] - A).length() >= (a[1] - A).length()
		if tramos[3 * ta + 2] == 0 or adelante:
			out = PackedVector2Array([a[1], b[1]])
	if out.is_empty():
		out = astar.get_point_path(ini, fin)
	astar.remove_point(ini)
	astar.remove_point(fin)
	if out.is_empty():
		return out
	if desde.distance_to(out[0]) > 0.5:
		out.insert(0, desde)
	if hasta.distance_to(out[out.size() - 1]) > 0.5:
		out.append(hasta)
	return out
