# La bicicleta y el auto: la comuna mide ~20 km de lado, y caminando (8 m/s) o corriendo (18) se tarda. E sube al
# vehículo si está a menos de CERCA, o lo trae al lado del personaje (donde quedó puede estar a kilómetros); E de nuevo
# baja, y el vehículo queda estacionado ahí. V cambia entre la bicicleta y el auto (también andando). W/S acelera y
# frena (detenido, S retrocede), A/D gira, Espacio frena de golpe; con la bicicleta, Q pedalea de pie (más rápido).
#
# Física de juego, no de simulador: un CharacterBody3D (como el personaje) con una cápsula acostada a lo largo del
# vehículo, que se desliza contra muros y autos estacionados y sube sola los bordes de hasta r·(1 − cos 40°) (el auto,
# 20 cm: soleras y veredas; la bicicleta, con un peldaño como el de jugador.gd). No se puede volcar: el cuerpo nunca se
# inclina; lo que se inclina es el modelo, que se apoya en el suelo bajo sus ruedas (cuatro rayos) y, en la bicicleta,
# se echa hacia la curva; la cápsula toma solo su cabeceo, para quedar a lo largo de una pendiente. Avanza en la
# dirección en que apunta (sin derrape): giro = rapidez / batalla · tan(volante), acotado por la aceleración lateral
# («lateral»), así que de rápido gira menos. Acelera con potencia: a = mín(acel, potencia / v), y la pendiente le resta
# g · sen(cabeceo); en una subida llega a potencia / (g · sen): por el Cerro La Virgen (~20°) la bicicleta sube a
# ~13 km/h (de pie, ~22) y el auto a ~85. VehicleBody3D se probó y se descartó (CHANGELOG, «Bicicleta y auto»).
#
# La rapidez máxima del auto depende de dónde va: en una calzada de la Ruta 5 vmax_ruta, en el resto vmax. La calzada
# sale de datos/ruta5.json (la copia de data/ruta5.json que hace `make juego`: las líneas de OSM entre la primera y la
# segunda pista, CLAUDE.md, «Las líneas de OSM de la Ruta 5…»), no del suelo: en el glb su asfalto va en la capa «suelo»
# como el de las calles. Mientras la tesela de adelante no tiene colisión (mapa.gd), frena;
# sin la de abajo, espera quieto (jugador.gd hace lo mismo).
#
#   var v := preload("res://vehiculo.gd").new()
#   v.jugador = jugador; v.mapa = mapa; add_child(v)
#   v.usar()            # E: sube, baja o lo trae
#   v.cambiar()         # V: bicicleta <-> auto
#   await v.prueba()    # --vehiculo bici|auto --conducir N [--volante v]: acelera N s y dice dónde terminó (main.gd)
#
# El auto es el sedán de modelos/entorno/auto.gd (el de calles.gd y autos.gd), con sus ruedas aparte para que giren.
extends CharacterBody3D

const Malla := preload("res://malla.gd")
const Mat := preload("res://materiales.gd")
const Args := preload("res://args.gd")
const Auto := preload("res://modelos/entorno/auto.gd")

const CERCA := 6.0  # m: E sube a un vehículo a esta distancia; más lejos, lo trae
const SEGUIR := 1.2  # s sin mover el mouse para que la cámara vuelva detrás del vehículo
const PISO := 40.0  # grados: más empinado es un muro (más el cabeceo del vehículo: apoyar())
# lo que cambia entre los dos: rapidez (m/s), aceleraciones (m/s²), geometría (m), la cápsula (radio y largo) y la cámara
const TIPOS := {
	"bici": {"nombre": "bicicleta", "vmax": 12.0, "vmax_fuerte": 16.0, "vmax_ruta": 16.0, "acel": 4.5, "acel_fuerte": 6.0,
		"potencia": 12.0, "potencia_fuerte": 20.0,  # W/kg (m²/s³): la de un ciclista, exagerada como el relieve
		"freno": 6.0, "frenazo": 8.0, "reversa": 1.5, "batalla": 1.05, "giro": 0.65, "lateral": 6.0, "radio": 0.3, "largo": 1.8,
		"peldano": 0.25, "brazo": 5.5, "alto": 1.9, "ojo": Vector3(0, 1.62, -0.05)},
	"auto": {"nombre": "auto", "vmax": 25.0, "vmax_fuerte": 25.0, "vmax_ruta": 36.0, "acel": 4.5, "acel_fuerte": 4.5,
		"potencia": 80.0, "potencia_fuerte": 80.0,  # W/kg: 100 kW en 1.250 kg
		"freno": 9.0, "frenazo": 11.0, "reversa": 5.0, "batalla": 2.8, "giro": 0.6, "lateral": 8.0, "radio": 0.85, "largo": 4.6,
		"peldano": 0.0, "brazo": 9.0, "alto": 2.4, "ojo": Vector3(-0.38, 1.18, 0.25)},
}

var tipo := "bici"
var t: Dictionary = TIPOS["bici"]
var jugador: CharacterBody3D  # jugador.gd
var mapa: Node3D  # mapa.gd
var montado := false
var activo := false  # aparece la primera vez que se usa
var rapidez := 0.0  # m/s a lo largo del rumbo (negativa: en reversa)
var rumbo := 0.0  # como jugador.yaw: 0 mirando al norte (-Z), crece a la izquierda
var volante := 0.0  # -1 izquierda … 1 derecha, suavizado
var en_ruta := false
var r5 := {}  # celda de R5_CELDA m -> [[a, b], …]: los tramos de las dos calzadas de la Ruta 5, en metros de grilla
const R5_CELDA := 100.0
var pisa := ""  # la capa del suelo bajo el vehículo
var ultimo_suelo := Vector3.ZERO
var llegar := Vector3.INF  # ir(): como jugador.gd
var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var forma := CollisionShape3D.new()
var modelo := Node3D.new()  # se inclina con el suelo (y la bicicleta, en las curvas)
var ruedas: Array[Node3D] = []  # giran con la rapidez
var direccion: Array[Node3D] = []  # giran con el volante (la horquilla, las ruedas de adelante)
var radio_rueda := 0.34
var biela: Node3D  # la bicicleta: los pedales
var fase := 0.0  # ángulo de las ruedas
var fase_biela := 0.0
var inclinar := Vector3.ZERO  # (cabeceo, alabeo, alto) del modelo, suavizados
var asiento := Node3D.new()  # donde va el peatón en la bicicleta
var hud := Label.new()

# --conducir: lo medido mientras anda
var prueba_on := false
var med := {}


func _init() -> void:
	name = "vehiculo"


func _ready() -> void:
	add_child(forma)
	add_child(modelo)
	floor_max_angle = deg_to_rad(PISO)
	floor_constant_speed = true
	floor_stop_on_slope = true
	var capa := CanvasLayer.new()
	add_child(capa)
	hud.anchor_top = 1.0
	hud.anchor_bottom = 1.0
	hud.position = Vector2(16, -44)
	hud.add_theme_font_size_override("font_size", 22)
	hud.add_theme_color_override("font_color", Color(1, 1, 1))
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	hud.add_theme_constant_override("outline_size", 5)
	hud.visible = false
	capa.add_child(hud)
	cargar_r5()
	armar(tipo)
	visible = false
	forma.disabled = true


# ---------- subir, bajar, cambiar ----------

# E: si está montado, baja; si el vehículo está cerca, sube; si no, lo trae al lado y sube
func usar() -> void:
	if montado:
		bajar()
		return
	if not activo or global_position.distance_to(jugador.global_position) > CERCA:
		traer()
	subir()


# V: la bicicleta por el auto o al revés, donde esté (montado o no)
func cambiar() -> void:
	armar("auto" if tipo == "bici" else "bici")
	if montado:
		peaton_al_vehiculo()
		jugador.largo = t["brazo"]
		rapidez = clampf(rapidez, -t["reversa"], t["vmax_ruta"])
	print("vehiculo.gd: ", t["nombre"])


func traer() -> void:
	var adelante := Vector3.FORWARD.rotated(Vector3.UP, jugador.yaw)
	var derecha := adelante.cross(Vector3.UP)
	var lado: float = t["radio"] + 1.2
	rumbo = jugador.yaw
	rotation.y = rumbo
	activo = true
	visible = true
	forma.disabled = false
	rapidez = 0.0
	velocity = Vector3.ZERO
	# a la derecha, a la izquierda, adelante o atrás: el primero donde cabe; si en ninguno, donde está el personaje
	var p0 := jugador.global_position
	for d in [derecha * lado, -derecha * lado, adelante * (t["largo"] * 0.5 + 1.0), -adelante * (t["largo"] * 0.5 + 1.0), Vector3.ZERO]:
		global_position = suelo(p0 + d, p0.y + 1.5) + Vector3.UP * 0.05
		if d == Vector3.ZERO or not choca_aqui():
			break
	ultimo_suelo = global_position


func subir() -> void:
	montado = true
	jugador.vehiculo = self
	jugador.velocity = Vector3.ZERO
	jugador.forma.disabled = true
	jugador.brazo.add_excluded_object(get_rid())
	jugador.largo_a_pie = jugador.largo
	jugador.largo = t["brazo"]
	peaton_al_vehiculo()
	hud.visible = true


func bajar() -> void:
	montado = false
	hud.visible = false
	var adelante := Vector3.FORWARD.rotated(Vector3.UP, rumbo)
	var izq := Vector3.UP.cross(adelante)  # se baja por la izquierda
	var lado: float = t["radio"] + 0.7
	var p0 := global_position
	var p := p0
	for d in [izq * lado, -izq * lado, -adelante * (t["largo"] * 0.5 + 0.6), adelante * (t["largo"] * 0.5 + 0.6)]:
		p = suelo(p0 + d, p0.y + 1.5) + Vector3.UP * 0.1
		if not jugador_choca(p):
			break
	peaton_al_jugador()
	jugador.vehiculo = null
	jugador.forma.disabled = false
	jugador.brazo.remove_excluded_object(get_rid())
	jugador.brazo.position = Vector3(0, jugador.ALTO - 0.15, 0)
	jugador.largo = jugador.largo_a_pie
	jugador.global_position = p
	jugador.inicio = p
	jugador.velocity = Vector3.ZERO
	jugador.cuerpo.rotation.y = rumbo


# el peatón en la bicicleta (sentado en el asiento, pedaleando: peaton.gd sentar()); en el auto no se ve
func peaton_al_vehiculo() -> void:
	var pe: Node3D = jugador.peaton
	if tipo == "bici":
		if pe.get_parent() != asiento:
			pe.reparent(asiento, false)
		pe.transform = Transform3D.IDENTITY
		pe.visible = true
	else:
		peaton_al_jugador()
		pe.visible = false


func peaton_al_jugador() -> void:
	var pe: Node3D = jugador.peaton
	if pe.get_parent() != jugador.cuerpo:
		pe.reparent(jugador.cuerpo, false)
	pe.transform = Transform3D.IDENTITY
	pe.visible = true


# Tab con el vehículo: como jugador.gd ir()
func ir(x: float, y: float, h: float) -> void:
	llegar = Vector3(x, y, h)
	rapidez = 0.0
	velocity = Vector3.ZERO
	global_position = Vector3(x, h + 1.0, -y)


# ---------- la física ----------

func _physics_process(dt: float) -> void:
	if not activo:
		return
	if llegar != Vector3.INF:
		if mapa and not mapa.solido(llegar.x, llegar.y):
			seguir_jugador()
			return
		global_position = suelo(Vector3(llegar.x, 0, -llegar.y), llegar.z + 1.6) + Vector3.UP * 0.05
		ultimo_suelo = global_position
		llegar = Vector3.INF
	elif mapa and not mapa.solido(global_position.x, -global_position.z):
		if prueba_on:
			med["espera"] += 1
		seguir_jugador()
		return  # la tesela de abajo todavía no tiene colisión: espera

	var adelante := Vector3.FORWARD.rotated(Vector3.UP, rumbo)
	var acel := 0.0
	var fren := 0.0
	var gira := 0.0
	var fuerte := false
	var frenazo := false
	if not montado:
		frenazo = true  # estacionado: no se va cuesta abajo
	elif not jugador.quieto:
		acel = Input.get_action_strength("adelante")
		fren = Input.get_action_strength("atras")
		gira = Input.get_axis("izquierda", "derecha")
		fuerte = Input.is_action_pressed("impulso")
		frenazo = Input.is_action_pressed("saltar")

	# lo que pide la tesela de adelante: sin su colisión, frena a tiempo (a 1,5 s de lo que recorre más 10 m)
	var mira: float = absf(rapidez) * 1.5 + 10.0
	var p_mira := global_position + adelante * mira * signf(rapidez if rapidez != 0.0 else 1.0)
	var falta: bool = mapa != null and not mapa.solido(p_mira.x, -p_mira.z)
	if falta and absf(rapidez) > 2.0:
		frenazo = true
		if prueba_on:
			med["frena"] += 1

	var vmax: float = t["vmax_ruta"] if en_ruta else (t["vmax_fuerte"] if fuerte else t["vmax"])
	var a_max: float = t["acel_fuerte"] if fuerte else t["acel"]
	a_max = minf(a_max, t["potencia_fuerte" if fuerte else "potencia"] / maxf(absf(rapidez), 2.0))
	# la pendiente, del cabeceo del modelo (los rayos bajo las ruedas, suavizado: la normal del suelo salta en los bordes
	# de las capas); + subiendo
	var cuesta := g * sin(inclinar.x) if is_on_floor() else 0.0
	if frenazo:
		rapidez = move_toward(rapidez, 0.0, t["frenazo"] * dt)
	elif acel > 0.0 and rapidez < -0.3:
		rapidez = move_toward(rapidez, 0.0, t["freno"] * acel * dt)
	elif fren > 0.0 and rapidez > 0.3:
		rapidez = move_toward(rapidez, 0.0, t["freno"] * fren * dt)
	elif acel > 0.0:
		# toda la aceleración hasta el 70 % de la máxima, y luego menos hasta llegar
		rapidez += a_max * acel * clampf((vmax - rapidez) / (0.3 * vmax), 0.0, 1.0) * dt
	elif fren > 0.0:
		rapidez = move_toward(rapidez, -t["reversa"], t["acel"] * fren * dt)
	if rapidez > vmax and not frenazo:  # salió de la Ruta 5, soltó Q o va cuesta abajo: frena de a poco
		rapidez = move_toward(rapidez, vmax, (3.0 + maxf(-cuesta, 0.0)) * dt)
	# el roce y el aire: sin pedal, el auto pierde ~0,6 m/s² a 25 m/s
	if acel == 0.0 and fren == 0.0:
		rapidez = move_toward(rapidez, 0.0, (0.25 + 0.0006 * rapidez * rapidez) * dt)
	if not (frenazo and absf(rapidez) < 1.0):  # frenado y casi detenido, los frenos lo sujetan
		rapidez -= cuesta * dt

	# el volante vuelve al centro más rápido de lo que gira; con la máxima rapidez, la mitad del ángulo
	var vel_volante := 3.0 if absf(gira) > absf(volante) and signf(gira) == signf(volante) else 5.0
	volante = move_toward(volante, gira, vel_volante * dt)
	var angulo: float = volante * t["giro"] * lerpf(1.0, 0.5, clampf(absf(rapidez) / t["vmax"], 0.0, 1.0))
	var giro: float = rapidez / t["batalla"] * tan(angulo)
	var tope: float = t["lateral"] / maxf(absf(rapidez), 1.0)
	giro = clampf(giro, -tope, tope)
	rumbo -= giro * dt
	rotation.y = rumbo
	adelante = Vector3.FORWARD.rotated(Vector3.UP, rumbo)

	var antes := rapidez
	velocity.x = adelante.x * rapidez
	velocity.z = adelante.z * rapidez
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= g * dt
	floor_snap_length = 0.3 + absf(rapidez) * 0.02
	var deseo := Vector3(velocity.x, 0, velocity.z) * dt
	move_and_slide()
	var subio := false
	if is_on_wall() and t["peldano"] > 0.0:
		subio = subir_cordon(deseo, t["peldano"])
	if is_on_wall() and not subio:
		# contra un muro: queda la rapidez a lo largo de lo que deslizó
		var h := Vector3(velocity.x, 0, velocity.z)
		var queda := h.dot(adelante)
		rapidez = queda if signf(queda) == signf(rapidez) else 0.0
		rapidez = clampf(rapidez, -absf(antes), absf(antes))
	pisa = capa_del_suelo()
	en_ruta = en_r5(global_position.x, -global_position.z)
	if prueba_on:
		medir_choques(antes)
	if is_on_floor():
		ultimo_suelo = global_position
	elif global_position.y < ultimo_suelo.y - 60:  # se cayó de la maqueta: vuelve al último suelo
		global_position = ultimo_suelo + Vector3.UP * 0.5
		velocity = Vector3.ZERO
		rapidez = 0.0
	seguir_jugador()


# como jugador.gd subir_cordon(): un borde más alto que lo que la cápsula sube sola
func subir_cordon(paso: Vector3, alto: float) -> bool:
	if not is_on_floor() or paso.length() < 0.001:
		return false
	paso = paso.normalized() * max(paso.length(), 0.05)
	var sube := Vector3.UP * alto
	if test_move(global_transform, sube):
		return false
	var arriba := global_transform.translated(sube)
	if test_move(arriba, paso):
		return false
	global_position += sube + paso
	return true


# la capa de lo que pisa, de un rayo bajo el centro: el padre del cuerpo de colisión de mapa.gd se llama como la capa
# ("" si no hay suelo a menos de 1,5 m; las colisiones del deslizamiento no sirven: detenido, move_and_slide no las da)
func capa_del_suelo() -> String:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, global_position + Vector3.DOWN * 1.5)
	q.exclude = [get_rid(), jugador.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return nombre_de(r.collider) if r else ""


static func nombre_de(o: Object) -> String:
	var n := o as Node
	if n == null:
		return "?"
	return String(n.get_parent().name) if n.name == &"colision" else String(n.name)


# el personaje va con el vehículo (la cámara es la suya)
func seguir_jugador() -> void:
	if montado:
		jugador.global_position = global_position
		jugador.velocity = velocity


# ---------- lo que se ve ----------

func _process(dt: float) -> void:
	if not activo:
		return
	fase += rapidez / radio_rueda * dt
	for r in ruedas:
		r.rotation.x = -fase
	for d in direccion:
		d.rotation.y = -volante * t["giro"] * lerpf(1.0, 0.5, clampf(absf(rapidez) / t["vmax"], 0.0, 1.0))
	apoyar(dt)
	if tipo == "bici":
		# una vuelta de pedal cada ~4,3 m (un cambio medio); sin pedalear, la biela queda donde estaba
		if montado and Input.get_action_strength("adelante") > 0.0:
			fase_biela += rapidez / 4.3 * TAU * dt
		biela.rotation.x = -fase_biela
		if montado:
			pedalear(dt)
	if montado:
		hud.text = "%d km/h · %s%s" % [roundi(absf(rapidez) * 3.6), t["nombre"], " · Ruta 5" if en_ruta and tipo == "auto" else ""]


# el modelo sobre el suelo bajo sus ruedas: cabeceo y alabeo de cuatro rayos (dos en la bicicleta), y la bicicleta
# inclinada hacia la curva (lo que pide la aceleración lateral)
func apoyar(dt: float) -> void:
	var b: float = t["batalla"] / 2.0
	var tr := 0.75 if tipo == "auto" else 0.0
	var h := {}
	for k in [["f", 0.0, -b], ["t", 0.0, b], ["i", -tr, 0.0], ["d", tr, 0.0]]:
		if tipo == "bici" and k[1] == 0.0 and k[2] == 0.0:
			continue
		h[k[0]] = altura_en(to_global(Vector3(k[1], 0, k[2])))
	var y0 := global_position.y
	var hf: float = h.get("f", y0)
	var ht: float = h.get("t", y0)
	var cab := atan2(hf - ht, t["batalla"])
	var alab := 0.0
	var alto := (hf + ht) / 2.0 - y0
	if tipo == "auto":
		var hi: float = h.get("i", y0)
		var hd: float = h.get("d", y0)
		alab = atan2(hi - hd, 2.0 * tr)
		alto = (hf + ht + hi + hd) / 4.0 - y0
	else:
		var giro: float = rapidez / t["batalla"] * tan(volante * t["giro"])
		alab = clampf(atan(rapidez * giro / g), -0.6, 0.6)
	alto = clampf(alto, -1.0, 1.0)
	var k := 1.0 - exp(-12.0 * dt)
	inclinar = inclinar.lerp(Vector3(cab, alab, alto), k)
	modelo.position.y = inclinar.z
	modelo.rotation = Vector3(inclinar.x, 0, inclinar.y)
	# la cápsula, con el cabeceo del modelo (en torno a su centro, así su punto más bajo no se mueve): derecha en una
	# pendiente de 19°, la punta delantera tocaba el borde de una capa plana (unos cm sobre el terreno) a 49° y lo
	# tomaba por un muro (el auto no subía el Cerro La Virgen)
	forma.rotation.x = PI / 2 + inclinar.x
	# y lo que cuenta como suelo, medido desde la pendiente en que va: un borde de 14 cm en una subida de 19° se ve a 49°
	floor_max_angle = deg_to_rad(PISO) + minf(absf(inclinar.x), deg_to_rad(30.0))


# la altura del suelo bajo un punto (sin contar el vehículo ni el personaje), o la del vehículo si no hay
func altura_en(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.2, p + Vector3.DOWN * 1.5)
	q.exclude = [get_rid(), jugador.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return r.position.y if r else global_position.y


# las piernas en los pedales y las manos en el manubrio (peaton.gd sentar(), en el marco de la cadera: adelante, arriba)
func pedalear(dt: float) -> void:
	var pe: Node3D = jugador.peaton
	var pies := []
	for i in 2:
		var a := -fase_biela + PI * i
		var pedal := BIELA_C + Vector2(cos(a), sin(a)) * BIELA_R
		pies.append(pedal + Vector2(-0.03, 0.07) - CADERA)
	var fuerte := Input.is_action_pressed("impulso") and rapidez > 1.0
	pe.sentar(dt, pies, 0.62 if not fuerte else 0.75, 1.42, 0.35)


# ---------- los modelos ----------

# en el marco de la bicicleta (adelante, arriba), m: el eje de los pedales y la cadera del ciclista
const BIELA_C := Vector2(-0.02, 0.29)
const BIELA_R := 0.17
const CADERA := Vector2(-0.24, 1.02)


func armar(nuevo: String) -> void:
	tipo = nuevo
	t = TIPOS[tipo]
	for c in modelo.get_children():
		if c == asiento:
			continue
		c.queue_free()
	ruedas.clear()
	direccion.clear()
	var cap := CapsuleShape3D.new()
	cap.radius = t["radio"]
	cap.height = t["largo"]
	forma.shape = cap
	forma.rotation.x = PI / 2  # acostada, a lo largo del vehículo
	forma.position.y = t["radio"]
	if tipo == "bici":
		bicicleta()
	else:
		auto()


static func material(rugoso: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rugoso
	m.metallic = metal
	return m


# una pieza del modelo: las capas de m con un material sin dibujo (el de patron.gdshader está en coordenadas del mundo y
# se deslizaría sobre algo que se mueve, como las ventanas de la página: CLAUDE.md, «Lo que se mueve no usa winMat()»)
func pieza(padre: Node3D, m: Malla, pos := Vector3.ZERO) -> Node3D:
	var mats := {"": material(0.5), "pintura": material(0.35, 0.25), "metal": material(0.35, 0.6), "goma": material(0.9),
		"vidrio": Mat.patron("vidrio")}
	var am := ArrayMesh.new()
	for nombre in m.capas:
		var c: Array = m.capas[nombre]
		if c[0].is_empty():
			continue
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = c[0]
		a[Mesh.ARRAY_NORMAL] = c[1]
		a[Mesh.ARRAY_COLOR] = c[2]
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		am.surface_set_material(am.get_surface_count() - 1, mats.get(nombre, mats[""]))
	var mi := MeshInstance3D.new()
	mi.mesh = am
	var n := Node3D.new()
	n.position = pos
	n.add_child(mi)
	padre.add_child(n)
	return n


# una rueda de radio r y ancho w centrada en su eje (X), con n rayos: neumático, llanta y tapa
func rueda(r: float, w: float, llanta: float, n_rayos: int, gruesa: bool) -> Malla:
	var m := Malla.new()
	var f := Malla.grilla()
	var k := 18
	var c := Malla.ngon(0, 0, r, k)
	var ci := Malla.ngon(0, 0, r * llanta, k)
	var negro := Color(0.06, 0.06, 0.06)
	var gris := Color(0.6, 0.61, 0.63)
	for i in k:
		var a := c[i]
		var b := c[(i + 1) % k]
		var nn := ((a + b) / 2).normalized()
		m.cara([f.V(-w, a.x, a.y), f.V(w, a.x, a.y), f.V(w, b.x, b.y), f.V(-w, b.x, b.y)], negro, "goma", f.N(0, nn.x, nn.y))
		for s in [-1.0, 1.0]:  # los flancos: un anillo entre el neumático y la llanta
			var ai := ci[i]
			var bi := ci[(i + 1) % k]
			m.cara([f.V(s * w, a.x, a.y), f.V(s * w, b.x, b.y), f.V(s * w, bi.x, bi.y), f.V(s * w, ai.x, ai.y)], negro, "goma", f.N(s, 0))
	if gruesa:  # la llanta del auto: un disco
		for s in [-1.0, 1.0]:
			var q := []
			for a in ci:
				q.append(f.V(s * (w + 0.005), a.x, a.y))
			m.cara(q, gris, "metal", f.N(s, 0))
	else:  # la de la bicicleta: aro y rayos
		for i in k:
			var a := ci[i]
			var b := ci[(i + 1) % k]
			var nn := ((a + b) / 2).normalized()
			m.cara([f.V(-w * 0.8, a.x, a.y), f.V(w * 0.8, a.x, a.y), f.V(w * 0.8, b.x, b.y), f.V(-w * 0.8, b.x, b.y)], gris, "metal", f.N(0, -nn.x, -nn.y))
		for i in n_rayos:
			var a := TAU * i / n_rayos
			var s := 1.0 if i % 2 == 0 else -1.0
			m.tubo(Vector3(s * 0.03, 0, 0), Vector3(0, sin(a), -cos(a)) * r * llanta, 0.004, 0.004, 4, gris, gris)
		m.tubo(Vector3(-0.05, 0, 0), Vector3(0.05, 0, 0), 0.02, 0.02, 8, gris, gris)
	return m


# una bicicleta urbana de 1,75 m (ruedas de 0,68 m, batalla 1,05): cuadro de diamante, horquilla y manubrio que giran,
# pedales que giran con la rueda
func bicicleta() -> void:
	radio_rueda = 0.34
	var b: float = t["batalla"] / 2.0
	var col := Color(0.12, 0.42, 0.52)
	var oscuro := Color(0.1, 0.1, 0.11)
	var cromo := Color(0.7, 0.71, 0.72)
	# (adelante, arriba) -> Vector3 del modelo
	var P := func(a: float, h: float, x := 0.0) -> Vector3: return Vector3(x, h, -a)
	var cuadro := Malla.new()
	var tras: Vector3 = P.call(-b, radio_rueda)
	var pedal: Vector3 = P.call(BIELA_C.x, BIELA_C.y)
	var sillin: Vector3 = P.call(-0.2, 0.86)
	var cabeza_a: Vector3 = P.call(0.41, 0.93)
	var cabeza_b: Vector3 = P.call(0.45, 0.76)
	cuadro.tubo(pedal, sillin, 0.018, 0.018, 8, col, col)  # tubo del asiento
	cuadro.tubo(sillin, cabeza_a, 0.017, 0.017, 8, col, col)  # tubo superior
	cuadro.tubo(pedal, cabeza_b, 0.022, 0.022, 8, col, col)  # tubo inferior
	cuadro.tubo(cabeza_b, cabeza_a, 0.024, 0.024, 8, col, col)  # tubo de dirección
	for x in [-0.055, 0.055]:
		cuadro.tubo(pedal + Vector3(x * 0.6, 0, 0), tras + Vector3(x, 0, 0), 0.011, 0.01, 6, col, col)  # vainas
		cuadro.tubo(sillin + Vector3(x * 0.3, 0, 0), tras + Vector3(x, 0, 0), 0.01, 0.01, 6, col, col)  # tirantes
	cuadro.tubo(sillin, P.call(-0.24, 0.97), 0.013, 0.013, 6, cromo, cromo)  # tija
	cuadro.bloque(P.call(-0.25, 0.985), Vector3(0.13, 0.05, 0.26), oscuro)  # sillín
	cuadro.bloque(P.call(-0.17, 0.985), Vector3(0.06, 0.045, 0.1), oscuro)
	# el guardabarros de atrás y la parrilla
	cuadro.tubo(P.call(-b - 0.05, 0.72), P.call(-b + 0.25, 0.7), 0.035, 0.035, 6, oscuro, oscuro)
	cuadro.tubo(pedal, pedal + Vector3(0.03, 0, 0), 0.05, 0.05, 10, cromo, cromo)  # el plato
	pieza(modelo, cuadro)
	# la dirección: horquilla, rueda de adelante y manubrio, en torno al eje del tubo de dirección (vertical, simplificado)
	var piv := Node3D.new()
	piv.position = P.call(0.45, 0.0)
	modelo.add_child(piv)
	direccion.append(piv)
	var dir_m := Malla.new()
	var o := Vector3(0, 0, 0.45)  # del modelo al pivote: -P(0.45)
	for x in [-0.045, 0.045]:
		dir_m.tubo(cabeza_b + o + Vector3(x * 0.5, 0, 0), P.call(b, radio_rueda, x) + o, 0.012, 0.01, 6, col, col)
	dir_m.tubo(cabeza_a + o, P.call(0.39, 1.06) + o, 0.014, 0.014, 6, cromo, cromo)  # potencia
	var manubrio: Vector3 = P.call(0.37, 1.06) + o
	dir_m.tubo(manubrio + Vector3(-0.29, 0, 0.04), manubrio + Vector3(0.29, 0, 0.04), 0.012, 0.012, 6, cromo, cromo)
	for x in [-1.0, 1.0]:
		dir_m.tubo(manubrio + Vector3(x * 0.2, 0, 0.04), manubrio + Vector3(x * 0.29, 0, 0.04), 0.018, 0.018, 6, oscuro, oscuro)
	dir_m.tubo(P.call(b - 0.05, 0.72) + o, P.call(b + 0.2, 0.62) + o, 0.035, 0.035, 6, oscuro, oscuro)
	dir_m.bloque(P.call(0.47, 0.95) + o, Vector3(0.08, 0.07, 0.04), Color(0.95, 0.93, 0.8))  # el foco
	pieza(piv, dir_m)
	var rd := pieza(piv, rueda(radio_rueda, 0.017, 0.88, 16, false), P.call(b, radio_rueda) + o)
	ruedas.append(rd)
	ruedas.append(pieza(modelo, rueda(radio_rueda, 0.017, 0.88, 16, false), tras))
	# los pedales: dos bielas y sus pedales, en torno al eje
	var bm := Malla.new()
	for s in [-1.0, 1.0]:
		var x: float = s * 0.09
		var punta := Vector3(x, s * BIELA_R, 0)  # la derecha arriba, la izquierda abajo (en el marco de la biela)
		bm.tubo(Vector3(x, 0, 0), punta, 0.012, 0.012, 6, cromo, cromo)
		bm.bloque(punta + Vector3(s * 0.05, 0, 0), Vector3(0.09, 0.025, 0.07), oscuro)
	biela = pieza(modelo, bm, pedal)
	# el ciclista: peaton.gd con la cadera sobre el sillín
	asiento.position = P.call(CADERA.x, CADERA.y - 0.93)
	if asiento.get_parent() == null:
		modelo.add_child(asiento)


# el sedán de modelos/entorno/auto.gd (el de calles.gd y autos.gd: largo 4,64 m, ancho 1,72), rojo, sin sus ruedas: las
# de aquí giran con la rapidez y las de adelante con el volante
func auto() -> void:
	var tipo_auto := Auto.SEDAN
	radio_rueda = Auto.RUEDA_R[tipo_auto]
	var ancho: float = Auto.ANCHO[tipo_auto]
	var vr: float = Auto.RUEDA_V[tipo_auto]
	var m := Malla.new()
	var f := Malla.grilla()
	Auto.modelo(m, f, tipo_auto, Color(0.6, 0.08, 0.07), null, false)
	# el piso: sin él, desde arriba de una pendiente se ve el cielo por debajo
	var cb: Array = Auto.CUERPOS[tipo_auto][0]
	m.caja(f, -ancho + 0.02, cb[0][0] + 0.1, ancho - 0.02, cb[1][0] - 0.1, cb[0][1] - 0.02, cb[0][1], Auto.GRIS, "pintura")
	pieza(modelo, m)
	for sv in [1.0, -1.0]:
		for su in [-1.0, 1.0]:
			var pos := Vector3(su * (ancho - 0.105), radio_rueda, -sv * vr)
			if sv > 0:  # las de adelante giran con el volante
				var piv := Node3D.new()
				piv.position = pos
				modelo.add_child(piv)
				direccion.append(piv)
				ruedas.append(pieza(piv, rueda(radio_rueda, 0.115, 0.62, 0, true)))
			else:
				ruedas.append(pieza(modelo, rueda(radio_rueda, 0.115, 0.62, 0, true), pos))


# ---------- ayudas ----------

# las dos calzadas de data/ruta5.json («c»: p, delta de enteros en decímetros de grilla, como dec() de la página) en
# celdas, para en_r5(); sin el archivo, ninguna (el auto no pasa de vmax)
func cargar_r5() -> void:
	var f := "res://datos/ruta5.json"
	if not FileAccess.file_exists(f):
		push_warning("vehiculo.gd: falta juego/datos/ruta5.json (make juego): el auto no sabe dónde está la Ruta 5")
		return
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
	if not (j is Dictionary):
		return
	for c in j.get("c", []):
		var p: Array = c["p"]
		var x := 0.0
		var y := 0.0
		var prev := Vector2.INF
		for i in range(0, p.size(), 2):
			x += p[i]
			y += p[i + 1]
			var q := Vector2(x, y) / 10.0
			if prev != Vector2.INF:
				var k0 := Vector2i(floori(minf(prev.x, q.x) / R5_CELDA - 0.11), floori(minf(prev.y, q.y) / R5_CELDA - 0.11))
				var k1 := Vector2i(floori(maxf(prev.x, q.x) / R5_CELDA + 0.11), floori(maxf(prev.y, q.y) / R5_CELDA + 0.11))
				for ky in range(k0.y, k1.y + 1):
					for kx in range(k0.x, k1.x + 1):
						var k := Vector2i(kx, ky)
						if not r5.has(k):
							r5[k] = []
						r5[k].append([prev, q])
			prev = q


# si (x, y) de grilla cae en una calzada de la Ruta 5: de 5,5 m a la izquierda a 10,5 m a la derecha de su línea
# (la calzada va de 4,5 a 6 m, o 9,5 con tercera pista: R5R de la página, más un metro de berma)
func en_r5(x: float, y: float) -> bool:
	var p := Vector2(x, y)
	for s in r5.get(Vector2i(floori(x / R5_CELDA), floori(y / R5_CELDA)), []):
		var a: Vector2 = s[0]
		var d: Vector2 = s[1] - a
		var l2 := d.length_squared()
		if l2 < 1e-6:
			continue
		var u := (p - a).dot(d) / l2
		if u < 0.0 or u > 1.0:
			continue
		var lado := (p - a).dot(Vector2(d.y, -d.x)) / sqrt(l2)  # + a la derecha del sentido de la calzada
		if lado > -5.5 and lado < 10.5:
			return true
	return false

# el suelo bajo p: un rayo desde `desde` (altura) contra la colisión, sin el vehículo ni el personaje; si no da con
# nada, desde arriba
func suelo(p: Vector3, desde: float) -> Vector3:
	var esp := get_world_3d().direct_space_state
	for d in [desde, 1500.0]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, d, p.z), Vector3(p.x, -500.0, p.z))
		q.exclude = [get_rid(), jugador.get_rid()]
		var r := esp.intersect_ray(q)
		if r:
			return r.position
	return p


# si el vehículo, donde está, se mete en algo
func choca_aqui() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = forma.shape
	q.transform = global_transform * forma.transform
	q.transform.origin += Vector3.UP * 0.1
	q.exclude = [get_rid(), jugador.get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# si el personaje, en p, se mete en algo
func jugador_choca(p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = jugador.forma.shape
	q.transform = Transform3D(Basis(), p + jugador.forma.position + Vector3.UP * 0.05)
	q.exclude = [get_rid(), jugador.get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# ---------- la cámara (jugador.gd la llama mientras va montado) ----------

# detrás del vehículo y más alta que la del peatón; vuelve detrás sola si el mouse lleva SEGUIR s quieto. Con la rueda
# en 0, la primera persona: el ojo del ciclista o del conductor (a la izquierda, como en Chile)
func camara(dt: float) -> void:
	var j := jugador
	var primera: bool = j.largo < 0.6
	j.brazo.position = Basis(Vector3.UP, rumbo) * t["ojo"] if primera else Vector3(0, t["alto"], 0)
	if j.t_mouse > SEGUIR and absf(rapidez) > 1.5:
		var detras := rumbo if rapidez > 0.0 else rumbo + PI
		var k := 1.0 - exp(-2.5 * dt)
		j.yaw = lerp_angle(j.yaw, detras, k)
		j.pitch = lerpf(j.pitch, -0.22 if not primera else -0.08, k)
	j.brazo.spring_length = lerpf(j.brazo.spring_length, j.largo, 0.2)
	if tipo == "bici":
		j.peaton.visible = not primera


# ---------- --conducir ----------

# --vehiculo bici|auto (sube al comenzar) --conducir N (acelera N s) [--volante v: -1 izquierda … 1 derecha] [--fuerte]
# [--bajar]: imprime dónde terminó, contra qué chocó, cuánto esperó la colisión y los cuadros más lentos, y con --bajar
# se baja y dice dónde quedó el personaje
func prueba() -> void:
	await mapa.esperar()
	med = {"espera": 0, "frena": 0, "choques": [], "dt": [], "vmax": 0.0, "m": 0.0, "leidas": mapa.stats["leidas"], "pisa": {}}
	prueba_on = true
	var s := Args.num("--conducir", 5.0, 0.0, 600.0)
	var v := Args.num("--volante", 0.0, -1.0, 1.0)
	Input.action_press("adelante")
	if v > 0.0:
		Input.action_press("derecha", v)
	elif v < 0.0:
		Input.action_press("izquierda", -v)
	if Args.has("--fuerte"):
		Input.action_press("impulso")
	var t0 := Time.get_ticks_msec()
	var antes := global_position
	var t1 := Time.get_ticks_usec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame
		var ahora := Time.get_ticks_usec()
		med["dt"].append((ahora - t1) / 1000.0)
		t1 = ahora
		med["vmax"] = maxf(med["vmax"], absf(rapidez))
		med["m"] += Vector2(global_position.x - antes.x, global_position.z - antes.z).length()
		med["pisa"][pisa] = med["pisa"].get(pisa, 0) + 1
		antes = global_position
	for a in ["adelante", "derecha", "izquierda", "impulso"]:
		Input.action_release(a)
	prueba_on = false
	var dts: Array = med["dt"]
	dts.sort()
	var lentos := dts.filter(func(x): return x > 33.4).size()
	var media := 0.0
	for x in dts:
		media += x
	media /= maxf(dts.size(), 1)
	var pisadas := []
	for k in med["pisa"]:
		pisadas.append("%s %d" % [k if k != "" else "(aire)", med["pisa"][k]])
	print("vehiculo.gd: %s, %.0f s: %.0f m (máx %.1f m/s, ahora %.1f), en x %.1f, y %.1f, altura %.2f; rumbo %.0f°" % [
		t["nombre"], s, med["m"], med["vmax"], rapidez, global_position.x, -global_position.z, global_position.y, rad_to_deg(rumbo)])
	print("vehiculo.gd: choques: %s" % (", ".join(med["choques"]) if not med["choques"].is_empty() else "ninguno"))
	print("vehiculo.gd: esperando colisión %d cuadros de física, frenando por la de adelante %d; %d teselas leídas" % [
		med["espera"], med["frena"], mapa.stats["leidas"] - med["leidas"]])
	print("vehiculo.gd: cuadros %d, media %.1f ms, mediana %.1f, p99 %.1f, peor %.1f, %d de más de 33 ms; pisa: %s" % [
		dts.size(), media, dts[dts.size() / 2], dts[int(dts.size() * 0.99)], dts[-1], lentos, ", ".join(pisadas)])
	if not Args.has("--bajar"):
		return
	# --bajar: se baja; dónde queda el personaje, y si cabe ahí
	bajar()
	await get_tree().physics_frame
	var jp := jugador.global_position
	print("vehiculo.gd: baja en x %.1f, y %.1f, altura %.2f (el vehículo, a %.1f m), %s" % [jp.x, -jp.z, jp.y,
		jp.distance_to(global_position), "libre" if not jugador_choca(jp) else "DENTRO DE ALGO"])


# los choques de este cuadro: contra qué y a qué rapidez (los que quitan más de 2 m/s)
func medir_choques(antes: float) -> void:
	if not is_on_wall():
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().angle_to(Vector3.UP) > floor_max_angle + 0.01 and absf(antes) - absf(rapidez) > 2.0:
			var p := c.get_position()
			med["choques"].append("«%s» a %.1f m/s en (%.0f, %.0f)" % [nombre_de(c.get_collider()), absf(antes), p.x, -p.z])
			return


func _unhandled_input(e: InputEvent) -> void:
	if jugador == null or jugador.quieto or e.is_echo():
		return
	if e.is_action_pressed("vehiculo"):
		usar()
	elif e.is_action_pressed("cambiar"):
		cambiar()
