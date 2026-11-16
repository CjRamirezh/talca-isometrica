# Un paseo por la Plaza de Armas: la maqueta exportada por tools/export.py (juego/plaza.glb, una caja de 400 m
# alrededor de la plaza: la plaza, las calles que la rodean y las manzanas del frente) con un personaje en tercera
# persona que camina sobre ella.
#
#   make juego                                                     # exporta juego/plaza.glb e importa en Godot (~30 s)
#   /Applications/Godot.app/Contents/MacOS/Godot --path juego       # jugar (o abrir juego/project.godot en el editor)
#   /Applications/Godot.app/Contents/MacOS/Godot --path juego -- --png shots/juego.png [--desde x,y] [--girar 90] [--mirar -10] [--camara 5] [--caminar 3]
#
# WASD o flechas: caminar; Mayús: correr; Espacio: saltar; mouse: mirar; rueda: acercar la cámara (hasta la primera
# persona); Esc: soltar el mouse (un clic lo vuelve a tomar). --png guarda un cuadro y sale; --desde x,y pone al
# personaje en ese punto de grilla, --girar G gira la vista G grados a
# la izquierda, --mirar P la inclina P grados, --camara L pone la cámara a L m (0: primera persona) y --caminar N camina N segundos hacia adelante antes (para revisar la colisión sin teclado).
#
# Coordenadas como en la página: X = x de grilla (oriente), Y = altura, Z = -y (norte), origen en la plaza.
# Colisión: una malla exacta (trimesh) por capa del glb, salvo los árboles (se atraviesan). El importador de Godot no
# usa los colores por vértice del glb (ver tools/godot/ver.gd): se encienden aquí.
#
# Lo que se ve y lo que reemplaza al glb va en archivos propios, para que este no crezca:
#   cine.gd          --cine: un plano de cine a la tarde, con la cámara en un recorrido fijo y peatones (ver cine.gd)
#   vp.gd            --vp: producción virtual con una tele de fondo, la cámara movida por un teléfono (ver vp.gd)
#   ambiente.gd      cielo, luz, sombras, niebla y posproceso (un Node3D que se agrega a la escena)
#   jugador.gd       el personaje y su cámara
#   modelos/*.gd     modelos propios del juego, más detallados que los de la página. Cada uno es un Node3D que construye
#                    lo suyo (geometría y colisión) en _ready() y puede declarar
#                      func recortes() -> Array   # [{"poligono": PackedVector2Array([...]), "capas": ["hitos", ...]}]
#                    polígonos en metros de grilla (x al oriente, y al norte; X = x, Z = -y) dentro de los cuales se
#                    quita del glb lo de esas capas ("capas" vacío o ausente: todas), antes de crear la colisión: el
#                    suelo se corta en el borde del polígono y un objeto (un árbol, un auto) se va o queda entero
#                    (recortar()). Capas del glb: terreno, suelo, usos, patios, ciudad, autos, arboles,
#                    edificios, hitos, veredas (plaza.json, "capas").
extends Node3D

const SIN_COLISION := ["arboles", "alamos", "agua", "autos-ruta5", "trenes"]
const INICIO := Vector2(0, -45)  # x, y de grilla: el borde sur de la plaza, mirando al norte

var jugador: CharacterBody3D


func abs_path(p: String) -> String:
	return p if p.is_absolute_path() else OS.get_environment("PWD").path_join(p)


func _ready() -> void:
	acciones()
	if not ResourceLoader.exists("res://plaza.glb"):
		push_error("falta juego/plaza.glb: corra `make juego` en la raíz del repositorio")
		get_tree().quit(1)
		return
	var plaza: Node3D = load("res://plaza.glb").instantiate()
	add_child(plaza)
	var mods := modelos()
	var recs := []
	for m in mods:
		if m.has_method("recortes"):
			recs.append_array(m.recortes())

	var caja := AABB()
	var primera := true
	for mi in plaza.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m:
				m.vertex_color_use_as_albedo = true
		recortar(mi, recs)
		var b: AABB = mi.global_transform * mi.get_aabb()
		caja = b if primera else caja.merge(b)
		primera = false
		if not (mi.name in SIN_COLISION or mi.get_parent().name in SIN_COLISION):
			mi.create_trimesh_collision()
	muros(caja)
	add_child(preload("res://ambiente.gd").new())
	for m in mods:
		add_child(m)

	var args := OS.get_cmdline_user_args()
	if "--cine" in args:  # un plano de cine: la cámara, la hora y los peatones, en función del tiempo (cine.gd)
		add_child(preload("res://cine.gd").new())
		return
	if "--vp" in args:  # la tele de fondo: la cámara la mueve un teléfono (vp.gd), sin personaje
		add_child(preload("res://vp.gd").new())
		await png(args)
		return
	jugador = preload("res://jugador.gd").new()
	jugador.mouse = not ("--png" in args or "--caminar" in args)
	add_child(jugador)
	await get_tree().physics_frame
	await get_tree().physics_frame
	jugador.inicio = suelo(INICIO.x, -INICIO.y) + Vector3.UP * 0.1
	jugador.global_position = jugador.inicio
	ayuda()

	if "--desde" in args:
		var d: PackedStringArray = args[args.find("--desde") + 1].split(",")
		jugador.inicio = suelo(float(d[0]), -float(d[1])) + Vector3.UP * 0.1
		jugador.global_position = jugador.inicio
	if "--girar" in args:
		jugador.yaw = deg_to_rad(float(args[args.find("--girar") + 1]))
	if "--mirar" in args:  # grados sobre (+) o bajo (−) la horizontal
		jugador.pitch = deg_to_rad(float(args[args.find("--mirar") + 1]))
	if "--camara" in args:  # largo del brazo de la cámara en m (0: primera persona)
		jugador.largo = float(args[args.find("--camara") + 1])
		jugador.brazo.spring_length = jugador.largo
	if "--caminar" in args:
		Input.action_press("adelante")
		await get_tree().create_timer(float(args[args.find("--caminar") + 1])).timeout
		Input.action_release("adelante")
		var choque := jugador.get_last_slide_collision()
		var contra := ""
		if choque and jugador.is_on_wall():
			contra = ", contra «%s»" % choque.get_collider().get_parent().name
		print("main.gd: jugador en x %.1f, y %.1f, altura %.2f%s" % [jugador.global_position.x, -jugador.global_position.z, jugador.global_position.y, contra])
	await png(args)


# --png x.png: guarda un cuadro y sale
func png(args: PackedStringArray) -> void:
	if not "--png" in args:
		return
	for i in 10:
		await RenderingServer.frame_post_draw
	var out := abs_path(args[args.find("--png") + 1])
	get_viewport().get_texture().get_image().save_png(out)
	print("main.gd -> ", out)
	get_tree().quit()


# los modelos de modelos/*.gd, en orden de nombre
func modelos() -> Array:
	var out := []
	var fs := Array(ResourceLoader.list_directory("res://modelos/"))
	fs.sort()
	for f in fs:
		if f.ends_with(".gd"):
			out.append(load("res://modelos/" + f).new())
	return out


# quita de una malla del glb lo que cae en un recorte que toca su capa. Los triángulos se juntan en piezas por sus
# vértices (soldados al milímetro: el glb repite los de cada cara). Una pieza chica y con alto (un árbol, un auto,
# un farol) se quita o queda entera, por el centro de su planta: no se corta un objeto por la mitad. En lo demás
# (el suelo y las losas, planos a cualquier tamaño; las piezas grandes soldadas), cada triángulo inclinado o plano
# se corta en el borde del polígono (en planta) y lo que queda se vuelve a triangular, con sus atributos (posición,
# normal, color, uv) interpolados en el triángulo original: sigue en su plano; uno casi vertical (un muro) es una
# línea en planta y se quita si su centro cae dentro. Antes todo se quitaba por el centro de cada triángulo: un
# triángulo grande que cruzaba el borde quedaba o se iba entero (el suelo de una manzana de la página asomaba por las
# fachadas de 1 Sur), y los objetos quedaban a medias
const VERTICAL := 0.2  # |normal.y| bajo esto: un muro
const SUBDIV := 6  # cuántas veces partir en cuatro un triángulo con un recorte entero adentro (un hueco)
const OBJETO := 25.0  # m: una pieza de este lado o menos en planta, y de más de ALTO_OBJETO de alto, es un objeto
const ALTO_OBJETO := 0.3


func recortar(mi: MeshInstance3D, recs: Array) -> void:
	var capa := String(mi.name)
	var pols := []
	for r in recs:
		var capas: Array = r.get("capas", [])
		if capas.is_empty() or capa in capas or String(mi.get_parent().name) in capas:
			var pol: PackedVector2Array = r["poligono"]
			pols.append([pol, _caja(pol)])
	if pols.is_empty():
		return
	var am := mi.mesh as ArrayMesh
	var nuevo := ArrayMesh.new()
	var xf := mi.global_transform
	var n := {"quitados": 0, "cortados": 0}
	for s in am.get_surface_count():
		var a := am.surface_get_arrays(s)
		for k in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			assert(a[k] == null, "recortar: atributo %d sin interpolar" % k)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var w := PackedVector3Array()  # en el mundo
		w.resize(v.size())
		for i in v.size():
			w[i] = xf * v[i]
		var pieza := _piezas(w, idx)  # por vértice: el índice de su pieza
		var cajas := {}  # pieza -> AABB en el mundo
		for i in idx:
			var k: int = pieza[i]
			cajas[k] = cajas[k].expand(w[i]) if cajas.has(k) else AABB(w[i], Vector3.ZERO)
		var objeto := {}  # pieza (objeto) -> se quita
		for k in cajas:
			var bb: AABB = cajas[k]
			if maxf(bb.size.x, bb.size.z) <= OBJETO and bb.size.y > ALTO_OBJETO:
				var c := bb.get_center()
				objeto[k] = _dentro(Vector2(c.x, -c.z), pols)
		var out := {"a": a, "base": v.size(), "nuevos": {}}  # los vértices nuevos, por atributo (Array: por referencia)
		var keep := []
		for t in range(0, idx.size(), 3):
			var i0 := idx[t]
			var i1 := idx[t + 1]
			var i2 := idx[t + 2]
			if objeto.has(pieza[i0]):  # antes de la prueba de cajas: un objeto se va entero
				if objeto[pieza[i0]]:
					n.quitados += 1
				else:
					keep.append_array([i0, i1, i2])
				continue
			var tri := PackedVector2Array([Vector2(w[i0].x, -w[i0].z), Vector2(w[i1].x, -w[i1].z), Vector2(w[i2].x, -w[i2].z)])
			var tb := _caja(tri)
			var hits := []
			for pb in pols:
				if pb[1].intersects(tb, true):
					hits.append(pb)
			if hits.is_empty():
				keep.append_array([i0, i1, i2])
				continue
			var nm := (w[i1] - w[i0]).cross(w[i2] - w[i0])
			if absf(nm.y) < VERTICAL * nm.length():  # un muro: por su centro
				var c := (tri[0] + tri[1] + tri[2]) / 3.0
				if _dentro(c, hits):
					n.quitados += 1
				else:
					keep.append_array([i0, i1, i2])
				continue
			var piezas := _recorte(tri, hits, 0)
			if piezas.size() == 1 and absf(_area(piezas[0]) - _area(tri)) <= 1e-6 * absf(_area(tri)) + 1e-9:
				keep.append_array([i0, i1, i2])  # no lo toca
				continue
			if piezas.is_empty():
				n.quitados += 1
				continue
			n.cortados += 1
			var signo := signf(_area(tri))
			for pz in piezas:
				var tr := PackedInt32Array([0, 1, 2]) if pz.size() == 3 else Geometry2D.triangulate_polygon(pz)
				if tr.is_empty() and absf(_area(pz)) > 1e-4:  # no la pudo triangular: en abanico, antes que un hueco
					push_warning("recortar: %s, una pieza de %d vértices en abanico" % [capa, pz.size()])
					for k in range(1, pz.size() - 1):
						tr.append_array([0, k, k + 1])
				for k in range(0, tr.size(), 3):
					var q0: Vector2 = pz[tr[k]]
					var q1: Vector2 = pz[tr[k + 1]]
					var q2: Vector2 = pz[tr[k + 2]]
					var ar := (q1 - q0).cross(q2 - q0) / 2.0
					if absf(ar) < 1e-6:
						continue
					var q := [q0, q1, q2] if signf(ar) == signo else [q0, q2, q1]
					for p in q:
						keep.append(_vertice(out, i0, i1, i2, tri, p))
		if keep.is_empty():
			continue
		_juntar(a, out.nuevos)
		a[Mesh.ARRAY_INDEX] = PackedInt32Array(keep)
		nuevo.add_surface_from_arrays(am.surface_get_primitive_type(s), a)
		nuevo.surface_set_material(nuevo.get_surface_count() - 1, am.surface_get_material(s))
	mi.mesh = nuevo
	print("main.gd: %s, %d triángulos quitados y %d cortados" % [capa, n.quitados, n.cortados])


# lo que queda de un triángulo (en planta) fuera de los recortes hits: polígonos simples, sin huecos. Un recorte
# entero dentro de una pieza deja un hueco, que triangulate_polygon no acepta: el triángulo se parte en cuatro y
# cada parte se recorta de nuevo (tras SUBDIV veces, la parte se quita o queda por su centro)
func _recorte(tri: PackedVector2Array, hits: Array, prof: int) -> Array:
	var piezas := [tri]
	for h in hits:
		var nuevas := []
		for pz in piezas:
			if not _caja(pz).intersects(h[1], true):
				nuevas.append(pz)
				continue
			var r := Geometry2D.clip_polygons(pz, h[0])
			if _hueco(r):
				if prof >= SUBDIV:
					return [] if _dentro((tri[0] + tri[1] + tri[2]) / 3.0, hits) else [tri]
				var m01 := (tri[0] + tri[1]) / 2.0
				var m12 := (tri[1] + tri[2]) / 2.0
				var m20 := (tri[2] + tri[0]) / 2.0
				var out := []
				for sub in [[tri[0], m01, m20], [m01, tri[1], m12], [m20, m12, tri[2]], [m01, m12, m20]]:
					out.append_array(_recorte(PackedVector2Array(sub), hits, prof + 1))
				return out
			nuevas.append_array(r)
		piezas = nuevas
	return piezas


# clip_polygons devuelve un hueco como un polígono de la orientación contraria a la de los demás
func _hueco(r: Array) -> bool:
	if r.size() < 2:
		return false
	var cw := Geometry2D.is_polygon_clockwise(r[0])
	for p in r:
		if Geometry2D.is_polygon_clockwise(p) != cw:
			return true
	return false


# un vértice nuevo en el punto p (en planta) del triángulo i0 i1 i2 (tri, en planta): sus atributos interpolados
# con las coordenadas baricéntricas de p, en out.nuevos; devuelve su índice
func _vertice(out: Dictionary, i0: int, i1: int, i2: int, tri: PackedVector2Array, p: Vector2) -> int:
	var a: Array = out.a
	var nv: Dictionary = out.nuevos
	var d := (tri[1] - tri[0]).cross(tri[2] - tri[0])
	var b1 := (p - tri[0]).cross(tri[2] - tri[0]) / d
	var b2 := (tri[1] - tri[0]).cross(p - tri[0]) / d
	var b0 := 1.0 - b1 - b2
	for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		var x = a[k]
		if x == null:
			continue
		if not nv.has(k):
			nv[k] = []
		match k:
			Mesh.ARRAY_TANGENT:
				var tv := Vector3(x[i0 * 4], x[i0 * 4 + 1], x[i0 * 4 + 2]) * b0 \
					+ Vector3(x[i1 * 4], x[i1 * 4 + 1], x[i1 * 4 + 2]) * b1 + Vector3(x[i2 * 4], x[i2 * 4 + 1], x[i2 * 4 + 2]) * b2
				tv = tv.normalized()
				nv[k].append_array([tv.x, tv.y, tv.z, x[i0 * 4 + 3]])
			Mesh.ARRAY_NORMAL:
				nv[k].append((x[i0] * b0 + x[i1] * b1 + x[i2] * b2).normalized())
			_:
				nv[k].append(x[i0] * b0 + x[i1] * b1 + x[i2] * b2)
	return out.base + nv[Mesh.ARRAY_VERTEX].size() - 1


# agrega a los arreglos de la superficie los vértices nuevos
func _juntar(a: Array, nv: Dictionary) -> void:
	for k in nv:
		var x = a[k]
		match k:
			Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL:
				x.append_array(PackedVector3Array(nv[k]))
			Mesh.ARRAY_TANGENT:
				x.append_array(PackedFloat32Array(nv[k]))
			Mesh.ARRAY_COLOR:
				x.append_array(PackedColorArray(nv[k]))
			_:
				x.append_array(PackedVector2Array(nv[k]))
		a[k] = x


# las piezas de una malla: los triángulos unidos por vértices en el mismo lugar (al milímetro); por vértice, el
# representante de su pieza
func _piezas(w: PackedVector3Array, idx: PackedInt32Array) -> PackedInt32Array:
	var padre := PackedInt32Array()
	padre.resize(w.size())
	var en := {}
	for i in w.size():
		var key := Vector3i((w[i] * 1000.0).round())
		padre[i] = en.get(key, i)
		if not en.has(key):
			en[key] = i
	for t in range(0, idx.size(), 3):
		var r0 := _raiz(padre, idx[t])
		for j in [1, 2]:
			var r := _raiz(padre, idx[t + j])
			if r != r0:
				padre[r] = r0
	for i in w.size():
		padre[i] = _raiz(padre, i)
	return padre


func _raiz(padre: PackedInt32Array, i: int) -> int:
	while padre[i] != i:
		padre[i] = padre[padre[i]]
		i = padre[i]
	return i


func _dentro(p: Vector2, hits: Array) -> bool:
	for pb in hits:
		if pb[1].has_point(p) and Geometry2D.is_point_in_polygon(p, pb[0]):
			return true
	return false


func _caja(pol: PackedVector2Array) -> Rect2:
	var bb := Rect2(pol[0], Vector2.ZERO)
	for p in pol:
		bb = bb.expand(p)
	return bb


func _area(pol: PackedVector2Array) -> float:
	var s := 0.0
	for i in pol.size():
		s += pol[i].cross(pol[(i + 1) % pol.size()])
	return s / 2.0


# las teclas, como acciones (así --caminar puede apretarlas)
func acciones() -> void:
	var teclas := {"adelante": [KEY_W, KEY_UP], "atras": [KEY_S, KEY_DOWN], "izquierda": [KEY_A, KEY_LEFT],
		"derecha": [KEY_D, KEY_RIGHT], "saltar": [KEY_SPACE], "correr": [KEY_SHIFT]}
	for a in teclas:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a)
		for k in teclas[a]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)


# el suelo bajo (X, Z): un rayo desde arriba contra la colisión
func suelo(x: float, z: float) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200, z), Vector3(x, -200, z))
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return r.position if r else Vector3(x, 0, z)


# muros invisibles en el borde de la caja exportada, para no caerse de la maqueta
func muros(caja: AABB) -> void:
	var c := caja.get_center()
	var s := caja.size
	var cuerpo := StaticBody3D.new()
	add_child(cuerpo)
	for m in [[Vector3(c.x, c.y, caja.position.z), Vector3(s.x, 200, 1)], [Vector3(c.x, c.y, caja.end.z), Vector3(s.x, 200, 1)],
			[Vector3(caja.position.x, c.y, c.z), Vector3(1, 200, s.z)], [Vector3(caja.end.x, c.y, c.z), Vector3(1, 200, s.z)]]:
		var forma := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = m[1]
		forma.shape = b
		forma.position = m[0]
		cuerpo.add_child(forma)


func ayuda() -> void:
	var capa := CanvasLayer.new()
	add_child(capa)
	var l := Label.new()
	l.text = "WASD: caminar · Mayús: correr · Espacio: saltar · mouse: mirar · rueda: cámara · Esc: soltar el mouse"
	l.position = Vector2(16, 12)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	capa.add_child(l)
