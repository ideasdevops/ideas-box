#!/usr/bin/env bash
# Compatibilidad con el bash 3.2 de macOS, que no se nota probando en Linux.
# Lo corre check-leaks.sh; también se puede correr solo:
#
#   bash tools/check-bash32.sh
#
# Qué busca:
#   · una variable pegada a un carácter no ASCII ("«$name»", "$dirá"): en macOS con
#     locale UTF-8, bash 3.2 toma el primer byte como parte del nombre y, con set -u,
#     corta con "name?: unbound variable". Va con llaves: "«${name}»".
#   · mapfile/readarray, ${var,,}/${var^^} y arrays asociativos: no existen en 3.2.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

FILES=(install.sh instalar.sh bin/ideasbox "Ideas Box.command" installer/askpass.sh)
while IFS= read -r f; do FILES+=("$f"); done < <(find lib catalog/installers tools -name '*.sh' | sort)

fails=0
check() {
  local label="$1" pat="$2" out
  # Los comentarios que mencionan lo prohibido no cuentan
  out="$(LC_ALL=C grep -nP "$pat" "${FILES[@]}" 2>/dev/null | grep -v 'check-bash32.sh' \
    | LC_ALL=C grep -vP '^[^:]+:[0-9]+:\s*#' | cut -c1-160)" || true
  if [ -n "$out" ]; then
    printf '\n✗ %s\n%s\n' "$label" "$out"; fails=$((fails+1))
  else
    printf '✓ %s\n' "$label"
  fi
}

echo "Chequeo de compatibilidad con bash 3.2 (macOS)"
check 'Variables sin llaves antes de un carácter no ASCII' '\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xff]'
check 'Sin mapfile ni readarray'                           '^\s*(mapfile|readarray)\b|[;&|]\s*(mapfile|readarray)\b'
check 'Sin ${var,,} ni ${var^^}'                           '\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)'
check 'Sin arrays asociativos'                             '\b(declare|local|typeset)\s+-[a-zA-Z]*A'

echo
[ "$fails" -eq 0 ] || { echo "✗ $fails chequeos de bash 3.2 fallaron."; exit 1; }
echo "✓ Compatible con bash 3.2."
