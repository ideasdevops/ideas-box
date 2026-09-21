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

_candidate_mounts() {
  # Particiones montadas que sirven como raíz de datos (excluye sistema y solo-lectura).
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

_print_partition_guide() {
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

datastore_wizard() {
  step "3/8 · Raíz de datos"

  if [ -n "$DATA_ROOT" ]; then
    info "Raíz de datos indicada por perfil/flag: $DATA_ROOT"
  else
    local -a opts=() mounts=()
    local line mnt size fstype label

    while IFS=$'\t' read -r mnt size fstype label; do
      [ -n "$mnt" ] || continue
      mounts+=("$mnt")
      opts+=("$mnt  ($size, $fstype, $label)")
    done < <(_candidate_mounts)

    echo
    echo "¿Dónde va a vivir la información de la empresa (memoria, clientes, proyectos, contenido)?"
    echo
    local i=1
    for o in "${opts[@]}"; do printf '  %d) disco/partición: %s\n' "$i" "$o"; i=$((i+1)); done
    local opt_home=$i;   printf '  %d) carpeta en tu home: %s\n' "$i" "$HOME/$EMPRESA_SLUG-data"; i=$((i+1))
    local opt_manual=$i; printf '  %d) otra ruta (la escribo yo)\n' "$i"; i=$((i+1))
    local opt_guide=$i;  printf '  %d) quiero una partición dedicada y todavía no la tengo\n' "$i"
    echo

    local choice
    ask "Opción" choice "$opt_home"

    if [ "$choice" = "$opt_guide" ]; then
      _print_partition_guide
      if confirm "¿Seguir ahora con una carpeta en el home y migrar después?" y; then
        choice="$opt_home"
      else
        die "Instalación detenida. Creá la partición y volvé a correr install.sh."
      fi
    fi

    if [ "$choice" = "$opt_manual" ]; then
      ask "Ruta absoluta para la raíz de datos" DATA_ROOT "$HOME/$EMPRESA_SLUG-data"
    elif [ "$choice" = "$opt_home" ]; then
      DATA_ROOT="$HOME/$EMPRESA_SLUG-data"
    else
      local idx=$((choice-1))
      [ -n "${mounts[$idx]:-}" ] || die "Opción inválida: $choice"
      DATA_ROOT="${mounts[$idx]}/$EMPRESA_SLUG"
    fi
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
