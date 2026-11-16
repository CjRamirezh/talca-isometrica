"""Qué cambió en los data/*.json (archivos de una línea: git diff no sirve): por archivo, cada clave con su tipo y su
tamaño antes y después, y en las listas cuántos elementos cambiaron en su lugar, cuántos se agregaron o quitaron y el
primero distinto. Biblioteca estándar.

  python3 tools/datadiff.py                    # data/ del árbol de trabajo contra HEAD
  python3 tools/datadiff.py HEAD~3             # contra otra versión de git
  python3 tools/datadiff.py a.json b.json      # dos archivos cualesquiera
  python3 tools/datadiff.py --hondo 2 …        # baja dos niveles en los diccionarios (por omisión, 1)

Sale con 1 si algo cambió (sirve de puerta: `make golden` compara las salidas del pipeline enteras).
"""
import json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def size(v):
    return f'{type(v).__name__}[{len(v)}]' if isinstance(v, (list, dict, str)) else repr(v)[:40]

def short(v, n=90):
    s = json.dumps(v, ensure_ascii=False, separators=(',', ':')); return s if len(s) <= n else s[:n] + '…'

def compare(a, b, path, depth, out):
    """Lines describing how b differs from a, under `path`."""
    if a == b: return
    if isinstance(a, dict) and isinstance(b, dict) and depth > 0:
        for k in [*a, *(k for k in b if k not in a)]:
            p = f'{path}.{k}' if path else k
            if k not in b: out.append(f'  {p}: quitada ({size(a[k])})')
            elif k not in a: out.append(f'  {p}: nueva ({size(b[k])}) {short(b[k], 60)}')
            else: compare(a[k], b[k], p, depth - 1, out)
        return
    if isinstance(a, list) and isinstance(b, list):
        n = min(len(a), len(b)); ch = [i for i in range(n) if a[i] != b[i]]
        msg = f'  {path}: {len(a)} -> {len(b)} elementos'
        if ch: msg += f'; {len(ch)} distintos en su lugar, el primero [{ch[0]}]: {short(a[ch[0]], 60)} -> {short(b[ch[0]], 60)}'
        if len(b) != len(a): msg += f"; {abs(len(b) - len(a))} {'agregados' if len(b) > len(a) else 'quitados'} al final"
        out.append(msg); return
    out.append(f'  {path or "(raíz)"}: {size(a)} {short(a, 60)} -> {size(b)} {short(b, 60)}')

def main(a):
    depth = 1
    if '--hondo' in a: i = a.index('--hondo'); depth = int(a[i+1]); del a[i:i+2]
    if any(x.startswith('-') for x in a) or len(a) > 2: raise SystemExit(__doc__)
    if len(a) == 2: pairs = [(a[0], json.load(open(a[0])), json.load(open(a[1])))]
    else:
        rev = a[0] if a else 'HEAD'; pairs = []
        for f in sorted((ROOT / 'data').glob('*.json')):
            r = subprocess.run(['git', 'show', f'{rev}:data/{f.name}'], cwd=ROOT, capture_output=True, text=True)
            old = json.loads(r.stdout) if r.returncode == 0 else {}
            pairs.append((f'data/{f.name}' + ('' if r.returncode == 0 else f' (no está en {rev})'), old, json.load(open(f))))
    changed = 0
    for name, x, y in pairs:
        out = []; compare(x, y, '', depth, out)
        if out: changed += 1; print(name); print('\n'.join(out))
    print(f'{changed} archivos distintos' if changed else 'sin cambios')
    return 1 if changed else 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
