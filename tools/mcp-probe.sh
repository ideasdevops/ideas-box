#!/usr/bin/env bash
# Prueba un conector MCP como lo haría Claude Code: lo arranca con sus argumentos
# reales y le manda un `initialize`. Que el binario exista no dice nada sobre
# credenciales vencidas o dependencias rotas; esto sí.
#
#   bash tools/mcp-probe.sh <servidor> [lanzador] [claude.json]
set -uo pipefail

server="${1:?falta el nombre del servidor}"
launcher="${2:-$HOME/.config/ideasbox/launchers/$server.sh}"
claude_json="${3:-$HOME/.claude.json}"

[ -x "$launcher" ] || { echo "sin lanzador: $launcher" >&2; exit 2; }

argv=()
while IFS= read -r _a; do [ -n "$_a" ] && argv+=("$_a"); done < <(SERVER="$server" python3 -c '
import json, os, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
srv = (cfg.get("mcpServers") or {}).get(os.environ["SERVER"]) or {}
for a in srv.get("args") or []:
    print(a)
' "$claude_json")

req='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"doctor","version":"1"}}}'
resp="$(printf '%s\n' "$req" | timeout 20 "$launcher" "${argv[@]}" 2>/dev/null | head -c 4000)"

case "$resp" in
  *serverInfo*) printf '%s\n' "$resp" | head -c 300; exit 0 ;;
  *)            echo "sin respuesta válida al initialize" >&2; exit 1 ;;
esac
