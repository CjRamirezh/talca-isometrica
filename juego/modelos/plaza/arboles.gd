# Árboles de la plaza hechos en código, uno por especie de las que se ven en las fotos (Commons, 2013–2024; las fuentes
# de cada una, en plaza.gd). Cada especie tiene unas pocas variantes (semillas) que se reparten con giro y escala
# distintos. Un árbol es una ArrayMesh con dos superficies: la corteza (tronco y ramas, corteza.gdshader) y el follaje
# en tarjetas con textura (follaje.gdshader) o en hojas sólidas (cordyline, agapantos). El origen es el pie del tronco.
#
# Medidas de las fotos y de lo típico de cada especie en ciudad; ninguna se midió en el lugar:
#   palmera  Phoenix canariensis: estípite de 0,9–1,1 m de diámetro con la base de las hojas en rombos, 9–15 m,
#            40–50 frondas arqueadas de 4,5–5,5 m, racimos de dátiles naranjos (foto de 2024 «…en 2024 01»)
#   cedro    Cedrus deodara: 18–24 m, copa cónica ancha, ramas horizontales con las puntas caídas, verde azulado,
#            tronco despejado hasta ~5 m (foto de 2024 «…en 2024 02», junto al memorial de Spano)
#   araucaria  Araucaria heterophylla o columnaris: 20–26 m, pisos de cinco ramas horizontales (fotos de 2024 «03», «04»)
#   frondoso árbol de hoja ancha genérico (fresno, plátano, tilo: las fotos no permiten decir cuál), 12–17 m
#   podado   la copa recortada en cúpula sobre troncos retorcidos (pitosporo o laurel, foto de 2024 «01»), ~6 m
#   cordyline  Cordyline australis: troncos delgados que se ramifican en penachos de hojas angostas (foto de 2014
#            «Talca, plaza (14836795037)»), 4–6 m
#   arbusto  bolas recortadas de ~1,2 m junto a las soleras (foto de 2024 «01»)
#   agapanto matas de hojas en cinta en los bordes de los prados (fotos de 2014 y 2024)
extends RefCounted

const Malla := preload("res://malla.gd")
const Mat := preload("res://materiales.gd")
const Tx = preload("res://modelos/plaza/texturas.gd")

const ESPECIES := {
	"palmera": {"corteza": Color(0.50, 0.42, 0.32), "tipo": 1, "hojas": Color(0.40, 0.52, 0.20)},
	"cedro": {"corteza": Color(0.27, 0.25, 0.23), "tipo": 0, "hojas": Color(0.30, 0.42, 0.36)},
	"araucaria": {"corteza": Color(0.3, 0.25, 0.21), "tipo": 2, "hojas": Color(0.20, 0.34, 0.18)},
	"frondoso": {"corteza": Color(0.27, 0.245, 0.22), "tipo": 0, "hojas": Color(0.33, 0.50, 0.20)},
	"podado": {"corteza": Color(0.38, 0.35, 0.31), "tipo": 0, "hojas": Color(0.26, 0.42, 0.17)},
	"cordyline": {"corteza": Color(0.50, 0.45, 0.38), "tipo": 2, "hojas": Color(0.38, 0.52, 0.22)},
	"arbusto": {"corteza": Color(0.4, 0.35, 0.3), "tipo": 0, "hojas": Color(0.24, 0.40, 0.16)},
	"agapanto": {"corteza": Color(0.4, 0.35, 0.3), "tipo": 0, "hojas": Color(0.22, 0.40, 0.16)},
}
const VARIANTES := 3

var mat_corteza = {}
var mat_follaje = {}
var mat_solido: StandardMaterial3D
var mat_datiles: ShaderMaterial
var cache = {}
var radios = {}  # especie/variante -> radio del tronco a 1 m (colisión)
var sombras = {}  # especie/variante -> la malla de la sombra
const SOMBRA_K := {"frondoso": 2, "podado": 2, "arbusto": 2, "cedro": 2, "araucaria": 3}  # una tarjeta de cada k


func _init() -> void:
	var tex = {
		"palmera": Tx.fronda(11, Color(0.42, 0.55, 0.22)),
		"cedro": Tx.agujas(12, Color(0.32, 0.44, 0.38)),
		"araucaria": Tx.araucaria(13, Color(0.22, 0.36, 0.19)),
		"frondoso": Tx.hojas(14, Color(0.36, 0.54, 0.22)),
		"podado": Tx.hojas(15, Color(0.28, 0.45, 0.18), 520, 6.0, 3.2),
		"arbusto": Tx.hojas(16, Color(0.26, 0.43, 0.17), 480, 6.0, 3.0),
	}
	for e in ESPECIES:
		mat_corteza[e] = Mat.plaza("corteza", {"tipo": ESPECIES[e]["tipo"], "vueltas": 5.0 if e == "palmera" else 6.0})
		if e in tex:
			mat_follaje[e] = Mat.plaza("follaje", {"tex": tex[e], "viento": 1.4 if e == "palmera" else 1.0,
				"brillo": 0.45 if e in ["podado", "arbusto", "palmera"] else 0.3})
	mat_solido = StandardMaterial3D.new()
	mat_solido.vertex_color_use_as_albedo = true
	mat_solido.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_solido.roughness = 0.7
	mat_solido.backlight_enabled = true
	mat_solido.backlight = Color(0.25, 0.35, 0.12)
	mat_datiles = Mat.plaza("follaje", {"tex": Tx.flores(17, [Color(0.9, 0.5, 0.12), Color(0.95, 0.62, 0.15), Color(0.8, 0.42, 0.1)], 70)})


# la malla de una variante (se arma una vez)
func malla(especie: String, variante: int) -> ArrayMesh:
	var clave = "%s/%d" % [especie, variante % VARIANTES]
	if clave in cache:
		return cache[clave]
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(clave) & 0x7fffffff
	var tr = Malla.new()
	var fo = Malla.new()
	var extra = Malla.new()  # sólidos (hojas en cinta) o dátiles
	var r = 0.3
	match especie:
		"palmera": r = palmera(rng, tr, fo, extra)
		"cedro": r = cedro(rng, tr, fo)
		"araucaria": r = araucaria(rng, tr, fo)
		"frondoso": r = frondoso(rng, tr, fo)
		"podado": r = podado(rng, tr, fo)
		"cordyline": r = cordyline(rng, tr, extra)
		"arbusto": r = arbusto(rng, fo)
		"agapanto": r = agapanto(rng, extra)
	var m = ArrayMesh.new()
	tr.malla(mat_corteza[especie], m)
	if especie in mat_follaje:
		fo.malla(mat_follaje[especie], m)
	extra.malla(mat_datiles if especie == "palmera" else mat_solido, m)
	cache[clave] = m
	radios[clave] = r
	# la sombra: la corteza y una tarjeta de cada racimo (las tres cruzadas de un racimo dan casi la misma sombra)
	var s = ArrayMesh.new()
	tr.malla(mat_corteza[especie], s)
	if especie in mat_follaje:
		fo.cada(SOMBRA_K.get(especie, 1)).malla(mat_follaje[especie], s)
	sombras[clave] = s
	return m


# la malla que proyecta la sombra de una variante (instancia solo de sombra)
func sombra(especie: String, variante: int) -> ArrayMesh:
	malla(especie, variante)
	return sombras["%s/%d" % [especie, variante % VARIANTES]]


func radio(especie: String, variante: int) -> float:
	malla(especie, variante)
	return radios["%s/%d" % [especie, variante % VARIANTES]]


# ---- piezas ----

# una tarjeta de follaje: un cuadrado centrado en p con ejes u, v (mitades), normal de iluminación nn
static func tarjeta(m, p: Vector3, u: Vector3, v: Vector3, nn: Vector3, col: Color) -> void:
	m.quad(p - u - v, p + u - v, p + u + v, p - u + v, col, nn, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])


# un racimo: tres tarjetas cruzadas de lado s en p, iluminadas desde el centro de la copa c
static func racimo(m, rng: RandomNumberGenerator, p: Vector3, s: float, c: Vector3, col: Color, tarjetas := 3) -> void:
	var nn = (p - c).normalized()
	nn = (nn + Vector3.UP * 0.35).normalized()
	var b = Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf() * TAU)
	var ejes = [[b.x, b.y], [b.y, b.z], [b.z, b.x]]
	for i in tarjetas:
		var tinte = col * rng.randf_range(0.85, 1.15)
		tinte.a = 1.0
		tarjeta(m, p, ejes[i][0] * s * 0.5, ejes[i][1] * s * 0.5, nn, tinte)


# un tronco o rama curvo: una serie de tubos por los puntos pts con radios rs (UV en m a lo largo)
static func rama(m, pts: Array, rs: Array, k: int, col: Color) -> void:
	var largo = 0.0
	for i in pts.size() - 1:
		var l: float = (pts[i + 1] - pts[i]).length()
		var ca: Color = col * (0.92 + 0.08 * float(i) / pts.size())
		m.tubo(pts[i], pts[i + 1], rs[i], rs[i + 1], k, ca, ca, largo, largo + l)
		largo += l


func palmera(rng: RandomNumberGenerator, tr, fo, datiles) -> float:
	var E: Dictionary = ESPECIES["palmera"]
	var H = rng.randf_range(9.0, 13.0)
	var r0 = rng.randf_range(0.45, 0.55)
	var incl = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.2, 0.7)
	var pts = []; var rs = []
	var n = 12
	for i in n + 1:
		var t = float(i) / n
		pts.append(Vector3.UP * (H * t - 0.3) + incl * t * t)
		var r = r0 * (1.0 + 0.45 * pow(max(0.0, 1.0 - t * 6.0), 2.0)) * (1.0 - 0.08 * t)  # el pie se ensancha
		rs.append(r)
	rama(tr, pts, rs, 14, E["corteza"])
	var top: Vector3 = pts[n]
	# la «piña»: las bases de las frondas vivas, un bulbo un poco más ancho que el estípite
	tr.torno(top - Vector3.UP * 0.2, [Vector2(r0 * 0.95, 0), Vector2(r0 * 1.35, 0.5), Vector2(r0 * 1.25, 1.0), Vector2(0.3, 1.5), Vector2(0.0, 1.7)], 14,
		E["corteza"] * 1.1)
	var c = top + Vector3.UP * 1.2
	var nf = rng.randi_range(40, 52)
	var col: Color = E["hojas"]
	for i in nf:
		var az = i * 2.39996 + rng.randf_range(-0.15, 0.15)  # ángulo áureo
		var f = float(i) / nf  # 0: las de arriba (nuevas), 1: las de abajo (viejas)
		var el = lerp(1.25, -0.25, f) + rng.randf_range(-0.15, 0.15)
		var L = rng.randf_range(4.3, 5.5)
		var horiz = Vector3(cos(az), 0, sin(az))
		var d0 = (horiz * cos(el) + Vector3.UP * sin(el)).normalized()
		var p0 = c + horiz * 0.3 + Vector3.UP * lerp(0.3, -0.6, f)
		var caida = L * lerp(0.25, 0.55, f)
		var lado = horiz.cross(Vector3.UP).normalized()
		var pasos = 6
		var tinte = col * lerp(1.05, 0.85, f)
		if f > 0.85 and rng.randf() < 0.5:
			tinte = Color(0.55, 0.5, 0.28)  # alguna fronda vieja amarillenta
		tinte.a = 1
		var prev_p = p0; var prev_l = Vector3.ZERO; var prev_r = Vector3.ZERO
		for j in pasos + 1:
			var t = float(j) / pasos
			var p = p0 + d0 * L * t + Vector3.DOWN * caida * t * t
			var tang = (d0 * L + Vector3.DOWN * 2.0 * caida * t).normalized()
			var ancho = 0.65 * sin(PI * (0.08 + 0.92 * t)) * (1.0 - 0.3 * t) + 0.05
			var up = tang.cross(lado).normalized()
			if up.y < 0:
				up = -up
			# los folíolos en V: cada mitad sube 30°
			var izq = (lado * cos(0.5) + up * sin(0.5)) * ancho
			var der = (-lado * cos(0.5) + up * sin(0.5)) * ancho
			if j > 0:
				var nn = (up + (p - c).normalized() * 0.5).normalized()
				fo.quad(prev_p + prev_l, p + izq, p, prev_p, tinte, nn,
					[Vector2(t - 1.0 / pasos, 0), Vector2(t, 0), Vector2(t, 0.5), Vector2(t - 1.0 / pasos, 0.5)])
				fo.quad(prev_p, p, p + der, prev_p + prev_r, tinte, nn,
					[Vector2(t - 1.0 / pasos, 0.5), Vector2(t, 0.5), Vector2(t, 1), Vector2(t - 1.0 / pasos, 1)])
			prev_p = p; prev_l = izq; prev_r = der
	# racimos de dátiles naranjos colgando bajo la copa
	for i in rng.randi_range(3, 6):
		var az = rng.randf() * TAU
		var p = top + Vector3(cos(az), 0, sin(az)) * rng.randf_range(0.7, 1.1) + Vector3.UP * rng.randf_range(-0.1, 0.4)
		var u = Vector3(-sin(az), 0, cos(az)) * 0.35
		tarjeta(datiles, p - Vector3.UP * 0.4, u, Vector3.UP * 0.5, Vector3(cos(az), 0.3, sin(az)).normalized(), Color(1, 1, 1))
		tarjeta(datiles, p - Vector3.UP * 0.4, Vector3(cos(az), 0, sin(az)) * 0.35, Vector3.UP * 0.5, Vector3(cos(az), 0.3, sin(az)).normalized(), Color(1, 1, 1))
	return r0


func cedro(rng: RandomNumberGenerator, tr, fo) -> float:
	var E: Dictionary = ESPECIES["cedro"]
	var H = rng.randf_range(18.0, 23.0)
	var r0 = rng.randf_range(0.5, 0.65)
	var R = rng.randf_range(6.0, 7.5)
	var h0 = rng.randf_range(4.5, 6.0)
	var pts = []; var rs = []
	for i in 13:
		var t = i / 12.0
		pts.append(Vector3(sin(t * 3.0) * 0.15, H * 0.97 * t - 0.3, cos(t * 2.0) * 0.1 - 0.1))
		rs.append(r0 * (1.0 - 0.92 * t) * (1.0 + 0.4 * pow(max(0.0, 1.0 - t * 8.0), 2.0)))
	rama(tr, pts, rs, 12, E["corteza"])
	var col: Color = E["hojas"]
	var c = Vector3(0, (h0 + H) * 0.5, 0)
	var h = h0
	var az = rng.randf() * TAU
	while h < H - 0.8:
		var f = (h - h0) / (H - h0)
		var L = R * pow(1.0 - f, 0.85) * rng.randf_range(0.8, 1.1) + 0.6
		az += 2.39996 + rng.randf_range(-0.3, 0.3)
		var d = Vector3(cos(az), 0, sin(az))
		var p0 = Vector3(0, h, 0)
		var sube = rng.randf_range(0.05, 0.25) * (1.0 - f)
		var p1 = p0 + d * L * 0.55 + Vector3.UP * L * sube
		var p2 = p0 + d * L + Vector3.UP * (L * sube - L * 0.22)  # la punta cae
		var rr = 0.03 + 0.12 * L / R
		rama(tr, [p0, p1, p2], [rr, rr * 0.6, 0.02], 5, E["corteza"] * 0.9)
		# almohadillas de agujas a lo largo de la rama: tarjetas casi horizontales que se inclinan en la punta
		var lado = d.cross(Vector3.UP)
		var k = int(L / 0.7) + 1
		for j in k:
			var t = 0.25 + 0.75 * float(j) / max(1, k - 1)
			var p: Vector3 = (p0.lerp(p1, t / 0.55) if t < 0.55 else p1.lerp(p2, (t - 0.55) / 0.45))
			var ancho = lerp(2.6, 1.5, t) * rng.randf_range(0.85, 1.15)
			var caida = lerp(0.15, 0.7, t)
			var u = (d + Vector3.DOWN * caida).normalized() * ancho * 0.6
			var v = lado * ancho * 0.55
			var nn = ((p - c).normalized() + Vector3.UP * 0.6).normalized()
			var tinte = col * rng.randf_range(0.85, 1.1)
			tinte.a = 1
			tarjeta(fo, p + Vector3.DOWN * 0.15, u, v, nn, tinte)
			tarjeta(fo, p + Vector3.DOWN * 0.45 + lado * rng.randf_range(-0.3, 0.3), u.rotated(Vector3.UP, 0.5), v.rotated(Vector3.UP, 0.5), nn, tinte * 0.9)
			# una cortina que cuelga de la almohadilla
			if rng.randf() < 0.8:
				tarjeta(fo, p + Vector3.DOWN * 0.7, v * 1.1, Vector3.DOWN * 0.75, nn, tinte * 0.95)
		h += rng.randf_range(0.3, 0.5)
	# la guía de arriba, que se inclina
	var cima = Vector3(0.1, H, 0)
	for i in 4:
		var t = rng.randf() * TAU
		tarjeta(fo, cima + Vector3(cos(t) * 0.3, -0.4 - i * 0.4, sin(t) * 0.3), Vector3(cos(t), 0, sin(t)) * 0.5, Vector3.UP * 0.6, Vector3.UP, col)
	return r0


func araucaria(rng: RandomNumberGenerator, tr, fo) -> float:
	var E: Dictionary = ESPECIES["araucaria"]
	var H = rng.randf_range(19.0, 25.0)
	var r0 = rng.randf_range(0.35, 0.45)
	var pts = []; var rs = []
	for i in 9:
		var t = i / 8.0
		pts.append(Vector3(0, H * t - 0.3, 0))
		rs.append(r0 * (1.0 - 0.9 * t) * (1.0 + 0.3 * pow(max(0.0, 1.0 - t * 8.0), 2.0)))
	rama(tr, pts, rs, 10, E["corteza"])
	var col: Color = E["hojas"]
	var h0 = H * rng.randf_range(0.28, 0.38)
	var Lmax = rng.randf_range(3.5, 4.8)
	var h = h0
	var giro = rng.randf() * TAU
	while h < H - 0.4:
		var f = (h - h0) / (H - h0)
		var L = Lmax * pow(1.0 - f, 0.75) + 0.35
		giro += 0.63
		for b in 5:
			if rng.randf() < 0.08 and f < 0.5:
				continue  # alguna rama perdida en los pisos de abajo
			var az = giro + b * TAU / 5
			var d = Vector3(cos(az), 0, sin(az))
			var p0 = Vector3(0, h, 0)
			var p1 = p0 + d * L * 0.6 + Vector3.DOWN * L * 0.05
			var p2 = p0 + d * L + Vector3.UP * L * 0.12  # la punta sube
			rama(tr, [p0, p1, p2], [0.06 + 0.04 * (1 - f), 0.04, 0.02], 4, E["corteza"])
			# el cordón de hojas: dos tarjetas cruzadas a lo largo de cada tramo
			var lado = d.cross(Vector3.UP).normalized()
			for seg in [[p0.lerp(p1, 0.15), p1], [p1, p2]]:
				var a: Vector3 = seg[0]; var e: Vector3 = seg[1]
				var mitad = (e - a) * 0.5
				var m = a + mitad
				var nn = (d + Vector3.UP * 0.5).normalized()
				var tinte = col * rng.randf_range(0.85, 1.15)
				tinte.a = 1
				var dg = (lado + Vector3.UP).normalized() * 0.6
				fo.quad(m - mitad - dg, m + mitad - dg, m + mitad + dg, m - mitad + dg, tinte * 0.9, nn,
					[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
				fo.quad(m - mitad - lado * 0.7, m + mitad - lado * 0.7, m + mitad + lado * 0.7, m - mitad + lado * 0.7, tinte, nn,
					[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
				fo.quad(m - mitad + Vector3.DOWN * 0.65, m + mitad + Vector3.DOWN * 0.65, m + mitad + Vector3.UP * 0.5, m - mitad + Vector3.UP * 0.5, tinte, nn,
					[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		h += rng.randf_range(0.9, 1.2)
	return r0


func frondoso(rng: RandomNumberGenerator, tr, fo) -> float:
	var E: Dictionary = ESPECIES["frondoso"]
	var H = rng.randf_range(12.0, 16.5)
	var R = rng.randf_range(5.0, 7.0)
	var r0 = rng.randf_range(0.32, 0.48)
	var hf = rng.randf_range(2.6, 3.8)
	var lean = Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
	var tope = Vector3.UP * hf + lean
	rama(tr, [Vector3.DOWN * 0.3, Vector3.UP * 0.4, Vector3.UP * hf * 0.6 + lean * 0.5, tope], [r0 * 1.45, r0 * 1.05, r0 * 0.95, r0 * 0.85], 10, E["corteza"])
	var c = Vector3(lean.x, hf + (H - hf) * 0.45, lean.z)
	var ry = (H - hf) * 0.55
	var col: Color = E["hojas"]
	var puntas = []
	var nl = rng.randi_range(3, 5)
	for i in nl:
		var az = TAU * i / nl + rng.randf_range(-0.3, 0.3)
		var el = rng.randf_range(0.6, 1.05)
		var d = Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
		ramas(rng, tr, tope, d, R * 0.55, r0 * 0.55, 3, puntas, c, R, ry)
	for p in puntas:
		racimo(fo, rng, p, rng.randf_range(2.3, 3.1), c, col, 2)
	# relleno de la copa: racimos sobre una cáscara del elipsoide, para que se lea llena
	var n = int(R * R * 1.7)
	for i in n:
		var d = Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.75, 1), rng.randf_range(-1, 1))
		if d.length() > 1 or d.length() < 0.2:
			continue
		d = d.normalized() * rng.randf_range(0.45, 1.0)
		var p = c + Vector3(d.x * R, d.y * ry, d.z * R)
		racimo(fo, rng, p, rng.randf_range(2.3, 3.1), c, col, 2)
	return r0


func ramas(rng: RandomNumberGenerator, tr, p: Vector3, d: Vector3, L: float, r: float, nivel: int, puntas: Array, c: Vector3, R: float, ry: float) -> void:
	var e = p + d * L
	# que no salga de la copa
	var q = e - c
	var k = Vector3(q.x / R, q.y / ry, q.z / R).length()
	if k > 1.0:
		e = c + q / k
	var mid = p.lerp(e, 0.5) + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, 0.3), rng.randf_range(-0.3, 0.3)) * L * 0.3
	rama(tr, [p, mid, e], [r, r * 0.8, r * 0.62], 6 if nivel >= 2 else 4, ESPECIES["frondoso"]["corteza"])
	if nivel == 0:
		puntas.append(e)
		return
	if nivel == 1:
		puntas.append(mid)
	var hijos = rng.randi_range(2, 3)
	if nivel <= 2:
		puntas.append(p.lerp(e, 0.7))
	for i in hijos:
		var eje = d.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))).normalized()
		if eje == Vector3.ZERO:
			eje = Vector3.RIGHT
		var d2 = d.rotated(eje, rng.randf_range(0.35, 0.8))
		d2 = (d2 + (e - c).normalized() * 0.3 + Vector3.UP * 0.15).normalized()
		ramas(rng, tr, e, d2, L * rng.randf_range(0.55, 0.75), r * 0.58, nivel - 1, puntas, c, R, ry)


func podado(rng: RandomNumberGenerator, tr, fo) -> float:
	var E: Dictionary = ESPECIES["podado"]
	var R = rng.randf_range(2.8, 3.6)
	var ry = rng.randf_range(2.0, 2.6)
	var c = Vector3(0, ry + rng.randf_range(1.6, 2.2), 0)
	var nt = rng.randi_range(2, 4)
	for i in nt:
		var az = TAU * i / nt + rng.randf_range(-0.4, 0.4)
		var d = Vector3(cos(az), 0, sin(az))
		var r = rng.randf_range(0.14, 0.24)
		rama(tr, [Vector3.DOWN * 0.2 + d * 0.15, Vector3.UP * 0.8 + d * 0.35, Vector3.UP * 1.6 + d * 0.9, c + d * R * 0.4 + Vector3.DOWN * 0.5],
			[r * 1.3, r, r * 0.85, r * 0.5], 7, E["corteza"])
	var col: Color = E["hojas"]
	var n = int(R * R * 7)
	for i in n:
		var d = Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1))
		if d.length() < 0.1:
			continue
		d = d.normalized() * rng.randf_range(0.82, 1.0)
		racimo(fo, rng, c + Vector3(d.x * R, d.y * ry, d.z * R), rng.randf_range(1.0, 1.4), c, col, 2)
	return 0.45


func cordyline(rng: RandomNumberGenerator, tr, hojas) -> float:
	var E: Dictionary = ESPECIES["cordyline"]
	var H = rng.randf_range(3.5, 5.5)
	var hb = H * rng.randf_range(0.45, 0.6)
	rama(tr, [Vector3.DOWN * 0.2, Vector3.UP * hb], [0.16, 0.12], 7, E["corteza"])
	var nb = rng.randi_range(2, 3)
	for i in nb:
		var az = TAU * i / nb + rng.randf_range(-0.4, 0.4)
		var d = Vector3(cos(az) * 0.35, 1, sin(az) * 0.35).normalized()
		var tope = Vector3.UP * hb + d * (H - hb) * rng.randf_range(0.8, 1.1)
		var medio = Vector3.UP * hb + (tope - Vector3.UP * hb) * 0.5 + Vector3(d.x, 0, d.z) * 0.15
		rama(tr, [Vector3.UP * hb, medio, tope], [0.1, 0.08, 0.06], 6, E["corteza"])
		penacho(rng, hojas, tope, 0.9, 0.045, E["hojas"], 34)
	return 0.16


# un penacho de hojas en cinta: n hojas que salen de p en todas direcciones, arqueadas
static func penacho(rng: RandomNumberGenerator, m, p: Vector3, L: float, ancho: float, col: Color, n: int, solo_arriba := false) -> void:
	for i in n:
		var az = rng.randf() * TAU
		var el = rng.randf_range(-0.6, 1.4) if not solo_arriba else rng.randf_range(0.5, 1.4)
		var d = Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
		var lado = d.cross(Vector3.UP).normalized() * ancho
		if lado == Vector3.ZERO:
			lado = Vector3.RIGHT * ancho
		var l = L * rng.randf_range(0.75, 1.15)
		var a = p
		var tinte = col * rng.randf_range(0.8, 1.15)
		tinte.a = 1
		var prev_w = lado * 0.4
		for j in range(1, 4):
			var t = j / 3.0
			var b = p + d * l * t + Vector3.DOWN * l * 0.25 * t * t
			var w = lado * (1.0 - t * 0.85)
			var nn = (d + Vector3.UP).normalized()
			m.quad(a - prev_w, b - w, b + w, a + prev_w, tinte, nn)
			a = b; prev_w = w


func arbusto(rng: RandomNumberGenerator, fo) -> float:
	var R = rng.randf_range(0.6, 0.8)
	var ry = R * rng.randf_range(0.75, 0.9)
	var c = Vector3(0, ry * 0.85, 0)
	var col: Color = ESPECIES["arbusto"]["hojas"]
	for i in 30:
		var d = Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 1), rng.randf_range(-1, 1))
		if d.length() < 0.1:
			continue
		d = d.normalized() * rng.randf_range(0.75, 1.0)
		racimo(fo, rng, c + Vector3(d.x * R, d.y * ry, d.z * R), rng.randf_range(0.5, 0.7), c, col, 2)
	return 0.0


func agapanto(rng: RandomNumberGenerator, hojas) -> float:
	for i in rng.randi_range(3, 5):
		var p = Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
		penacho(rng, hojas, p, 0.6, 0.035, ESPECIES["agapanto"]["hojas"], 14, true)
	return 0.0
