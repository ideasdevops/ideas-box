import re
from pathlib import Path

from fastapi import APIRouter, HTTPException

from config import AGENTS_DIR, AGENT_DOMAINS

router = APIRouter(prefix="/api/agents", tags=["agents"])

# Frontmatter YAML-ish minimo: name/description/tools, sin depender de PyYAML
_FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
_FIELD_RE = re.compile(r"^([a-zA-Z_]+):\s*(.*)$")


def _parse_frontmatter(text: str) -> dict:
    match = _FRONTMATTER_RE.match(text)
    if not match:
        return {}
    fields: dict[str, str] = {}
    current_key = None
    for line in match.group(1).splitlines():
        field_match = _FIELD_RE.match(line)
        if field_match:
            current_key = field_match.group(1)
            fields[current_key] = field_match.group(2).strip().strip('"').strip("'")
        elif current_key and line.startswith((" ", "\t")):
            fields[current_key] = (fields.get(current_key, "") + " " + line.strip()).strip()
    return fields


def _conectores(tools: str) -> list[dict]:
    """Agrupa las herramientas mcp__<servidor>__<tool> por conector, para mostrarlas legibles."""
    por_servidor: dict[str, list[str]] = {}
    basicas = []
    for t in (x.lstrip("-") for x in re.split(r"[\s,]+", tools)):
        if t.startswith("mcp__") and t.count("__") >= 2:
            _, servidor, tool = t.split("__", 2)
            por_servidor.setdefault(servidor, []).append(tool)
        elif t and t[0].isupper():
            basicas.append(t)
    out = [{"conector": s, "herramientas": sorted(v)} for s, v in sorted(por_servidor.items())]
    if basicas:
        out.insert(0, {"conector": "básicas", "herramientas": basicas})
    return out


def scan_agents() -> list[dict]:
    agents = []
    if not AGENTS_DIR.exists():
        return agents
    for domain in AGENT_DOMAINS:
        domain_dir = AGENTS_DIR / domain
        if not domain_dir.exists():
            continue
        for agent_file in sorted(domain_dir.glob("*.md")):
            text = agent_file.read_text(encoding="utf-8", errors="replace")
            meta = _parse_frontmatter(text)
            agents.append({
                "nombre": meta.get("name", agent_file.stem),
                "dominio": domain,
                "descripcion": meta.get("description", ""),
                "tools": meta.get("tools", ""),
                "modelo": meta.get("model", ""),
                "conectores": _conectores(meta.get("tools", "")),
                "archivo": str(agent_file),
            })
    return agents


def find_agent(nombre: str) -> dict | None:
    if not nombre:
        return None
    needle = nombre.strip().lower()
    for agent in scan_agents():
        if agent["nombre"].lower() == needle:
            return agent
    return None


@router.get("")
def list_agents():
    agents = scan_agents()
    return {"total": len(agents), "agentes": agents}


@router.get("/{nombre}")
def agent_detail(nombre: str):
    from routers.skills import scan_skills  # noqa: PLC0415
    agent = find_agent(nombre)
    if not agent:
        raise HTTPException(404, "agente no encontrado")
    texto = Path(agent["archivo"]).read_text(encoding="utf-8", errors="replace")
    cuerpo = _FRONTMATTER_RE.sub("", texto, count=1).strip()
    # Skills que el agente menciona (dominio/carpeta) en sus instrucciones
    usa = [s for s in scan_skills() if f"{s['dominio']}/{s['carpeta']}" in cuerpo]
    return {**agent, "instrucciones": cuerpo, "skills": usa}
