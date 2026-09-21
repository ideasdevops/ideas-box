#!/usr/bin/env bash
# Perfil de la empresa: lo que después rellena plantillas de agentes, docs y CLAUDE.md.

profile_defaults() {
  EMPRESA_NOMBRE="${EMPRESA_NOMBRE:-}"
  EMPRESA_SLUG="${EMPRESA_SLUG:-}"
  EMPRESA_RUBRO="${EMPRESA_RUBRO:-}"
  EMPRESA_SITIO="${EMPRESA_SITIO:-}"
  EMPRESA_RESPONSABLE="${EMPRESA_RESPONSABLE:-}"
  EMPRESA_IDIOMA="${EMPRESA_IDIOMA:-es}"
  EMPRESA_TZ="${EMPRESA_TZ:-$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)}"
  DATA_ROOT="${DATA_ROOT:-}"
}

profile_wizard() {
  step "2/8 · Identidad de la empresa"
  profile_defaults

  if [ -f "$STACK_PROFILE" ] && [ "$NON_INTERACTIVE" != 1 ]; then
    warn "Ya existe un perfil en $STACK_PROFILE"
    if confirm "¿Reusar el perfil existente?" y; then
      load_profile
      ok "Perfil reusado: $EMPRESA_NOMBRE"
      return 0
    fi
  fi

  cat <<'TXT'

Estos datos personalizan los agentes, la documentación y la memoria del stack.
No se envían a ningún lado: quedan en tu equipo.

TXT
  while [ -z "$EMPRESA_NOMBRE" ]; do
    ask "Nombre de la empresa" EMPRESA_NOMBRE
    [ -n "$EMPRESA_NOMBRE" ] || err "El nombre no puede quedar vacío."
  done
  EMPRESA_SLUG="$(slugify "$EMPRESA_NOMBRE")"
  ask "Identificador corto (para rutas y nombres de MCP)" EMPRESA_SLUG "$EMPRESA_SLUG"
  EMPRESA_SLUG="$(slugify "$EMPRESA_SLUG")"
  ask "¿A qué se dedica? (una línea, la leen los agentes)" EMPRESA_RUBRO "servicios digitales"
  ask "Sitio web o dominio principal (opcional)" EMPRESA_SITIO ""
  ask "Nombre de quien opera el stack (opcional)" EMPRESA_RESPONSABLE ""
  ask "Idioma de trabajo de los agentes (es/en)" EMPRESA_IDIOMA "$EMPRESA_IDIOMA"
  ask "Zona horaria" EMPRESA_TZ "$EMPRESA_TZ"

  ok "Perfil: $EMPRESA_NOMBRE ($EMPRESA_SLUG) · $EMPRESA_RUBRO"
}

profile_save() {
  run mkdir -p "$STACK_CONFIG_DIR" "$STACK_SECRETS_DIR"
  run chmod 700 "$STACK_CONFIG_DIR" "$STACK_SECRETS_DIR" 2>/dev/null || true
  write_file "$STACK_PROFILE" 600 <<EOF
# Perfil del stack — generado por install.sh el $(date -Iseconds)
# Editable a mano; volvé a correr \`$STACK_NAME sync\` después de cambiarlo.
EMPRESA_NOMBRE="$EMPRESA_NOMBRE"
EMPRESA_SLUG="$EMPRESA_SLUG"
EMPRESA_RUBRO="$EMPRESA_RUBRO"
EMPRESA_SITIO="$EMPRESA_SITIO"
EMPRESA_RESPONSABLE="$EMPRESA_RESPONSABLE"
EMPRESA_IDIOMA="$EMPRESA_IDIOMA"
EMPRESA_TZ="$EMPRESA_TZ"
DATA_ROOT="$DATA_ROOT"
STACK_SRC="$STACK_SRC"
STACK_VERSION="$(cat "$STACK_SRC/VERSION" 2>/dev/null || echo 0.0.0)"
EOF
  ok "Perfil guardado en $STACK_PROFILE"
}
