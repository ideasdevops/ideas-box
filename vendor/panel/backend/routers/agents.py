import re

from fastapi import APIRouter

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
