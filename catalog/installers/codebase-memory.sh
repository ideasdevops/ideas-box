#!/usr/bin/env bash
# Descarga el binario de codebase-memory-mcp desde la release más reciente.
#
# La release publica muchos formatos para la misma plataforma (.tar.gz, .mcpb, .zip,
# variantes "-ui-" y "-portable", y un .bundle de firma por cada uno). Elegir mal deja
# un zip renombrado como si fuera un ejecutable, así que acá el orden de preferencia es
# explícito y al final se verifica que el binario realmente corra.
set -euo pipefail

REPO="DeusData/codebase-memory-mcp"
DEST="${HOME}/.local/bin/codebase-memory-mcp"
mkdir -p "$(dirname "$DEST")"

case "$(uname -m)" in
  x86_64|amd64)  plat='linux-amd64' ;;
  aarch64|arm64) plat='linux-arm64' ;;
  *) echo "Arquitectura no soportada: $(uname -m)" >&2; exit 1 ;;
esac

api="https://api.github.com/repos/$REPO/releases/latest"
assets="$(curl -fsSL -H 'Accept: application/vnd.github+json' "$api" \
  | grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4)"

pick() {  # primer asset que matchea el patrón, descartando firmas y variantes de UI
  printf '%s\n' "$assets" | grep -viE '\.(bundle|sha256|asc|sig)$' | grep -v -- '-ui-' | grep -E "$1" | head -1
}

# Preferencia: tar.gz nativo → tar.gz portable. Nunca .mcpb (es un bundle, no un binario).
url="$(pick "codebase-memory-mcp-${plat}\.tar\.gz$")"
[ -n "$url" ] || url="$(pick "codebase-memory-mcp-${plat}-portable\.tar\.gz$")"

if [ -z "$url" ]; then
  echo "No encontré un tar.gz para $plat en la última release de $REPO." >&2
  echo "Instalalo a mano desde https://github.com/$REPO/releases y volvé a correr el instalador." >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "→ Bajando $(basename "$url")"
curl -fsSL "$url" -o "$tmp/asset.tar.gz"

# Verificación de integridad si la release publica checksums
sums="$(printf '%s\n' "$assets" | grep -E '/checksums\.txt$' | head -1 || true)"
if [ -n "$sums" ] && command -v sha256sum >/dev/null; then
  curl -fsSL "$sums" -o "$tmp/checksums.txt" || true
  esperado="$(grep -F "$(basename "$url")" "$tmp/checksums.txt" 2>/dev/null | awk '{print $1}' | head -1 || true)"
  if [ -n "$esperado" ]; then
    real="$(sha256sum "$tmp/asset.tar.gz" | awk '{print $1}')"
    [ "$esperado" = "$real" ] || { echo "Checksum no coincide para $(basename "$url")" >&2; exit 1; }
    echo "→ Checksum verificado"
  fi
fi

tar -xzf "$tmp/asset.tar.gz" -C "$tmp"
bin="$(find "$tmp" -type f -name 'codebase-memory-mcp' -perm -u+x | head -1)"
[ -n "$bin" ] || bin="$(find "$tmp" -type f -name 'codebase-memory-mcp' | head -1)"
[ -n "$bin" ] || { echo "El paquete no contiene el ejecutable codebase-memory-mcp" >&2; exit 1; }

cp "$bin" "$DEST"
chmod +x "$DEST"

# Si no corre, es mejor fallar acá que dejar un archivo roto registrado como conector.
"$DEST" --version >/dev/null 2>&1 || "$DEST" version >/dev/null 2>&1 || {
  echo "El binario descargado no se ejecuta correctamente en este sistema." >&2
  exit 1
}
echo "✓ codebase-memory-mcp en $DEST"
