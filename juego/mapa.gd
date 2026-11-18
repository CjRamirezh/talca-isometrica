# La comuna entera, por teselas: lo que `make juego` exporta de la página a juego/mapa/ (tools/export.py --teselas
# juego/mapa --comuna --tam 500 --instancias arboles,alamos --lejos): un glb por tesela de 500 m (t_<i>_<j>.glb, x de
# 500·i a 500·(i+1), y de 500·j a 500·(j+1)), sus árboles como datos (t_<i>_<j>.json, arboleda.gd), lejos.glb (un nodo
# por tesela con solo el relieve, el agua y el borde) e indice.json (las teselas, las capas, los lugares, las luces de
# los hitos y el límite de la comuna). mapa/ lleva un .gdignore: Godot no importa los glb, se leen al jugar
# (GLTFDocument), en hilos (WorkerThreadPool), mientras se juega.
#
# Alrededor de la cámara (la que esté en uso: el personaje, cine.gd, vp.gd) se cargan las teselas a menos de CARGA y
# se sueltan las que pasan de SOLTAR; donde no hay una cargada se ve la de lejos.glb. Cada tesela, al leerla y antes de
# agregarla, pasa por los recortes de los modelos (recorte.gd) y toma el material de cada capa (materiales.gd); su
# colisión (una malla exacta por capa sólida, glb.gd) se arma solo a menos de COLISION, y se suelta lejos. Las capas
# chicas se dejan de dibujar antes que las teselas (VISTA). En el borde de la comuna, un muro invisible.
#
#   var mapa := preload("res://mapa.gd").new()
#   mapa.recs = recortes; add_child(mapa)
#   mapa.arrancar([Vector2(0, 0)])   # sin hilos: las teselas a menos de ARRANQUE de esos puntos de grilla, con colisión
#                                    # (arrancar(puntos, mapa.CARGA): todo lo que pide la cámara ahí, para --cine)
#   await mapa.esperar()             # hasta que esté cargado todo lo que pide la cámara (capturas, --cine, --fps)
#   mapa.solido(x, y)                # si la colisión bajo ese punto de grilla ya está
extends Node3D

const Glb := preload("res://glb.gd")
const Mat := preload("res://materiales.gd")
const Recorte := preload("res://recorte.gd")
const Arboleda := preload("res://arboleda.gd")
const DIR := "res://mapa/"
const CARGA := 1800.0  # m de la cámara al borde de la tesela
const SOLTAR := 2300.0
const COLISION := 250.0
const SIN_COLISION := 500.0
const ARRANQUE := 250.0
const HILOS := 3  # teselas que se leen a la vez
const VISTA := {"autos": 450.0, "autos-ruta5": 600.0, "trenes": 900.0, "veredas": 900.0, "patios": 1100.0}

var recs := []  # los recortes de los modelos (main.gd)
var info := {}
var tam := 500.0
var teselas := {}  # "i_j" -> la entrada de indice.json
var cargadas := {}  # "i_j" -> Node3D (la raíz del glb)
var colision := {}  # "i_j" -> true: tiene su colisión
var lejos := {}  # "i_j" -> MeshInstance3D de lejos.glb
var tareas := {}  # id de WorkerThreadPool -> ["leer" | "colision", clave]
var hechas := []  # lo que terminaron los hilos: [tipo, clave, resultado]
var cerrojo := Mutex.new()
var arboleda: Node3D
var foco := Vector2(INF, INF)
var t_revisar := 0.0
var stats := {"leidas": 0, "ms": 0}


func _init() -> void:
	name = "mapa"
	info = Glb.info()
	tam = float(info.get("tesela_m", 500.0))
	for t in info.get("teselas", []):
		teselas["%d_%d" % [t["i"], t["j"]]] = t


func _ready() -> void:
	arboleda = Arboleda.new()
	add_child(arboleda)
	cargar_lejos()
	muro_del_limite()


# lejos.glb: una malla por tesela (t_<i>_<j>), con una superficie por capa (su material se llama como la capa)
func cargar_lejos() -> void:
	var l: Dictionary = info.get("lejos", {})
	if l.is_empty():
		return
	var raiz := leer_glb(DIR + String(l["archivo"]))
	if raiz == null:
		return
	raiz.name = "lejos"
	add_child(raiz)
	for mi in raiz.find_children("*", "MeshInstance3D", true, false):
		var clave := String(mi.name).trim_prefix("t_")
		lejos[clave] = mi
		for s in mi.mesh.get_surface_count():
			var capa := String(mi.mesh.surface_get_material(s).resource_name)
			if Glb.tipo(capa) != "":
				mi.set_surface_override_material(s, Mat.capa(capa, Glb.tipo(capa)))
		colores(mi.mesh)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = not cargadas.has(clave)


static func leer_glb(ruta: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(ruta), st)
	if err != OK:
		push_error("mapa.gd: no pude leer %s (%s)" % [ruta, error_string(err)])
		return null
	return doc.generate_scene(st) as Node3D


# Las capas sin material propio en el juego (tipo null en LAYERS: borde, via, ruta5, cerro, trenes, otros) quedan con
# el del glb, y el importador de Godot no usa sus colores por vértice (COLOR_0 con material): sin esto salen blancas
static func colores(m: Mesh) -> void:
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s) as BaseMaterial3D
		if mat:
			mat.vertex_color_use_as_albedo = true


# ---------- las teselas ----------

func caja(clave: String) -> Rect2:
	var t: Dictionary = teselas[clave]
	return Rect2(t["i"] * tam, t["j"] * tam, tam, tam)


func distancia(clave: String, p: Vector2) -> float:
	var c := caja(clave)
	var q := Vector2(clampf(p.x, c.position.x, c.end.x), clampf(p.y, c.position.y, c.end.y))
	return q.distance_to(p)


# las teselas a menos de r de p, de la más cercana a la más lejana
func cerca_de(p: Vector2, r: float) -> Array:
	var out := []
	var i0 := floori((p.x - r) / tam)
	var i1 := floori((p.x + r) / tam)
	var j0 := floori((p.y - r) / tam)
	var j1 := floori((p.y + r) / tam)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k := "%d_%d" % [i, j]
			if teselas.has(k) and distancia(k, p) <= r:
				out.append(k)
	out.sort_custom(func(a, b): return distancia(a, p) < distancia(b, p))
	return out


# en un hilo: el glb de la tesela con los recortes aplicados, sus árboles listos para arboleda.gd y, si se pide, las
# formas de su colisión
func leer(clave: String, con_colision: bool) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var t: Dictionary = teselas[clave]
	var raiz := leer_glb(DIR + String(t["archivo"]))
	var out := {"raiz": raiz, "arboles": {}, "formas": {}}
	if raiz == null:
		return out
	raiz.name = "t_" + clave
	if Recorte.toca(recs, caja(clave)):
		for mi in raiz.find_children("*", "MeshInstance3D", true, false):
			Recorte.recortar(mi, recs)
	var f := DIR + String(t["archivo"]).get_basename() + ".json"
	if t.has("instancias") and FileAccess.file_exists(f):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		if j is Dictionary:
			out["arboles"] = Arboleda.preparar(j, recs)
	if con_colision:
		out["formas"] = formas(raiz)
	out["ms"] = Time.get_ticks_msec() - t0
	return out


static func formas(raiz: Node3D) -> Dictionary:
	return formas_de(mallas_solidas(raiz))


# capa -> Mesh de las capas sólidas de una tesela (en el hilo principal si ya está en la escena: Godot no deja tocar
# un nodo de la escena desde otro hilo)
static func mallas_solidas(raiz: Node3D) -> Dictionary:
	var out := {}
	for mi in raiz.find_children("*", "MeshInstance3D", true, false):
		if Glb.solida(String(mi.name)) and mi.mesh:
			out[String(mi.name)] = mi.mesh
	return out


static func formas_de(mallas: Dictionary) -> Dictionary:
	var out := {}
	for capa in mallas:
		out[capa] = mallas[capa].create_trimesh_shape()
	return out


# en el hilo principal: la tesela leída, a la escena
func poner(clave: String, r: Dictionary) -> void:
	var raiz: Node3D = r["raiz"]
	if raiz == null:
		return
	for mi in raiz.find_children("*", "MeshInstance3D", true, false):
		var capa := String(mi.name)
		if Glb.tipo(capa) != "":
			mi.material_override = Mat.capa(capa, Glb.tipo(capa))
		else:
			colores(mi.mesh)
		if VISTA.has(capa):
			mi.visibility_range_end = VISTA[capa]
	add_child(raiz)
	cargadas[clave] = raiz
	if lejos.has(clave):
		lejos[clave].visible = false
	if not r["arboles"].is_empty():
		arboleda.agregar(clave, r["arboles"])
	if not r["formas"].is_empty():
		poner_colision(clave, r["formas"])
	stats["leidas"] += 1
	stats["ms"] += int(r.get("ms", 0))


# la colisión de una tesela: un StaticBody3D bajo cada malla sólida, como create_trimesh_collision() (main.gd --caminar
# dice contra qué capa chocó por el nombre del padre del cuerpo)
func poner_colision(clave: String, fs: Dictionary) -> void:
	var raiz: Node3D = cargadas.get(clave)
	if raiz == null:
		return
	for mi in raiz.find_children("*", "MeshInstance3D", true, false):
		var capa := String(mi.name)
		if fs.has(capa) and fs[capa] != null:
			var cuerpo := StaticBody3D.new()
			cuerpo.name = "colision"
			var forma := CollisionShape3D.new()
			forma.shape = fs[capa]
			cuerpo.add_child(forma)
			mi.add_child(cuerpo)
	colision[clave] = true


func quitar_colision(clave: String) -> void:
	var raiz: Node3D = cargadas.get(clave)
	if raiz:
		for c in raiz.find_children("colision", "StaticBody3D", true, false):
			c.queue_free()
	colision.erase(clave)


func soltar(clave: String) -> void:
	cargadas[clave].queue_free()
	cargadas.erase(clave)
	colision.erase(clave)
	arboleda.quitar(clave)
	if lejos.has(clave):
		lejos[clave].visible = true


# sin hilos, al comenzar: lo que necesitan los modelos (suelo.gd lee el «terreno» de las teselas cargadas) y el lugar
# donde aparece el personaje, con colisión. Con r = CARGA, todo lo que la cámara pedirá ahí (--cine: Movie Maker graba
# cada cuadro, también los de una carga en hilos, así que la película carga antes del primero)
func arrancar(puntos: Array, r := ARRANQUE) -> void:
	var t0 := Time.get_ticks_msec()
	for p in puntos:
		for k in cerca_de(p, r):
			if not cargadas.has(k):
				poner(k, leer(k, distancia(k, p) <= maxf(ARRANQUE, COLISION)))
	print("mapa.gd: %d teselas al comenzar en %d ms (de %d; %d MB)" % [cargadas.size(), Time.get_ticks_msec() - t0, teselas.size(),
		roundi(_mb(cargadas.keys()))])


func _mb(claves: Array) -> float:
	var s := 0.0
	for k in claves:
		s += float(teselas[k].get("MB", 0.0))
	return s


func _process(dt: float) -> void:
	recoger()
	t_revisar -= dt
	if t_revisar > 0.0:
		return
	t_revisar = 0.2
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	foco = Vector2(cam.global_position.x, -cam.global_position.z)
	revisar(foco)


# lo que falta y lo que sobra alrededor de p
func revisar(p: Vector2) -> void:
	for k in cargadas.keys():
		var d := distancia(k, p)
		if d > SOLTAR and not ocupada(k):
			soltar(k)
		elif d > SIN_COLISION and colision.has(k):
			quitar_colision(k)
	for k in cerca_de(p, CARGA):
		if tareas.size() >= HILOS:
			break
		if ocupada(k):
			continue
		var con := distancia(k, p) <= COLISION
		if not cargadas.has(k):
			lanzar("leer", k, con)
		elif con and not colision.has(k):
			lanzar("colision", k, true)


func ocupada(clave: String) -> bool:
	for id in tareas:
		if tareas[id][1] == clave:
			return true
	return false


func lanzar(tipo: String, clave: String, con: bool) -> void:
	var f: Callable
	if tipo == "leer":
		f = func():
			var r := leer(clave, con)
			cerrojo.lock()
			hechas.append([tipo, clave, r])
			cerrojo.unlock()
	else:
		var mallas := mallas_solidas(cargadas[clave])
		f = func():
			var r := formas_de(mallas)
			cerrojo.lock()
			hechas.append([tipo, clave, r])
			cerrojo.unlock()
	var id := WorkerThreadPool.add_task(f, false, "mapa: %s %s" % [tipo, clave])
	tareas[id] = [tipo, clave]


# en el hilo principal: lo que terminaron los hilos
func recoger() -> void:
	for id in tareas.keys():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			tareas.erase(id)
	cerrojo.lock()
	var listas := hechas
	hechas = []
	cerrojo.unlock()
	for h in listas:
		if h[0] == "leer":
			if cargadas.has(h[1]):
				continue
			poner(h[1], h[2])
		elif cargadas.has(h[1]) and not colision.has(h[1]):
			poner_colision(h[1], h[2])


# si ya está todo lo que pide la cámara: las teselas a menos de CARGA y la colisión a menos de COLISION
func listo() -> bool:
	if not tareas.is_empty():
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return true
	var p := Vector2(cam.global_position.x, -cam.global_position.z)
	for k in cerca_de(p, CARGA):
		if not cargadas.has(k) or (distancia(k, p) <= COLISION and not colision.has(k)):
			return false
	return true


func esperar() -> void:
	var t0 := Time.get_ticks_msec()
	await get_tree().process_frame
	while not listo():
		t_revisar = 0.0
		await get_tree().process_frame
	print("mapa.gd: %d teselas cargadas en %d ms (%d MB)" % [cargadas.size(), Time.get_ticks_msec() - t0, roundi(_mb(cargadas.keys()))])


# si la colisión bajo el punto (x, y) de grilla ya está (jugador.gd no cae mientras no)
func solido(x: float, y: float) -> bool:
	var k := "%d_%d" % [floori(x / tam), floori(y / tam)]
	return colision.has(k) or not teselas.has(k)


func lejos_visible(v: bool) -> void:
	var l := get_node_or_null("lejos")
	if l:
		l.visible = v


# un muro invisible a lo largo del límite de la comuna (indice.json, «limite»: el anillo de la página, LIM), de 2 km de
# alto: el personaje no sale del diorama
func muro_del_limite() -> void:
	var lim: Array = info.get("limite", [])
	if lim.size() < 3:
		return
	var caras := PackedVector3Array()
	for i in lim.size():
		var a: Array = lim[i]
		var b: Array = lim[(i + 1) % lim.size()]
		var pa := Vector3(a[0], -500, -a[1])
		var pb := Vector3(b[0], -500, -b[1])
		var arriba := Vector3.UP * 2000
		caras.append_array([pa, pb, pb + arriba, pa, pb + arriba, pa + arriba])
	var forma := ConcavePolygonShape3D.new()
	forma.backface_collision = true
	forma.set_faces(caras)
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "limite"
	var cs := CollisionShape3D.new()
	cs.shape = forma
	cuerpo.add_child(cs)
	add_child(cuerpo)
