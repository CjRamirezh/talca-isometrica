// El paño de una bandera de captura la bandera (bandera.gd): un plano vertical (PlaneMesh de cara a Z, subdividido a lo
// largo) que ondea más lejos del asta (UV.x = 0 en el asta) y cuelga un poco en la punta; `fase` desfasa cada bandera.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 color : source_color = vec3(0.72, 0.27, 0.18);
uniform float fase = 0.0;

void vertex() {
	float u = UV.x;
	float a = TIME * 5.0 + fase - u * 7.0;
	float b = TIME * 2.3 + fase * 0.7 - u * 3.0;
	VERTEX.z += (sin(a) * 0.09 + sin(b) * 0.04) * u;
	VERTEX.y -= 0.07 * u * u;
	NORMAL = normalize(vec3(-(cos(a) * 0.63 + cos(b) * 0.12) * u, 0.0, 1.0));
}

void fragment() {
	ALBEDO = color;
	ROUGHNESS = 0.9;
}
