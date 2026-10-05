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
      # Corte duro solo debajo de 13: ahí Claude Code no arranca. El binario de codebase-memory
      # pide 14 en Apple Silicon y 15 en Intel, pero una Mac Intel con macOS 13 (OCLP) completó
      # la instalación igual: debajo de ese mínimo se avisa y se sigue.
      [ "${v%%.*}" -ge 13 ] 2>/dev/null || fail "Ideas Box necesita macOS 13 o posterior (Claude Code no arranca en versiones anteriores). Este equipo tiene macOS $v. Alternativa: instalar Linux Mint o Ubuntu en este equipo."
      local min=15 chip=Intel
      case "$(uname -m)" in arm64|aarch64) min=14; chip='con Apple Silicon' ;; esac
      if ! [ "${v%%.*}" -ge "$min" ] 2>/dev/null; then
        printf '\033[33m!\033[0m %s\n' "En una Mac $chip lo recomendado es macOS $min o posterior (este equipo tiene $v)." \
          "  El conector de código (codebase-memory) puede no funcionar; la instalación sigue igual." >&2
      fi
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
    if ! git -C "$dir" pull --ff-only --quiet 2>/dev/null; then
      # Historia distinta a la de GitHub: si la copia no tiene cambios propios, se alinea
      if [ -z "$(git -C "$dir" status --porcelain 2>/dev/null)" ] \
          && git -C "$dir" fetch --quiet origin main && git -C "$dir" reset --quiet --hard origin/main; then
        ok "Ideas Box actualizado"
      else
        printf '\n\033[33m!\033[0m No se pudo actualizar %s: tiene cambios hechos a mano.\n' "$dir"
        printf '  Para dejarla igual a la versión publicada (descarta esos cambios):\n'
        printf '    git -C %s fetch origin main && git -C %s reset --hard origin/main\n\n' "$dir" "$dir"
        fail "Actualizá la copia y volvé a pegar la línea de instalación."
      fi
    fi
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
  [ -f "$dir/lib/gui.sh" ] || fail "La copia de $dir es anterior al asistente gráfico y no se pudo actualizar."
  ok "Ideas Box listo en $dir"

  # La terminal sigue siendo la de la persona: el asistente puede necesitarla una vez
  # (contraseña en WSL) y muestra ahí la dirección por si el navegador no se abre solo.
  if { : </dev/tty; } 2>/dev/null; then
    exec bash "$dir/install.sh" --gui "$@" </dev/tty
  fi
  exec bash "$dir/install.sh" --gui "$@"
}

main "$@"
