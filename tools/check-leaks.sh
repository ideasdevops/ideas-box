#!/usr/bin/env bash
# Verifica que el repo del stack no arrastre datos de la empresa que lo originó
# ni credenciales. Correlo antes de cada commit y antes de publicar el repo.
#
#   bash tools/check-leaks.sh [--extra "palabra1|palabra2"]

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

EXTRA=""
[ "${1:-}" = "--extra" ] && EXTRA="|${2:-}"

# Marcas de la empresa de origen y de sus clientes. Ampliable con --extra.
MARCAS='ideasdevops|datos-bkp|merchlabs|somosmerch|labinstrumental|lab-instrumental|digitaldev|sumpetrol|racturismo|huertaverde|huerta verde|luber|taker|mobility|zecat|ventura|vinodinamicos|renee fonter|poste\.io|chatwoot\.ideasdevops'
SECRETOS='EAA[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
IPS='\b(([0-9]{1,3}\.){3}[0-9]{1,3})\b'
HOMES='/home/[a-z][a-z0-9_-]*/'

EXCLUDE=(--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=venv
         --exclude-dir=__pycache__ --exclude=check-leaks.sh)

fails=0
report() {  # <etiqueta> <patrón> <nivel>
  local label="$1" pat="$2" level="$3" out
  out="$(grep -rInE "${EXCLUDE[@]}" "$pat" . 2>/dev/null)" || true
  if [ -n "$out" ]; then
    if [ "$level" = error ]; then
      printf '\n✗ %s\n%s\n' "$label" "$out"
      fails=$((fails+1))
    else
      printf '\n! %s (revisar a mano)\n%s\n' "$label" "$out"
    fi
  else
    printf '✓ %s\n' "$label"
  fi
}

echo "Chequeo de fugas en $(pwd)"
report "Sin marcas de la empresa de origen"        "(${MARCAS}${EXTRA})" error
report "Sin credenciales con formato conocido"     "($SECRETOS)"          error
report "Sin rutas absolutas de un home concreto"   "$HOMES"               error
report "Sin direcciones IP"                        "$IPS"                 warn

echo
if [ "$fails" -gt 0 ]; then
  echo "✗ $fails chequeos fallaron: el repo NO está listo para compartirse."
  exit 1
fi
echo "✓ Sin fugas detectadas."
