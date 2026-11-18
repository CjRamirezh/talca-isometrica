# El personaje: una cápsula de 1,75 m (la colisión; lo que se ve es peaton.gd, animado según la velocidad) con una cámara en tercera persona sobre un brazo (SpringArm3D) que se acorta
# cuando un muro se interpone. La rueda lo acorta hasta 0: primera persona, sin cuerpo a la vista.
extends CharacterBody3D

const CAMINAR := 8.0  # m/s (de verdad, ~1,4: se siente lento en una caja de 400 m)
const CORRER := 18.0
const SALTO := 4.5
const ALTO := 1.75
const RADIO := 0.3
const SENS := 0.004
const PELDANO := 0.4  # m: lo más alto que sube sin saltar (soleras, el borde de la plaza)

var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var yaw := 0.0  # 0: mirando al norte (-Z)
var pitch := -0.3
var largo := 5.0
var inicio := Vector3.ZERO
var mouse := true  # falso en las pruebas (--png): el mouse real no mueve la cámara
var brazo := SpringArm3D.new()
var cam := Camera3D.new()
var cuerpo := Node3D.new()
var pose := -1.0
var peaton: Node3D = preload("res://peaton.gd").new()  # el cuerpo que se ve (peaton.gd)
var mapa: Node3D  # mapa.gd: mientras la colisión bajo el personaje no está, no cae
var quieto := false  # viaje.gd: con la lista de lugares abierta, las teclas no lo mueven
var llegar := Vector3.INF  # ir(): el punto de grilla (x, y, altura del lugar) donde aparece cuando su tesela esté lista


func _ready() -> void:
	var forma := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIO
	cap.height = ALTO
	forma.shape = cap
	forma.position.y = ALTO / 2
	add_child(forma)

	cuerpo.add_child(peaton)
	add_child(cuerpo)

	brazo.position.y = ALTO - 0.15
	brazo.margin = 0.2
	brazo.add_excluded_object(get_rid())
	add_child(brazo)
	brazo.add_child(cam)
	cam.near = 0.05
	cam.far = 3000
	cam.fov = 70
	cam.current = true

	floor_snap_length = PELDANO + 0.05
	floor_max_angle = deg_to_rad(50)
	pose = preload("res://args.gd").num("--pose", pose, 0.0, 20.0)
	if mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(e: InputEvent) -> void:
	if not mouse:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * SENS
		pitch = clamp(pitch - e.relative.y * SENS, -1.45, 1.2)
	elif e is InputEventMouseButton and e.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			largo = max(0.0, largo - 1.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			largo = min(20.0, largo + 1.0)
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# aparece en el punto (x, y) de grilla, cuya altura del suelo es h (el «h» de los lugares de mapa/indice.json),
# cuando mapa.gd tenga ahí su colisión
func ir(x: float, y: float, h: float) -> void:
	llegar = Vector3(x, y, h)
	velocity = Vector3.ZERO
	global_position = Vector3(x, h + 1.0, -y)


func _physics_process(dt: float) -> void:
	if llegar != Vector3.INF:
		if mapa and not mapa.solido(llegar.x, llegar.y):
			return
		global_position = suelo_en(llegar) + Vector3.UP * 0.1
		inicio = global_position
		llegar = Vector3.INF
	elif mapa and not mapa.solido(global_position.x, -global_position.z):
		return  # la tesela de adelante todavía no tiene colisión: espera
	if not is_on_floor():
		velocity.y -= g * dt
	elif Input.is_action_pressed("saltar") and not quieto:
		velocity.y = SALTO

	var v := Vector2.ZERO if quieto else Input.get_vector("izquierda", "derecha", "adelante", "atras")
	var dir := Vector3(v.x, 0, v.y).rotated(Vector3.UP, yaw)
	var rapidez := CORRER if Input.is_action_pressed("correr") else CAMINAR
	var k := 1.0 - exp(-12.0 * dt)  # arranca y frena en ~0,2 s
	velocity.x = lerp(velocity.x, dir.x * rapidez, k)
	velocity.z = lerp(velocity.z, dir.z * rapidez, k)
	if dir.length() > 0.01:
		cuerpo.rotation.y = lerp_angle(cuerpo.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-10.0 * dt))
	var deseo := Vector3(velocity.x, 0, velocity.z) * dt  # antes de que el choque lo anule
	move_and_slide()
	subir_cordon(deseo)
	if is_on_floor():
		inicio = global_position
	elif global_position.y < inicio.y - 60:  # se cayó de la maqueta: vuelve al último suelo
		global_position = inicio + Vector3.UP * 0.5
		velocity = Vector3.ZERO


# el suelo en el punto de un lugar: un rayo desde poco más arriba del suelo (h), para no quedar en un techo; si no da
# con nada, desde arriba
func suelo_en(p: Vector3) -> Vector3:
	var esp := get_world_3d().direct_space_state
	for desde in [p.z + 1.6, 1500.0]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, desde, -p.y), Vector3(p.x, p.z - 30.0, -p.y))
		q.exclude = [get_rid()]
		var r := esp.intersect_ray(q)
		if r:
			return r.position
	return Vector3(p.x, p.z, -p.y)


# Las soleras y los peldaños bajos (hasta PELDANO): CharacterBody3D no sube escalones solo. Si choca un muro al
# caminar, prueba el mismo paso PELDANO más arriba y, si cabe, avanza ahí; el ajuste al suelo (floor_snap_length) lo
# baja en el cuadro siguiente.
func subir_cordon(paso: Vector3) -> void:
	if not is_on_floor() or not is_on_wall() or paso.length() < 0.001:
		return
	paso = paso.normalized() * max(paso.length(), 0.05)
	var sube := Vector3.UP * PELDANO
	if test_move(global_transform, sube):  # un techo encima
		return
	var arriba := global_transform.translated(sube)
	if test_move(arriba, paso):
		return
	global_position += sube + paso


func _process(dt: float) -> void:
	var v := Vector2(velocity.x, velocity.z).length()
	if pose >= 0.0:  # --pose R: anima como a R m/s sin moverse (capturas del peatón)
		v = pose
	peaton.animar(dt, v, is_on_floor())
	largo_actual()
	brazo.rotation = Vector3(pitch, yaw, 0)


func largo_actual() -> void:
	brazo.spring_length = lerp(brazo.spring_length, largo, 0.2)
	cuerpo.visible = brazo.get_hit_length() > 0.6
