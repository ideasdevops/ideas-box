#!/usr/bin/env bash
# Dependencias de sistema: paquetes, Node, Python, Claude Code y Docker (opcional).
# apt en Ubuntu/Mint/Debian, Homebrew en macOS.

# Nombre del paquete por sistema. Lo que no aparece en el mapa se llama igual en los dos.
APT_BASE=(ca-certificates curl wget git jq unzip rsync xz-utils
          python3 python3-venv python3-pip build-essential pkg-config)
BREW_BASE=(curl wget git jq xz python@3.12)      # unzip, rsync y compiladores vienen con macOS + Xcode CLT
APT_MEDIA=(ffmpeg imagemagick)
BREW_MEDIA=(ffmpeg imagemagick)

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

# Homebrew se instala sin sudo y en el home del usuario; el script oficial pide
# confirmación aparte y puede tardar varios minutos la primera vez.
ensure_brew() {
  if have brew; then
    ok "Homebrew presente ($(brew --version 2>/dev/null | head -1))"
    return 0
  fi
  warn "No hay Homebrew y macOS no trae gestor de paquetes."
  confirm "¿Instalar Homebrew ahora? (lo necesita el resto del proceso)" y \
    || die "Sin Homebrew no se pueden instalar las dependencias. Instalalo desde https://brew.sh y volvé a correr."
  run bash -c '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  # El shell actual todavía no lo tiene en el PATH
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && eval "$("$b" shellenv)" && break
  done
  have brew || die "Homebrew quedó instalado pero no está en el PATH de esta shell. Abrí una terminal nueva y volvé a correr."
}

ensure_xcode_clt() {
  xcode-select -p >/dev/null 2>&1 && { ok "Herramientas de línea de comandos de Xcode presentes"; return 0; }
  warn "Faltan las herramientas de línea de comandos de Xcode (compilador, git, make)."
  info "Se va a abrir el instalador gráfico de Apple; aceptalo y esperá a que termine."
  run xcode-select --install || true
  die "Cuando termine la instalación de Xcode CLT, volvé a correr install.sh."
}

brew_install() {
  local pkgs=("$@") faltan=()
  for p in "${pkgs[@]}"; do
    brew list --formula "$p" >/dev/null 2>&1 || faltan+=("$p")
  done
  if [ ${#faltan[@]} -eq 0 ]; then
    ok "Paquetes ya presentes: ${pkgs[*]}"
    return 0
  fi
  info "Instalando: ${faltan[*]}"
  run brew install "${faltan[@]}" || die "Falló la instalación de paquetes con Homebrew."
}

pkg_install_base()  { if is_mac; then brew_install "${BREW_BASE[@]}";  else apt_install "${APT_BASE[@]}";  fi; }
pkg_install_media() { if is_mac; then brew_install "${BREW_MEDIA[@]}"; else apt_install "${APT_MEDIA[@]}"; fi; }

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
    warn "Node $v es anterior a $NODE_MIN_MAJOR; se instalará una versión más nueva."
  fi

  if is_mac && have brew; then
    info "Instalando Node con Homebrew"
    run brew install node
    NODE_BIN="$(command -v node)"
    [ -x "$NODE_BIN" ] && { ok "Node $("$NODE_BIN" -v)"; return 0; }
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

# Claude Code. Instalador nativo oficial (soporta Linux y macOS); npm global como plan B.
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
    run npm install -g @anthropic-ai/claude-code \
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
  if is_mac; then
    info "Docker en macOS se instala como Docker Desktop, con instalador gráfico:"
    info "  https://www.docker.com/products/docker-desktop/   (o: brew install --cask docker)"
    info "No es obligatorio para el stack; instalalo si vas a levantar servicios en esta máquina."
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
  info "Sistema detectado: $OS_PRETTY"
  if is_mac; then
    ensure_xcode_clt
    ensure_brew
  fi
  pkg_install_base
  if confirm "¿Instalar herramientas de media (ffmpeg, imagemagick)? Las usan los agentes de contenido y video" y; then
    pkg_install_media
  fi
  ensure_node
  ensure_claude
  ensure_docker
  lock_record "node" "$($NODE_BIN -v 2>/dev/null || echo desconocido)"
  lock_record "claude-code" "$(claude --version 2>/dev/null | head -1 || echo desconocido)"
}
