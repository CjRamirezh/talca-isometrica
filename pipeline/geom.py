"""Plane geometry shared by the pipeline (standard library only). Points are (x, y) tuples in grid metres; a ring is
a list of points without the closing repeat, a polyline a list of points.

  dec, enc            the delta-encoded integer polylines of data/*.json ([x0, y0, dx1, dy1, …]; enc(pts, 10): decimetres)
  area, centre, vertex_mean, bbox, apart
  pip                 point in polygon (even-odd), for a ring tested a few times
  in_ring, near_ring, clip_line
                      the same over a ring indexed by bands (cached per ring object): for a ring tested many times, like
                      the commune's limit (461 vertices); in_ring gives exactly pip's answers
  crossings_at, scanlines
                      the x where a horizontal line crosses a ring (the rows of a raster)
  seg_dist, seg_point, polyline_dist, crossings
  rdp, simplify_ring  Douglas–Peucker
  merc_px, tile_of    Web Mercator (the Esri tiles)

Every function keeps the floating-point operations of the copies it replaced (the outputs of the pipeline did not
change: tests/golden.py); change one and data/ may change by a vertex.
"""
import math

# ---------------------------------------------------------------- encoding
def dec(a):
    """[x0, y0, dx1, dy1, …] -> [(x0, y0), (x1, y1), …]."""
    pts, x, y = [], 0, 0
    for i in range(0, len(a), 2): x += a[i]; y += a[i+1]; pts.append((x, y))
    return pts

def enc(pts, k=1):
    """[(x, y), …] -> integers in delta, each coordinate rounded after scaling by k (1: metres; 10: decimetres)."""
    out = []; px = py = 0
    for x, y in pts:
        xi, yi = int(round(x*k)), int(round(y*k)); out += [xi-px, yi-py]; px, py = xi, yi
    return out

# ---------------------------------------------------------------- measures
def area(r):
    """Signed area (counter-clockwise > 0)."""
    return sum(r[i-1][0]*r[i][1]-r[i][0]*r[i-1][1] for i in range(len(r)))/2

def centre(r):
    """The area centroid of a ring (the vertex mean when its area is under 1e-9 m²)."""
    A = area(r)
    if abs(A) < 1e-9: return vertex_mean(r)
    cx = sum((r[i-1][0]+r[i][0])*(r[i-1][0]*r[i][1]-r[i][0]*r[i-1][1]) for i in range(len(r)))/(6*A)
    cy = sum((r[i-1][1]+r[i][1])*(r[i-1][0]*r[i][1]-r[i][0]*r[i-1][1]) for i in range(len(r)))/(6*A)
    return (cx, cy)

def vertex_mean(r): return (sum(p[0] for p in r)/len(r), sum(p[1] for p in r)/len(r))

def bbox(r):
    """(xmin, ymin, xmax, ymax)."""
    xs = [p[0] for p in r]; ys = [p[1] for p in r]; return (min(xs), min(ys), max(xs), max(ys))

def apart(a, b):
    """Two boxes (xmin, ymin, xmax, ymax) that do not touch."""
    return a[0] > b[2] or b[0] > a[2] or a[1] > b[3] or b[1] > a[3]

# ---------------------------------------------------------------- point in polygon
def pip(p, r):
    """Point in polygon, even-odd (a point on a left or bottom edge is inside, on a right or top one outside)."""
    inside = False; x, y = p
    for i in range(len(r)):
        (x0, y0), (x1, y1) = r[i-1], r[i]
        if (y0 > y) != (y1 > y) and x < x0 + (y-y0)*(x1-x0)/(y1-y0): inside = not inside
    return inside

_IDX = {}
def _index(ring, band=100):
    """Ring edges by horizontal bands of `band` m (cached per ring object): in_ring and clip_line test only nearby edges."""
    k = id(ring)
    if k not in _IDX or _IDX[k][0] is not ring:
        B = {}
        for i in range(len(ring)):
            a, b = ring[i-1], ring[i]
            for j in range(int(min(a[1], b[1]) // band), int(max(a[1], b[1]) // band) + 1): B.setdefault(j, []).append((a, b))
        _IDX[k] = (ring, B, band)
    return _IDX[k][1], _IDX[k][2]

def in_ring(p, ring):
    """pip() over the ring's edges near p only (the same answers; the index is built on the first call for that list,
    which must not change afterwards)."""
    B, band = _index(ring); c = False; x, y = p
    for a, b in B.get(int(y // band), ()):
        if (a[1] > y) != (b[1] > y) and x < a[0] + (y-a[1])*(b[0]-a[0])/(b[1]-a[1]): c = not c
    return c

def near_ring(p, ring, m):
    """Is p inside the polygon or less than m metres from its edge?"""
    if in_ring(p, ring): return True
    B, band = _index(ring); x, y = p
    for j in range(int((y - m) // band), int((y + m) // band) + 1):
        for a, b in B.get(j, ()):
            if seg_dist(p, a, b) < m: return True
    return False

def clip_line(pts, ring):
    """The parts of a polyline inside a polygon: a list of polylines, cut exactly where they cross its edges."""
    B, band = _index(ring); out, cur = [], []
    for k in range(len(pts)):
        p = pts[k]
        if k:
            a = pts[k-1]; ts = []
            edges = {e for j in range(int(min(a[1], p[1]) // band), int(max(a[1], p[1]) // band) + 1) for e in B.get(j, ())}
            for c, d in edges:
                den = (p[0]-a[0])*(d[1]-c[1]) - (p[1]-a[1])*(d[0]-c[0])
                if den == 0: continue
                t = ((c[0]-a[0])*(d[1]-c[1]) - (c[1]-a[1])*(d[0]-c[0])) / den
                u = ((c[0]-a[0])*(p[1]-a[1]) - (c[1]-a[1])*(p[0]-a[0])) / den
                if 0 < t < 1 and 0 <= u < 1: ts.append(t)
            for t in sorted(ts):
                q = (a[0]+(p[0]-a[0])*t, a[1]+(p[1]-a[1])*t)
                if cur: cur.append(q); out.append(cur); cur = []
                else: cur = [q]
        if in_ring(p, ring): cur.append(p)
    if len(cur) > 1: out.append(cur)
    return [l for l in out if len(l) > 1]

# ---------------------------------------------------------------- scanlines
def crossings_at(r, y):
    """The x where the horizontal line at y crosses the ring's edges, sorted (pairs bound the inside, as in pip)."""
    return sorted(r[i-1][0] + (y-r[i-1][1])*(r[i][0]-r[i-1][0])/(r[i][1]-r[i-1][1]) for i in range(len(r)) if (r[i-1][1] > y) != (r[i][1] > y))

def scanlines(rings, y0, step, n):
    """crossings_at() of the rows y0 + j·step (0 ≤ j < n) over several rings (a polygon and its holes) at once, each
    edge visiting only its rows: {j: sorted x}, only the rows that cross."""
    rows = {}
    for r in rings:
        for i in range(len(r)):
            (ax, ay), (bx, by) = r[i-1], r[i]
            if ay == by: continue
            lo, hi = (ay, by) if ay < by else (by, ay)
            for j in range(max(0, math.ceil((lo-y0)/step)), min(n-1, math.floor((hi-y0)/step))+1):
                y = y0 + j*step
                if lo <= y < hi: rows.setdefault(j, []).append(ax + (y-ay)*(bx-ax)/(by-ay))
    for xs in rows.values(): xs.sort()
    return rows

# ---------------------------------------------------------------- segments
def seg_point(p, a, b):
    """The point of segment ab nearest to p."""
    dx, dy = b[0]-a[0], b[1]-a[1]; L = dx*dx+dy*dy or 1e-9
    t = max(0, min(1, ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/L)); return (a[0]+t*dx, a[1]+t*dy)

def seg_dist(p, a, b):
    """Distance from p to segment ab."""
    dx, dy = b[0]-a[0], b[1]-a[1]; L = dx*dx+dy*dy or 1e-9
    t = max(0, min(1, ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/L)); return math.hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dy)

def polyline_dist(p, pl):
    """Distance from p to a polyline."""
    return min(seg_dist(p, pl[i], pl[i+1]) for i in range(len(pl)-1))

def crossings(pl, ql):
    """The points where two polylines cross (ends included)."""
    out = []
    for i in range(len(pl)-1):
        a, b = pl[i], pl[i+1]; r = (b[0]-a[0], b[1]-a[1])
        for j in range(len(ql)-1):
            c, d = ql[j], ql[j+1]; s = (d[0]-c[0], d[1]-c[1]); den = r[0]*s[1]-r[1]*s[0]
            if abs(den) < 1e-12: continue
            t = ((c[0]-a[0])*s[1]-(c[1]-a[1])*s[0])/den; u = ((c[0]-a[0])*r[1]-(c[1]-a[1])*r[0])/den
            if 0 <= t <= 1 and 0 <= u <= 1: out.append((a[0]+t*r[0], a[1]+t*r[1]))
    return out

# ---------------------------------------------------------------- simplification
def rdp(pts, eps):
    """Douglas–Peucker over an open polyline: the points farther than eps from the chord of their stretch (the first
    of equally far ones). A closed polyline (first point = last) has no chord: simplify_ring() splits it."""
    if len(pts) < 3: return pts
    a, b = pts[0], pts[-1]; dx, dy = b[0]-a[0], b[1]-a[1]; L = math.hypot(dx, dy) or 1e-9
    dmax, idx = 0, 0
    for i in range(1, len(pts)-1):
        p = pts[i]; d = abs(dy*(p[0]-a[0]) - dx*(p[1]-a[1])) / L
        if d > dmax: dmax, idx = d, i
    if dmax > eps: return rdp(pts[:idx+1], eps)[:-1] + rdp(pts[idx:], eps)
    return [a, b]

def simplify_ring(ring, eps):
    """A ring simplified as two open halves, split at its middle vertex (so that its first vertex is not stuck on a
    straight edge)."""
    h = len(ring) // 2
    return rdp(ring[:h+1], eps)[:-1] + rdp(ring[h:] + [ring[0]], eps)[:-1]

# ---------------------------------------------------------------- Web Mercator
def merc_px(lat, lon, z):
    """Global pixel (x, y) of a point in the 256-px tiles of zoom z."""
    n = 2 ** z; s = math.radians(lat)
    return (lon+180)/360*n*256, (1-math.log(math.tan(s)+1/math.cos(s))/math.pi)/2*n*256

def tile_of(lat, lon, z):
    """The tile (column, row) of a point at zoom z."""
    n = 2 ** z; s = math.radians(lat)
    return int((lon+180)/360*n), int((1-math.log(math.tan(s)+1/math.cos(s))/math.pi)/2*n)

def inner_point(r):
    """A point with integer coordinates inside ring r (pip): its rounded area centroid, or else the rounded middle of
    the longest inside run of the rows y = k m from the middle of its box outwards; None for a ring too thin."""
    c = centre(r); c = (round(c[0]), round(c[1]))
    if pip(c, r): return c
    x0, y0, x1, y1 = bbox(r); ym = round((y0 + y1) / 2)
    for k in range(int(y1 - y0) + 2):
        for y in (ym + k, ym - k):
            xs = crossings_at(r, y)
            for a, b in sorted(((xs[i], xs[i+1]) for i in range(0, len(xs)-1, 2)), key=lambda s: s[0] - s[1]):
                p = (round((a + b) / 2), y)
                if pip(p, r): return p
    return None
