"""Paths and the projection shared by the whole pipeline.

Local coordinate system ("grid metres"):
  * Origin: the centre of Talca's Plaza de Armas (-35.42653, -71.66600).
  * A local equirectangular projection (enough at the scale of a city: error < 0.1 %).
  * Turned +5°: Talca's grid of numbered streets is turned ~5° clockwise from north; turning the coordinates +5°
    makes the Norte/Sur streets parallel to the x axis and the Oriente/Poniente ones to the y axis, so that the
    grid matches the isometric axes of the render.
  * x grows eastwards, y northwards. In three.js: X = x, Z = -y.
The plane geometry (points in polygons, segments, Douglas–Peucker) is in geom.py; in_ring, near_ring and clip_line
are imported here too, for the tools that took them from common.
"""
import math, os
from pathlib import Path
from geom import in_ring, near_ring, clip_line, simplify_ring   # noqa: F401 (in_ring, near_ring, clip_line: re-exported)

ROOT = Path(__file__).resolve().parent.parent
RAW = Path(os.environ.get('TALCA_RAW', ROOT / 'raw'))        # downloaded sources (not versioned)
DATA = ROOT / 'data'                                           # processed data (versioned)
CONFIG = ROOT / 'config'

MANZANAS_DIR = RAW / 'chile_geojson' / 'manzanas'
NAV_GRAPH = RAW / 'cicloconecta' / 'data' / 'cities' / 'talca' / 'nav_graph.json'

LAT0, LON0 = -35.42653, -71.66600
KX = 111320 * math.cos(math.radians(35.4265))   # metres per degree of longitude
KY = 110950                                      # metres per degree of latitude
TH = math.radians(5.0)                           # the grid's turn

def loc(lon, lat):
    """(lon, lat) -> (x, y) in grid metres."""
    x = (lon - LON0) * KX
    y = (lat - LAT0) * KY
    return (x * math.cos(TH) - y * math.sin(TH), x * math.sin(TH) + y * math.cos(TH))

def unloc(x, y):
    """(x, y) in grid metres -> (lat, lon)."""
    xr = x * math.cos(-TH) - y * math.sin(-TH)
    yr = x * math.sin(-TH) + y * math.cos(-TH)
    return (LAT0 + yr / KY, LON0 + xr / KX)

# The model is the commune of Talca: its limit (OSM relation 541797, admin_level=8, dpachile:id 07101), in
# raw/osm/comuna-talca.json. EXT is the box that holds it, fitted to the relief's grid (40 m) with one cell of margin;
# everything outside the limit is cut (the template, with DATA.limit).
COMUNA_OSM = 541797
EXT = (-4920, 15800, -10840, 13000)                      # xmin, xmax, ymin, ymax in grid metres

def comuna(eps=2.0):
    """The commune's boundary: one ring [(x, y), ...] in grid metres, counter-clockwise, simplified to `eps` m.
    Downloaded once from the OSM API (relation/<id>/full) and cached in raw/osm/comuna-talca.json."""
    import osm, net
    f = RAW / 'osm' / 'comuna-talca.json'
    if not f.exists():
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(net.get(f'https://api.openstreetmap.org/api/0.6/relation/{COMUNA_OSM}/full.json'))
    m = osm.read(f)
    segs = [list(m.W[e['ref']]['nodes']) for e in m.R[COMUNA_OSM]['members'] if e['type'] == 'way' and e['role'] == 'outer']
    ring = segs.pop(0)
    while segs:                                         # chain the outer ways, each turned to follow the previous one
        for i, s in enumerate(segs):
            if s[0] == ring[-1]: ring += s[1:]; segs.pop(i); break
            if s[-1] == ring[-1]: ring += s[::-1][1:]; segs.pop(i); break
        else: raise SystemExit('el límite de la comuna no cierra')
    assert ring[0] == ring[-1], 'el límite de la comuna no cierra'
    R = simplify_ring([m.N[n] for n in ring[:-1]], eps)
    if sum(R[i-1][0]*R[i][1] - R[i][0]*R[i-1][1] for i in range(len(R))) < 0: R = R[::-1]
    return R

def require(path, hint='Ejecute primero: make fetch'):
    """path, or exit with «Falta <path>» and the hint (what makes it)."""
    if not Path(path).exists():
        raise SystemExit(f'Falta {path}.\n{hint}')
    return path
