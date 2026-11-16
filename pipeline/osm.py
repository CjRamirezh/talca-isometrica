"""OpenStreetMap JSON (the API's `map` boxes and `full` objects, cached in raw/osm/) read into maps by id, in grid metres.

  m = osm.load('comuna')            # raw/osm/map-comuna.json (read once per process)
  N, W, R = m                       # node id -> (x, y); way id -> way element; relation id -> relation element
  m.nodes[id]                       # the node element (its tags, lon, lat)
  m.pts(way)                        # the way's points, skipping nodes the download lacks
  osm.join(ways)                    # open ways (node ids or points) chained into closed rings
"""
import json
from common import RAW, loc, require

class Map:
    """The elements of one OSM JSON, by type and id; unpacks as (N, W, R)."""
    def __init__(self, elements):
        self.elements = elements
        self.nodes = {e['id']: e for e in elements if e['type'] == 'node'}
        self.W = {e['id']: e for e in elements if e['type'] == 'way'}
        self.R = {e['id']: e for e in elements if e['type'] == 'relation'}
        self.N = {i: loc(e['lon'], e['lat']) for i, e in self.nodes.items()}
    def __iter__(self): return iter((self.N, self.W, self.R))
    def pts(self, way):
        """A way's points in grid metres (its nodes missing from the download left out)."""
        return [self.N[n] for n in way['nodes'] if n in self.N]

_MAPS = {}
def load(name='comuna', hint='Ejecute: make osm'):
    """raw/osm/map-<name>.json (traces.py tiles / tiles-comuna), read once per process."""
    if name not in _MAPS: _MAPS[name] = read(require(RAW / 'osm' / f'map-{name}.json', hint))
    return _MAPS[name]

def read(path):
    """Any OSM JSON file ({"elements": […]}) as a Map."""
    with open(path) as f: return Map(json.load(f)['elements'])

def join(ways, last=False):
    """Open ways (lists of node ids or of points) chained by their ends into closed rings, each with its first item
    repeated at the end; the chains that do not close are left out. Each ring starts from the first way left (or the
    last, `last=True`: usos.py, whose polygons start where they did when they were imported)."""
    ways, rings = [list(w) for w in ways if len(w) > 1], []
    while ways:
        cur = ways.pop() if last else ways.pop(0)
        while cur[0] != cur[-1]:
            for k, w in enumerate(ways):
                if w[0] == cur[-1]: cur += w[1:]
                elif w[-1] == cur[-1]: cur += w[-2::-1]
                elif w[-1] == cur[0]: cur = w[:-1] + cur
                elif w[0] == cur[0]: cur = w[:0:-1] + cur
                else: continue
                ways.pop(k); break
            else: break
        if cur[0] == cur[-1]: rings.append(cur)
    return rings
