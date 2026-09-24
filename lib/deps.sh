#!/usr/bin/env bash
# Dependencias de sistema: paquetes, Node, Python, Claude Code y Docker (opcional).
# apt en Ubuntu/Mint/Debian, Homebrew en macOS. En los Mac donde Homebrew ya no se
# instala (Intel, o macOS viejo) lo imprescindible se baja suelto a ~/.local/bin.

# Nombre del paquete por sistema. Lo que no aparece en el mapa se llama igual en los dos.
APT_BASE=(ca-certificates curl wget git jq unzip rsync xz-utils
          python3 python3-venv python3-pip build-essential pkg-config)
BREW_BASE=(curl wget git jq xz python@3.12)      # unzip, rsync y compiladores vienen con macOS + Xcode CLT
APT_MEDIA=(ffmpeg imagemagick)
BREW_MEDIA=(ffmpeg imagemagick)

# Mínimos de macOS que imponen otros, no nosotros:
# - Claude Code publica binarios compilados para macOS 13.0 en adelante; en 12 no arranca.
# - El install.sh oficial de Homebrew aborta en Intel y por debajo de su
#   MACOS_OLDEST_SUPPORTED (15.0 a septiembre de 2026). Un Homebrew ya instalado sigue sirviendo.
# - Node 24 pide macOS 13.5; Node 22 corre desde macOS 11.
CLAUDE_MACOS_MIN=13
BREW_MACOS_MIN=15
MAC_NOBREW=0
USER_BIN="$HOME/.local/bin"

# mac_version_ge <mayor> [menor] — compara contra la versión de macOS en curso
mac_version_ge() {
  local v maj min rest
  v="$(sw_vers -productVersion 2>/dev/null || echo 0)"
  maj="${v%%.*}"
  case "$v" in *.*) rest="${v#*.}"; min="${rest%%.*}" ;; *) min=0 ;; esac
  case "$maj" in ''|*[!0-9]*) maj=0 ;; esac
  case "$min" in ''|*[!0-9]*) min=0 ;; esac
  [ "$maj" -gt "$1" ] || { [ "$maj" -eq "$1" ] && [ "$min" -ge "${2:-0}" ]; }
}

# Se corta antes de instalar nada: sin Claude Code el resto del stack no tiene quién lo use.
macos_preflight() {
  mac_version_ge "$CLAUDE_MACOS_MIN" && return 0
  err "macOS $OS_VERSION es anterior a macOS $CLAUDE_MACOS_MIN, el mínimo que pide Claude Code."
  err "En este equipo Claude Code no arranca, así que no tiene sentido seguir con la instalación."
  info "Salidas posibles:"
  info "  1. Instalar Ubuntu, Linux Mint o Debian en este equipo: Ideas Box corre completo ahí."
  info "  2. Subir de versión de macOS. Si Apple ya no la ofrece para este modelo, existe"
  info "     OpenCore Legacy Patcher (no oficial): https://dortania.github.io/OpenCore-Legacy-Patcher/"
  info "  3. Instalar Ideas Box en otro equipo."
  exit 1
}

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
# Si Homebrew no se puede instalar en este Mac, deja MAC_NOBREW=1 y el resto de las
# funciones toman el camino sin gestor.
ensure_brew() {
  _brew_to_path
  if have brew; then
    ok "Homebrew presente ($(brew --version 2>/dev/null | head -1))"
    return 0
  fi
  if [ "$(uname -m)" != arm64 ] || ! mac_version_ge "$BREW_MACOS_MIN"; then
    warn "Homebrew ya no se puede instalar en este Mac: solo soporta Apple Silicon con macOS $BREW_MACOS_MIN o posterior."
    info "Sigo sin gestor de paquetes: lo imprescindible se instala en $USER_BIN, sin sudo."
    MAC_NOBREW=1
    return 0
  fi
  warn "No hay Homebrew y macOS no trae gestor de paquetes."
  confirm "¿Instalar Homebrew ahora? (lo necesita el resto del proceso)" y \
    || die "Sin Homebrew no se pueden instalar las dependencias. Instalalo desde https://brew.sh y volvé a correr."
  run bash -c '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  [ "$DRY_RUN" = 1 ] && return 0
  _brew_to_path
  have brew || die "Homebrew quedó instalado pero no está en el PATH de esta shell. Abrí una terminal nueva y volvé a correr."
}

# Un Homebrew recién instalado, o uno que el perfil de la shell no carga, no está en el PATH
_brew_to_path() {
  have brew && return 0
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && eval "$("$b" shellenv)" && return 0
  done
  return 0
}

# --- Mac sin Homebrew -------------------------------------------------------
# git, curl, rsync y unzip vienen con macOS y las herramientas de Xcode; wget y xz
# no los usa nadie del stack. Faltan jq y un Python que alcance para los conectores.

# Los servidores MCP en Python piden 3.10 o posterior; el de Xcode CLT es 3.9.
python_ok() {
  have python3 && python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null
}

nobrew_jq() {
  have jq && { ok "jq presente ($(jq --version 2>/dev/null))"; return 0; }
  local arch=amd64 base="https://github.com/jqlang/jq/releases/latest/download" tmp esperado real
  [ "$(uname -m)" = arm64 ] && arch=arm64
  info "Instalando jq en $USER_BIN"
  if [ "$DRY_RUN" = 1 ]; then run curl -fsSL -o "$USER_BIN/jq" "$base/jq-macos-$arch"; return 0; fi
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/jq" "$base/jq-macos-$arch" && curl -fsSL -o "$tmp/sums" "$base/sha256sum.txt" \
    || { rm -rf "$tmp"; die "No se pudo bajar jq desde GitHub."; }
  esperado="$(awk -v f="jq-macos-$arch" '$2 == f { print $1 }' "$tmp/sums")"
  real="$(shasum -a 256 "$tmp/jq" | awk '{ print $1 }')"
  [ -n "$esperado" ] && [ "$esperado" = "$real" ] || { rm -rf "$tmp"; die "El checksum de jq no coincide; no lo instalo."; }
  mkdir -p "$USER_BIN"
  install -m 755 "$tmp/jq" "$USER_BIN/jq"
  rm -rf "$tmp"
  ok "jq $("$USER_BIN/jq" --version 2>/dev/null) en $USER_BIN"
}

# Python de usuario con uv: binarios de python-build-standalone, sin sudo ni compilar.
# Se repara solo: si ~/.local/bin/python3 está roto, es viejo o apunta a otro lado, se
# reemplaza por el de uv (un archivo real se renombra, no se borra).
nobrew_python() {
  hash -r   # bash recuerda la ruta de python3 de la primera vez que lo ejecutó
  python_ok && { ok "$(python3 -V 2>&1) en $(command -v python3)"; return 0; }
  info "El python3 disponible ($(python3 -V 2>&1 || echo 'ninguno')) no alcanza para los conectores; instalo Python 3.12 con uv"
  if ! have uv; then
    run env UV_NO_MODIFY_PATH=1 sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' \
      || die "No se pudo instalar uv desde https://astral.sh/uv/install.sh (¿hay conexión?)."
    hash -r
  fi
  run uv python install 3.12 || die "uv no pudo instalar Python 3.12."
  [ "$DRY_RUN" = 1 ] && { run ln -sfn "<python 3.12 de uv>" "$USER_BIN/python3"; return 0; }
  have uv || die "uv quedó instalado fuera de $USER_BIN y no lo encuentro en el PATH."

  # --system: que no devuelva el Python de un venv si se corre dentro de un proyecto
  local py dest="$USER_BIN/python3"
  py="$(uv python find --system 3.12 2>/dev/null)" && [ -x "$py" ] \
    || die "uv dice que instaló Python 3.12 pero no lo encuentra."
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    mv "$dest" "$dest.viejo-$(date +%Y%m%d-%H%M%S)"
    warn "Había un python3 propio en $USER_BIN; quedó renombrado como $(basename "$dest").viejo-*"
  fi
  ln -sfn "$py" "$dest"
  hash -r
  python_ok || die "Python 3.12 quedó en $py pero python3 sigue resolviendo a $(command -v python3). Revisá el PATH."
  ok "$(python3 -V 2>&1) en $dest"
}

# Para que python3, jq, claude e ideasbox se encuentren también en las próximas terminales.
# zsh es la shell por defecto de macOS desde Catalina y lee ~/.zprofile al abrir sesión.
persist_user_bin() {
  local rc="$HOME/.zprofile"
  grep -qs '\.local/bin' "$rc" && return 0
  if [ "$DRY_RUN" = 1 ]; then run "agregar \$HOME/.local/bin al PATH en $rc"; return 0; fi
  printf '\n# Ideas Box: binarios de usuario (python3, jq, claude, ideasbox)\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
  ok "$USER_BIN agregado al PATH en $rc"
}

nobrew_install_base() {
  run mkdir -p "$USER_BIN"
  export PATH="$USER_BIN:$PATH"
  persist_user_bin
  nobrew_jq
  nobrew_python
}

# ffmpeg e ImageMagick no tienen un binario oficial único para Mac: se indica de dónde bajarlos
nobrew_install_media() {
  if have ffmpeg && { have magick || have convert; }; then
    ok "ffmpeg e ImageMagick presentes"
    return 0
  fi
  warn "Sin Homebrew, ffmpeg e ImageMagick se instalan a mano (los agentes de contenido los usan, el resto no):"
  have ffmpeg || info "  ffmpeg:      https://ffmpeg.org/download.html#build-mac — copiá ffmpeg y ffprobe a $USER_BIN"
  have magick || have convert || info "  ImageMagick: https://imagemagick.org/script/download.php#macosx"
}

# xcode-select -p puede devolver una ruta que ya no existe (CLT borradas a mano o una
# actualización de macOS que las invalidó): se confirma que haya un git real adentro.
_clt_ok() {
  local d
  d="$(xcode-select -p 2>/dev/null)" && [ -x "$d/usr/bin/git" ]
}

# Instalación sin ventana, igual que el instalador de Homebrew: el archivo de marca hace que
# softwareupdate liste las CLT como disponibles. La ventana de xcode-select --install falla
# seguido con "no disponible en el servidor de actualización"; este camino no.
_clt_softwareupdate() {
  local marca="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress" label
  touch "$marca"
  info "Buscando las herramientas en el servidor de Apple (puede tardar un minuto)"
  label="$(softwareupdate -l 2>/dev/null \
    | grep -B 1 -E 'Command Line Tools' \
    | awk -F'*' '/^ *\*/ { print $2 }' \
    | sed -e 's/^ *Label: //' -e 's/^ *//' \
    | grep -vi beta \
    | sort -V | tail -n 1)"
  if [ -z "$label" ]; then
    rm -f "$marca"
    warn "softwareupdate no ofrece las herramientas de línea de comandos para este macOS."
    return 1
  fi
  info "Instalando «$label» con softwareupdate: pide tu contraseña de administrador y tarda de 5 a 15 minutos"
  _need_sudo
  run $SUDO softwareupdate -i "$label" --verbose || { rm -f "$marca"; return 1; }
  rm -f "$marca"
  [ "$DRY_RUN" = 1 ] && return 0
  run $SUDO xcode-select --switch /Library/Developer/CommandLineTools || true
  _clt_ok
}

ensure_xcode_clt() {
  _clt_ok && { ok "Herramientas de línea de comandos de Xcode presentes"; return 0; }
  warn "Faltan las herramientas de línea de comandos de Xcode (compilador, git, make)."
  if _clt_softwareupdate; then
    ok "Herramientas de línea de comandos de Xcode instaladas"
    return 0
  fi

  # Plan B: la ventana de Apple, y si tampoco anda, la descarga manual
  warn "No se pudieron instalar con softwareupdate. Pruebo con el instalador gráfico de Apple."
  run xcode-select --install || true
  info "Si la ventana falla o no aparece, bajalas a mano (con tu Apple ID, gratis):"
  info "  https://developer.apple.com/download/all/?q=command%20line%20tools"
  info "  Elegí la versión más nueva que diga compatible con tu macOS ($OS_VERSION) e instalá el .dmg."
  if [ "$NON_INTERACTIVE" = 1 ] || [ -z "$STACK_TTY" ]; then
    die "Cuando termine la instalación de Xcode CLT, volvé a correr install.sh."
  fi
  # Se espera acá en vez de cortar: al terminar la instalación se sigue sin relanzar nada
  until _clt_ok; do
    confirm "¿Ya terminó la instalación? (Enter para comprobar, n para salir)" y \
      || die "Cuando termine la instalación de Xcode CLT, volvé a correr install.sh."
    _clt_ok || warn "Todavía no las encuentro."
  done
  ok "Herramientas de línea de comandos de Xcode instaladas"
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

pkg_install_base() {
  if ! is_mac; then apt_install "${APT_BASE[@]}"
  elif [ "$MAC_NOBREW" = 1 ]; then nobrew_install_base
  else brew_install "${BREW_BASE[@]}"
  fi
}
pkg_install_media() {
  if ! is_mac; then apt_install "${APT_MEDIA[@]}"
  elif [ "$MAC_NOBREW" = 1 ]; then nobrew_install_media
  else brew_install "${BREW_MEDIA[@]}"
  fi
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
  # La LTS vigente (24) pide macOS 13.5; debajo queda la 22, con soporte hasta abril de 2027
  local target='lts/*'
  is_mac && ! mac_version_ge 13 5 && target=22
  nvm install "$target" >/dev/null
  nvm alias default "$target" >/dev/null
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

# Cuando el paso 1 se saltea (--skip-deps, o retomando una instalación cortada), los
# pasos siguientes igual necesitan el entorno que ese paso deja: PATH y Node.
deps_env_only() {
  detect_os
  export PATH="$USER_BIN:$PATH"
  is_mac && _brew_to_path
  hash -r
  ensure_node 2>/dev/null || true
}

deps_main() {
  step "1/8 · Dependencias del sistema"
  detect_os
  info "Sistema detectado: $OS_PRETTY"
  if is_mac; then
    macos_preflight
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
