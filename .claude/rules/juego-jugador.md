---
paths:
  - "juego/jugador.gd"
  - "juego/vehiculo.gd"
  - "juego/vida.gd"
  - "juego/armas.gd"
  - "juego/blancos.gd"
  - "juego/menu.gd"
  - "juego/peaton.gd"
  - "juego/red.gd"
  - "juego/modelos/entorno/armas.gd"
---

# El personaje del juego (vida, armas, jetpack, menú)

Lo que hace el personaje en el juego: bajarse de un vehículo, la vida, las armas y los muñecos de práctica, el jetpack y el menú de Esc, con sus pruebas sin teclado. El resto del juego (el mapa por teselas, los vehículos, la exportación) está en `juego.md`, que se carga con todo `juego/`.

## Comandos

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path juego -- --caer 30 [--desde 568.5,-245 --dano 70 --vehiculo bici --pausa 1.2 --png shots/x.png]   # la vida (jugador.gd, vida.gd prueba()): --caer m lo deja caer desde m m (negativo: bajo el suelo, fuera de la maqueta) e imprime la rapidez, el daño y, si muere, dónde reaparece (la Plaza de Armas); --dano n le quita n e imprime cómo se recupera (en los carritos de completos de 5 y 6 Oriente, rápido); --pausa s congela para la captura
/Applications/Godot.app/Contents/MacOS/Godot --headless --path juego -- --girar 58 --mirar -3 --arma pistola|rifle|cuchillo [--apuntar] --disparar 6 [--pausa 0 --orbitar 70 --png shots/x.png]   # las armas sin teclado (armas.gd prueba()): dispara n veces a lo que hay bajo la mira (desde INICIO, --girar 58 apunta al muñeco más cercano de blancos.gd) e imprime cada impacto, el daño y la munición; --pausa s congela s de juego después del último tiro (0: el fogonazo y la trazadora) y --orbitar G gira la cámara alrededor del personaje para ver la pose de lado
/Applications/Godot.app/Contents/MacOS/Godot --headless --path juego -- --vehiculo jetpack --volar 20 [--fuerte --bajar]   # el jetpack despega, sube (35 % de N s), avanza (45 %), baja con C y aterriza flotando: altura máxima, recorrido, combustible, rapidez de cada aterrizaje (DURO: daño) y cuadros esperando la colisión (vehiculo.gd prueba_vuelo()); con --pausa s y --png (tools/godot_oculto.sh), una captura en vuelo
/Applications/Godot.app/Contents/MacOS/Godot --headless --path juego -- --menu-prueba [--servidor]   # el menú de Esc (menu.gd) sin teclado: aprieta Esc, Tab y M por Input.parse_input_event e imprime qué queda abierto, si está en pausa y si el personaje quedó quieto (con --servidor, en una partida en red, sin pausa); --menu --png shots/x.png (tools/godot_oculto.sh): una captura con el menú abierto
```

## Trampas

- **Bajarse del vehículo y el servidor de física.** `vehiculo.gd bajar()` mueve al personaje al costado y le enciende la cápsula, pero un `CharacterBody3D` (cinemático) llega a su lugar nuevo en el servidor de física recién en el paso siguiente; ni `force_update_transform()` ni `PhysicsServer3D.body_set_state()` lo adelantan. En ese cuadro el vehículo choca con la cápsula todavía en el asiento, sale 1 m hacia arriba y en el siguiente se va con ella, sobre la cabeza del personaje (la bicicleta detenida, en cada bajada). `jugador.gd bajado()` apaga la cápsula dos cuadros de física después de bajar (con E o al morir). Cualquier cosa que teletransporte un cuerpo y le encienda la colisión en el mismo cuadro tiene el mismo problema.
- **El jetpack del juego.** Puesto, el peatón va en el `asiento` del vehículo y la mochila en su `torso`; la pose de vuelo (`vehiculo.gd pose_vuelo()`, que `red.gd` usa también para los otros jugadores) escribe las articulaciones de `peaton.gd` desde afuera, como `sentar()`: si cambian los nombres de `muslo`, `codo`, etc., cambie `pose_vuelo()`. La altura y el techo (180 m) son sobre lo que tiene debajo (un rayo), no sobre la plaza, y la regla de «cayó 60 m bajo el último suelo» de los vehículos no se aplica (volando desde el Cerro La Virgen lo devolvería arriba): si el rayo no da con nada donde la colisión ya está, atravesó el suelo y vuelve arriba. Un viaje con Tab pone `en_aire` en falso, para que llegar al suelo bajando con C no cuente como aterrizaje duro. En la red, `red.gd estado_propio()` manda «en el suelo» desde `en_aire`, porque mientras lo lleva `vehiculo.gd` el `is_on_floor()` del personaje no cambia.
- **Las armas del juego.** Un `.gd` suelto en `juego/modelos/` es un modelo del mapa: `main.gd modelos()` instancia cada uno y lo agrega a la escena; las piezas que comparten otros scripts van en una subcarpeta (`modelos/entorno/auto.gd`, `modelos/entorno/armas.gd`). Un `Sprite3D` o `QuadMesh` con `billboard` ignora la escala del nodo sin `billboard_keep_scale = true` (el fogonazo y las partículas salen de 1 m). Lo que dura menos que un cuadro puede no verse nunca: un efecto que nace en `_physics_process` recibe en el `_process` del mismo cuadro un delta calculado antes (~50 ms en Xvfb con la GPU compartida), así que `armas.gd` deja correr el tiempo de cada efecto recién desde el cuadro siguiente al primero dibujado. Con `Engine.time_scale = 0` (`--pausa`) el resto de los pasos de física de ese cuadro corren igual: `armas.gd` salta su `_physics_process` cuando el delta es 0. Lo golpeado recibe el daño si su cuerpo o un ancestro tiene `recibir_dano(cantidad, punto, desde)`; si expone `vida`, la mira marca cuando cae, y si expone `polvo` (Color), ese es el color de lo que salta. `Input.action_press()` (las pruebas sin teclado) cuenta como `just_pressed` recién en el cuadro de física siguiente: hay que dejar la acción apretada hasta que pase el efecto.
