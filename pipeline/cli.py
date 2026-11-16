"""The command line of the pipeline's scripts: one way to name a command, pass its arguments and its flags.

  if __name__ == '__main__': cli.run({'check': cmd_check, 'osm': cmd_osm}, __doc__)

argv[1] names the command (or, with `default`, anything else goes to that function whole). The function's signature
is the syntax:
  - its positional parameters are the arguments, checked for their number (`*args` takes the rest), converted by
    their annotation when it is a type (int, float);
  - its keyword-only parameters are the flags, `--name value` or `--name=value` (dashes for underscores; a trailing one, as in map_, dropped), converted by
    their annotation; one whose default is False is a switch (`--name`); a tuple annotation (float, float) takes that
    many values (`--origin 10 20`); maybe(type, value) is a flag whose value may be left out (`--geo`, `--geo 150`,
    `--rejilla=5`): absent it is the default, alone `value`, else the value given (the next argument is taken when it
    converts to the type);
  - a flag the function does not take, too few or too many arguments, or a value that does not convert end with the
    usage (the module's docstring) and exit code 1; -h or --help print it and exit 0.
"""
import inspect, sys

class maybe:
    """A flag whose value may be left out: absent -> the parameter's default, alone -> `value`."""
    def __init__(self, type=str, value=True): self.type, self.value = type, value

def _conv(f, ann, v, what):
    if ann in (int, float) or isinstance(ann, maybe) and ann.type in (int, float):
        try: return (ann.type if isinstance(ann, maybe) else ann)(v)
        except ValueError: fail(f'{what}: {v!r} no es un número')
    return v

def fail(msg, doc=None):
    raise SystemExit(f'{msg}\n\n{doc.strip()}' if doc else msg)

def call(f, args, doc=''):
    """Call f with the command-line arguments `args`, by its signature (see the module's docstring)."""
    sig = inspect.signature(f); P = list(sig.parameters.values())
    pos = [p for p in P if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
    star = next((p for p in P if p.kind == p.VAR_POSITIONAL), None)
    flags = {p.name.rstrip('_').replace('_', '-'): p for p in P if p.kind == p.KEYWORD_ONLY}   # map_ -> --map
    vals, kw, i = [], {}, 0
    while i < len(args):
        a = args[i]; i += 1
        if not a.startswith('--') or a == '--':
            vals.append(a); continue
        name, eq, v = a[2:].partition('=')
        p = flags.get(name)
        if p is None: fail(f'opción desconocida: --{name}' + (f" (acepta: {', '.join('--' + k for k in flags)})" if flags else ' (no acepta opciones)'), doc)
        ann = p.annotation
        if isinstance(ann, maybe):
            if eq: kw[p.name] = _conv(f, ann, v, f'--{name}')
            elif i < len(args) and not args[i].startswith('--') and (ann.type is str or _num(args[i], ann.type)):
                kw[p.name] = _conv(f, ann, args[i], f'--{name}'); i += 1
            else: kw[p.name] = ann.value
        elif p.default is False:
            if eq: fail(f'--{name} no lleva valor', doc)
            kw[p.name] = True
        elif isinstance(ann, tuple):
            got = [v] if eq else []
            while len(got) < len(ann) and i < len(args): got.append(args[i]); i += 1
            if len(got) < len(ann): fail(f'--{name} lleva {len(ann)} valores', doc)
            kw[p.name] = tuple(_conv(f, t, x, f'--{name}') for t, x in zip(ann, got))
        else:
            if not eq:
                if i == len(args): fail(f'--{name} lleva un valor', doc)
                v = args[i]; i += 1
            kw[p.name] = _conv(f, ann, v, f'--{name}')
    need = [p for p in pos if p.default is p.empty]
    if len(vals) < len(need) or (not star and len(vals) > len(pos)):
        n = f'{len(need)}' + ('' if len(need) == len(pos) and not star else f' a {len(pos)}' if not star else ' o más')
        fail(f'{f.__name__.removeprefix("cmd_")}: lleva {n} argumentos, recibió {len(vals)}' + (f": {' '.join(vals)}" if vals else ''), doc)
    conv = [_conv(f, pos[k].annotation if k < len(pos) else star.annotation, v, pos[k].name if k < len(pos) else star.name) for k, v in enumerate(vals)]
    return f(*conv, **kw)

def _num(s, t):
    try: t(s); return True
    except ValueError: return False

def run(cmds, doc, argv=None, default=None):
    """Dispatch argv (sys.argv[1:]) to cmds[argv[0]](…), or to default(…) with every argument when argv[0] is not a
    command (default=None: that is an error). No arguments run default, or print the usage and exit 1."""
    a = sys.argv[1:] if argv is None else list(argv)
    if a and a[0] in ('-h', '--help'): print(doc.strip()); sys.exit(0)
    if a and a[0] in cmds: return call(cmds[a[0]], a[1:], doc)
    if default: return call(default, a, doc)
    fail(f'comando desconocido: {a[0]} (comandos: {", ".join(cmds)})' if a else 'falta el comando', doc)
