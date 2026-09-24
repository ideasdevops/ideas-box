#!/usr/bin/env bash
# Habilidades y conectores propios de la empresa, creados por el usuario.
# Viven en la raíz de datos (se respaldan con ella), nunca en el repo del stack:
#   habilidades → $DATA_ROOT/.claude/skills/<área>/<nombre>/SKILL.md
#   conectores  → $DATA_ROOT/.claude/mcp-catalog/<id>.mcp  (mismo formato que catalog/mcp)

# skills_new — pregunta nombre, área y propósito, deja una habilidad lista para completar
skills_new() {
  local nombre slug desc area_n dom dir i=0
  echo
  echo "Una habilidad es una receta de trabajo que tus agentes siguen cuando hace falta:"
  echo "por ejemplo «responder presupuestos», «publicar una promo» o «cerrar el mes»."
  echo
  ask "¿Cómo se llama la habilidad?" nombre ""
  [ -n "$nombre" ] || die "La habilidad necesita un nombre."
  slug="$(slugify "$nombre")"
  [ -n "$slug" ] || die "El nombre tiene que tener al menos una letra o un número."
  ask "¿Para qué sirve? (una línea: cuándo la tienen que usar los agentes)" desc ""
  [ -n "$desc" ] || desc="$nombre"

  echo
  echo "¿De qué área es?"
  for dom in "${DOMINIOS[@]}"; do i=$((i+1)); printf '  %d) %s\n' "$i" "$(area_label "$dom")"; done
  ask "Área" area_n 1
  case "$area_n" in ''|*[!0-9]*) area_n=1 ;; esac
  [ "$area_n" -ge 1 ] && [ "$area_n" -le "${#DOMINIOS[@]}" ] || area_n=1
  dom="${DOMINIOS[$((area_n-1))]}"

  dir="$DATA_ROOT/.claude/skills/$dom/$slug"
  [ -e "$dir" ] && die "Ya existe una habilidad «$slug» en $(area_label "$dom"): $dir"
  run mkdir -p "$dir"
  write_file "$dir/SKILL.md" 644 <<EOF
---
name: $slug
description: $desc
---

# $nombre

## Cuándo usarla
- $desc

## Pasos
1. (completar: qué se revisa primero)
2. (completar: qué se hace)
3. (completar: cómo se entrega o a quién se avisa)

## Reglas
- Todo lo que salga hacia afuera (clientes, publicaciones, pagos) pide aprobación explícita.
EOF
  canonical_link >/dev/null
  ok "Habilidad creada: $(area_label "$dom") → $nombre"
  info "Archivo: $dir/SKILL.md"

  if have claude && confirm "¿Abrimos Claude para completarla juntos? (te va a hacer preguntas y la escribe por vos)" y; then
    (cd "$HOME" && claude "Completemos la habilidad «$nombre» que acabo de crear en $dir/SKILL.md. Sirve para: $desc. Hacéme las preguntas que necesites sobre cómo trabajamos y reescribí los pasos y las reglas con lo que te cuente. Mantené el encabezado name/description.") || true
  else
    info "Cuando quieras, abrí Claude y pedile: «completemos la habilidad $nombre»."
  fi
}

# --- Conectores propios -------------------------------------------------------

# mcp_new — arma un conector a partir de la línea de instalación que trae su documentación
# (npx -y <paquete> ... para Node, uvx <paquete> ... para Python)
mcp_new() {
  local linea titulo desc id claves cat
  cat="$(mcp_user_catalog)"
  [ -n "$cat" ] || die "No hay raíz de datos cargada. Instalá Ideas Box primero."
  echo
  echo "Pegá la línea que indica la documentación del conector para arrancarlo. Ejemplos:"
  echo "  npx -y @modelcontextprotocol/server-github"
  echo "  uvx mcp-server-fetch"
  echo
  ask "Línea de instalación" linea ""
  [ -n "$linea" ] || die "Sin la línea de instalación no puedo armar el conector. Pedíselo a Claude desde el menú."
  ask "¿Cómo le decimos a esta herramienta? (ej: GitHub)" titulo ""
  [ -n "$titulo" ] || die "El conector necesita un nombre."
  id="$(slugify "$titulo")"
  if [ -f "$STACK_SRC/catalog/mcp/$id.mcp" ]; then
    die "«$id» ya está en la lista oficial de conectores. Usá «Conectar una herramienta»."
  fi
  ask "¿Para qué la van a usar los agentes? (una línea)" desc "Conector propio de $titulo"
  echo "Si la documentación pide claves o datos de acceso (variables como GITHUB_TOKEN o API_KEY),"
  echo "escribí sus nombres separados por espacios. Los valores te los pido después, al conectarla."
  ask "Nombres de las variables (Enter si no pide ninguna)" claves ""

  run mkdir -p "$cat"
  if [ "$DRY_RUN" = 1 ]; then run "escribir $cat/$id.mcp a partir de: $linea"; return 0; fi

  LINEA="$linea" ID="$id" TITULO="$titulo" DESC="$desc" CLAVES="$claves" \
    python3 - > "$cat/$id.mcp.tmp" <<'PY' || { rm -f "$cat/$id.mcp.tmp"; die "No reconozco esa línea. Tiene que empezar con npx o uvx; si no, pedíselo a Claude desde el menú."; }
import json, os, re, shlex, sys

partes = shlex.split(os.environ["LINEA"])
if not partes:
    sys.exit(1)
herr, resto = partes[0], partes[1:]

def q(v):
    return shlex.quote(v)

out = {
    "ID": os.environ["ID"], "TITLE": os.environ["TITULO"], "DESC": os.environ["DESC"],
    "TIER": "propio", "TOOLGROUP": os.environ["ID"],
}
if herr == "npx":
    pos = [p for p in resto if not p.startswith("-")]
    if not pos:
        sys.exit(1)
    paquete, extra = pos[0], resto[resto.index(pos[0]) + 1:]
    out.update({
        "KIND": "custom",
        # Se baja una vez al conectar, para fallar ahí y no cuando lo use un agente
        "INSTALL_CUSTOM": f'PATH="__NODEDIR__:$PATH" "__NODEDIR__/npm" cache add {q(paquete)}',
        "CMD": "__NPX__",
        "ARGS_JSON": json.dumps(["-y", paquete] + extra),
        "LAUNCH_ENV": 'PATH="__NODEDIR__:$PATH"',
        "ORIGEN": f"npm:{paquete}",
    })
elif herr == "uvx":
    paquete = None
    if len(resto) >= 2 and resto[0] == "--from":
        paquete, resto = resto[1], resto[2:]
    resto = [p for p in resto]
    if not resto:
        sys.exit(1)
    comando, extra = resto[0], resto[1:]
    paquete = paquete or comando
    out.update({
        "KIND": "python",
        "BUILD": f"venv/bin/pip install --quiet {q(paquete)}",
        "DIR": f"propio-{os.environ['ID']}",
        "CMD": f"__SRC__/venv/bin/{re.sub(r'[=<>~!].*$', '', comando)}",
        "ARGS_JSON": json.dumps(extra),
        "ORIGEN": f"pypi:{paquete}",
    })
else:
    sys.exit(1)

claves = os.environ["CLAVES"].split()
if claves:
    out["ENV_KEYS"] = " ".join(claves)
    out["ENV_SECRET"] = " ".join(k for k in claves if re.search(r"KEY|TOKEN|SECRET|PASS", k, re.I))

print("# Conector propio — creado con `ideasbox mcp new`. Editable a mano.")
for k, v in out.items():
    print(f"{k}={q(v)}")
PY
  mv "$cat/$id.mcp.tmp" "$cat/$id.mcp"
  ok "Conector «$titulo» creado en $cat/$id.mcp"
  if confirm "¿Lo conectamos ahora?" y; then
    mcp_install "$id"
    canonical_render >/dev/null
  else
    info "Cuando quieras: menú → «Conectar una herramienta» → $titulo"
  fi
}
