#!/usr/bin/env bash
# Instalación y registro de servidores MCP.
#
# Reglas de diseño:
#  - Ningún secreto entra en ~/.claude.json. Cada servidor arranca por un lanzador
#    en ~/.config/<stack>/launchers/ que carga su .env con permisos 600.
#  - Cada servidor instalado queda anotado en mcp-installed.tsv; de ahí salen los
#    `tools:` reales de cada agente (sin eso, un agente declara MCPs que no existen
#    y se queda sin capacidad).

MCP_REGISTRY="$STACK_CONFIG_DIR/mcp-installed.tsv"
MCP_LAUNCHERS="$STACK_CONFIG_DIR/launchers"

mcp_catalog_files() { find "$STACK_SRC/catalog/mcp" -name '*.mcp' | sort; }

# mcp_catalog_load <id> — carga un .mcp en el entorno actual
mcp_catalog_load() {
  local id="$1" f="$STACK_SRC/catalog/mcp/$1.mcp"
  [ -f "$f" ] || die "No existe el servidor MCP '$id' en el catálogo."
  # limpiar valores de una carga previa
  unset ID TITLE DESC TIER KIND REPO REF DIR BUILD CMD ARGS_JSON MULTI \
        INSTANCE_PROMPT ENV_KEYS ENV_SECRET REQUIRES_HOST NOTES TOOLGROUP \
        LAUNCH_EXTRA_ARGS INSTALL_CUSTOM LAUNCH_ENV VENDOR
  MULTI=0; REF="main"; BUILD=""; ENV_KEYS=""; ENV_SECRET=""; REQUIRES_HOST=""
  NOTES=""; LAUNCH_EXTRA_ARGS=""; INSTALL_CUSTOM=""; LAUNCH_ENV=""; VENDOR=""
  # shellcheck disable=SC1090
  . "$f"
  [ -n "${ID:-}" ] || die "Catálogo inválido: $f (falta ID)"
}

mcp_catalog_list() {
  local tier_filter="${1:-}" f
  for f in $(mcp_catalog_files); do
    ( mcp_catalog_load "$(basename "$f" .mcp)"
      [ -z "$tier_filter" ] || [ "$TIER" = "$tier_filter" ] || exit 0
      printf '  %-16s %-9s %s\n' "$ID" "[$TIER]" "$TITLE" )
  done
}

mcp_registry_add() {
  local id="$1" server="$2" toolgroup="$3" label="$4"
  [ "$DRY_RUN" = 1 ] && return 0
  mkdir -p "$(dirname "$MCP_REGISTRY")"
  touch "$MCP_REGISTRY"
  tsv_drop "$MCP_REGISTRY" "$server" > "$MCP_REGISTRY.tmp" || true
  printf '%s\t%s\t%s\t%s\n' "$server" "$id" "$toolgroup" "$label" >> "$MCP_REGISTRY.tmp"
  sort -o "$MCP_REGISTRY" "$MCP_REGISTRY.tmp"
  rm -f "$MCP_REGISTRY.tmp"
}

mcp_registry_servers_for() {   # <toolgroup> -> nombres de servidor instalados
  local tg="$1"
  [ -f "$MCP_REGISTRY" ] || return 0
  awk -F'\t' -v tg="$tg" '$3==tg {print $1}' "$MCP_REGISTRY"
}

mcp_is_installed() {
  [ -f "$MCP_REGISTRY" ] && awk -F'\t' -v s="$1" '$1==s {found=1} END{exit !found}' "$MCP_REGISTRY"
}

_mcp_fetch() {   # clona o actualiza el código fuente; deja SRC_DIR
  SRC_DIR="$STACK_MCP_SRC/${DIR:-$ID}"
  if [ -n "${REPO:-}" ]; then
    if [ -d "$SRC_DIR/.git" ]; then
      info "Actualizando $ID"
      run git -C "$SRC_DIR" fetch --quiet --depth 1 origin "$REF" || true
      run git -C "$SRC_DIR" checkout --quiet FETCH_HEAD || true
    else
      info "Clonando $ID desde $REPO"
      run mkdir -p "$(dirname "$SRC_DIR")"
      run git clone --quiet --depth 1 --branch "$REF" "$REPO" "$SRC_DIR" \
        || run git clone --quiet --depth 1 "$REPO" "$SRC_DIR" \
        || die "No se pudo clonar $REPO"
    fi
    [ "$DRY_RUN" = 1 ] || lock_record "mcp:$ID" "$(git -C "$SRC_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
  elif [ -n "${VENDOR:-}" ]; then
    info "Instalando $ID desde el repo del stack"
    run mkdir -p "$SRC_DIR"
    run rsync -a --delete --exclude venv --exclude '__pycache__' "$STACK_SRC/vendor/$VENDOR/" "$SRC_DIR/"
    lock_record "mcp:$ID" "vendor-$(cat "$STACK_SRC/VERSION" 2>/dev/null || echo 0)"
  fi
}

_mcp_build() {
  case "$KIND" in
    node)
      [ -n "$BUILD" ] || BUILD="npm install --no-audit --no-fund"
      info "Compilando $ID (node)"
      run bash -c "cd '$SRC_DIR' && PATH='$(dirname "$NODE_BIN")':\$PATH $BUILD" \
        || die "Falló la compilación de $ID"
      ;;
    python)
      info "Creando entorno Python de $ID"
      run python3 -m venv "$SRC_DIR/venv" \
        || die "No se pudo crear el entorno Python de $ID. Instalá python3-venv: sudo apt install python3-venv"
      run "$SRC_DIR/venv/bin/pip" install --quiet --upgrade pip wheel
      if [ -n "$BUILD" ]; then
        run bash -c "cd '$SRC_DIR' && $BUILD" || die "Falló la instalación de $ID"
      elif [ -f "$SRC_DIR/pyproject.toml" ] || [ -f "$SRC_DIR/setup.py" ]; then
        run "$SRC_DIR/venv/bin/pip" install --quiet "$SRC_DIR"
      elif [ -f "$SRC_DIR/requirements.txt" ]; then
        run "$SRC_DIR/venv/bin/pip" install --quiet -r "$SRC_DIR/requirements.txt"
      fi
      ;;
    binary|custom)
      [ -n "$INSTALL_CUSTOM" ] || die "$ID declara KIND=$KIND pero no define INSTALL_CUSTOM"
      info "Instalando $ID"
      run bash -c "$INSTALL_CUSTOM" || die "Falló la instalación de $ID"
      ;;
    *) die "KIND desconocido en $ID: $KIND" ;;
  esac
}

# Pide las variables de entorno declaradas y escribe el .env del servidor.
_mcp_env_wizard() {
  local server="$1" key val prompt_var envfile="$STACK_SECRETS_DIR/$server.env" body=""
  [ -n "$ENV_KEYS" ] || { MCP_ENVFILE=""; return 0; }

  if [ -f "$envfile" ] && confirm "Ya hay credenciales para $server. ¿Reusarlas?" y; then
    MCP_ENVFILE="$envfile"; return 0
  fi

  for key in $ENV_KEYS; do
    prompt_var="ENV_PROMPT_$key"
    local prompt="${!prompt_var:-$key}"
    if [[ " $ENV_SECRET " == *" $key "* ]]; then
      ask_secret "  $prompt" val
    else
      ask "  $prompt" val ""
    fi
    if [ -z "$val" ]; then
      warn "$key quedó vacío: el servidor $server va a fallar hasta que lo completes en $envfile"
    fi
    body+="$key=$(printf '%s' "$val" | sed 's/"/\\"/g')"$'\n'
  done

  run mkdir -p "$STACK_SECRETS_DIR"
  write_file "$envfile" 600 <<EOF
# Credenciales de $server — generado por el instalador. No versionar.
$body
EOF
  MCP_ENVFILE="$envfile"
}

_mcp_launcher() {   # crea el lanzador que carga el .env y ejecuta el servidor
  local server="$1" envfile="$2" cmd="$3"
  run mkdir -p "$MCP_LAUNCHERS"
  local launcher="$MCP_LAUNCHERS/$server.sh"
  local src_env="" load_env=""
  [ -n "$LAUNCH_ENV" ] && src_env="export ${LAUNCH_ENV//__SRC__/$SRC_DIR}"
  [ -n "$envfile" ] && load_env="if [ -f \"$envfile\" ]; then set -a; . \"$envfile\"; set +a; fi"
  write_file "$launcher" 700 <<EOF
#!/usr/bin/env bash
# Lanzador de $server — generado por el stack.
# Mantiene los secretos fuera de ~/.claude.json: viven en el .env de al lado, con permisos 600.
set -euo pipefail
$load_env
$src_env
export INFRA_BACKUP_ROOT="\${INFRA_BACKUP_ROOT:-$DATA_ROOT/05-OPERACIONES/backups}"
exec "$cmd" "\$@" $LAUNCH_EXTRA_ARGS
EOF
  MCP_LAUNCHER="$launcher"
}

_mcp_register_claude() {   # escribe la entrada en ~/.claude.json
  local server="$1" launcher="$2" args_json="$3"
  SERVER="$server" LAUNCHER="$launcher" ARGS="$args_json" python3 - <<'PY' | json_merge "$CLAUDE_JSON"
import json, os
args = json.loads(os.environ["ARGS"] or "[]")
print(json.dumps({"mcpServers": {os.environ["SERVER"]: {
    "type": "stdio",
    "command": os.environ["LAUNCHER"],
    "args": args,
    "env": {},
}}}))
PY
}

# mcp_install <id> [label]
mcp_install() {
  local id="$1" label="${2:-}"
  mcp_catalog_load "$id"

  local missing=()
  for b in $REQUIRES_HOST; do have "$b" || missing+=("$b"); done
  if [ ${#missing[@]} -gt 0 ]; then
    warn "$ID necesita en el sistema: ${missing[*]} — se omite."
    return 1
  fi

  local server="$ID"
  if [ "${MULTI:-0}" = 1 ]; then
    if [ -z "$label" ]; then
      ask "  ${INSTANCE_PROMPT:-Etiqueta para esta instancia}" label "$EMPRESA_SLUG"
    fi
    label="$(slugify "$label")"
    server="$ID-$label"
  fi

  _mcp_fetch
  _mcp_build
  _mcp_env_wizard "$server"

  local cmd="${CMD:-}"
  cmd="${cmd//__SRC__/$SRC_DIR}"
  cmd="${cmd//__NODE__/$NODE_BIN}"
  local args="${ARGS_JSON:-[]}"
  args="${args//__SRC__/$SRC_DIR}"

  _mcp_launcher "$server" "${MCP_ENVFILE:-}" "$cmd"
  _mcp_register_claude "$server" "$MCP_LAUNCHER" "$args"
  mcp_registry_add "$ID" "$server" "${TOOLGROUP:-$ID}" "${label:-}"

  ok "MCP listo: $server"
  [ -n "$NOTES" ] && info "   nota: $NOTES"
  return 0
}

mcp_wizard() {
  step "5/8 · Servidores MCP"
  require_cmds git python3
  local f id

  info "Instalando el núcleo (sin credenciales)"
  for f in $(mcp_catalog_files); do
    id="$(basename "$f" .mcp)"
    ( mcp_catalog_load "$id"; [ "$TIER" = core ] ) || continue
    mcp_install "$id" || true
  done

  if [ "$NON_INTERACTIVE" = 1 ]; then
    info "Modo no interactivo: los conectores de negocio se omiten (necesitan credenciales)."
    info "Agregalos después con: $STACK_NAME mcp add <id>"
    return 0
  fi

  echo
  echo "Conectores de negocio — se instalan solo los que uses. Vas a necesitar"
  echo "las credenciales a mano; podés agregarlos después con: $STACK_NAME mcp add <id>"
  echo
  for f in $(mcp_catalog_files); do
    id="$(basename "$f" .mcp)"
    mcp_catalog_load "$id"
    [ "$TIER" = negocio ] || continue
    printf '\n%s%s%s — %s\n' "$C_B" "$ID" "$C_RESET" "$DESC"
    confirm "¿Instalar $id?" n || continue
    mcp_install "$id" || continue
    # Varias cuentas del mismo conector solo se ofrecen con una persona respondiendo:
    # con --yes esto sería un bucle infinito.
    if [ "${MULTI:-0}" = 1 ] && [ "$ASSUME_YES" != 1 ]; then
      while confirm "  ¿Agregar otra cuenta o servidor de $id?" n; do
        mcp_install "$id" || break
      done
    fi
  done

  echo
  info "Opcionales disponibles (instalables después con '$STACK_NAME mcp add <id>'):"
  mcp_catalog_list opcional
}
