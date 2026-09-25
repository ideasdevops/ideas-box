#!/usr/bin/env bash
# Menú en lenguaje común. Es la puerta de entrada para quien no conoce la terminal:
# se abre con doble clic en el ícono de Ideas Box o escribiendo `ideasbox` a secas, y
# acepta un número o una frase ("conectar chatwoot", "crear una habilidad").
# Cada acción corre el comando técnico equivalente en un proceso aparte, así un error
# no cierra el menú.

IDEASBOX_BIN="$STACK_SRC/bin/ideasbox"
MENU_LOOP=0   # 1 mientras el menú está abierto; una frase directa no tiene menú al que volver

# Nombres en lenguaje común de las áreas de trabajo (DOMINIOS en canonical.sh)
area_label() {
  case "$1" in
    core) echo "general" ;;           dev) echo "desarrollo" ;;
    ops) echo "servidores y operaciones" ;;  qa) echo "pruebas y calidad" ;;
    ventas) echo "ventas" ;;          marketing) echo "marketing" ;;
    contenido) echo "contenido y redes" ;;   clientes) echo "atención a clientes" ;;
    internos) echo "procesos internos" ;;    *) echo "$1" ;;
  esac
}

# Una instalación cortada a mitad ya tiene perfil pero todavía no sirve: el menú
# ofrece terminarla en lugar de mostrar opciones que fallarían.
install_pending() { [ -s "$STACK_CONFIG_DIR/install.state" ]; }
stack_installed() { [ -f "$STACK_PROFILE" ] && ! install_pending; }

_menu_pause() {
  [ "$MENU_LOOP" = 1 ] && [ -n "$STACK_TTY" ] || return 0
  local _r
  read -r -u 3 -p "Enter para volver al menú " _r || true
}

# Corre una acción del CLI en un proceso aparte: si falla, el menú sigue abierto
_menu_run() {
  echo
  if bash "$IDEASBOX_BIN" "$@"; then :; else warn "La acción terminó con un error. Podés reintentarla desde el menú."; fi
  _menu_pause
}

# Abre Claude con un pedido ya escrito, para que la persona siga la charla desde ahí
menu_open_claude() {
  local prompt="${1:-}"
  if ! have claude; then
    warn "Claude Code no está disponible en esta terminal. Abrí una terminal nueva y escribí: claude"
    return 1
  fi
  info "Abriendo Claude. Para volver al menú, escribí /exit o apretá Ctrl+D dos veces."
  if [ -n "$prompt" ]; then (cd "$HOME" && claude "$prompt") || true
  else (cd "$HOME" && claude) || true
  fi
}

# --- Interpretación de frases -------------------------------------------------
# Devuelve una acción: hablar, instalar, revisar, skills-add[:pack], skills-new,
# mcp-add[:id], mcp-new, actualizar, respaldo, salir o nada (no se entendió).
_menu_ids_mcp()   { mcp_catalog_ids; }
_menu_ids_packs() { _pack_rows | awk -F'\t' '{print $1}'; }

# ¿La frase nombra este id? Vale el id entero o su primera parte ("brave" → brave-search)
_menu_names() {
  local t="$1" id="$2" corto="${2%%-*}"
  case "$t" in *" $id "*) return 0 ;; esac
  [ ${#corto} -ge 4 ] && case "$t" in *" $corto "*) return 0 ;; esac
  return 1
}

menu_intent() {
  local t id crear=0 skill=0 mcp=0
  t=" $(normaliza "$*" | tr -c 'a-z0-9-' ' ') "
  case "$t" in *" salir "*|*" chau "*|*" nada "*|*" exit "*|*" terminar "*) echo salir; return ;; esac
  case "$t" in *crear*|*crea\ *|*nuev*|*armar*|*arma\ *|*propi*|*escribir*|*" no esta "*|*" no aparece "*|*" otra "*|*falta*) crear=1 ;; esac
  case "$t" in *habilidad*|*skill*|*pack*|*destreza*) skill=1 ;; esac
  case "$t" in *conect*|*herramienta*|*integr*|*mcp*|*servidor*|*aplicacion*|*app\ *) mcp=1 ;; esac

  if [ "$skill" = 1 ]; then
    [ "$crear" = 1 ] && { echo skills-new; return; }
    for id in $(_menu_ids_packs); do _menu_names "$t" "$id" && { echo "skills-add:$id"; return; }; done
    echo skills-add; return
  fi
  for id in $(_menu_ids_mcp); do _menu_names "$t" "$id" && { echo "mcp-add:$id"; return; }; done
  if [ "$mcp" = 1 ]; then
    [ "$crear" = 1 ] && echo mcp-new || echo mcp-add
    return
  fi
  case "$t" in
    *icono*|*acceso*directo*|*escritorio*) echo icono ;;
    *revis*|*diagnost*|*doctor*|*chequ*|*control*|*estado*|*funciona*|*anda\ *|*problema*|*error*) echo revisar ;;
    *actualiz*|*update*) echo actualizar ;;
    *respald*|*backup*|*copia*|*resguard*) echo respaldo ;;
    *instal*|*configur*|*empezar\ de*|*rehacer*) echo instalar ;;
    *hablar*|*agente*|*claude*|*abrir*|*chat*|*trabaj*|*empez*|*preguntar*) echo hablar ;;
    *) echo nada ;;
  esac
}

# --- Acciones con elección guiada ---------------------------------------------

menu_skills_add() {
  local -a ids=() ; local id tier dom repo sub desc i=0 choice
  echo
  echo "Habilidades que podés sumar (cada una es un paquete de conocimientos para tus agentes):"
  echo
  while IFS=$'\t' read -r id tier dom repo sub desc; do
    i=$((i+1)); ids+=("$id")
    printf '  %d) %s — %s\n' "$i" "$id" "$desc"
  done < <(_pack_rows)
  echo
  ask "¿Cuál sumamos? (número, o Enter para volver)" choice ""
  case "$choice" in ''|*[!0-9]*) return 0 ;; esac
  [ "$choice" -ge 1 ] && [ "$choice" -le "$i" ] || { warn "Ese número no está en la lista."; return 0; }
  _menu_run skills add "${ids[$((choice-1))]}"
}

menu_mcp_add() {
  local -a ids=(); local id i=0 choice estado
  echo
  echo "Herramientas que podés conectar a tus agentes:"
  echo
  for id in $(mcp_catalog_ids); do
    ( mcp_catalog_load "$id"; [ "$TIER" != core ] ) || continue
    i=$((i+1)); ids+=("$id")
    estado=""; mcp_id_installed "$id" && estado="  (ya conectada)"
    printf '  %d) %s%s\n' "$i" "$(mcp_catalog_load "$id"; printf '%s' "$TITLE")" "$estado"
  done
  echo
  echo "Tené a mano los datos de acceso (usuario, clave o token) de la herramienta: te los voy a pedir."
  ask "¿Cuál conectamos? (número, o Enter para volver)" choice ""
  case "$choice" in ''|*[!0-9]*) return 0 ;; esac
  [ "$choice" -ge 1 ] && [ "$choice" -le "$i" ] || { warn "Ese número no está en la lista."; return 0; }
  _menu_run mcp add "${ids[$((choice-1))]}"
}

menu_mcp_new() {
  echo
  echo "Un conector nuevo le da a tus agentes acceso a una herramienta que no está en la lista."
  echo "Solo conviene sumar conectores de fuentes confiables: corren en tu equipo con tus credenciales."
  echo
  echo "  1) Que me ayude Claude (recomendado si no sabés por dónde empezar)"
  echo "  2) Tengo la línea de instalación de la documentación (empieza con npx o uvx)"
  echo
  local choice herramienta
  ask "Opción (o Enter para volver)" choice ""
  case "$choice" in
    1)
      ask "¿Qué herramienta querés conectar? (ej: Google Calendar, Notion, tu CRM)" herramienta ""
      [ -n "$herramienta" ] || return 0
      menu_open_claude "Quiero conectar $herramienta a Ideas Box. Usá la habilidad ideas-box-admin: buscá un conector MCP confiable para $herramienta, revisá que sea seguro, explicame qué va a poder hacer y armá el conector propio. Las credenciales las cargo yo desde el menú."
      _menu_pause
      ;;
    2) _menu_run mcp new ;;
    *) return 0 ;;
  esac
}

# --- Menú principal -----------------------------------------------------------

_menu_do() {
  local accion="$1" arg=""
  case "$accion" in *:*) arg="${accion#*:}"; accion="${accion%%:*}" ;; esac
  if [ "$accion" != instalar ] && [ "$accion" != salir ] && [ "$accion" != nada ] && ! stack_installed; then
    warn "Primero hay que terminar de instalar Ideas Box: elegí la opción 1 del menú."
    return 0
  fi
  case "$accion" in
    hablar)     menu_open_claude ""; _menu_pause ;;
    instalar)   echo; bash "$STACK_SRC/install.sh" || true; _menu_pause ;;
    revisar)    _menu_run doctor ;;
    skills-add) if [ -n "$arg" ]; then _menu_run skills add "$arg"; else menu_skills_add; fi ;;
    skills-new) _menu_run skills new ;;
    mcp-add)    if [ -n "$arg" ]; then _menu_run mcp add "$arg"; else menu_mcp_add; fi ;;
    mcp-new)    menu_mcp_new ;;
    actualizar) _menu_run update ;;
    respaldo)   _menu_run backup ;;
    icono)      _menu_run icono ;;
    salir)      return 1 ;;
    *)          warn "No te entendí. Elegí un número de la lista o probá con otras palabras (ej: «conectar chatwoot»)." ;;
  esac
  return 0
}

menu_main() {
  # Una frase directa (`ideasbox conectar chatwoot`) se resuelve sin mostrar el menú
  if [ $# -gt 0 ]; then
    stack_installed && load_profile
    _menu_do "$(menu_intent "$@")" || true
    return 0
  fi
  [ -n "$STACK_TTY" ] || { usage; return 0; }

  local choice accion
  MENU_LOOP=1
  while :; do
    stack_installed && load_profile
    echo
    printf '%s  IDEAS BOX%s' "$C_B" "$C_RESET"
    stack_installed && printf ' · %s' "$EMPRESA_NOMBRE"
    printf '\n  ¿Qué hacemos?\n\n'
    if stack_installed; then
      echo "  1) Hablar con mis agentes"
      echo "  2) Revisar que todo esté bien"
      echo "  3) Sumar habilidades"
      echo "  4) Conectar una herramienta"
      echo "  5) Crear una habilidad nueva"
      echo "  6) Crear un conector nuevo"
      echo "  7) Actualizar todo"
      echo "  8) Hacer un respaldo"
      echo "  9) Completar o rehacer la instalación"
    else
      if install_pending; then echo "  1) Terminar de instalar mi Ideas Box (quedó a mitad)"
      else echo "  1) Instalar mi Ideas Box"
      fi
      echo
      echo "  (el resto de las opciones aparece cuando termine la instalación)"
    fi
    echo "  0) Salir"
    echo
    ask "Elegí un número o escribí lo que querés hacer" choice ""
    if stack_installed; then
      case "$choice" in
        1) accion=hablar ;; 2) accion=revisar ;; 3) accion=skills-add ;; 4) accion=mcp-add ;;
        5) accion=skills-new ;; 6) accion=mcp-new ;; 7) accion=actualizar ;; 8) accion=respaldo ;;
        9) accion=instalar ;; 0) accion=salir ;; '') continue ;; *) accion="$(menu_intent "$choice")" ;;
      esac
    else
      case "$choice" in
        1) accion=instalar ;; 0) accion=salir ;; '') continue ;; *) accion="$(menu_intent "$choice")" ;;
      esac
    fi
    _menu_do "$accion" || break
  done
  echo "Hasta luego."
}

# --- Accesos directos ---------------------------------------------------------
# Un ícono para abrir el menú sin escribir comandos: .command en macOS (Finder lo abre
# en Terminal con doble clic) y una entrada .desktop en Linux. Los dos llevan el logo
# de assets/icon/; sin él quedaban con el ícono genérico de script o de terminal.

# macOS: el ícono propio de un archivo vive en sus atributos extendidos, no en el
# contenido; NSWorkspace lo escribe sin pedir permisos de automatización. Si falla,
# el acceso directo igual funciona con el ícono genérico.
_mac_set_icon() {
  local png="$1" file="$2"
  [ -f "$png" ] && have osascript || return 0
  run osascript -l JavaScript -e '
    function run(argv) {
      ObjC.import("AppKit");
      var img = $.NSImage.alloc.initWithContentsOfFile(argv[0]);
      if (!$.NSWorkspace.sharedWorkspace.setIconForFileOptions(img, argv[1], 0)) throw "setIcon";
    }' "$png" "$file" >/dev/null 2>&1 || warn "No se pudo ponerle el logo al ícono; funciona igual."
  return 0
}

# Linux: el logo va al tema de íconos del usuario, así no depende de dónde quedó el
# repo. Imprime la ruta que va en Icon= (absoluta: sirve aunque el tema no se refresque).
_linux_install_icon() {
  local src="$STACK_SRC/assets/icon" base="$HOME/.local/share/icons/hicolor" s
  [ -f "$src/ideas-box-512.png" ] || { echo utilities-terminal; return 0; }
  {
    for s in 256 512; do
      run mkdir -p "$base/${s}x${s}/apps"
      run cp "$src/ideas-box-$s.png" "$base/${s}x${s}/apps/ideas-box.png"
    done
    run mkdir -p "$base/scalable/apps"
    run cp "$src/ideas-box.svg" "$base/scalable/apps/ideas-box.svg"
    have gtk-update-icon-cache && [ -f "$base/index.theme" ] && run gtk-update-icon-cache -q "$base" 2>/dev/null
  } >&2   # stdout queda solo para la ruta (en --dry-run, run también imprime)
  echo "$base/512x512/apps/ideas-box.png"
}

menu_install_shortcut() {
  local cli="$HOME/.local/bin/$STACK_NAME" desk
  if is_mac; then
    desk="$HOME/Desktop"
    [ -d "$desk" ] || return 0
    confirm "¿Crear el ícono «Ideas Box» en tu Escritorio? (macOS puede pedir permiso para acceder al Escritorio)" y || return 0
    write_file "$desk/Ideas Box.command" 755 <<EOF
#!/bin/bash
# Doble clic: abre el menú de Ideas Box en una Terminal.
exec "$cli" menu
EOF
    _mac_set_icon "$STACK_SRC/assets/icon/ideas-box-512.png" "$desk/Ideas Box.command"
    ok "Ícono creado: Escritorio → Ideas Box"
    return 0
  fi

  local apps="$HOME/.local/share/applications" icon
  icon="$(_linux_install_icon)"
  write_file "$apps/ideas-box.desktop" 755 <<EOF
[Desktop Entry]
Type=Application
Name=Ideas Box
Comment=Menú de tu empresa online híbrida
Exec="$cli" menu
Terminal=true
Icon=$icon
Categories=Office;Utility;
EOF
  ok "Ideas Box quedó en el menú de aplicaciones"
  desk="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
  if [ -d "$desk" ] && [ "$desk" != "$HOME" ] && confirm "¿Crear también el ícono en tu Escritorio?" y; then
    run cp "$apps/ideas-box.desktop" "$desk/ideas-box.desktop"
    run chmod 755 "$desk/ideas-box.desktop"
    have gio && run gio set "$desk/ideas-box.desktop" metadata::trusted true 2>/dev/null || true
    ok "Ícono creado en el Escritorio"
  fi
}
