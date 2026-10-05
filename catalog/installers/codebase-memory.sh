#!/usr/bin/env bash
# Descarga el binario de codebase-memory-mcp desde la release más reciente.
#
# La release publica muchos formatos para la misma plataforma (.tar.gz, .mcpb, .zip,
# variantes "-ui-" y "-portable", y un .bundle de firma por cada uno). Elegir mal deja
# un zip renombrado como si fuera un ejecutable, así que acá el orden de preferencia es
# explícito y al final se verifica que el binario realmente corra.
set -euo pipefail
# Con set -e, cualquier corte inesperado tiene que dejar rastro en el log del asistente.
trap 'rc=$?; echo "codebase-memory: el instalador se cortó en la línea $LINENO (código $rc)" >&2' ERR

REPO="DeusData/codebase-memory-mcp"
DEST="${HOME}/.local/bin/codebase-memory-mcp"
mkdir -p "$(dirname "$DEST")"

case "$(uname -s)" in
  Linux)  os='linux' ;;
  Darwin) os='darwin' ;;
  *) echo "Sistema no soportado: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64)  plat="$os-amd64" ;;
  aarch64|arm64) plat="$os-arm64" ;;
  *) echo "Arquitectura no soportada: $(uname -m)" >&2; exit 1 ;;
esac

api="https://api.github.com/repos/$REPO/releases/latest"
assets="$(curl -fsSL -H 'Accept: application/vnd.github+json' "$api" \
  | grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4)"

pick() {  # primer asset que matchea el patrón, descartando firmas y variantes de UI
  # Que no haya match no es un error: macOS no tiene variante -portable, y con pipefail
  # el grep vacío tumbaba el script entero sin decir nada (Mac Apple Silicon, 2026-10-05).
  printf '%s\n' "$assets" | grep -viE '\.(bundle|sha256|asc|sig)$' | grep -v -- '-ui-' | grep -E "$1" | head -1 || true
}

# Preferencia: tar.gz nativo → tar.gz portable. Nunca .mcpb (es un bundle, no un binario).
# El nativo se enlaza contra una glibc reciente (2.38 en v0.11.0): en Ubuntu 22.04,
# Pop!_OS 22.04, Debian 12 y afines no arranca. El portable es estático y corre en
# cualquier Linux, así que si el nativo falla se prueba ese antes de rendirse.
candidatos="$(pick "codebase-memory-mcp-${plat}\.tar\.gz$"; pick "codebase-memory-mcp-${plat}-portable\.tar\.gz$")"

if [ -z "$candidatos" ]; then
  echo "No encontré un tar.gz para $plat en la última release de $REPO." >&2
  echo "Instalalo a mano desde https://github.com/$REPO/releases y volvé a correr el instalador." >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Verificación de integridad si la release publica checksums. macOS no trae sha256sum, sí shasum.
sums="$(printf '%s\n' "$assets" | grep -E '/checksums\.txt$' | head -1 || true)"
if command -v sha256sum >/dev/null; then sha256() { sha256sum "$1"; }
else sha256() { shasum -a 256 "$1"; }
fi
[ -z "$sums" ] || curl -fsSL "$sums" -o "$tmp/checksums.txt" || true

corre() { "$1" --version >/dev/null 2>&1 || "$1" version >/dev/null 2>&1; }

# Baja, verifica y extrae un candidato; deja el ejecutable en $tmp/<n>/codebase-memory-mcp.
prueba() {  # $1 = url, $2 = subcarpeta de trabajo
  dir="$tmp/$2"; mkdir -p "$dir"
  echo "→ Bajando $(basename "$1")"
  curl -fsSL "$1" -o "$dir/asset.tar.gz" || { echo "No pude bajar $(basename "$1")" >&2; return 1; }
  esperado="$(grep -F "$(basename "$1")" "$tmp/checksums.txt" 2>/dev/null | awk '{print $1}' | head -1 || true)"
  if [ -n "$esperado" ]; then
    real="$(sha256 "$dir/asset.tar.gz" | awk '{print $1}')"
    # Un checksum que no coincide es motivo para cortar todo, no para probar otro asset.
    [ "$esperado" = "$real" ] || { echo "Checksum no coincide para $(basename "$1")" >&2; exit 1; }
    echo "→ Checksum verificado"
  fi
  tar -xzf "$dir/asset.tar.gz" -C "$dir"
  bin="$(find "$dir" -type f -name 'codebase-memory-mcp' -perm -u+x | head -1)"
  [ -n "$bin" ] || bin="$(find "$dir" -type f -name 'codebase-memory-mcp' | head -1)"
  [ -n "$bin" ] || { echo "El paquete no contiene el ejecutable codebase-memory-mcp" >&2; return 1; }
  chmod +x "$bin"
  # macOS: lo mismo que hace el instalador oficial (sacar la cuarentena y re-firmar ad hoc),
  # para que Gatekeeper no mate el binario al primer arranque.
  if [ "$os" = darwin ]; then
    xattr -d com.apple.quarantine "$bin" >/dev/null 2>&1 || true
    codesign --sign - --force "$bin" >/dev/null 2>&1 || true
  fi
  corre "$bin"
}

n=0; elegido=''
for url in $candidatos; do
  n=$((n + 1))
  if prueba "$url" "$n"; then elegido="$bin"; break; fi
  echo "→ $(basename "$url") no corre en este sistema; pruebo la siguiente variante" >&2
done

# Si ninguno corre, es mejor fallar acá que dejar un archivo roto registrado como conector.
if [ -z "$elegido" ]; then
  echo "El binario descargado no se ejecuta correctamente en este sistema." >&2
  if [ "$os" = darwin ]; then
    min=15; [ "$plat" = darwin-arm64 ] && min=14
    echo "En esta Mac codebase-memory pide macOS $min o posterior (este equipo tiene $(sw_vers -productVersion 2>/dev/null))." >&2
    echo "Si no podés actualizar macOS, Ideas Box funciona igual sin este conector." >&2
  fi
  exit 1
fi

cp "$elegido" "$DEST"
chmod +x "$DEST"
echo "✓ codebase-memory-mcp en $DEST"
