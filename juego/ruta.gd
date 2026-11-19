# El marcador y el camino hasta él, como en los videojuegos: el mapa grande (plano.gd, M) pone el marcador con un
# clic; aquí se busca el camino por la red de calles (plano_datos.gd camino(): A* desde la calle más cercana al
# personaje hasta la más cercana al marcador, con las puntas rectas), que plano.gd dibuja en los dos mapas, y en el
# mundo van una cinta de flechas sobre el suelo a lo largo de los próximos ADELANTE m del camino y una columna de luz en
# el marcador, que se ve desde toda la comuna.
#
# El camino se rehace cuando el personaje (o el vehículo en que va) se aparta más de DESVIO m de él, y el marcador se
# quita al llegar a menos de LLEGAR m, con un aviso. La cinta sigue el suelo con rayos contra la colisión, que mapa.gd
# arma solo a menos de ~250 m de la cámara: termina donde un rayo no da con nada (más allá, el camino está en los
# mapas). Se rehace cada CINTA_CADA m que se avanza, no en cada cuadro. La columna se apoya en el suelo de la colisión
# o, lejos, en el relieve de lejos.glb (mapa.gd, «lejos»); más allá de LEJOS m se dibuja más cerca y más chica (el
# mismo tamaño en la pantalla), porque la cámara no ve más allá de 3 km, y su ancho no baja de unos píxeles.
#
#   var r := preload("res://ruta.gd").new(); r.jugador = …; r.vehiculo = …; r.mapa = …; add_child(r)
#   r.marcar(Vector2(297, 748), "Catedral")   # punto de grilla (x, y); el nombre va en el aviso de llegada
#   r.quitar()
#   r.restante()                              # m que faltan por el camino
extends Node3D

const Datos := preload("res://plano_datos.gd")
const DESVIO := 25.0  # m fuera del camino: se busca otro
const LLEGAR := 12.0  # m del marcador: llegó
const ADELANTE := 260.0  # m de cinta por delante
const PASO := 2.0  # m entre muestras de la cinta
const ANCHO := 1.8  # m, el ancho de la cinta
const ALTO := 0.22  # m sobre el suelo
const CINTA_CADA := 5.0  # m avanzados para rehacer la cinta
const LEJOS := 2400.0  # m: más allá, la columna se acerca y se achica
const ALTO_FARO := 400.0  # m, el alto de la columna de cerca
const COLOR := Color(0.80, 0.42, 1.0)

signal cambio  # el marcador o el camino cambiaron (plano.gd vuelve a dibujar)
signal llego(nombre: String)

var datos: RefCounted  # plano_datos.gd
var jugador: CharacterBody3D
var vehiculo: CharacterBody3D
var mapa: Node3D
var marcador := Vector2.INF
var nombre := ""
var camino := PackedVector2Array()
var acum := PackedFloat32Array()  # m desde el comienzo del camino hasta cada punto
var recto := false  # sin camino por la red: una línea recta
var prog := 0  # el tramo del camino en que va el personaje
var prog_m := 0.0  # m del camino ya recorridos (su proyección)
var proy := Vector2.INF  # el punto del camino más cercano al personaje
var ms_astar := 0.0
var t_fuera := 0.0
var t_calc := 100.0
var t_seguir := 0.0
var cinta_en := Vector2.INF  # dónde estaba el personaje cuando se hizo la cinta
var cinta_y := 0  # cuántas muestras dieron con el suelo la última vez
var guia := MeshInstance3D.new()
var malla := ArrayMesh.new()
var faro := Node3D.new()
var columna := MeshInstance3D.new()
var faro_y := NAN
var faro_exacto := false  # la altura salió de la colisión, no de lejos.glb
var t_faro := 0.0


func _ready() -> void:
	name = "ruta"
	datos = Datos.uno()
	guia.mesh = malla
	guia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/guia.gdshader")
	m.set_shader_parameter("color", COLOR)
	guia.material_override = m
	add_child(guia)
	armar_faro()
	faro.visible = false
	add_child(faro)


func armar_faro() -> void:
	var col := columna
	var c := CylinderMesh.new()
	c.top_radius = 2.5
	c.bottom_radius = 2.5
	c.height = 500.0
	c.radial_segments = 12
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	col.mesh = c
	col.position.y = 250.0 - 2.0  # desde 2 m bajo el suelo
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/faro.gdshader")
	m.set_shader_parameter("color", COLOR)
	col.material_override = m
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	col.extra_cull_margin = 16384.0  # el sombreador lo ensancha: que no lo recorte la caja de la malla
	faro.add_child(col)
	var aro := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(16, 16)
	aro.mesh = q
	aro.position.y = 0.3
	var ma := ShaderMaterial.new()
	ma.shader = preload("res://shaders/faro.gdshader")
	ma.set_shader_parameter("color", COLOR)
	ma.set_shader_parameter("aro", true)
	aro.material_override = ma
	aro.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	faro.add_child(aro)


func pos() -> Vector2:
	return Vector2(jugador.global_position.x, -jugador.global_position.z)


func activo() -> bool:
	return marcador != Vector2.INF


func marcar(p: Vector2, n := "") -> void:
	marcador = adentro(p)
	nombre = n
	faro_y = NAN
	faro_exacto = false
	t_faro = 0.0
	faro.visible = true
	calcular()


# un punto fuera de la comuna (al otro lado del muro del límite, donde no se llega) pasa a 10 m dentro del límite, en
# el punto del borde más cercano
func adentro(p: Vector2) -> Vector2:
	if datos == null or datos.limite.size() < 3 or Geometry2D.is_point_in_polygon(p, datos.limite):
		return p
	var lim: PackedVector2Array = datos.limite
	var bq := p
	var bd := INF
	for i in lim.size():
		var q := Geometry2D.get_closest_point_to_segment(p, lim[i], lim[(i + 1) % lim.size()])
		if p.distance_to(q) < bd:
			bd = p.distance_to(q)
			bq = q
	return bq + (bq - p).normalized() * 10.0


func quitar() -> void:
	marcador = Vector2.INF
	nombre = ""
	camino = PackedVector2Array()
	acum = PackedFloat32Array()
	malla.clear_surfaces()
	faro.visible = false
	cambio.emit()


func calcular() -> void:
	var p := pos()
	var t0 := Time.get_ticks_usec()
	var c := PackedVector2Array()
	if datos:
		c = datos.camino(p, marcador)
	ms_astar = (Time.get_ticks_usec() - t0) / 1000.0
	recto = c.size() <= 2
	if c.size() < 2:
		c = PackedVector2Array([p, marcador])
	camino = c
	acum.resize(c.size())
	acum[0] = 0.0
	for i in range(1, c.size()):
		acum[i] = acum[i - 1] + c[i - 1].distance_to(c[i])
	prog = 0
	prog_m = 0.0
	proy = c[0]
	t_calc = 0.0
	t_fuera = 0.0
	cinta_en = Vector2.INF
	print("ruta.gd: camino a (%.0f, %.0f)%s: %.2f km%s, %d puntos, %.1f ms" % [marcador.x, marcador.y,
		" «%s»" % nombre if nombre != "" else "", acum[acum.size() - 1] / 1000.0,
		" en línea recta" if recto else "", c.size(), ms_astar])
	cambio.emit()


func restante() -> float:
	if acum.is_empty():
		return 0.0
	return maxf(acum[acum.size() - 1] - prog_m, 0.0)


func _process(dt: float) -> void:
	if not activo() or jugador == null:
		return
	t_calc += dt
	t_seguir += dt
	if t_seguir >= 0.1:
		seguir(t_seguir)
		t_seguir = 0.0
	if activo():  # seguir() lo quita al llegar
		poner_faro(dt)


func seguir(dt: float) -> void:
	var p := pos()
	if p.distance_to(marcador) < LLEGAR:
		var n := nombre
		quitar()
		llego.emit(n)
		print("ruta.gd: llegó%s" % (" a «%s»" % n if n != "" else ""))
		return
	# el tramo más cercano, desde el actual hasta unos cuantos más adelante (no hacia atrás: en una vuelta en U el
	# camino pasa dos veces cerca)
	var bd := INF
	var bi := prog
	var bq := proy
	for i in range(prog, mini(prog + 40, camino.size() - 1)):
		var q := Geometry2D.get_closest_point_to_segment(p, camino[i], camino[i + 1])
		var d := p.distance_to(q)
		if d < bd - 0.01:
			bd = d
			bi = i
			bq = q
	if bd > DESVIO and not recto:
		t_fuera += dt
		if t_fuera > 0.5 and t_calc > 1.5:
			calcular()
		return
	if recto and t_calc > 3.0 and bd > DESVIO:  # quizás ya hay una calle cerca
		calcular()
		return
	t_fuera = 0.0
	if bi != prog or bq != proy:
		prog = bi
		proy = bq
		prog_m = acum[bi] + camino[bi].distance_to(bq)
	if cinta_en == Vector2.INF or cinta_en.distance_to(p) > CINTA_CADA or cinta_y < 8:
		cinta_en = p
		cinta()


# ---------- la cinta del suelo ----------

# las muestras del camino desde la proyección del personaje hacia adelante: [punto, m desde el comienzo del camino]
func muestras() -> Array:
	var out := [[proy, prog_m]]
	var u := prog_m
	var hasta := prog_m + ADELANTE
	var i := prog
	var a := proy
	while i < camino.size() - 1 and u < hasta:
		var b := camino[i + 1]
		var L := a.distance_to(b)
		var n := maxi(1, ceili(L / PASO))
		for k in range(1, n + 1):
			var q := a.lerp(b, float(k) / n)
			out.append([q, u + L * k / n])
		u += L
		a = b
		i += 1
	return out


func cinta() -> void:
	malla.clear_surfaces()
	var ms := muestras()
	if ms.size() < 2:
		return
	var esp := get_world_3d().direct_space_state
	var excluir: Array[RID] = [jugador.get_rid()]
	if vehiculo:
		excluir.append(vehiculo.get_rid())
	var choques: Variant = mapa.get("autos").get("choques") if mapa and mapa.get("autos") else null
	if choques is CollisionObject3D:
		excluir.append(choques.get_rid())
	var y := jugador.global_position.y
	var pts := []  # [Vector3, u]
	for m in ms:
		var q: Vector2 = m[0]
		var r := {}
		for desde in [y + 20.0, 1500.0]:
			var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, desde, -q.y), Vector3(q.x, -500.0, -q.y))
			rq.exclude = excluir
			r = esp.intersect_ray(rq)
			if r:
				break
		if not r:
			break  # sin colisión todavía: la cinta termina aquí
		y = r.position.y
		pts.append([Vector3(q.x, y + ALTO, -q.y), m[1]])
	cinta_y = pts.size()
	if pts.size() < 2:
		return
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var largo: float = pts[pts.size() - 1][1] - pts[0][1]
	var lados := []
	for k in pts.size():
		var a: Vector3 = pts[maxi(k - 1, 0)][0]
		var b: Vector3 = pts[mini(k + 1, pts.size() - 1)][0]
		var d := Vector3(b.x - a.x, 0, b.z - a.z)
		if d.length() < 0.001:
			d = Vector3.FORWARD
		var lado := d.normalized().cross(Vector3.UP) * (ANCHO / 2.0)
		lados.append(lado)
	for k in range(pts.size() - 1):
		var p0: Vector3 = pts[k][0]
		var p1: Vector3 = pts[k + 1][0]
		var l0: Vector3 = lados[k]
		var l1: Vector3 = lados[k + 1]
		var u0: float = pts[k][1]
		var u1: float = pts[k + 1][1]
		var a0 := alfa(u0 - pts[0][1], largo)
		var a1 := alfa(u1 - pts[0][1], largo)
		for t in [[p0 - l0, u0, 0.0, a0], [p0 + l0, u0, 1.0, a0], [p1 + l1, u1, 1.0, a1],
				[p0 - l0, u0, 0.0, a0], [p1 + l1, u1, 1.0, a1], [p1 - l1, u1, 0.0, a1]]:
			v.append(t[0])
			uv.append(Vector2(t[1], t[2]))
			col.append(Color(1, 1, 1, t[3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


# se aparece en los primeros 3 m y se desvanece en los últimos 60
static func alfa(u: float, largo: float) -> float:
	return clampf(u / 3.0, 0.0, 1.0) * clampf((largo - u) / 60.0, 0.0, 1.0)


# ---------- la columna de luz ----------

func poner_faro(dt: float) -> void:
	t_faro -= dt
	if t_faro <= 0.0 and not faro_exacto:
		# del relieve de lejos.glb una vez (leer la malla cuesta); de la colisión, apenas esté
		t_faro = 1.0
		var h := altura_colision(marcador)
		if not is_nan(h):
			faro_y = h
			faro_exacto = true
		elif is_nan(faro_y):
			faro_y = altura_lejos(marcador)
	if is_nan(faro_y) and camino.size() > 0:  # sin tesela (no debería pasar dentro de la comuna): a la altura del personaje
		faro_y = jugador.global_position.y
	var cam := get_viewport().get_camera_3d()
	if cam == null or is_nan(faro_y):
		faro.visible = false
		return
	faro.visible = true
	var w := Vector3(marcador.x, faro_y, -marcador.y)
	var o := cam.global_position
	var d := Vector2(w.x - o.x, w.z - o.z).length()
	if d > LEJOS:
		var k := LEJOS / d
		faro.global_position = o + (w - o) * k
		faro.scale = Vector3.ONE * k
	else:
		faro.global_position = w
		faro.scale = Vector3.ONE
	# de lejos, más alta: siempre sube unos 25° sobre el horizonte (si no, a 7 km se esconde tras los árboles cercanos)
	var alto := maxf(ALTO_FARO, d * 0.47)
	columna.scale.y = alto / 500.0
	columna.position.y = alto / 2.0 - 2.0


# la altura del suelo en un punto de grilla, de la colisión (NAN si su tesela todavía no la tiene)
func altura_colision(p: Vector2) -> float:
	if mapa and mapa.colision.has("%d_%d" % [floori(p.x / mapa.tam), floori(p.y / mapa.tam)]):
		var rq := PhysicsRayQueryParameters3D.create(Vector3(p.x, 1500, -p.y), Vector3(p.x, -500, -p.y))
		rq.exclude = [jugador.get_rid()]
		var r := get_world_3d().direct_space_state.intersect_ray(rq)
		if r:
			return r.position.y
	return NAN


# la del relieve de lejos.glb (el triángulo de su malla «terreno» bajo el punto; NAN si no hay tesela)


func altura_lejos(p: Vector2) -> float:
	if mapa == null:
		return NAN
	var mi: MeshInstance3D = mapa.lejos.get("%d_%d" % [floori(p.x / mapa.tam), floori(p.y / mapa.tam)])
	if mi == null:
		return NAN
	var x := mi.global_transform.affine_inverse() * Vector3(p.x, 0, -p.y)
	var q := Vector2(x.x, x.z)
	for s in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(s)
		if mat == null or String(mat.resource_name) != "terreno":
			continue
		var arr := mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n := ix.size() if not ix.is_empty() else vs.size()
		for t in range(0, n, 3):
			var a := vs[ix[t] if not ix.is_empty() else t]
			var b := vs[ix[t + 1] if not ix.is_empty() else t + 1]
			var c := vs[ix[t + 2] if not ix.is_empty() else t + 2]
			var bc := Geometry2D.point_is_inside_triangle(q, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z))
			if bc:
				var w := baricentro(q, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z))
				var y := a.y * w.x + b.y * w.y + c.y * w.z
				return (mi.global_transform * Vector3(x.x, y, x.z)).y
	return NAN


static func baricentro(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-9:
		return Vector3(1, 0, 0)
	var v := (v2.x * v1.y - v1.x * v2.y) / den
	var w := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - v - w, v, w)
