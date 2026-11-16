# /// script
# requires-python = ">=3.10"
# dependencies = ["playwright==1.63"]
# ///
"""Evalúa expresiones JavaScript en el mapa cargado (Chromium sin interfaz) e imprime el resultado.

  uv run tools/probe.py "__stats.ms" "Object.keys(__rail)"
  uv run tools/probe.py "(()=>{const r=__rail.main;return [r.s[r.s.length-1], r.x[0], r.y[0]]})()"
  uv run tools/probe.py --js "__train('main',6200)" "__trains()"      # --js corre antes (repetible)

Cada argumento es una expresión (o una IIFE) que se evalúa con page.evaluate; el resultado se imprime como JSON, una
línea por expresión. Sirve para mirar lo que la página expone en window.__* (__rail, __stats, __usos, __pads,
__trains) sin tomar capturas. Cada --js espera a que el mapa quede quieto antes de seguir. Abre la página con Map de
tools/page.py (una sola carga, ~1 min con SwiftShader; --gl metal, la GPU del Mac). Sale con 1 si una expresión falla
o hubo errores de consola.
"""
import argparse, asyncio, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from page import Map, add_page_args

async def main(a):
    fails = 0
    async with Map.from_args(a, quiet=True) as m:
        for js in a.js or []: await m.run(js)
        for e in a.expr:
            try: print(json.dumps(await m.page.evaluate(e), ensure_ascii=False))
            except Exception as x: print('ERROR', e, '->', str(x).splitlines()[0]); fails += 1
        fails += len(m.print_logs())
    if fails: raise SystemExit(1)

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('expr', nargs='+', help='expresiones JS; cada una se imprime como JSON')
    ap.add_argument('--js', action='append', help='JS que corre antes de evaluar (repetible)')
    add_page_args(ap)
    asyncio.run(main(ap.parse_intermixed_args()))
