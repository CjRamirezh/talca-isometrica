# Talca Isométrica — tareas del pipeline. Ver README.md.
PY ?= python3
PW ?= uv run --with "playwright==1.63" python   # Python con Playwright, para las capturas (el del sistema no lo tiene)
PIL ?= uv run --with pillow python               # Python con Pillow: lo que lee las teselas de Esri (golf) o dibuja paneles
GODOT ?= /Applications/Godot.app/Contents/MacOS/Godot
PORT ?= 8765
DRY_RUN ?= 0
.PHONY: all fetch osm data elevation ruta5 edificios edificios-ml golf pois build check golden lint smoke hooks validate diagnostics shots site-assets juego deploy serve clean

all: data elevation edificios golf pois build         ## pipeline completo (requiere raw/: make fetch)

fetch:                        ## descarga las fuentes a raw/ (~117 MB)
	./pipeline/fetch_sources.sh

osm:                          ## la API map de OSM sobre toda la comuna -> raw/osm/map-comuna.json (caminos rurales, Ruta 5, vía; ~240 cajas la primera vez)
	cd pipeline && $(PY) traces.py tiles-comuna

data:                         ## raw/ + config/trazados.json -> data/geometry.json
	cd pipeline && $(PY) process_geometry.py

elevation:                    ## raw/dem/copernicus/ (Copernicus GLO-30; pipeline/geotiff.py lo lee) -> data/elevation.json
	cd pipeline && $(PY) elevation.py

ruta5:                        ## raw/osm/map-comuna.json -> data/ruta5.json (calzadas y ramales de la Ruta 5; requiere traces.py tiles-comuna)
	cd pipeline && $(PY) traces.py calzadas comuna

edificios:                    ## raw/osm/map-comuna.json + config/edificios.json (+ config/techos.json) -> data/edificios.json (los edificios de OSM y, donde OSM no los tiene, las huellas de raw/edificios-ml/)
	cd pipeline && $(PY) edificios.py

edificios-ml:                 ## raw/overture, raw/msbuildings, raw/google-open-buildings* -> raw/edificios-ml/ (huellas de aprendizaje automático y alturas de Google 2.5D, para make edificios; uv)
	uv run --with duckdb --with shapely --with numpy --with rasterio --with pyproj python -I tools/ml_buildings.py

golf:                         ## la imagen de Esri sobre el Talca Country Club (su contorno, en config/usos.json) -> data/golf.json (pasto cortado y copas; Pillow, por uv)
	cd pipeline && $(PIL) golf.py

pois:                         ## pipeline/pois.py -> data/pois.json + data/pois.csv
	cd pipeline && $(PY) pois.py

build:                        ## -> dist/: index.html, assets/ (el script, three.js y los datos, con hash) y los archivos de src/site/ (requiere npm install)
	cd pipeline && $(PY) build.py

check: build                  ## revisión rápida (~1 s): JSON, marcadores, hitos, node --check, los archivos que pide la página, trampas de config/ y data/, las pruebas de tests/ y que todo el Python compile; la corre el hook de pre-commit
	$(PY) tools/check.py
	$(PY) -m compileall -q pipeline tools tests
	$(PY) -m unittest discover -s tests -q

golden:                       ## las salidas de los comandos del pipeline contra una referencia (antes de refactorizar: make golden REF=shots/golden-ref SAVE=1; ~5 min)
	$(PY) tests/golden.py $(if $(SAVE),--save,--against) $(or $(REF),shots/golden-ref)

lint:                         ## ESLint (versión fija, por npx) sobre el script unido, con el archivo y la línea de src/ (~3 s; tools/lint.py)
	$(PY) tools/lint.py

smoke: build lint             ## carga la página en Chromium y falla si hay errores de consola o la generación sale vacía (~1 min)
	$(PW) tools/screenshot.py shots/smoke.png --strict

hooks:                        ## instala .githooks/ (pre-commit = make check; pre-push = make deploy al empujar main a origin, sin bloquear)
	git config core.hooksPath .githooks

juego: build                  ## juego/plaza.glb (400 m alrededor de la plaza, tools/export.py) y su importación en Godot; luego: Godot --path juego
	$(PW) tools/export.py --glb juego/plaza.glb --lado 400
	mkdir -p juego/datos && cp config/fachadas.json data/plaza-osm.json juego/datos/   # lo que el juego comparte con la página
	$(GODOT) --headless --path juego --import

deploy:                       ## make build y sube dist/ a Cloudflare Pages (talca.eduramirez.com); DRY_RUN=1 arma sin subir
	DRY_RUN=$(DRY_RUN) ./scripts/deploy-cloudflare.sh

validate:                     ## compara cada lugar con su dirección en la grilla (requiere raw/)
	cd pipeline && $(PY) geocode.py validate

diagnostics:                  ## paneles PNG de manzanas + calles + trazados (requiere raw/; Pillow, por uv)
	cd pipeline && $(PIL) diagnostics.py

shots: build                  ## capturas de referencia en shots/ (requiere npm install + playwright)
	$(PW) tools/screenshot.py shots/vista-inicial.png
	$(PW) tools/screenshot.py shots/corte.png --hash corte-apelaciones
	$(PW) tools/screenshot.py shots/movil-oscuro.png --size 390x844 --dark

site-assets: build            ## src/site/og.jpg (Open Graph, 1200 × 630), apple-touch-icon.png y los pósters del arranque (poster-*.webp), desde el mapa y el favicon
	uv run tools/site_assets.py   # las dependencias, del encabezado del archivo

serve: build                  ## sirve dist/ en http://localhost:$(PORT) y lo abre en el navegador (otro puerto: make serve PORT=9000)
	(sleep 1 && $(PY) -m webbrowser -t http://localhost:$(PORT)/ >/dev/null) & \
	cd dist && $(PY) -m http.server $(PORT)

clean:
	rm -rf shots diagnostics pipeline/__pycache__
