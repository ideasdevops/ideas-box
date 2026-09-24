"""
Chat de interpretación en lenguaje natural -> crea tareas en el tablero
siguiendo la estructura ya definida (tasks). Usa OpenRouter (OPENROUTER_API_KEY).
El modelo solo puede sugerir agente_sugerido/server_objetivo del catálogo REAL --
se le pasa el catálogo completo en el system prompt, nunca inventa nombres.

NO ejecuta nada -- crea la tarea y listo, igual que crearla a mano o desde
una plantilla. La ejecucion real vive en execution.py (POST /api/tasks/{id}/ejecutar),
disparada a mano desde el tablero, no desde acá.
"""
import json
import re

from fastapi import APIRouter
from pydantic import BaseModel

from config import EMPRESA_NOMBRE, EMPRESA_RUBRO
from db import db_session
from routers.agents import scan_agents
from routers.servers import server_roster
from services.openrouter import call_openrouter

router = APIRouter(prefix="/api/chat", tags=["chat"])

_TASK_BLOCK_RE = re.compile(r"```task\s*\n(.*?)\n```", re.DOTALL)


class ChatMessage(BaseModel):
    mensaje: str


def _build_system_prompt() -> str:
    agentes = scan_agents()
    agentes_txt = "\n".join(f"- {a['nombre']} ({a['dominio']}): {a['descripcion']}" for a in agentes)
    roster = server_roster()
    servers_txt = (
        "\n".join(f"- {s['alias']}: {s['label']}" for s in roster)
        or "(todavía no hay servidores conectados)"
    )
    rubro_txt = f" Se dedica a: {EMPRESA_RUBRO}." if EMPRESA_RUBRO else ""

    return f"""Sos el asistente organizador del panel de comando de {EMPRESA_NOMBRE}.{rubro_txt} Tu única función
es entender claramente lo que el usuario pide, en lenguaje natural, y convertirlo en una
tarea del tablero cuando ya tengas lo necesario. NUNCA ejecutás la tarea vos mismo -- solo
la registrás para que un agente/humano la trabaje después.

Catálogo REAL de agentes disponibles (elegí agente_sugerido SOLO de esta lista, por su
nombre exacto):
{agentes_txt}

Roster REAL de servers (elegí server_objetivo SOLO de esta lista si la tarea toca
infraestructura, por su alias exacto, o dejalo vacío si no aplica):
{servers_txt}

Si te falta información clave para armar una tarea útil (qué canal, qué proyecto, qué
alcance), preguntá -- no inventes detalles ni asumas un agente/server al azar.

Cuando ya tengas lo suficiente, respondé con una confirmación breve en texto Y, en el
mismo mensaje, un bloque exacto con este formato (JSON válido adentro):

```task
{{"titulo": "...", "descripcion": "...", "agente_sugerido": "...", "server_objetivo": "", "prioridad": "media", "recurrencia": "ninguna", "auto_publicar": false}}
```

`prioridad` es baja/media/alta. `server_objetivo` puede quedar como string vacío si no
aplica. `recurrencia` es ninguna/diaria/semanal/mensual -- usá "mensual" para cosas como
backups periódicos u otras tareas que el usuario diga que se repiten cada mes, "ninguna"
si es un pedido puntual. `auto_publicar` es SIEMPRE false salvo que el usuario pida
EXPLÍCITAMENTE en la conversación que se publique solo al terminar -- nunca lo pongas en
true por inferencia o por defecto, es una decisión que el usuario tiene que pedir con
todas las letras. No emitas el bloque ```task``` hasta estar seguro -- una vez que lo
mandás, la tarea se crea de verdad en el tablero."""


def _valid_agent_names() -> set[str]:
    return {a["nombre"] for a in scan_agents()}


def _valid_server_aliases() -> set[str]:
    return {s["alias"] for s in server_roster()}


@router.get("/history")
def get_history():
    with db_session() as conn:
        rows = conn.execute(
            """SELECT cm.*, t.titulo AS tarea_titulo, t.agente_sugerido AS tarea_agente
               FROM chat_messages cm
               LEFT JOIN tasks t ON t.id = cm.tarea_creada_id
               ORDER BY cm.id ASC"""
        ).fetchall()
        return {"mensajes": [dict(r) for r in rows]}


@router.post("")
def send_message(msg: ChatMessage):
    with db_session() as conn:
        historial = [dict(r) for r in conn.execute("SELECT rol, texto FROM chat_messages ORDER BY id ASC").fetchall()]
        conn.execute("INSERT INTO chat_messages (rol, texto) VALUES ('usuario', ?)", (msg.mensaje,))

    messages = [{"role": "user" if m["rol"] == "usuario" else "assistant", "content": m["texto"]} for m in historial]
    messages.append({"role": "user", "content": msg.mensaje})
    raw_response = call_openrouter(_build_system_prompt(), messages)

    task_match = _TASK_BLOCK_RE.search(raw_response)
    respuesta_texto = _TASK_BLOCK_RE.sub("", raw_response).strip()
    tarea_creada = None

    if task_match:
        try:
            task_data = json.loads(task_match.group(1))
        except json.JSONDecodeError:
            task_data = None

        if task_data:
            agente = task_data.get("agente_sugerido", "")
            server = task_data.get("server_objetivo", "") or ""
            if agente and agente not in _valid_agent_names():
                agente = ""  # el modelo alucinó un nombre -- no lo forzamos, queda vacío
            if server and server not in _valid_server_aliases():
                server = ""

            recurrencia = task_data.get("recurrencia", "ninguna")
            if recurrencia not in ("ninguna", "diaria", "semanal", "mensual"):
                recurrencia = "ninguna"

            auto_publicar = 1 if task_data.get("auto_publicar") is True else 0

            with db_session() as conn:
                cursor = conn.execute(
                    """INSERT INTO tasks (titulo, descripcion, agente_sugerido, server_objetivo, prioridad, recurrencia, auto_publicar, fuente)
                       VALUES (?, ?, ?, ?, ?, ?, ?, 'chat')""",
                    (
                        task_data.get("titulo", "Tarea sin título")[:255],
                        task_data.get("descripcion", ""),
                        agente,
                        server,
                        task_data.get("prioridad", "media"),
                        recurrencia,
                        auto_publicar,
                    ),
                )
                task_id = cursor.lastrowid
                row = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
                tarea_creada = dict(row)

    with db_session() as conn:
        conn.execute(
            "INSERT INTO chat_messages (rol, texto, tarea_creada_id) VALUES ('asistente', ?, ?)",
            (respuesta_texto, tarea_creada["id"] if tarea_creada else None),
        )

    return {"respuesta": respuesta_texto, "tarea_creada": tarea_creada}
