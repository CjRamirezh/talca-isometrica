"""Los autos de KayKit City Builder Bits (Kay Lousberg, CC0) como triángulos en metros, para el juego (calles.gd).

  python3 tools/autos_kaykit.py bajar     # los glTF, su textura y la licencia, de GitHub -> raw/kaykit/ (una vez)
  python3 tools/autos_kaykit.py celdas    # qué celdas de la textura usa cada auto, con su color y su área (para CELDAS)
  python3 tools/autos_kaykit.py           # raw/kaykit/ -> data/autos-kaykit.json (lo copia `make juego` a juego/datos/)

Cada auto de KayKit es una carrocería y cuatro ruedas, de ~0,94 de largo, pintados con una textura de 8 × 4 franjas
de color en degradé (citybits_texture.png). Aquí se aplanan al marco de calles.gd (u a la derecha, v hacia adelante,
h desde el suelo bajo las ruedas), en metros (ESCALA, ANCHO), y cada triángulo toma el color de la textura en su
centro y un material del juego (CELDAS: pintura, vidrio, metal, emisivo). Los triángulos de la celda de la pintura
de cada modelo (PINTURA) llevan en vez de su color el factor del degradé ("f": su luminancia sobre la del centro de la
celda), y el juego los pinta con un color de COLORES_AUTO por ese factor. Así el juego no importa glTF ni texturas: los
autos pasan por Malla.cara(), con los materiales, la noche y la colisión del resto de la calle. Solo biblioteca
estándar (el PNG se decodifica aquí).
"""
import json
import pathlib
import struct
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'pipeline'))
import cli  # noqa: E402
import net  # noqa: E402

RAW = ROOT / 'raw' / 'kaykit'
OUT = ROOT / 'data' / 'autos-kaykit.json'
URL = ('https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-City-Builder-Bits-1.0/main/'
       'addons/kaykit_city_builder_bits/Assets/gltf/')
LICENCIA = ('https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-City-Builder-Bits-1.0/main/LICENSE.txt')
# los modelos que usa el juego: el de la policía es el de Nueva York (blanco y azul); Carabineros es verde
MODELOS = {'sedan': 'car_sedan', 'hatchback': 'car_hatchback', 'station': 'car_stationwagon', 'taxi': 'car_taxi'}
# la celda (columna, fila) de la pintura de cada modelo, en la textura de 8 × 4
PINTURA = {'sedan': (2, 1), 'hatchback': (4, 1), 'station': (2, 2), 'taxi': (3, 1)}
# el material de cada celda que no es pintura, y un color que reemplaza al de la textura (None: el suyo); lo que no
# está aquí, "pintura" con su color (los focos traseros rojos, los intermitentes). Las celdas, de `celdas`:
VIDRIO = '212930'  # el de las ventanas de los autos propios de calles.gd (0,13; 0,16; 0,19)
CELDAS = {(4, 0): ('pintura', None),  # neumáticos y bajos (#2a2a2a)
          (2, 0): ('metal', None),    # llantas y parachoques (#7f8a8f)
          (0, 3): ('vidrio', VIDRIO), (1, 3): ('vidrio', VIDRIO),  # las ventanas (en la textura, un vidrio café con brillos)
          (1, 0): ('vidrio', None)}   # los focos delanteros (#dde2e5)
# el letrero de techo del taxi (la celda de los focos, sobre LETRERO_H m): el amarillo del de los colectivos de calles.gd
LETRERO_H, LETRERO = 0.8, ('pintura', 'f2cc26')
ESCALA = 4.6          # metros por unidad de KayKit en largo y alto (el sedán: 4,3 m de largo)
ANCHO = 1.78 / 0.418  # y en ancho: los modelos son de juguete, anchos; el ancho de un sedán real
NC, NF = 8, 4         # columnas y filas de la textura


def png(path):
    """(ancho, alto, filas): un PNG RGBA o RGB de 8 bits sin entrelazar, decodificado a bytes por fila."""
    b = pathlib.Path(path).read_bytes()
    assert b[:8] == b'\x89PNG\r\n\x1a\n', 'no es un PNG'
    i, idat, w = 8, [], None
    while i < len(b):
        n, t = struct.unpack('>I4s', b[i:i + 8])
        d = b[i + 8:i + 8 + n]
        if t == b'IHDR':
            w, h, bits, ct, _, _, il = struct.unpack('>IIBBBBB', d)
            assert bits == 8 and ct in (2, 6) and il == 0, 'solo PNG RGB(A) de 8 bits sin entrelazar'
            bpp = 4 if ct == 6 else 3
        elif t == b'IDAT':
            idat.append(d)
        i += 12 + n
    raw = zlib.decompress(b''.join(idat))
    st = w * bpp
    filas, prev = [], bytearray(st)
    for y in range(h):
        ft, f = raw[y * (st + 1)], bytearray(raw[y * (st + 1) + 1:(y + 1) * (st + 1)])
        if ft == 1:
            for x in range(bpp, st): f[x] = (f[x] + f[x - bpp]) & 255
        elif ft == 2:
            for x in range(st): f[x] = (f[x] + prev[x]) & 255
        elif ft == 3:
            for x in range(st): f[x] = (f[x] + ((f[x - bpp] if x >= bpp else 0) + prev[x]) // 2) & 255
        elif ft == 4:
            for x in range(st):
                a = f[x - bpp] if x >= bpp else 0
                c = prev[x - bpp] if x >= bpp else 0
                p = a + prev[x] - c
                pa, pb, pc = abs(p - a), abs(p - prev[x]), abs(p - c)
                f[x] = (f[x] + (a if pa <= pb and pa <= pc else prev[x] if pb <= pc else c)) & 255
        filas.append(bytes(f))
        prev = f
    return w, h, bpp, filas


class Textura:
    def __init__(self, path):
        self.w, self.h, self.bpp, self.filas = png(path)

    def rgb(self, u, v):
        x = min(self.w - 1, max(0, int(u * self.w)))
        y = min(self.h - 1, max(0, int(v * self.h)))  # glTF: v = 0 arriba, como las filas del PNG
        f = self.filas[y]
        return tuple(f[x * self.bpp + k] / 255 for k in range(3))


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def accesor(g, buf, i):
    a = g['accessors'][i]
    bv = g['bufferViews'][a['bufferView']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}[a['type']]
    fmt = {5126: 'f', 5123: 'H', 5125: 'I', 5121: 'B'}[a['componentType']]
    sz = struct.calcsize('<' + fmt)
    st = bv.get('byteStride', n * sz)
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    return [struct.unpack_from('<' + fmt * n, buf, off + k * st) for k in range(a['count'])]


def triangulos(nombre):
    """[(p0, p1, p2, normal, uv del centro)] del modelo, en sus unidades (x, y, z de glTF), con las traslaciones
    de sus nodos (KayKit no gira ni escala los nodos: si alguno lo hace, falla)."""
    g = json.loads((RAW / f'{nombre}.gltf').read_text())
    buf = (RAW / g['buffers'][0]['uri']).read_bytes()
    out = []

    def nodo(i, t0):
        n = g['nodes'][i]
        assert 'rotation' not in n and 'scale' not in n and 'matrix' not in n, f'{nombre}: nodo {i} con giro o escala'
        t = [t0[k] + n.get('translation', [0, 0, 0])[k] for k in range(3)]
        if 'mesh' in n:
            for pr in g['meshes'][n['mesh']]['primitives']:
                P = accesor(g, buf, pr['attributes']['POSITION'])
                N = accesor(g, buf, pr['attributes']['NORMAL'])
                T = accesor(g, buf, pr['attributes']['TEXCOORD_0'])
                I = [i[0] for i in accesor(g, buf, pr['indices'])] if 'indices' in pr else list(range(len(P)))
                for k in range(0, len(I), 3):
                    a, b, c = I[k:k + 3]
                    ps = [tuple(P[j][q] + t[q] for q in range(3)) for j in (a, b, c)]
                    nn = [sum(N[j][q] for j in (a, b, c)) for q in range(3)]
                    uv = tuple(sum(T[j][q] for j in (a, b, c)) / 3 for q in range(2))
                    out.append((ps, nn, uv))
        for ch in n.get('children', []):
            nodo(ch, t)

    for r in g['scenes'][g.get('scene', 0)]['nodes']:
        nodo(r, [0, 0, 0])
    return out


def area(ps):
    a, b, c = ps
    u = [b[k] - a[k] for k in range(3)]
    v = [c[k] - a[k] for k in range(3)]
    x = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    return 0.5 * sum(q * q for q in x) ** 0.5


def celda(uv):
    return (min(NC - 1, int(uv[0] * NC)), min(NF - 1, int(uv[1] * NF)))


def celdas():
    """Por modelo: las celdas de la textura que usa, con su color medio, su área (m²) y su altura media."""
    tx = Textura(RAW / 'citybits_texture.png')
    for k, nombre in MODELOS.items():
        acc = {}
        for ps, nn, uv in triangulos(nombre):
            c = celda(uv)
            col = tx.rgb(*uv)
            a = area(ps) * ESCALA * ESCALA
            s = acc.setdefault(c, [0, [0, 0, 0], 0, 0])
            s[0] += a
            s[1] = [s[1][q] + col[q] * a for q in range(3)]
            s[2] += sum(p[1] for p in ps) / 3 * ESCALA * a
            s[3] += 1
        print(f'{k} ({nombre}), pintura {PINTURA[k]}:')
        for c, (a, col, hh, n) in sorted(acc.items(), key=lambda e: -e[1][0]):
            hexa = ''.join(f'{round(q / a * 255):02x}' for q in col)
            print(f'  celda {c}: {a:5.2f} m², {n:4d} triángulos, #{hexa}, h media {hh / a:4.2f} m'
                  f'{"  <- pintura" if c == PINTURA[k] else ""}  {CELDAS.get(c, "")}')
            # (h media: sobre el centro de los modelos de KayKit, no sobre el suelo)


def bajar():
    """Los cuatro autos (glTF y .bin), la textura y la licencia -> raw/kaykit/ (no reemplaza lo que hay)."""
    RAW.mkdir(parents=True, exist_ok=True)
    pedir = [(LICENCIA, 'LICENSE.txt'), (URL + 'citybits_texture.png', 'citybits_texture.png')]
    for n in MODELOS.values():
        pedir += [(URL + n + '.gltf', n + '.gltf'), (URL + n + '.bin', n + '.bin')]
    for url, f in pedir:
        p = RAW / f
        if p.exists():
            continue
        p.write_bytes(net.get(url))
        print(f'  {f}: {p.stat().st_size} bytes')
    lic = [ln.strip() for ln in (RAW / 'LICENSE.txt').read_text().splitlines() if 'License:' in ln]
    print(lic[0] if lic else 'raw/kaykit/LICENSE.txt sin «License:»: revísela antes de usar los modelos')


def r3(x):
    return round(x, 3)


def construir():
    """raw/kaykit/ -> data/autos-kaykit.json."""
    for n in MODELOS.values():
        cli.fail(f'falta raw/kaykit/{n}.gltf: corra `python3 tools/autos_kaykit.py bajar`') \
            if not (RAW / f'{n}.gltf').exists() else None
    tx = Textura(RAW / 'citybits_texture.png')
    out = {'fuente': 'KayKit City Builder Bits 1.0, de Kay Lousberg (www.kaylousberg.com), CC0 1.0: '
                     'github.com/KayKit-Game-Assets/KayKit-City-Builder-Bits-1.0 (tools/autos_kaykit.py)',
           'marco': 'u a la derecha, v hacia adelante, h desde el suelo; metros', 'modelos': {}}
    for k, nombre in MODELOS.items():
        ts = triangulos(nombre)
        y0 = min(p[1] for ps, _, _ in ts for p in ps)  # el suelo: lo más bajo de las ruedas
        ref = lum(tx.rgb((PINTURA[k][0] + 0.5) / NC, (PINTURA[k][1] + 0.5) / NF))
        pal, P, N, K = [], [], [], []
        idx = {}
        for ps, nn, uv in ts:
            c = celda(uv)
            col = tx.rgb(*uv)
            if c == PINTURA[k]:
                e = ('f', round(lum(col) / ref, 2))  # el factor del degradé sobre el color que elija el juego
            else:
                m, fijo = CELDAS.get(c, ('pintura', None))
                if k == 'taxi' and c == (1, 0) and min(p[1] - y0 for p in ps) * ESCALA > LETRERO_H:
                    m, fijo = LETRERO
                e = (fijo or ''.join(f'{min(255, round(q * 255)) & 0xf8:02x}' for q in col), m)
            if e not in idx:
                idx[e] = len(pal)
                pal.append({'f': e[1]} if e[0] == 'f' else {'c': e[0], 'm': e[1]})
            # glTF: x a la izquierda del auto, y arriba, z adelante -> u = -x (derecha), v = z, h = y - y0
            for p in ps:
                P += [r3(-p[0] * ANCHO), r3(p[2] * ESCALA), r3((p[1] - y0) * ESCALA)]
            n = (-nn[0] / ANCHO, nn[2] / ESCALA, nn[1] / ESCALA)
            ln = sum(q * q for q in n) ** 0.5 or 1
            N += [r3(q / ln) for q in n]
            K.append(idx[e])
        us, vs, hs = P[0::3], P[1::3], P[2::3]
        out['modelos'][k] = {'kaykit': nombre, 'caja': [min(us), min(vs), max(us), max(vs), 0, max(hs)],
                             'paleta': pal, 'p': P, 'n': N, 'k': K}
        print(f'{k}: {len(K)} triángulos, {r3(max(vs) - min(vs))} × {r3(max(us) - min(us))} × {r3(max(hs))} m, '
              f'{len(pal)} colores')
    OUT.write_text(json.dumps(out, separators=(',', ':')) + '\n')
    print(f'{OUT.relative_to(ROOT)}: {OUT.stat().st_size // 1024} KB')


if __name__ == '__main__':
    cli.run({'bajar': bajar, 'celdas': celdas}, __doc__, default=construir)
