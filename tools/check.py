"""Revisión rápida del repo (menos de un segundo): la corre `make check`, y el hook de pre-commit (`make hooks`).

  python tools/check.py            # config/, data/, los fuentes de src/ y dist/ (make build)
  python tools/check.py --no-dist  # sin dist/ (antes de make build)

Comprueba:
  - que todos los JSON de config/ y data/ se lean;
  - que src/page.html tenga los marcadores /*STYLE*/, /*DATA*/ y <!--SCRIPTS--> una sola vez y que los bloques
    `// ==== hito:` no repitan id; que cada archivo de src/js/hitos/ esté en su ORDER, empiece con su línea
    `// ==== hito: <id> ====` y no tenga otra, y que cada fuente termine en un salto de línea;
  - que un hito no use un nombre que declara otro (lo que comparten va en la cabecera de buildModels) ni lea
    MODELS['<id>'] antes del hito que lo pone (hitos_deps());
  - que data/pois.json tenga ids únicos y que cada recorrido apunte a lugares que existen;
  - que el script de dist/assets/ compile (node --check; el error da el archivo de src/ y la línea, con build.where()),
    que cada archivo que pide dist/index.html (src, href, srcset y lo que pide desde JS en assets/) exista en dist/, y que
    dist/assets/ no tenga otros.
Termina con código 1 y una línea por falla. No reemplaza a `make smoke` (carga la página en Chromium y revisa la
generación) ni a `python pipeline/usos.py check` (14 s; avisos sobre los usos de suelo).
"""
import json, re, shutil, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'pipeline'))
import build
SRC_PAGE = build.SRC / 'page.html'

def js_depth(t):
    """For each character of JavaScript text t, the nesting depth of (), [] and {} it is at, and whether it is code
    (not inside a string, a template, a comment or a regex literal); a light scanner, enough for src/js/hitos/."""
    depth, code, d, i, n = [0] * len(t), [False] * len(t), 0, 0, len(t)
    prev = ''  # the last code character that is not a space: a / after it starts a regex literal or divides
    while i < n:
        c = t[i]
        if c in '"\'`' or t.startswith('//', i) or t.startswith('/*', i) or (c == '/' and prev not in ')]}' and not (prev.isalnum() or prev in '_$')):
            if t.startswith('//', i): j = t.find('\n', i); j = n if j < 0 else j
            elif t.startswith('/*', i): j = t.find('*/', i + 2) + 2
            else:
                j, end = i + 1, c
                while j < n and t[j] != end:
                    if t[j] == '\\': j += 1
                    elif end == '/' and t[j] == '[':  # a character class may hold a /
                        while j < n and t[j] != ']': j += 2 if t[j] == '\\' else 1
                    j += 1
                j += 1
            for k in range(i, min(j, n)): depth[k] = d
            i = j; continue
        if c in ')]}': d -= 1
        depth[i], code[i] = d, True
        if c in '([{': d += 1
        if not c.isspace(): prev = c
        i += 1
    return depth, code, d

def hitos_deps(fail):
    """The landmarks share nothing among themselves: build.py pastes them one after another into buildModels, so a
    name one of them declares at its top level (a const, a let, a function) exists only for the code after it, and a
    landmark that uses another's name depends on their order in ORDER, which nothing says (a mistake is a
    ReferenceError that only make smoke sees). What they share goes in the header of buildModels (src/js/45-landmarks.js).
    So: a landmark may not use a name another one declares at its top level, and MODELS['<id>'] may be read only by the
    landmarks after the one that sets it."""
    order = build.hito_ids(); hdir = build.SRC / 'js' / 'hitos'
    files = {h: (hdir / f'{h}.js').read_text() for h in order if (hdir / f'{h}.js').exists()}
    decl, scans = {}, {}
    for h, t in files.items():
        depth, code, end = js_depth(t); scans[h] = (depth, code)
        if end: fail(f'src/js/hitos/{h}.js: los paréntesis o llaves no cierran ({end:+d}): no se pudo revisar'); continue
        for m in re.finditer(r'\b(?:const|let|var|function)\s+([A-Za-z_$][\w$]*)', t):
            if code[m.start()] and depth[m.start()] == 0: decl.setdefault(m.group(1), (h, t.count('\n', 0, m.start()) + 1))
            # the other declarators of the same statement: `, name =` at depth 0
            if code[m.start()] and depth[m.start()] == 0 and m.group(0).startswith(('const', 'let', 'var')):
                j = m.end()
                while j < len(t) and not (code[j] and depth[j] == 0 and t[j] == ';'):
                    if code[j] and depth[j] == 0 and t[j] == ',':
                        k = re.match(r',\s*([A-Za-z_$][\w$]*)\s*=', t[j:])
                        if k: decl.setdefault(k.group(1), (h, t.count('\n', 0, j) + 1))
                    j += 1
    pos = {h: i for i, h in enumerate(order)}
    for h, t in files.items():
        if h not in scans: continue
        depth, code = scans[h]
        for name, (dh, dl) in decl.items():
            if dh == h or re.search(rf'\b(?:const|let|var|function)\s+{re.escape(name)}\b', t): continue
            for m in re.finditer(rf'(?<![\w$.]){re.escape(name)}(?![\w$])', t):
                if not code[m.start()] or re.match(r'\s*:', t[m.end():]): continue  # a string, a comment or an object key
                fail(f'src/js/hitos/{h}.js:{t.count(chr(10), 0, m.start()) + 1}: usa {name}, que declara src/js/hitos/{dh}.js:{dl} '
                     f'({"más abajo en ORDER: sería un ReferenceError" if pos[dh] > pos[h] else "otro hito"}); lo que comparten los hitos va en la cabecera de buildModels (src/js/45-landmarks.js)')
                break
    sets = {}
    for h, t in files.items():
        for m in re.finditer(r"MODELS\[['\"]([\w-]+)['\"]\]\s*=(?!=)", t): sets.setdefault(m.group(1), h)
    for h, t in files.items():
        for m in re.finditer(r"MODELS\[['\"]([\w-]+)['\"]\](?!\s*=(?!=))", t):
            s = sets.get(m.group(1))
            if s and s != h and pos[s] > pos[h]:
                fail(f'src/js/hitos/{h}.js:{t.count(chr(10), 0, m.start()) + 1}: lee MODELS[\'{m.group(1)}\'], que src/js/hitos/{s}.js pone más abajo en ORDER (todavía no existe)')

def main(dist=True):
    t0 = time.time(); bad = []
    fail = lambda m: bad.append(m)

    for f in sorted((ROOT / 'config').glob('*.json')) + sorted((ROOT / 'data').glob('*.json')):
        try: json.load(open(f))
        except ValueError as e: fail(f'{f.relative_to(ROOT)}: JSON inválido: {e}')

    order = build.hito_ids(); hdir = build.SRC / 'js' / 'hitos'
    for h in sorted({h for h in order if order.count(h) > 1}): fail(f'src/js/hitos/ORDER: hito repetido: {h}')
    for h in order:
        if not (hdir / f'{h}.js').exists(): fail(f'src/js/hitos/ORDER: no existe src/js/hitos/{h}.js')
    for f in sorted(hdir.glob('*.js')):
        if f.stem not in order: fail(f'src/js/hitos/{f.name}: no está en ORDER (build.py no lo incluye)')
        else:
            t = f.read_text()
            if not t.startswith(f'  // ==== hito: {f.stem} ====\n') or re.findall(r'// ==== hito: ([\w-]+) ====', t) != [f.stem]:
                fail(f'src/js/hitos/{f.name}: debe empezar con «  // ==== hito: {f.stem} ====» y no tener otro bloque')
    hitos_deps(fail)
    try: page, tpl = build.page(), build.script()
    except (AssertionError, OSError) as e: fail(f'src/: no se pudo unir la página o el script: {e}'); page = tpl = None
    for m in ('/*STYLE*/', '/*DATA*/', '<!--SCRIPTS-->') if page is not None else ():
        n = (SRC_PAGE.read_text() if m == '/*STYLE*/' else page).count(m)
        if n != 1: fail(f'src/page.html: el marcador {m} aparece {n} veces (debe ser 1)')
    hitos = re.findall(r'// ==== hito: ([\w-]+) ====', tpl or '')
    for h in sorted({h for h in hitos if hitos.count(h) > 1}): fail(f'src/: bloque de hito repetido: {h}')
    for f in build.sources():
        if not f.exists(): continue
        t, name = f.read_text(), f.relative_to(ROOT)
        if not t.endswith('\n'): fail(f'{name}: no termina en un salto de línea (build.py lo pegaría al siguiente)')

    pois = json.load(open(ROOT / 'data' / 'pois.json'))
    ids = [p['id'] for p in pois['pois']]
    for i in sorted({i for i in ids if ids.count(i) > 1}): fail(f'data/pois.json: id repetido: {i}')
    for k, t in pois['tours'].items():
        for s in t['s']:
            if s not in ids: fail(f'data/pois.json: el recorrido {k} apunta a un lugar que no existe: {s}')

    if dist:
        index = ROOT / 'dist' / 'index.html'
        if not index.exists(): fail('dist/index.html no existe (make build)')
        else:
            html = index.read_text()
            asked = set(re.findall(r'\s(?:src|href|srcset)="([^"]+)"', html))
            asked |= set(re.findall(r'"(assets/[^"]+)"', html))   # the data (/*DATA*/) and the scripts, asked for from JS
            if not re.search(r'"assets/geometry\.\w+\.json"', html): fail('dist/index.html: no pide los datos (/*DATA*/ en src/page.html)')
            local = {u.split('#')[0] for u in asked if not re.match(r'[a-z]+:|//|#', u)}
            for u in sorted(local):
                if not (ROOT / 'dist' / u).is_file(): fail(f'dist/index.html pide {u}, que no está en dist/')
            for f in sorted((ROOT / 'dist' / 'assets').glob('*')):
                if f'assets/{f.name}' not in local: fail(f'dist/assets/{f.name}: ningún archivo lo pide (¿quedó de otro build?)')
            app = [u for u in local if re.fullmatch(r'assets/app\.\w+\.js', u)]
            node = shutil.which('node')
            if len(app) != 1: fail(f'dist/index.html: debe pedir un script assets/app.<hash>.js (pide {len(app)})')
            elif not node: fail('node no está en el PATH: hace falta para node --check (nodenv / brew install node)')
            else:
                r = subprocess.run([node, '--check', str(ROOT / 'dist' / app[0])], capture_output=True, text=True)
                if r.returncode:
                    err = next((l for l in r.stderr.splitlines() if 'Error' in l), r.stderr.strip())
                    where = re.search(r':(\d+)\n', r.stderr)
                    at = ''
                    if where:
                        try: src, k = build.where(int(where.group(1))); at = f' en {src}:{k}'
                        except ValueError: at = f' (línea {where.group(1)} del script)'
                    fail(f'dist/{app[0]}: el script no compila{at}: {err}')

    for m in bad: print('FALLA:', m)
    print(f'check: {len(bad)} fallas' if bad else f'check: ok ({(time.time()-t0)*1000:.0f} ms)')
    return 1 if bad else 0

if __name__ == '__main__':
    if '-h' in sys.argv or '--help' in sys.argv: raise SystemExit(__doc__)
    sys.exit(main(dist='--no-dist' not in sys.argv))
