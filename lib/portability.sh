#!/usr/bin/env bash
# Capa de compatibilidad Linux / macOS.
#
# macOS trae utilidades BSD y un bash de 2007: no tiene `readlink -f`, `stat -c`,
# `df --output`, `find -xtype`, `grep -P`, `mapfile` ni `${var,,}`. En vez de
# repartir condicionales por todo el código, cada diferencia se resuelve una vez acá.

os_detect_kernel() {
  case "$(uname -s)" in
    Darwin) STACK_OS=macos ;;
    Linux)  STACK_OS=linux ;;
    *)      STACK_OS=desconocido ;;
  esac
  export STACK_OS
}
os_detect_kernel

is_mac() { [ "$STACK_OS" = macos ]; }

# path_resolve <ruta> — equivalente portable de `readlink -f`
path_resolve() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p" 2>/dev/null && return 0
  fi
  # Resolución manual: sigue symlinks hasta el destino final
  local dir base
  while [ -L "$p" ]; do
    dir="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$dir/$p" ;; esac
  done
  dir="$(cd "$(dirname "$p")" && pwd)"
  base="$(basename "$p")"
  printf '%s/%s\n' "$dir" "$base"
}

# perm_of <archivo> — permisos en octal (644, 600...)
perm_of() {
  if is_mac; then stat -f '%Lp' "$1" 2>/dev/null
  else            stat -c '%a'  "$1" 2>/dev/null
  fi
}

# avail_of <ruta> — espacio libre legible del sistema de archivos que la contiene
avail_of() {
  df -h "$1" 2>/dev/null | awk 'NR==2 {print $4}'
}

# broken_links <dir...> — lista symlinks rotos (BSD find no tiene -xtype)
broken_links() {
  local d
  for d in "$@"; do
    [ -d "$d" ] || continue
    find "$d" -maxdepth 1 -type l 2>/dev/null | while IFS= read -r l; do
      [ -e "$l" ] || printf '%s\n' "$l"
    done
  done
}

# lower <texto> — bash 3.2 no tiene ${var,,}. Solo ASCII: para texto acentuado,
# componer con deaccent (tr no baja de caja los multibyte: "SÍ" quedaría "sÍ").
lower() { printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'; }

# normaliza <texto> — minúsculas y sin acentos, para comparar respuestas del usuario
normaliza() { lower "$(deaccent "$1")"; }

# tsv_drop <archivo> <clave> — imprime el TSV sin la fila cuya 1ª columna sea la clave
# (reemplaza `grep -vP "^\Qclave\E\t"`, que no existe en BSD grep)
tsv_drop() {
  local f="$1" key="$2"
  [ -f "$f" ] || return 0
  awk -F'\t' -v k="$key" '$1 != k' "$f"
}

# deaccent <texto> — transliteración mínima; el //TRANSLIT de iconv no es fiable en macOS
deaccent() {
  printf '%s' "$1" | sed \
    -e 'y/áàäâãÁÀÄÂÃ/aaaaaAAAAA/' \
    -e 'y/éèëêÉÈËÊ/eeeeEEEE/' \
    -e 'y/íìïîÍÌÏÎ/iiiiIIII/' \
    -e 'y/óòöôõÓÒÖÔÕ/oooooOOOOO/' \
    -e 'y/úùüûÚÙÜÛ/uuuuUUUU/' \
    -e 'y/ñÑçÇ/nNcC/'
}

# tz_current — zona horaria del sistema
tz_current() {
  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl show -p Timezone --value 2>/dev/null && return 0
  fi
  if [ -L /etc/localtime ]; then
    # /etc/localtime -> /var/db/timezone/zoneinfo/America/Argentina/Mendoza
    path_resolve /etc/localtime | sed -E 's|.*/zoneinfo/||'
    return 0
  fi
  printf 'UTC\n'
}
