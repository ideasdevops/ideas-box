#!/usr/bin/env bash
# Utilidades compartidas por el instalador y por el CLI `empresa`.
# Se espera que quien haga source defina STACK_SRC (raíz del repo del stack).

set -o pipefail

# shellcheck source=lib/portability.sh
. "$(dirname "${BASH_SOURCE[0]}")/portability.sh"

STACK_NAME="${STACK_NAME:-ideasbox}"
STACK_SRC="${STACK_SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STACK_CONFIG_DIR="${STACK_CONFIG_DIR:-$HOME/.config/$STACK_NAME}"
STACK_PROFILE="$STACK_CONFIG_DIR/empresa.conf"
STACK_LOCKS="$STACK_CONFIG_DIR/locks.tsv"
STACK_SECRETS_DIR="$STACK_CONFIG_DIR/secrets"
STACK_MCP_SRC="${STACK_MCP_SRC:-$HOME/.local/share/mcp-servers}"
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_JSON="${CLAUDE_JSON:-$HOME/.claude.json}"

# El ícono abre el menú con el PATH de la sesión de escritorio, que no tiene ~/.local/bin
# hasta el próximo inicio de sesión (Debian/MX) o nunca (Mac con Homebrew): ahí dejan
# claude e ideasbox sus instaladores. Se agregan acá para no depender de eso.
ib_user_path() {
  local d n
  for d in /usr/local/bin /opt/homebrew/bin "$HOME/.claude/local" "$HOME/.local/bin"; do
    [ -d "$d" ] || continue
    case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
  done
  # Node de nvm (y un claude instalado con npm): al final, para no tapar al del sistema
  for n in "$HOME"/.nvm/versions/node/*/bin; do d="$n"; done
  if [ -n "${d:-}" ] && [ -d "$d" ]; then
    case ":$PATH:" in *":$d:"*) ;; *) PATH="$PATH:$d" ;; esac
  fi
  export PATH
}
ib_user_path

DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_B=$'\033[1m'
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_INFO=$'\033[36m'
else
  C_RESET=; C_DIM=; C_B=; C_OK=; C_WARN=; C_ERR=; C_INFO=
fi

log()   { printf '%s\n' "$*"; }
info()  { printf '%s→%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
ok()    { printf '%s✓%s %s\n' "$C_OK" "$C_RESET" "$*"; }
warn()  { printf '%s!%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
err()   { printf '%s✗%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }
step()  { printf '\n%s%s%s\n' "$C_B" "$*" "$C_RESET"; }
debug() { [ "${STACK_DEBUG:-0}" = 1 ] && printf '%s  %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2 || true; }

# run <cmd...> — respeta DRY_RUN
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '%s  [dry-run] %s%s\n' "$C_DIM" "$*" "$C_RESET"
    return 0
  fi
  "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }

# De dónde se lee cuando hay que preguntar. Sin una terminal real, preguntar
# devuelve vacío en silencio y la instalación termina a medias sin que se note:
# por eso init_input() lo resuelve una vez y el instalador corta si no hay.
STACK_TTY=""
init_input() {
  if { : >/dev/tty; } 2>/dev/null; then
    STACK_TTY=/dev/tty
  elif [ -t 0 ]; then
    STACK_TTY=/dev/stdin
  else
    STACK_TTY=""
    return 0
  fi
  # Se abre una sola vez en el descriptor 3: reabrir el archivo en cada pregunta
  # hace que un origen que no sea un dispositivo vuelva siempre a la primera línea.
  exec 3< "$STACK_TTY" || STACK_TTY=""
}

require_input() {
  [ "$NON_INTERACTIVE" = 1 ] && return 0
  [ -n "$STACK_TTY" ] && return 0
  err "Esta instalación es interactiva y no hay terminal disponible."
  err "Si lo estás corriendo con 'curl | bash', bajá el repo y corré: bash install.sh"
  err "O usá --non-interactive para aceptar todos los valores por defecto."
  exit 1
}

# confirm <pregunta> [default:y|n]
confirm() {
  local q="$1" def="${2:-n}" ans hint
  [ "$ASSUME_YES" = 1 ] && return 0
  if [ "$NON_INTERACTIVE" = 1 ] || [ -z "$STACK_TTY" ]; then
    [ "$def" = y ] && return 0 || return 1
  fi
  [ "$def" = y ] && hint="[S/n]" || hint="[s/N]"
  read -r -u 3 -p "$q $hint " ans || ans=""
  ans="${ans:-$def}"
  case "$(normaliza "$ans")" in s|si|y|yes|ok) return 0 ;; *) return 1 ;; esac
}

# ask <pregunta> <variable-destino> [default]
ask() {
  local q="$1" __var="$2" def="${3:-}" ans
  if [ "$NON_INTERACTIVE" = 1 ] || [ -z "$STACK_TTY" ]; then
    printf -v "$__var" '%s' "$def"; return 0
  fi
  if [ -n "$def" ]; then
    read -r -u 3 -p "$q [$def]: " ans || ans=""
  else
    read -r -u 3 -p "$q: " ans || ans=""
  fi
  printf -v "$__var" '%s' "${ans:-$def}"
}

# ask_secret <pregunta> <variable-destino> — no hace echo de lo tipeado
ask_secret() {
  local q="$1" __var="$2" ans
  if [ "$NON_INTERACTIVE" = 1 ] || [ -z "$STACK_TTY" ]; then
    printf -v "$__var" '%s' ""; return 0
  fi
  read -r -s -u 3 -p "$q: " ans || ans=""
  printf '\n'
  printf -v "$__var" '%s' "$ans"
}

# slugify <texto> — minúsculas, sin acentos, sin espacios
slugify() {
  local s
  s="$(normaliza "$1")"
  s="$(printf '%s' "$s" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  printf '%s' "$s"
}

# backup_file <path> — copia con timestamp antes de sobrescribir
backup_file() {
  local f="$1" dest
  [ -e "$f" ] || return 0
  dest="$CLAUDE_BACKUP_DIR/$(basename "$f").$(date +%Y%m%d-%H%M%S).bak"
  run mkdir -p "$CLAUDE_BACKUP_DIR"
  run cp -a "$f" "$dest"
  debug "backup: $f -> $dest"
}
CLAUDE_BACKUP_DIR="${CLAUDE_BACKUP_DIR:-$STACK_CONFIG_DIR/backups}"

# write_file <path> — lee contenido de stdin, respeta DRY_RUN, hace backup
write_file() {
  local f="$1" mode="${2:-644}" content
  content="$(cat)"
  if [ "$DRY_RUN" = 1 ]; then
    printf '%s  [dry-run] write %s (%s bytes)%s\n' "$C_DIM" "$f" "${#content}" "$C_RESET"
    return 0
  fi
  [ -e "$f" ] && backup_file "$f"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$content" > "$f"
  chmod "$mode" "$f"
}

# require_cmds <cmd...> — corta si falta alguno
require_cmds() {
  local missing=()
  for c in "$@"; do have "$c" || missing+=("$c"); done
  [ ${#missing[@]} -eq 0 ] || die "Faltan comandos requeridos: ${missing[*]}"
}

# python_venv_bin — imprime un intérprete Python >= 3.10 para crear los venv de los conectores.
# `python3` a secas no alcanza en Mac: el de Xcode CLT es 3.9 y python@3.12 de Homebrew solo
# enlaza python3.12, no python3. Se prueban los versionados, el de Homebrew y el de uv.
python_venv_bin() {
  local c p brew_prefix
  local cands=(python3.13 python3.12 python3.11 python3.10 python3 "$HOME/.local/bin/python3")
  if have brew; then
    brew_prefix="$(brew --prefix 2>/dev/null)"
    [ -n "$brew_prefix" ] && cands+=("$brew_prefix/opt/python@3.12/libexec/bin/python3" "$brew_prefix/bin/python3.12")
  fi
  have uv && p="$(uv python find --system 3.12 2>/dev/null)" && cands+=("$p")
  for c in "${cands[@]}"; do
    p="$(command -v "$c" 2>/dev/null)" || continue
    # ensurepip: en Ubuntu puede haber un python3.X sin su paquete -venv, que no arma venvs
    "$p" -c 'import sys, ensurepip; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1 \
      && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

# python_uv_312 — imprime un Python 3.12 de uv, instalando uv si hace falta (sin sudo ni
# compilar). Es el plan B cuando el Python del sistema es tan nuevo (Ubuntu con 3.14) que
# alguna dependencia de un conector todavía no publica binarios para él.
python_uv_312() {
  local uv py
  uv="$(command -v uv 2>/dev/null)" || uv="$HOME/.local/bin/uv"
  if [ ! -x "$uv" ]; then
    have curl || return 1
    env UV_NO_MODIFY_PATH=1 sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' >&2 || return 1
    [ -x "$uv" ] || return 1
  fi
  "$uv" python install 3.12 >&2 || return 1
  py="$("$uv" python find --system 3.12 2>/dev/null)" && [ -x "$py" ] || return 1
  printf '%s\n' "$py"
}

load_profile() {
  [ -f "$STACK_PROFILE" ] || die "No hay perfil en $STACK_PROFILE. Ejecutá primero install.sh."
  # shellcheck disable=SC1090
  . "$STACK_PROFILE"
}

# detect_os — define OS_ID, OS_VERSION, OS_PRETTY y PKG (apt | brew)
detect_os() {
  if is_mac; then
    OS_ID="macos"
    OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo '?')"
    OS_PRETTY="macOS $OS_VERSION ($(uname -m))"
    PKG=brew
    return 0
  fi

  [ -r /etc/os-release ] || die "Sistema no soportado. Ideas Box corre en Ubuntu, Linux Mint, Debian y macOS."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_LIKE="${ID_LIKE:-}"
  OS_VERSION="${VERSION_ID:-}"
  OS_PRETTY="${PRETTY_NAME:-$OS_ID}"
  case "$OS_ID $OS_LIKE" in
    *debian*|*ubuntu*) PKG=apt ;;
    *) PKG="" ;;
  esac
  [ -n "$PKG" ] || die "Distribución no soportada ($OS_PRETTY). Ideas Box soporta Ubuntu, Linux Mint, Debian y macOS."
}

# lock_record <clave> <valor> — deja trazabilidad de versiones instaladas
lock_record() {
  [ "$DRY_RUN" = 1 ] && return 0
  mkdir -p "$(dirname "$STACK_LOCKS")"
  touch "$STACK_LOCKS"
  local key="$1" val="$2" tmp
  tmp="$(mktemp)"
  tsv_drop "$STACK_LOCKS" "$key" > "$tmp" || true
  printf '%s\t%s\t%s\n' "$key" "$val" "$(date -Iseconds)" >> "$tmp"
  sort -o "$STACK_LOCKS" "$tmp"
  rm -f "$tmp"
}

# json_merge <archivo.json> — aplica un patch JSON (stdin) con python3
json_merge() {
  local target="$1" patch
  patch="$(cat)"
  if [ "$DRY_RUN" = 1 ]; then
    printf '%s  [dry-run] merge json en %s%s\n' "$C_DIM" "$target" "$C_RESET"
    return 0
  fi
  [ -e "$target" ] && backup_file "$target"
  PATCH="$patch" TARGET="$target" python3 - <<'PY'
import json, os, sys

target = os.environ["TARGET"]
patch = json.loads(os.environ["PATCH"])

try:
    with open(target) as fh:
        base = json.load(fh)
except (FileNotFoundError, json.JSONDecodeError):
    base = {}

def deep(dst, src):
    for k, v in src.items():
        if isinstance(v, dict) and isinstance(dst.get(k), dict):
            deep(dst[k], v)
        elif isinstance(v, list) and isinstance(dst.get(k), list):
            for item in v:
                if item not in dst[k]:
                    dst[k].append(item)
        else:
            dst[k] = v
    return dst

deep(base, patch)
os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
tmp = target + ".tmp"
with open(tmp, "w") as fh:
    json.dump(base, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
os.replace(tmp, target)
PY
}
