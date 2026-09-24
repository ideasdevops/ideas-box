from datetime import datetime, timedelta
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from config import EMPRESA_NOMBRE
from db import db_session
from routers.agents import find_agent
from routers.servers import find_server
from routers.skills import suggest_skills

router = APIRouter(prefix="/api/tasks", tags=["tasks"])

Prioridad = Literal["baja", "media", "alta"]
Estado = Literal["pendiente", "en_progreso", "listo_para_revision", "hecho", "descartada"]
Recurrencia = Literal["ninguna", "diaria", "semanal", "mensual"]


def _next_occurrence(base: datetime, recurrencia: Recurrencia) -> datetime:
    if recurrencia == "diaria":
        return base + timedelta(days=1)
    if recurrencia == "semanal":
        return base + timedelta(weeks=1)
    if recurrencia == "mensual":
        # Sin dependencias de terceros (dateutil) -- suma 1 mes a mano, con
        # clamp de dia si el mes destino es mas corto (ej. 31 ene -> 28/29 feb).
        month = base.month + 1
        year = base.year + (1 if month > 12 else 0)
        month = 1 if month > 12 else month
        for day in range(base.day, 0, -1):
            try:
                return base.replace(year=year, month=month, day=day)
            except ValueError:
                continue
    return base


class TaskCreate(BaseModel):
    titulo: str
    descripcion: str = ""
    agente_sugerido: str = ""
    server_objetivo: str = ""
    prioridad: Prioridad = "media"
    programada_para: str | None = None
    recurrencia: Recurrencia = "ninguna"
    auto_publicar: bool = False


class TaskUpdate(BaseModel):
    titulo: str | None = None
    descripcion: str | None = None
    agente_sugerido: str | None = None
    server_objetivo: str | None = None
    prioridad: Prioridad | None = None
    estado: Estado | None = None
    programada_para: str | None = None
    recurrencia: Recurrencia | None = None
    auto_publicar: bool | None = None


@router.get("")
def list_tasks(estado: Estado | None = None, fuente: str | None = None):
    with db_session() as conn:
        query = "SELECT * FROM tasks"
        clauses, params = [], []
        if estado:
            clauses.append("estado = ?")
            params.append(estado)
        if fuente:
            clauses.append("fuente = ?")
            params.append(fuente)
        if clauses:
            query += " WHERE " + " AND ".join(clauses)
        query += " ORDER BY creada_en DESC"
        rows = conn.execute(query, params).fetchall()
        return {"total": len(rows), "tareas": [dict(r) for r in rows]}


@router.get("/templates")
def list_templates():
    with db_session() as conn:
        rows = conn.execute("SELECT * FROM task_templates ORDER BY id").fetchall()
        return {"templates": [dict(r) for r in rows]}


@router.post("")
def create_task(task: TaskCreate):
    with db_session() as conn:
        cursor = conn.execute(
            """INSERT INTO tasks (titulo, descripcion, agente_sugerido, server_objetivo, prioridad, programada_para, recurrencia, auto_publicar)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (task.titulo, task.descripcion, task.agente_sugerido, task.server_objetivo, task.prioridad, task.programada_para, task.recurrencia, int(task.auto_publicar)),
        )
        new_id = cursor.lastrowid
        row = conn.execute("SELECT * FROM tasks WHERE id = ?", (new_id,)).fetchone()
        return dict(row)


@router.get("/{task_id}/prompt")
def generate_prompt(task_id: int):
    with db_session() as conn:
        row = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
        if not row:
            raise HTTPException(404, "tarea no encontrada")
        task = dict(row)

    agent = find_agent(task["agente_sugerido"])
    server = find_server(task["server_objetivo"])
    skills = suggest_skills(f"{task['titulo']} {task['descripcion']}")

    lines = [
        f"# Tarea: {task['titulo']}",
        "",
        task["descripcion"] or "(sin descripción adicional)",
        "",
    ]

    if agent:
        lines += [
            f"## Rol sugerido: {agent['nombre']} ({agent['dominio']})",
            agent["descripcion"],
            "",
        ]
    elif task["agente_sugerido"]:
        lines += [f"## Rol sugerido: {task['agente_sugerido']} (no encontrado en el catálogo actual — verificar el nombre)", ""]

    if skills:
        lines.append("## Skills relevantes a consultar primero")
        for s in skills:
            lines.append(f"- `{s['dominio']}/{s['carpeta']}` — {s['descripcion'][:140]}")
        lines.append("")

    if server:
        lines += [
            f"## Server objetivo: {server['label']}",
            "MCPs disponibles: " + ", ".join(f"`{m}`" for m in server["mcps"]) + ".",
            "Lectura (estado, logs, métricas) es libre; ejecutar comandos, reiniciar servicios o "
            "bajar backups requiere aprobación explícita.",
            "",
            "**Antes de ejecutar cualquier acción real contra este server**: confirmar el alcance exacto con el usuario "
            "si toca infraestructura de un cliente — no asumir autorización implícita por estar en el roster.",
            "",
        ]
    elif task["server_objetivo"]:
        lines += [f"## Server objetivo: {task['server_objetivo']} (no matchea el roster conocido — verificar)", ""]

    lines += [
        "---",
        f"Tarea #{task['id']} del panel de {EMPRESA_NOMBRE} · prioridad {task['prioridad']} · creada {task['creada_en']}",
    ]

    return {"task_id": task_id, "prompt": "\n".join(lines)}


@router.patch("/{task_id}")
def update_task(task_id: int, patch: TaskUpdate):
    fields = {k: v for k, v in patch.model_dump(exclude_unset=True).items()}
    if not fields:
        raise HTTPException(400, "nada para actualizar")
    with db_session() as conn:
        existing = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
        if not existing:
            raise HTTPException(404, "tarea no encontrada")
        existing = dict(existing)

        # Tarea recurrente marcada "hecho": en vez de cerrarla, vuelve a
        # "pendiente" con el proximo_vencimiento calculado -- el reciclado
        # nunca se pisa por un PATCH que no toca estado (ej. solo cambiar
        # titulo), solo dispara cuando estado pasa a 'hecho' explicitamente.
        if fields.get("estado") == "hecho" and existing["recurrencia"] != "ninguna":
            # Ancla en el vencimiento anterior (no en "ahora") para que la
            # cadencia no se corra si se completa unos dias tarde/temprano.
            base = (
                datetime.fromisoformat(existing["proximo_vencimiento"])
                if existing["proximo_vencimiento"]
                else datetime.now()
            )
            siguiente = _next_occurrence(base, existing["recurrencia"])
            fields["estado"] = "pendiente"
            fields["proximo_vencimiento"] = siguiente.date().isoformat()

        set_clause = ", ".join(f"{k} = ?" for k in fields) + ", actualizada_en = datetime('now')"
        conn.execute(f"UPDATE tasks SET {set_clause} WHERE id = ?", (*fields.values(), task_id))
        row = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
        return dict(row)


@router.delete("/{task_id}")
def delete_task(task_id: int):
    with db_session() as conn:
        existing = conn.execute("SELECT id FROM tasks WHERE id = ?", (task_id,)).fetchone()
        if not existing:
            raise HTTPException(404, "tarea no encontrada")
        conn.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
        return {"ok": True}
