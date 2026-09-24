#!/usr/bin/env bash
# Avance de la instalación. Cada paso que termina queda anotado; si install.sh se corta
# (un error, Ctrl+C, se cerró la terminal), la próxima corrida ofrece retomar: carga
# las respuestas ya dadas y salta a lo que falta. Al terminar bien, el archivo se borra.

STACK_STATE="$STACK_CONFIG_DIR/install.state"
RESUME=0
STATE_CURRENT=""
STATE_MAX_RETRY=5

# Nombres legibles de cada paso, para decirle al usuario dónde quedó
_state_label() {
  case "$1" in
    deps) echo "dependencias" ;;     perfil) echo "identidad de la empresa" ;;
    datos) echo "raíz de datos" ;;   packs) echo "packs de skills" ;;
    mcp) echo "conectores MCP" ;;    canonico) echo "agentes y skills" ;;
    settings) echo "configuración de Claude Code" ;;  cli) echo "comando $STACK_NAME" ;;
    panel) echo "panel de control" ;; *) echo "$1" ;;
  esac
}

state_is_done() { [ -f "$STACK_STATE" ] && grep -qx "$1" "$STACK_STATE"; }

state_done() {
  [ "$DRY_RUN" = 1 ] && return 0
  mkdir -p "$STACK_CONFIG_DIR"
  state_is_done "$1" || printf '%s\n' "$1" >> "$STACK_STATE"
}

state_clear() { [ "$DRY_RUN" = 1 ] || rm -f "$STACK_STATE"; }

_state_list() {
  local s out=""
  while IFS= read -r s; do out="${out:+$out, }$(_state_label "$s")"; done < "$STACK_STATE"
  printf '%s' "$out"
}

# run_step <id> <comando...> — corre el paso salvo que ya se haya hecho en la corrida anterior
run_step() {
  local id="$1"; shift
  if [ "$RESUME" = 1 ] && state_is_done "$id"; then
    ok "Ya hecho en la corrida anterior: $(_state_label "$id")"
    return 0
  fi
  STATE_CURRENT="$id"
  "$@"
  state_done "$id"
  STATE_CURRENT=""
}

state_offer_resume() {
  [ -s "$STACK_STATE" ] || return 0
  # Relanzado por state_on_exit tras elegir reintentar: se retoma sin volver a preguntar
  if [ "${IB_AUTO_RESUME:-0}" = 1 ]; then
    RESUME=1
    [ -f "$STACK_PROFILE" ] && state_is_done perfil && load_profile
    ok "Reintento ${IB_INSTALL_RETRY:-1} de $STATE_MAX_RETRY: sigo desde lo que faltaba"
    return 0
  fi
  echo
  warn "La instalación anterior quedó a mitad."
  info "Ya estaba completo: $(_state_list)"
  if confirm "¿Retomar desde donde quedó? (se reusan las respuestas que ya diste)" y; then
    RESUME=1
    [ -f "$STACK_PROFILE" ] && state_is_done perfil && load_profile
    ok "Retomando${EMPRESA_NOMBRE:+ la instalación de $EMPRESA_NOMBRE}"
  else
    state_clear
    info "Empiezo de cero. Lo que ya estaba instalado se detecta y no se baja de nuevo."
  fi
}

# Trap de salida: si algo cortó la instalación, avisar que el avance no se perdió
state_on_exit() {
  local rc=$?
  [ "$rc" = 0 ] && return 0
  [ "$DRY_RUN" = 1 ] && return 0
  echo >&2
  [ -n "$STATE_CURRENT" ] && warn "La instalación se cortó durante el paso: $(_state_label "$STATE_CURRENT")."
  [ -s "$STACK_STATE" ] && warn "Lo que ya completaste quedó guardado: $(_state_list)."
  state_offer_retry "$rc"
  [ -s "$STACK_STATE" ] || return 0
  warn "Para seguir desde ahí, abrí de nuevo el menú de Ideas Box y elegí «Terminar de instalar»"
  warn "(o en la terminal: bash install.sh). Respondé que sí a retomar."
}

# Tras un corte, ofrece reintentar en el acto: el instalador se relanza a sí mismo (con el
# código actualizado, si se corrigió algo mientras tanto) y sigue desde el paso que falló.
# El paso fallido no quedó marcado, así que se repite; si fueron las dependencias, también.
# No se ofrece con Ctrl+C, sin terminal, con --yes/--non-interactive (sería un bucle sin
# fin ante un error que no cambia) ni después de STATE_MAX_RETRY intentos.
state_offer_retry() {
  local rc="$1" n="${IB_INSTALL_RETRY:-0}"
  case "$rc" in 130|143) return 0 ;; esac
  [ -n "$STACK_TTY" ] && [ "$NON_INTERACTIVE" != 1 ] && [ "$ASSUME_YES" != 1 ] || return 0
  if [ "$n" -ge "$STATE_MAX_RETRY" ]; then
    warn "Ya van $n reintentos con el mismo resultado: hace falta revisar el error de arriba."
    return 0
  fi
  echo >&2
  info "Si el error de arriba se puede resolver (conexión, credencial, instalar algo), resolvelo y seguí."
  confirm "¿Reintentar ahora desde ese paso?" y || return 0
  trap - EXIT
  exec env IB_AUTO_RESUME=1 IB_INSTALL_RETRY=$((n + 1)) \
    bash "$STACK_SRC/install.sh" ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}
}
