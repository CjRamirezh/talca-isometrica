#!/usr/bin/env bash
# Descarga las fuentes de datos públicas a raw/ (≈ 117 MB tras el sparse checkout).
#   1. Manzanas del Censo 2017 (INE) en GeoJSON  — github.com/jiboncom/chile_geojson
#   2. Grafo vial de Talca extraído de OpenStreetMap — github.com/Shiroku36/cicloconecta
#   3. Elevación Copernicus DEM GLO-30 (tesela S36W072, 45 MB) del bucket público de AWS — registry.opendata.aws/copernicus-dem
#   4. Elevación SRTM 1" (tesela S36W072) de los Terrain Tiles de AWS — registry.opendata.aws/terrain-tiles
#      (el relieve hasta octubre de 2026; elevation.py --srtm, para comparar)
# Solo se baja lo necesario para la Región del Maule / Talca. Los dos repositorios se bajan en el commit que dio los
# datos de hoy (CHILE_GEOJSON, CICLOCONECTA: un commit nuevo puede cambiar data/geometry.json, y con él los `bi` de
# config/usos.json y DATA.railx) y cada archivo se comprueba al final contra pipeline/fuentes.sha256 (shasum -c). Para
# pasar a otra versión: cambie el commit, borre la carpeta, corra make fetch y luego actualice las sumas con
#   (cd raw && shasum -a 256 $(awk '{print $2}' ../pipeline/fuentes.sha256)) > pipeline/fuentes.sha256
set -euo pipefail
cd "$(dirname "$0")/.."
RAW="${TALCA_RAW:-raw}"
SUMS="$PWD/pipeline/fuentes.sha256"
mkdir -p "$RAW"
CHILE_GEOJSON=dd54afc10d1dcc7b706cf17f50777e812d06e199   # jiboncom/chile_geojson (master, octubre de 2026)
CICLOCONECTA=5bc4ce9fdf49754355a33771389a995c0499a76f    # Shiroku36/cicloconecta (main, octubre de 2026)

clone_sparse () {  # repo destino commit rutas...
  local repo="$1" dest="$2" sha="$3"; shift 3
  if [ -d "$dest/.git" ]; then
    local have; have=$(git -C "$dest" rev-parse HEAD)
    if [ "$have" = "$sha" ]; then echo "· $dest ya existe, en $sha"
    else echo "· $dest ya existe, pero en $have, no en $sha: bórrelo para bajar el commit fijado" >&2; fi
    return
  fi
  git init -q "$dest"
  git -C "$dest" remote add origin "https://github.com/$repo"
  git -C "$dest" sparse-checkout set --no-cone "$@"
  git -C "$dest" fetch -q --depth 1 --filter=blob:none origin "$sha"
  git -C "$dest" checkout -q --detach FETCH_HEAD
}

clone_sparse jiboncom/chile_geojson "$RAW/chile_geojson" "$CHILE_GEOJSON" \
  '/manzanas/R07_MANZANA_IND_C17.shp.geojson' \
  '/manzanas/R07_MANZANA_SIN_INF_C17.shp.geojson' \
  '/manzanas/R07_MANZANA_ALDEA_C17.shp.geojson' '/README.md'

clone_sparse Shiroku36/cicloconecta "$RAW/cicloconecta" "$CICLOCONECTA" \
  '/data/cities/talca/*' '/README*' '/pipeline/*'

mkdir -p "$RAW/dem"
if [ -f "$RAW/dem/S36W072.hgt.gz" ]; then echo "· $RAW/dem/S36W072.hgt.gz ya existe, se omite"
else curl -fL --retry 3 -o "$RAW/dem/S36W072.hgt.gz" https://s3.amazonaws.com/elevation-tiles-prod/skadi/S36/S36W072.hgt.gz; fi

COP=Copernicus_DSM_COG_10_S36_00_W072_00_DEM
mkdir -p "$RAW/dem/copernicus"
if [ -f "$RAW/dem/copernicus/$COP.tif" ]; then echo "· $RAW/dem/copernicus/$COP.tif ya existe, se omite"
else curl -fL --retry 3 -o "$RAW/dem/copernicus/$COP.tif" "https://copernicus-dem-30m.s3.amazonaws.com/$COP/$COP.tif"; fi

echo "Sumas de pipeline/fuentes.sha256:"
if ! (cd "$RAW" && shasum -a 256 -c "$SUMS"); then
  echo "Una fuente no es la que dio los datos de hoy: make data puede cambiar data/ (vea el comienzo de este archivo)." >&2
  exit 1
fi
echo "Listo. Fuentes en $RAW/"
