"""Paneles de diagnóstico (PNG) para trazar o revisar ríos, vía férrea y Ruta 5.

Dibuja las manzanas del Censo (rosado = con datos, celeste = sin información), las calles OSM
(gris; troncales en rojo) y los trazados de config/trazados.json (azul), con una grilla de
lat/lon fina para leer coordenadas. Los ríos se trazaron mirando estos paneles: un río aparece
como un hueco continuo entre manzanas.

  python pipeline/diagnostics.py                 # todos los paneles -> diagnostics/
  python pipeline/diagnostics.py centro          # un panel
  python pipeline/diagnostics.py -71.70 -71.66 -35.445 -35.412   # caja libre (lon0 lon1 lat0 lat1)
Requiere Pillow, importado dentro de main (uv run --with pillow python pipeline/diagnostics.py; make diagnostics).
"""
import json
import cli
from common import ROOT, MANZANAS_DIR, NAV_GRAPH, CONFIG, require

VIEWS = {  # lon0, lon1, lat0, lat1
    'ciudad': (-71.72, -71.58, -35.475, -35.37),
    'noroeste': (-71.70, -71.62, -35.425, -35.375),
    'poniente': (-71.715, -71.66, -35.46, -35.41),
    'sur': (-71.68, -71.60, -35.465, -35.425),
    'estacion': (-71.665, -71.62, -35.46, -35.395),
    'centro': (-71.695, -71.655, -35.445, -35.412),
}
W = 1440                                                  # panel width in pixels (the margin for the labels aside)

def main(views):
    from PIL import Image, ImageDraw
    blocks = []
    for fn, c in [('R07_MANZANA_IND_C17', (232, 200, 216)), ('R07_MANZANA_SIN_INF_C17', (187, 204, 221)), ('R07_MANZANA_ALDEA_C17', (204, 221, 187))]:
        for f in json.load(open(require(MANZANAS_DIR / f'{fn}.shp.geojson')))['features']:
            if f['properties'].get('NOM_COMUNA') not in ('TALCA', 'MAULE', 'PENCAHUE', 'SAN CLEMENTE'): continue
            g = f['geometry']
            for p in (g['coordinates'] if g['type'] == 'MultiPolygon' else [g['coordinates']]): blocks.append((p[0], c))
    g = json.load(open(require(NAV_GRAPH)))
    N = {n['id']: (n['lon'], n['lat']) for n in g['nodes']}
    thin, major, trunk = [], [], []
    for e in g['edges']:
        seg = [N[e['u']], N[e['v']]]
        (trunk if e['highway'].startswith('trunk') else major if e['highway'] in ('primary', 'secondary') else thin).append(seg)
    tz = json.load(open(CONFIG / 'trazados.json'))
    traces = [v['puntos'] for v in tz['rios'].values() if 'puntos' in v] + [tz['ferrocarril']['puntos'], tz['ruta5']['puntos']]
    out = ROOT / 'diagnostics'; out.mkdir(exist_ok=True)
    for name, (x0, x1, y0, y1) in views.items():
        s = W / (x1 - x0); H = int((y1 - y0) * s / 0.815); M = 60     # a degree of latitude is 1/0.815 of one of longitude here
        img = Image.new('RGB', (W + M, H + M), 'white'); d = ImageDraw.Draw(img, 'RGBA')
        P = lambda lon, lat: (M + (lon - x0) * s, (y1 - lat) * s / 0.815)
        box = lambda pts: any(x0 <= q[0] <= x1 and y0 <= q[1] <= y1 for q in pts)
        for r, c in blocks:
            if box(r): d.polygon([P(*q) for q in r], fill=c, outline=(170, 136, 136))
        for segs, col, w in ((thin, (119, 119, 119), 1), (major, (34, 34, 34), 2), (trunk, (255, 0, 0), 3)):
            for a, b in segs:
                if box((a, b)): d.line([P(*a), P(*b)], fill=col, width=w)
        for t in traces: d.line([P(lo, la) for la, lo in t], fill=(31, 95, 214, 204), width=3)
        step = 0.0025 if (x1 - x0) > 0.05 else 0.001
        d.rectangle([0, 0, M - 1, H + M], fill='white'); d.rectangle([0, H, W + M, H + M], fill='white')   # the margins, for the labels
        k = int(x0 / step) * step
        while k <= x1:                                    # the lat/lon grid, labelled outside the map
            if k >= x0: q = P(k, y1)[0]; d.line([(q, 0), (q, H)], fill=(68, 136, 255, 150)); d.text((q - 18, H + 4 + 12 * (round(k / step) % 3)), f'{k:.4f}', fill='black')
            k += step
        k = int(y0 / step) * step
        while k <= y1:
            if k >= y0: q = P(x0, k)[1]; d.line([(M, q), (W + M, q)], fill=(68, 136, 255, 150)); d.text((2, q - 5), f'{k:.4f}', fill='black')
            k += step
        fn = out / f'panel_{name}.png'; img.save(fn); print(fn.relative_to(ROOT), img.size)

def cmd(*a):
    if len(a) == 4 and all(v.lstrip('-').replace('.', '', 1).isdigit() for v in a): return main({'caja': tuple(map(float, a))})
    bad = [k for k in a if k not in VIEWS]
    if bad: raise SystemExit(f"vistas desconocidas: {' '.join(bad)} (hay: {', '.join(VIEWS)})")
    main({k: VIEWS[k] for k in a} if a else VIEWS)

if __name__ == '__main__':
    cli.run({}, __doc__, default=cmd)
