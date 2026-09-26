#!/usr/bin/env bash
# Renoise: plugin oficial de Claude Code (skills de dirección y producción de video) y su
# CLI nativo en ~/.local/bin/renoise. El CLI lo baja el script del propio plugin, que
# verifica la versión publicada; acá no se redistribuye nada.
set -euo pipefail
# Por HTTPS: con "owner/repo" Claude clona por SSH y falla sin una clave cargada en GitHub
MARKET_REPO="https://github.com/ArcoCodes/renoise-plugins-official.git"
PLUGIN="renoise@renoise-plugins-official"

claude_bin="$(command -v claude 2>/dev/null || true)"
[ -n "$claude_bin" ] || claude_bin="$HOME/.local/bin/claude"
[ -x "$claude_bin" ] || { echo "Falta Claude Code: Renoise se instala como plugin de Claude." >&2; exit 1; }
node_bin="${NODE_BIN:-$(command -v node 2>/dev/null || true)}"
[ -x "$node_bin" ] || { echo "Falta Node para instalar el CLI de Renoise." >&2; exit 1; }

if "$claude_bin" plugin marketplace list 2>/dev/null | grep -q 'renoise-plugins-official'; then
  "$claude_bin" plugin marketplace update renoise-plugins-official >/dev/null 2>&1 || true
else
  "$claude_bin" plugin marketplace add "$MARKET_REPO"
fi
if "$claude_bin" plugin list 2>/dev/null | grep -q "$PLUGIN"; then
  "$claude_bin" plugin update "$PLUGIN" >/dev/null 2>&1 || true
else
  "$claude_bin" plugin install "$PLUGIN" --scope user
fi

# La versión instalada del plugin trae el instalador del CLI
root="$(python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/plugins/installed_plugins.json")
try:
    e = json.load(open(p))["plugins"]["renoise@renoise-plugins-official"]
    print(e[0]["installPath"])
except Exception:
    pass
PY
)"
script="$root/skills/renoise-setup/scripts/install-cli.mjs"
[ -f "$script" ] || { echo "El plugin de Renoise quedó sin su instalador del CLI ($script)." >&2; exit 1; }
"$node_bin" "$script" --ensure
[ -x "$HOME/.local/bin/renoise" ] || { echo "El CLI de Renoise no quedó en ~/.local/bin/renoise." >&2; exit 1; }
echo "✓ Renoise: plugin $PLUGIN y CLI $("$HOME/.local/bin/renoise" version 2>/dev/null | head -1)"
