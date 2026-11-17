# Un plano de cine en la Plaza de Armas: «Una tarde en la Plaza de Armas». Una sola toma de DURACION s, de la hora
# dorada a la noche, con la luz del sol donde está en Talca ese día (ambiente.gd), peatones que cruzan la plaza
# (peaton.gd) y una cámara en un recorrido fijo que termina frente a la Catedral. Todo es función del tiempo t de la
# toma: la cámara (PLANO), la hora (HORAS) y los peatones (PEATONES), así que un cuadro se puede rehacer solo
# (--cuadro) y la película sale igual cada vez.
#
#   make cine [CINE=1280x720] [CINE_CRF=23]              # la película: shots/cine/plaza.mp4 (ver Makefile; ~1 min en el Mac)
#   Godot --path juego --write-movie $PWD/shots/cine/plaza.avi --fixed-fps 30 -- --cine
#   Godot --path juego -- --cine --cuadro 0,12,30 --png shots/cine/c.png   # cuadros sueltos, para ajustar el encuadre
#
# La ruta de --write-movie va absoluta (Godot toma una relativa desde juego/, y si la carpeta no existe no graba nada,
# con un solo ERROR en la consola). El tamaño de la película es el de la ventana del proyecto (1600 × 1000):
# --resolution no lo cambia; make cine escribe juego/override.cfg con CINE y lo borra al terminar. En el mismo archivo
# sube la calidad del MJPEG a 1,0 (editor/movie_writer/video_quality): con la de omisión, 0,75, las copas oscuras y el
# cielo de noche salen con una grilla de 8 × 8 que el H.264 además copia (125 MB los 30 s a CRF 18, contra 99 MB).
# Una secuencia PNG (--write-movie x.png) no sirve en Godot 4.7.2: tarda seis veces más y la hora del juego avanza
# mal (901 archivos con 3 s de toma).
#
# Con --write-movie (Movie Maker de Godot) cada cuadro dura 1/--fixed-fps s del juego, tarde lo que tarde en
# dibujarse: la película sale con toda la calidad (SSIL, sombras blandas, niebla) aunque la máquina no llegue a 30
# cuadros por segundo. Al terminar la toma, el juego sale y Godot cierra el archivo.
#
#   --cuadro T     solo el cuadro del segundo T de la toma: con --png lo guarda y sale; con varios (--cuadro 0,12,30
#                  --png x.png), x-t0.png, x-t12.png… de una sola carga
#   --sin-titulo   sin la hora, el título ni los fundidos (para montar aparte)
#
# Coordenadas como en main.gd: x, y de grilla (x al oriente, y al norte), X = x, Z = -y; las alturas de PLANO son
# sobre el suelo bajo ese punto (un rayo contra la colisión, main.suelo()), y las de adonde mira, sobre el suelo bajo
# la cámara. Lo aproximado: los recorridos de los
# peatones van por los senderos del plano de plaza.gd a ojo (los prados y la pileta, sin colisión con los escaños).
extends Node3D

const Args := preload("res://args.gd")
const Peaton := preload("res://peaton.gd")

const DURACION := 30.0  # s
const FUNDIDO := 1.2  # s: de negro al comenzar y a negro al terminar
const DIA := 15  # 15 de enero
const HORAS := [19.75, 21.9]  # la hora al comenzar y al terminar (hora de verano); el sol se pone a las 21:00
const LUZ := [0.12, 0.8]  # la hora avanza entre estas fracciones de la toma (antes y después queda quieta)
const FOV := 50.0

# la cámara: [t, x, y, alto, mira x, mira y, mira alto]. Entre las claves, una curva de Hermite con las tangentes de
# Catmull-Rom (por el tiempo de cada clave), detenida en la primera y la última: arranca y se posa sola. La posición
# sigue esa curva y la mirada también, pero en ángulos (rumbo e inclinación hacia el punto de cada clave), no en el
# punto: un punto a 8 m (la pileta) que pasa a uno a 33 m barre casi todo el giro en el primer tercio del tramo (un
# latigazo de 90° en 1,5 s), y los ángulos lo reparten. El recorrido
# va por el pasillo de baldosas del lado norte de la plaza (y ≈ 40, entre la hilera de árboles de la calle y las
# palmeras de adentro: el único tramo sin copas encima, ver `--cenital -30,10,150`), que apunta al frontis de la
# Catedral (x ≈ -74, y ≈ 40); con el sol al poniente, la Catedral queda a contraluz y el cielo detrás se enciende.
const PLANO := [
	[0.0, 2.0, 38.0, 0.9, -0.8, 29.7, 1.0],      # baja, junto a la pileta norte, mirando el agua (entre los faroles del eje)
	[6.0, 2.0, 40.5, 1.8, -30.0, 40.0, 3.5],     # sube y gira al poniente, por el pasillo
	[16.0, -8.0, 40.5, 2.4, -74.0, 40.0, 10.0],   # avanza a ~1 m/s: la Catedral al fondo, entre los árboles
	[24.0, -16.0, 40.5, 3.2, -74.0, 40.0, 12.0],
	[DURACION, -20.0, 40.5, 4.0, -74.0, 40.0, 14.0],  # se posa: el frontis y el campanario enteros, de noche
]

# Un peatón: sus colores, su rapidez (m/s), dónde va en t = 0 (m del recorrido; negativo: entra después) y su
# recorrido en x, y de grilla; al final se queda quieto. "anillo", a0, a1 en un recorrido: el anillo de ANILLO m
# alrededor de la pileta central, de a0 a a1 grados (0: al oriente).
const ANILLO := 7.6
const PEATONES := [
	# delante de la cámara hacia la Catedral; cruza 1 Poniente y se queda frente a la escalinata
	{"colores": {"polera": "b03a2e", "jeans": "2d3c58", "pelo": "1c1410"}, "v": 1.3, "s0": 30.0,
		"ruta": [[28, 41.5], [-44, 42], [-60, 40.5], [-68.5, 40.5]]},
	# hacia la cámara: se cruzan a media toma (t ≈ 15 s), a 3 m
	{"colores": {"polera": "e8e2d0", "jeans": "4a4038", "pelo": "6b4a2e", "piel": "d8a98a"}, "v": 1.25, "s0": 24.0,
		"ruta": [[-50, 37.5], [40, 37.5]]},
	# entra por el norte, cruza el pasillo al comienzo y se va al oriente
	{"colores": {"polera": "2f5d3a", "jeans": "1f2430", "pelo": "2a1d16", "piel": "a87358"}, "v": 1.35, "s0": 4.0,
		"ruta": [[3, 60], [3, 45], [12, 38.5], [45, 38.5]]},
	# por la vereda de 1 Poniente, al pie de la Catedral, al final
	{"colores": {"polera": "d9a23a", "jeans": "35466a", "pelo": "120d0a"}, "v": 1.4, "s0": 0.0,
		"ruta": [[-58.5, -2], [-58.5, 70]]},
]

var t := 0.0
var cam := Camera3D.new()
var ambiente: Node
var main: Node
var claves := []  # [t, posición, mira, Vector3(inclinación, rumbo, 0)] en el mundo
var peatones := []  # {"nodo", "puntos": PackedVector3Array, "largo": PackedFloat32Array, "v", "s0", "y"}
var negro := ColorRect.new()
var reloj := Label.new()
var titulo := VBoxContainer.new()
var listo := false
var quieto := -1.0  # --cuadro: el t fijo
var cuadros := PackedFloat32Array()  # --cuadro T1,T2,…
var con_titulo := true


func _ready() -> void:
	main = get_parent()
	for n in main.get_children():
		if n.has_method("poner_hora"):
			ambiente = n
	cam.fov = FOV
	cam.near = 0.1
	cam.far = 3000
	add_child(cam)
	cam.make_current()
	con_titulo = not Args.has("--sin-titulo")
	for c in Args.lista("--cuadro"):
		if c.is_valid_float():
			cuadros.append(clampf(float(c), 0.0, DURACION))
		else:
			push_warning("cine.gd: --cuadro espera segundos de la toma, no «%s»" % c)
	if cuadros.size() > 0:
		quieto = cuadros[0]
	pantalla()
	if ambiente:
		ambiente.dia = DIA
		if ambiente.reloj:
			ambiente.reloj.get_parent().visible = false  # el reloj del juego
	# los rayos contra el suelo necesitan la colisión ya en el mundo
	await get_tree().physics_frame
	await get_tree().physics_frame
	for k in PLANO:
		var p: Vector3 = suelo(k[1], k[2]) + Vector3.UP * float(k[3])
		var m := Vector3(k[4], p.y - float(k[3]) + float(k[6]), -float(k[5]))  # sobre el suelo bajo la cámara: un rayo en la Catedral daría en el techo
		claves.append([float(k[0]), p, m, angulos(m - p, claves)])
	for d in PEATONES:
		peatones.append(peaton(d))
	listo = true
	if cuadros.size() == 1:
		await fijar(quieto)
		await main.png()  # sin --png queda en ese cuadro, para mirarlo
		return
	if cuadros.size() > 1:  # varios cuadros de una sola carga: x.png -> x-t12.png, x-t24.png…
		var out: String = main.abs_path(Args.texto("--png")) if Args.has("--png") else "user://cine.png"
		for c in cuadros:
			await fijar(c)
			var f := "%s-t%s.png" % [out.get_basename(), String.num(c, 2).trim_suffix(".0")]  # c-t12.png, c-t29.9.png
			get_viewport().get_texture().get_image().save_png(f)
			print("cine.gd -> ", f)
		get_tree().quit()
		return
	mover(0.0)


# el cuadro del segundo tt, con los pasos de los peatones ya en su fase y la luz del cielo al día
func fijar(tt: float) -> void:
	quieto = tt
	t = tt
	for i in 40:
		mover(1.0 / 30.0)
	for i in 8:
		await RenderingServer.frame_post_draw


func _process(dt: float) -> void:
	if not listo or quieto >= 0.0:
		return
	t += dt
	mover(dt)
	if t >= DURACION:
		print("cine.gd: %.1f s, fin de la toma" % t)
		get_tree().quit()


func mover(dt: float) -> void:
	var h := lerpf(HORAS[0], HORAS[1], smoothstep(LUZ[0], LUZ[1], t / DURACION))
	if ambiente:
		ambiente.objetivo = h
		ambiente.poner_hora(h)
	camara(t)
	for p in peatones:
		paso(p, dt)
	if con_titulo:
		var f := clampf(t / FUNDIDO, 0.0, 1.0) * clampf((DURACION - t) / FUNDIDO, 0.0, 1.0)
		negro.color.a = 0.0 if quieto >= 0.0 else 1.0 - smoothstep(0.0, 1.0, f)  # los cuadros sueltos, sin fundido
		reloj.text = "15 de enero · %02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]
		titulo.modulate.a = smoothstep(DURACION - 8.0, DURACION - 5.5, t)
		reloj.modulate.a = 1.0 - titulo.modulate.a  # el título la reemplaza


# ---------- la cámara ----------

func camara(tt: float) -> void:
	var n := claves.size()
	var i := 0
	while i < n - 2 and tt > claves[i + 1][0]:
		i += 1
	var t0: float = claves[i][0]
	var t1: float = claves[i + 1][0]
	var u := clampf((tt - t0) / (t1 - t0), 0.0, 1.0)
	cam.global_position = hermite(i, 1, u)
	cam.basis = Basis.from_euler(hermite(i, 3, u))  # YXZ: el rumbo y después la inclinación; la cámara mira hacia -Z


# la inclinación y el rumbo de la dirección d, con el rumbo sin saltos de 2π respecto de la clave anterior
func angulos(d: Vector3, antes: Array) -> Vector3:
	var rumbo := atan2(-d.x, -d.z)
	if antes.size() > 0:
		var r0: float = antes[-1][3].y
		rumbo = r0 + wrapf(rumbo - r0, -PI, PI)
	return Vector3(asin(d.normalized().y), rumbo, 0.0)


# el valor k de las claves (1, la cámara; 3, los ángulos de la mirada) entre las claves i e i + 1, en u ∈ [0, 1]
func hermite(i: int, k: int, u: float) -> Vector3:
	var a: Vector3 = claves[i][k]
	var b: Vector3 = claves[i + 1][k]
	var dt: float = claves[i + 1][0] - claves[i][0]
	var ma := tangente(i, k) * dt
	var mb := tangente(i + 1, k) * dt
	var u2 := u * u
	var u3 := u2 * u
	return a * (2 * u3 - 3 * u2 + 1) + ma * (u3 - 2 * u2 + u) + b * (-2 * u3 + 3 * u2) + mb * (u3 - u2)


func tangente(i: int, k: int) -> Vector3:
	if i == 0 or i == claves.size() - 1:
		return Vector3.ZERO
	return (claves[i + 1][k] - claves[i - 1][k]) / (claves[i + 1][0] - claves[i - 1][0])


# ---------- los peatones ----------

func peaton(d: Dictionary) -> Dictionary:
	var pts := PackedVector2Array()
	var ruta: Array = d["ruta"]
	var j := 0
	while j < ruta.size():
		var r = ruta[j]
		if r is String and r == "anillo":  # el anillo de la pileta, de un ángulo a otro (grados, 0: al oriente)
			var a0: float = ruta[j + 1]
			var a1: float = ruta[j + 2]
			var pasos := maxi(2, int(absf(a1 - a0) / 10.0))
			for s in pasos + 1:
				var a := deg_to_rad(lerpf(a0, a1, float(s) / pasos))
				pts.append(Vector2(0.2, -1.4) + Vector2(cos(a), sin(a)) * ANILLO)
			j += 3
			continue
		pts.append(Vector2(r[0], r[1]))
		j += 1
	var largo := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		largo.append(largo[i - 1] + pts[i].distance_to(pts[i - 1]))
	var nodo: Node3D = Peaton.new()
	nodo.colores = d["colores"]
	add_child(nodo)
	return {"nodo": nodo, "puntos": pts, "largo": largo, "v": float(d["v"]), "s0": float(d["s0"]), "y": NAN, "rumbo": NAN}


func paso(p: Dictionary, dt: float) -> void:
	var pts: PackedVector2Array = p["puntos"]
	var largo: PackedFloat32Array = p["largo"]
	var total: float = largo[largo.size() - 1]
	var s: float = p["s0"] + p["v"] * t
	var nodo: Node3D = p["nodo"]
	nodo.visible = s >= 0.0
	var rapidez: float = p["v"] if s > 0.0 and s < total else 0.0
	s = clampf(s, 0.0, total)
	var i := 0
	while i < pts.size() - 2 and s > largo[i + 1]:
		i += 1
	var a := pts[i]
	var b := pts[i + 1]
	var q := a.lerp(b, (s - largo[i]) / maxf(largo[i + 1] - largo[i], 1e-6))
	var dir := b - a
	var rumbo := atan2(-dir.x, dir.y)  # peaton.gd mira hacia -Z (el norte): rumbo 0 al norte, positivo al poniente
	p["rumbo"] = rumbo if is_nan(p["rumbo"]) else lerp_angle(p["rumbo"], rumbo, 1.0 - exp(-6.0 * dt))
	var desde: float = 50.0 if is_nan(p["y"]) else p["y"] + 1.0  # bajo las copas, no sobre ellas
	var y := suelo(q.x, -q.y, desde).y
	p["y"] = y
	nodo.global_position = Vector3(q.x, y, -q.y)
	nodo.rotation.y = p["rumbo"]
	nodo.animar(dt, rapidez, true)


func suelo(x: float, y: float, desde := 200.0) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, desde, -y), Vector3(x, -200, -y))
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return r.position if r else Vector3(x, 0, -y)


# ---------- lo que va sobre la imagen ----------

func pantalla() -> void:
	var capa := CanvasLayer.new()
	add_child(capa)
	var alto := float(get_viewport().get_visible_rect().size.y)
	reloj.add_theme_font_size_override("font_size", int(alto * 0.03))
	reloj.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	reloj.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	reloj.add_theme_constant_override("outline_size", int(alto * 0.004))
	reloj.anchor_top = 1.0
	reloj.anchor_bottom = 1.0
	reloj.offset_left = alto * 0.05
	reloj.offset_top = -alto * 0.09
	capa.add_child(reloj)

	titulo.set_anchors_preset(Control.PRESET_FULL_RECT)
	titulo.alignment = BoxContainer.ALIGNMENT_END  # en el tercio de abajo: arriba está el campanario
	titulo.offset_bottom = -alto * 0.045
	titulo.modulate.a = 0.0
	for l in [["Talca · Plaza de Armas", 0.065], ["35,43° S · 71,67° O · la luz del sol de ese lugar y ese día", 0.026]]:
		var e := Label.new()
		e.text = l[0]
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.add_theme_font_size_override("font_size", int(alto * l[1]))
		e.add_theme_color_override("font_color", Color(1, 0.97, 0.9))
		e.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
		e.add_theme_constant_override("outline_size", int(alto * 0.006))
		titulo.add_child(e)
	capa.add_child(titulo)

	negro.set_anchors_preset(Control.PRESET_FULL_RECT)
	negro.color = Color(0, 0, 0, 1)
	negro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(negro)
	reloj.visible = con_titulo
	titulo.visible = con_titulo
	negro.visible = con_titulo
