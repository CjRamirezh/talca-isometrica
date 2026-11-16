"""La memoria del script durante la generación: el montón de JS por fase, su pico, lo que queda después de un GC y
quién asigna (o retiene) más, con el archivo y la línea de src/.

  uv run --with "playwright==1.63" python tools/heap.py                 # teléfono (390x844, densidad 2), SwiftShader
  uv run --with "playwright==1.63" python tools/heap.py --vivo          # quién retiene lo que queda después del GC
  uv run --with "playwright==1.63" python tools/heap.py --top 40 --size 1440x900 --dpr 1
  TALCA_DIST=<copia de dist/> uv run --with "playwright==1.63" python tools/heap.py   # otra versión, para comparar

Carga el mapa en Chromium sin interfaz con --enable-precise-memory-info y lee window.__mem (99-boot.js: MB del montón
después de cada fase de la primera etapa, el pico entre ellas y las tajadas de rest(), y al final). Con el perfilador
de asignaciones por muestreo de CDP (HeapProfiler.startSampling, una muestra cada --intervalo bytes) imprime los MB
asignados por función: todo lo que se asignó durante la carga (también lo que el GC ya soltó), o con --vivo solo lo
que sigue vivo al terminar, después de un GC forzado (HeapProfiler.collectGarbage). Al final, el montón antes y
después de ese GC (Runtime.getHeapUsage). Una carga, ~1 min con SwiftShader.
"""
import argparse, asyncio, json, sys
from collections import Counter
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from screenshot import serve, GL
from profile import src_of

def by_function(prof):
    """{(function, src file:line): bytes} of a sampling heap profile, each node's own (selfSize)."""
    out = Counter()
    def walk(n):
        f = n['callFrame']; out[(f['functionName'] or '(anónima)', src_of(f))] += n.get('selfSize', 0)
        for c in n.get('children', []): walk(c)
    walk(prof['head'])
    return out

async def main(a):
    from playwright.async_api import async_playwright
    w, h = map(int, a.size.split('x'))
    async with async_playwright() as p:
        b = await p.chromium.launch(args=GL['swiftshader'] + ['--enable-precise-memory-info'])
        pg = await b.new_page(viewport={'width': w, 'height': h}, has_touch=w < 800, is_mobile=w < 800, device_scale_factor=a.dpr)
        cdp = await pg.context.new_cdp_session(pg)
        await cdp.send('HeapProfiler.enable')
        await cdp.send('HeapProfiler.startSampling', {'samplingInterval': a.intervalo,
            'includeObjectsCollectedByMajorGC': not a.vivo, 'includeObjectsCollectedByMinorGC': not a.vivo})
        await pg.goto(serve())
        await pg.wait_for_function('window.__stats', timeout=300000)
        mem = await pg.evaluate('JSON.stringify(window.__mem||null)')  # null: a version from before window.__mem
        before = await cdp.send('Runtime.getHeapUsage')
        if a.vivo: await cdp.send('HeapProfiler.collectGarbage')
        prof = (await cdp.send('HeapProfiler.getSamplingProfile'))['profile']
        await cdp.send('HeapProfiler.stopSampling')
        if not a.vivo: await cdp.send('HeapProfiler.collectGarbage')
        after = await cdp.send('Runtime.getHeapUsage')
        await b.close()
    print('montón por fase (MB, window.__mem):', mem if mem != 'null' else '(esta versión no lo tiene)')
    print(f"al terminar: {before['usedSize']/2**20:.0f} MB; después de un GC: {after['usedSize']/2**20:.0f} MB")
    F = by_function(prof); total = sum(F.values())
    print(f"\n{'lo que sigue vivo después del GC' if a.vivo else 'asignado durante la carga'}: {total/2**20:.0f} MB (muestreado), por función:")
    for (fn, src), n in F.most_common(a.top):
        print(f'{n/2**20:8.1f} MB {100*n/max(1,total):5.1f} %  {fn}  {src}')

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--size', default='390x844'); ap.add_argument('--dpr', type=float, default=2)
    ap.add_argument('--vivo', action='store_true', help='solo lo que sigue vivo después de un GC forzado')
    ap.add_argument('--intervalo', type=int, default=1 << 16, help='bytes entre muestras (CDP samplingInterval)')
    ap.add_argument('--top', type=int, default=30)
    asyncio.run(main(ap.parse_args()))
