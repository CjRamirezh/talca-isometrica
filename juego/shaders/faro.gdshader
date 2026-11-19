// La columna de luz del marcador (ruta.gd), y el aro en el suelo (aro = true, sobre un plano), sin niebla para verse
// desde toda la comuna. La columna es un cilindro sin tapas, más opaco al medio y abajo, que se desvanece hacia arriba
// y nunca mide menos de `pixeles` de ancho en la pantalla (a 10 km, un cilindro de 3 m sería menos de un píxel): el
// sombreador lo ensancha a lo largo de su eje, como brillo.gdshader a los faroles. Se mezcla (no se suma): sumado, un
// violeta desaparece contra el cielo claro.
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.8, 0.42, 1.0);
uniform float pixeles = 7.0;  // el radio mínimo, en píxeles
uniform bool aro = false;
varying float alto;

void vertex() {
	alto = VERTEX.y / 500.0 + 0.5;  // 0 abajo, 1 arriba (CylinderMesh de 500 m)
	if (!aro) {
		float k = length(MODEL_MATRIX[0].xyz);
		vec4 c = MODELVIEW_MATRIX * vec4(0.0, VERTEX.y, 0.0, 1.0);
		// metros por píxel junto al eje: la distancia en la pantalla entre el eje y un punto a 1 m de él
		vec4 a = PROJECTION_MATRIX * c;
		vec4 b = PROJECTION_MATRIX * (c + vec4(1.0, 0.0, 0.0, 0.0));
		float px = 1.0 / max(abs(b.x / b.w - a.x / a.w) * 0.5 * VIEWPORT_SIZE.x, 1e-6);
		float r = length(VERTEX.xz);
		if (r > 0.0) {
			float rr = max(r * k, pixeles * px) / k;
			VERTEX.xz *= rr / r;
		}
	}
}

void fragment() {
	if (aro) {
		float r = length(UV - 0.5) * 2.0;
		float pulso = fract(TIME * 0.6);
		float anillo = smoothstep(0.08, 0.0, abs(r - mix(0.25, 1.0, pulso))) * (1.0 - pulso);
		float fijo = smoothstep(0.06, 0.0, abs(r - 0.3));
		ALBEDO = mix(color, vec3(1.0), fijo * 0.5);
		ALPHA = clamp(anillo + fijo, 0.0, 1.0) * 0.9;
	} else {
		float lado = abs(dot(NORMAL, VIEW));
		float a = clamp(alto, 0.0, 1.0);
		float h = 1.0 - a * a;
		ALBEDO = mix(color, vec3(1.0), lado * lado * 0.45);
		ALPHA = h * (0.35 + 0.6 * lado);
	}
}
