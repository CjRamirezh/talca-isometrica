# Los autos del juego, en un solo lugar: los estacionados de calles.gd (alrededor de la plaza, uno por uno en su
# malla) y los de toda la comuna de autos.gd (los de la página, en un MultiMesh por tipo). Hasta noviembre de 2026
# eran auto() de calles.gd; el modelo, las medidas y los colores no cambiaron.
#
# Un auto se escribe en un marco (Malla.Marco) con v hacia adelante, u al costado y h desde el suelo (las ruedas lo
# tocan en h = 0): la carrocería (un perfil lateral extruido a lo ancho) y la cabina más angosta encima, con ventanas
# laterales y pilar, parabrisas, parachoques, focos, espejos, ruedas con llanta y tapabarros. Siete siluetas: sedán,
# hatchback, SUV, camioneta y colectivo (sedán negro con letrero amarillo) de calles.gd, y el furgón y el camión de
# autos.gd (la página tiene furgones de 4,9 m y 1,3 veces el alto, y en la Ruta 5 camiones de 11–13 m).
#
#   const Auto := preload("res://modelos/entorno/auto.gd")
#   Auto.modelo(m, marco, Auto.SEDAN, Color(0.6, 0.08, 0.07), choques)   # choques: una Malla para la caja de colisión
#   Auto.modelo(m, marco, Auto.SUV, Auto.PINTURA)   # la carrocería en alfa 0: en un MultiMesh con Mat.tinte, el color
#                                                   # de cada instancia (autos.gd)
#   Auto.caja(Auto.SUV)                             # [medio ancho, v de atrás, v de adelante, alto]: la de colisión
#   Auto.modelo(m, marco, Auto.SEDAN, col, null, false)   # sin neumáticos ni llantas (los tapabarros sí): el auto de
#                                                   # vehiculo.gd, que pone sus ruedas aparte para que giren
extends RefCounted

const Malla := preload("res://malla.gd")

const SEDAN := 0
const HATCHBACK := 1
const SUV := 2
const CAMIONETA := 3
const COLECTIVO := 4
const FURGON := 5
const CAMION := 6
const TIPOS := 7

# los colores de calles.gd (los más comunes en Chile: blanco, gris, plata, negro, rojo, azul)
const COLORES := [Color(0.92, 0.92, 0.9), Color(0.92, 0.92, 0.9), Color(0.62, 0.64, 0.66), Color(0.75, 0.76, 0.77),
	Color(0.1, 0.1, 0.11), Color(0.35, 0.36, 0.38), Color(0.6, 0.08, 0.07), Color(0.12, 0.2, 0.42), Color(0.45, 0.06, 0.08)]
const NEGRO_COLECTIVO := Color(0.07, 0.07, 0.08)
const PINTURA := Color(1, 1, 1, 0)  # la carrocería de una malla para MultiMesh: el color lo pone la instancia
const VIDRIO := Color(0.13, 0.16, 0.19)
const GRIS := Color(0.18, 0.18, 0.19)

# la carrocería hasta la línea de cintura (v hacia adelante, h) y la cabina encima; v = 0 al medio del auto
const CUERPOS := [
	[[[-2.25, 0.32], [2.25, 0.32], [2.32, 0.58], [2.1, 0.8], [1.0, 0.9], [-1.65, 0.93], [-2.22, 0.86]], [[1.0, 0.9], [-1.65, 0.93], [-0.95, 1.42], [0.3, 1.44]]],
	[[[-1.95, 0.32], [1.95, 0.32], [2.02, 0.58], [1.82, 0.82], [0.85, 0.93], [-1.92, 0.95], [-2.0, 0.6]], [[0.85, 0.93], [-1.92, 0.95], [-1.82, 1.45], [0.2, 1.47]]],
	[[[-2.2, 0.4], [2.2, 0.4], [2.27, 0.72], [2.05, 0.98], [1.0, 1.05], [-2.15, 1.08], [-2.25, 0.75]], [[1.0, 1.05], [-2.15, 1.08], [-2.05, 1.7], [0.45, 1.72]]],
	[[[-2.6, 0.45], [2.6, 0.45], [2.67, 0.8], [2.42, 1.05], [1.35, 1.1], [-0.4, 1.12], [-0.4, 1.12], [-2.6, 1.12]], [[1.35, 1.1], [-0.4, 1.12], [-0.3, 1.78], [0.85, 1.8]]],
	[[[-2.25, 0.32], [2.25, 0.32], [2.32, 0.58], [2.1, 0.8], [1.0, 0.9], [-1.65, 0.93], [-2.22, 0.86]], [[1.0, 0.9], [-1.65, 0.93], [-0.95, 1.42], [0.3, 1.44]]],
	# el furgón: 4,9 m, la cabina alta hasta atrás (en la página, 1,3 veces el alto de un auto)
	[[[-2.45, 0.36], [2.45, 0.36], [2.52, 0.68], [2.3, 0.98], [1.45, 1.06], [-2.45, 1.08]], [[1.45, 1.06], [-2.45, 1.08], [-2.45, 2.02], [0.8, 2.04]]]]
const ANCHO := [0.86, 0.85, 0.92, 0.93, 0.86, 0.95]  # medio ancho de la carrocería
const RUEDA_V := [1.4, 1.25, 1.4, 1.75, 1.4, 1.6]  # el eje, desde el medio
const RUEDA_R := [0.31, 0.31, 0.36, 0.38, 0.31, 0.33]
const CAMION_L := 11.5  # m: el camión de modelo (autos.gd lo estira al largo de la página, 10,8–12,6 m)


static func caja(tipo: int) -> Array:
	if tipo == CAMION:
		return [1.25, -CAMION_L / 2.0, CAMION_L / 2.0, 3.6]
	var c: Array = CUERPOS[tipo]
	return [ANCHO[tipo], c[0][0][0], c[0][1][0], c[1][3][1]]


static func modelo(m: Malla, f: Malla.Marco, tipo: int, col: Color, choques: Malla = null, llantas := true) -> void:
	if tipo == CAMION:
		camion(m, f, col, choques)
		return
	var ancho: float = ANCHO[tipo]
	var cuerpos: Array = CUERPOS[tipo]
	var vid := VIDRIO
	var cb: Array = cuerpos[0]
	if choques:
		choques.caja(f, -ancho, cb[0][0], ancho, cb[1][0], 0.2, cuerpos[1][3][1], col)
	for parte in 2:
		var poli := PackedVector2Array()
		for q in cuerpos[parte]:
			poli.append(Vector2(q[0], q[1]))
		if Geometry2D.is_polygon_clockwise(poli):
			poli.reverse()
		var w: float = ancho if parte == 0 else ancho * 0.8
		var idx := Geometry2D.triangulate_polygon(poli)
		for sg in [-1.0, 1.0]:
			for t in range(0, idx.size(), 3):
				m.cara([f.V(sg * w, poli[idx[t]].x, poli[idx[t]].y), f.V(sg * w, poli[idx[t + 1]].x, poli[idx[t + 1]].y),
					f.V(sg * w, poli[idx[t + 2]].x, poli[idx[t + 2]].y)], col, "pintura", f.N(sg, 0))
			if parte == 1:
				# las ventanas laterales: la cabina achicada 7 cm, con un pilar al medio
				for r in Geometry2D.offset_polygon(poli, -0.07):
					var ri: PackedVector2Array = r
					var ix := Geometry2D.triangulate_polygon(ri)
					for t in range(0, ix.size(), 3):
						m.cara([f.V(sg * (w + 0.005), ri[ix[t]].x, ri[ix[t]].y), f.V(sg * (w + 0.005), ri[ix[t + 1]].x, ri[ix[t + 1]].y),
							f.V(sg * (w + 0.005), ri[ix[t + 2]].x, ri[ix[t + 2]].y)], vid, "vidrio", f.N(sg, 0))
				var vb := (poli[0].x + poli[1].x) / 2.0 - 0.15
				m.cara([f.V(sg * (w + 0.01), vb - 0.06, poli[0].y), f.V(sg * (w + 0.01), vb + 0.06, poli[0].y),
					f.V(sg * (w + 0.01), vb + 0.06, poli[2].y), f.V(sg * (w + 0.01), vb - 0.06, poli[2].y)], col, "pintura", f.N(sg, 0))
		for i in poli.size():
			var a := poli[i]
			var b := poli[(i + 1) % poli.size()]
			var e := b - a
			if e.length() < 0.01:
				continue
			var n := Vector2(e.y, -e.x).normalized()  # hacia afuera (antihorario)
			# en la carrocería, los cantos de arriba que quedan bajo la cabina no se ven: igual se dibujan
			var esvidrio: bool = parte == 1 and abs(e.y) > 0.3
			m.cara([f.V(-w, a.x, a.y), f.V(w, a.x, a.y), f.V(w, b.x, b.y), f.V(-w, b.x, b.y)], vid if esvidrio else col,
				"vidrio" if esvidrio else "pintura", f.N(0, n.x, n.y))
	var base: Array = cuerpos[0]
	var vf: float = base[2][0] + 0.004
	var vt: float = base[0][0] - 0.004
	var hb: float = base[0][1]
	# parachoques gris oscuro, focos, luces traseras, patente, espejos
	m.caja(f, -ancho - 0.02, vf - 0.12, ancho + 0.02, vf + 0.04, hb, hb + 0.2, GRIS, "pintura")
	m.caja(f, -ancho - 0.02, vt - 0.04, ancho + 0.02, vt + 0.12, hb, hb + 0.2, GRIS, "pintura")
	var hf: float = base[2][1]
	for sg in [-1.0, 1.0]:
		m.cara([f.V(sg * (ancho - 0.06), vf - 0.05, hf + 0.02), f.V(sg * (ancho - 0.38), vf - 0.05, hf + 0.02),
			f.V(sg * (ancho - 0.38), vf - 0.08, hf + 0.14), f.V(sg * (ancho - 0.06), vf - 0.08, hf + 0.14)], Color(0.95, 0.95, 0.88), "vidrio", f.N(0, 1, 0.3))
		m.cara([f.V(sg * (ancho - 0.04), vt, hb + 0.35), f.V(sg * (ancho - 0.32), vt, hb + 0.35), f.V(sg * (ancho - 0.32), vt, hb + 0.5),
			f.V(sg * (ancho - 0.04), vt, hb + 0.5)], Color(0.72, 0.07, 0.05), "pintura", f.N(0, -1))
		var cab: Array = cuerpos[1]
		var ve: float = cab[0][0] - 0.15
		m.caja(f, sg * (ancho * 0.8) - (0.0 if sg > 0 else 0.2), ve - 0.08, sg * (ancho * 0.8) + (0.2 if sg > 0 else 0.0), ve + 0.08, cab[0][1] + 0.02, cab[0][1] + 0.16, col, "pintura")
	m.cara([f.V(-0.26, vt - 0.11, hb + 0.04), f.V(0.26, vt - 0.11, hb + 0.04), f.V(0.26, vt - 0.11, hb + 0.17), f.V(-0.26, vt - 0.11, hb + 0.17)], Color(0.93, 0.93, 0.9), "pintura", f.N(0, -1))
	if tipo == COLECTIVO:
		# el letrero de techo de los colectivos: placa blanca con el número de línea en negro, sobre fondo amarillo
		var cab: Array = cuerpos[1]
		var hr: float = cab[3][1]
		m.caja(f, -0.32, -0.45, 0.32, -0.25, hr, hr + 0.22, Color(0.95, 0.8, 0.15), "pintura")
	# las ruedas: cilindros acostados, con la llanta gris
	var vr: float = RUEDA_V[tipo]
	ruedas(m, f, ancho, [-vr, vr], RUEDA_R[tipo], llantas)


# las ruedas (con llanta y tapabarro) en cada eje v de ejes, a los dos lados de una carrocería de medio ancho ancho
# (llantas falso: solo los tapabarros)
static func ruedas(m: Malla, f: Malla.Marco, ancho: float, ejes: Array, r: float, llantas := true) -> void:
	for cv: float in ejes:
		for su in [-1.0, 1.0]:
			if not llantas:
				tapabarro(m, f, ancho, cv, r, su)
				continue
			var c := Malla.ngon(cv, r, r, 12)
			for i in 12:
				var a := c[i]
				var b := c[(i + 1) % 12]
				var n := ((a + b) / 2 - Vector2(cv, r)).normalized()
				m.cara([f.V(su * (ancho - 0.22), a.x, a.y), f.V(su * (ancho + 0.01), a.x, a.y), f.V(su * (ancho + 0.01), b.x, b.y),
					f.V(su * (ancho - 0.22), b.x, b.y)], Color(0.07, 0.07, 0.07), "pintura", f.N(0, n.x, n.y))
			var q := []
			for a in Malla.ngon(cv, r, r * 0.62, 12):
				q.append(f.V(su * (ancho + 0.012), a.x, a.y))
			m.cara(q, Color(0.55, 0.56, 0.58), "metal", f.N(su, 0))
			tapabarro(m, f, ancho, cv, r, su)


# el tapabarro: un arco oscuro sobre la rueda del eje cv, al lado su
static func tapabarro(m: Malla, f: Malla.Marco, ancho: float, cv: float, r: float, su: float) -> void:
	var q2 := []
	for k in 7:
		var t := PI * k / 6.0
		q2.append(Vector2(cv + cos(t) * (r + 0.06), r + sin(t) * (r + 0.06)))
	for k in 6:
		m.cara([f.V(su * (ancho + 0.004), q2[k].x, q2[k].y), f.V(su * (ancho + 0.004), q2[k + 1].x, q2[k + 1].y),
			f.V(su * (ancho + 0.004), cv + (q2[k + 1].x - cv) * 0.85, r + (q2[k + 1].y - r) * 0.85),
			f.V(su * (ancho + 0.004), cv + (q2[k].x - cv) * 0.85, r + (q2[k].y - r) * 0.85)], Color(0.1, 0.1, 0.1), "pintura", f.N(su, 0))


# un camión de 11,5 m (los de la Ruta 5 de la página: un quinto de sus autos, en la pista de la derecha): el chasis,
# la cabina con parabrisas y ventanas, la caja de carga del color de la instancia y seis ruedas por lado (dobles atrás)
static func camion(m: Malla, f: Malla.Marco, col: Color, choques: Malla = null) -> void:
	var L := CAMION_L / 2.0
	var a := 1.25
	if choques:
		choques.caja(f, -a, -L, a, L, 0.2, 3.6, col)
	var gris := Color(0.22, 0.22, 0.23)
	var cab := Color(0.88, 0.88, 0.86)  # las cabinas, casi siempre blancas
	m.caja(f, -1.0, -L + 0.2, 1.0, L - 0.3, 0.55, 0.95, gris, "metal")  # el chasis
	# la cabina: la trompa baja y el parabrisas inclinado
	var vc := L - 2.3
	m.caja(f, -1.2, vc, 1.2, L - 0.05, 0.95, 1.55, cab, "pintura")
	m.caja(f, -1.2, vc, 1.2, L - 0.55, 1.55, 3.05, cab, "pintura")
	m.cara([f.V(-1.2, L - 0.55, 1.55), f.V(1.2, L - 0.55, 1.55), f.V(1.2, L - 0.85, 2.9), f.V(-1.2, L - 0.85, 2.9)], VIDRIO, "vidrio", f.N(0, 1, 0.22))
	m.cara([f.V(-1.2, L - 0.55, 1.55), f.V(-1.2, L - 0.05, 1.55), f.V(1.2, L - 0.05, 1.55), f.V(1.2, L - 0.55, 1.55)], cab, "pintura", f.N(0, 0, 1))
	for sg in [-1.0, 1.0]:
		m.cara([f.V(sg * 1.205, vc + 0.3, 1.75), f.V(sg * 1.205, L - 0.75, 1.75), f.V(sg * 1.205, L - 0.75, 2.75), f.V(sg * 1.205, vc + 0.3, 2.75)], VIDRIO, "vidrio", f.N(sg, 0))
		m.cara([f.V(sg * 0.95, L - 0.045, 1.0), f.V(sg * 0.55, L - 0.045, 1.0), f.V(sg * 0.55, L - 0.045, 1.2), f.V(sg * 0.95, L - 0.045, 1.2)], Color(0.95, 0.95, 0.88), "vidrio", f.N(0, 1))
	m.caja(f, -1.25, L - 0.1, 1.25, L + 0.05, 0.6, 0.95, GRIS, "pintura")  # el parachoques
	# la caja de carga
	m.caja(f, -a, -L, a, vc - 0.25, 1.0, 3.6, col, "pintura")
	m.caja(f, -a - 0.01, -L - 0.01, a + 0.01, -L + 0.06, 1.1, 1.3, Color(0.72, 0.07, 0.05), "pintura")  # las luces de atrás
	ruedas(m, f, 1.18, [L - 1.45, -L + 3.3, -L + 1.9], 0.5)
