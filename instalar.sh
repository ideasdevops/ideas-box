#!/usr/bin/env bash
# Ideas Box — arranque del instalador. Es lo que corre la línea de la landing:
#
#   curl -fsSL https://raw.githubusercontent.com/ideasdevops/ideas-box/main/instalar.sh | bash
#
# Baja (o actualiza) Ideas Box en ~/ideas-box y abre el asistente gráfico en el navegador.
# Todo lo demás pasa ahí. Opciones para install.sh: ... | bash -s -- --skip-deps
#
# Todo va dentro de main(): con `curl | bash` el script llega por la entrada estándar, y
# cualquier comando que la lea antes de tiempo se comería el resto del archivo.

main() {
  set -euo pipefail
  local repo="https://github.com/ideasdevops/ideas-box"
  local dir="${IDEASBOX_DIR:-$HOME/ideas-box}"

  say()  { printf '\033[36m→\033[0m %s\n' "$*"; }
  ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
  fail() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

  printf '\n  \033[1mIdeas Box\033[0m — preparando el asistente de instalación\n\n'

  case "$(uname -s)" in
    Darwin)
      local v; v="$(sw_vers -productVersion 2>/dev/null || echo 0)"
      [ "${v%%.*}" -ge 13 ] 2>/dev/null || fail "Ideas Box necesita macOS 13 o posterior. Este equipo tiene macOS $v."
      # Herramientas de Apple: traen git y Python, sin los que no hay asistente
      if ! xcode-select -p >/dev/null 2>&1 || ! /usr/bin/git --version >/dev/null 2>&1; then
        say "Hacen falta las herramientas de desarrollo de Apple (gratis). Se abre la ventana de Apple:"
        say "hacé clic en «Instalar» y aceptá la licencia. Tarda entre 5 y 15 minutos."
        osascript -e 'display dialog "Para empezar, Ideas Box necesita las herramientas de desarrollo de Apple (gratis).\n\nEn la ventana de Apple que se abre, hacé clic en «Instalar» y aceptá la licencia. Cuando termine, el asistente sigue solo." buttons {"Continuar"} default button 1 with title "Ideas Box" with icon note' >/dev/null 2>&1 || true
        xcode-select --install >/dev/null 2>&1 || true
        say "Esperando a que termine la instalación de Apple…"
        until xcode-select -p >/dev/null 2>&1 && /usr/bin/git --version >/dev/null 2>&1; do sleep 5; done
        ok "Herramientas de Apple instaladas"
      fi
      ;;
    Linux) ;;
    *) fail "Sistema no soportado: $(uname -s). Ideas Box corre en macOS, Linux y Windows 11 (con Ubuntu en WSL)." ;;
  esac

  if [ -d "$dir/.git" ]; then
    say "Actualizando Ideas Box en $dir"
    git -C "$dir" pull --ff-only --quiet || say "No se pudo actualizar; sigo con la versión que ya está."
  elif [ -f "$dir/install.sh" ] && [ -f "$dir/VERSION" ]; then
    say "Uso la copia de Ideas Box que ya está en $dir"
  elif [ -e "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
    fail "$dir ya existe y no es Ideas Box. Movelo o elegí otra carpeta: IDEASBOX_DIR=/otra/ruta"
  elif command -v git >/dev/null 2>&1; then
    say "Descargando Ideas Box en $dir"
    git clone --quiet --depth 1 "$repo.git" "$dir"
  else
    # Sin git (Linux mínimo): el comprimido del repo. El instalador lo convierte en un
    # clon apenas instala git, para que las actualizaciones funcionen.
    say "Descargando Ideas Box en $dir"
    mkdir -p "$dir"
    curl -fsSL "$repo/archive/refs/heads/main.tar.gz" | tar -xz --strip-components=1 -C "$dir" \
      || fail "No se pudo descargar Ideas Box. ¿Hay conexión a internet?"
  fi
  ok "Ideas Box listo en $dir"

  # La terminal sigue siendo la de la persona: el asistente puede necesitarla una vez
  # (contraseña en WSL) y muestra ahí la dirección por si el navegador no se abre solo.
  if { : </dev/tty; } 2>/dev/null; then
    exec bash "$dir/install.sh" --gui "$@" </dev/tty
  fi
  exec bash "$dir/install.sh" --gui "$@"
}

main "$@"
