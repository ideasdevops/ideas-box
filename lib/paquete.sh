#!/usr/bin/env bash
# IdeasPackage: la empresa entera de Ideas Box en un pendrive o disco externo, para abrirla en
# cualquier equipo (también en uno que ya tiene su propio Ideas Box) sin tocar la configuración
# del dueño de ese equipo.
#
#   ideasbox paquete crear [destino]   empaqueta esta empresa en <destino>/IdeasPackage
#   ideasbox paquete buscar            lista los paquetes de los discos conectados
#   ideasbox paquete abrir [ruta]      «Hola <nombre>, ¿querés iniciar tu empresa en este equipo?»
#   ideasbox paquete guardar           guarda en el pendrive lo trabajado (también cada 10 min solo)
#   ideasbox paquete cerrar            guarda, apaga la sesión invitada y borra todo rastro
#   ideasbox paquete estado            qué paquete está abierto en este equipo
#
# Contenido del paquete (pensado para pendrives FAT/exFAT: sin symlinks ni permisos):
#   IdeasPackage/ideaspackage.json   manifiesto: propietario, empresa, fechas, versión
#   IdeasPackage/datos/              la raíz de datos (agentes, skills, memoria, trabajos, panel)
#   IdeasPackage/enlaces.tsv         symlinks de la raíz de datos (FAT no los guarda)
#   IdeasPackage/perfil.conf         identidad de la empresa (empresa.conf sin rutas del equipo)
#   IdeasPackage/conectores.tsv      conectores instalados (mcp-installed.tsv)
#   IdeasPackage/secretos.gpg        credenciales de los conectores, cifradas (AES-256, contraseña)
#   IdeasPackage/en-uso.json         presente mientras la empresa está abierta en algún equipo
#
# Sesión invitada: todo corre con un HOME propio en ~/.cache/ideaspackage/<slug>/home, así
# ~/.claude, ~/CLAUDE.md, ~/.claude.json y ~/.config/ideasbox del anfitrión nunca se leen ni se
# escriben. La copia de trabajo de los datos va al lado (datos/) y se sincroniza al pendrive al
# guardar y al cerrar. Las credenciales descifradas viven solo en memoria (XDG_RUNTIME_DIR, tmpfs).
# Lo que se puede reconstruir (venvs de los conectores) queda en cache/ para no rearmarlo cada vez.
# La cuenta de Claude se inicia en cada sesión y se borra al cerrar.

PKG_DIRNAME="IdeasPackage"
PKG_FORMAT=1
PKG_AUTOSAVE_MIN="${PKG_AUTOSAVE_MIN:-10}"
PKG_CACHE_ROOT="${IDEASPACKAGE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/ideaspackage}"
PKG_RUN_ROOT="${XDG_RUNTIME_DIR:-/dev/shm}"

_pkg_need() {
  local falta=() c
  for c in rsync gpg python3; do have "$c" || falta+=("$c"); done
  [ ${#falta[@]} -eq 0 ] || die "IdeasPackage necesita: ${falta[*]} (en Debian/Ubuntu/JFlowOS: sudo apt install ${falta[*]})"
}

_pkg_json() {  # _pkg_json <archivo> <clave.subclave> — lee un valor del manifiesto
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d.get(k, "") if isinstance(d, dict) else ""
print(d if not isinstance(d, (dict, list)) else json.dumps(d))
PY
}

_pkg_nombre_corto() { printf '%s' "${1%% *}"; }   # «Joaquín de Rosas» → «Joaquín»

# Discos externos montados: pendrives, discos USB (con o sin tabla de particiones), imágenes.
# → TSV: punto de montaje  tamaño  sistema de archivos  etiqueta
_pkg_externos() {
  if is_mac; then _candidate_mounts_macos; return; fi
  lsblk -rno MOUNTPOINT,SIZE,FSTYPE,LABEL 2>/dev/null | while read -r mnt size fs label; do
    case "$mnt" in /media/*|/mnt/*|/run/media/*) ;; *) continue ;; esac
    mnt="$(printf '%b' "$mnt")"   # lsblk escapa los espacios como \x20
    printf '%s\t%s\t%s\t%s\n' "$mnt" "$size" "${fs:-?}" "$(printf '%b' "${label:-sin-etiqueta}")"
  done
}

_pkg_montajes() { { _pkg_externos | cut -f1; _candidate_mounts | cut -f1; } | sort -u; }

# paquete_buscar → TSV: ruta  propietario  empresa  actualizado  en_uso
paquete_buscar() {
  local m p
  _pkg_montajes | while IFS= read -r m; do
    for p in "$m/$PKG_DIRNAME" "$m"/*/"$PKG_DIRNAME"; do
      [ -f "$p/ideaspackage.json" ] || continue
      printf '%s\t%s\t%s\t%s\t%s\n' "$p" "$(_pkg_json "$p/ideaspackage.json" propietario)" \
        "$(_pkg_json "$p/ideaspackage.json" empresa.nombre)" "$(_pkg_json "$p/ideaspackage.json" actualizado)" \
        "$([ -f "$p/en-uso.json" ] && _pkg_json "$p/en-uso.json" equipo)"
    done
  done
}

# --- crear --------------------------------------------------------------------

_pkg_elegir_destino() {
  local -a ops=() ; local m size fs label i=0 eleccion
  while IFS=$'\t' read -r m size fs label; do
    [ -w "$m" ] || continue
    ops+=("$m"); i=$((i+1))
    printf '  %d) %s  (%s, %s, %s)\n' "$i" "$m" "$label" "$size" "$fs"
  done < <(_pkg_externos)
  [ ${#ops[@]} -gt 0 ] || die "No encuentro ningún pendrive o disco externo conectado. Conectalo y volvé a intentar."
  ask "¿En cuál guardo el paquete? (número)" eleccion "1" pkg_destino
  [[ "$eleccion" =~ ^[0-9]+$ ]] && [ "$eleccion" -ge 1 ] && [ "$eleccion" -le ${#ops[@]} ] || die "Opción inválida."
  PKG_DESTINO="${ops[$((eleccion-1))]}"
}

_pkg_pedir_clave_nueva() {
  local a b
  while :; do
    ask_secret "Contraseña para proteger las credenciales del paquete (mínimo 8 caracteres)" a pkg_clave
    [ ${#a} -ge 8 ] || { warn "Muy corta."; [ "$NON_INTERACTIVE" = 1 ] && die "Falta la contraseña"; continue; }
    ask_secret "Repetila" b pkg_clave2
    [ "$a" = "$b" ] && break
    warn "No coinciden."; [ "$NON_INTERACTIVE" = 1 ] && die "Las contraseñas no coinciden"
  done
  PKG_CLAVE="$a"
}

# gpg con una carpeta propia y descartable: si no, crea ~/.gnupg en el usuario del anfitrión
_pkg_gpg() {
  local gh rc; gh="$(mktemp -d "$PKG_RUN_ROOT/ideaspackage-gpg.XXXXXX")"
  gpg --homedir "$gh" --batch --quiet --no-permission-warning --pinentry-mode loopback "$@"; rc=$?
  gpgconf --homedir "$gh" --kill all >/dev/null 2>&1; rm -rf "$gh"
  return $rc
}

# _pkg_cifrar <dir-de-secretos> <archivo.gpg> — usa PKG_CLAVE
_pkg_cifrar() {
  local src="$1" out="$2"
  ( cd "$src" && tar -cf - --mode='go-rwx' . ) | _pkg_gpg --yes --passphrase-fd 3 --symmetric --cipher-algo AES256 \
      --s2k-digest-algo SHA512 --s2k-count 65011712 -o "$out.tmp" 3<<<"$PKG_CLAVE" \
    && mv -f "$out.tmp" "$out"
}

# _pkg_descifrar <archivo.gpg> <dir-destino> — usa PKG_CLAVE; falla si la contraseña no es
_pkg_descifrar() {
  local in="$1" dst="$2"
  ( umask 077; mkdir -p "$dst" ); chmod 700 "$(dirname "$dst")" "$dst"
  _pkg_gpg --passphrase-fd 3 -d "$in" 3<<<"$PKG_CLAVE" 2>/dev/null | ( umask 077; tar -xf - --no-same-permissions -C "$dst" 2>/dev/null )
  local rc=("${PIPESTATUS[@]}")
  chmod 700 "$dst"; find "$dst" -type f -exec chmod 600 {} + 2>/dev/null
  [ "${rc[0]}" = 0 ] && [ "${rc[1]}" = 0 ]
}

# Symlinks de la raíz de datos: relativos a ella cuando apuntan adentro (así sirven en otro equipo)
_pkg_listar_enlaces() {
  local raiz="$1"
  ( cd "$raiz" && find . -type l -print0 2>/dev/null | while IFS= read -r -d '' l; do
      t="$(readlink "$l")"
      case "$t" in "$raiz"/*) t="@/${t#"$raiz"/}" ;; esac
      printf '%s\t%s\n' "${l#./}" "$t"
    done )
}

_pkg_restaurar_enlaces() {
  local raiz="$1" tsv="$2" l t
  [ -f "$tsv" ] || return 0
  while IFS=$'\t' read -r l t; do
    [ -n "$l" ] || continue
    case "$t" in "@/"*) t="$raiz/${t#@/}" ;; esac
    mkdir -p "$(dirname "$raiz/$l")"
    ln -sfn "$t" "$raiz/$l"
  done < "$tsv"
}

# rsync tolerante a FAT/exFAT: sin symlinks, sin permisos ni dueños, fechas con 2 s de margen
_pkg_rsync() {
  rsync -rt --no-links --info=skip0,nonreg0 --modify-window=2 --delete --delay-updates \
    --exclude='node_modules/' --exclude='venv/' --exclude='.venv/' --exclude='__pycache__/' \
    --exclude='*.pyc' --exclude='05-OPERACIONES/panel/*.db-wal' --exclude='05-OPERACIONES/panel/*.db-shm' \
    "$@"
}

_pkg_manifiesto() {  # _pkg_manifiesto <dir-paquete> <creado>
  PKG="$1" CREADO="$2" OWNER="${EMPRESA_RESPONSABLE:-$EMPRESA_NOMBRE}" NOMBRE="$EMPRESA_NOMBRE" SLUG="$EMPRESA_SLUG" \
  RUBRO="${EMPRESA_RUBRO:-}" EQUIPO="$(hostname 2>/dev/null || echo equipo)" \
  VERSION="$(cat "$STACK_SRC/VERSION" 2>/dev/null || echo '?')" FORMATO="$PKG_FORMAT" python3 - <<'PY'
import json, os, time
p = os.environ["PKG"]
now = time.strftime("%Y-%m-%dT%H:%M:%S")
json.dump({
    "formato": int(os.environ["FORMATO"]),
    "propietario": os.environ["OWNER"],
    "empresa": {"nombre": os.environ["NOMBRE"], "slug": os.environ["SLUG"], "rubro": os.environ["RUBRO"]},
    "creado": os.environ["CREADO"] or now,
    "actualizado": now,
    "ultimo_equipo": os.environ["EQUIPO"],
    "ideasbox": os.environ["VERSION"],
}, open(os.path.join(p, "ideaspackage.json.tmp"), "w"), ensure_ascii=False, indent=2)
os.replace(os.path.join(p, "ideaspackage.json.tmp"), os.path.join(p, "ideaspackage.json"))
PY
}

paquete_crear() {
  _pkg_need
  load_profile
  [ -n "${IDEASPACKAGE_SESION:-}" ] && die "Esta ya es una sesión de IdeasPackage: para actualizar el paquete usá «ideasbox paquete guardar»."
  [ -d "$DATA_ROOT/.claude" ] || die "No encuentro la raíz de datos ($DATA_ROOT). ¿Está conectado el disco?"

  step "IdeasPackage · empaquetar «${EMPRESA_NOMBRE}»"
  local destino="${1:-}"
  if [ -z "$destino" ]; then _pkg_elegir_destino; destino="$PKG_DESTINO"; fi
  [ -d "$destino" ] && [ -w "$destino" ] || die "No puedo escribir en $destino"
  local pkg="$destino/$PKG_DIRNAME" creado=""
  if [ -f "$pkg/ideaspackage.json" ]; then
    local otro; otro="$(_pkg_json "$pkg/ideaspackage.json" empresa.slug)"
    [ "$otro" = "$EMPRESA_SLUG" ] || die "$pkg ya tiene el paquete de otra empresa ($otro). Usá otro disco o borralo antes."
    confirm "Ya hay un paquete de $EMPRESA_NOMBRE en $destino. ¿Actualizarlo?" y pkg_actualizar || exit 0
    creado="$(_pkg_json "$pkg/ideaspackage.json" creado)"
  fi

  local usado libre
  usado="$(du -sk --exclude=node_modules --exclude=venv "$DATA_ROOT" 2>/dev/null | cut -f1)"
  libre="$(df -Pk "$destino" | awk 'NR==2 {print $4}')"
  [ -n "$usado" ] && [ -n "$libre" ] && [ "$usado" -lt "$libre" ] \
    || die "No entra: la empresa ocupa $((usado/1024)) MB y en $destino quedan $((libre/1024)) MB."

  _pkg_pedir_clave_nueva
  mkdir -p "$pkg/datos"

  info "Copiando la empresa ($((usado/1024)) MB)… puede tardar varios minutos en un pendrive"
  _pkg_rsync "$DATA_ROOT/" "$pkg/datos/" || die "Falló la copia al disco."
  _pkg_listar_enlaces "$DATA_ROOT" > "$pkg/enlaces.tsv"
  grep -vE '^(DATA_ROOT|STACK_SRC|STACK_VERSION)=' "$STACK_PROFILE" > "$pkg/perfil.conf"
  cp "$MCP_REGISTRY" "$pkg/conectores.tsv" 2>/dev/null || : > "$pkg/conectores.tsv"

  info "Cifrando las credenciales"
  local tmp; tmp="$(mktemp -d "$PKG_RUN_ROOT/ideaspackage-crear.XXXXXX")"; chmod 700 "$tmp"
  [ -d "$STACK_SECRETS_DIR" ] && cp -a "$STACK_SECRETS_DIR/." "$tmp/"
  _pkg_cifrar "$tmp" "$pkg/secretos.gpg" || { rm -rf "$tmp"; die "No se pudieron cifrar las credenciales."; }
  rm -rf "$tmp"

  _pkg_manifiesto "$pkg" "$creado"
  sync
  ok "Paquete listo en $pkg"
  info "Conectalo en otro equipo con Ideas Box y abrí Ideas Box: te va a ofrecer iniciar tu empresa."
  warn "Guardá la contraseña: sin ella no se pueden usar las credenciales de los conectores."
}

# --- sesión invitada ------------------------------------------------------------

_pkg_dirs() {  # define las rutas de la sesión de <slug>
  PKG_SLUG="$1"
  PKG_G="$PKG_CACHE_ROOT/$PKG_SLUG"
  PKG_HOME="$PKG_G/home"
  PKG_DATOS="$PKG_G/datos"
  PKG_CACHE="$PKG_G/cache"
  PKG_RUN="$PKG_RUN_ROOT/ideaspackage-$PKG_SLUG"
}

# Entorno de la sesión invitada. Se usa para todo lo que corre «como» la empresa invitada.
_pkg_escribir_entorno() {
  local host_path="$PATH"
  cat > "$PKG_G/entorno.sh" <<EOF
# Entorno de la empresa invitada (IdeasPackage). Generado: no editar.
export IDEASPACKAGE_SESION="$PKG_SLUG"
export IDEASPACKAGE_RUTA="$PKG_RUTA"
export IDEASPACKAGE_CACHE="$PKG_CACHE_ROOT"   # la caché real (adentro, XDG_CACHE_HOME es la invitada)
export HOME="$PKG_HOME"
export XDG_CONFIG_HOME="$PKG_HOME/.config" XDG_DATA_HOME="$PKG_HOME/.local/share"
export XDG_CACHE_HOME="$PKG_HOME/.cache" XDG_STATE_HOME="$PKG_HOME/.local/state"
unset STACK_CONFIG_DIR CLAUDE_CONFIG_DIR CLAUDE_JSON STACK_MCP_SRC DATA_ROOT
export STACK_SRC="$STACK_SRC"
export PANEL_PORT="$PKG_PANEL_PORT"
export DISABLE_AUTOUPDATER=1
# Programas del equipo (claude, node) sirven, su configuración no: va al final del PATH
export PATH="$PKG_HOME/.local/bin:$host_path"
EOF
}

_pkg_puerto_libre() {
  local p
  for p in $(seq 8421 8440); do
    (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null || { echo "$p"; return; }
  done
  echo 8441
}

_pkg_lock_escribir() {
  EQUIPO="$(hostname 2>/dev/null || echo equipo)" USUARIO="$(id -un)" python3 - "$PKG_RUTA/en-uso.json" <<'PY'
import json, os, sys, time
json.dump({"equipo": os.environ["EQUIPO"], "usuario": os.environ["USUARIO"],
           "desde": time.strftime("%Y-%m-%dT%H:%M:%S"), "pid": os.getppid()},
          open(sys.argv[1], "w"), ensure_ascii=False)
PY
}

paquete_abrir() {
  _pkg_need
  [ -n "${IDEASPACKAGE_SESION:-}" ] && die "Ya estás dentro de la sesión de $IDEASPACKAGE_SESION."
  local ruta="${1:-}"
  if [ -z "$ruta" ]; then
    local -a lista=(); local l
    while IFS= read -r l; do lista+=("$l"); done < <(paquete_buscar)
    [ ${#lista[@]} -gt 0 ] || die "No encontré ningún IdeasPackage en los discos conectados."
    ruta="$(cut -f1 <<<"${lista[0]}")"
  fi
  [ -f "$ruta/ideaspackage.json" ] || die "$ruta no es un IdeasPackage."
  PKG_RUTA="$(cd "$ruta" && pwd)"
  local m="$PKG_RUTA/ideaspackage.json"
  local dueno empresa slug fmt
  dueno="$(_pkg_json "$m" propietario)"; empresa="$(_pkg_json "$m" empresa.nombre)"
  slug="$(_pkg_json "$m" empresa.slug)"; fmt="$(_pkg_json "$m" formato)"
  [ -n "$slug" ] || die "El manifiesto del paquete está incompleto."
  [ "${fmt:-0}" -le "$PKG_FORMAT" ] || die "Este paquete es de una versión más nueva de Ideas Box. Actualizá Ideas Box en este equipo."
  _pkg_dirs "$(slugify "$slug")"

  if [ -f "$PKG_RUN/abierta" ]; then
    ok "La empresa $empresa ya está abierta en este equipo."
    _pkg_lanzar_sesion; return 0
  fi

  printf '\n  %sHola %s.%s\n' "$C_B" "$(_pkg_nombre_corto "$dueno")" "$C_RESET"
  confirm "  ¿Querés iniciar tu empresa «${empresa}» en este equipo?" y pkg_iniciar || { info "Listo, no se abrió nada."; return 0; }

  if [ -f "$PKG_RUTA/en-uso.json" ]; then
    local eq desde; eq="$(_pkg_json "$PKG_RUTA/en-uso.json" equipo)"; desde="$(_pkg_json "$PKG_RUTA/en-uso.json" desde)"
    warn "El paquete figura abierto en «${eq}» desde $desde (¿se cerró mal?)."
    warn "Si seguís, lo que no se haya guardado allá no va a estar acá."
    confirm "  ¿Abrirlo igual?" n pkg_forzar || return 0
  fi

  local intentos=0
  while :; do
    ask_secret "  Contraseña del paquete" PKG_CLAVE pkg_clave
    if _pkg_descifrar "$PKG_RUTA/secretos.gpg" "$PKG_RUN/secretos"; then break; fi
    intentos=$((intentos+1)); rm -rf "$PKG_RUN/secretos"
    [ $intentos -ge 3 ] || [ "$NON_INTERACTIVE" = 1 ] && die "Contraseña incorrecta."
    warn "Contraseña incorrecta."
  done
  printf '%s' "$PKG_CLAVE" > "$PKG_RUN/clave"; chmod 600 "$PKG_RUN/clave"   # para re-cifrar al guardar (tmpfs)

  step "Preparando tu empresa en este equipo"
  rm -rf "$PKG_HOME"; mkdir -p "$PKG_HOME" "$PKG_DATOS" "$PKG_CACHE"/{mcp-servers,bin,panel,claude}; chmod 700 "$PKG_G"
  info "Trayendo los datos del pendrive…"
  _pkg_rsync "$PKG_RUTA/datos/" "$PKG_DATOS/" || die "No se pudieron copiar los datos."
  _pkg_restaurar_enlaces "$PKG_DATOS" "$PKG_RUTA/enlaces.tsv"
  _pkg_lock_escribir

  # HOME invitado: configuración nueva; lo pesado y reconstruible, en cache/ (persiste)
  mkdir -p "$PKG_HOME/.config/$STACK_NAME" "$PKG_HOME/.local/share/ideasbox" "$PKG_HOME/.local/state"
  ln -sfn "$PKG_CACHE/mcp-servers" "$PKG_HOME/.local/share/mcp-servers"
  ln -sfn "$PKG_CACHE/bin" "$PKG_HOME/.local/bin"
  ln -sfn "$PKG_CACHE/panel" "$PKG_HOME/.local/share/ideasbox/panel"
  mkdir -p "$PKG_CACHE/claude"; ln -sfn "$PKG_CACHE/claude" "$PKG_HOME/.local/share/claude"   # si hay que instalar Claude Code
  ln -sfn "$PKG_RUN/secretos" "$PKG_HOME/.config/$STACK_NAME/secrets"
  { cat "$PKG_RUTA/perfil.conf"; printf 'DATA_ROOT="%s"\nSTACK_SRC="%s"\n' "$PKG_DATOS" "$STACK_SRC"; } \
    > "$PKG_HOME/.config/$STACK_NAME/empresa.conf"
  chmod 600 "$PKG_HOME/.config/$STACK_NAME/empresa.conf"
  cp "$PKG_RUTA/conectores.tsv" "$PKG_HOME/.config/$STACK_NAME/mcp-installed.tsv" 2>/dev/null || true
  PKG_PANEL_PORT="$(_pkg_puerto_libre)"
  _pkg_escribir_entorno

  info "Armando agentes, skills y conectores (la primera vez en este equipo tarda más)"
  ( . "$PKG_G/entorno.sh"; ASSUME_YES=1 NON_INTERACTIVE=1 bash "$STACK_SRC/bin/ideasbox" paquete _hidratar ) \
    || warn "Algunos conectores no se pudieron preparar; el resto de la empresa funciona."

  date +%s > "$PKG_RUN/abierta"
  _pkg_autoguardado_iniciar
  ok "Tu empresa «${empresa}» está abierta en este equipo."
  info "Se guarda sola cada $PKG_AUTOSAVE_MIN minutos. Al terminar: «Cerrar mi empresa» (o ideasbox paquete cerrar)."
  _pkg_lanzar_sesion
}

# Dentro del entorno invitado: arma lo que depende del equipo (rutas, venvs, lanzadores).
paquete_hidratar() {
  [ -n "${IDEASPACKAGE_SESION:-}" ] || die "Solo corre dentro de una sesión de IdeasPackage."
  load_profile
  # Claude Code: el del equipo sirve (está en el PATH); si el equipo no lo tiene, va a la caché invitada
  have claude || ensure_claude || warn "No se pudo instalar Claude Code: los agentes no van a poder trabajar."
  local id tier dom repo sub desc
  while IFS=$'\t' read -r id tier dom repo sub desc; do
    [ -d "$(packs_dir)/$id" ] && _pack_link "$(packs_dir)/$id" "$sub" "$dom" "$id" >/dev/null || true
  done < <(_pack_rows)
  if [ -s "$MCP_REGISTRY" ]; then
    local server cid label
    while IFS=$'\t' read -r server cid _ label; do
      [ -n "$cid" ] || continue
      info "  conector $server"
      mcp_install "$cid" "$label" >/dev/null 2>&1 || warn "  $server no se pudo preparar en este equipo"
    done < <(cat "$MCP_REGISTRY")
  fi
  canonical_main --force >/dev/null
  settings_apply >/dev/null
  # CLI de la empresa invitada (no toca el ~/.local/bin del anfitrión)
  ln -sfn "$STACK_SRC/bin/ideasbox" "$HOME/.local/bin/ideasbox"
}

# Abre una terminal con la empresa invitada (menú de Ideas Box), o deja las instrucciones.
_pkg_lanzar_sesion() {
  local empresa; empresa="$(_pkg_json "$PKG_RUTA/ideaspackage.json" empresa.nombre)"
  local cmd="cd \"$PKG_HOME\"; . \"$PKG_G/entorno.sh\"; printf '\\n  Empresa invitada: %s (IdeasPackage)\\n' \"$empresa\"; bash \"$STACK_SRC/bin/ideasbox\" menu; exec bash"
  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ -z "${IDEASPACKAGE_NO_TERMINAL:-}" ]; then
    local t
    for t in x-terminal-emulator xfce4-terminal gnome-terminal konsole xterm; do
      have "$t" || continue
      case "$t" in
        gnome-terminal) setsid "$t" --title="$empresa · IdeasPackage" -- bash -c "$cmd" >/dev/null 2>&1 & ;;
        *) setsid "$t" -T "$empresa · IdeasPackage" -e bash -c "$cmd" >/dev/null 2>&1 & ;;
      esac
      return 0
    done
  fi
  info "Para trabajar con tu empresa en esta terminal:  . \"$PKG_G/entorno.sh\" && ideasbox"
}

# Guardado automático: proceso propio (setsid), sobrevive a que se cierre la terminal que abrió la sesión
_pkg_autoguardado_iniciar() {
  [ "$PKG_AUTOSAVE_MIN" -gt 0 ] 2>/dev/null || return 0
  IDEASPACKAGE_CACHE="$PKG_CACHE_ROOT" setsid nohup bash "$STACK_SRC/bin/ideasbox" paquete _autoguardar "$PKG_SLUG" \
    </dev/null >>"$PKG_G/autoguardado.log" 2>&1 &
  echo $! > "$PKG_RUN/autoguardado.pid"
}

paquete_autoguardar() {
  _pkg_dirs "$1"
  while sleep $((PKG_AUTOSAVE_MIN * 60)); do
    [ -f "$PKG_RUN/abierta" ] || exit 0
    IDEASPACKAGE_SILENCIO=1 paquete_guardar "$PKG_SLUG" || true
  done
}

# Encuentra la sesión abierta: la indicada, la del entorno actual o la única abierta.
_pkg_sesion_actual() {
  local s="${1:-${IDEASPACKAGE_SESION:-}}" f
  if [ -z "$s" ]; then
    for f in "$PKG_RUN_ROOT"/ideaspackage-*/abierta; do
      [ -f "$f" ] || continue
      s="$(basename "$(dirname "$f")")"; s="${s#ideaspackage-}"; break
    done
  fi
  [ -n "$s" ] || return 1
  _pkg_dirs "$s"
  [ -f "$PKG_RUN/abierta" ] || return 1
  PKG_RUTA="$(sed -n 's/^export IDEASPACKAGE_RUTA="\(.*\)"$/\1/p' "$PKG_G/entorno.sh" 2>/dev/null)"
  [ -n "$PKG_RUTA" ]
}

paquete_guardar() {
  _pkg_sesion_actual "${1:-}" || die "No hay ninguna empresa de IdeasPackage abierta en este equipo."
  [ -d "$PKG_RUTA" ] || die "El pendrive con el paquete no está conectado ($PKG_RUTA). Volvé a conectarlo para guardar."
  # SQLite del panel: consolidar el WAL antes de copiar
  local db="$PKG_DATOS/05-OPERACIONES/panel/panel.db"
  [ -f "$db" ] && have sqlite3 && sqlite3 "$db" 'PRAGMA wal_checkpoint(TRUNCATE);' >/dev/null 2>&1
  [ -n "${IDEASPACKAGE_SILENCIO:-}" ] || info "Guardando en el pendrive…"
  _pkg_rsync "$PKG_DATOS/" "$PKG_RUTA/datos/" || die "No se pudo guardar en el pendrive."
  _pkg_listar_enlaces "$PKG_DATOS" > "$PKG_RUTA/enlaces.tsv.tmp" && mv -f "$PKG_RUTA/enlaces.tsv.tmp" "$PKG_RUTA/enlaces.tsv"
  local cfg="$PKG_HOME/.config/$STACK_NAME"
  grep -vE '^(DATA_ROOT|STACK_SRC|STACK_VERSION)=' "$cfg/empresa.conf" > "$PKG_RUTA/perfil.conf.tmp" && mv -f "$PKG_RUTA/perfil.conf.tmp" "$PKG_RUTA/perfil.conf"
  [ -f "$cfg/mcp-installed.tsv" ] && cp -f "$cfg/mcp-installed.tsv" "$PKG_RUTA/conectores.tsv"
  # Credenciales: se vuelven a cifrar si cambiaron en la sesión (conector nuevo, token renovado)
  local firma; firma="$( (cd "$PKG_RUN/secretos" && find . -type f -exec sha256sum {} + | sort) 2>/dev/null | sha256sum | cut -c1-16)"
  if [ "$firma" != "$(cat "$PKG_RUN/secretos.firma" 2>/dev/null)" ]; then
    PKG_CLAVE="$(cat "$PKG_RUN/clave")" _pkg_cifrar "$PKG_RUN/secretos" "$PKG_RUTA/secretos.gpg" && echo "$firma" > "$PKG_RUN/secretos.firma"
  fi
  ( EMPRESA_NOMBRE="$(_pkg_json "$PKG_RUTA/ideaspackage.json" empresa.nombre)"
    EMPRESA_SLUG="$(_pkg_json "$PKG_RUTA/ideaspackage.json" empresa.slug)"
    EMPRESA_RESPONSABLE="$(_pkg_json "$PKG_RUTA/ideaspackage.json" propietario)"
    EMPRESA_RUBRO="$(_pkg_json "$PKG_RUTA/ideaspackage.json" empresa.rubro)"
    _pkg_manifiesto "$PKG_RUTA" "$(_pkg_json "$PKG_RUTA/ideaspackage.json" creado)" )
  sync
  date '+%H:%M' > "$PKG_RUN/ultimo-guardado"
  [ -n "${IDEASPACKAGE_SILENCIO:-}" ] || ok "Guardado en el pendrive ($(date '+%H:%M'))."
}

paquete_cerrar() {
  _pkg_sesion_actual "${1:-}" || { info "No hay ninguna empresa de IdeasPackage abierta en este equipo."; return 0; }
  local empresa; empresa="$(_pkg_json "$PKG_RUTA/ideaspackage.json" empresa.nombre 2>/dev/null)"
  step "Cerrando «${empresa:-$PKG_SLUG}»"
  if [ -d "$PKG_RUTA" ]; then
    IDEASPACKAGE_SILENCIO= paquete_guardar "$PKG_SLUG" || { warn "No se pudo guardar: no borro nada en este equipo."; return 1; }
  else
    warn "El pendrive no está conectado: conectalo para guardar antes de cerrar."
    confirm "¿Cerrar igual y PERDER lo trabajado desde el último guardado ($(cat "$PKG_RUN/ultimo-guardado" 2>/dev/null || echo 'nunca'))?" n pkg_cerrar_sin_guardar || return 1
  fi
  [ -f "$PKG_RUN/autoguardado.pid" ] && { kill "$(cat "$PKG_RUN/autoguardado.pid")" 2>/dev/null || true; }
  # Procesos de la empresa invitada (panel, claude, conectores): se apagan
  ( . "$PKG_G/entorno.sh" 2>/dev/null; bash "$STACK_SRC/bin/ideasbox" panel stop >/dev/null 2>&1 ) || true
  # (sin tocar este proceso ni sus padres: el cierre puede venir del menú de la propia sesión)
  local yo=" " p=$$ pid
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do yo+="$p "; p="$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)"; done
  for pid in $(pgrep -u "$(id -u)" 2>/dev/null); do
    case "$yo" in *" $pid "*) continue ;; esac
    [ -r "/proc/$pid/environ" ] || continue
    { tr '\0' '\n' < "/proc/$pid/environ"; } 2>/dev/null | grep -qx "IDEASPACKAGE_SESION=$PKG_SLUG" && { kill "$pid" 2>/dev/null || true; }
  done
  [ -d "$PKG_RUTA" ] && rm -f "$PKG_RUTA/en-uso.json"
  # Rastros: credenciales (tmpfs), configuración y sesión de Claude, copia de los datos
  rm -rf "$PKG_RUN" "$PKG_HOME" "$PKG_DATOS" "$PKG_G/entorno.sh" "$PKG_G/autoguardado.log"
  sync
  ok "Listo: «${empresa:-$PKG_SLUG}» quedó guardada en el pendrive y este equipo no conserva datos ni credenciales."
  info "(Solo queda en ~/.cache/ideaspackage/$PKG_SLUG/cache lo reconstruible de los conectores, para abrir más rápido la próxima vez.)"
}

paquete_estado() {
  if _pkg_sesion_actual "${1:-}"; then
    printf 'Abierta: %s\n  pendrive  %s %s\n  desde     %s\n  guardado  %s\n  panel     http://127.0.0.1:%s\n' \
      "$(_pkg_json "$PKG_RUTA/ideaspackage.json" empresa.nombre)" "$PKG_RUTA" "$([ -d "$PKG_RUTA" ] && echo '(conectado)' || echo '(DESCONECTADO)')" \
      "$(date -d "@$(cat "$PKG_RUN/abierta")" '+%H:%M' 2>/dev/null)" "$(cat "$PKG_RUN/ultimo-guardado" 2>/dev/null || echo 'todavía no')" \
      "$(sed -n 's/^export PANEL_PORT="\(.*\)"$/\1/p' "$PKG_G/entorno.sh")"
  else
    echo "No hay ninguna empresa de IdeasPackage abierta en este equipo."
  fi
  local hay; hay="$(paquete_buscar)"
  [ -n "$hay" ] && { echo; echo "Paquetes conectados:"; printf '%s\n' "$hay" | awk -F'\t' '{printf "  %s — %s (%s)%s\n", $3, $2, $1, ($5!=""?"  [abierto en "$5"]":"")}'; }
  return 0
}

paquete_main() {
  local sub="${1:-estado}"; shift || true
  case "$sub" in
    crear)    paquete_crear "$@" ;;
    buscar)   paquete_buscar ;;
    abrir)    paquete_abrir "$@" ;;
    guardar)  paquete_guardar "$@" ;;
    cerrar)   paquete_cerrar "$@" ;;
    estado)   paquete_estado "$@" ;;
    _hidratar) paquete_hidratar ;;
    _autoguardar) paquete_autoguardar "$@" ;;
    *) die "Uso: $STACK_NAME paquete {crear|buscar|abrir|guardar|cerrar|estado}" ;;
  esac
}
