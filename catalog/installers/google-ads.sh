#!/usr/bin/env bash
# Compila el MCP de Google Ads (Go) en ~/.local/share/mcp-servers/goads/bin/goads
set -euo pipefail
SRC="${HOME}/.local/share/mcp-servers/goads"
command -v go >/dev/null || { echo "Falta Go (apt install golang-go)" >&2; exit 1; }
cd "$SRC"
mkdir -p bin
go build -o bin/goads ./cmd/... 2>/dev/null || go build -o bin/goads .
echo "✓ goads compilado en $SRC/bin/goads"
