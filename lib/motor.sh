#!/usr/bin/env bash
# Motor local de respaldo: un modelo que corre en el equipo (Ollama) para que el trabajo no
# se frene cuando se agota el plan de Claude. No reemplaza a Claude: es más lento y más chico,
# así que trabaja con bloqueos (sin push/commit/deploy/servidores) y con un punto de
# restauración git, y lo que hace se revisa en Claude al volver.

MOTOR_CONF="$STACK_CONFIG_DIR/fallback.conf"
MOTOR_MODEL_BASE="${MOTOR_MODEL_BASE:-qwen3.5}"         # modelo de Ollama con herramientas, ~6,6 GB
MOTOR_MODEL="${MOTOR_MODEL:-$MOTOR_MODEL_BASE-ideasbox}" # mismo modelo con ventana de 32k (Ollama usa 4k por defecto)
MOTOR_CTX="${MOTOR_CTX:-32768}"
MOTOR_RAM_MIN=12       # GB: por debajo, el modelo deja al equipo sin memoria
MOTOR_RAM_OK=16
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"

# Modelos en la nube de otros proveedores (OpenAI, Gemini). Claude Code solo habla el formato de
# Anthropic: LiteLLM, corriendo en este equipo, traduce. Cobran por uso con la clave del usuario,
# por eso nunca son el respaldo automático salvo que la persona lo elija.
NUBE_PROVEEDORES="openai gemini"
LITELLM_DIR="${LITELLM_DIR:-$HOME/.local/share/$STACK_NAME/litellm}"
LITELLM_PORT="${LITELLM_PORT:-4141}"
LITELLM_URL="http://127.0.0.1:$LITELLM_PORT"
# 1.82.7 y 1.82.8 se publicaron adulteradas en PyPI (marzo de 2026): nunca esas.
LITELLM_PIP="${LITELLM_PIP:-litellm[proxy]!=1.82.7,!=1.82.8}"

# fallback_conf_set <clave> <valor> — reemplaza o agrega en fallback.conf (valor entre comillas simples)
fallback_conf_set() {
  local k="$1" v="$2" tmp
  [ "$DRY_RUN" = 1 ] && { debug "fallback.conf: $k=$v"; return 0; }
  mkdir -p "$STACK_CONFIG_DIR"
  [ -f "$MOTOR_CONF" ] || cat >"$MOTOR_CONF" <<'TXT'
# Ideas Box — uso del plan de Claude y motor local de respaldo
# WARN_5H / CRIT_5H / WARN_7D: % de uso desde el que se pide ahorrar
# AUTO_OPEN=1: si se corta Claude por límite, abrir solo el motor local
TXT
  tmp="$MOTOR_CONF.tmp"
  grep -v "^$k=" "$MOTOR_CONF" >"$tmp" || true
  printf "%s='%s'\n" "$k" "$(printf '%s' "$v" | sed "s/'/'\\\\''/g")" >>"$tmp"
  mv "$tmp" "$MOTOR_CONF"
}

fallback_conf_get() {
  [ -f "$MOTOR_CONF" ] || return 0
  sed -n "s/^$1='\(.*\)'$/\1/p" "$MOTOR_CONF" | tail -1
}

motor_ram_gb() {
  if is_mac; then
    echo $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
  else
    awk '/MemTotal/ {printf "%d", $2/1048576 + 0.5}' /proc/meminfo 2>/dev/null || echo 0
  fi
}

motor_free_gb() {
  if is_mac; then
    # páginas libres + inactivas: lo que macOS puede dar sin pelearse con nadie
    vm_stat 2>/dev/null | awk '/page size of/ {ps=$8} /Pages free|Pages inactive/ {gsub("\\.","",$NF); n+=$NF} END {printf "%d", n*ps/1073741824}'
  else
    awk '/MemAvailable/ {printf "%d", $2/1048576}' /proc/meminfo 2>/dev/null || echo 0
  fi
}

ollama_up() { curl -fsS -m 3 "$OLLAMA_URL/api/version" >/dev/null 2>&1; }

# Ollama corre como servicio en Linux con systemd y en macOS con brew services; en WSL sin
# systemd no queda ningún servicio, así que se levanta a mano cuando hace falta.
ollama_ensure_running() {
  ollama_up && return 0
  have ollama || return 1
  if is_mac && have brew; then
    brew services start ollama >/dev/null 2>&1 || true
  fi
  if ! ollama_up; then
    mkdir -p "$STACK_CONFIG_DIR/uso"
    nohup ollama serve >>"$STACK_CONFIG_DIR/uso/ollama.log" 2>&1 </dev/null &
  fi
  local i=0
  while [ $i -lt 20 ]; do ollama_up && return 0; sleep 1; i=$((i + 1)); done
  return 1
}

motor_installed() {
  have ollama && ollama_ensure_running && ollama list 2>/dev/null | awk '{print $1}' | grep -q "^$MOTOR_MODEL\(:latest\)\?$"
}

motor_install_ollama() {
  if have ollama; then
    ok "Ollama presente ($(ollama --version 2>/dev/null | tail -1))"
    return 0
  fi
  info "Instalando Ollama (el programa que corre modelos de IA en este equipo)"
  if is_mac; then
    if have brew; then
      run brew install ollama || return 1
    else
      warn "Sin Homebrew no puedo instalar Ollama solo en este Mac."
      info "Bajalo de https://ollama.com/download, abrilo una vez y después corré: $STACK_NAME motor install"
      return 1
    fi
  else
    _need_sudo
    # El script oficial, bajado primero y corrido como root: así usa la contraseña ya
    # pedida (con el asistente, la ventana nativa) en vez de pedirla otra vez adentro.
    local script
    script="$(mktemp)"
    run curl -fsSL https://ollama.com/install.sh -o "$script" || { rm -f "$script"; return 1; }
    run $SUDO sh "$script" || { rm -f "$script"; return 1; }
    rm -f "$script"
  fi
  [ "$DRY_RUN" = 1 ] && return 0
  have ollama || { warn "Ollama se instaló pero no está en el PATH de esta shell."; return 1; }
}

motor_install() {
  local ram
  ram="$(motor_ram_gb)"
  if [ "${ram:-0}" -lt "$MOTOR_RAM_MIN" ]; then
    warn "Este equipo tiene ${ram} GB de RAM; el motor local necesita al menos ${MOTOR_RAM_MIN} GB (mejor ${MOTOR_RAM_OK})."
    confirm "¿Instalarlo igual? (puede dejar al equipo muy lento)" n motor_forzar || return 0
  fi
  motor_install_ollama || { warn "No se pudo instalar Ollama. El resto de Ideas Box quedó bien."; return 1; }
  [ "$DRY_RUN" = 1 ] && { fallback_conf_set MOTOR 1; return 0; }
  ollama_ensure_running || { warn "Ollama no arranca. Probá: ollama serve"; return 1; }

  info "Bajando el modelo $MOTOR_MODEL_BASE (unos 6,6 GB: según tu conexión, puede tardar bastante)"
  ollama pull "$MOTOR_MODEL_BASE" || { warn "Falló la descarga del modelo. Reintentá con: $STACK_NAME motor install"; return 1; }

  local mf
  mf="$(mktemp)"
  printf 'FROM %s\nPARAMETER num_ctx %s\n' "$MOTOR_MODEL_BASE" "$MOTOR_CTX" >"$mf"
  ollama create "$MOTOR_MODEL" -f "$mf" >/dev/null || { rm -f "$mf"; warn "No pude preparar $MOTOR_MODEL."; return 1; }
  rm -f "$mf"

  fallback_conf_set MOTOR 1
  fallback_conf_set AUTO_OPEN "$(fallback_conf_get AUTO_OPEN | grep . || echo 1)"
  ok "Motor local listo ($MOTOR_MODEL). Si se agota el plan de Claude, el trabajo sigue ahí."
}

# --- Proveedores en la nube: OpenAI y Gemini ------------------------------------------

_nube_label() { case "$1" in openai) echo "OpenAI (ChatGPT)" ;; gemini) echo "Google Gemini" ;; *) echo "$1" ;; esac; }
_nube_secret() { echo "$STACK_SECRETS_DIR/$1.env"; }
nube_conectada() { [ -s "$(_nube_secret "$1")" ] && [ -n "$(fallback_conf_get "MODELO_$(printf '%s' "$1" | tr 'a-z' 'A-Z')")" ]; }

# El modelo más nuevo de cada proveedor que habilita la clave (la lista cambia seguido)
_nube_elegir_modelo() {
  local prov="$1" key="$2"
  case "$prov" in
    openai)
      curl -fsS -m 20 https://api.openai.com/v1/models -H "Authorization: Bearer $key" | python3 -c '
import json, re, sys
ids = [m["id"] for m in json.load(sys.stdin).get("data", [])]
best = sorted((tuple(int(x) for x in re.findall(r"\d+", i)), i) for i in ids if re.fullmatch(r"gpt-5(\.\d+)?", i))
print(best[-1][1] if best else "")' ;;
    gemini)
      curl -fsS -m 20 "https://generativelanguage.googleapis.com/v1beta/models?key=$key&pageSize=200" | python3 -c '
import json, re, sys
ids = [m["name"].split("/", 1)[-1] for m in json.load(sys.stdin).get("models", [])]
best = sorted((tuple(int(x) for x in re.findall(r"\d+", i)), i) for i in ids if re.fullmatch(r"gemini-\d+(\.\d+)?-pro", i))
print(best[-1][1] if best else "")' ;;
  esac
}

_litellm_config() {
  local prov modelo master
  master="$(cat "$STACK_SECRETS_DIR/litellm-master.key")"
  {
    echo "# Generado por $STACK_NAME motor conectar — se rehace en cada conexión"
    echo "model_list:"
    for prov in $NUBE_PROVEEDORES; do
      nube_conectada "$prov" || continue
      modelo="$(fallback_conf_get "MODELO_$(printf '%s' "$prov" | tr 'a-z' 'A-Z')")"
      echo "  - model_name: $STACK_NAME-$prov"
      echo "    litellm_params:"
      echo "      model: $prov/$modelo"
      echo "      api_key: os.environ/$(printf '%s' "$prov" | tr 'a-z' 'A-Z')_API_KEY"
    done
    echo "litellm_settings:"
    echo "  drop_params: true"
    echo "general_settings:"
    echo "  master_key: $master"
  } >"$LITELLM_DIR/config.yaml"
  chmod 600 "$LITELLM_DIR/config.yaml"
}

litellm_up() { curl -fsS -m 3 "$LITELLM_URL/health/liveliness" >/dev/null 2>&1; }

litellm_ensure_running() {
  litellm_up && return 0
  [ -x "$LITELLM_DIR/venv/bin/litellm" ] || return 1
  mkdir -p "$STACK_CONFIG_DIR/uso"
  # Las claves entran por el entorno del proceso, nunca en la línea de comandos
  (
    set -a
    for f in "$STACK_SECRETS_DIR"/openai.env "$STACK_SECRETS_DIR"/gemini.env; do [ -f "$f" ] && . "$f"; done
    set +a
    nohup "$LITELLM_DIR/venv/bin/litellm" --config "$LITELLM_DIR/config.yaml" --host 127.0.0.1 \
      --port "$LITELLM_PORT" >>"$STACK_CONFIG_DIR/uso/litellm.log" 2>&1 </dev/null &
  )
  local i=0
  while [ $i -lt 60 ]; do litellm_up && return 0; sleep 1; i=$((i + 1)); done
  return 1
}

litellm_install() {
  [ -x "$LITELLM_DIR/venv/bin/litellm" ] && return 0
  local py
  py="$(python_venv_bin)" || { warn "Hace falta Python 3.10 o posterior con venv."; return 1; }
  info "Instalando el traductor de modelos (LiteLLM) — tarda un par de minutos la primera vez"
  run mkdir -p "$LITELLM_DIR"
  run "$py" -m venv "$LITELLM_DIR/venv" || return 1
  run "$LITELLM_DIR/venv/bin/pip" install --quiet --upgrade pip || true
  run "$LITELLM_DIR/venv/bin/pip" install --quiet "$LITELLM_PIP" || return 1
}

# nube_conectar openai|gemini
nube_conectar() {
  local prov="${1:-}" key modelo var
  case " $NUBE_PROVEEDORES " in *" $prov "*) ;; *) die "Proveedores disponibles: $NUBE_PROVEEDORES" ;; esac
  var="$(printf '%s' "$prov" | tr 'a-z' 'A-Z')_API_KEY"
  step "Conectar $(_nube_label "$prov")"
  cat <<TXT

Tus agentes van a poder trabajar también con $(_nube_label "$prov"), con tu propia clave.
Cobra por uso: cada pedido se descuenta de tu cuenta de $(_nube_label "$prov"), aparte del plan de Claude.
$( [ "$prov" = openai ] && echo "La clave se crea en https://platform.openai.com/api-keys" || echo "La clave se crea en https://aistudio.google.com/apikey" )

TXT
  ask_secret "Pegá la clave (no se muestra)" key "nube_$prov"
  [ -n "$key" ] || { info "Sin clave, no conecto nada."; return 0; }
  modelo="$(_nube_elegir_modelo "$prov" "$key" 2>/dev/null || true)"
  [ -n "$modelo" ] || die "La clave no funcionó o no habilita ningún modelo compatible. Revisala y probá de nuevo."
  ok "Clave válida · modelo: $modelo"

  run mkdir -p "$STACK_SECRETS_DIR"; chmod 700 "$STACK_SECRETS_DIR"
  ( umask 077; printf '%s=%s\n' "$var" "$key" >"$(_nube_secret "$prov")" )
  [ -s "$STACK_SECRETS_DIR/litellm-master.key" ] || ( umask 077; python3 -c 'import secrets; print("sk-ib-" + secrets.token_hex(24))' >"$STACK_SECRETS_DIR/litellm-master.key" )
  fallback_conf_set "MODELO_$(printf '%s' "$prov" | tr 'a-z' 'A-Z')" "$modelo"

  litellm_install || { warn "No se pudo instalar LiteLLM. La clave quedó guardada; reintentá con: $STACK_NAME motor conectar $prov"; return 1; }
  _litellm_config
  # Si ya corría, que tome la configuración nueva
  if litellm_up; then pkill -f "$LITELLM_DIR/venv/bin/litellm" 2>/dev/null || true; sleep 1; fi
  litellm_ensure_running || { warn "LiteLLM no arrancó; mirá $STACK_CONFIG_DIR/uso/litellm.log"; return 1; }
  ok "$(_nube_label "$prov") conectado. Para usarlo: $STACK_NAME con $prov"
  if confirm "¿Usarlo como respaldo automático cuando se agote Claude? (cobra por uso; si no, el respaldo es el motor local gratis)" n "nube_respaldo_$prov"; then
    fallback_conf_set RESPALDO "$prov"; fallback_conf_set MOTOR 1
    ok "Si se agota Claude, el trabajo sigue en $(_nube_label "$prov")."
  fi
}

# Paso opcional del instalador
motor_wizard() {
  step "Motor local de respaldo (opcional)"
  local ram def=n
  ram="$(motor_ram_gb)"
  [ "${ram:-0}" -ge "$MOTOR_RAM_OK" ] && def=y
  cat <<TXT

Un modelo de IA que corre en este equipo, sin internet y sin costo. Si se agota el
plan de Claude, el trabajo sigue ahí solo (con aviso) en vez de quedar frenado.
Es más lento y menos capaz que Claude: no publica, no hace commits ni toca
servidores, y lo que hace se revisa cuando Claude vuelve.
Necesita ~7 GB de disco y ${MOTOR_RAM_OK} GB de RAM o más (este equipo: ${ram} GB).
Se puede instalar después con: $STACK_NAME motor install

TXT
  if motor_installed 2>/dev/null; then
    fallback_conf_set MOTOR 1
    ok "El motor local ya está instalado ($MOTOR_MODEL)."
    return 0
  fi
  if ! confirm "¿Instalar el motor local de respaldo?" "$def" motor; then
    info "Motor local salteado."
    return 0
  fi
  motor_install || warn "El motor local no quedó instalado. Reintentá con: $STACK_NAME motor install"
}

# Bloqueos duros del motor local: no puede publicar ni deshacer trabajo hecho con Claude.
_motor_settings() {
  cat <<'JSON'
{"alwaysThinkingEnabled":false,"permissions":{"deny":[
 "Bash(git push*)","Bash(git commit*)","Bash(git reset*)","Bash(git checkout*)","Bash(git restore*)",
 "Bash(git rebase*)","Bash(git stash*)","Bash(git clean*)","Bash(git branch -D*)","Bash(git update-ref*)",
 "Bash(rm -rf*)","Bash(rm -r *)","Bash(ssh *)","Bash(scp *)","Bash(rsync *)","Bash(docker *)",
 "Bash(curl -X POST*)","Bash(curl -X PUT*)","Bash(curl -X DELETE*)","Bash(sudo *)"]}}
JSON
}

# motor_session [args de claude…] — Claude Code con el modelo local en vez de la nube.
# Modo mínimo (--bare): sin hooks, memoria, conectores ni tu cuenta de Claude, para que el
# pedido entre en la ventana del modelo y responda en un tiempo razonable.
motor_session() {
  local prov="${MOTOR_PROVEEDOR:-local}"
  have claude || die "Claude Code no está instalado."
  if [ "$prov" != local ]; then
    _nube_session "$prov" "$@"
    return
  fi
  motor_installed || die "El motor local no está instalado. Corré: $STACK_NAME motor install"
  local free
  free="$(motor_free_gb)"
  [ "${free:-0}" -lt 8 ] && warn "Hay ${free} GB de RAM libre: cerrá programas pesados si el motor local va muy lento."
  [ -t 2 ] && printf '\033[1;33m[MOTOR LOCAL] %s · sin conectores ni memoria · revisá en Claude lo que haga\033[0m\n' "$MOTOR_MODEL" >&2

  local sys="Sos un asistente que trabaja en la terminal del usuario, en ${EMPRESA_IDIOMA:-es}. Usá las herramientas \
(Bash, Read, Edit, Write, Glob, Grep) para leer y modificar archivos; leé antes de editar. Respuestas breves. \
Si un comando falla, decilo: no inventes resultados. Nada de publicar, commits, push, deploys ni acciones sobre \
servidores: eso queda para Claude. Cambios chicos y acotados; no reescribas trabajo ya hecho."

  # La sesión de Claude que se cortó no se hereda: sin esto se marca como sesión hija.
  local v
  for v in $(env | awk -F= '/^(CLAUDE|ANTHROPIC)[A-Za-z0-9_]*=/ {print $1}'); do unset "$v"; done
  export ANTHROPIC_BASE_URL="$OLLAMA_URL" ANTHROPIC_API_KEY=ollama ANTHROPIC_MODEL="$MOTOR_MODEL" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="$MOTOR_MODEL" ANTHROPIC_DEFAULT_SONNET_MODEL="$MOTOR_MODEL" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="$MOTOR_MODEL" CLAUDE_CODE_SUBAGENT_MODEL="$MOTOR_MODEL" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 API_TIMEOUT_MS=1800000 \
    CLAUDE_CODE_MAX_CONTEXT_TOKENS="$MOTOR_CTX"
  exec claude --bare --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
    --permission-mode default --tools Bash,Read,Edit,Write,Glob,Grep --disable-slash-commands \
    --settings "$(_motor_settings)" --system-prompt "$sys" "$@"
}

# Sesión con OpenAI o Gemini: modelos capaces y con ventana grande, así que cargan el CLAUDE.md
# y la memoria de la empresa (sin --bare). Conectores, solo con --mcp: OpenAI acepta hasta 128
# herramientas por pedido. Mismos bloqueos que el motor local: no es Claude quien trabaja.
_nube_session() {
  local prov="$1" mcp_args v modelo
  shift
  nube_conectada "$prov" || die "$(_nube_label "$prov") no está conectado. Corré: $STACK_NAME motor conectar $prov"
  litellm_ensure_running || die "No arranca LiteLLM; mirá $STACK_CONFIG_DIR/uso/litellm.log"
  modelo="$(fallback_conf_get "MODELO_$(printf '%s' "$prov" | tr 'a-z' 'A-Z')")"
  mcp_args="--strict-mcp-config"
  case " $* " in *" --mcp "*) mcp_args="" ;; esac
  [ -t 2 ] && printf '\033[1;36m[%s] %s · cobra por uso con tu clave · revisá en Claude lo que haga\033[0m\n' "$(_nube_label "$prov")" "$modelo" >&2
  for v in $(env | awk -F= '/^(CLAUDE|ANTHROPIC)[A-Za-z0-9_]*=/ {print $1}'); do unset "$v"; done
  export ANTHROPIC_BASE_URL="$LITELLM_URL" ANTHROPIC_AUTH_TOKEN="$(cat "$STACK_SECRETS_DIR/litellm-master.key")" \
    ANTHROPIC_MODEL="$STACK_NAME-$prov" ANTHROPIC_DEFAULT_OPUS_MODEL="$STACK_NAME-$prov" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="$STACK_NAME-$prov" ANTHROPIC_DEFAULT_HAIKU_MODEL="$STACK_NAME-$prov" \
    CLAUDE_CODE_SUBAGENT_MODEL="$STACK_NAME-$prov" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    CLAUDE_CODE_MAX_CONTEXT_TOKENS=128000
  local pass=() a
  for a in "$@"; do [ "$a" = --mcp ] || pass+=("$a"); done
  if [ -n "$mcp_args" ]; then
    exec claude $mcp_args --mcp-config '{"mcpServers":{}}' --permission-mode default \
      --settings "$(_motor_settings)" ${pass[@]+"${pass[@]}"}
  fi
  exec claude --permission-mode default --settings "$(_motor_settings)" ${pass[@]+"${pass[@]}"}
}

# motor_continuar [traspaso.md | -l] — retoma en el motor local una sesión cortada por límite
motor_continuar() {
  local dir="$STACK_CONFIG_DIR/traspasos" h="${1:-}" f n i=0
  local pend=()
  if [ -d "$dir" ]; then
    for f in "$dir"/*.md; do
      [ -e "$f" ] && [ ! -e "${f%.md}.retomado" ] && pend+=("$f")
    done
  fi
  if [ "$h" = "-l" ]; then
    [ ${#pend[@]} -eq 0 ] && echo "(ningún trabajo pendiente)" || printf '%s\n' "${pend[@]}"
    return 0
  fi
  if [ -z "$h" ]; then
    [ ${#pend[@]} -gt 0 ] || die "No hay trabajos para retomar. Para una sesión local en blanco: $STACK_NAME local"
    if [ ${#pend[@]} -eq 1 ]; then
      h="${pend[0]}"
    else
      echo "Trabajos para retomar:"
      for f in "${pend[@]}"; do i=$((i + 1)); printf '  %s) %s\n' "$i" "$(head -1 "$f" | sed 's/^# Traspaso — //')"; done
      ask "¿Cuál retomo?" n 1 motor_cual
      h="${pend[$(( ${n:-1} - 1 ))]}"
    fi
  fi
  [ -f "$h" ] || die "No existe: $h"
  local cwd
  cwd="$(sed -n 's/^- Directorio: `\([^`]*\)`.*/\1/p' "$h" | head -1)"
  [ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd"

  "$STACK_SRC/bin/ideasbox-fallback" checkpoint "$h"
  touch "${h%.md}.retomado"
  printf '\033[1;33mRetomando en el motor local: %s\033[0m\n' "$(head -1 "$h" | sed 's/^# Traspaso — //')"
  grep -m1 '^- Volver a Claude' "$h" || true
  echo
  # Leer es inofensivo: pre-autorizado para que arranque solo; editar y ejecutar siguen pidiendo confirmación.
  local resp
  resp="$(fallback_conf_get RESPALDO)"
  if [ -n "$resp" ] && [ "$resp" != local ] && nube_conectada "$resp"; then MOTOR_PROVEEDOR="$resp"; fi
  MOTOR_PROVEEDOR="${MOTOR_PROVEEDOR:-local}" motor_session --allowedTools Read "Estás retomando una tarea que venía haciendo Claude y se cortó por el límite de uso. \
Leé el archivo de traspaso $h con la herramienta Read. Resumime en 3 a 5 líneas en qué estado quedó y cuál es el \
próximo paso, y esperá mi confirmación antes de hacer cambios. Al terminar el trabajo, agregá a ese archivo la \
sección '## Lo que hizo el motor local'."
}

motor_status() {
  echo "Uso del plan de Claude:"
  "$STACK_SRC/bin/ideasbox-fallback" status
  echo
  if motor_installed 2>/dev/null; then
    printf '  motor local    instalado (%s) · RAM libre %s GB · apertura automática %s\n' \
      "$MOTOR_MODEL" "$(motor_free_gb)" "$([ "$(fallback_conf_get AUTO_OPEN)" = 0 ] && echo apagada || echo encendida)"
  else
    printf '  motor local    no instalado (%s motor install)\n' "$STACK_NAME"
  fi
  local prov
  for prov in $NUBE_PROVEEDORES; do
    if nube_conectada "$prov"; then
      printf '  %-14s conectado (%s) · %s con %s\n' "$prov" "$(fallback_conf_get "MODELO_$(printf '%s' "$prov" | tr 'a-z' 'A-Z')")" "$STACK_NAME" "$prov"
    else
      printf '  %-14s no conectado (%s motor conectar %s)\n' "$prov" "$STACK_NAME" "$prov"
    fi
  done
  printf '  respaldo       si se agota Claude: %s\n' "$(fallback_conf_get RESPALDO | grep . || echo local)"
}

motor_main() {
  case "${1:-status}" in
    install) motor_install ;;
    status) motor_status ;;
    auto)
      case "${2:-}" in
        on) fallback_conf_set AUTO_OPEN 1; ok "Al agotarse Claude, el motor local se abre solo." ;;
        off) fallback_conf_set AUTO_OPEN 0; ok "Al agotarse Claude, solo aviso: retomás con $STACK_NAME continuar." ;;
        *) die "Uso: $STACK_NAME motor auto on|off" ;;
      esac ;;
    conectar) nube_conectar "${2:-}" ;;
    respaldo)
      case "${2:-}" in
        local) fallback_conf_set RESPALDO local ;;
        openai|gemini) nube_conectada "$2" || die "Primero: $STACK_NAME motor conectar $2"; fallback_conf_set RESPALDO "$2" ;;
        *) die "Uso: $STACK_NAME motor respaldo local|openai|gemini" ;;
      esac
      fallback_conf_set MOTOR 1
      ok "Si se agota Claude, el trabajo sigue en: $2" ;;
    remove)
      fallback_conf_set MOTOR 0
      have ollama && ollama rm "$MOTOR_MODEL" >/dev/null 2>&1 || true
      ok "Motor local desactivado. Ollama y el modelo base quedan; para borrarlos: ollama rm $MOTOR_MODEL_BASE" ;;
    *) die "Uso: $STACK_NAME motor install|status|conectar openai|gemini|respaldo local|openai|gemini|auto on|off|remove" ;;
  esac
}
