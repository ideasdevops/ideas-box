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
    warn "No encuentro Claude Code en este equipo (busqué en el PATH y en ~/.local/bin)."
    info "Instalalo con: curl -fsSL https://claude.ai/install.sh | bash   y volvé a abrir Ideas Box."
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
    *panel*|*tablero*|*tarea*|*programa*|*agenda*) echo panel ;;
    *revis*|*diagnost*|*doctor*|*chequ*|*control*|*estado*|*funciona*|*anda\ *|*problema*|*error*) echo revisar ;;
    *actualiz*|*update*) echo actualizar ;;
    *respald*|*backup*|*copia*|*resguard*) echo respaldo ;;
    *archivo*|*carpeta*|*generad*|*entregable*|*documento*) echo carpeta ;;
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
    # El asistente gráfico; si no se puede mostrar, install.sh sigue solo en la terminal
    instalar)   echo; bash "$STACK_SRC/install.sh" --gui || true; _menu_pause ;;
    revisar)    _menu_run doctor ;;
    skills-add) if [ -n "$arg" ]; then _menu_run skills add "$arg"; else menu_skills_add; fi ;;
    skills-new) _menu_run skills new ;;
    mcp-add)    if [ -n "$arg" ]; then _menu_run mcp add "$arg"; else menu_mcp_add; fi ;;
    mcp-new)    menu_mcp_new ;;
    actualizar) _menu_run update ;;
    respaldo)   _menu_run backup ;;
    icono)      _menu_run icono ;;
    panel)      _menu_run panel open ;;
    carpeta)    _menu_run carpeta ;;
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
      echo " 10) Abrir el panel de tareas y programación"
      echo " 11) Abrir la carpeta con lo que generan mis agentes"
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
        9) accion=instalar ;; 10) accion=panel ;; 11) accion=carpeta ;; 0) accion=salir ;; '') continue ;; *) accion="$(menu_intent "$choice")" ;;
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
# Dos íconos para no escribir comandos: «Ideas Box» abre el menú (en una terminal) y
# «Panel Ideas Box» levanta el tablero de tareas y lo abre en el navegador (sin terminal).
# Menú: .command en macOS (Finder lo abre en Terminal), .desktop en Linux, .lnk en WSL.
# Panel: una mini app hecha con osacompile en macOS, .desktop sin terminal en Linux y
# .lnk en WSL. Cada uno lleva su logo de assets/icon/ (ideas-box-* y panel-*).

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
# _linux_install_icon [origen] [nombre] — origen: prefijo en assets/icon (ideas-box, panel);
# nombre: cómo queda en el tema de íconos.
_linux_install_icon() {
  local from="${1:-ideas-box}" name="${2:-ideas-box}" fallback="${3:-utilities-terminal}"
  local src="$STACK_SRC/assets/icon" base="$HOME/.local/share/icons/hicolor" s
  [ -f "$src/$from-512.png" ] || { echo "$fallback"; return 0; }
  {
    for s in 256 512; do
      run mkdir -p "$base/${s}x${s}/apps"
      run cp "$src/$from-$s.png" "$base/${s}x${s}/apps/$name.png"
    done
    run mkdir -p "$base/scalable/apps"
    run cp "$src/$from.svg" "$base/scalable/apps/$name.svg"
    have gtk-update-icon-cache && [ -f "$base/index.theme" ] && run gtk-update-icon-cache -q "$base" 2>/dev/null
  } >&2   # stdout queda solo para la ruta (en --dry-run, run también imprime)
  echo "$base/512x512/apps/$name.png"
}

# _linux_desktop_to_desk <archivo .desktop> <pregunta> [clave del asistente] — copia opcional al Escritorio
_linux_desktop_to_desk() {
  local entry="$1" question="$2" key="${3:-}" desk
  desk="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
  if [ -d "$desk" ] && [ "$desk" != "$HOME" ] && confirm "$question" y "$key"; then
    run cp "$entry" "$desk/$(basename "$entry")"
    run chmod 755 "$desk/$(basename "$entry")"
    have gio && run gio set "$desk/$(basename "$entry")" metadata::trusted true 2>/dev/null || true
    ok "Ícono creado en el Escritorio"
  fi
  return 0
}

# WSL: un .desktop dentro de Ubuntu no aparece en Windows. Se crea un acceso directo .lnk
# de Windows (menú Inicio y, si se acepta, Escritorio) que abre wsl.exe en esta distro y
# lanza el menú. El .ico se copia a %LOCALAPPDATA%\IdeasBox: apuntarlo a \\wsl.localhost
# deja el ícono en blanco mientras la distro está apagada.
_wsl_powershell() {
  local p
  p="$(command -v powershell.exe 2>/dev/null)" && { echo "$p"; return 0; }
  p="$(wslpath -u 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' 2>/dev/null)"
  [ -x "$p" ] && echo "$p"
}

# -EncodedCommand (UTF-16LE en base64) evita pelear con las comillas entre bash y Windows
_wsl_ps_run() {
  run "$1" -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand \
    "$(printf '%s' "$2" | iconv -f UTF-8 -t UTF-16LE | base64 | tr -d '\n')" >/dev/null
}

# _wsl_make_shortcut <nombre> <comando> <descripción> <.ico> <pregunta> <estilo> [clave del asistente]
# Crea «<nombre>.lnk» en el menú Inicio y, si se acepta, en el Escritorio de Windows; el
# acceso abre wsl.exe en esta distro y corre <comando> con el PATH del usuario.
# Estilo de ventana: 1 normal, 7 minimizada.
_wsl_make_shortcut() {
  local name="$1" cmd="$2" desc="$3" ico_src="$4" question="$5" style="${6:-1}" key="${7:-}"
  local ps ico_win ico_base distro args desk_ps='$false' script
  ps="$(_wsl_powershell)" || ps=""
  if [ -z "$ps" ] || ! have wslpath || ! have iconv || ! have base64; then
    warn "No pude hablar con Windows desde Ubuntu (¿interoperabilidad de WSL desactivada?)."
    info "Desde la terminal de Ubuntu: $cmd"
    return 0
  fi
  confirm "$question" y "$key" && desk_ps='$true'
  ico_win="$(wslpath -w "$ico_src")"
  ico_base="$(basename "$ico_src")"
  distro="${WSL_DISTRO_NAME:+-d $WSL_DISTRO_NAME }"
  # bash -li: carga el PATH del usuario (nvm, ~/.local/bin) como una terminal normal
  args="${distro}--cd ~ -e bash -lic \"exec $cmd\""
  script="\$ErrorActionPreference = 'Stop'
\$dir = Join-Path \$env:LOCALAPPDATA 'IdeasBox'
New-Item -ItemType Directory -Force -Path \$dir | Out-Null
\$ico = Join-Path \$dir '${ico_base//\'/\'\'}'
Copy-Item -LiteralPath '${ico_win//\'/\'\'}' -Destination \$ico -Force
\$targets = @([Environment]::GetFolderPath('Programs'))
if ($desk_ps) { \$targets += [Environment]::GetFolderPath('Desktop') }
\$wsh = New-Object -ComObject WScript.Shell
foreach (\$d in \$targets) {
  \$l = \$wsh.CreateShortcut((Join-Path \$d '${name//\'/\'\'}.lnk'))
  \$l.TargetPath = Join-Path \$env:SystemRoot 'System32\\wsl.exe'
  \$l.Arguments = '${args//\'/\'\'}'
  \$l.IconLocation = \"\$ico,0\"
  \$l.Description = '${desc//\'/\'\'}'
  \$l.WorkingDirectory = \$env:USERPROFILE
  \$l.WindowStyle = $style
  \$l.Save()
}"
  if _wsl_ps_run "$ps" "$script"; then
    ok "$name quedó en el menú Inicio de Windows"
    [ "$desk_ps" = '$true' ] && ok "Ícono «${name}» creado en el Escritorio de Windows"
  else
    warn "Windows no dejó crear el acceso directo «${name}». Desde Ubuntu: $cmd"
  fi
  return 0
}

_wsl_install_shortcut() {
  _wsl_make_shortcut "Ideas Box" "'$1' menu" "Menú de tu empresa online híbrida" \
    "$STACK_SRC/assets/icon/ideas-box.ico" \
    "¿Crear también el ícono «Ideas Box» en tu Escritorio de Windows?" 1 shortcut_menu
}

menu_install_shortcut() {
  local cli="$HOME/.local/bin/$STACK_NAME" desk
  if is_wsl; then
    _wsl_install_shortcut "$cli"
    return 0
  fi
  if is_mac; then
    desk="$HOME/Desktop"
    [ -d "$desk" ] || return 0
    confirm "¿Crear el ícono «Ideas Box» en tu Escritorio? (macOS puede pedir permiso para acceder al Escritorio)" y shortcut_menu || return 0
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
  _linux_desktop_to_desk "$apps/ideas-box.desktop" "¿Crear también el ícono en tu Escritorio?" shortcut_menu
}

# macOS: una app mínima (AppleScript compilado con osacompile, que viene con el sistema)
# en vez de un .command, para que el doble clic no deje una Terminal abierta. `do shell
# script` muestra solo el error si el comando falla. Se reemplaza únicamente una app que
# hayamos creado nosotros (tiene nuestro script compilado adentro).
_mac_make_app() {
  local app="$1" cli="$2" args="$3" png="$4"
  have osacompile || return 1
  if [ -e "$app" ]; then
    [ -f "$app/Contents/Resources/Scripts/main.scpt" ] || { warn "$app existe y no es nuestro; lo dejo como está."; return 0; }
    run rm -rf "$app"
  fi
  run osacompile -o "$app" \
    -e "do shell script (quoted form of \"$cli\") & \" $args\"" >/dev/null 2>&1 || return 1
  _mac_set_icon "$png" "$app"
  return 0
}

# «Panel Ideas Box»: levanta el tablero de tareas si hace falta y lo abre en el navegador
panel_install_shortcut() {
  local cli="$HOME/.local/bin/$STACK_NAME" desk name="Panel Ideas Box"
  if is_wsl; then
    # Ventana minimizada que mantiene vivo el panel: WSL puede apagar la distro cuando no
    # queda ninguna sesión de wsl.exe. Cerrarla apaga el panel.
    _wsl_make_shortcut "$name" "'$cli' panel open --keep" "Tablero de tareas y programación de tus agentes" \
      "$STACK_SRC/assets/icon/panel.ico" \
      "¿Crear también el ícono «${name}» en tu Escritorio de Windows?" 7 shortcut_panel
    return 0
  fi
  if is_mac; then
    desk="$HOME/Desktop"
    [ -d "$desk" ] || return 0
    confirm "¿Crear el ícono «${name}» en tu Escritorio?" y shortcut_panel || return 0
    if _mac_make_app "$desk/$name.app" "$cli" "panel open" "$STACK_SRC/assets/icon/panel-512.png"; then
      ok "Ícono creado: Escritorio → $name"
    else
      # Sin osacompile: un .command, que abre una Terminal pero funciona igual
      write_file "$desk/$name.command" 755 <<EOF
#!/bin/bash
# Doble clic: levanta el panel de Ideas Box y lo abre en el navegador.
exec "$cli" panel open
EOF
      _mac_set_icon "$STACK_SRC/assets/icon/panel-512.png" "$desk/$name.command"
      ok "Ícono creado: Escritorio → $name"
    fi
    return 0
  fi

  local apps="$HOME/.local/share/applications" icon
  icon="$(_linux_install_icon panel ideas-box-panel x-office-calendar)"
  write_file "$apps/ideas-box-panel.desktop" 755 <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=Tablero de tareas y programación de tus agentes
Exec="$cli" panel open
Terminal=false
Icon=$icon
Categories=Office;ProjectManagement;
EOF
  ok "$name quedó en el menú de aplicaciones"
  _linux_desktop_to_desk "$apps/ideas-box-panel.desktop" "¿Crear también el ícono «${name}» en tu Escritorio?" shortcut_panel
}

# «Archivos Ideas Box»: la raíz de datos, donde cada agente guarda lo que genera en su
# carpeta (06-CONTENIDO, 07-DOCUMENTOS, 10-PROSPECCIONES…). En macOS y Linux es un enlace
# simbólico en el Escritorio (Finder y los gestores de archivos lo abren como carpeta); en
# WSL, un .lnk de Windows a la ruta \\wsl.localhost\… que da wslpath.
FOLDER_SHORTCUT_NAME="Archivos Ideas Box"

data_install_shortcut() {
  local name="$FOLDER_SHORTCUT_NAME" desk link q
  q="¿Crear en tu Escritorio el acceso «${name}», la carpeta donde tus agentes guardan lo que generan?"
  if [ -z "${DATA_ROOT:-}" ] || [ ! -d "$DATA_ROOT" ]; then
    warn "La raíz de datos no está disponible; no creo el acceso «${name}»."
    return 0
  fi
  if is_wsl; then
    local ps target
    ps="$(_wsl_powershell)" || ps=""
    if [ -z "$ps" ] || ! have wslpath || ! have iconv || ! have base64; then
      info "Tus archivos están en: $DATA_ROOT"
      return 0
    fi
    confirm "$q" y shortcut_data || return 0
    target="$(wslpath -w "$DATA_ROOT")"
    if _wsl_ps_run "$ps" "\$ErrorActionPreference = 'Stop'
\$l = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) '${name//\'/\'\'}.lnk'))
\$l.TargetPath = '${target//\'/\'\'}'
\$l.Description = 'Lo que generan tus agentes'
\$l.Save()"; then
      ok "Acceso «${name}» creado en el Escritorio de Windows"
    else
      warn "Windows no dejó crear el acceso «${name}». Tus archivos están en: $DATA_ROOT"
    fi
    return 0
  fi

  if is_mac; then desk="$HOME/Desktop"
  else desk="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
  fi
  [ -d "$desk" ] && [ "$desk" != "$HOME" ] || return 0
  link="$desk/$name"
  # Solo se reemplaza un enlace; una carpeta o archivo real con ese nombre es del usuario
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    warn "Ya hay algo llamado «${name}» en tu Escritorio y no es un acceso nuestro; lo dejo como está."
    return 0
  fi
  confirm "$q" y shortcut_data || return 0
  run ln -sfn "$DATA_ROOT" "$link"
  ok "Acceso creado: Escritorio → $name"
}

# Abre la raíz de datos en el explorador de archivos del sistema
data_open_folder() {
  load_profile
  [ -d "$DATA_ROOT" ] || die "La raíz de datos no está disponible: $DATA_ROOT"
  if is_wsl && have wslpath && have explorer.exe; then
    explorer.exe "$(wslpath -w "$DATA_ROOT")" || true   # devuelve 1 aunque abra bien
  else
    _open_url "$DATA_ROOT"
  fi
  ok "Tus archivos: $DATA_ROOT"
}
