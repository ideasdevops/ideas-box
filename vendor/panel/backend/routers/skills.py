import re
from pathlib import Path

from fastapi import APIRouter, HTTPException, Query

from config import SKILLS_DIR, SKILL_DOMAINS
from routers.agents import _parse_frontmatter

router = APIRouter(prefix="/api/skills", tags=["skills"])


def _origen(skill_dir: Path) -> str:
    """'propia' (de Ideas Box o creada por la empresa) o el nombre del pack de terceros."""
    try:
        real = skill_dir.resolve()
    except OSError:
        return "propia"
    partes = real.parts
    if "skill-packs" in partes:
        i = partes.index("skill-packs")
        if i + 1 < len(partes):
            return partes[i + 1]
    return "propia"


def scan_skills() -> list[dict]:
    skills = []
    if not SKILLS_DIR.exists():
        return skills
    for domain in SKILL_DOMAINS:
        domain_dir = SKILLS_DIR / domain
        if not domain_dir.exists():
            continue
        # Un nivel: dominio/<skill>/SKILL.md -- no recursivo, para no explotar las
        # capabilities anidadas de web-design-library como si fueran skills sueltos.
        for skill_dir in sorted(p for p in domain_dir.iterdir() if p.is_dir()):
            skill_file = skill_dir / "SKILL.md"
            if not skill_file.exists():
                continue
            text = skill_file.read_text(encoding="utf-8", errors="replace")
            meta = _parse_frontmatter(text)
            skills.append({
                "nombre": meta.get("name", skill_dir.name),
                "dominio": domain,
                "descripcion": meta.get("description", ""),
                "carpeta": skill_dir.name,
                "origen": _origen(skill_dir),
                "archivo": str(skill_file),
            })
    return skills


_STOPWORDS = {
    "para", "esta", "este", "estos", "estas", "cual", "cuales", "sobre", "como",
    "donde", "desde", "hacia", "pero", "aunque", "cuando", "todo", "toda", "todos",
    "todas", "otro", "otra", "otros", "otras", "solo", "sola", "with", "from", "that",
    "this", "these", "those", "when", "where", "which",
}


def suggest_skills(text: str, limit: int = 4, min_score: int = 2) -> list[dict]:
    """Match crudo por palabras del titulo/descripcion contra nombre+descripcion de skills.
    Heuristica simple a proposito -- no vale la pena un embedding para esto. min_score=2
    exige al menos 2 palabras en común para filtrar ruido de una sola coincidencia genérica."""
    words = {w for w in re.split(r"\W+", text.lower()) if len(w) > 3 and w not in _STOPWORDS}
    if not words:
        return []
    scored = []
    for skill in scan_skills():
        haystack = f"{skill['nombre']} {skill['descripcion']}".lower()
        score = sum(1 for w in words if w in haystack)
        if score >= min_score:
            scored.append((score, skill))
    scored.sort(key=lambda pair: pair[0], reverse=True)
    return [s for _, s in scored[:limit]]


@router.get("")
def list_skills(q: str | None = Query(default=None, description="filtro de texto libre")):
    skills = scan_skills()
    if q:
        needle = q.lower()
        skills = [
            s for s in skills
            if needle in s["nombre"].lower() or needle in s["descripcion"].lower()
        ]
    return {"total": len(skills), "skills": skills}


@router.get("/{dominio}/{carpeta}")
def skill_detail(dominio: str, carpeta: str):
    for s in scan_skills():
        if s["dominio"] == dominio and s["carpeta"] == carpeta:
            from routers.agents import _FRONTMATTER_RE, scan_agents  # noqa: PLC0415
            texto = Path(s["archivo"]).read_text(encoding="utf-8", errors="replace")
            cuerpo = _FRONTMATTER_RE.sub("", texto, count=1).strip()
            ref = f"{dominio}/{carpeta}"
            usan = [a["nombre"] for a in scan_agents()
                    if ref in Path(a["archivo"]).read_text(encoding="utf-8", errors="replace")]
            return {**s, "contenido": cuerpo[:60000], "agentes": usan}
    raise HTTPException(404, "habilidad no encontrada")
