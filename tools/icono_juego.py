# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow==13.0.0"]
# ///
"""El ícono del juego de Godot y su lanzador de escritorio (Linux).

  uv run tools/icono_juego.py                  # juego/icono.png (256 × 256): el ícono de la ventana (config/icon de project.godot)
  uv run tools/icono_juego.py --png x.png [--escala 8]   # además, una copia ampliada para mirarlo
  uv run tools/icono_juego.py --instalar       # además, el lanzador: el menú de aplicaciones y el escritorio (make lanzador)
  uv run tools/icono_juego.py --desinstalar    # quita el lanzador y sus íconos

El ícono es pixel art de 32 × 32, como el favicon del sitio (src/site/favicon.svg, del que toma la paleta): una
tesela isométrica de la Plaza de Armas, con sus senderos en cruz, la torre de la Catedral, dos árboles y el
personaje. Se dibuja aquí con primitivas (cajas y rombos isométricos de 2:1, un sprite) y un contorno azul noche;
juego/icono.png sale ampliado sin suavizar y va en git.

--instalar escribe los íconos en ~/.local/share/icons/hicolor/<n>x<n>/apps/ (32, 64, 128 y 256 sin suavizar; 16, 24 y
48 reducidos desde 256), el lanzador talca-isometrica-juego.desktop en ~/.local/share/applications/ (el menú de
Cinnamon, GNOME, KDE) y una copia ejecutable en el escritorio (xdg-user-dir DESKTOP), que Nemo pide ejecutable.
Lanza Godot (GODOT=<ruta>, o godot o godot4 del PATH, con su ruta absoluta: el menú no siempre ve ~/.local/bin) con
--path juego/, a la vista: es para jugar, no para revisar (las sesiones de Claude usan tools/godot_oculto.sh).
StartupWMClass es config/name de project.godot, la clase que Godot da a su ventana en X11, para que el panel junte la
ventana con el lanzador. Requiere juego/mapa/ (make juego).
"""
import argparse, os, re, shutil, stat, subprocess, sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
JUEGO = ROOT / 'juego'
ICONO = JUEGO / 'icono.png'
ID = 'talca-isometrica-juego'
N = 32
# la paleta del favicon (azul noche, vino, crema, gris) y la de la plaza
C = dict(
    ol='#1F2A44',                                     # contorno
    g='#6FA046', gd='#5E8C3B', gl='#82B353',          # pasto, sus motas y el borde iluminado
    p='#E6DCC4', pd='#CBBE9F',                         # senderos de baldosa y su orilla
    sl='#5A8636', sr='#47692A',                        # el canto del pasto en los costados
    el='#A57447', er='#7E5634', ed='#6A4529',          # tierra de los costados y su veta
    wl='#F3F4EF', wr='#C9CCC0', win='#1F2A44',          # muros de la torre (crema, gris) y sus vanos
    rl='#7A1F3D', rr='#5B1730',                        # el chapitel (vino)
    t1='#3F7A35', t2='#5E9E45', t3='#2C5626', tk='#6B4A2F',   # copas y troncos
    hh='#3B2A20', sk='#E3A97E', sh='#7A1F3D', sj='#3B5A8C', sz='#262A30', ss='#4F7A31',  # el personaje y su sombra
)


def rombo(x, y, cx, cy, hw):
    """¿El píxel (x, y) cae en el rombo 2:1 de centro (cx, cy) y semiancho hw (centros en los bordes de los píxeles)?"""
    return abs(x + .5 - cx) / hw + abs(y + .5 - cy) / (hw / 2) <= 1


def dibujo():
    px = [[None] * N for _ in range(N)]

    def put(x, y, c):
        if 0 <= x < N and 0 <= y < N:
            px[y][x] = c

    # la tesela: un rombo de 30 × 16 (filas 11 a 26) y costados de 4 píxeles
    cx, cy, hw = 16, 19, 15
    for y in range(N):
        for x in range(N):
            if rombo(x, y, cx, cy, hw):
                a, b = (x + .5 - cx) / hw, (y + .5 - cy) / (hw / 2)
                s1, s2 = abs(a + b), abs(a - b)        # los dos ejes de la plaza
                if min(s1, s2) < .1:
                    c = 'p'
                elif min(s1, s2) < .17:
                    c = 'pd' if min(s1, s2) == s1 and b > 0 or min(s1, s2) == s2 and b > 0 else 'g'
                else:
                    c = 'gd' if (x * 7 + y * 13) % 11 == 0 else 'g'
                if a + b > .82 or b - a > .82:        # el borde de adelante, iluminado
                    c = 'gl' if c == 'g' else c
                put(x, y, c)
    for x in range(N):
        col = [y for y in range(N) if rombo(x, y, cx, cy, hw)]
        if not col:
            continue
        yb = max(col)
        izq = x < cx
        for d in range(1, 5):
            c = ('sl' if izq else 'sr') if d == 1 else ('el' if izq else 'er')
            if d == 3 and (x * 5) % 7 == 0:
                c = 'ed'
            put(x, yb + d, c)

    # la torre de la Catedral, atrás: caja de 8 × 4 de planta y 9 de alto, con un chapitel de vino
    tx, ty, th, thw = 16, 14, 9, 4
    for y in range(N):
        for x in range(N):
            if rombo(x, y, tx, ty - th, thw):
                put(x, y, 'wl' if x < tx else 'wr')     # la tapa la cubre el chapitel
            elif any(rombo(x, y, tx, ty - t, thw) for t in range(th)):
                put(x, y, 'wl' if x < tx else 'wr')
    for x, y in ((14, 7), (14, 8), (17, 8), (17, 9)):   # los vanos del campanario, uno por cara (bajan con el muro)
        put(x, y, 'win')
    ph = 6
    for y in range(N):
        for x in range(N):
            if any(rombo(x, y, tx, ty - th - t * .25, thw * (1 - t * .25 / ph)) for t in range(int(ph / .25))):
                put(x, y, 'rl' if x < tx else 'rr')

    # dos árboles, a los lados
    def arbol(bx, by):
        for y in range(by - 9, by - 1):
            for x in range(bx - 4, bx + 4):
                dx, dy = x + .5 - bx, y + .5 - (by - 5.5)
                if dx * dx / 14 + dy * dy / 11 <= 1:
                    c = 't1'
                    if dx + dy < -2.6:
                        c = 't2'
                    elif dx + dy > 2.6:
                        c = 't3'
                    put(x, y, c)
        for x in (bx - 1, bx):
            put(x, by - 1, 'tk')
            put(x, by - 2, 'tk')
    arbol(7, 20)
    arbol(26, 19)

    # el personaje, adelante a la izquierda del centro, con su sombra
    sprite = [
        '.hhh.',
        'hhhhh',
        'hekeh',
        '.kkk.',
        '.SSS.',
        'SSSSS',
        'kSSSk',
        '.SSS.',
        '.JJJ.',
        '.J.J.',
        '.J.J.',
        'zz.zz',
    ]
    key = {'h': 'hh', 'k': 'sk', 'e': 'sz', 'S': 'sh', 'J': 'sj', 'z': 'sz'}
    fx, fy = 14, 25                                   # fila de los zapatos y columna del centro
    for x in range(fx - 3, fx + 4):
        put(x, fy + 1, 'ss')
    for x in range(fx - 2, fx + 3):
        put(x, fy, 'ss')
    pers = set()
    for j, fila in enumerate(sprite):
        for i, ch in enumerate(fila):
            if ch != '.':
                x, y = fx - 2 + i, fy - len(sprite) + 1 + j
                put(x, y, key[ch])
                pers.add((x, y))
    # el contorno del personaje sobre la plaza, y el de todo contra el fondo
    for (x, y) in list(pers):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in pers and 0 <= q[0] < N and 0 <= q[1] < N:
                put(*q, 'ol')
    llenos = {(x, y) for y in range(N) for x in range(N) if px[y][x]}
    for (x, y) in llenos:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in llenos and 0 <= q[0] < N and 0 <= q[1] < N:
                put(*q, 'ol')
    return px


def imagen(lado):
    """El ícono de lado × lado: sin suavizar si lado es múltiplo de 32; si no, reducido desde 256."""
    px = dibujo()
    base = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    for y in range(N):
        for x in range(N):
            if px[y][x]:
                h = C[px[y][x]].lstrip('#')
                base.putpixel((x, y), tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,))
    if lado % N == 0:
        return base.resize((lado, lado), Image.NEAREST)
    return base.resize((256, 256), Image.NEAREST).resize((lado, lado), Image.LANCZOS)


def godot():
    g = os.environ.get('GODOT') or shutil.which('godot') or shutil.which('godot4')
    if not g:
        sys.exit('icono_juego.py: no hay godot ni godot4 en el PATH (o GODOT=<ruta del binario>)')
    return str(Path(g).resolve()) if os.sep in g else g


def q(s):
    """Un argumento de Exec= (Desktop Entry Specification): entre comillas si hace falta."""
    if re.fullmatch(r'[\w./+-]+', s):
        return s
    return '"' + re.sub(r'(["`$\\])', r'\\\1', s) + '"'


def escritorio():
    try:
        d = subprocess.run(['xdg-user-dir', 'DESKTOP'], capture_output=True, text=True).stdout.strip()
    except FileNotFoundError:
        d = ''
    return Path(d) if d and d != str(Path.home()) else Path.home() / 'Desktop'


def lugares():
    datos = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local' / 'share')
    return datos / 'applications' / f'{ID}.desktop', datos / 'icons' / 'hicolor', escritorio() / f'{ID}.desktop'


TAMANOS = (16, 24, 32, 48, 64, 128, 256)


def instalar():
    if sys.platform != 'linux':
        sys.exit('icono_juego.py --instalar: solo en Linux (en el Mac: Godot --path juego)')
    if not (JUEGO / 'mapa' / 'indice.json').exists():
        print('aviso: falta juego/mapa/ (make juego): el lanzador abrirá el juego sin la comuna', file=sys.stderr)
    app, temas, esc = lugares()
    for n in TAMANOS:
        d = temas / f'{n}x{n}' / 'apps'
        d.mkdir(parents=True, exist_ok=True)
        imagen(n).save(d / f'{ID}.png')
    nombre = re.search(r'^config/name="(.*)"', (JUEGO / 'project.godot').read_text(), re.M).group(1)
    g = godot()
    texto = '\n'.join([
        '[Desktop Entry]',
        'Type=Application',
        'Name=Talca Isométrica: el juego',
        'GenericName=Paseo por Talca',
        'Comment=Pasear por la comuna de Talca en tercera persona, con la Plaza de Armas en detalle',
        f'Exec={q(g)} --path {q(str(JUEGO))}',
        f'Path={JUEGO}',
        f'Icon={ID}',
        'Terminal=false',
        'Categories=Game;AdventureGame;',
        'Keywords=talca;maqueta;plaza;godot;juego;',
        'StartupNotify=true',
        f'StartupWMClass={nombre}',
        '',
    ])
    app.parent.mkdir(parents=True, exist_ok=True)
    app.write_text(texto)
    esc.parent.mkdir(parents=True, exist_ok=True)
    esc.write_text(texto)
    for f in (app, esc):
        f.chmod(f.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    for cmd in (['gio', 'set', str(esc), 'metadata::trusted', 'true'],        # GNOME y Nemo: lanzador de confianza
                ['gtk-update-icon-cache', '-f', '-t', '-q', str(temas)],       # si hay caché, sin esto no ven el ícono
                ['update-desktop-database', '-q', str(app.parent)],
                ['desktop-file-validate', str(app)]):
        if shutil.which(cmd[0]):
            r = subprocess.run(cmd, capture_output=True, text=True)
            if r.returncode or (cmd[0] == 'desktop-file-validate' and r.stdout.strip()):
                print(f'aviso: {" ".join(cmd[:2])}: {(r.stdout + r.stderr).strip()}', file=sys.stderr)
    print(f'{app}\n{esc}\n{temas}/<n>x<n>/apps/{ID}.png ({", ".join(map(str, TAMANOS))})\nExec={q(g)} --path {q(str(JUEGO))}')


def desinstalar():
    app, temas, esc = lugares()
    for f in [app, esc] + [temas / f'{n}x{n}' / 'apps' / f'{ID}.png' for n in TAMANOS]:
        if f.exists():
            f.unlink()
            print('quitado', f)
    if shutil.which('gtk-update-icon-cache') and (temas / 'icon-theme.cache').exists():
        subprocess.run(['gtk-update-icon-cache', '-f', '-t', '-q', str(temas)])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0], formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--png', help='una copia ampliada del ícono, para mirarlo')
    ap.add_argument('--escala', type=int, default=8, help='los píxeles de pantalla por píxel del ícono en --png (8)')
    ap.add_argument('--instalar', action='store_true', help='el lanzador en el menú y en el escritorio, con sus íconos')
    ap.add_argument('--desinstalar', action='store_true', help='quita el lanzador y sus íconos')
    a = ap.parse_args()
    if a.desinstalar:
        return desinstalar()
    imagen(256).save(ICONO)
    print(ICONO)
    if a.png:
        imagen(N * a.escala).save(a.png)
        print(a.png)
    if a.instalar:
        instalar()


if __name__ == '__main__':
    main()
