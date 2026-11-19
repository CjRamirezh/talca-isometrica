---
paths:
  - "pipeline/usos.py"
  - "pipeline/fuentes_cl.py"
  - "pipeline/cobertura.py"
  - "config/usos*.json"
  - "config/manzanas.json"
  - "src/js/26-cobertura.js"
  - "src/js/76-usos.js"
  - "tools/sentinel.py"
---

# Los usos de suelo y las fuentes chilenas

`config/usos*.json`, `pipeline/usos.py`, CONAF y CIREN, y su dibujo en `76-usos.js`. Más detalle en docs/METODOLOGIA.md §13.

## Arquitectura

| Archivo (`src/js/`) | Qué hace |
|---|---|
| `26-cobertura.js` | bajo `// ==== cobertura de CONAF ====`: `COB` decodifica `DATA.cob` (`pipeline/cobertura.py`) y sube `EW` en cada nodo del relieve al peso de su clase (`COB_W`: nativo, plantación, asilvestrada, matorral…), una vez y antes de que nadie lo lea: el color del terreno, las parcelas de `buildBase()`, `wildTrees()` y el borde urbano siguen la pendiente y CONAF. `cobK(x,y)` da la clase y `cobTall(x,y)` si es una plantación de eucalipto o pino (sus árboles van como álamos, en columnas). Sin `DATA.cob` no cambia nada |
| `76-usos.js` | bajo `// ==== usos de suelo ====`: `USOS` decodifica `DATA.usos` (polígono, uso, opciones; los usos contenidos en otro son sus `kids` y su suelo se recorta del padre). `usosPlan()` (después de los hitos, antes de `applyPads`) los marca en `occ` salvo un margen junto a las calles y salta los que caen sobre un hito, un río o la Alameda; `usosBase(B,S)` (después de `buildBase`) dibuja el suelo en su propia malla a 0,11, los detalles a 0,12–0,14, los objetos en `S` o `B` y los árboles en `TREES`/`PO_FIELD`, un dibujador por uso en `draw`; `usosFringe()` pone matorral en el suelo pelado del borde urbano. Un huerto de CIREN (`config/usos-ciren.json`) trae su especie, año de plantación, conducción y árboles por hectárea (`o.e`, `o.y`, `o.d`, `o.n`): hileras a la distancia que dan los árboles por hectárea, copas más angostas si es joven, tonos por especie (`HUERTO`) y una copa plana si es parronal (kiwi, uva de mesa); sus árboles, solo en el borde. `window.__usos` da los conteos (`tt`: árboles por uso) |

## Comandos

```bash
python pipeline/usos.py importar comuna      # rehace las entradas de OSM de config/usos.json (requiere raw/osm/map-comuna.json, make osm)
python pipeline/usos.py blancos 0.5 --osm comuna   # manzanas «sin información» que ningún uso cubre todavía
python pipeline/usos.py check                # revisa config/usos.json (fuente, confianza, hitos, superposiciones, cobertura; ~8 s)
python pipeline/usos.py bc [--rehacer]       # bc (un punto de su manzana) en las entradas con bi; --rehacer: los bi que ya no lo contienen (cambiaron las manzanas)
python pipeline/usos.py osm todo w123 [--eps 1.5]   # polígono de OSM en metros de grilla, para una entrada a mano
python -I pipeline/fuentes_cl.py fetch ciren|ciren-tabla|ciren-uso|conaf|minvu|censo2024 [carpeta]   # fuentes chilenas -> raw/cl/<fuente>/ (no reemplaza lo que hay); `info`: qué hay y cuánto cae en la comuna
uv run --with pillow python -I pipeline/fuentes_cl.py panel conaf 5295 3596 [1200] [16]   # los polígonos de una fuente (ciren-uso, conaf, censo2024, ciren, minvu) sobre la imagen de Esri, por clase -> diagnostics/
python -I pipeline/usos.py importar ciren|censo2024|areasverdes   # huertos de CIREN 2024, manzanas del Censo 2024 construidas desde 2017, plazas de MINVU-INE -> config/usos-<fuente>.json; quita de usos.json lo de OSM que reemplazan
python -I pipeline/usos.py escuelas [300]       # colegios de MINEDUC 2025 (con 300 alumnos o más) sin entrada educacional, con su polígono de OSM o la línea de satellite.py; `salud`: lo mismo con DEIS
python -I pipeline/cobertura.py [stats]         # CONAF 2024 -> data/cobertura.json (una clase cada 40 m, src/js/26-cobertura.js); stats: hectáreas por clase y cuánto marca ya la pendiente
```

## Trampas

- **Manzanas «sin información».** El Censo da ese tipo (1) a toda manzana sin viviendas, y la plantilla la pinta como parque (`built` falso: sin lotes, árboles densos). En el centro muchas son comercio o recintos. Si una se ve verde y no lo es, compruébalo con `pipeline/satellite.py` y agrega un punto dentro de ella en `config/manzanas.json` si son casas o comercio corriente, o una entrada en `config/usos.json` si es otra cosa (una industria, un colegio, un eriazo); no edites `data/geometry.json`, que `make data` regenera. Al revés también pasa: el Censo da personas a tres tramos del bandejón de la Alameda, que salían con casas; una manzana con datos que es parque va en `parques` de `config/manzanas.json` (`build.py` la deja en tipo 1).
- **Los usos del campo reemplazan las parcelas genéricas.** `buildBase()` no pone una parcela agrícola (ni su hilera de álamos) donde su centro cae en un uso de suelo (`usoAt`, salvo `parcelas`), y un huerto de más de 4 ha lleva árboles solo en sus 12 m de borde: adentro, cada hilera es una franja de copa con su sombra (hay 585 ha de huertos; con un árbol cada 33 m² serían 180 mil árboles más). `usos.py importar` corre sobre `comuna`: con `todo` (el rectángulo anterior) borraría los del campo.
- **Usos de suelo que se superponen.** OSM dibuja canchas sobre canchas y parques que cruzan un colegio. Un uso contenido entero en otro es su hijo y su suelo se recorta del padre; uno que se superpone sin estar dentro sube su suelo 1 cm (`u.lift`), o los dos parpadean a 0,11. Los usos sin suelo propio (eriazo, bosque, parcelas) pueden superponerse a todo: `inUso()` los deja fuera de los que tienen suelo. Si un uso nuevo tiene suelo, agréguelo a `USO_GROUND`.
- **El suelo de un uso no pisa el agua ni los hitos.** Los usos se dibujan a 0,11, la altura del agua y de las franjas de ripio. `usosBase()` corta sus triángulos donde `occ` estaba ocupado antes de los usos (`OCC0`: ríos, ripio, hitos, Ruta 5, vía), en piezas de hasta ~2 m; por eso los bordes del suelo junto a un río son escalonados de cerca. Un uso que cae más de un 35 % sobre eso (60 % un eriazo o bosque) no se dibuja.
- **Datos de OSM posteriores a la imagen de Esri.** OSM tiene villas y condominios que la imagen de Esri muestra como potreros o loteos en obras (el sur del Piduco, el poniente de la Ruta 5 Sur). Mandan las fuentes más recientes: se dibujan, con confianza media y una nota en `config/usos.json`.
- **Los `bi` de `config/usos.json` son índices de `data/geometry.json`.** Si cambian las manzanas (otro recorte, otro filtro), cada `bi` lleva su `bc`, un punto de su manzana, y `make check` falla si la manzana ya no lo contiene; `usos.py bc --rehacer` toma la que sí.
- **Los usos están en varios archivos, y su lugar siembra su dibujo.** `DATA.usos` junta `config/usos.json` y los archivos de las fuentes chilenas en el orden de `USOS_FILES` (`build.py`), y cada uso dibuja con `rng(1000+i*7919)`, su lugar en esa lista: quitar o agregar una entrada en medio (un `importar ciren` que reemplaza huertos de OSM) cambia el dibujo de todas las que siguen, y `tools/regress.py` sale distinto en todo el mapa, no solo donde está la entrada. Lo nuevo va al final (un archivo nuevo, al final de `USOS_FILES`): `make check` falla si una entrada que ya estaba en HEAD cambió de lugar (a propósito: `TALCA_USOS_ORDEN=ok`). Las entradas de esos archivos cuentan como a mano para `importar comuna` (lo de OSM que cubren en más de un 30 % se descarta), y cada `importar` de una fuente chilena quita de `config/usos.json` solo lo que reemplaza: `importar comuna` hoy no reproduce exactamente `config/usos.json` (descartaría el golf, Cecinas PF, el Cementerio General y el Terminal, que los hitos ya modelan y `usosPlan` salta), y correrlo desordena todas las semillas.
- **Una entrada nueva con suelo, dentro o fuera de otra, nunca a medias.** La regla de 1 cm (`u.lift`) evita el parpadeo de dos suelos, pero las hileras de uno (a 0,13) quedan encima del suelo del otro y su copa parpadea con ellas. `usos.py` (`nest()`, `rclip()`: un raster de 1 m) recorta un polígono nuevo que cae sobre todo dentro de otra entrada con suelo a 2 m dentro de ella (queda como su hijo, que la plantilla recorta de su suelo), y uno que la pisa en parte, a 2 m fuera.
- **Las manzanas del Censo 2024 no reemplazan las de 2017.** Las del mapa son las de 2017 (los `bi` de `config/usos.json` dependen de ellas): las de 2024 entran como `vivienda`, con `poly` (una manzana construida desde 2017, que `build.py` agrega con sus viviendas y personas) o con `bi` (una de 2017 «sin información» que ya está construida). Una manzana de 2024 grande y rala (menos de 8 viviendas por hectárea en más de 2 ha) no entra: son caseríos entre potreros y huertos (la de 46 ha al oriente de la Ruta 5 tiene 46 viviendas), y como manzana construida `recipeOf` le pondría galpones. Pasar el mapa a las manzanas de 2024 es otro trabajo: rehacer los `bi`, como en octubre de 2026 al pasar a la comuna.
- **`EW` no es solo la pendiente.** `26-cobertura.js` lo sube al cargar con la cobertura de CONAF: lo que lee `wildAt` (las parcelas de `buildBase`, `wildTrees`, el matorral del borde urbano, el color del terreno) ve también las plantaciones y los bosques de ribera del plano. Un `bosque` de `config/usos.json` pone todos sus árboles: `wildTrees` salta lo que `usosPlan` ocupó. Hasta octubre de 2026 el bosque saltaba la pendiente creyendo que la cubría `wildTrees`, y sus laderas quedaban peladas.
