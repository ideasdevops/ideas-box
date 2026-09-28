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

panel_installed() { [ -x "$PANEL_SRC/backend/venv/bin/uvicorn" ]; }

# Abre una URL en el navegador del usuario sin retener la terminal
_open_url() {
  local url="$1"
  if is_mac; then
    open "$url"
  elif is_wsl; then
    # explorer.exe devuelve 1 aunque abra bien
    if have wslview; then wslview "$url"; else explorer.exe "$url" || true; fi
  elif have xdg-open; then
    xdg-open "$url" >/dev/null 2>&1 &
  elif have gio; then
    gio open "$url" >/dev/null 2>&1 &
  else
    info "Abrí en tu navegador: $url"
  fi
  return 0
}

# Avisos del acceso directo: sin terminal (Linux), el error tiene que verse igual
_panel_notice() {
  err "$1"
  [ -t 2 ] || { have notify-send && notify-send "Panel Ideas Box" "$1" 2>/dev/null; } || true
}

# panel_open [--keep] — lo que corre el ícono «Panel Ideas Box»: levanta el panel si no
# está corriendo y lo abre en el navegador. Con --keep (WSL) se queda esperando y apaga
# el panel al cerrar la ventana.
panel_open() {
  local keep=0 started=0 url
  [ "${1:-}" = --keep ] && keep=1
  load_profile
  url="http://127.0.0.1:$PANEL_PORT"
  if ! panel_installed; then
    _panel_notice "El panel no está instalado. Instalalo desde el menú de Ideas Box o con: $STACK_NAME panel install"
    return 1
  fi
  if ! panel_is_running; then
    panel_start || { _panel_notice "El panel no pudo arrancar. Detalle: $STACK_NAME panel logs"; return 1; }
    started=1
  fi
  _open_url "$url"
  if [ "$keep" = 1 ] && [ "$started" = 1 ]; then
    trap 'panel_stop >/dev/null 2>&1; exit 0' HUP INT TERM
    echo
    echo "El panel está abierto en tu navegador ($url)."
    echo "Podés minimizar esta ventana. Al cerrarla, el panel se apaga."
    while panel_is_running; do sleep 5; done
  fi
  return 0
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
  # En --dry-run no hay perfil escrito (load_profile cortaría): alcanza con avisar
  if [ "$DRY_RUN" = 1 ]; then info "(dry-run) se instalaría el panel en $PANEL_SRC"; return 0; fi
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
  # Sin un Python que arme venvs (Ubuntu sin python3-venv) se usa un 3.12 de uv, sin sudo
  py="$(python_venv_bin)" || py="$(python_uv_312)" || die "El panel necesita Python 3.10 o posterior y no encontré ninguno. En Mac: brew install python@3.12; en Linux: sudo apt install python3-venv."
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
  ok "Panel instalado. Abrilo con el ícono «Panel Ideas Box» o con: $STACK_NAME panel open"
  panel_install_shortcut
}

panel_start() {
  load_profile
  panel_installed || die "El panel no está instalado. Corré: $STACK_NAME panel install"
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
  if ! confirm "¿Instalar el panel ahora? (compila la interfaz, tarda unos minutos)" n panel; then
    info "Panel salteado."
    return 0
  fi
  panel_install || warn "El panel no se pudo instalar. El resto del stack quedó bien; reintentá con: $STACK_NAME panel install"
}

# panel_serve — el panel en primer plano (sin nohup). Lo usa el arranque automático de
# Windows: en WSL, la distro se apaga cuando no queda ninguna sesión de wsl.exe, así que
# el acceso de Inicio de Windows mantiene abierta (minimizada) la sesión que lo corre.
panel_serve() {
  load_profile
  panel_installed || die "El panel no está instalado. Corré: $STACK_NAME panel install"
  panel_is_running && { ok "El panel ya está corriendo en http://127.0.0.1:$PANEL_PORT"; return 0; }
  run mkdir -p "$PANEL_STATE_DIR"
  echo $$ >"$PANEL_PID_FILE"
  info "Panel de Ideas Box en http://127.0.0.1:$PANEL_PORT — dejá esta ventana abierta (podés minimizarla)."
  exec "$PANEL_SRC/backend/venv/bin/uvicorn" --app-dir "$PANEL_SRC/backend" main:app \
    --host 127.0.0.1 --port "$PANEL_PORT" >>"$PANEL_LOG_FILE" 2>&1 </dev/null
}

# --- Arranque automático al iniciar sesión --------------------------------------------
# Las tareas programadas solo corren con el panel abierto. Esto lo levanta solo al entrar
# al equipo: un LaunchAgent en macOS, una entrada de autostart del escritorio en Linux y
# un acceso en la carpeta Inicio de Windows (WSL). Apagado por defecto: lo activa quien
# usa programaciones, desde el panel o con `ideasbox panel autostart on`.
PANEL_LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.ideasbox.panel.plist"
PANEL_XDG_AUTOSTART="$HOME/.config/autostart/ideasbox-panel.desktop"
PANEL_WSL_MARK="$STACK_CONFIG_DIR/autostart-windows"

panel_autostart_status() {
  if is_mac; then [ -f "$PANEL_LAUNCH_AGENT" ]
  elif is_wsl; then [ -f "$PANEL_WSL_MARK" ]
  else [ -f "$PANEL_XDG_AUTOSTART" ]
  fi
}

panel_autostart() {
  local cli="$HOME/.local/bin/$STACK_NAME"
  case "${1:-status}" in
    status)
      if panel_autostart_status; then echo on; else echo off; fi ;;
    on)
      panel_installed || die "El panel no está instalado. Corré: $STACK_NAME panel install"
      if is_mac; then
        run mkdir -p "$(dirname "$PANEL_LAUNCH_AGENT")"
        write_file "$PANEL_LAUNCH_AGENT" 644 <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.ideasbox.panel</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$cli</string><string>panel</string><string>start</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
      elif is_wsl; then
        local ps; ps="$(_wsl_powershell)" || ps=""
        [ -n "$ps" ] && have wslpath || die "No pude hablar con Windows desde Ubuntu (¿interoperabilidad de WSL desactivada?)."
        local distro="${WSL_DISTRO_NAME:+-d $WSL_DISTRO_NAME }"
        local args="${distro}--cd ~ -e bash -lic \"exec '$cli' panel serve\""
        _wsl_ps_run "$ps" "\$ErrorActionPreference = 'Stop'
\$l = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'Panel Ideas Box.lnk'))
\$l.TargetPath = Join-Path \$env:SystemRoot 'System32\\wsl.exe'
\$l.Arguments = '${args//\'/\'\'}'
\$l.WindowStyle = 7
\$l.Description = 'Panel de Ideas Box (arranque automático)'
\$l.Save()" || die "Windows no dejó crear el acceso de arranque automático."
        run touch "$PANEL_WSL_MARK"
      else
        write_file "$PANEL_XDG_AUTOSTART" 644 <<EOF
[Desktop Entry]
Type=Application
Name=Panel Ideas Box
Comment=Arranca el panel de Ideas Box al iniciar sesión (para las tareas programadas)
Exec="$cli" panel start
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
      fi
      ok "El panel va a arrancar solo al iniciar sesión."
      ;;
    off)
      if is_mac; then run rm -f "$PANEL_LAUNCH_AGENT"
      elif is_wsl; then
        local ps; ps="$(_wsl_powershell)" || ps=""
        [ -n "$ps" ] && _wsl_ps_run "$ps" "Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path ([Environment]::GetFolderPath('Startup')) 'Panel Ideas Box.lnk')" || true
        run rm -f "$PANEL_WSL_MARK"
      else run rm -f "$PANEL_XDG_AUTOSTART"
      fi
      ok "Arranque automático del panel desactivado."
      ;;
    *) die "Uso: $STACK_NAME panel autostart [on|off|status]" ;;
  esac
}

panel_main() {
  case "${1:-status}" in
    install) panel_install ;;
    start)   panel_start ;;
    open)    panel_open "${2:-}" ;;
    stop)    panel_stop ;;
    restart) panel_stop; panel_start ;;
    status)  panel_status ;;
    logs)    tail -n "${2:-40}" "$PANEL_LOG_FILE" 2>/dev/null || info "Sin log todavía." ;;
    serve)   panel_serve ;;
    autostart) panel_autostart "${2:-status}" ;;
    *) die "Uso: $STACK_NAME panel [install|open|start|stop|restart|status|logs|serve|autostart]" ;;
  esac
}
