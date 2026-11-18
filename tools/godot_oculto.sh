#!/bin/zsh
# El juego de Godot sin que se vea ni se quede con el teclado: el mismo Godot del Mac, lanzado oculto (`open -j -g`).
# Corrido directo, Godot se pone al frente al partir y le quita el teclado y el mouse a quien trabaja, aunque se le
# pida una ventana fuera de la pantalla (--position), sin foco (window/size/no_focus) o se lance con `open -g`: lo
# probamos en noviembre de 2026. Lanzado oculto, la app al frente no cambia, no aparece ninguna ventana y dibuja con la
# GPU igual: la vista inicial dio 68,1 cuadros por segundo oculta y 67,9 a la vista. Las sesiones de Claude revisan el
# juego siempre así (--png, --caminar con --png, --fps, --cine --cuadro), nunca con el binario directo.
#
#   tools/godot_oculto.sh --path juego -- --png shots/x.png [--desde x,y …]   # los mismos argumentos que Godot
#   tools/godot_oculto.sh --path juego -- --fps 6
#   make cine GODOT=tools/godot_oculto.sh
#
# `open` no le pasa al proceso ni el directorio ni el entorno: --path se vuelve absoluto y PWD va con --env (main.gd
# resuelve con él las rutas relativas de --png). La salida de Godot se junta en un archivo y se imprime al terminar.
# Sale con 1 si hubo un SCRIPT ERROR o un ERROR, o si Godot salió con error. Sin --png, --fps ni --cuadro el juego no sale
# solo: quedaría corriendo oculto (Cmd+Tab lo muestra).
set -e
app=${GODOT_APP:-/Applications/Godot.app}
args=()
while (( $# )); do
  if [[ $1 == --path && $# -ge 2 ]]; then args+=(--path ${2:A}); shift 2
  elif [[ $1 == --path=* ]]; then args+=(--path=${${1#--path=}:A}); shift
  else args+=("$1"); shift; fi
done
out=$(mktemp -t godot_oculto)
trap 'rm -f $out' EXIT
st=0
open -j -g -n -W --env PWD="$PWD" --stdout $out --stderr $out -a $app --args "${args[@]}" || st=$?
cat $out
if (( st )) || grep -qE "^(SCRIPT )?ERROR" $out; then exit 1; fi
