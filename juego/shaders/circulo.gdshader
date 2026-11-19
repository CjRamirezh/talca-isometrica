// El recorte redondo del mapa en miniatura (plano.gd): lo que se dibuja fuera del círculo no se pinta. Más barato que
// clip_children, que dibuja los hijos en un búfer aparte en cada cuadro (~0,08 ms). La posición se compara en las
// coordenadas del lienzo (MODEL_MATRIX: de las del nodo a las de la CanvasLayer), no en las de la ventana.
shader_type canvas_item;

uniform vec2 centro;  // en el lienzo, px
uniform float radio;
varying vec2 lienzo;

void vertex() {
	lienzo = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (distance(lienzo, centro) > radio) {
		discard;
	}
}
