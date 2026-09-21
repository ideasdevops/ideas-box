#!/usr/bin/env python3
"""Renderiza las plantillas del stack en la raíz de datos de la empresa.

Dos cosas que hace y que un `cp` no haría:

1. Expande grupos de herramientas MCP. Una plantilla de agente escribe
   `{{TOOLS easypanel:ro}}` y acá se convierte en una línea por herramienta y por
   servidor realmente instalado. Si el servidor no está, la línea desaparece:
   así ningún agente declara un `mcp__...` inexistente y se queda sin capacidad.

2. No pisa lo que el usuario editó. Guarda el hash de lo último que generó; si el
   archivo en destino cambió respecto de eso, deja la versión nueva al lado como
   `.nuevo` y avisa, en vez de sobrescribir.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import sys
from pathlib import Path

VAR_RE = re.compile(r"\{\{([A-Z_]+)\}\}")
TOOLS_RE = re.compile(r"^(?P<indent>[ \t]*)(?:- +)?\{\{TOOLS +(?P<group>[a-z0-9-]+:[a-z0-9-]+)\}\}[ \t]*$")


def load_groups(path: Path) -> dict[str, list[str]]:
    groups: dict[str, list[str]] = {}
    if not path.exists():
        return groups
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        groups[parts[0].strip()] = [t.strip() for t in parts[1].split(",") if t.strip()]
    return groups


def load_registry(path: Path) -> dict[str, list[str]]:
    """toolgroup -> [nombres de servidor instalados]"""
    reg: dict[str, list[str]] = {}
    if not path.exists():
        return reg
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) < 3:
            continue
        server, _id, toolgroup = cols[0], cols[1], cols[2]
        reg.setdefault(toolgroup, []).append(server)
    return reg


def expand_tools(text: str, groups: dict[str, list[str]], registry: dict[str, list[str]],
                 warnings: list[str]) -> str:
    out: list[str] = []
    for line in text.splitlines():
        m = TOOLS_RE.match(line)
        if not m:
            out.append(line)
            continue
        group = m.group("group")
        indent = m.group("indent")
        family = group.split(":", 1)[0]
        tools = groups.get(group)
        if tools is None:
            warnings.append(f"grupo de herramientas desconocido: {group}")
            continue
        servers = registry.get(family, [])
        for server in servers:
            for tool in tools:
                out.append(f"{indent}- mcp__{server}__{tool}")
    return "\n".join(out) + ("\n" if text.endswith("\n") else "")


def substitute(text: str, variables: dict[str, str], warnings: list[str], origin: str) -> str:
    def repl(m: re.Match) -> str:
        key = m.group(1)
        if key not in variables:
            warnings.append(f"variable sin valor {{{{{key}}}}} en {origin}")
            return m.group(0)
        return variables[key]

    return VAR_RE.sub(repl, text)


def sha(data: str | bytes) -> str:
    if isinstance(data, str):
        data = data.encode()
    return hashlib.sha256(data).hexdigest()[:16]


def load_state(path: Path) -> dict[str, str]:
    state: dict[str, str] = {}
    if path.exists():
        for line in path.read_text().splitlines():
            if "\t" in line:
                k, v = line.split("\t", 1)
                state[k] = v
    return state


def save_state(path: Path, state: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{k}\t{v}\n" for k, v in sorted(state.items())))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="directorio de plantillas")
    ap.add_argument("--dest", required=True, help="directorio destino")
    ap.add_argument("--groups", required=True)
    ap.add_argument("--registry", required=True)
    ap.add_argument("--state", required=True)
    ap.add_argument("--force", action="store_true", help="sobrescribir aunque el usuario haya editado")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    src, dest = Path(args.src), Path(args.dest)
    groups = load_groups(Path(args.groups))
    registry = load_registry(Path(args.registry))
    state = load_state(Path(args.state))
    warnings: list[str] = []

    variables = {k[4:]: v for k, v in os.environ.items() if k.startswith("VAR_")}

    written = skipped = conflicts = 0

    for path in sorted(src.rglob("*")):
        if path.is_dir() or path.name.startswith("."):
            continue
        rel = path.relative_to(src)
        target = dest / (str(rel)[:-5] if rel.name.endswith(".tmpl") else str(rel))

        if rel.name.endswith(".tmpl"):
            text = path.read_text()
            text = expand_tools(text, groups, registry, warnings)
            text = substitute(text, variables, warnings, str(rel))
            payload = text
        else:
            payload = path.read_bytes()

        digest = sha(payload)
        key = str(target)

        if target.exists():
            current = sha(target.read_bytes() if isinstance(payload, bytes) else target.read_text())
            if current == digest:
                skipped += 1
                state[key] = digest
                continue
            if not args.force and state.get(key) not in (None, current):
                # el usuario lo editó después de que lo generamos
                alt = Path(str(target) + ".nuevo")
                if not args.dry_run:
                    alt.parent.mkdir(parents=True, exist_ok=True)
                    alt.write_text(payload) if isinstance(payload, str) else alt.write_bytes(payload)
                warnings.append(f"editado por vos, dejé la versión nueva en {alt}")
                conflicts += 1
                continue

        if not args.dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(payload) if isinstance(payload, str) else target.write_bytes(payload)
            if target.suffix == ".sh" or target.parent.name == "hooks":
                target.chmod(0o755)
        state[key] = digest
        written += 1

    if not args.dry_run:
        save_state(Path(args.state), state)

    for w in dict.fromkeys(warnings):
        print(f"  ! {w}", file=sys.stderr)
    print(f"  {written} archivos escritos, {skipped} sin cambios, {conflicts} conservados por edición propia")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
