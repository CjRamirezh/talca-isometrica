# Las piezas de la plaza que no son suelo ni árboles: el quiosco, las tres piletas, el memorial de Carlos Spano, la
# estatua de Monseñor Larraín, los faroles, los escaños, los basureros y la losa del escudo municipal frente al
# quiosco. Cada una dice de qué foto sale y qué es aproximado. `p` es el nodo de la plaza (plaza.gd): sus ayudantes
# (instancia, shader, colision, formas, ocupar) y sus alturas (PAV: la cara de las baldosas).
extends RefCounted

const Malla = preload("res://modelos/plaza/malla.gd")
const Tx = preload("res://modelos/plaza/texturas.gd")

var p  # plaza.gd
var rng = RandomNumberGenerator.new()
var m_hierro: StandardMaterial3D
var m_pintura: StandardMaterial3D
var m_vidrio: StandardMaterial3D
var faroles: Array[Vector2] = []

const HIERRO := Color(0.10, 0.12, 0.11)        # el fierro fundido del quiosco (casi negro, verdoso)
const VERDE_FAROL := Color(0.16, 0.22, 0.20)   # faroles y basureros (fotos de 2018 y 2024)
const VERDE_PILETA := Color(0.16, 0.36, 0.30)  # la fuente de fierro de la pileta central (foto de 2018)
const AZUL := Color(0.22, 0.52, 0.86)          # el interior pintado de las piletas
const PIEDRA := Color(0.56, 0.56, 0.53)


func _init(plaza) -> void:
	p = plaza
	rng.seed = 2024
	m_hierro = StandardMaterial3D.new()
	m_hierro.vertex_color_use_as_albedo = true
	m_hierro.metallic = 0.5
	m_hierro.roughness = 0.45
	m_pintura = StandardMaterial3D.new()
	m_pintura.vertex_color_use_as_albedo = true
	m_pintura.roughness = 0.7
	m_vidrio = StandardMaterial3D.new()
	m_vidrio.albedo_color = Color(0.95, 0.92, 0.82)
	m_vidrio.emission_enabled = true
	m_vidrio.emission = Color(1.0, 0.86, 0.6)
	m_vidrio.emission_energy_multiplier = 0.15
	m_vidrio.roughness = 0.15


func construir() -> void:
	quiosco(p.QUIOSCO)
	losa_escudo(p.QUIOSCO + Vector2(10.3, 0))
	pileta_central(p.PILETA)
	pileta_chica(p.PILETA_N)
	pileta_chica(p.PILETA_O)
	spano(p.SPANO)
	larrain(p.LARRAIN)
	poner_faroles()


static func G(x: float, y: float, h: float) -> Vector3:
	return Vector3(x, h, -y)


func material_textura(tex: Texture2D) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(1, 1, 1)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.metallic = 0.5
	m.roughness = 0.45
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


# un octágono de radio r (al vértice) en c, girado a0
static func octogono(c: Vector2, r: float, a0 := PI / 8, k := 8) -> PackedVector2Array:
	var o = PackedVector2Array()
	for i in k:
		o.append(c + Vector2.from_angle(a0 + TAU * i / k) * r)
	return o


# ---- el quiosco ----

# Quiosco de fierro fundido, octogonal (OSM w223617018, ~8,8 m entre vértices). De las fotos de 2013 y 2014: base de
# sillares gris verdoso de ~1,35 m con una cornisa de piedra y una escalera de seis peldaños; ocho columnas delgadas
# con capitel; baranda calada; arcos rebajados calados entre las columnas; friso calado, cornisa, un frontón triangular
# con medallón en cada cara y una cresta semicircular en cada esquina; cielo de madera en tablas radiales; techo de
# zinc que sube a un tambor y una cúpula de escamas con remate. La escalera mira al oriente, hacia la losa del escudo
# (foto «Talca, plaza (15711413856)»: la losa delante de la escalera y un prado detrás a la derecha); el hito de la
# página la ponía al poniente, también sin fuente. Aproximado: las alturas (a ojo, con una persona de escala), el
# dibujo de la filigrana (texturas.gd) y el número de peldaños.
func quiosco(c2: Vector2) -> void:
	var PAV: float = p.PAV
	var R = 4.4
	var D = PAV + 1.35                       # el piso del quiosco
	var base = octogono(c2, R)
	var piedra = Malla.new()
	piedra.muros(base, PAV - 0.05, D - 0.1, Color(0.42, 0.45, 0.41))
	var corn = octogono(c2, R + 0.12)
	piedra.prisma(corn, D - 0.1, D, Color(0.52, 0.53, 0.49), Color(0.5, 0.49, 0.45))
	p.colision.prisma(corn, PAV - 0.05, D, Color.WHITE, Color.WHITE)
	# la escalera, en la cara oriente (entre los vértices de ±22,5°)
	var xf = R * cos(PI / 8)
	var esc = Malla.new()
	for i in 6:
		var h = PAV + (i + 1) * 0.225
		var largo = (6 - i) * 0.32
		var cx = c2.x + xf + largo / 2 - 0.05
		var q = PackedVector2Array([Vector2(cx - largo / 2, c2.y - 1.5), Vector2(cx + largo / 2, c2.y - 1.5), Vector2(cx + largo / 2, c2.y + 1.5), Vector2(cx - largo / 2, c2.y + 1.5)])
		esc.prisma(q, PAV - 0.02, h, Color(0.45, 0.46, 0.43), Color(0.52, 0.51, 0.48))
		p.colision.prisma(q, PAV - 0.02, h, Color.WHITE, Color.WHITE)
	p.instancia(piedra.malla(p.shader("piedra.gdshader", {"sillar": Vector2(0.62, 0.34)})))
	p.instancia(esc.malla(p.shader("piedra.gdshader", {"sillar": Vector2(0.5, 0.225)})))
	p.ocupar(c2 + Vector2(xf + 1.0, 0), 1.6)

	var C = G(c2.x, c2.y, D)
	var fe = Malla.new()
	var cols = octogono(c2, 4.05)
	var H = 3.0                               # de piso a cornisa
	for v in cols:
		fe.torno(G(v.x, v.y, D), [Vector2(0.15, 0), Vector2(0.15, 0.08), Vector2(0.1, 0.16), Vector2(0.08, 0.3), Vector2(0.075, 2.7),
			Vector2(0.1, 2.78), Vector2(0.15, 2.9), Vector2(0.16, 3.0), Vector2(0.0, 3.0)], 10, HIERRO)
		var cil = CylinderShape3D.new()
		cil.radius = 0.12
		cil.height = H
		p.formas.append([cil, Transform3D(Basis(), G(v.x, v.y, D + H / 2))])
	# baranda, arcos y friso: paños calados entre columnas
	var baranda = Malla.new()
	var arcos = Malla.new()
	var friso = Malla.new()
	for i in 8:
		var a = cols[i]; var b = cols[(i + 1) % 8]
		var mid = (a + b) / 2
		var nn = Vector3(mid.x - c2.x, 0, -(mid.y - c2.y)).normalized()
		var ab = (b - a).normalized()
		var a2 = a + ab * 0.08; var b2 = b - ab * 0.08
		var este: bool = mid.x - c2.x > 3.0 and abs(mid.y - c2.y) < 1.0
		if not este:
			baranda.quad(G(a2.x, a2.y, D + 0.05), G(b2.x, b2.y, D + 0.05), G(b2.x, b2.y, D + 0.95), G(a2.x, a2.y, D + 0.95), Color.WHITE, nn,
				[Vector2(0, 1), Vector2(2.4, 1), Vector2(2.4, 0), Vector2(0, 0)])
			p.colision.quad(G(a.x, a.y, D), G(b.x, b.y, D), G(b.x, b.y, D + 1.0), G(a.x, a.y, D + 1.0), Color.WHITE, nn)
			# pasamanos
			fe.tubo(G(a.x, a.y, D + 0.97), G(b.x, b.y, D + 0.97), 0.035, 0.035, 6, HIERRO, HIERRO)
		arcos.quad(G(a2.x, a2.y, D + 2.2), G(b2.x, b2.y, D + 2.2), G(b2.x, b2.y, D + 2.95), G(a2.x, a2.y, D + 2.95), Color.WHITE, nn,
			[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		var fa = c2 + (a - c2) * 1.04; var fb = c2 + (b - c2) * 1.04
		friso.quad(G(fa.x, fa.y, D + 3.08), G(fb.x, fb.y, D + 3.08), G(fb.x, fb.y, D + 3.55), G(fa.x, fa.y, D + 3.55), Color.WHITE, nn,
			[Vector2(0, 1), Vector2(2.0, 1), Vector2(2.0, 0), Vector2(0, 0)])
		# frontón triangular con medallón
		var pa = c2 + (a - c2) * 1.08 + ab * 0.6; var pb = c2 + (b - c2) * 1.08 - ab * 0.6
		var pm = (pa + pb) / 2
		fe.tri(G(pa.x, pa.y, D + 3.68), G(pb.x, pb.y, D + 3.68), G(pm.x, pm.y, D + 4.3), HIERRO, nn)
		fe.tri(G(pa.x, pa.y, D + 3.68), G(pb.x, pb.y, D + 3.68), G(pm.x, pm.y, D + 4.3), HIERRO, -nn)
		var med = G(pm.x, pm.y, D + 3.9) + nn * 0.03
		var up = Vector3.UP; var lado = Vector3(ab.x, 0, -ab.y)
		for k in 12:
			var t0 = TAU * k / 12; var t1 = TAU * (k + 1) / 12
			fe.tri(med, med + (lado * cos(t0) + up * sin(t0)) * 0.17, med + (lado * cos(t1) + up * sin(t1)) * 0.17, Color(0.2, 0.22, 0.2), nn)
		# la cresta semicircular sobre cada esquina
		var cr = c2 + (a - c2) * 1.07
		var tg = Vector3(-(a - c2).y, 0, -(a - c2).x).normalized()  # tangente (Godot)
		var no = Vector3(a.x - c2.x, 0, -(a.y - c2.y)).normalized()
		var cb = G(cr.x, cr.y, D + 3.68)
		for k in 8:
			var t0 = PI * k / 8; var t1 = PI * (k + 1) / 8
			fe.tri(cb, cb + (tg * cos(t0) + up * sin(t0)) * 0.42, cb + (tg * cos(t1) + up * sin(t1)) * 0.42, HIERRO, no)
			fe.tri(cb, cb + (tg * cos(t0) + up * sin(t0)) * 0.42, cb + (tg * cos(t1) + up * sin(t1)) * 0.42, HIERRO, -no)
	# franjas macizas del entablamento y la cornisa
	fe.muros(octogono(c2, 4.22), D + 2.98, D + 3.08, HIERRO)
	fe.muros(octogono(c2, 4.22), D + 3.55, D + 3.62, HIERRO)
	fe.prisma(octogono(c2, 4.45), D + 3.62, D + 3.72, HIERRO, HIERRO)
	# el cielo de madera (tablas radiales), visto desde abajo
	var madera = Malla.new()
	madera.torno(C + Vector3.UP * 3.0, [Vector2(0.0, 0.95), Vector2(4.2, 0.0)], 8,
		Color(0.55, 0.36, 0.2), PI / 8, false)
	for k in 32:
		var t = TAU * k / 32
		madera.tubo(C + Vector3.UP * 3.93, C + Vector3(cos(t) * 4.1, 2.99, sin(t) * 4.1), 0.02, 0.02, 3, Color(0.4, 0.25, 0.13), Color(0.4, 0.25, 0.13))
	p.instancia(madera.malla(m_pintura))
	# techo de zinc, tambor y cúpula de escamas con remate
	var zinc = Malla.new()
	zinc.torno(C + Vector3.UP * 3.72, [Vector2(4.4, 0.0), Vector2(2.35, 0.55)], 8, Color.WHITE, PI / 8, false)
	zinc.torno(C + Vector3.UP * 4.6, [Vector2(2.3, 0.0), Vector2(2.25, 0.35), Vector2(2.0, 0.85), Vector2(1.55, 1.25), Vector2(0.95, 1.55),
		Vector2(0.4, 1.72), Vector2(0.0, 1.76)], 32, Color.WHITE)
	p.instancia(zinc.malla(p.shader("zinc.gdshader")))
	fe.muros(octogono(c2, 2.32), D + 4.25, D + 4.62, HIERRO)
	fe.torno(C + Vector3.UP * 6.3, [Vector2(0.12, 0), Vector2(0.2, 0.15), Vector2(0.2, 0.3), Vector2(0.06, 0.45), Vector2(0.05, 0.6),
		Vector2(0.14, 0.7), Vector2(0.14, 0.85), Vector2(0.03, 1.0), Vector2(0.0, 1.25)], 10, HIERRO)
	# crestería: puntas sobre el borde del techo
	for k in 48:
		var t = TAU * k / 48
		var b = C + Vector3(cos(t) * 3.9, 3.8, sin(t) * 3.9)
		fe.tubo(b, b + Vector3.UP * 0.22, 0.015, 0.004, 3, HIERRO, HIERRO)
	p.instancia(fe.malla(m_hierro))
	p.instancia(baranda.malla(material_textura(Tx.filigrana())))
	p.instancia(arcos.malla(material_textura(Tx.arco())))
	p.instancia(friso.malla(material_textura(Tx.filigrana(true))))


# La losa lisa con el escudo de la Municipalidad pintado en rojo ladrillo, delante de la escalera del quiosco (foto de
# 2014 «Talca, plaza (15711413856)»: «I. MUNICIPALIDAD DE TALCA», «MINVU ABRIL 2007»). Medidas a ojo; el escudo, un
# dibujo de volutas que no copia el real.
func losa_escudo(c2: Vector2) -> void:
	var PAV: float = p.PAV
	var q = PackedVector2Array([c2 + Vector2(-2.4, -3.9), c2 + Vector2(2.4, -3.9), c2 + Vector2(2.4, 3.9), c2 + Vector2(-2.4, 3.9)])
	var m = Malla.new()
	m.plano(q, PAV + 0.006, Color(0.6, 0.59, 0.56))
	p.instancia(m.malla(p.shader("piedra.gdshader", {"rugoso": 0.7})), Transform3D.IDENTITY, false)
	var rojo = Color(0.62, 0.24, 0.2)
	# el escudo: un dibujo plano con transparencia sobre la losa
	var L = Tx._lienzo(256, 256, 9, rojo)
	L.linea(70, 50, 186, 50, 5, 5, rojo)
	L.linea(70, 50, 70, 150, 5, 5, rojo)
	L.linea(186, 50, 186, 150, 5, 5, rojo)
	for i in 40:
		var t = float(i) / 40.0
		L.linea(70 + t * 58, 150 + sin(t * PI / 2) * 50, 70 + (t + 0.025) * 58, 150 + sin(min(1.0, t + 0.025) * PI / 2) * 50, 5, 5, rojo)
		L.linea(186 - t * 58, 150 + sin(t * PI / 2) * 50, 186 - (t + 0.025) * 58, 150 + sin(min(1.0, t + 0.025) * PI / 2) * 50, 5, 5, rojo)
	for s in [-1, 1]:
		L.anillo(128 + s * 95, 70, 22, 4, rojo)
		L.anillo(128 + s * 95, 70, 9, 3, rojo)
		L.anillo(128 + s * 85, 160, 18, 4, rojo)
		L.linea(128 + s * 60, 30, 128 + s * 117, 50, 4, 3, rojo)
	L.linea(90, 100, 166, 100, 3, 3, rojo)
	L.anillo(128, 80, 14, 3, rojo)
	var mt = material_textura(L.textura())
	mt.metallic = 0.0
	mt.roughness = 0.75
	var e = Malla.new()
	var a = c2 + Vector2(-2.3, 0.0)
	e.quad(G(a.x, a.y - 1.8, PAV + 0.009), G(a.x + 3.0, a.y - 1.8, PAV + 0.009), G(a.x + 3.0, a.y + 1.8, PAV + 0.009), G(a.x, a.y + 1.8, PAV + 0.009),
		Color.WHITE, Vector3.UP, [Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1)])
	p.instancia(e.malla(mt), Transform3D.IDENTITY, false)
	# los textos, tendidos en la losa, para leerse desde el oriente (arriba del texto hacia el quiosco)
	var bs = Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))
	for t in [["I. MUNICIPALIDAD\nDE TALCA", Vector2(1.5, 0.0), 0.006, 96], ["MINVU\nABRIL 2007", Vector2(2.05, 2.9), 0.0035, 64]]:
		var l = Label3D.new()
		l.text = t[0]
		l.font_size = t[3]
		l.pixel_size = t[2]
		l.modulate = rojo
		l.outline_size = 0
		l.shaded = true
		l.double_sided = false
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var pos: Vector2 = c2 + t[1]
		l.transform = Transform3D(bs, G(pos.x, pos.y, PAV + 0.012))
		p.add_child(l)


# ---- las piletas ----

# La pileta central (OSM n3428801388; foto de 2018 «Talca Plaza (5)»): un tazón redondo de piedra gris de ~6,4 m con
# borde moldurado a 0,75 m, el interior pintado de azul, un pedestal en cruz al medio y la fuente de fierro verde de dos
# platos con remate. El agua es una licencia: la foto la muestra casi vacía.
func pileta_central(c2: Vector2) -> void:
	var PAV: float = p.PAV
	var Rb = 3.2
	var C = G(c2.x, c2.y, PAV)
	tazon(C, Rb, 0.75, 0.35)
	var ped = Malla.new()
	for q in [[0.42, 0.42], [1.15, 0.22], [0.22, 1.15]]:
		ped.caja(C + Vector3.UP * 0.47, Vector3(q[0] * 2, 0.56, q[1] * 2), PIEDRA)
	p.instancia(ped.malla(p.shader("piedra.gdshader")))
	var f = Malla.new()
	var b = C + Vector3.UP * 0.75
	f.torno(b, [Vector2(0.4, 0), Vector2(0.4, 0.1), Vector2(0.28, 0.2), Vector2(0.22, 0.45), Vector2(0.15, 0.8), Vector2(0.13, 1.25),
		Vector2(0.22, 1.33), Vector2(0.9, 1.5), Vector2(1.0, 1.62), Vector2(0.95, 1.66), Vector2(0.2, 1.52), Vector2(0.11, 1.55),
		Vector2(0.1, 1.75), Vector2(0.16, 1.85), Vector2(0.12, 2.05), Vector2(0.09, 2.35), Vector2(0.16, 2.42), Vector2(0.5, 2.55),
		Vector2(0.55, 2.64), Vector2(0.5, 2.67), Vector2(0.1, 2.58), Vector2(0.07, 2.7), Vector2(0.12, 2.8), Vector2(0.05, 3.0),
		Vector2(0.09, 3.1), Vector2(0.0, 3.25)], 20, VERDE_PILETA)
	p.instancia(f.malla(m_hierro))
	var cil = CylinderShape3D.new()
	cil.radius = 0.5
	cil.height = 1.0
	p.formas.append([cil, Transform3D(Basis(), b + Vector3.UP * 0.5)])
	var plato = Malla.new()
	var d1 = PackedVector2Array(); var d2 = PackedVector2Array()
	for k in 24:
		d1.append(c2 + Vector2.from_angle(TAU * k / 24) * 0.93)
		d2.append(c2 + Vector2.from_angle(TAU * k / 24) * 0.5)
	plato.plano(d1, PAV + 0.75 + 1.6, Color.WHITE)
	plato.plano(d2, PAV + 0.75 + 2.62, Color.WHITE)
	p.instancia(plato.malla(p.shader("agua.gdshader", {"alfa": 0.7})), Transform3D.IDENTITY, false)


# un tazón redondo de piedra con el interior azul y agua: borde de alto h y grueso g, con una moldura volada arriba
func tazon(C: Vector3, R: float, h: float, g: float) -> void:
	var PAV: float = p.PAV
	var m = Malla.new()
	var perfil = [Vector2(R, -0.03), Vector2(R, h - 0.12), Vector2(R + 0.07, h - 0.12), Vector2(R + 0.07, h), Vector2(R - g, h),
		Vector2(R - g, 0.2), Vector2(0.0, 0.2)]
	var cols = [PIEDRA * 0.95, PIEDRA * 0.9, PIEDRA, PIEDRA * 1.08, AZUL, AZUL, AZUL]
	for i in cols.size():
		cols[i].a = 1.0
	m.torno(C, perfil, 48, func(i): return cols[min(i, cols.size() - 1)], 0.0, false)
	p.instancia(m.malla(p.shader("piedra.gdshader", {"rugoso": 0.8})))
	p.colision.torno(C, [Vector2(R + 0.07, -0.03), Vector2(R + 0.07, h), Vector2(R - g, h), Vector2(R - g, 0.2), Vector2(0.0, 0.2)], 16, Color.WHITE)
	var agua = PackedVector2Array()
	for k in 40:
		agua.append(Vector2(C.x, -C.z) + Vector2.from_angle(TAU * k / 40) * (R - g + 0.01))
	var a = Malla.new()
	a.plano(agua, C.y + h - 0.2, Color.WHITE)
	p.instancia(a.malla(p.shader("agua.gdshader")), Transform3D.IDENTITY, false)
	p.ocupar(Vector2(C.x, -C.z), R + 0.8)


# Las piletas norte y poniente (OSM n11021259067, n3428801896): no hay fotos de ellas. Tazones de 5,2 m pintados de
# azul por dentro (la poniente se ve azul en la imagen de Esri) con un surtidor de piedra al medio, como en el hito.
func pileta_chica(c2: Vector2) -> void:
	var C = G(c2.x, c2.y, p.PAV)
	tazon(C, 2.6, 0.6, 0.3)
	var m = Malla.new()
	m.torno(C + Vector3.UP * 0.2, [Vector2(0.35, 0), Vector2(0.35, 0.5), Vector2(0.25, 0.6), Vector2(0.15, 1.4), Vector2(0.3, 1.5),
		Vector2(0.3, 1.6), Vector2(0.1, 1.65), Vector2(0.06, 1.9), Vector2(0.0, 1.95)], 12, PIEDRA * 1.05)
	p.instancia(m.malla(p.shader("piedra.gdshader")))



# ---- memoriales ----

# El memorial del coronel Carlos Spano (OSM n11021258973, «historic=memorial», inscripción de 1971; fotos de 2017 y
# 2024 «…en 2024 02»): un macizo redondo de 7,8 m (OSM w1186645150) con solera blanca de borde verde, reja de aros y
# begonias; un pedestal blanco de hormigón y la losa de granito gris, de canto irregular arriba, con la inscripción
# hacia el sur. Medidas a ojo.
func spano(c2: Vector2) -> void:
	var PAV: float = p.PAV
	var C = G(c2.x, c2.y, PAV)
	var R = 3.9
	var m = Malla.new()
	var blanco = Color(0.9, 0.89, 0.85)
	var verde = Color(0.24, 0.38, 0.3)
	var cols = [blanco, verde, verde, Color(0.3, 0.24, 0.18)]
	m.torno(C, [Vector2(R, -0.03), Vector2(R, 0.3), Vector2(R - 0.22, 0.3), Vector2(R - 0.22, 0.24), Vector2(0.0, 0.24)], 48,
		func(i): return cols[min(i, 3)], 0.0, false)
	p.instancia(m.malla(p.shader("piedra.gdshader", {"rugoso": 0.85})))
	p.colision.torno(C, [Vector2(R, -0.03), Vector2(R, 0.3), Vector2(R - 0.22, 0.3), Vector2(R - 0.22, 0.24), Vector2(0.0, 0.24)], 16, Color.WHITE)
	# reja de aros
	var rj = Malla.new()
	for k in 40:
		var t0 = TAU * k / 40; var t1 = TAU * (k + 1) / 40
		var a = C + Vector3(cos(t0), 0, sin(t0)) * (R - 0.4); var b = C + Vector3(cos(t1), 0, sin(t1)) * (R - 0.4)
		var l = a.distance_to(b)
		rj.quad(a + Vector3.UP * 0.24, b + Vector3.UP * 0.24, b + Vector3.UP * 0.6, a + Vector3.UP * 0.6, Color.WHITE,
			Vector3(cos((t0 + t1) / 2), 0, sin((t0 + t1) / 2)), [Vector2(k * l / 0.8, 1), Vector2((k + 1) * l / 0.8, 1), Vector2((k + 1) * l / 0.8, 0), Vector2(k * l / 0.8, 0)])
	var mr = material_textura(Tx.reja())
	mr.albedo_color = Color(1.3, 1.6, 1.4)
	p.instancia(rj.malla(mr))
	# begonias: tarjetas bajas con flores rojas, rosadas y blancas
	var fl = Malla.new()
	var tex = Tx.flores(31, [Color(0.85, 0.15, 0.2), Color(0.95, 0.45, 0.6), Color(0.97, 0.95, 0.93), Color(0.8, 0.1, 0.35)])
	for k in 70:
		var r = sqrt(rng.randf()) * (R - 0.6)
		if r < 0.75:
			continue
		var t = rng.randf() * TAU
		var q = C + Vector3(cos(t) * r, 0.24 + rng.randf_range(0.08, 0.18), sin(t) * r)
		var az = rng.randf() * TAU
		var u = Vector3(cos(az), 0, sin(az)) * 0.32
		var v = Vector3(-sin(az), 0, cos(az)) * 0.32
		fl.quad(q - u - v, q + u - v, q + u + v, q - u + v, Color.WHITE, Vector3.UP, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		fl.quad(q - u + Vector3.DOWN * 0.15, q + u + Vector3.DOWN * 0.15, q + u + Vector3.UP * 0.12, q - u + Vector3.UP * 0.12, Color.WHITE,
			Vector3.UP, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	var mf = material_textura(tex)
	mf.metallic = 0.0
	mf.roughness = 0.8
	p.instancia(fl.malla(mf), Transform3D.IDENTITY, false)
	# el pedestal y la losa
	var ped = Malla.new()
	ped.torno(C + Vector3.UP * 0.24, [Vector2(0.62, 0), Vector2(0.62, 0.08), Vector2(0.5, 0.16), Vector2(0.42, 0.3), Vector2(0.4, 0.68),
		Vector2(0.48, 0.78), Vector2(0.56, 0.84), Vector2(0.56, 0.92), Vector2(0.0, 0.92)], 20, blanco)
	p.instancia(ped.malla(p.shader("piedra.gdshader", {"rugoso": 0.8})))
	var cil = CylinderShape3D.new()
	cil.radius = 0.6
	cil.height = 2.9
	p.formas.append([cil, Transform3D(Basis(), C + Vector3.UP * 1.45)])
	var losa = Malla.new()
	var y0 = PAV + 1.16
	var contorno = [Vector2(-0.62, 0), Vector2(0.62, 0), Vector2(0.64, 1.45), Vector2(0.5, 1.62), Vector2(0.3, 1.58), Vector2(0.1, 1.72),
		Vector2(-0.15, 1.66), Vector2(-0.35, 1.74), Vector2(-0.55, 1.6), Vector2(-0.66, 1.5)]
	var gr = Color(0.56, 0.57, 0.56)
	var e = 0.15
	for k in contorno.size():
		var a: Vector2 = contorno[k]; var b: Vector2 = contorno[(k + 1) % contorno.size()]
		var nn = Vector3(b.y - a.y, -(b.x - a.x), 0).normalized()
		losa.quad(G(c2.x + a.x, c2.y - e, y0 + a.y), G(c2.x + b.x, c2.y - e, y0 + b.y), G(c2.x + b.x, c2.y + e, y0 + b.y), G(c2.x + a.x, c2.y + e, y0 + a.y), gr, nn)
	for s in [-1.0, 1.0]:
		for k in range(1, contorno.size() - 1):
			var a: Vector2 = contorno[0]; var b: Vector2 = contorno[k]; var d: Vector2 = contorno[k + 1]
			losa.tri(G(c2.x + a.x, c2.y + s * e, y0 + a.y), G(c2.x + b.x, c2.y + s * e, y0 + b.y), G(c2.x + d.x, c2.y + s * e, y0 + d.y),
				gr, Vector3(0, 0, -s))
	p.instancia(losa.malla(p.shader("piedra.gdshader", {"rugoso": 0.6})))
	var l = Label3D.new()
	l.text = "CORONEL\nCARLOS SPANO\nAQUÍ CAYÓ HEROICAMENTE JUNTO\nA LA BANDERA DE CHILE, 4 - III - 1814.\nO'HIGGINS ORDENÓ RENDIR ESTE HOMENAJE:\n\"LA PATRIA AGRADECIDA AL HÉROE DE TALCA\".\nINSTITUTO DE CONMEMORACIÓN HISTÓRICA DE CHILE 1971\nINICIATIVA DE HISTORIA Y GEOGRAFÍA\nDE TALCA 13 - IX - 1971"
	l.font_size = 40
	l.pixel_size = 0.0017
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = 1.08 / 0.0017
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate = Color(0.2, 0.2, 0.2)
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = G(c2.x, c2.y - e - 0.006, y0 + 0.85)
	l.rotation.y = 0.0  # mira a +Z de Godot: el sur
	p.add_child(l)
	p.ocupar(c2, R + 0.3)


# Monseñor Manuel Larraín, obispo de Talca de 1939 a 1966 (OSM n11021259030, estatua de 1972–1973; foto de 2005 «Talca
# plaza armas larrain», del escultor G. Albridi según la firma en la base): de pie, con sotana abotonada, muceta y
# cruz pectoral, sobre una base de piedra con la firma y una grada. Una figura simplificada (tornos y tubos) de 2,3 m;
# mira hacia el centro de la plaza (la foto no dice hacia dónde).
func larrain(c2: Vector2) -> void:
	var PAV: float = p.PAV
	var gris = Color(0.64, 0.63, 0.6)
	var m = Malla.new()
	var C = G(c2.x, c2.y, PAV)
	var ang = atan2(-c2.x, c2.y)  # el frente (+Z local) hacia el centro
	var bs = Basis(Vector3.UP, ang)
	var L = func(x: float, y: float, z: float) -> Vector3: return C + bs * Vector3(x, y, z)
	m.caja(L.call(0, 0.15, 0), Vector3(1.8, 0.36, 1.8), gris * 0.85, ang)
	m.caja(L.call(0, 0.62, 0), Vector3(1.25, 0.58, 0.9), gris, ang)
	var f = Malla.new()
	var pie = Vector3(0, 0.92, 0)
	f.caja(pie + Vector3.UP * 0.05, Vector3(0.6, 0.1, 0.5), gris)
	f.torno(pie + Vector3.UP * 0.1, [Vector2(0.38, 0), Vector2(0.36, 0.12), Vector2(0.3, 0.6), Vector2(0.25, 1.05), Vector2(0.22, 1.32),
		Vector2(0.24, 1.42), Vector2(0.25, 1.6), Vector2(0.2, 1.72), Vector2(0.08, 1.8), Vector2(0.07, 1.86), Vector2(0.0, 1.86)], 14, gris)
	f.torno(pie + Vector3.UP * 1.38, [Vector2(0.35, 0), Vector2(0.33, 0.08), Vector2(0.27, 0.28), Vector2(0.14, 0.4), Vector2(0.0, 0.42)], 14, gris * 1.02)
	f.torno(pie + Vector3.UP * 1.84, [Vector2(0.0, 0), Vector2(0.08, 0.04), Vector2(0.105, 0.14), Vector2(0.1, 0.24), Vector2(0.06, 0.3), Vector2(0.0, 0.31)], 12, gris * 1.04)
	for s in [-1.0, 1.0]:
		var hombro = pie + Vector3(s * 0.27, 1.6, 0.0)
		var codo = pie + Vector3(s * 0.31, 1.25, 0.06)
		var mano = pie + Vector3(s * 0.29, 0.98, 0.14)
		f.tubo(hombro, codo, 0.075, 0.07, 8, gris, gris)
		f.tubo(codo, mano, 0.07, 0.06, 8, gris, gris)
		f.torno(mano + Vector3.DOWN * 0.06, [Vector2(0.0, 0), Vector2(0.05, 0.04), Vector2(0.045, 0.1), Vector2(0.0, 0.12)], 8, gris)
	# la cruz pectoral
	f.caja(pie + Vector3(0, 1.4, 0.27), Vector3(0.04, 0.18, 0.03), gris * 0.9)
	f.caja(pie + Vector3(0, 1.44, 0.27), Vector3(0.12, 0.04, 0.03), gris * 0.9)
	for k in 9:
		f.caja(pie + Vector3(0, 0.35 + k * 0.13, 0.345 - 0.012 * k), Vector3(0.03, 0.03, 0.02), gris * 0.88)
	var mf = f.malla(p.shader("piedra.gdshader", {"rugoso": 0.75}))
	var mb = m.malla(p.shader("piedra.gdshader", {"sillar": Vector2(0.0, 0.0)}))
	p.instancia(mb)
	p.instancia(mf, Transform3D(bs, C))
	var l = Label3D.new()
	l.text = "MONS. MANUEL LARRAÍN\nOBISPO DE TALCA\n1939 - 1966\n\"VEN SEÑOR JESÚS\""
	l.font_size = 36
	l.pixel_size = 0.0028
	l.modulate = Color(0.3, 0.3, 0.3)
	l.outline_size = 0
	l.shaded = true
	l.transform = Transform3D(bs, L.call(0, 0.62, 0.456))
	p.add_child(l)
	var caja = BoxShape3D.new()
	caja.size = Vector3(1.8, 3.4, 1.8)
	p.formas.append([caja, Transform3D(bs, C + Vector3.UP * 1.7)])
	p.ocupar(c2, 1.4)


# ---- faroles, escaños y basureros ----

# El farol de la plaza (fotos de 2018 «Talca Plaza (5)» y 2024 «02», «03»): poste de fierro verde oscuro de ~4,6 m
# con base, anillos y un farol de cuatro caras con sombrerete; a 3 m, dos brazos curvos con maceteros colgantes de
# greda con flores. Cada farol se arma completo (los brazos giran con él).
func farol_malla() -> ArrayMesh:
	var f = Malla.new()
	f.torno(Vector3.ZERO, [Vector2(0.21, -0.02), Vector2(0.21, 0.32), Vector2(0.17, 0.38), Vector2(0.17, 0.44), Vector2(0.11, 0.55),
		Vector2(0.09, 0.62), Vector2(0.085, 1.2), Vector2(0.105, 1.24), Vector2(0.085, 1.3), Vector2(0.065, 2.9), Vector2(0.09, 2.95),
		Vector2(0.09, 3.05), Vector2(0.06, 3.1), Vector2(0.055, 3.75), Vector2(0.1, 3.8), Vector2(0.14, 3.86), Vector2(0.0, 3.87)], 8, VERDE_FAROL, PI / 8, false)
	# el farol: cuatro montantes, vidrio y sombrerete
	var v = Malla.new()
	for k in 4:
		var t0 = PI / 4 + k * PI / 2; var t1 = t0 + PI / 2
		var a0 = Vector3(cos(t0), 0, sin(t0)); var a1 = Vector3(cos(t1), 0, sin(t1))
		v.quad(a0 * 0.15 + Vector3.UP * 3.87, a1 * 0.15 + Vector3.UP * 3.87, a1 * 0.22 + Vector3.UP * 4.45, a0 * 0.22 + Vector3.UP * 4.45, Color.WHITE,
			((a0 + a1) / 2).normalized())
		f.tubo(a0 * 0.16 + Vector3.UP * 3.86, a0 * 0.23 + Vector3.UP * 4.46, 0.018, 0.018, 4, VERDE_FAROL, VERDE_FAROL)
	f.torno(Vector3.UP * 4.44, [Vector2(0.24, 0), Vector2(0.3, 0.04), Vector2(0.28, 0.08), Vector2(0.12, 0.28), Vector2(0.05, 0.32),
		Vector2(0.05, 0.42), Vector2(0.0, 0.5)], 4, VERDE_FAROL, PI / 4, false)
	# brazos y maceteros
	var greda = Color(0.72, 0.38, 0.22)
	var fl = Malla.new()
	for s in [-1.0, 1.0]:
		var a = Vector3(0.06 * s, 3.0, 0); var b = Vector3(0.35 * s, 3.12, 0); var c = Vector3(0.58 * s, 3.05, 0)
		f.tubo(a, b, 0.022, 0.02, 5, VERDE_FAROL, VERDE_FAROL)
		f.tubo(b, c, 0.02, 0.018, 5, VERDE_FAROL, VERDE_FAROL)
		var m0 = Vector3(0.58 * s, 2.62, 0)
		for k in 3:
			var t = TAU * k / 3
			f.tubo(c, m0 + Vector3(cos(t), 0.18, sin(t)) * 0.13, 0.006, 0.006, 3, VERDE_FAROL, VERDE_FAROL)
		f.torno(m0, [Vector2(0.0, 0), Vector2(0.09, 0.0), Vector2(0.14, 0.17), Vector2(0.155, 0.2), Vector2(0.13, 0.2), Vector2(0.0, 0.17)], 12, greda)
		for k in 3:
			var t = TAU * k / 3 + 0.4
			var u = Vector3(cos(t), 0, sin(t)) * 0.2
			fl.quad(m0 + u * -1 + Vector3.UP * 0.12, m0 + u + Vector3.UP * 0.12, m0 + u + Vector3.UP * 0.45, m0 - u + Vector3.UP * 0.45,
				Color.WHITE, Vector3.UP, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	var m = f.malla(m_hierro)
	v.malla(m_vidrio, m)
	var mf = material_textura(Tx.flores(41, [Color(0.9, 0.2, 0.3), Color(0.95, 0.6, 0.2), Color(0.85, 0.3, 0.6)], 60))
	mf.metallic = 0.0
	fl.malla(mf, m)
	return m


# Dónde: cuatro en diagonal alrededor de la pileta central (el hito), uno en cada paseo diagonal donde cruza el anillo
# (foto de 2024 «01»: un farol al medio del paseo) y dos en cada plazoleta de los ejes, a la entrada y a la salida.
# Las posiciones, salvo las del hito, son aproximadas.
func poner_faroles() -> void:
	var mesh = farol_malla()
	var lista: Array[Vector2] = []
	for k in 4:
		lista.append(p.PILETA + Vector2.from_angle(PI / 4 + k * PI / 2) * 8.6)
	for k in 4:
		var d = Vector2.from_angle(PI / 4 + k * PI / 2)
		lista.append(Vector2(0.2, -1.2) + d * 21.8)
		lista.append(Vector2(0.2, -1.2) + d * 38.0)
	for eje in [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]:
		var lado = Vector2(-eje.y, eje.x)
		for r in [23.6, 37.0]:
			for s in [-1.0, 1.0]:
				lista.append(Vector2(0.2, -1.2) + eje * r + lado * s * 5.5)
	for q in lista:
		if p.en_prado(q, 0.4) >= 0 or not p.libre(q, 0.8):
			continue
		var t = atan2(q.y + 1.2, q.x - 0.2)
		p.instancia(mesh, Transform3D(Basis(Vector3.UP, -t), G(q.x, q.y, p.PAV)))
		var cil = CylinderShape3D.new()
		cil.radius = 0.2
		cil.height = 4.4
		p.formas.append([cil, Transform3D(Basis(), G(q.x, q.y, p.PAV + 2.2))])
		p.ocupar(q, 0.8)
		faroles.append(q)
	p.stats["faroles"] = faroles.size()


# El escaño (fotos de 2013 «Plaza de armas de Talca2» y 2018): costados de fierro fundido con volutas, asiento de cinco
# listones y respaldo de tres, de madera pintada de verde; 1,8 m.
func escano_malla() -> ArrayMesh:
	var f = Malla.new()
	var verde = Color(0.17, 0.34, 0.22)
	for s in [-0.85, 0.85]:
		var P = func(y: float, z: float) -> Vector3: return Vector3(s, y, z)
		f.tubo(P.call(0, 0.24), P.call(0.45, 0.2), 0.03, 0.025, 5, HIERRO, HIERRO)          # pata delantera
		f.tubo(P.call(0, -0.26), P.call(0.45, -0.22), 0.03, 0.025, 5, HIERRO, HIERRO)       # pata trasera
		f.tubo(P.call(0.45, -0.22), P.call(0.86, -0.36), 0.025, 0.02, 5, HIERRO, HIERRO)    # respaldo
		f.tubo(P.call(0.43, 0.24), P.call(0.43, -0.24), 0.025, 0.025, 5, HIERRO, HIERRO)    # bajo el asiento
		f.tubo(P.call(0.66, -0.28), P.call(0.66, 0.2), 0.022, 0.022, 5, HIERRO, HIERRO)     # brazo
		f.tubo(P.call(0.66, 0.2), P.call(0.56, 0.27), 0.022, 0.02, 5, HIERRO, HIERRO)
		f.tubo(P.call(0.56, 0.27), P.call(0.45, 0.22), 0.02, 0.02, 5, HIERRO, HIERRO)
		f.tubo(P.call(0.03, 0.24), P.call(0.12, 0.33), 0.025, 0.02, 5, HIERRO, HIERRO)      # voluta del pie
		f.tubo(P.call(0.03, -0.26), P.call(0.12, -0.35), 0.025, 0.02, 5, HIERRO, HIERRO)
	for k in 5:
		f.caja(Vector3(0, 0.47, 0.2 - k * 0.1), Vector3(1.85, 0.035, 0.075), verde)
	for k in 3:
		var y = 0.6 + k * 0.1
		f.caja(Vector3(0, y, -0.27 - (y - 0.45) * 0.34), Vector3(1.85, 0.075, 0.03), verde, 0.0)
	return f.malla(m_hierro)


func basurero_malla() -> ArrayMesh:
	var f = Malla.new()
	f.caja(Vector3(0, 0.5, -0.24), Vector3(0.07, 1.0, 0.07), VERDE_FAROL)
	f.caja(Vector3(0, 0.6, 0), Vector3(0.42, 0.62, 0.42), VERDE_FAROL)
	f.caja(Vector3(0, 0.93, 0), Vector3(0.46, 0.04, 0.46), VERDE_FAROL * 0.8)
	return f.malla(m_hierro)


# Dónde: al borde de los paseos, con el respaldo hacia el prado (foto de 2024 «01»), a 0,75 m de la solera, cada
# ~8 m en los tramos de solera de más de 3,5 m, sin tocar faroles, piletas ni otros escaños; un basurero junto a uno de
# cada tres. Aproximado: las fotos muestran escaños así, no dónde están todos.
func poner_escanos() -> void:
	var esc = escano_malla()
	var bas = basurero_malla()
	var n = 0; var nb = 0
	var interior: PackedVector2Array = Malla.adentro(p.pz, 1.2)
	for i in p.prados.size():
		var q: PackedVector2Array = p.prados[i]
		var sgn = 1.0 if Malla.area(q) > 0 else -1.0
		for k in q.size():
			var a = q[k]; var b = q[(k + 1) % q.size()]
			var l = a.distance_to(b)
			if l < 6.0:
				continue
			var d = (b - a) / l
			var afuera = Vector2(d.y, -d.x) * sgn
			var cuantos = int((l + 4.0) / 13.0)
			for j in cuantos:
				var s = l * (j + 0.5) / cuantos
				var c = a + d * s + afuera * 0.75
				var esquinas = [c + d * 0.95 + afuera * 0.35, c - d * 0.95 + afuera * 0.35, c + d * 0.95 - afuera * 0.35, c - d * 0.95 - afuera * 0.35]
				var ok: bool = p.libre(c, 1.6) and Geometry2D.is_point_in_polygon(c, interior)
				for e in esquinas:
					if p.en_prado(e) >= 0:
						ok = false
				if not ok:
					continue
				var t = atan2(afuera.x, -afuera.y)  # +Z local (el frente del escaño) hacia afuera del prado
				var bs = Basis(Vector3.UP, t)
				p.instancia(esc, Transform3D(bs, G(c.x, c.y, p.PAV)))
				var caja = BoxShape3D.new()
				caja.size = Vector3(1.85, 0.5, 0.5)
				p.formas.append([caja, Transform3D(bs, G(c.x, c.y, p.PAV + 0.25))])
				var resp = BoxShape3D.new()
				resp.size = Vector3(1.85, 0.45, 0.08)
				p.formas.append([resp, Transform3D(bs, G(c.x, c.y, p.PAV) + bs * Vector3(0, 0.7, -0.33))])
				p.ocupar(c, 1.0)
				n += 1
				if n % 3 == 1:
					var cb = c + d * 1.4
					if p.libre(cb, 0.4) and p.en_prado(cb, 0.25) < 0:
						p.instancia(bas, Transform3D(bs, G(cb.x, cb.y, p.PAV)))
						var bx = BoxShape3D.new()
						bx.size = Vector3(0.45, 1.0, 0.45)
						p.formas.append([bx, Transform3D(bs, G(cb.x, cb.y, p.PAV + 0.5))])
						p.ocupar(cb, 0.4)
						nb += 1
	p.stats["escanos"] = n
	p.stats["basureros"] = nb


# una roca chica de caras planas (octaedro subdividido, deformado y aplastado), centrada en c con radio r
static func roca(m, rng: RandomNumberGenerator, c: Vector3, r: float, col: Color) -> void:
	var vs = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var caras = [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [0, 4, 3], [4, 1, 3], [1, 5, 3], [5, 0, 3]]
	var sub = []
	var medio = {}
	var mid = func(i: int, j: int) -> int:
		var k = "%d_%d" % [min(i, j), max(i, j)]
		if not k in medio:
			vs.append(((vs[i] + vs[j]) / 2).normalized())
			medio[k] = vs.size() - 1
		return medio[k]
	for f in caras:
		var a: int = mid.call(f[0], f[1]); var b: int = mid.call(f[1], f[2]); var d: int = mid.call(f[2], f[0])
		sub.append_array([[f[0], a, d], [a, f[1], b], [d, b, f[2]], [a, b, d]])
	for i in vs.size():
		var v: Vector3 = vs[i] * rng.randf_range(0.75, 1.15)
		vs[i] = c + Vector3(v.x, max(v.y * 0.6, -0.15), v.z) * r
	for f in sub:
		var a: Vector3 = vs[f[0]]; var b: Vector3 = vs[f[1]]; var d: Vector3 = vs[f[2]]
		var nn = ((a + b + d) / 3 - c).normalized()
		m.tri(a, b, d, col * rng.randf_range(0.85, 1.1), nn)
