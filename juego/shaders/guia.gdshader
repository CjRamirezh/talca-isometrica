// La cinta del camino a un marcador (ruta.gd): flechas (chevrones) que avanzan por el suelo hacia el marcador, con
// los bordes marcados. UV.x son los metros a lo largo del camino (desde su comienzo, para que las flechas no salten
// cuando la cinta se rehace) y UV.y va de un borde (0) al otro (1); el alfa del color de los vértices la aparece al
// comienzo y la desvanece al final. Sin luz ni niebla: se lee igual de día y de noche.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

uniform vec3 color : source_color = vec3(0.8, 0.42, 1.0);
uniform float paso = 5.0;  // m entre flechas
uniform float rapidez = 0.9;  // flechas por segundo

void fragment() {
	float v = UV.y * 2.0 - 1.0;
	float f = fract(UV.x / paso + abs(v) * 0.45 - TIME * rapidez);
	float flecha = 1.0 - smoothstep(0.30, 0.36, f);
	float borde = smoothstep(0.78, 0.86, abs(v));
	ALBEDO = mix(color, vec3(1.0), flecha * 0.35);
	ALPHA = COLOR.a * max(max(flecha * 0.9, borde * 0.85), 0.22);
}
