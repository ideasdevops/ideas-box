#!/usr/bin/env bash
# Verifica que el repo no arrastre datos de terceros ni credenciales.
# Correlo antes de cada commit.
#
#   bash tools/check-leaks.sh [--extra "palabra1|palabra2"]
#
# Distingue dos cosas que no son lo mismo:
#   · nombres de CLIENTES y rutas privadas → nunca, en ningún archivo;
#   · la marca del AUTOR (IdeasDevOps) → legítima en autoría, licencia y en el
#     manual de usuario, que por definición está brandeado.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

EXTRA=""
[ "${1:-}" = "--extra" ] && EXTRA="|${2:-}"

# Nunca, en ningún lado: clientes, marcas ajenas y rutas del equipo de origen.
PROHIBIDO='merchlabs|somosmerch|labinstrumental|lab-instrumental|digitaldev|sumpetrol|racturismo|huertaverde|huerta verde|luber|taker|mobility|zecat|ventura|vinodinamicos|renee fonter|datos-bkp|chatwoot\.ideasdevops'

# Marca propia: permitida solo en autoría, licencia, URL del repo y el manual.
MARCA_PROPIA='ideasdevops'
CONTEXTO_OK='IdeasDevOps & Disruptia AI|Copyright \(c\) [0-9]{4} IdeasDevOps|github\.com[:/]ideasdevops/|^\./AUTHORS:|^\./docs/manual/'

SECRETOS='EAA[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
IPS='\b(([0-9]{1,3}\.){3}[0-9]{1,3})\b'
HOMES='/home/[a-z][a-z0-9_-]*/|/Users/[a-z][a-z0-9_-]*/'

# fonts.css son tipografías en base64: texto para grep, ruido para este chequeo.
EXCLUDE=(--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=venv
         --exclude-dir=__pycache__ --exclude=check-leaks.sh
         --exclude=fonts.css --exclude=*.pdf)

fails=0

# revisar <etiqueta> <patrón> <nivel:error|warn> [filtro-de-excepciones]
revisar() {
  local label="$1" pat="$2" level="$3" allow="${4:-}" out
  out="$(grep -rIinE "${EXCLUDE[@]}" "$pat" . 2>/dev/null)" || true
  [ -n "$allow" ] && out="$(printf '%s' "$out" | grep -vE "$allow")"
  if [ -n "$out" ]; then
    local total; total="$(printf '%s\n' "$out" | wc -l)"
    out="$(printf '%s' "$out" | cut -c1-160 | head -20)"
    [ "$total" -gt 20 ] && out="$out"$'\n'"  … y $((total-20)) coincidencias más"
    if [ "$level" = error ]; then
      printf '\n✗ %s\n%s\n' "$label" "$out"; fails=$((fails+1))
    else
      printf '\n! %s (revisar a mano)\n%s\n' "$label" "$out"
    fi
  else
    printf '✓ %s\n' "$label"
  fi
}

echo "Chequeo de fugas en $(pwd)"
revisar "Sin nombres de clientes ni rutas privadas" "(${PROHIBIDO}${EXTRA})" error
revisar "Marca propia solo donde corresponde"       "$MARCA_PROPIA"          error "$CONTEXTO_OK"
revisar "Sin credenciales con formato conocido"     "$SECRETOS"              error
revisar "Sin rutas absolutas de un home concreto"   "$HOMES"                 error
revisar "Sin direcciones IP"                        "$IPS"                   warn

echo
if [ "$fails" -gt 0 ]; then
  echo "✗ $fails chequeos fallaron: el repo NO está listo para compartirse."
  exit 1
fi
echo "✓ Sin fugas detectadas."
