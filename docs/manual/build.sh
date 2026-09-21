#!/usr/bin/env bash
# Genera el PDF del manual a partir de manual.html.
#
#   bash docs/manual/build.sh
#
# No necesita red: las tipografías ya están embebidas en assets/fonts.css y los
# logos son PNG locales. Solo requiere un Chromium o Chrome instalado.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
SALIDA="Manual-Ideas-Box.pdf"

navegador=""
for c in chromium chromium-browser google-chrome google-chrome-stable \
         "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
  if command -v "$c" >/dev/null 2>&1; then navegador="$c"; break; fi
  if [ -x "$c" ]; then navegador="$c"; break; fi
done
[ -n "$navegador" ] || { echo "No encontré Chromium ni Chrome para generar el PDF." >&2; exit 1; }

perfil="$(mktemp -d)"
trap 'rm -rf "$perfil"' EXIT

"$navegador" --headless --disable-gpu --no-sandbox \
  --user-data-dir="$perfil" \
  --no-pdf-header-footer \
  --virtual-time-budget=10000 \
  --print-to-pdf="$SALIDA" \
  "manual.html" 2>/dev/null

[ -s "$SALIDA" ] || { echo "El PDF salió vacío." >&2; exit 1; }
echo "✓ $SALIDA  ($(du -h "$SALIDA" | cut -f1))"
