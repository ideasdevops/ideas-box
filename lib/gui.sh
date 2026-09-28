#!/usr/bin/env bash
# Asistente gráfico de instalación.
#
#   bash install.sh --gui   (lo que corre el comando de instalación de la landing)
#
# Reparto de trabajo:
#   · gui_launch (este archivo, en la terminal): lo mínimo para poder mostrar una página
#     — herramientas de Apple en Mac, Python, cómo se va a pedir la contraseña — y
#     arranca installer/server.py, que abre el asistente en el navegador.
#   · installer/server.py sirve la interfaz (installer/web/dist, precompilada: no
#     necesita Node) y, cuando la persona confirma, corre `install.sh --gui-run` con
#     las respuestas en un archivo. La instalación es la misma de siempre.
#   · gui_run_setup (modo --gui-run): carga esas respuestas como IB_ANS_<clave>, que
#     confirm/ask/ask_secret consultan antes de preguntar (lib/common.sh). Lo que no
#     esté ahí se pregunta en el navegador con un modal.
#
# Contraseña de administrador: nunca pasa por el asistente. En Mac y en Linux con
# escritorio la pide la ventana nativa (sudo -A con installer/askpass.sh); en WSL o sin
# zenity/kdialog, se pide una vez en esta terminal antes de abrir el asistente.

GUI_DIR="$STACK_SRC/installer"
IB_REPO_URL="https://github.com/ideasdevops/ideas-box.git"

_gui_python() {
  local p
  for p in python3 /usr/bin/python3; do
    p="$(command -v "$p" 2>/dev/null)" || continue
    # En Mac, /usr/bin/python3 sin las herramientas de Apple es un stub que abre un diálogo
    "$p" -c 'import sys; sys.exit(sys.version_info < (3, 8))' >/dev/null 2>&1 && { printf '%s' "$p"; return 0; }
  done
  return 1
}

# ¿Hay una ventana nativa para pedir la contraseña?
_gui_askpass_ok() {
  is_mac && have osascript && return 0
  is_wsl && return 1
  [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || return 1
  have zenity || have kdialog
}

# Herramientas de Apple con su propia ventana: Python y git llegan con ellas, y sin
# Python no hay asistente. Se espera acá, con avisos, hasta que termine.
_gui_mac_clt() {
  _clt_ok && return 0
  info "Ideas Box necesita las herramientas de desarrollo de Apple (incluyen git y Python)."
  osascript -e 'display dialog "Para empezar, Ideas Box necesita las herramientas de desarrollo de Apple (gratis, de Apple).\n\nSe va a abrir una ventana de Apple: hacé clic en «Instalar» y aceptá la licencia. Tarda entre 5 y 15 minutos; después el asistente sigue solo." buttons {"Continuar"} default button 1 with title "Ideas Box" with icon note' >/dev/null 2>&1 || true
  xcode-select --install >/dev/null 2>&1 || true
  info "Esperando a que termine la instalación de Apple (esta ventana sigue sola)…"
  local n=0
  until _clt_ok; do
    sleep 5; n=$((n+1))
    # Cada 10 minutos, por si la ventana de Apple se cerró o falló
    if [ $((n % 120)) -eq 0 ]; then
      warn "Todavía no terminan las herramientas de Apple. Si la ventana falló, bajalas de:"
      info "  https://developer.apple.com/download/all/?q=command%20line%20tools"
    fi
  done
  ok "Herramientas de Apple instaladas"
}

# Sin ventana nativa, sudo se autoriza una vez en esta terminal y se mantiene vivo
# mientras dure el asistente (el caché de sudo es por terminal y los hijos la heredan).
_gui_sudo_terminal() {
  [ "$(id -u)" = 0 ] && return 0
  have sudo || return 0
  sudo -n true 2>/dev/null || {
    echo
    info "Ideas Box va a instalar programas del sistema. Escribí la contraseña de tu usuario"
    info "(no se ve mientras la escribís). Es la única vez que se usa esta terminal."
    sudo -v || die "Sin la contraseña no se pueden instalar los programas del sistema."
  }
  local parent=$$
  ( while kill -0 "$parent" 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) >/dev/null 2>&1 &
}

gui_launch() {
  detect_os
  is_mac && _gui_mac_clt
  local py
  if ! py="$(_gui_python)"; then
    echo
    warn "No encontré Python 3 para mostrar el asistente gráfico."
    warn "La instalación sigue acá, en la terminal, con las mismas preguntas."
    echo
    return 1
  fi
  if _gui_askpass_ok; then
    export SUDO_ASKPASS="$GUI_DIR/askpass.sh" IB_SUDO_FLAGS="-A"
  elif [ "${SKIP_DEPS:-0}" != 1 ]; then
    _gui_sudo_terminal
  fi
  local extra=()
  [ "${SKIP_DEPS:-0}" = 1 ] && extra+=(--skip-deps)
  [ "${DRY_RUN:-0}" = 1 ] && extra+=(--dry-run)
  exec "$py" "$GUI_DIR/server.py" --src "$STACK_SRC" ${extra[@]+"${extra[@]}"}
}

# Modo --gui-run: lo lanza server.py. Respuestas de los formularios → IB_ANS_*
gui_run_setup() {
  local answers="$1"
  IB_GUI=1
  [ -f "$answers" ] || die "No encuentro el archivo de respuestas del asistente: $answers"
  # shellcheck disable=SC1090
  . "$answers"
  # Homebrew: su instalador no pregunta nada con NONINTERACTIVE y usa sudo -A si hay SUDO_ASKPASS
  export NONINTERACTIVE=1
  return 0
}

# Modo --gui-probe <slug>: opciones de raíz de datos, una por línea (ruta, etiqueta,
# espacio libre, recomendada 1/0, ya existe 1/0), separadas por tabs.
gui_probe_dataroots() {
  EMPRESA_SLUG="$(slugify "${1:-mi-empresa}")"
  detect_os >/dev/null 2>&1 || true
  _data_root_candidates
  local i=0 rec
  while [ $i -lt ${#DR_PATHS[@]} ]; do
    rec=0; [ $((i+1)) = "$DR_RECOMMENDED" ] && rec=1
    printf '%s\t%s\t%s\t%s\t%s\n' "${DR_PATHS[$i]}" "${DR_LABELS[$i]}" \
      "$(_free_at "${DR_PATHS[$i]}")" "$rec" "$([ -f "${DR_PATHS[$i]}/.ideas-box" ] && echo 1 || echo 0)"
    i=$((i+1))
  done
}

# El comando de instalación baja el repo sin git cuando no lo hay (Linux mínimo): apenas
# git está disponible se lo convierte en un clon, para que `ideasbox update` funcione.
stack_git_adopt() {
  [ -d "$STACK_SRC/.git" ] && return 0
  have git || return 0
  info "Conectando la carpeta de Ideas Box con su repositorio (para las actualizaciones)"
  ( cd "$STACK_SRC" && git init -q && git remote add origin "$IB_REPO_URL" \
      && git fetch -q --depth 1 origin main && git reset -q origin/main \
      && git branch -q -M main && git branch -q --set-upstream-to=origin/main main ) \
    || { warn "No se pudo conectar con el repositorio; las actualizaciones van a pedir volver a instalar."; rm -rf "$STACK_SRC/.git"; }
  return 0
}
