#!/usr/bin/env bash
# Dependencias de sistema: paquetes apt, Node, Python, Claude Code y Docker (opcional).

APT_BASE=(ca-certificates curl wget git jq unzip rsync xz-utils
          python3 python3-venv python3-pip build-essential pkg-config)
APT_MEDIA=(ffmpeg imagemagick)

SUDO=""
_need_sudo() {
  [ "$(id -u)" = 0 ] && { SUDO=""; return 0; }
  have sudo || die "Se necesita sudo para instalar paquetes del sistema. Instalalo o corré el script como root."
  SUDO="sudo"
}

apt_install() {
  local pkgs=("$@") faltan=()
  for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || faltan+=("$p")
  done
  if [ ${#faltan[@]} -eq 0 ]; then
    ok "Paquetes ya presentes: ${pkgs[*]}"
    return 0
  fi
  _need_sudo
  info "Instalando: ${faltan[*]}"
  run $SUDO apt-get update -qq
  run env DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y --no-install-recommends "${faltan[@]}"
}

# Node >= 20. Si el del sistema no alcanza, se instala uno de usuario con nvm.
NODE_MIN_MAJOR=20
NODE_BIN=""
ensure_node() {
  local v major
  if have node; then
    v="$(node -v 2>/dev/null | sed 's/^v//')"
    major="${v%%.*}"
    if [ "${major:-0}" -ge "$NODE_MIN_MAJOR" ]; then
      NODE_BIN="$(command -v node)"
      ok "Node $v en $NODE_BIN"
      return 0
    fi
    warn "Node $v es anterior a $NODE_MIN_MAJOR; se instalará una versión de usuario."
  fi

  info "Instalando Node LTS con nvm (sin sudo, en \$HOME/.nvm)"
  export NVM_DIR="$HOME/.nvm"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    run bash -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash'
  fi
  if [ "$DRY_RUN" = 1 ]; then NODE_BIN="\$HOME/.nvm/.../node"; return 0; fi
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  nvm install --lts >/dev/null
  nvm alias default 'lts/*' >/dev/null
  NODE_BIN="$(nvm which default)"
  [ -x "$NODE_BIN" ] || die "No se pudo resolver el binario de Node tras instalar nvm."
  ok "Node $("$NODE_BIN" -v) en $NODE_BIN"
}

# Claude Code. Instalador nativo oficial; npm global como plan B.
ensure_claude() {
  if have claude; then
    ok "Claude Code ya instalado ($(claude --version 2>/dev/null | head -1))"
    return 0
  fi
  info "Instalando Claude Code (instalador nativo)"
  if run bash -c 'curl -fsSL https://claude.ai/install.sh | bash'; then
    :
  else
    warn "El instalador nativo falló; intento con npm global."
    run "$NODE_BIN" "$(dirname "$NODE_BIN")/npm" install -g @anthropic-ai/claude-code \
      || run npm install -g @anthropic-ai/claude-code \
      || die "No se pudo instalar Claude Code. Instalalo a mano y volvé a correr el script."
  fi
  export PATH="$HOME/.local/bin:$PATH"
  have claude || warn "Claude quedó instalado pero no está en el PATH de esta shell. Agregá \$HOME/.local/bin a tu PATH."
}

ensure_docker() {
  if have docker; then
    ok "Docker ya instalado ($(docker --version 2>/dev/null))"
    return 0
  fi
  if ! confirm "¿Instalar Docker? (recomendado si vas a levantar servicios propios en este equipo)" n; then
    info "Docker omitido."
    return 0
  fi
  _need_sudo
  run bash -c 'curl -fsSL https://get.docker.com | sh'
  run $SUDO usermod -aG docker "$USER" || true
  warn "Cerrá sesión y volvé a entrar para que tu usuario tome el grupo docker."
}

deps_main() {
  step "1/8 · Dependencias del sistema"
  detect_os
  info "Distribución detectada: $OS_PRETTY"
  apt_install "${APT_BASE[@]}"
  if confirm "¿Instalar herramientas de media (ffmpeg, imagemagick)? Las usan los agentes de contenido y video" y; then
    apt_install "${APT_MEDIA[@]}"
  fi
  ensure_node
  ensure_claude
  ensure_docker
  lock_record "node" "$($NODE_BIN -v 2>/dev/null || echo desconocido)"
  lock_record "claude-code" "$(claude --version 2>/dev/null | head -1 || echo desconocido)"
}
