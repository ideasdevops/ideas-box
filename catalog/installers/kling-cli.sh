#!/usr/bin/env bash
# Kling CLI (paquete npm oficial, versión internacional). Su skill oficial se clona
# aparte como pack de terceros (SKILL_PACK en la ficha).
# El paquete va a una carpeta propia y ~/.local/bin/kling es un envoltorio que lo corre
# con el Node absoluto: el Node de nvm no está en el PATH de Claude Code ni del ícono.
set -euo pipefail
PKG="@klingai/cli-global"
PREFIX="$HOME/.local/share/mcp-servers/kling-cli"
node_bin="${NODE_BIN:-$(command -v node 2>/dev/null || true)}"
[ -x "$node_bin" ] || { echo "Falta Node para instalar el CLI de Kling." >&2; exit 1; }
npm_bin="$(dirname "$node_bin")/npm"
[ -x "$npm_bin" ] || npm_bin="$(command -v npm)"

mkdir -p "$PREFIX" "$HOME/.local/bin"
PATH="$(dirname "$node_bin"):$PATH" "$npm_bin" install -g --prefix "$PREFIX" \
  --registry=https://registry.npmjs.org --no-audit --no-fund "$PKG@latest" >/dev/null
entry="$(readlink -f "$PREFIX/bin/kling" 2>/dev/null || python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$PREFIX/bin/kling")"
[ -f "$entry" ] || { echo "El paquete $PKG no dejó el comando kling." >&2; exit 1; }
cat > "$HOME/.local/bin/kling" <<WRAP
#!/usr/bin/env bash
# Envoltorio de Ideas Box para el CLI de Kling ($PKG)
exec "$node_bin" "$entry" "\$@"
WRAP
chmod 755 "$HOME/.local/bin/kling"

echo "✓ Kling CLI $("$HOME/.local/bin/kling" --version 2>/dev/null | head -1)"
