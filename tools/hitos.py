# /// script
# requires-python = ">=3.10"
# dependencies = ["playwright==1.63"]
# ///
"""Los hitos uno por uno: cuánto tarda cada uno y una huella exacta de lo que dibuja y cambia, para refactorizarlos sin
cambiar nada (más fino que tools/regress.py, que solo mira siete vistas).

  uv run tools/hitos.py                         # ms de cada hito (los más caros primero)
  uv run tools/hitos.py --save shots/hitos-ref.json     # antes del cambio
  uv run tools/hitos.py --against shots/hitos-ref.json  # después: qué hito cambió y en qué parte

Carga el mapa (Map de tools/page.py, ~1 min; --gl metal, la GPU del Mac; TALCA_ESPERA=<s> alarga la espera de la
carga, 300 s por omisión) con window.__HITOS_HASH, para que buildModels guarde después de
cada hito una huella por parte (hitoClock() en src/js/45-landmarks.js: los vértices e índices nuevos de S y B, occ, el
relieve EH, MODELS, PADS, GLOW, NOLOTS, TREES, CLEAR, RAIL_BR, las marcas de las calles y los `keep` de los usos), y
con window.__KEEP, para que las mallas terminadas conserven sus arreglos: también guarda una huella de cada capa de la
escena al final de la generación (lo que los hitos registran y otros dibujan después, como los puentes de RAIL_BR, y
todo lo demás del mapa). Con --against imprime el primer hito cuya huella cambió (los siguientes suelen cambiar con
él, porque S sigue creciendo), las partes que cambiaron y las capas de la escena distintas, y sale con 1.
Los ms se miden sin la huella (que tarda segundos); con --save o --against salen igual, pero de una carga con
__KEEP. Por omisión imprime solo los ms (__stats.t.hitos), de una carga normal. Sale con 1 si hubo errores de consola.
"""
import argparse, asyncio, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from page import Map, add_page_args

# a hash of every layer of the finished scene: the attributes, index and draw range of each mesh (the strips share
# their tiles' buffers and are skipped), the matrices and colours of each InstancedMesh
SCENE = r'''(()=>{const out={};let n=0;
  const fnv=(h,a)=>{if(!a)return h;const u=new Uint8Array(a.buffer,a.byteOffset,a.byteLength);for(let i=0;i<u.length;i++)h=Math.imul(h^u[i],16777619);return h>>>0;};
  for(const top of __three.scene.children){let h=0x811c9dc5,c=0;
    top.traverse(o=>{if(!o.geometry||o.userData.strip)return;const g=o.geometry;c++;
      for(const k of Object.keys(g.attributes).sort())h=fnv(h,g.attributes[k].array);
      if(g.index)h=fnv(h,g.index.array);h=fnv(h,new Float64Array([g.drawRange.start,g.drawRange.count===Infinity?-1:g.drawRange.count]));
      if(o.isInstancedMesh){h=fnv(h,o.instanceMatrix.array);if(o.instanceColor)h=fnv(h,o.instanceColor.array);h=fnv(h,new Float64Array([o.count]));}});
    if(c)out[(top.name||top.type)+'#'+(n++)]=h.toString(16).padStart(8,'0')+'/'+c;}
  return out;})()'''

async def main(a):
    fp = a.save or a.against
    async with Map.from_args(a, init='window.__HITOS_HASH=1;window.__KEEP=1' if fp else None, ready='full', quiet=True) as m:
        r = await m.page.evaluate('({t:__hitos.t,h:__hitos.h})')
        if fp: r['scene'] = await m.page.evaluate(SCENE)
        if m.print_logs(): raise SystemExit('hitos: errores de consola')
    t = r['t']
    print(f'hitos: {sum(t.values()):.0f} ms;', ', '.join(f'{k} {v}' for k, v in sorted(t.items(), key=lambda kv: -kv[1])[:a.top]))
    if a.save:
        Path(a.save).parent.mkdir(parents=True, exist_ok=True)
        Path(a.save).write_text(json.dumps({'h': r['h'], 'scene': r['scene']}, indent=1)); print('guardado:', a.save)
    if a.against:
        ref = json.loads(Path(a.against).read_text()); bad = 0
        if list(ref['h']) != list(r['h']): print('el orden o la lista de hitos cambió:', list(r['h']))
        for k in r['h']:
            d = {p: (ref['h'].get(k, {}).get(p), v) for p, v in r['h'][k].items() if ref['h'].get(k, {}).get(p) != v}
            if d:
                print(f'{k}:', '; '.join(f'{p} {x} -> {y}' for p, (x, y) in d.items())); bad += 1
                if not a.all: break
        sd = {k: (ref['scene'].get(k), v) for k, v in r['scene'].items() if ref['scene'].get(k) != v}
        sd.update({k: (v, None) for k, v in ref['scene'].items() if k not in r['scene']})
        for k, (x, y) in sd.items(): print(f'escena {k}: {x} -> {y}')
        print('igual' if not bad and not sd else f'distinto: {bad} hito(s), {len(sd)} capa(s) de la escena')
        sys.exit(1 if bad or sd else 0)

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--save', help='guarda las huellas en este JSON')
    ap.add_argument('--against', help='compara con las huellas guardadas')
    ap.add_argument('--all', action='store_true', help='todos los hitos distintos, no solo el primero')
    ap.add_argument('--top', type=int, default=12, help='cuántos hitos imprimir (los más caros)')
    add_page_args(ap, only=('gl',))
    asyncio.run(main(ap.parse_args()))
