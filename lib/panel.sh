#!/usr/bin/env bash
# Panel de control local: tablero de tareas para los agentes, con el catálogo
# de agentes, skills y servidores del stack.
#
#   · El código vive en vendor/panel y se copia a $PANEL_SRC al instalar.
#   · Las tareas se guardan en la raíz de datos, no en el home: son datos de la
#     empresa y tienen que viajar con el backup.
#   · No se expone a la red. Escucha en 127.0.0.1 y no tiene autenticación
#     porque no la necesita: es una herramienta de un puesto de trabajo.

PANEL_SRC="${PANEL_SRC:-$HOME/.local/share/$STACK_NAME/panel}"
PANEL_STATE_DIR="${PANEL_STATE_DIR:-$HOME/.local/state/$STACK_NAME}"
PANEL_PID_FILE="$PANEL_STATE_DIR/panel.pid"
PANEL_LOG_FILE="$PANEL_STATE_DIR/panel.log"
PANEL_ENV_FILE="$STACK_SECRETS_DIR/panel.env"
PANEL_PORT="${PANEL_PORT:-8420}"

panel_is_running() {
  [ -f "$PANEL_PID_FILE" ] || return 1
  local pid; pid="$(cat "$PANEL_PID_FILE" 2>/dev/null)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

panel_env_seed() {
  [ -f "$PANEL_ENV_FILE" ] && return 0
  run mkdir -p "$STACK_SECRETS_DIR"
  write_file "$PANEL_ENV_FILE" 600 <<'EOF'
# Credenciales del panel. Todo es opcional: sin nada configurado el tablero
# funciona igual, solo quedan apagados el chat y la redacción automática.

# Chat en lenguaje natural y redacción de contenido (openrouter.ai)
OPENROUTER_API_KEY=""
OPENROUTER_MODEL="openai/gpt-4o-mini"

# Aviso de "tarea lista para revisar": webhook | evolution | none
NOTIFY_CHANNEL=""

# Canal webhook: sirve para Slack, Discord, n8n o cualquier endpoint HTTP
NOTIFY_WEBHOOK_URL=""

# Canal evolution: WhatsApp por Evolution API
EVOLUTION_API_URL=""
EVOLUTION_API_KEY=""
EVOLUTION_INSTANCE=""
NOTIFY_WHATSAPP_NUMBER=""
EOF
  ok "Credenciales del panel: $PANEL_ENV_FILE (todas opcionales)"
}

panel_install() {
  load_profile
  [ -d "$DATA_ROOT" ] || die "La raíz de datos no está disponible: $DATA_ROOT"

  step "Panel de control"

  info "Copiando el panel a $PANEL_SRC"
  run mkdir -p "$PANEL_SRC"
  run rsync -a --delete \
    --exclude venv --exclude node_modules --exclude __pycache__ --exclude dist \
    "$STACK_SRC/vendor/panel/" "$PANEL_SRC/"

  info "Entorno Python del panel"
  local py
  py="$(python_venv_bin)" || die "El panel necesita Python 3.10 o posterior y no encontré ninguno. En Mac: brew install python@3.12; en Linux: sudo apt install python3-venv."
  run "$py" -m venv "$PANEL_SRC/backend/venv" \
    || die "No se pudo crear el entorno Python. Instalá python3-venv: sudo apt install python3-venv"
  pip_platform_constraints
  run "$PANEL_SRC/backend/venv/bin/pip" install --quiet --upgrade pip wheel
  run "$PANEL_SRC/backend/venv/bin/pip" install --quiet -r "$PANEL_SRC/backend/requirements.txt" \
    || die "No se pudieron instalar las dependencias del panel"

  info "Compilando la interfaz (puede tardar un par de minutos la primera vez)"
  local node_dir; node_dir="$(dirname "${NODE_BIN:-$(command -v node)}")"
  run bash -c "cd '$PANEL_SRC/frontend' && PATH='$node_dir':\$PATH npm install --no-audit --no-fund --silent" \
    || die "Falló npm install del panel"
  run bash -c "cd '$PANEL_SRC/frontend' && PATH='$node_dir':\$PATH npm run build" \
    || die "Falló la compilación de la interfaz del panel"

  panel_env_seed
  run mkdir -p "$DATA_ROOT/05-OPERACIONES/panel"
  ok "Panel instalado. Levantalo con: $STACK_NAME panel start"
}

panel_start() {
  load_profile
  [ -x "$PANEL_SRC/backend/venv/bin/uvicorn" ] \
    || die "El panel no está instalado. Corré: $STACK_NAME panel install"
  if panel_is_running; then
    ok "El panel ya está corriendo en http://127.0.0.1:$PANEL_PORT"
    return 0
  fi
  [ -d "$DATA_ROOT" ] || die "La raíz de datos no está disponible: $DATA_ROOT"

  run mkdir -p "$PANEL_STATE_DIR"
  if [ "${DRY_RUN:-0}" = 1 ]; then
    info "(dry-run) uvicorn en 127.0.0.1:$PANEL_PORT"
    return 0
  fi

  # Sin `cd` y sin subshell: así $! es el PID real de uvicorn y no el de un
  # shell intermedio. stdin cerrado y salida al log para que el proceso no
  # retenga la terminal de quien lo lanzó.
  local arranque="nohup"
  have setsid && arranque="setsid nohup"
  $arranque "$PANEL_SRC/backend/venv/bin/uvicorn" \
    --app-dir "$PANEL_SRC/backend" main:app \
    --host 127.0.0.1 --port "$PANEL_PORT" >>"$PANEL_LOG_FILE" 2>&1 </dev/null &
  echo $! >"$PANEL_PID_FILE"

  # Darle margen a que levante: si el puerto está tomado o falta una
  # dependencia, muere enseguida y conviene decirlo ahora, no dejar un PID muerto.
  local intento=0
  while [ "$intento" -lt 20 ]; do
    if curl -fsS -m 2 "http://127.0.0.1:$PANEL_PORT/api/health" >/dev/null 2>&1; then
      ok "Panel en http://127.0.0.1:$PANEL_PORT"
      return 0
    fi
    panel_is_running || break
    intento=$((intento+1))
    sleep 1
  done
  rm -f "$PANEL_PID_FILE"
  err "El panel no llegó a levantar. Últimas líneas de $PANEL_LOG_FILE:"
  tail -n 15 "$PANEL_LOG_FILE" >&2 2>/dev/null || true
  return 1
}

panel_stop() {
  if ! panel_is_running; then
    info "El panel no estaba corriendo."
    rm -f "$PANEL_PID_FILE"
    return 0
  fi
  local pid; pid="$(cat "$PANEL_PID_FILE")"
  run kill "$pid"
  rm -f "$PANEL_PID_FILE"
  ok "Panel detenido."
}

panel_status() {
  load_profile
  if panel_is_running; then
    printf '  panel    corriendo (pid %s) en http://127.0.0.1:%s\n' "$(cat "$PANEL_PID_FILE")" "$PANEL_PORT"
  elif [ -x "$PANEL_SRC/backend/venv/bin/uvicorn" ]; then
    printf '  panel    instalado, detenido\n'
  else
    printf '  panel    no instalado (%s panel install)\n' "$STACK_NAME"
  fi
}

# Paso opcional del instalador: compilar la interfaz tarda y no todo el mundo
# quiere el panel, así que se pregunta en vez de asumir.
panel_wizard() {
  step "Panel de control local (opcional)"
  cat <<TXT

Un tablero web en tu máquina para programar tareas a los agentes, con el
catálogo de agentes, skills y servidores del stack ya enchufado.
Se puede instalar después con: $STACK_NAME panel install

TXT
  if ! confirm "¿Instalar el panel ahora? (compila la interfaz, tarda unos minutos)" n; then
    info "Panel salteado."
    return 0
  fi
  panel_install || warn "El panel no se pudo instalar. El resto del stack quedó bien; reintentá con: $STACK_NAME panel install"
}

panel_main() {
  case "${1:-status}" in
    install) panel_install ;;
    start)   panel_start ;;
    stop)    panel_stop ;;
    restart) panel_stop; panel_start ;;
    status)  panel_status ;;
    logs)    tail -n "${2:-40}" "$PANEL_LOG_FILE" 2>/dev/null || info "Sin log todavía." ;;
    *) die "Uso: $STACK_NAME panel [install|start|stop|restart|status|logs]" ;;
  esac
}
