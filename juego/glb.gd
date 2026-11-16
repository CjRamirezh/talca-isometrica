# Lo que tools/export.py escribe al lado de juego/plaza.glb (juego/plaza.json), leído una vez: las capas que puede
# tener el glb con su tipo y si son sólidas (LAYERS de tools/export.js), los lugares y las luces de noche de los
# hitos (GLOW de la página). El juego no tiene listas propias de capas: las toma de aquí.
#
#   const Glb := preload("res://glb.gd")
#   Glb.tipo("edificios")      # "edificio" (suelo, edificio, hito, arbol, auto; "" sin material propio)
#   Glb.solida("arboles")      # false: sin colisión
#   Glb.es_capa("hitos")       # para revisar los nombres de los recortes de modelos/
#   Glb.lugar("plaza-de-armas")   # {id, nombre, x, y, h, ...} o {}
#   Glb.luces()                # [Vector3] en Godot: cada lámpara de un hito dentro de la caja
extends RefCounted

const RUTA := "res://plaza.json"

static var _info := {}


static func info() -> Dictionary:
	if _info.is_empty():
		var f := FileAccess.open(RUTA, FileAccess.READ)
		var j: Variant = JSON.parse_string(f.get_as_text()) if f else null
		if not (j is Dictionary) or not j.has("capas"):
			push_error("glb.gd: %s no está o es de antes de las capas (noviembre de 2026): corra `make juego`" % RUTA)
			j = {"capas": {}, "lugares": [], "luces": []}
		_info = j
	return _info


static func es_capa(nombre: String) -> bool:
	return info()["capas"].has(nombre)


static func tipo(nombre: String) -> String:
	var c: Variant = info()["capas"].get(nombre)
	return String(c["tipo"]) if c is Dictionary and c["tipo"] != null else ""


static func solida(nombre: String) -> bool:
	var c: Variant = info()["capas"].get(nombre)
	return c is Dictionary and bool(c["solido"])


static func lugar(id: String) -> Dictionary:
	for l in info().get("lugares", []):
		if l.get("id") == id:
			return l
	return {}


static func luces() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for l in info().get("luces", []):
		out.append(Vector3(l[0], l[2], -l[1]))
	return out
