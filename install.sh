#!/usr/bin/env bash
# Ideas Box — instalador del stack de empresa online híbrida.
#
#   bash install.sh                 instalación guiada
#   bash install.sh --dry-run       muestra qué haría, sin tocar nada
#   bash install.sh --help          opciones
#
# Soporta Ubuntu, Linux Mint y Debian recién instalados.

set -euo pipefail

# macOS todavía trae bash 3.2 de fábrica. El código está escrito para funcionar ahí,
# pero si alguien lo corre con algo más viejo conviene decirlo antes de fallar raro.
if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 3 ]; then
  echo "Ideas Box necesita bash 3.2 o superior. Ejecutalo con: bash install.sh" >&2
  exit 1
fi

STACK_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export STACK_SRC

# shellcheck source=lib/common.sh
. "$STACK_SRC/lib/common.sh"
. "$STACK_SRC/lib/state.sh"
. "$STACK_SRC/lib/deps.sh"
. "$STACK_SRC/lib/profile.sh"
. "$STACK_SRC/lib/datastore.sh"
. "$STACK_SRC/lib/mcp.sh"
. "$STACK_SRC/lib/thirdparty.sh"
. "$STACK_SRC/lib/canonical.sh"
. "$STACK_SRC/lib/settings.sh"
. "$STACK_SRC/lib/menu.sh"
. "$STACK_SRC/lib/doctor.sh"

SKIP_DEPS=0

usage() {
  cat <<TXT
Ideas Box — instalador del stack de empresa online híbrida sobre Claude Code

Uso: bash install.sh [opciones]

  --data-root RUTA     raíz de datos (salta la pregunta del disco)
  --empresa NOMBRE     nombre de la empresa (salta la pregunta)
  --skip-deps          no instalar paquetes del sistema
  --dry-run            mostrar acciones sin ejecutarlas
  --yes                aceptar todas las confirmaciones
  --non-interactive    no preguntar nada; toma el valor por defecto de cada opción
  --debug              salida detallada
  -h, --help           esta ayuda

Si la instalación se corta, volvé a correr bash install.sh: ofrece retomar desde
el paso que quedó, con las respuestas que ya diste.

Qué hace, en orden:
  1. dependencias del sistema + Node + Claude Code
  2. identidad de la empresa
  3. raíz de datos (disco aparte si existe, si no una carpeta del home)
  4. packs de skills
  5. servidores MCP (con sus credenciales)
  6. agentes, skills propios, documentación y memoria
  7. symlinks de runtime en ~/.claude
  8. permisos y hooks de Claude Code
TXT
}

while [ $# -gt 0 ]; do
  case "$1" in
    --data-root) DATA_ROOT="$2"; shift 2 ;;
    --data-root=*) DATA_ROOT="${1#*=}"; shift ;;
    --empresa) EMPRESA_NOMBRE="$2"; shift 2 ;;
    --empresa=*) EMPRESA_NOMBRE="${1#*=}"; shift ;;
    --skip-deps) SKIP_DEPS=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --debug) STACK_DEBUG=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opción desconocida: $1 (probá --help)" ;;
  esac
done

banner() {
  cat <<'TXT'

  ╔══════════════════════════════════════════════════════════╗
  ║   IDEAS BOX — tu empresa online híbrida, en una caja     ║
  ║   agentes · skills · memoria canónica · conectores MCP   ║
  ╚══════════════════════════════════════════════════════════╝

TXT
}

install_cli() {
  local dest="$HOME/.local/bin/$STACK_NAME"
  run mkdir -p "$HOME/.local/bin"
  run ln -sfn "$STACK_SRC/bin/ideasbox" "$dest"
  ok "Comando '$STACK_NAME' disponible en $dest"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "Agregá \$HOME/.local/bin a tu PATH para usar '$STACK_NAME' directo." ;;
  esac
  menu_install_shortcut
}

resumen() {
  cat <<TXT

$(printf '%s' "$C_B")Listo.$(printf '%s' "$C_RESET")

  Empresa        $EMPRESA_NOMBRE
  Datos          $DATA_ROOT
  Canónico       $DATA_ROOT/.claude  (agentes, skills, memoria, docs)
  Runtime        $CLAUDE_CONFIG_DIR  (solo symlinks)
  Credenciales   $STACK_SECRETS_DIR  (600, fuera de ~/.claude.json)

Cómo seguir:
  · Abrí el ícono «Ideas Box» o escribí $STACK_NAME en una terminal. Ahí están
    «Hablar con mis agentes», «Conectar una herramienta», «Crear una habilidad nueva»
    y el resto de las opciones, en palabras comunes.
  · La primera vez que hables con tus agentes, Claude te va a pedir iniciar sesión.

Todo lo que genera el stack es texto plano: si algo no te sirve, editalo.
TXT
}

# Los pasos 2 y 3 guardan el perfil apenas terminan: si después algo corta la
# instalación, las respuestas ya dadas no se pierden.
perfil_step() { profile_wizard; profile_save; }
datos_step()  { datastore_wizard; profile_save; }

main() {
  banner
  init_input
  require_input
  [ "$DRY_RUN" = 1 ] && warn "Modo dry-run: no se modifica nada."

  state_offer_resume
  trap state_on_exit EXIT

  if [ "$SKIP_DEPS" = 1 ] || { [ "$RESUME" = 1 ] && state_is_done deps; }; then
    info "Salteo dependencias del sistema"
    deps_env_only
  else
    deps_main
    state_done deps
  fi

  run_step perfil   perfil_step
  run_step datos    datos_step
  run_step packs    thirdparty_wizard
  run_step mcp      mcp_wizard
  run_step canonico canonical_main
  run_step settings settings_apply
  run_step cli      install_cli
  state_clear
  resumen
}

main "$@"
