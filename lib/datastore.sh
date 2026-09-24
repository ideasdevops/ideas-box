#!/usr/bin/env bash
# Raíz de datos: disco/partición aparte si existe, si no una carpeta en $HOME.
# Este script NO modifica tablas de particiones ni formatea nada.

# Carpetas de negocio de la raíz de datos.
DATA_TREE=(
  "00-INBOX"
  "01-RECURSOS-IA/00-INBOX" "01-RECURSOS-IA/10-CANDIDATOS" "01-RECURSOS-IA/20-VALIDADOS" "01-RECURSOS-IA/90-ARCHIVO"
  "02-CLIENTES"
  "03-PROYECTOS"
  "04-SERVICIOS"
  "05-OPERACIONES/bitacoras" "05-OPERACIONES/scripts" "05-OPERACIONES/backups"
  "06-CONTENIDO/10-CRUDOS" "06-CONTENIDO/30-LISTOS-PARA-PUBLICAR"
  "07-DOCUMENTOS"
  "08-IMAGENES"
  "09-VIDEOS"
  "10-PROSPECCIONES"
  "90-ARCHIVO"
)
CLAUDE_TREE=(
  ".claude/agents" ".claude/skills" ".claude/docs"
  ".claude/memory/shared" ".claude/memory/clientes" ".claude/memory/proyectos"
  ".claude/memory/operaciones" ".claude/memory/referencias" ".claude/memory/workflows"
  ".claude/memory/qa"
)

_candidate_mounts_linux() {
  lsblk -rno NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,LABEL 2>/dev/null | while read -r name size type mnt fstype label; do
    [ "$type" = part ] || continue
    [ -n "$mnt" ] || continue
    case "$mnt" in
      /|/boot|/boot/*|/boot/efi|"[SWAP]"|/snap/*|/var/snap/*) continue ;;
    esac
    [ -w "$mnt" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$mnt" "$size" "${fstype:-?}" "${label:-sin-etiqueta}"
  done
}

# En macOS los volúmenes externos se montan en /Volumes. El disco de arranque también
# aparece ahí como enlace a /, así que se descarta comparando el dispositivo con el de la raíz.
_candidate_mounts_macos() {
  local raiz_dev; raiz_dev="$(df / | awk 'NR==2 {print $1}')"
  local vol dev size fstype
  for vol in /Volumes/*; do
    [ -d "$vol" ] || continue
    [ -L "$vol" ] && continue
    [ -w "$vol" ] || continue
    dev="$(df "$vol" 2>/dev/null | awk 'NR==2 {print $1}')"
    [ "$dev" = "$raiz_dev" ] && continue
    size="$(df -h "$vol" 2>/dev/null | awk 'NR==2 {print $2}')"
    fstype="$(diskutil info "$vol" 2>/dev/null | awk -F: '/Type \(Bundle\)/ {gsub(/^ +/,"",$2); print $2; exit}')"
    printf '%s\t%s\t%s\t%s\n' "$vol" "${size:-?}" "${fstype:-?}" "$(basename "$vol")"
  done
}

_candidate_mounts() {
  if is_mac; then _candidate_mounts_macos; else _candidate_mounts_linux; fi
}

_print_partition_guide() {
  if is_mac; then
    cat <<'TXT'

── Cómo dejar un volumen dedicado para los datos (macOS) ───────────────────
Este instalador no toca los discos: borrar el equivocado es irreversible.
Si querés un volumen aparte, creálo una vez a mano:

  Opción A — volumen APFS en el disco interno (no requiere formatear nada):
    1. Abrí Utilidad de Discos (Disk Utility).
    2. Seleccioná el contenedor APFS → botón "+" (Añadir volumen APFS).
    3. Nombralo, por ejemplo, "Datos". Comparte espacio con el sistema.

  Opción B — disco externo:
    1. Utilidad de Discos → seleccioná el disco externo.
    2. Borrar → formato APFS o Mac OS Plus (con registro) → nombralo "Datos".

  Por línea de comandos:  diskutil list
                          diskutil apfs addVolume disk1 APFS Datos

El volumen queda montado en /Volumes/Datos. Volvé a correr el instalador y
elegilo de la lista.
─────────────────────────────────────────────────────────────────────────────

TXT
    return 0
  fi

  cat <<'TXT'

── Cómo dejar una partición dedicada para los datos ────────────────────────
Este instalador no toca la tabla de particiones: formatear el disco equivocado
es irreversible. Si querés una partición aparte, hacelo una vez a mano:

  1. Ver discos:            lsblk -f
  2. Particionar (GUI):     sudo gparted        # o: sudo cfdisk /dev/sdX
  3. Formatear la nueva:    sudo mkfs.ext4 -L datos /dev/sdXN
  4. Punto de montaje:      sudo mkdir -p /mnt/datos
  5. Montaje permanente:    echo "LABEL=datos /mnt/datos ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
  6. Montar y dar permisos: sudo mount -a && sudo chown -R "$USER:$USER" /mnt/datos

Cuando exista y esté montada, volvé a correr el instalador y elegila de la lista.
─────────────────────────────────────────────────────────────────────────────

TXT
}

# --- Menú de raíz de datos ---------------------------------------------------
# Antes de preguntar se mira el equipo: instalaciones previas, carpetas principales
# del usuario y discos montados. Cada opción muestra el espacio libre y por qué
# conviene o no, para que alguien sin experiencia pueda elegir sin adivinar.

# _free_at <ruta> — espacio libre donde quedaría <ruta>, aunque todavía no exista
_free_at() {
  local p="$1"
  while [ ! -e "$p" ] && [ "$p" != / ]; do p="$(dirname "$p")"; done
  avail_of "$p"
}

# Carpeta de documentos con su nombre real: en Linux depende del idioma del
# escritorio (Documentos, Documents…); en macOS siempre es Documents.
_documents_dir() {
  local d=""
  if ! is_mac && have xdg-user-dir; then d="$(xdg-user-dir DOCUMENTS 2>/dev/null)"; fi
  [ -n "$d" ] && [ "$d" != "$HOME" ] && [ -d "$d" ] && { printf '%s' "$d"; return 0; }
  for d in "$HOME/Documents" "$HOME/Documentos"; do
    [ -d "$d" ] && { printf '%s' "$d"; return 0; }
  done
  return 1
}

# Raíces de datos que dejó una corrida anterior (completa o cortada a mitad): la que
# quedó anotada en locks.tsv y las que tengan la marca .ideas-box en el home o en
# un volumen. En macOS no se revisan Documentos, Escritorio ni Descargas: tocarlas
# dispara el pedido de permisos del sistema antes de que el usuario sepa por qué.
_previous_roots() {
  {
    [ -f "$STACK_LOCKS" ] && awk -F'\t' '$1 == "data_root" { print $2 }' "$STACK_LOCKS"
    local d mnt rest
    for d in "$HOME"/*/; do
      case "$(basename "$d")" in Documents|Desktop|Downloads|Library|Pictures|Movies|Music) is_mac && continue ;; esac
      [ -f "$d.ideas-box" ] && printf '%s\n' "${d%/}"
    done
    while IFS=$'\t' read -r mnt rest; do
      [ -n "$mnt" ] || continue
      for d in "$mnt"/*/; do [ -f "$d.ideas-box" ] && printf '%s\n' "${d%/}"; done
    done < <(_candidate_mounts)
  } 2>/dev/null | awk 'NF && !seen[$0]++' | while IFS= read -r d; do
    [ -f "$d/.ideas-box" ] && printf '%s\n' "$d"
  done
}

_choose_data_root() {
  local -a paths=() labels=()
  local d mnt size fstype label nombre docs recommended="" note

  # 1. Instalaciones previas
  while IFS= read -r d; do
    nombre="$(awk -F= '$1 == "nombre" { print $2 }' "$d/.ideas-box" 2>/dev/null)"
    paths+=("$d"); labels+=("ya existe: instalación anterior de Ideas Box${nombre:+ ($nombre)}")
    [ -n "$recommended" ] || recommended=${#paths[@]}
  done < <(_previous_roots)

  # 2. Carpetas principales del usuario
  d="$HOME/$EMPRESA_SLUG-data"
  if [ ! -f "$d/.ideas-box" ]; then
    paths+=("$d"); labels+=("carpeta nueva en tu usuario")
    [ -n "$recommended" ] || recommended=${#paths[@]}
  fi
  if docs="$(_documents_dir)" && [ ! -f "$docs/$EMPRESA_SLUG-data/.ideas-box" ]; then
    note="carpeta nueva dentro de $(basename "$docs")"
    is_mac && note="$note — macOS va a pedir permiso de acceso, y si iCloud sincroniza Documentos puede dejar archivos a medio bajar"
    paths+=("$docs/$EMPRESA_SLUG-data"); labels+=("$note")
  fi

  # 3. Discos y volúmenes aparte
  while IFS=$'\t' read -r mnt size fstype label; do
    [ -n "$mnt" ] || continue
    [ -f "$mnt/$EMPRESA_SLUG/.ideas-box" ] && continue   # ya listado como instalación previa
    paths+=("$mnt/$EMPRESA_SLUG"); labels+=("disco aparte: $label, $size, $fstype — si no está conectado, los agentes no ven los datos")
  done < <(_candidate_mounts)

  local n=${#paths[@]}
  local opt_manual=$((n+1)) opt_guide=$((n+2)) intentos=0

  while :; do
    intentos=$((intentos+1))
    [ "$intentos" -le 5 ] || die "Demasiados intentos sin elegir una raíz de datos. Volvé a correr install.sh."
    echo
    echo "¿Dónde guardamos la información de la empresa?"
    echo "Es la carpeta donde van a vivir la memoria de los agentes, los clientes, los proyectos"
    echo "y el contenido. Conviene un lugar que respaldes y que no se sincronice solo con la nube."
    echo
    local i=0
    while [ $i -lt "$n" ]; do
      printf '  %d) %s\n' $((i+1)) "${paths[$i]}"
      printf '     %s · %s libres%s\n' "${labels[$i]}" "$(_free_at "${paths[$i]}")" \
        "$([ $((i+1)) = "$recommended" ] && echo '  ← recomendado')"
      i=$((i+1))
    done
    printf '  %d) otra ruta (la escribo yo)\n' "$opt_manual"
    if is_mac; then
      printf '  %d) quiero un volumen dedicado y todavía no lo tengo\n' "$opt_guide"
    else
      printf '  %d) quiero una partición dedicada y todavía no la tengo\n' "$opt_guide"
    fi
    echo

    local choice
    ask "Opción" choice "$recommended"

    if [ "$choice" = "$opt_guide" ]; then
      _print_partition_guide
      confirm "¿Seguir ahora con una carpeta en tu usuario y migrar después?" y \
        || die "Instalación detenida. Creá la partición y volvé a correr install.sh."
      DATA_ROOT="$HOME/$EMPRESA_SLUG-data"
    elif [ "$choice" = "$opt_manual" ]; then
      ask "Ruta completa (empieza con /)" DATA_ROOT "$HOME/$EMPRESA_SLUG-data"
    else
      case "$choice" in ''|*[!0-9]*) choice=0 ;; esac
      if [ "$choice" -lt 1 ] || [ "$choice" -gt "$n" ]; then
        warn "Opción inválida: elegí un número de la lista."
        continue
      fi
      DATA_ROOT="${paths[$((choice-1))]}"
    fi

    if [ -f "$DATA_ROOT/.ideas-box" ]; then
      info "Se reutiliza $DATA_ROOT: lo que ya tiene no se toca, solo se completa lo que falte."
    else
      info "Se va a crear $DATA_ROOT ($(_free_at "$DATA_ROOT") libres)."
    fi
    confirm "¿Confirmás?" y && break
  done
}

datastore_wizard() {
  step "3/8 · Raíz de datos"

  if [ -n "$DATA_ROOT" ]; then
    info "Raíz de datos indicada por perfil/flag: $DATA_ROOT"
  else
    _choose_data_root
  fi

  case "$DATA_ROOT" in
    /*) ;;
    *) die "La raíz de datos debe ser una ruta absoluta (recibí: $DATA_ROOT)" ;;
  esac

  if [ -e "$DATA_ROOT" ] && [ ! -d "$DATA_ROOT" ]; then
    die "$DATA_ROOT existe y no es un directorio."
  fi

  run mkdir -p "$DATA_ROOT"
  [ "$DRY_RUN" = 1 ] || [ -w "$DATA_ROOT" ] || die "No tenés permiso de escritura en $DATA_ROOT"

  local d
  for d in "${DATA_TREE[@]}" "${CLAUDE_TREE[@]}"; do
    run mkdir -p "$DATA_ROOT/$d"
  done

  # Marca de identidad: permite a `ideasbox doctor` distinguir "disco no montado"
  # de "disco montado pero vacío".
  write_file "$DATA_ROOT/.ideas-box" 644 <<EOF
slug=$EMPRESA_SLUG
nombre=$EMPRESA_NOMBRE
creado=$(date -Iseconds)
EOF

  ok "Raíz de datos lista en $DATA_ROOT"
  lock_record "data_root" "$DATA_ROOT"
}
