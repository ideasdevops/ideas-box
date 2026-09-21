#!/usr/bin/env bash
# Diagnóstico del stack. Pensado para correrlo cuando "algo dejó de andar".

DOCTOR_FAILS=0
DOCTOR_WARNS=0
DOCTOR_DEEP="${DOCTOR_DEEP:-0}"

_chk()  { ok "$*"; }
_bad()  { err "$*"; DOCTOR_FAILS=$((DOCTOR_FAILS+1)); }
_warn() { warn "$*"; DOCTOR_WARNS=$((DOCTOR_WARNS+1)); }

doctor_main() {
  step "Diagnóstico del stack"

  # 1. Perfil
  if [ -f "$STACK_PROFILE" ]; then
    load_profile
    _chk "Perfil: $EMPRESA_NOMBRE ($EMPRESA_SLUG)"
  else
    _bad "No hay perfil en $STACK_PROFILE — corré install.sh"
    return 1
  fi

  # 2. Raíz de datos
  if [ -d "$DATA_ROOT" ] && [ -f "$DATA_ROOT/.ideas-box" ]; then
    local libre; libre="$(df -h --output=avail "$DATA_ROOT" 2>/dev/null | tail -1 | tr -d ' ')"
    _chk "Raíz de datos montada: $DATA_ROOT (libre: ${libre:-?})"
  elif [ -d "$DATA_ROOT" ]; then
    _bad "$DATA_ROOT existe pero no tiene la marca .ideas-box (¿disco equivocado o montaje vacío?)"
  else
    _bad "Raíz de datos NO disponible: $DATA_ROOT — si está en un disco aparte, montalo"
  fi

  # 3. Árbol canónico
  local d
  for d in agents skills memory docs; do
    if [ -d "$DATA_ROOT/.claude/$d" ]; then
      _chk "Árbol canónico: .claude/$d ($(find "$DATA_ROOT/.claude/$d" -maxdepth 2 -mindepth 1 | wc -l) entradas)"
    else
      _bad "Falta $DATA_ROOT/.claude/$d"
    fi
  done

  # 4. Runtime enlazado
  local rotos
  rotos="$(find "$CLAUDE_CONFIG_DIR/agents" "$CLAUDE_CONFIG_DIR/skills" -xtype l 2>/dev/null | wc -l)"
  if [ "$rotos" -gt 0 ]; then
    _warn "$rotos symlinks rotos en ~/.claude — corré '$STACK_NAME sync'"
  else
    local nag nsk
    nag="$(find "$CLAUDE_CONFIG_DIR/agents" -name '*.md' 2>/dev/null | wc -l)"
    nsk="$(find "$CLAUDE_CONFIG_DIR/skills" -maxdepth 2 -mindepth 2 2>/dev/null | wc -l)"
    _chk "Runtime: $nag agentes y $nsk skills enlazados"
  fi

  # 5. Claude Code
  if have claude; then
    _chk "Claude Code $(claude --version 2>/dev/null | head -1)"
  else
    _bad "No encuentro el comando 'claude' en el PATH"
  fi

  # 6. Servidores MCP
  if [ -s "$MCP_REGISTRY" ]; then
    local server id toolgroup label launcher envfile
    while IFS=$'\t' read -r server id toolgroup label; do
      launcher="$MCP_LAUNCHERS/$server.sh"
      if [ ! -x "$launcher" ]; then
        _bad "MCP $server: falta el lanzador $launcher"
        continue
      fi
      envfile="$STACK_SECRETS_DIR/$server.env"
      local sin_credenciales=0
      if [ -f "$envfile" ]; then
        local perm; perm="$(stat -c %a "$envfile")"
        [ "$perm" = 600 ] || _warn "MCP $server: $envfile tiene permisos $perm (debería ser 600)"
        if grep -qE '^[A-Z_]+=$' "$envfile"; then
          _warn "MCP $server: hay credenciales vacías en $envfile"
          sin_credenciales=1
        fi
      fi
      local cmd; cmd="$(grep -m1 '^exec ' "$launcher" | awk '{print $2}' | tr -d '"')"
      if [ -n "$cmd" ] && [ ! -x "$cmd" ]; then
        _bad "MCP $server: el ejecutable $cmd no existe o no es ejecutable"
      elif [ "$DOCTOR_DEEP" = 1 ]; then
        if bash "$STACK_SRC/tools/mcp-probe.sh" "$server" "$launcher" "$CLAUDE_JSON" >/dev/null 2>&1; then
          _chk "MCP $server ($id) responde al handshake"
        elif [ "$sin_credenciales" = 1 ]; then
          _warn "MCP $server: no arranca porque le faltan credenciales (completá $envfile)"
        else
          _bad "MCP $server: no respondió al handshake (revisá dependencias e instalación)"
        fi
      else
        _chk "MCP $server ($id) listo"
      fi
    done < "$MCP_REGISTRY"
  else
    _warn "No hay servidores MCP registrados"
  fi

  # 7. Secretos fuera de claude.json
  if [ -f "$CLAUDE_JSON" ] && python3 - "$CLAUDE_JSON" <<'PY'
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
leaks = []
for name, srv in (cfg.get("mcpServers") or {}).items():
    for k, v in (srv.get("env") or {}).items():
        if v:
            leaks.append(f"{name}.{k}")
    for a in srv.get("args") or []:
        if isinstance(a, str) and len(a) > 40 and not a.startswith("/") and not a.startswith("-"):
            leaks.append(f"{name}.args")
sys.exit(0 if leaks else 1)
PY
  then
    _warn "Hay credenciales embebidas en $CLAUDE_JSON (el stack las mantiene en $STACK_SECRETS_DIR)"
  else
    _chk "Sin credenciales embebidas en ~/.claude.json"
  fi

  echo
  if [ "$DOCTOR_FAILS" -gt 0 ]; then
    err "$DOCTOR_FAILS problemas, $DOCTOR_WARNS advertencias"
    return 1
  fi
  ok "Stack sano ($DOCTOR_WARNS advertencias)"
}
