#!/usr/bin/env bash
# Packs de skills de terceros. Se clonan de su upstream al disco de datos y se
# enlazan al árbol canónico: no se copian dentro del repo del stack ni se
# redistribuyen. Actualizables con `ideasbox update`.

PACKS_TSV="$STACK_SRC/catalog/skill-packs.tsv"
packs_dir() { printf '%s' "$DATA_ROOT/01-RECURSOS-IA/20-VALIDADOS/skill-packs"; }

_pack_rows() { grep -v '^#' "$PACKS_TSV" | grep -v '^[[:space:]]*$'; }

# _pack_link <dir-del-pack> <subdir> <dominio> <id>
_pack_link() {
  local base="$1" sub="$2" dom="$3" id="$4"
  local search="$base"
  [ "$sub" != "." ] && search="$base/$sub"
  [ -d "$search" ] || { warn "El pack $id no tiene el subdirectorio '$sub'"; return 1; }

  local dest="$DATA_ROOT/.claude/skills/$dom"
  run mkdir -p "$dest"

  local count=0 skillmd skilldir name
  while IFS= read -r skillmd; do
    skilldir="$(dirname "$skillmd")"
    name="$(basename "$skilldir")"
    # no pisar un skill propio con uno de tercero
    if [ -e "$dest/$name" ] && [ ! -L "$dest/$name" ]; then
      warn "  '$name' ya existe como skill propio; no lo reemplazo con el del pack $id"
      continue
    fi
    run ln -sfn "$skilldir" "$dest/$name"
    count=$((count+1))
  done < <(find "$search" -maxdepth 3 -name SKILL.md -not -path '*/.git/*' | sort)

  ok "  $id → $count skills en $dom/"
  return 0
}

thirdparty_install_pack() {
  local id="$1"
  local row; row="$(_pack_rows | awk -F'\t' -v id="$id" '$1==id')"
  [ -n "$row" ] || die "No existe el pack de skills '$id'."
  local tier dom repo sub desc
  IFS=$'\t' read -r _ tier dom repo sub desc <<<"$row"

  local base; base="$(packs_dir)/$id"
  if [ -d "$base/.git" ]; then
    info "Actualizando pack $id"
    run git -C "$base" pull --quiet --ff-only || warn "No se pudo actualizar $id"
  else
    info "Clonando pack $id"
    run mkdir -p "$(dirname "$base")"
    run git clone --quiet --depth 1 "$repo" "$base" || { warn "No se pudo clonar $repo"; return 1; }
  fi
  [ "$DRY_RUN" = 1 ] || lock_record "skills:$id" "$(git -C "$base" rev-parse --short HEAD 2>/dev/null || echo '?')"
  _pack_link "$base" "$sub" "$dom" "$id"
}

thirdparty_wizard() {
  step "4/8 · Packs de skills"
  local id tier dom repo sub desc

  while IFS=$'\t' read -r id tier dom repo sub desc; do
    case "$tier" in
      core)
        thirdparty_install_pack "$id" || true
        ;;
      negocio)
        printf '\n%s%s%s — %s\n' "$C_B" "$id" "$C_RESET" "$desc"
        confirm "¿Instalar el pack $id?" y && { thirdparty_install_pack "$id" || true; }
        ;;
      opcional)
        printf '\n%s%s%s — %s\n' "$C_B" "$id" "$C_RESET" "$desc"
        confirm "¿Instalar el pack $id? (grande, opcional)" n && { thirdparty_install_pack "$id" || true; }
        ;;
    esac
  done < <(_pack_rows)
}

thirdparty_update_all() {
  local id
  while IFS=$'\t' read -r id _; do
    [ -d "$(packs_dir)/$id/.git" ] || continue
    thirdparty_install_pack "$id" || true
  done < <(_pack_rows)
}
