"""HTTP for the pipeline (standard library only): one User-Agent and one retry policy for every download.

The services ask for a User-Agent that names the client (OpenStreetMap, Wikimedia) and Esri answers 403 to Python's;
UA is generic on purpose: no person's name or address.
"""
import json, sys, time, urllib.error, urllib.request

UA = 'talca-isometrica/1.0 (maqueta isometrica de Talca)'
TRANSIENT = (429, 500, 502, 503, 504, 509)            # busy or overloaded: worth waiting (509: OSM's bandwidth limit)

def get(url, *, data=None, headers=None, retry_on=TRANSIENT, tries=4, wait=5, timeout=120, quiet=False):
    """The body of url (a POST with `data`, bytes). An HTTP error whose code is in `retry_on`, a timeout or a dropped
    connection is retried after wait·k seconds (k = 1, 2, …) up to `tries` attempts; any other error (400: the OSM map
    box has too many nodes, 404) is raised at once, for the caller to handle."""
    h = {'User-Agent': UA, **(headers or {})}
    for k in range(1, tries + 1):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=data, headers=h), timeout=timeout) as r: return r.read()
        except urllib.error.HTTPError as e:
            if e.code not in retry_on or k == tries: raise
            why = f'HTTP {e.code}'
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            if k == tries: raise
            why = str(e)
        if not quiet: print(f'  {url[:90]}: {why}; reintento {k} en {wait*k} s', file=sys.stderr)
        time.sleep(wait * k)

def get_json(url, **kw):
    return json.loads(get(url, **kw))
