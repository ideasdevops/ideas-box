#!/usr/bin/env bash
# Árbol canónico: renderiza agentes, skills, docs y memoria en la raíz de datos,
# y deja en ~/.claude solo symlinks. La fuente de verdad nunca vive en el home.

DOMINIOS=(core dev ops qa ventas marketing contenido clientes internos)

canonical_render() {
  step "6/8 · Agentes, skills y documentación"
  local force="${1:-}"

  local -a env_vars=(
    "VAR_EMPRESA=$EMPRESA_NOMBRE"
    "VAR_EMPRESA_SLUG=$EMPRESA_SLUG"
    "VAR_RUBRO=$EMPRESA_RUBRO"
    "VAR_SITIO=${EMPRESA_SITIO:-(sin sitio configurado)}"
    "VAR_RESPONSABLE=${EMPRESA_RESPONSABLE:-el responsable del stack}"
    "VAR_DATA_ROOT=$DATA_ROOT"
    "VAR_TZ=$EMPRESA_TZ"
    "VAR_IDIOMA=$EMPRESA_IDIOMA"
    "VAR_FECHA=$(date +%Y-%m-%d)"
    "VAR_STACK=$STACK_NAME"
    "VAR_HOME=$HOME"
  )

  local extra=()
  [ "$force" = "--force" ] && extra+=(--force)
  [ "$DRY_RUN" = 1 ] && extra+=(--dry-run)

  run env "${env_vars[@]}" python3 "$STACK_SRC/tools/render.py" \
    --src "$STACK_SRC/templates/claude" \
    --dest "$DATA_ROOT/.claude" \
    --groups "$STACK_SRC/catalog/tool-groups.tsv" \
    --registry "$MCP_REGISTRY" \
    --state "$STACK_CONFIG_DIR/rendered.tsv" \
    "${extra[@]}"

  run env "${env_vars[@]}" python3 "$STACK_SRC/tools/render.py" \
    --src "$STACK_SRC/templates/home" \
    --dest "$HOME" \
    --groups "$STACK_SRC/catalog/tool-groups.tsv" \
    --registry "$MCP_REGISTRY" \
    --state "$STACK_CONFIG_DIR/rendered-home.tsv" \
    "${extra[@]}"

  ok "Árbol canónico en $DATA_ROOT/.claude"
}

# Symlinks de runtime: ~/.claude/{agents,skills} -> raíz canónica.
canonical_link() {
  step "7/8 · Runtime de Claude Code"
  local kind src dst dom item

  for kind in agents skills; do
    for dom in "${DOMINIOS[@]}"; do
      src="$DATA_ROOT/.claude/$kind/$dom"
      dst="$CLAUDE_CONFIG_DIR/$kind/$dom"
      [ -d "$src" ] || continue
      run mkdir -p "$dst"

      # limpiar symlinks rotos de corridas anteriores
      if [ "$DRY_RUN" != 1 ]; then
        find "$dst" -maxdepth 1 -xtype l -delete 2>/dev/null || true
      fi

      shopt -s nullglob
      for item in "$src"/*; do
        local name; name="$(basename "$item")"
        local link="$dst/$name"
        if [ -e "$link" ] && [ ! -L "$link" ]; then
          warn "$link existe y no es un symlink; lo dejo como está."
          continue
        fi
        run ln -sfn "$item" "$link"
      done
      shopt -u nullglob
    done
  done

  ok "Runtime enlazado en $CLAUDE_CONFIG_DIR"
}

canonical_main() {
  canonical_render "$@"
  canonical_link
}
