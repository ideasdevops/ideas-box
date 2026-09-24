"""
Redacción autónoma de tareas de CONTENIDO, y nada más.

Regla dura del stack: **el panel nunca publica solo.** Redacta el contenido
final y avisa que está listo; el panel no llama a ninguna API de redes
sociales y no tiene credenciales de ninguna red. `auto_publicar=1` solo cambia
el texto del aviso ("publicar pronto"): la publicación real la hace una
persona, o un agente en una sesión de Claude Code con los conectores MCP
instalados, que es donde sí existe el control de aprobación.

Sumar una llamada real a una API de publicación acá es una decisión de diseño
nueva, no un ajuste de configuración.
"""
from fastapi import APIRouter, HTTPException

from db import db_session
from routers.agents import find_agent
from routers.skills import suggest_skills
from services.openrouter import call_openrouter
from services.notify import send_task_ready_alert

router = APIRouter(prefix="/api/tasks", tags=["execution"])

# Únicos agentes habilitados para redactar sin intervención. Deploy, SEO y
# desarrollo quedan afuera a propósito: tocan producción o infraestructura de
# clientes, donde equivocarse cuesta caro. Ampliar esta lista es una decisión
# de diseño, no un cambio de configuración.
AGENTES_ELEGIBLES = {"content-strategist", "design-content"}


@router.get("/{task_id}/elegible")
def es_elegible(task_id: int):
    with db_session() as conn:
        row = conn.execute("SELECT agente_sugerido FROM tasks WHERE id = ?", (task_id,)).fetchone()
        if not row:
            raise HTTPException(404, "tarea no encontrada")
        return {"elegible": row["agente_sugerido"] in AGENTES_ELEGIBLES}


@router.post("/{task_id}/ejecutar")
def ejecutar_tarea(task_id: int):
    with db_session() as conn:
        row = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
        if not row:
            raise HTTPException(404, "tarea no encontrada")
        task = dict(row)

    if task["agente_sugerido"] not in AGENTES_ELEGIBLES:
        raise HTTPException(
            400,
            f"ejecución autónoma no habilitada para el agente '{task['agente_sugerido']}' -- "
            f"solo {', '.join(sorted(AGENTES_ELEGIBLES))} por ahora",
        )
    if task["estado"] not in ("pendiente",):
        raise HTTPException(400, f"la tarea ya está en estado '{task['estado']}', no se puede re-ejecutar desde acá")

    with db_session() as conn:
        conn.execute("UPDATE tasks SET estado = 'en_progreso', actualizada_en = datetime('now') WHERE id = ?", (task_id,))

    agent = find_agent(task["agente_sugerido"])
    skills = suggest_skills(f"{task['titulo']} {task['descripcion']}")
    skills_txt = "\n".join(f"- {s['dominio']}/{s['carpeta']}: {s['descripcion'][:200]}" for s in skills)

    system_prompt = f"""Sos {agent['nombre']}: {agent['descripcion']}

Tu trabajo ahora es redactar el CONTENIDO FINAL para la siguiente tarea -- no un plan, no
sugerencias, el texto/copy real y listo para revisar. Si la tarea no da suficiente detalle
para redactar algo concreto y útil, redactá la mejor versión razonable y dejá explícito
al final, en una línea aparte, qué información adicional convendría confirmar antes de
publicar -- no dejes de producir contenido solo por falta de detalle menor.

{f"Skills de referencia (criterios a aplicar):{chr(10)}{skills_txt}" if skills_txt else ""}

No inventes datos factuales (precios, fechas, cifras) que no estén en la tarea -- usá
placeholders visibles entre corchetes para esos casos, ej. [fecha de fin de promo]."""

    contenido = call_openrouter(
        system_prompt,
        [{"role": "user", "content": f"Título: {task['titulo']}\n\nDescripción: {task['descripcion']}"}],
        temperature=0.6,
    )

    with db_session() as conn:
        conn.execute(
            """UPDATE tasks SET estado = 'listo_para_revision', resultado_ejecucion = ?, actualizada_en = datetime('now')
               WHERE id = ?""",
            (contenido, task_id),
        )
        row = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
        task = dict(row)

    alerta = send_task_ready_alert(task)

    return {"tarea": task, "aviso": alerta}
